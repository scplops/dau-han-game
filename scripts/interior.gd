class_name Interior
extends Node3D
## Bên trong nhà chính, kiểu "nhà búp bê": bỏ mái, tường trước cắt thấp để nhìn chéo
## từ trên vào cả 3 gian. Đặt ở xa (vị trí node) nên camera ngoài sân không thấy.
## Kích thước khung nhà lấy từ `house` để khớp với bên ngoài.
## Toạ độ cục bộ giống nhà bên ngoài: x dọc nhà, z = 0 ở giữa, mặt trước hướng +z.

@export var house: House
@export var random_seed: int = 1313

@export_group("Mặt cắt")
@export var front_wall_cut: float = 0.9      # tường trước chỉ giữ phần thấp
@export var column_cut: float = 1.1          # cột hiên cắt ngang
@export var wall_thickness: float = 0.15

@export_group("Đèn dầu")
@export var lamp_energy: float = 1.8
@export var lamp_range: float = 6.0

# Kích thước (lấy từ House trong build)
var _len: float = 10.0
var _dep: float = 5.6
var _ver: float = 1.6
var _h: float = 2.6
var _p: float = 0.4
var _back_z: float
var _front_z: float
var _gian: float
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	build()


func build() -> void:
	if house != null:
		_len = house.length
		_dep = house.depth
		_ver = house.veranda_depth
		_h = house.wall_height
		_p = house.plinth_height
	_back_z = -_dep * 0.5
	_front_z = _back_z + (_dep - _ver)
	_gian = _len / 3.0
	_rng.seed = random_seed

	var shell := MeshBuilder.new(random_seed, 0.035)
	shell.contact_shade_height = _p + 0.5
	shell.contact_shade_strength = 0.18
	_build_surroundings(shell)
	_build_shell(shell)
	add_child(shell.commit_instance("Shell"))

	var floor_mb := MeshBuilder.new(random_seed + 1, 0.09)
	_build_floor(floor_mb)
	var floor_node := floor_mb.commit_instance("Floor")
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_node)

	var furn := MeshBuilder.new(random_seed + 2, 0.04)
	furn.contact_shade_height = _p + 0.25
	furn.contact_shade_strength = 0.25
	_build_center_gian(furn)
	_build_left_gian(furn)
	_build_right_gian(furn)
	add_child(furn.commit_instance("Furniture"))

	var flames := MeshBuilder.new(random_seed + 3, 0.0)
	_build_lamps(flames)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.vertex_color_is_srgb = true
	add_child(flames.commit_instance("LampFlames", flame_mat))

	# Bấm vào ô cửa để ra sân
	HouseEntry.make_click_target(self, _t(0.0, _p + 0.5, _front_z), Vector3(1.6, 1.0, 0.5),
			"Ra sân  ·  bấm chuột, E hoặc Esc")


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


static func _ry(angle: float, x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, angle), Vector3(x, y, z))


## Giữa gian thứ i (0 = trái, 1 = giữa, 2 = phải).
func _gx(i: int) -> float:
	return -_len * 0.5 + _gian * (i + 0.5)


# --- Nền xung quanh + khung nhà ------------------------------------------------------

func _build_surroundings(mb: MeshBuilder) -> void:
	var s := 150.0
	mb.add_quad(Vector3(-s, 0, -s), Vector3(s, 0, -s), Vector3(s, 0, s), Vector3(-s, 0, s),
			Palette.GRASS, Vector3(0, -1, 0))
	# Một khoảnh sân gạch trước nhà
	var z0 := _dep * 0.5 + 0.45
	for row in 8:
		for col in 22:
			var x := -6.0 + col * 0.55 + (0.27 if row % 2 == 1 else 0.0)
			var z := z0 + row * 0.55
			if x + 0.5 > 6.3:
				continue
			mb.add_quad(Vector3(x, 0.02, z), Vector3(x + 0.5, 0.02, z), Vector3(x + 0.5, 0.02, z + 0.5),
					Vector3(x, 0.02, z + 0.5), Palette.YARD, Vector3(x, -1, z))


func _build_shell(mb: MeshBuilder) -> void:
	var t := wall_thickness
	var core := _dep - _ver
	var core_z := _back_z + core * 0.5
	# Nền nhà + bậc thềm
	mb.add_box(Vector3(_len + 0.9, _p, _dep + 0.9), Palette.PLINTH, Transform3D.IDENTITY)
	mb.add_box(Vector3(2.8, _p * 0.5, 0.5), Palette.PLINTH, _t(0.0, 0.0, (_dep + 0.9) * 0.5 + 0.25))

	# Tường sau + hai tường hồi (cao đủ), mặt cắt trên đỉnh sẫm màu
	var walls: Array[Array] = [
		[Vector3(_len, _h, t), Vector3(0.0, _p, _back_z + t * 0.5)],
		[Vector3(t, _h, core), Vector3(-_len * 0.5 + t * 0.5, _p, core_z)],
		[Vector3(t, _h, core), Vector3(_len * 0.5 - t * 0.5, _p, core_z)],
	]
	# Tường trước cắt thấp, chừa ô cửa ở gian giữa
	var door_w := 1.6
	var side_w := (_len - door_w) * 0.5
	walls.append([Vector3(side_w, front_wall_cut, t), Vector3(-_len * 0.5 + side_w * 0.5, _p, _front_z - t * 0.5)])
	walls.append([Vector3(side_w, front_wall_cut, t), Vector3(_len * 0.5 - side_w * 0.5, _p, _front_z - t * 0.5)])
	for w in walls:
		var size: Vector3 = w[0]
		var pos: Vector3 = w[1]
		mb.add_box(size, Palette.WALL, Transform3D(Basis(), pos))
		mb.add_box(Vector3(size.x + 0.01, 0.03, size.z + 0.01), Palette.WALL_DARK,
				Transform3D(Basis(), pos + Vector3(0, size.y, 0)))
	# Chân tường phía trong
	mb.add_box(Vector3(_len - t * 2.0, 0.22, 0.03), Palette.WALL_DARK, _t(0.0, _p, _back_z + t + 0.015))
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.03, 0.22, core - t), Palette.WALL_DARK, _t(s * (_len * 0.5 - t - 0.015), _p, core_z))
	# Khung cửa (cắt) + bậu cửa
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.12, front_wall_cut + 0.15, t + 0.06), Palette.WOOD, _t(s * (door_w * 0.5 + 0.06), _p, _front_z - t * 0.5))
	mb.add_box(Vector3(door_w, 0.08, t + 0.06), Palette.WOOD, _t(0.0, _p, _front_z - t * 0.5))
	# Bậu cửa sổ (phần tường cắt ngang đúng chỗ cửa sổ)
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(1.3, 0.06, t + 0.1), Palette.WOOD, _t(s * _len / 3.0, _p + front_wall_cut, _front_z - t * 0.5))

	# Cột hiên (cắt ngang) và cột trong nhà ở ranh giới các gian
	var col_z := _dep * 0.5 - 0.25
	for i in 4:
		var x := lerpf(-_len * 0.5 + 0.3, _len * 0.5 - 0.3, i / 3.0)
		mb.add_box(Vector3(0.36, 0.14, 0.36), Palette.PLINTH, _t(x, _p, col_z))
		mb.add_prism(0.12, 0.115, column_cut, 6, Palette.WOOD, _t(x, _p + 0.14, col_z))
	for s in [-1.0, 1.0]:
		var x: float = s * _gian * 0.5
		for z in [_back_z + 0.35, _front_z - 0.3]:
			mb.add_prism(0.12, 0.11, _h, 6, Palette.WOOD, _t(x, _p, z))
		# Xà ngang nối cột trước – sau
		mb.add_box(Vector3(0.16, 0.2, core - 0.4), Palette.WOOD, _t(x, _p + _h - 0.2, core_z))
	# Xà dọc trên tường sau
	mb.add_box(Vector3(_len - 0.3, 0.18, 0.18), Palette.WOOD, _t(0.0, _p + _h - 0.18, _back_z + 0.3))

	# Vách gỗ lửng ngăn gian trái (buồng ngủ), chừa lối đi phía trước
	var vx := -_gian * 0.5
	var vz0 := _back_z + 0.45
	var vz1 := _front_z - 1.3
	mb.add_box(Vector3(0.08, 1.9, vz1 - vz0), Palette.WOOD_LIGHT, _t(vx, _p, (vz0 + vz1) * 0.5))
	var z := vz0 + 0.3
	while z < vz1 - 0.1:
		mb.add_box(Vector3(0.1, 1.9, 0.05), Palette.WOOD, _t(vx, _p, z))
		z += 0.45
	mb.add_box(Vector3(0.12, 0.08, vz1 - vz0), Palette.WOOD, _t(vx, _p + 1.9, (vz0 + vz1) * 0.5))


func _build_floor(mb: MeshBuilder) -> void:
	# Gạch đỏ vuông lát trong nhà
	var t := wall_thickness
	var x0 := -_len * 0.5 + t
	var x1 := _len * 0.5 - t
	var z0 := _back_z + t
	var z1 := _front_z - t
	var ts := 0.42
	var g := 0.02
	var y := _p + 0.005
	mb.add_quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1),
			Palette.GROUT, Vector3(0, -1, 0))
	var z := z0
	while z < z1 - 0.01:
		var ze := minf(z + ts, z1)
		var x := x0
		while x < x1 - 0.01:
			var xe := minf(x + ts, x1)
			mb.add_quad(Vector3(x + g, y + 0.01, z + g), Vector3(xe - g, y + 0.01, z + g),
					Vector3(xe - g, y + 0.01, ze - g), Vector3(x + g, y + 0.01, ze - g), Palette.FLOOR,
					Vector3(x, -1, z))
			x = xe
		z = ze


# --- Gian giữa: bàn thờ, hoành phi câu đối, bàn trà ------------------------------------

func _build_center_gian(mb: MeshBuilder) -> void:
	var p := _p
	var wall_z := _back_z + wall_thickness
	# Án thư (bàn thờ dưới): mặt bàn, chân, diềm thếp vàng
	var az := wall_z + 0.5
	_table(mb, Vector3(2.1, 0.92, 0.72), Vector3(0.0, p, az), Palette.ALTAR_RED, 0.07)
	mb.add_box(Vector3(1.9, 0.14, 0.03), Palette.GOLD, _t(0.0, p + 0.72, az + 0.36))
	# Sập thờ tầng trên (cao, sát tường)
	var tz := wall_z + 0.22
	mb.add_box(Vector3(1.5, 0.42, 0.42), Palette.ALTAR_RED, _t(0.0, p + 0.92, tz))
	mb.add_box(Vector3(1.4, 0.05, 0.02), Palette.GOLD, _t(0.0, p + 1.18, tz + 0.21))
	var top := p + 1.34
	# Bát hương, nhang, đôi chân nến, lọ hoa
	mb.add_prism(0.11, 0.13, 0.12, 8, Palette.CERAMIC, _t(0.0, top, tz))
	for i in 3:
		var x := (i - 1) * 0.035
		mb.add_prism(0.008, 0.008, 0.28, 3, Palette.ALTAR_RED, _t(x, top + 0.1, tz))
	for s in [-1.0, 1.0]:
		mb.add_prism(0.06, 0.03, 0.04, 6, Palette.GOLD, _t(s * 0.42, top, tz))
		mb.add_prism(0.02, 0.02, 0.32, 6, Palette.GOLD, _t(s * 0.42, top + 0.04, tz))
		mb.add_prism(0.03, 0.025, 0.08, 6, Palette.PILLOW, _t(s * 0.42, top + 0.36, tz))
		mb.add_prism(0.05, 0.08, 0.22, 7, Palette.CERAMIC, _t(s * 0.65, top, tz))
		mb.add_blob(Vector3(0.1, 0.08, 0.1), Palette.FLOWER_YELLOW, _rng, 0.2, _t(s * 0.65, top + 0.22, tz))
	# Mâm ngũ quả trên án thư
	var fz := az + 0.05
	mb.add_prism(0.24, 0.2, 0.03, 10, Palette.GOLD, _t(0.0, p + 0.92, fz))
	var fruits: Array[Color] = [Palette.FLOWER_YELLOW, Palette.LILY, Palette.ROOF, Palette.BEAK, Palette.BANYAN_LEAF_2]
	for i in fruits.size():
		var a := TAU * i / fruits.size()
		mb.add_blob(Vector3(0.07, 0.065, 0.07), fruits[i], _rng, 0.12,
				_t(cos(a) * 0.11, p + 0.95, fz + sin(a) * 0.08))
	mb.add_blob(Vector3(0.07, 0.07, 0.07), Palette.BAMBOO_LEAF, _rng, 0.12, _t(0.0, p + 1.0, fz))
	# Hoành phi + câu đối trên tường sau
	mb.add_box(Vector3(2.0, 0.46, 0.06), Palette.ALTAR_RED, _t(0.0, p + 2.0, wall_z + 0.03))
	mb.add_box(Vector3(1.75, 0.26, 0.02), Palette.GOLD, _t(0.0, p + 2.1, wall_z + 0.07))
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.26, 1.45, 0.05), Palette.ALTAR_RED, _t(s * 1.3, p + 0.9, wall_z + 0.03))
		mb.add_box(Vector3(0.1, 1.25, 0.02), Palette.GOLD, _t(s * 1.3, p + 1.0, wall_z + 0.06))

	# Bàn trà + hai ghế + chiếu
	var cz := _front_z - 1.35
	for i in 6:
		var col := Palette.MAT if i % 2 == 0 else Palette.MAT.darkened(0.08)
		mb.add_box(Vector3(2.0, 0.015, 0.25), col, _t(0.0, p + 0.01, cz - 0.75 + i * 0.25))
	_table(mb, Vector3(1.05, 0.55, 0.7), Vector3(0.0, p, cz), Palette.WOOD, 0.05)
	for s in [-1.0, 1.0]:
		_chair(mb, Vector3(s * 0.85, p, cz), s * -PI * 0.5)
	# Khay, ấm, chén
	var ty := p + 0.55
	mb.add_box(Vector3(0.45, 0.025, 0.3), Palette.WOOD_LIGHT, _t(0.12, ty, cz))
	mb.add_prism(0.08, 0.06, 0.1, 8, Palette.CERAMIC, _t(0.02, ty + 0.025, cz))
	mb.add_prism(0.03, 0.03, 0.02, 6, Palette.CERAMIC, _t(0.02, ty + 0.125, cz))
	mb.add_prism(0.012, 0.008, 0.1, 4, Palette.CERAMIC,
			Transform3D(Basis(Vector3.BACK, -1.0), Vector3(0.09, ty + 0.06, cz)))
	for i in 4:
		mb.add_prism(0.028, 0.035, 0.04, 6, Palette.CERAMIC, _t(0.2 + (i % 2) * 0.09, ty + 0.025, cz - 0.05 + float(i >> 1) * 0.1))


## Bàn đơn giản: mặt + 4 chân. `size` là (rộng, cao, sâu).
func _table(mb: MeshBuilder, size: Vector3, pos: Vector3, color: Color, leg: float) -> void:
	mb.add_box(Vector3(size.x, 0.06, size.z), color, _t(pos.x, pos.y + size.y - 0.06, pos.z))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(leg, size.y - 0.06, leg), color,
					_t(pos.x + sx * (size.x * 0.5 - leg), pos.y, pos.z + sz * (size.z * 0.5 - leg)))


## Ghế gỗ có tựa, quay theo `angle` (tựa nằm phía sau).
func _chair(mb: MeshBuilder, pos: Vector3, angle: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, angle), pos)
	mb.add_box(Vector3(0.45, 0.05, 0.42), Palette.WOOD, xf * _t(0.0, 0.42, 0.0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(0.05, 0.42, 0.05), Palette.WOOD, xf * _t(sx * 0.19, 0.0, sz * 0.18))
	mb.add_box(Vector3(0.45, 0.5, 0.05), Palette.WOOD, xf * _t(0.0, 0.47, -0.19))


# --- Gian trái: giường, màn, tủ --------------------------------------------------------

func _build_left_gian(mb: MeshBuilder) -> void:
	var p := _p
	var x := _gx(0) - 0.25
	var bz := _back_z + wall_thickness + 1.15
	# Giường gỗ: khung, chiếu, gối, chăn gấp
	_table(mb, Vector3(1.6, 0.45, 2.1), Vector3(x, p, bz), Palette.WOOD, 0.08)
	mb.add_box(Vector3(1.5, 0.03, 2.0), Palette.MAT, _t(x, p + 0.45, bz))
	mb.add_box(Vector3(0.5, 0.1, 0.3), Palette.PILLOW, _t(x - 0.35, p + 0.48, bz - 0.8))
	mb.add_box(Vector3(0.5, 0.1, 0.3), Palette.PILLOW, _t(x + 0.35, p + 0.48, bz - 0.8))
	mb.add_box(Vector3(0.9, 0.14, 0.45), Palette.BLANKET, _t(x, p + 0.48, bz + 0.65))
	# Cọc màn + màn cuộn
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(0.04, 1.5, 0.04), Palette.WOOD_LIGHT, _t(x + sx * 0.76, p + 0.45, bz + sz * 1.01))
	for sz in [-1.0, 1.0]:
		mb.add_box(Vector3(1.56, 0.03, 0.03), Palette.WOOD_LIGHT, _t(x, p + 1.95, bz + sz * 1.01))
	mb.add_prism(0.06, 0.06, 1.5, 6, Palette.PILLOW,
			Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + 0.75, p + 1.98, bz - 1.01)))
	# Tủ quần áo sát tường hồi, hai cánh có nẹp
	var wx := -_len * 0.5 + wall_thickness + 0.32
	var wz := _front_z - 0.95
	mb.add_box(Vector3(0.6, 1.75, 1.0), Palette.WOOD, _t(wx, p, wz))
	for sz in [-1.0, 1.0]:
		mb.add_box(Vector3(0.03, 1.5, 0.44), Palette.WOOD_LIGHT, _t(wx + 0.31, p + 0.12, wz + sz * 0.24))
		mb.add_box(Vector3(0.04, 0.12, 0.03), Palette.GOLD, _t(wx + 0.33, p + 0.9, wz + sz * 0.05))


# --- Gian phải: chạn bát, chum gạo, nong nia, quang gánh -------------------------------

func _build_right_gian(mb: MeshBuilder) -> void:
	var p := _p
	var wall_z := _back_z + wall_thickness
	# Chạn bát: hai thành, 3 tầng, bát đĩa
	var cx := _gx(2) - 0.2
	var cz := wall_z + 0.25
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.05, 1.5, 0.45), Palette.WOOD, _t(cx + s * 0.6, p, cz))
	for i in 4:
		var y := p + 0.05 + i * 0.45
		mb.add_box(Vector3(1.25, 0.04, 0.45), Palette.WOOD, _t(cx, y, cz))
		if i < 3:
			for k in 4:
				var bx := cx - 0.42 + k * 0.28
				mb.add_prism(0.07, 0.1, 0.06, 7, Palette.CERAMIC, _t(bx, y + 0.04, cz))
				mb.add_prism(0.065, 0.09, 0.05, 7, Palette.CERAMIC, _t(bx, y + 0.1, cz))
	mb.add_box(Vector3(1.25, 1.5, 0.03), Palette.WOOD_LIGHT, _t(cx, p, cz - 0.21))
	# Chum gạo có nắp + bao gạo
	var jx := _len * 0.5 - wall_thickness - 0.45
	var jz := wall_z + 1.35
	mb.add_prism(0.24, 0.38, 0.38, 9, Palette.JAR, _t(jx, p, jz))
	mb.add_prism(0.38, 0.22, 0.36, 9, Palette.JAR, _t(jx, p + 0.38, jz))
	mb.add_prism(0.27, 0.22, 0.06, 9, Palette.WOOD, _t(jx, p + 0.74, jz))
	for i in 2:
		mb.add_blob(Vector3(0.26, 0.24, 0.2), Palette.SACK, _rng, 0.15, _t(jx - 0.15 - i * 0.48, p, jz + 0.55))
	# Nong, nia dựng nghiêng vào tường hồi
	var nx := _len * 0.5 - wall_thickness - 0.06
	for i in 3:
		var r := 0.5 - i * 0.08
		var xf := Transform3D(Basis(Vector3.BACK, PI * 0.5 - 0.15), Vector3(nx - i * 0.05, p + r + 0.02, _front_z - 1.1 + i * 0.25))
		mb.add_prism(r, r, 0.03, 12, Palette.STRAW if i != 1 else Palette.STRAW.darkened(0.12), xf)
	# Quang gánh: đòn gánh + hai thúng
	var qx := _gx(2) + 0.1
	var qz := _front_z - 0.65
	for s in [-1.0, 1.0]:
		mb.add_prism(0.2, 0.26, 0.3, 10, Palette.STRAW.darkened(0.1), _t(qx + s * 0.6, p, qz))
		mb.add_box(Vector3(0.015, 0.55, 0.015), Palette.WOOD, _t(qx + s * 0.6, p + 0.3, qz))
	mb.add_prism(0.025, 0.025, 1.5, 6, Palette.BAMBOO_STEM,
			Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(qx + 0.75, p + 0.85, qz)))


# --- Đèn dầu ---------------------------------------------------------------------------

func _build_lamps(flames: MeshBuilder) -> void:
	var p := _p
	var spots: Array[Vector3] = [
		Vector3(-0.3, p + 0.55, _front_z - 1.35),                      # trên bàn trà
		Vector3(_gx(0) + 0.75, p + 1.2, _front_z - 0.7),               # treo cạnh giường
	]
	var mb := MeshBuilder.new(random_seed + 4, 0.0)
	for i in spots.size():
		var s := spots[i]
		if i == 1:
			mb.add_box(Vector3(0.04, 0.6, 0.04), Palette.WOOD, _t(s.x, s.y - 0.6, s.z))   # cọc treo
		mb.add_prism(0.07, 0.05, 0.06, 8, Palette.CERAMIC, _t(s.x, s.y, s.z))
		mb.add_prism(0.04, 0.035, 0.16, 8, Palette.CERAMIC.lerp(Palette.WATER_LIGHT, 0.4), _t(s.x, s.y + 0.06, s.z))
		flames.add_pyramid(0.02, 0.06, 5, Palette.WINDOW_GLOW, _t(s.x, s.y + 0.1, s.z))
		var light := OmniLight3D.new()
		light.name = "OilLamp%d" % i
		light.position = s + Vector3(0, 0.25, 0)
		light.light_color = Palette.WINDOW_GLOW
		light.omni_range = lamp_range
		light.light_energy = 0.0
		light.set_meta("max_energy", lamp_energy)
		light.add_to_group("night_light")
		add_child(light)
	add_child(mb.commit_instance("Lamps"))
