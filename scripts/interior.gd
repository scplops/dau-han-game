class_name Interior
extends Node3D
## Bên trong một toà nhà, kiểu "nhà búp bê": bỏ mái, tường trước cắt thấp để nhìn chéo
## từ trên vào. Đặt ở xa (vị trí node) nên camera ngoài sân không thấy.
## Nội thất dựng theo `spec` khi bước vào (`load_spec`) và xoá khi vào toà khác:
##   kind "home"   — nhà ở: số gian, kích thước, tường, mặt tiền giống bên ngoài; gian giữa
##                   là bàn thờ + bàn trà, các gian bên chọn từ ROOM_TYPES theo seed.
##   kind "dinh"   — đình làng: hậu cung, ngai thờ, hạc chầu, trống, chiêng, kiệu, bát bửu.
##   kind "pagoda" — chùa: Phật điện nhiều cấp, tượng, chuông, mõ, hộ pháp, bồ đoàn.
## Toạ độ cục bộ: x dọc nhà, z = 0 ở giữa, mặt trước hướng +z.

const ROOM_TYPES: Array[String] = ["bedroom", "plank", "storage", "loom", "mill", "study"]

@export var house: House
@export var random_seed: int = 1313

@export_group("Mặt cắt")
@export var front_wall_cut: float = 0.9      # tường trước chỉ giữ phần thấp
@export var column_cut: float = 1.1          # cột hiên cắt ngang
@export var wall_thickness: float = 0.15

@export_group("Đèn")
@export var lamp_energy: float = 1.8
@export var lamp_range: float = 6.0

## Thông số toà nhà đang hiện (xem đầu file).
var spec: Dictionary = {}

# Kích thước của toà đang dựng
var _len: float = 10.0
var _dep: float = 5.6
var _ver: float = 1.6
var _h: float = 2.6
var _p: float = 0.4
var _bays: int = 3
var _gian: float
var _back_z: float
var _front_z: float
var _door_x: float = 0.0
var _wall := "lime_yellow"
var _front := "veranda_wood"
var _poor: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if spec.is_empty() and house != null:
		load_spec(home_spec_from(house))


## Thông số nhà chính (cạnh ruộng) — giữ bày trí cố định như trước.
static func home_spec_from(h: House) -> Dictionary:
	return {
		"kind": "home", "name": "Nhà mình", "bays": 3, "bay": h.length / 3.0,
		"depth": h.depth, "veranda": h.veranda_depth, "height": h.wall_height,
		"plinth": h.plinth_height, "wall": "lime_yellow", "front": "veranda_wood",
		"roof": "tile_red", "seed": 1313, "rooms": ["bedroom", "altar", "storage"],
	}


## Xoá nội thất cũ, dựng theo `s`.
func load_spec(s: Dictionary) -> void:
	spec = s
	for c in get_children():
		remove_child(c)
		c.queue_free()
	build()


## Khoảng cách camera phù hợp với kích thước toà nhà.
func camera_distance() -> float:
	return clampf(maxf(_len, _dep * 1.6) * 1.05, 9.0, 30.0)


func build() -> void:
	var kind: String = spec.get("kind", "home")
	_rng.seed = int(spec.get("seed", random_seed))
	_bays = int(spec.get("bays", 3))
	_gian = float(spec.get("bay", 3.33))
	_len = float(spec.get("length", _bays * _gian))
	_dep = float(spec.get("depth", 5.6))
	_ver = float(spec.get("veranda", 1.6))
	_h = float(spec.get("height", 2.6))
	_p = float(spec.get("plinth", 0.4))
	_wall = spec.get("wall", "lime_yellow")
	_front = spec.get("front", "veranda_wood")
	_poor = spec.get("roof", "") == "thatch" or _wall == "mud"
	_back_z = -_dep * 0.5
	_front_z = _back_z + (_dep - _ver)
	_door_x = 0.0
	if kind == "home":
		_door_x = -_len * 0.5 + _gian * ((_bays >> 1) + 0.5)

	var shell := MeshBuilder.new(_rng.seed, 0.035)
	shell.contact_shade_height = _p + 0.5
	shell.contact_shade_strength = 0.18
	_build_surroundings(shell)
	var floor_mb := MeshBuilder.new(_rng.seed + 1, 0.09)
	var furn := MeshBuilder.new(_rng.seed + 2, 0.04)
	furn.contact_shade_height = _p + 0.25
	furn.contact_shade_strength = 0.25
	var flames := MeshBuilder.new(_rng.seed + 3, 0.0)
	var lamps: Array[Vector3] = []

	match kind:
		"dinh":
			_build_dinh(shell, floor_mb, furn, flames, lamps)
		"pagoda":
			_build_pagoda(shell, floor_mb, furn, flames, lamps)
		_:
			_build_home(shell, floor_mb, furn, flames, lamps)

	add_child(shell.commit_instance("Shell"))
	var floor_node := floor_mb.commit_instance("Floor")
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_node)
	add_child(furn.commit_instance("Furniture"))
	if flames.triangle_count() > 0:
		var flame_mat := StandardMaterial3D.new()
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.vertex_color_use_as_albedo = true
		flame_mat.vertex_color_is_srgb = true
		add_child(flames.commit_instance("Flames", flame_mat))
	for i in lamps.size():
		var light := OmniLight3D.new()
		light.name = "Lamp%d" % i
		light.position = lamps[i]
		light.light_color = Palette.WINDOW_GLOW
		light.omni_range = lamp_range * (1.6 if kind != "home" else 1.0)
		light.light_energy = 0.0
		light.set_meta("max_energy", lamp_energy)
		light.add_to_group("night_light")
		add_child(light)

	# Bấm vào ô cửa / bậc thềm để ra sân
	var exit_z := _front_z if _ver > 0.0 or kind == "home" else _dep * 0.5
	HouseEntry.make_click_target(self, _t(_door_x, _p + 0.5, exit_z), Vector3(1.6, 1.0, 0.5),
			"Ra sân  ·  bấm chuột, E hoặc Esc")


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## Giữa gian thứ i (0 = trái).
func _gx(i: int) -> float:
	return -_len * 0.5 + _gian * (i + 0.5)


# --- Nền xung quanh + khung nhà ------------------------------------------------------

func _build_surroundings(mb: MeshBuilder) -> void:
	var s := 150.0
	mb.add_quad(Vector3(-s, 0, -s), Vector3(s, 0, -s), Vector3(s, 0, s), Vector3(-s, 0, s),
			Palette.GRASS, Vector3(0, -1, 0))
	# Một khoảnh sân gạch trước nhà
	var z0 := _dep * 0.5 + 0.45
	var half := _len * 0.5 + 1.0
	for row in 8:
		var x := -half + (0.27 if row % 2 == 1 else 0.0)
		var z := z0 + row * 0.55
		while x + 0.5 < half:
			mb.add_quad(Vector3(x, 0.02, z), Vector3(x + 0.5, 0.02, z), Vector3(x + 0.5, 0.02, z + 0.5),
					Vector3(x, 0.02, z + 0.5), Palette.YARD, Vector3(x, -1, z))
			x += 0.55


## Nền nhà, tường sau + hồi đủ cao, tường trước cắt thấp chừa cửa ở `_door_x`.
func _build_shell(mb: MeshBuilder, wall_col: Color, wall_dk: Color, door_w: float) -> void:
	var t := wall_thickness
	var core := _dep - _ver
	var core_z := _back_z + core * 0.5
	mb.add_box(Vector3(_len + 0.9, _p, _dep + 0.9), Palette.PLINTH, Transform3D.IDENTITY)
	mb.add_box(Vector3(minf(2.8, _len * 0.5), _p * 0.5, 0.5), Palette.PLINTH,
			_t(_door_x, 0.0, (_dep + 0.9) * 0.5 + 0.25))
	var walls: Array[Array] = [
		[Vector3(_len, _h, t), Vector3(0.0, _p, _back_z + t * 0.5)],
		[Vector3(t, _h, core), Vector3(-_len * 0.5 + t * 0.5, _p, core_z)],
		[Vector3(t, _h, core), Vector3(_len * 0.5 - t * 0.5, _p, core_z)],
	]
	var left_w := (_door_x - door_w * 0.5) + _len * 0.5
	var right_w := _len * 0.5 - (_door_x + door_w * 0.5)
	var front_col := wall_col if _front != "panel_doors" else Palette.WOOD_LIGHT
	if left_w > 0.05:
		walls.append([Vector3(left_w, front_wall_cut, t), Vector3(-_len * 0.5 + left_w * 0.5, _p, _front_z - t * 0.5), front_col])
	if right_w > 0.05:
		walls.append([Vector3(right_w, front_wall_cut, t), Vector3(_len * 0.5 - right_w * 0.5, _p, _front_z - t * 0.5), front_col])
	for w in walls:
		var size: Vector3 = w[0]
		var pos: Vector3 = w[1]
		var col: Color = w[2] if w.size() > 2 else wall_col
		mb.add_box(size, col, Transform3D(Basis(), pos))
		mb.add_box(Vector3(size.x + 0.01, 0.03, size.z + 0.01), wall_dk,
				Transform3D(Basis(), pos + Vector3(0, size.y, 0)))
	if _wall == "brick":
		for y in [0.45, 0.87, 1.29, 1.71, 2.13]:
			if y < _h - 0.1:
				mb.add_box(Vector3(_len - t * 2.0, 0.03, 0.02), wall_dk, _t(0.0, _p + y, _back_z + t + 0.01))
	# Chân tường phía trong
	mb.add_box(Vector3(_len - t * 2.0, 0.22, 0.03), wall_dk, _t(0.0, _p, _back_z + t + 0.015))
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.03, 0.22, core - t), wall_dk, _t(s * (_len * 0.5 - t - 0.015), _p, core_z))
	# Khung cửa + bậu cửa
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.12, front_wall_cut + 0.15, t + 0.06), Palette.WOOD, _t(_door_x + s * (door_w * 0.5 + 0.06), _p, _front_z - t * 0.5))
	mb.add_box(Vector3(door_w, 0.08, t + 0.06), Palette.WOOD, _t(_door_x, _p, _front_z - t * 0.5))


## Cột hiên (cắt ngang).
func _build_veranda(mb: MeshBuilder, n: int, color: Color, square: bool) -> void:
	if _ver <= 0.0:
		return
	var col_z := _dep * 0.5 - 0.25
	for i in n:
		var x := lerpf(-_len * 0.5 + 0.3, _len * 0.5 - 0.3, float(i) / (n - 1))
		mb.add_box(Vector3(0.36, 0.14, 0.36), Palette.PLINTH, _t(x, _p, col_z))
		if square:
			mb.add_box(Vector3(0.32, column_cut, 0.32), color, _t(x, _p + 0.14, col_z))
		else:
			mb.add_prism(0.12, 0.115, column_cut, 6, color, _t(x, _p + 0.14, col_z))


func _build_floor(mb: MeshBuilder, color: Color, tile: float) -> void:
	var t := wall_thickness
	var x0 := -_len * 0.5 + t
	var x1 := _len * 0.5 - t
	var z0 := _back_z + t
	var z1 := _front_z - (t if _ver > 0.0 or _front != "open" else 0.0)
	if _front == "open":
		z1 = _dep * 0.5 - 0.2
	var g := 0.02 if tile > 0.0 else 0.0
	var y := _p + 0.005
	mb.add_quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1),
			Palette.GROUT if tile > 0.0 else color, Vector3(0, -1, 0))
	if tile <= 0.0:
		return
	var z := z0
	while z < z1 - 0.01:
		var ze := minf(z + tile, z1)
		var x := x0
		while x < x1 - 0.01:
			var xe := minf(x + tile, x1)
			mb.add_quad(Vector3(x + g, y + 0.01, z + g), Vector3(xe - g, y + 0.01, z + g),
					Vector3(xe - g, y + 0.01, ze - g), Vector3(x + g, y + 0.01, ze - g), color,
					Vector3(x, -1, z))
			x = xe
		z = ze


# --- Nhà ở ----------------------------------------------------------------------------

func _build_home(shell: MeshBuilder, floor_mb: MeshBuilder, furn: MeshBuilder, flames: MeshBuilder,
		lamps: Array[Vector3]) -> void:
	var wc := VillageHouse.wall_color(_wall)
	var wd := VillageHouse.wall_dark(_wall)
	_build_shell(shell, wc, wd, 1.6 if _front != "panel_doors" else _gian - 0.3)
	match _front:
		"veranda_brick":
			_build_veranda(shell, _bays + 1, wc if _wall != "lime_yellow" else Palette.WALL_WHITE, true)
		"veranda_wood":
			_build_veranda(shell, _bays + 1, Palette.WOOD, false)
	if _front == "panel_doors":
		# Hàng cánh cửa bức bàn (cắt thấp) giữa các cột
		for i in _bays + 1:
			shell.add_box(Vector3(0.2, front_wall_cut + 0.25, 0.2), Palette.WOOD, _t(-_len * 0.5 + _gian * i, _p, _front_z - 0.1))
	else:
		# Bậu cửa sổ ở các gian bên
		var mid := _bays >> 1
		for i in _bays:
			if i != mid:
				shell.add_box(Vector3(1.2, 0.06, wall_thickness + 0.1), Palette.WOOD, _t(_gx(i), _p + front_wall_cut, _front_z - wall_thickness * 0.5))
	# Cột trong nhà ở ranh giới các gian + xà
	var core := _dep - _ver
	for i in range(1, _bays):
		var x := -_len * 0.5 + _gian * i
		for z in [_back_z + 0.35, _front_z - 0.3]:
			shell.add_prism(0.12, 0.11, _h, 6, Palette.WOOD, _t(x, _p, z))
		shell.add_box(Vector3(0.16, 0.2, core - 0.4), Palette.WOOD, _t(x, _p + _h - 0.2, _back_z + core * 0.5))
	shell.add_box(Vector3(_len - 0.3, 0.18, 0.18), Palette.WOOD, _t(0.0, _p + _h - 0.18, _back_z + 0.3))

	if _poor:
		_build_floor(floor_mb, Palette.EARTH.darkened(0.08), 0.0)
	else:
		_build_floor(floor_mb, Palette.FLOOR, 0.42)

	var rooms := _pick_rooms()
	var mid := _bays >> 1
	for i in _bays:
		var x0 := -_len * 0.5 + _gian * i
		var x1 := x0 + _gian
		var outer := -1.0 if i < mid else 1.0      # phía tường hồi
		match rooms[i]:
			"altar": _room_altar(furn, flames, lamps, x0, x1)
			"bedroom": _room_bedroom(shell, furn, flames, lamps, x0, x1, outer)
			"plank": _room_plank(furn, x0, x1, outer)
			"storage": _room_storage(furn, x0, x1, outer)
			"loom": _room_loom(furn, x0, x1)
			"mill": _room_mill(furn, x0, x1)
			"study": _room_study(furn, flames, lamps, x0, x1)


## Gian giữa là bàn thờ; các gian bên: có ít nhất một chỗ ngủ, còn lại chọn theo seed.
func _pick_rooms() -> Array[String]:
	var rooms: Array[String] = []
	if spec.has("rooms"):
		for r in spec.rooms:
			rooms.append(str(r))
		return rooms
	var pool: Array[String] = []
	pool.assign(["storage", "loom", "mill", "plank"] if _poor else ["storage", "loom", "mill", "study", "plank", "bedroom"])
	var mid := _bays >> 1
	var slept := false
	for i in _bays:
		if i == mid:
			rooms.append("altar")
		elif not slept:
			rooms.append("plank" if _poor else "bedroom")
			slept = true
		else:
			var pick := pool[_rng.randi_range(0, pool.size() - 1)]
			pool.erase(pick)
			if pool.is_empty():
				pool.assign(["storage", "loom"])
			rooms.append(pick)
	return rooms


func _room_altar(mb: MeshBuilder, flames: MeshBuilder, lamps: Array[Vector3], x0: float, x1: float) -> void:
	var p := _p
	var cx := (x0 + x1) * 0.5
	var bw := minf(2.1, _gian - 0.6)
	var wall_z := _back_z + wall_thickness
	# Án thư + sập thờ
	var az := wall_z + 0.5
	_table(mb, Vector3(bw, 0.92, 0.72), Vector3(cx, p, az), Palette.ALTAR_RED if not _poor else Palette.WOOD, 0.07)
	mb.add_box(Vector3(bw - 0.2, 0.14, 0.03), Palette.GOLD if not _poor else Palette.WOOD_LIGHT, _t(cx, p + 0.72, az + 0.36))
	var tz := wall_z + 0.22
	mb.add_box(Vector3(bw * 0.72, 0.42, 0.42), Palette.ALTAR_RED if not _poor else Palette.WOOD, _t(cx, p + 0.92, tz))
	var top := p + 1.34
	mb.add_prism(0.11, 0.13, 0.12, 8, Palette.CERAMIC, _t(cx, top, tz))
	for i in 3:
		mb.add_prism(0.008, 0.008, 0.28, 3, Palette.ALTAR_RED, _t(cx + (i - 1) * 0.035, top + 0.1, tz))
	for s in [-1.0, 1.0]:
		mb.add_prism(0.02, 0.02, 0.32, 6, Palette.GOLD, _t(cx + s * bw * 0.2, top, tz))
		mb.add_prism(0.05, 0.08, 0.22, 7, Palette.CERAMIC, _t(cx + s * bw * 0.31, top, tz))
		mb.add_blob(Vector3(0.1, 0.08, 0.1), Palette.FLOWER_YELLOW, _rng, 0.2, _t(cx + s * bw * 0.31, top + 0.22, tz))
	# Mâm quả
	mb.add_prism(0.24, 0.2, 0.03, 10, Palette.GOLD, _t(cx, p + 0.92, az + 0.05))
	var fruits: Array[Color] = [Palette.FLOWER_YELLOW, Palette.LILY, Palette.ROOF, Palette.BEAK, Palette.BANYAN_LEAF_2]
	for i in fruits.size():
		var a := TAU * i / fruits.size()
		mb.add_blob(Vector3(0.07, 0.065, 0.07), fruits[i], _rng, 0.12, _t(cx + cos(a) * 0.11, p + 0.95, az + 0.05 + sin(a) * 0.08))
	# Hoành phi, câu đối (nhà khá giả)
	if not _poor:
		mb.add_box(Vector3(bw - 0.1, 0.46, 0.06), Palette.ALTAR_RED, _t(cx, p + 2.0, wall_z + 0.03))
		mb.add_box(Vector3(bw - 0.35, 0.26, 0.02), Palette.GOLD, _t(cx, p + 2.1, wall_z + 0.07))
		for s in [-1.0, 1.0]:
			if bw * 0.5 + 0.35 < _gian * 0.5:
				mb.add_box(Vector3(0.24, 1.4, 0.05), Palette.ALTAR_RED, _t(cx + s * (bw * 0.5 + 0.2), p + 0.9, wall_z + 0.03))
				mb.add_box(Vector3(0.09, 1.2, 0.02), Palette.GOLD, _t(cx + s * (bw * 0.5 + 0.2), p + 1.0, wall_z + 0.06))
	# Bàn trà + ghế (nhà tranh: phản thấp có khay)
	var cz := minf(_front_z - 1.25, az + 1.7)
	for i in 6:
		var col := Palette.MAT if i % 2 == 0 else Palette.MAT.darkened(0.08)
		mb.add_box(Vector3(minf(2.0, _gian - 0.4), 0.015, 0.25), col, _t(cx, p + 0.01, cz - 0.75 + i * 0.25))
	if _poor:
		_table(mb, Vector3(1.4, 0.38, 0.9), Vector3(cx, p, cz), Palette.WOOD_LIGHT, 0.07)
	else:
		_table(mb, Vector3(1.05, 0.55, 0.7), Vector3(cx, p, cz), Palette.WOOD, 0.05)
		for s in [-1.0, 1.0]:
			_chair(mb, Vector3(cx + s * 0.85, p, cz), s * -PI * 0.5)
	var ty := p + (0.38 if _poor else 0.55)
	mb.add_box(Vector3(0.45, 0.025, 0.3), Palette.WOOD_LIGHT, _t(cx + 0.12, ty, cz))
	mb.add_prism(0.08, 0.06, 0.1, 8, Palette.CERAMIC, _t(cx + 0.02, ty + 0.025, cz))
	mb.add_prism(0.012, 0.008, 0.1, 4, Palette.CERAMIC,
			Transform3D(Basis(Vector3.BACK, -1.0), Vector3(cx + 0.09, ty + 0.06, cz)))
	for i in 4:
		mb.add_prism(0.028, 0.035, 0.04, 6, Palette.CERAMIC, _t(cx + 0.2 + (i % 2) * 0.09, ty + 0.025, cz - 0.05 + float(i >> 1) * 0.1))
	_lamp(mb, flames, lamps, Vector3(cx - 0.3, ty, cz))


## Đèn dầu: thân gốm, bóng thuỷ tinh, ngọn lửa phát sáng + điểm đặt đèn.
func _lamp(mb: MeshBuilder, flames: MeshBuilder, lamps: Array[Vector3], s: Vector3) -> void:
	mb.add_prism(0.07, 0.05, 0.06, 8, Palette.CERAMIC, _t(s.x, s.y, s.z))
	mb.add_prism(0.04, 0.035, 0.16, 8, Palette.CERAMIC.lerp(Palette.WATER_LIGHT, 0.4), _t(s.x, s.y + 0.06, s.z))
	flames.add_pyramid(0.02, 0.06, 5, Palette.WINDOW_GLOW, _t(s.x, s.y + 0.1, s.z))
	lamps.append(s + Vector3(0, 0.25, 0))


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


## Buồng ngủ: vách gỗ lửng phía gian giữa, giường có màn, tủ, đèn treo.
func _room_bedroom(shell: MeshBuilder, mb: MeshBuilder, flames: MeshBuilder, lamps: Array[Vector3],
		x0: float, x1: float, outer: float) -> void:
	var p := _p
	var inner_x := x1 if outer < 0.0 else x0
	var vz0 := _back_z + 0.45
	var vz1 := _front_z - 1.3
	if vz1 - vz0 > 0.8:
		shell.add_box(Vector3(0.08, 1.9, vz1 - vz0), Palette.WOOD_LIGHT, _t(inner_x, p, (vz0 + vz1) * 0.5))
		var z := vz0 + 0.3
		while z < vz1 - 0.1:
			shell.add_box(Vector3(0.1, 1.9, 0.05), Palette.WOOD, _t(inner_x, p, z))
			z += 0.45
		shell.add_box(Vector3(0.12, 0.08, vz1 - vz0), Palette.WOOD, _t(inner_x, p + 1.9, (vz0 + vz1) * 0.5))
	var bed_w := minf(1.6, _gian - 1.0)
	var x := (x0 + 0.2 + bed_w * 0.5) if outer < 0.0 else (x1 - 0.2 - bed_w * 0.5)
	var bed_d := minf(2.1, _dep - _ver - 1.2)
	var bz := _back_z + wall_thickness + 0.05 + bed_d * 0.5
	_table(mb, Vector3(bed_w, 0.45, bed_d), Vector3(x, p, bz), Palette.WOOD, 0.08)
	mb.add_box(Vector3(bed_w - 0.1, 0.03, bed_d - 0.1), Palette.MAT, _t(x, p + 0.45, bz))
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(bed_w * 0.32, 0.1, 0.3), Palette.PILLOW, _t(x + s * bed_w * 0.22, p + 0.48, bz - bed_d * 0.38))
	mb.add_box(Vector3(bed_w * 0.56, 0.14, 0.45), Palette.BLANKET, _t(x, p + 0.48, bz + bed_d * 0.3))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(0.04, 1.5, 0.04), Palette.WOOD_LIGHT, _t(x + sx * (bed_w * 0.5 - 0.04), p + 0.45, bz + sz * (bed_d * 0.5 - 0.04)))
	for sz in [-1.0, 1.0]:
		mb.add_box(Vector3(bed_w - 0.04, 0.03, 0.03), Palette.WOOD_LIGHT, _t(x, p + 1.95, bz + sz * (bed_d * 0.5 - 0.04)))
	mb.add_prism(0.06, 0.06, bed_w - 0.1, 6, Palette.PILLOW,
			Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + bed_w * 0.5 - 0.05, p + 1.98, bz - bed_d * 0.5 + 0.04)))
	# Tủ sát tường hồi phía trước giường
	var wx := (x0 + 0.35) if outer < 0.0 else (x1 - 0.35)
	var wz := minf(_front_z - 0.65, bz + bed_d * 0.5 + 0.6)
	if wz + 0.45 < _front_z:
		mb.add_box(Vector3(0.6, 1.75, 0.9), Palette.WOOD, _t(wx, p, wz))
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(0.03, 1.5, 0.4), Palette.WOOD_LIGHT, _t(wx - outer * 0.31, p + 0.12, wz + sz * 0.22))
	# Đèn treo cạnh giường
	var lx := x - outer * (bed_w * 0.5 + 0.25)
	mb.add_box(Vector3(0.04, 0.6, 0.04), Palette.WOOD, _t(lx, p + 0.6, bz + bed_d * 0.5 - 0.1))
	_lamp(mb, flames, lamps, Vector3(lx, p + 1.2, bz + bed_d * 0.5 - 0.1))


## Phản gỗ + chõng tre (nhà tranh, hoặc gian khách).
func _room_plank(mb: MeshBuilder, x0: float, x1: float, outer: float) -> void:
	var p := _p
	var w := minf(1.9, _gian - 0.6)
	var x := (x0 + 0.2 + w * 0.5) if outer < 0.0 else (x1 - 0.2 - w * 0.5)
	var z := _back_z + wall_thickness + 0.85
	mb.add_box(Vector3(w, 0.38, 1.5), Palette.WOOD.darkened(0.1), _t(x, p, z))
	for i in 3:
		mb.add_box(Vector3(w, 0.02, 0.48), Palette.WOOD_LIGHT, _t(x, p + 0.38, z - 0.5 + i * 0.5))
	mb.add_box(Vector3(w - 0.15, 0.02, 1.35), Palette.MAT, _t(x, p + 0.4, z))
	mb.add_box(Vector3(0.5, 0.12, 0.3), Palette.PILLOW, _t(x, p + 0.42, z - 0.5))
	mb.add_box(Vector3(0.7, 0.08, 0.5), Palette.BLANKET.darkened(0.15), _t(x - 0.2, p + 0.42, z + 0.35))
	# Chõng tre: các nan tre nằm ngang trên 4 chân
	var cz := z + 1.4
	if cz + 0.4 < _front_z:
		var cx := (x0 + x1) * 0.5
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				mb.add_box(Vector3(0.05, 0.42, 0.05), Palette.BAMBOO_STEM, _t(cx + sx * 0.75, p, cz + sz * 0.28))
		for i in 9:
			mb.add_prism(0.025, 0.025, 1.6, 5, Palette.BAMBOO_STEM.lerp(Palette.STRAW, 0.3),
					Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(cx + 0.8, p + 0.44, cz - 0.27 + i * 0.067)))


## Kho: chạn bát, chum gạo, bao gạo, nong nia, quang gánh.
func _room_storage(mb: MeshBuilder, x0: float, x1: float, outer: float) -> void:
	var p := _p
	var wall_z := _back_z + wall_thickness
	var cx := (x0 + x1) * 0.5 - outer * 0.25
	var cz := wall_z + 0.25
	var cw := minf(1.25, _gian - 1.3)
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.05, 1.5, 0.45), Palette.WOOD, _t(cx + s * cw * 0.5, p, cz))
	for i in 4:
		var y := p + 0.05 + i * 0.45
		mb.add_box(Vector3(cw, 0.04, 0.45), Palette.WOOD, _t(cx, y, cz))
		if i < 3:
			var n := int(cw / 0.3)
			for k in n:
				var bx := cx - cw * 0.5 + 0.18 + k * 0.3
				mb.add_prism(0.07, 0.1, 0.06, 7, Palette.CERAMIC, _t(bx, y + 0.04, cz))
				mb.add_prism(0.065, 0.09, 0.05, 7, Palette.CERAMIC, _t(bx, y + 0.1, cz))
	mb.add_box(Vector3(cw, 1.5, 0.03), Palette.WOOD_LIGHT, _t(cx, p, cz - 0.21))
	# Chum gạo + bao gạo phía tường hồi
	var jx := (x1 - 0.45) if outer > 0.0 else (x0 + 0.45)
	var jz := minf(wall_z + 1.35, _front_z - 0.9)
	mb.add_prism(0.24, 0.38, 0.38, 9, Palette.JAR, _t(jx, p, jz))
	mb.add_prism(0.38, 0.22, 0.36, 9, Palette.JAR, _t(jx, p + 0.38, jz))
	mb.add_prism(0.27, 0.22, 0.06, 9, Palette.WOOD, _t(jx, p + 0.74, jz))
	for i in 2:
		mb.add_blob(Vector3(0.26, 0.24, 0.2), Palette.SACK, _rng, 0.15, _t(jx - outer * (0.6 + i * 0.48), p, jz + 0.45))
	# Nong nia dựng nghiêng vào tường hồi
	var nx := (x1 - 0.08) if outer > 0.0 else (x0 + 0.08)
	for i in 3:
		var r := 0.5 - i * 0.08
		var nz := _front_z - 1.0 + i * 0.25
		if nz < jz + 0.5:
			continue
		var xf := Transform3D(Basis(Vector3.BACK, outer * (PI * 0.5 - 0.15)), Vector3(nx - outer * i * 0.05, p + r + 0.02, nz))
		mb.add_prism(r, r, 0.03, 12, Palette.STRAW if i != 1 else Palette.STRAW.darkened(0.12), xf)
	# Quang gánh
	var qx := (x0 + x1) * 0.5
	var qz := _front_z - 0.55
	for s in [-1.0, 1.0]:
		mb.add_prism(0.2, 0.26, 0.3, 10, Palette.STRAW.darkened(0.1), _t(qx + s * 0.6, p, qz))
		mb.add_box(Vector3(0.015, 0.55, 0.015), Palette.WOOD, _t(qx + s * 0.6, p + 0.3, qz))
	mb.add_prism(0.025, 0.025, 1.5, 6, Palette.BAMBOO_STEM,
			Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(qx + 0.75, p + 0.85, qz)))


## Khung cửi dệt vải + ghế ngồi + rổ sợi.
func _room_loom(mb: MeshBuilder, x0: float, x1: float) -> void:
	var p := _p
	var cx := (x0 + x1) * 0.5
	var cz := (_back_z + _front_z) * 0.5 - 0.2
	var w := 1.2
	var d := 1.6
	for s in [-1.0, 1.0]:
		var sx: float = cx + s * w * 0.5
		mb.add_box(Vector3(0.07, 1.5, 0.07), Palette.WOOD, _t(sx, p, cz - d * 0.5))
		mb.add_box(Vector3(0.07, 0.8, 0.07), Palette.WOOD, _t(sx, p, cz + d * 0.5))
		mb.add_box(Vector3(0.06, 0.06, d), Palette.WOOD, _t(sx, p + 0.75, cz))
		mb.add_box(Vector3(0.06, 0.06, d * 0.6), Palette.WOOD, _t(sx, p + 1.45, cz - d * 0.2))
	# Trục cuốn sợi trước/sau, khổ vải đang dệt, khung go
	mb.add_prism(0.06, 0.06, w, 8, Palette.WOOD_LIGHT, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(cx + w * 0.5, p + 1.3, cz - d * 0.5)))
	mb.add_prism(0.08, 0.08, w, 8, Palette.WOOD_LIGHT, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(cx + w * 0.5, p + 0.72, cz + d * 0.5 - 0.1)))
	var cloth := Transform3D(Basis(Vector3.RIGHT, -0.33), Vector3(cx, p + 0.82, cz + d * 0.5 - 0.15))
	mb.add_box(Vector3(w - 0.2, 0.01, 1.3), Palette.FLOWER_WHITE, cloth)
	mb.add_box(Vector3(w - 0.2, 0.012, 0.35), Palette.BLANKET, cloth * _t(0.0, 0.0, 0.35))
	mb.add_box(Vector3(w - 0.1, 0.35, 0.05), Palette.WOOD, _t(cx, p + 0.9, cz))
	# Ghế ngồi dệt + rổ sợi
	mb.add_box(Vector3(0.7, 0.42, 0.3), Palette.WOOD, _t(cx, p, cz + d * 0.5 + 0.35))
	mb.add_prism(0.2, 0.25, 0.18, 10, Palette.STRAW, _t(cx + w * 0.5 + 0.4, p, cz + d * 0.5))
	for i in 3:
		mb.add_blob(Vector3(0.07, 0.06, 0.07), [Palette.BLANKET, Palette.FLOWER_WHITE, Palette.ALTAR_RED][i], _rng, 0.1,
				_t(cx + w * 0.5 + 0.35 + i * 0.07, p + 0.16, cz + d * 0.5))


## Cối xay thóc, cối giã gạo, bồ thóc, thúng.
func _room_mill(mb: MeshBuilder, x0: float, x1: float) -> void:
	var p := _p
	var cx := (x0 + x1) * 0.5
	var cz := (_back_z + _front_z) * 0.5
	# Cối xay: đế tròn, thân dưới, thớt trên + tay xay
	var mx := cx - 0.45
	mb.add_prism(0.5, 0.55, 0.25, 10, Palette.WOOD.darkened(0.1), _t(mx, p, cz))
	mb.add_prism(0.34, 0.34, 0.35, 10, Palette.MUD, _t(mx, p + 0.25, cz))
	mb.add_prism(0.34, 0.3, 0.3, 10, Palette.MUD.darkened(0.1), _t(mx, p + 0.6, cz))
	mb.add_limb(Vector3(mx + 0.3, p + 0.8, cz), Vector3(mx + 1.2, p + 0.85, cz + 0.2), 0.03, 0.03, 4, Palette.WOOD)
	mb.add_box(Vector3(0.04, 0.04, 0.6), Palette.WOOD, _t(mx + 1.2, p + 0.82, cz + 0.2))
	# Cối giã gạo + chày
	var gx := cx + 0.6
	var gz := cz + 0.6
	mb.add_prism(0.24, 0.28, 0.45, 8, Palette.ROCK, _t(gx, p, gz))
	mb.add_prism(0.16, 0.16, 0.46, 8, Palette.ROCK_DARK, _t(gx, p, gz))
	mb.add_limb(Vector3(gx + 0.05, p + 0.3, gz), Vector3(gx + 0.25, p + 1.3, gz - 0.1), 0.04, 0.035, 5, Palette.WOOD_LIGHT)
	# Bồ thóc to sát tường sau + thúng
	mb.add_prism(0.5, 0.45, 1.1, 12, Palette.STRAW.darkened(0.15), _t(cx + 0.4, p, _back_z + wall_thickness + 0.55))
	mb.add_prism(0.42, 0.42, 1.12, 12, Palette.STRAW.lerp(Palette.FLOWER_YELLOW, 0.4), _t(cx + 0.4, p, _back_z + wall_thickness + 0.55))
	mb.add_prism(0.24, 0.28, 0.2, 10, Palette.STRAW, _t(cx - 0.6, p, _front_z - 0.45))


## Góc học: bàn thấp trên chiếu, sách, nghiên mực, giá sách, đèn.
func _room_study(mb: MeshBuilder, flames: MeshBuilder, lamps: Array[Vector3], x0: float, x1: float) -> void:
	var p := _p
	var cx := (x0 + x1) * 0.5
	var cz := _back_z + wall_thickness + 1.2
	mb.add_box(Vector3(1.6, 0.015, 1.4), Palette.MAT, _t(cx, p + 0.01, cz))
	_table(mb, Vector3(0.9, 0.32, 0.5), Vector3(cx, p, cz - 0.15), Palette.WOOD, 0.05)
	for i in 3:
		mb.add_box(Vector3(0.22, 0.03, 0.3), [Palette.FLOWER_WHITE, Palette.STRAW, Palette.SACK][i], _t(cx - 0.25, p + 0.32 + i * 0.03, cz - 0.15))
	mb.add_box(Vector3(0.3, 0.005, 0.22), Palette.FLOWER_WHITE, _t(cx + 0.1, p + 0.32, cz - 0.12))
	mb.add_box(Vector3(0.12, 0.04, 0.08), Palette.WINDOW_DARK, _t(cx + 0.33, p + 0.32, cz - 0.25))
	mb.add_prism(0.006, 0.006, 0.18, 3, Palette.BAMBOO_STEM, Transform3D(Basis(Vector3.BACK, 1.2), Vector3(cx + 0.2, p + 0.34, cz - 0.05)))
	mb.add_box(Vector3(0.4, 0.06, 0.4), Palette.BLANKET, _t(cx, p + 0.02, cz + 0.35))   # đệm ngồi
	# Giá sách sát tường sau
	var bz := _back_z + wall_thickness + 0.2
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.04, 1.2, 0.3), Palette.WOOD, _t(cx + s * 0.55, p, bz))
	for i in 3:
		var y := p + 0.05 + i * 0.4
		mb.add_box(Vector3(1.1, 0.03, 0.3), Palette.WOOD, _t(cx, y, bz))
		for k in 6:
			var h := _rng.randf_range(0.18, 0.28)
			mb.add_box(Vector3(0.1, h, 0.2), [Palette.ALTAR_RED, Palette.STRAW, Palette.BLANKET, Palette.SACK][k % 4],
					_t(cx - 0.42 + k * 0.17, y + 0.03, bz))
	_lamp(mb, flames, lamps, Vector3(cx + 0.35, p + 0.32, cz - 0.05))


# --- Đình làng ------------------------------------------------------------------------

func _build_dinh(shell: MeshBuilder, floor_mb: MeshBuilder, mb: MeshBuilder, flames: MeshBuilder,
		lamps: Array[Vector3]) -> void:
	var p := _p
	var H := _h
	var t := 0.3
	_front = "open"
	_front_z = _dep * 0.5
	# Nền đá cao, tường sau + hai hồi bằng ván gỗ, mặt trước để thoáng
	shell.add_box(Vector3(_len + 2.0, p, _dep + 2.0), Palette.PLINTH.darkened(0.08), Transform3D.IDENTITY)
	for i in 3:
		shell.add_box(Vector3(8.0 - i * 1.2, p - i * 0.27, 0.5), Palette.PLINTH, _t(0.0, 0.0, (_dep + 2.0) * 0.5 + 0.25 + (2 - i) * 0.5))
	shell.add_box(Vector3(_len, H, t), Palette.WOOD, _t(0.0, p, -_dep * 0.5 + t * 0.5))
	for s in [-1.0, 1.0]:
		shell.add_box(Vector3(t, H, _dep - 0.3), Palette.WOOD, _t(s * (_len * 0.5 - t * 0.5), p, -0.15))
	# Ván ghép dọc trên tường gỗ
	var x := -_len * 0.5 + 0.5
	while x < _len * 0.5 - 0.3:
		shell.add_box(Vector3(0.04, H, 0.03), Palette.WOOD.darkened(0.15), _t(x, p, -_dep * 0.5 + t + 0.01))
		x += 0.6
	# Lưới cột lim (cột cái to hơn ở giữa)
	for ix in 6:
		for iz in 4:
			var cx := -_len * 0.5 + 0.6 + (_len - 1.2) * ix / 5.0
			var cz := -_dep * 0.5 + 0.8 + (_dep - 1.6) * iz / 3.0
			var big := (ix == 2 or ix == 3) and (iz == 1 or iz == 2)
			var r := 0.3 if big else 0.22
			shell.add_prism(r + 0.12, r + 0.12, 0.15, 8, Palette.PLINTH, _t(cx, p, cz))
			shell.add_prism(r, r * 0.92, H, 8, Palette.WOOD.darkened(0.1), _t(cx, p + 0.15, cz))
	# Xà dọc nối đầu cột theo từng hàng (để treo đèn lồng)
	for iz in 4:
		var rz := -_dep * 0.5 + 0.8 + (_dep - 1.6) * iz / 3.0
		shell.add_box(Vector3(_len - 1.0, 0.22, 0.22), Palette.WOOD.darkened(0.2), _t(0.0, p + H - 0.05, rz))
	_build_floor(floor_mb, Palette.FLOOR, 0.6)

	# Hậu cung: bệ cao, khám thờ, ngai, bài vị
	var hz := -_dep * 0.5 + 1.6
	mb.add_box(Vector3(6.0, 0.45, 2.6), Palette.PLINTH.darkened(0.15), _t(0.0, p, hz))
	mb.add_box(Vector3(6.1, 0.08, 2.7), Palette.ALTAR_RED, _t(0.0, p + 0.45, hz))
	var ky := p + 0.53
	mb.add_box(Vector3(2.4, 2.1, 1.3), Palette.ALTAR_RED, _t(0.0, ky, hz - 0.4))
	mb.add_box(Vector3(2.0, 1.7, 0.05), Palette.WINDOW_DARK, _t(0.0, ky + 0.15, hz + 0.27))
	mb.add_box(Vector3(2.5, 0.25, 1.4), Palette.GOLD, _t(0.0, ky + 2.1, hz - 0.4))
	mb.add_pyramid(0.8, 0.6, 4, Palette.GOLD, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, ky + 2.35, hz - 0.4)))
	# Ngai thờ trong khám
	var nz := hz + 0.05
	mb.add_box(Vector3(0.9, 0.5, 0.6), Palette.GOLD, _t(0.0, ky + 0.15, nz))
	mb.add_box(Vector3(0.9, 0.9, 0.1), Palette.GOLD, _t(0.0, ky + 0.65, nz - 0.25))
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.1, 0.35, 0.55), Palette.GOLD.darkened(0.15), _t(s * 0.42, ky + 0.65, nz))
	mb.add_box(Vector3(0.24, 0.55, 0.08), Palette.ALTAR_RED, _t(0.0, ky + 0.65, nz))   # bài vị
	mb.add_box(Vector3(0.14, 0.4, 0.02), Palette.GOLD, _t(0.0, ky + 0.72, nz + 0.05))
	# Ban thờ trước hậu cung: hương án, bát hương đồng, chân nến, mâm bồng
	var az := hz + 1.75
	_table(mb, Vector3(2.8, 1.05, 0.9), Vector3(0.0, p, az), Palette.ALTAR_RED, 0.1)
	mb.add_box(Vector3(2.6, 0.18, 0.03), Palette.GOLD, _t(0.0, p + 0.82, az + 0.45))
	var top := p + 1.05
	mb.add_prism(0.2, 0.24, 0.22, 10, Palette.GOLD.darkened(0.35), _t(0.0, top, az))
	for s in [-1.0, 1.0]:
		mb.add_prism(0.08, 0.04, 0.06, 6, Palette.GOLD, _t(s * 0.7, top, az))
		mb.add_prism(0.03, 0.03, 0.55, 6, Palette.GOLD, _t(s * 0.7, top + 0.06, az))
		mb.add_prism(0.04, 0.035, 0.12, 6, Palette.PILLOW, _t(s * 0.7, top + 0.6, az))
		mb.add_prism(0.06, 0.18, 0.2, 8, Palette.GOLD, _t(s * 1.1, top, az))
		mb.add_blob(Vector3(0.14, 0.12, 0.14), Palette.BEAK, _rng, 0.15, _t(s * 1.1, top + 0.2, az))
		# Hạc đứng trên lưng rùa chầu hai bên
		_crane_on_turtle(mb, Vector3(s * 1.15, p, az + 0.8))
		# Câu đối trên cột cái
		mb.add_box(Vector3(0.28, 1.6, 0.04), Palette.ALTAR_RED, _t(s * (_len * 0.1), p + 0.6, -_dep * 0.5 + 0.8 + (_dep - 1.6) * 2.0 / 3.0 + 0.32))
		mb.add_box(Vector3(0.1, 1.4, 0.02), Palette.GOLD, _t(s * (_len * 0.1), p + 0.7, -_dep * 0.5 + 0.8 + (_dep - 1.6) * 2.0 / 3.0 + 0.35))
	# Hoành phi trên tường sau
	mb.add_box(Vector3(3.4, 0.6, 0.08), Palette.ALTAR_RED, _t(0.0, p + 2.35, -_dep * 0.5 + t + 0.04))
	mb.add_box(Vector3(3.0, 0.36, 0.03), Palette.GOLD, _t(0.0, p + 2.47, -_dep * 0.5 + t + 0.09))

	# Trống đại trên giá (bên trái) và chiêng treo (bên phải)
	var dx := -_len * 0.5 + 2.4
	var dz := -0.6
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.1, 1.5, 0.1), Palette.WOOD, _t(dx, p, dz + s * 0.65))
	mb.add_box(Vector3(0.12, 0.1, 1.45), Palette.WOOD, _t(dx, p + 1.5, dz))
	var drum := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(dx, p + 1.0, dz - 0.45))
	mb.add_prism(0.5, 0.5, 0.9, 12, Palette.ALTAR_RED, drum)
	mb.add_prism(0.46, 0.46, 0.92, 12, Palette.PILLOW.darkened(0.1), drum * _t(0.0, -0.01, 0.0))
	mb.add_prism(0.55, 0.55, 0.06, 12, Palette.GOLD, drum * _t(0.0, 0.42, 0.0))
	var gx := _len * 0.5 - 2.4
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.1, 1.9, 0.1), Palette.WOOD, _t(gx, p, dz + s * 0.6))
	mb.add_box(Vector3(0.12, 0.1, 1.3), Palette.WOOD, _t(gx, p + 1.9, dz))
	mb.add_box(Vector3(0.02, 0.35, 0.02), Palette.WINDOW_DARK, _t(gx, p + 1.55, dz))
	mb.add_prism(0.45, 0.45, 0.06, 14, Palette.GOLD.darkened(0.2),
			Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(gx + 0.03, p + 1.15, dz)))
	mb.add_prism(0.12, 0.12, 0.08, 10, Palette.GOLD, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(gx + 0.06, p + 1.15, dz)))

	# Bát bửu: hai giá binh khí nghi trượng dọc tường hồi
	for s in [-1.0, 1.0]:
		var bx: float = s * (_len * 0.5 - 0.7)
		mb.add_box(Vector3(0.3, 0.25, 3.2), Palette.ALTAR_RED, _t(bx, p, 1.6))
		mb.add_box(Vector3(0.3, 0.08, 3.2), Palette.ALTAR_RED, _t(bx, p + 1.3, 1.6))
		for k in 8:
			var z := 0.2 + k * 0.4
			mb.add_prism(0.025, 0.025, 2.2, 5, Palette.ALTAR_RED, _t(bx, p, z))
			var tip := [Palette.GOLD, Palette.GOLD.darkened(0.2)][k % 2] as Color
			match k % 4:
				0: mb.add_blob(Vector3(0.12, 0.16, 0.04), tip, _rng, 0.1, _t(bx, p + 2.2, z))
				1: mb.add_pyramid(0.08, 0.35, 4, tip, _t(bx, p + 2.2, z))
				2: mb.add_box(Vector3(0.05, 0.3, 0.2), tip, _t(bx, p + 2.2, z))
				_: mb.add_prism(0.1, 0.1, 0.04, 8, tip, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(bx, p + 2.3, z)))
	# Kiệu bát cống (bên trái phía trước)
	var kx := -_len * 0.5 + 4.4
	var kz := 2.4
	mb.add_box(Vector3(1.1, 0.5, 1.1), Palette.ALTAR_RED, _t(kx, p + 0.3, kz))
	mb.add_box(Vector3(0.9, 0.9, 0.9), Palette.GOLD.darkened(0.1), _t(kx, p + 0.8, kz))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(0.05, 0.6, 0.05), Palette.ALTAR_RED, _t(kx + sx * 0.5, p + 1.7, kz + sz * 0.5))
	mb.add_pyramid(0.85, 0.5, 4, Palette.ALTAR_RED, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(kx, p + 2.3, kz)))
	for sz in [-1.0, 1.0]:
		mb.add_prism(0.04, 0.04, 3.6, 6, Palette.ALTAR_RED, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(kx + 1.8, p + 0.55, kz + sz * 0.35)))
		for sx in [-1.0, 1.0]:
			mb.add_box(Vector3(0.06, 0.55, 0.06), Palette.WOOD, _t(kx + sx * 1.6, p, kz + sz * 0.35))
	# Chiếu hội giữa đình
	for row in 3:
		for k in 2:
			var mx: float = (k - 0.5) * 2.4
			var mz := 1.0 + row * 1.25
			mb.add_box(Vector3(2.0, 0.015, 1.0), Palette.MAT if (row + k) % 2 == 0 else Palette.MAT.darkened(0.1), _t(mx, p + 0.01, mz))
			mb.add_box(Vector3(2.04, 0.02, 0.06), Palette.ALTAR_RED, _t(mx, p + 0.01, mz - 0.5))
	# Đèn lồng đỏ treo
	var beam_rows: Array[float] = [-_dep * 0.5 + 0.8 + (_dep - 1.6) / 3.0, -_dep * 0.5 + 0.8 + (_dep - 1.6) * 2.0 / 3.0]
	for s in [-1.0, 1.0]:
		for z in beam_rows:
			var lx: float = s * 3.6
			mb.add_box(Vector3(0.02, 0.6, 0.02), Palette.WINDOW_DARK, _t(lx, p + H - 0.6, z))
			mb.add_blob(Vector3(0.22, 0.28, 0.22), Palette.ALTAR_RED, _rng, 0.05, _t(lx, p + H - 1.15, z))
			flames.add_prism(0.12, 0.12, 0.06, 8, Palette.WINDOW_GLOW, _t(lx, p + H - 1.18, z))
			lamps.append(Vector3(lx, p + H - 1.0, z))
	# Nến trên ban thờ
	for s in [-1.0, 1.0]:
		flames.add_pyramid(0.025, 0.07, 5, Palette.WINDOW_GLOW, _t(s * 0.7, top + 0.72, az))
	lamps.append(Vector3(0.0, top + 0.9, az + 0.4))


## Hạc đứng trên lưng rùa (đồ thờ bằng đồng).
func _crane_on_turtle(mb: MeshBuilder, pos: Vector3) -> void:
	var bronze := Palette.GOLD.darkened(0.45)
	mb.add_blob(Vector3(0.45, 0.2, 0.6), bronze.darkened(0.1), _rng, 0.08, _t(pos.x, pos.y, pos.z))
	mb.add_blob(Vector3(0.12, 0.1, 0.15), bronze, _rng, 0.05, _t(pos.x, pos.y + 0.05, pos.z + 0.6))
	var body := pos + Vector3(0, 1.0, 0)
	for s in [-1.0, 1.0]:
		mb.add_limb(pos + Vector3(s * 0.1, 0.35, 0), body + Vector3(s * 0.08, 0.0, 0), 0.03, 0.025, 4, bronze)
	mb.add_blob(Vector3(0.18, 0.2, 0.32), bronze, _rng, 0.05, _t(body.x, body.y - 0.2, body.z))
	var head := body + Vector3(0, 1.0, 0.25)
	mb.add_limb(body + Vector3(0, 0.15, 0.2), head, 0.05, 0.03, 5, bronze)
	mb.add_blob(Vector3(0.06, 0.06, 0.08), bronze, _rng, 0.05, _t(head.x, head.y - 0.06, head.z))
	mb.add_limb(head, head + Vector3(0, -0.02, 0.22), 0.02, 0.003, 4, Palette.GOLD)


# --- Chùa -----------------------------------------------------------------------------

func _build_pagoda(shell: MeshBuilder, floor_mb: MeshBuilder, mb: MeshBuilder, flames: MeshBuilder,
		lamps: Array[Vector3]) -> void:
	var p := _p
	var wc := Palette.WALL
	var wd := Palette.WALL_DARK
	_front = "veranda_wood"
	_build_shell(shell, wc, wd, 2.4)
	_build_veranda(shell, 6, Palette.ALTAR_RED, false)
	# Hàng cửa son (cắt thấp) hai bên ô cửa giữa
	for i in 5:
		var x := -_len * 0.5 + _len * (i + 0.5) / 5.0
		if absf(x) < 1.0:
			continue
		shell.add_box(Vector3(1.4, front_wall_cut + 0.05, 0.06), Palette.ALTAR_RED, _t(x, p, _front_z - 0.02))
	_build_floor(floor_mb, Palette.FLOOR, 0.5)

	# Phật điện: ba cấp bệ ở tường sau
	var wall_z := _back_z + wall_thickness
	var tiers := [[0.0, 0.5, 2.6], [0.5, 0.45, 1.75], [0.95, 0.45, 0.95]]   # [độ cao, dày, sâu]
	for i in tiers.size():
		var tr: Array = tiers[i]
		var w := 8.0 - i * 1.2
		mb.add_box(Vector3(w, tr[1], tr[2]), Palette.ALTAR_RED, _t(0.0, p + tr[0], wall_z + tr[2] * 0.5))
		mb.add_box(Vector3(w + 0.04, 0.06, 0.03), Palette.GOLD, _t(0.0, p + tr[0] + tr[1] - 0.08, wall_z + tr[2] + 0.01))
	# Tam Thế (cấp trên cùng)
	var y3: float = p + 1.4
	for k in 3:
		_buddha(mb, Vector3((k - 1) * 1.6, y3, wall_z + 0.45), 0.85, Palette.GOLD)
	# A Di Đà lớn + Quan Âm, Thế Chí (cấp giữa)
	var y2: float = p + 0.95
	_buddha(mb, Vector3(0.0, y2, wall_z + 1.3), 0.75, Palette.GOLD)
	for s in [-1.0, 1.0]:
		_buddha(mb, Vector3(s * 1.7, y2, wall_z + 1.3), 0.6, Palette.CERAMIC)
	# Cửu Long nhỏ (cấp dưới)
	_buddha(mb, Vector3(0.0, p + 0.5, wall_z + 2.15), 0.35, Palette.GOLD.darkened(0.1))
	for s in [-1.0, 1.0]:
		mb.add_limb(Vector3(s * 0.55, p + 0.5, wall_z + 2.1), Vector3(s * 0.25, p + 1.05, wall_z + 2.15), 0.06, 0.03, 5, Palette.LILY.darkened(0.2))
	# Hoành phi trên Phật điện
	mb.add_box(Vector3(3.6, 0.5, 0.08), Palette.ALTAR_RED, _t(0.0, p + 2.45, wall_z + 0.04))
	mb.add_box(Vector3(3.2, 0.3, 0.03), Palette.GOLD, _t(0.0, p + 2.55, wall_z + 0.09))

	# Ban thờ trước Phật điện
	var az := wall_z + 3.35
	_table(mb, Vector3(2.6, 0.95, 0.8), Vector3(0.0, p, az), Palette.ALTAR_RED, 0.09)
	mb.add_box(Vector3(2.4, 0.16, 0.03), Palette.GOLD, _t(0.0, p + 0.74, az + 0.4))
	var top := p + 0.95
	mb.add_prism(0.16, 0.2, 0.18, 10, Palette.GOLD.darkened(0.35), _t(0.0, top, az))
	for i in 5:
		mb.add_prism(0.008, 0.008, 0.3, 3, Palette.ALTAR_RED, _t((i - 2) * 0.03, top + 0.15, az))
	for s in [-1.0, 1.0]:
		mb.add_prism(0.06, 0.1, 0.3, 8, Palette.CERAMIC, _t(s * 0.6, top, az))
		for k in 3:
			mb.add_pyramid(0.07, 0.14, 6, Palette.LOTUS, _t(s * 0.6 + (k - 1) * 0.06, top + 0.3 + k % 2 * 0.06, az))
		mb.add_prism(0.2, 0.16, 0.04, 10, Palette.GOLD, _t(s * 1.0, top, az))
		for k in 4:
			mb.add_blob(Vector3(0.06, 0.06, 0.06), [Palette.FLOWER_YELLOW, Palette.BEAK, Palette.LILY, Palette.ROOF][k], _rng, 0.1,
					_t(s * 1.0 + (k % 2 - 0.5) * 0.12, top + 0.04 + (k >> 1) * 0.08, az + (k % 2 - 0.5) * 0.08))
		# Đèn dầu trên ban thờ
		_lamp(mb, flames, lamps, Vector3(s * 0.3, top, az + 0.15))

	# Chuông (phải) và mõ (trái) đặt trên đôn
	var side := _len * 0.5 - 1.3
	mb.add_prism(0.3, 0.3, 0.45, 8, Palette.ALTAR_RED, _t(side, p, az))
	mb.add_prism(0.22, 0.12, 0.35, 12, Palette.GOLD.darkened(0.4), _t(side, p + 0.45, az))
	mb.add_prism(0.24, 0.24, 0.05, 12, Palette.GOLD.darkened(0.3), _t(side, p + 0.45, az))
	mb.add_prism(0.3, 0.3, 0.45, 8, Palette.ALTAR_RED, _t(-side, p, az))
	mb.add_box(Vector3(0.4, 0.04, 0.4), Palette.ALTAR_RED.darkened(0.2), _t(-side, p + 0.45, az))
	mb.add_blob(Vector3(0.24, 0.17, 0.2), Palette.ALTAR_RED, _rng, 0.08, _t(-side, p + 0.49, az))
	mb.add_limb(Vector3(-side + 0.25, p + 0.55, az + 0.15), Vector3(-side + 0.5, p + 0.6, az + 0.3), 0.015, 0.015, 4, Palette.WOOD)

	# Hộ pháp hai bên cửa
	for s in [-1.0, 1.0]:
		_guardian(mb, Vector3(s * (_len * 0.5 - 1.0), p, _front_z - 1.0), s)
	# Bồ đoàn (đệm ngồi) xếp hàng
	for row in 2:
		for k in 5:
			var bx := (k - 2) * 0.75
			var bz := az + 1.3 + row * 0.8
			if bz > _front_z - 0.6:
				continue
			mb.add_prism(0.2, 0.22, 0.1, 10, Palette.FLOWER_YELLOW.darkened(0.25), _t(bx, p, bz))


## Tượng Phật ngồi kiết già trên toà sen, có hào quang. `s` = tỉ lệ.
func _buddha(mb: MeshBuilder, base: Vector3, s: float, color: Color) -> void:
	var petal := Palette.LOTUS if color != Palette.CERAMIC else Palette.LILY
	mb.add_prism(0.42 * s, 0.5 * s, 0.18 * s, 12, petal, _t(base.x, base.y, base.z))
	for k in 8:
		var a := TAU * k / 8.0
		mb.add_pyramid(0.12 * s, 0.18 * s, 4, petal.lightened(0.15), Transform3D(Basis(Vector3(-sin(a), 0, cos(a)), 0.5),
				base + Vector3(cos(a) * 0.42 * s, 0.1 * s, sin(a) * 0.42 * s)))
	var y := base.y + 0.18 * s
	mb.add_blob(Vector3(0.42, 0.14, 0.3) * s, color, _rng, 0.06, _t(base.x, y, base.z))          # chân xếp bằng
	mb.add_blob(Vector3(0.27, 0.36, 0.2) * s, color, _rng, 0.05, _t(base.x, y + 0.12 * s, base.z))  # thân
	mb.add_blob(Vector3(0.13, 0.15, 0.13) * s, color, _rng, 0.04, _t(base.x, y + 0.8 * s, base.z))  # đầu
	mb.add_blob(Vector3(0.06, 0.07, 0.06) * s, color.darkened(0.15), _rng, 0.04, _t(base.x, y + 1.06 * s, base.z))
	mb.add_prism(0.3 * s, 0.3 * s, 0.03, 14, Palette.GOLD.lightened(0.1),
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(base.x, y + 0.92 * s, base.z - 0.14 * s)))


## Tượng hộ pháp đứng, cầm gươm.
func _guardian(mb: MeshBuilder, pos: Vector3, side: float) -> void:
	mb.add_box(Vector3(0.9, 0.3, 0.7), Palette.PLINTH, _t(pos.x, pos.y, pos.z))
	var y := pos.y + 0.3
	mb.add_blob(Vector3(0.38, 0.75, 0.3), Palette.ALTAR_RED, _rng, 0.08, _t(pos.x, y, pos.z))
	mb.add_box(Vector3(0.6, 0.18, 0.4), Palette.GOLD.darkened(0.2), _t(pos.x, y + 1.25, pos.z))
	mb.add_blob(Vector3(0.18, 0.2, 0.18), Palette.WOOD.darkened(0.2), _rng, 0.05, _t(pos.x, y + 1.43, pos.z))
	mb.add_pyramid(0.2, 0.3, 6, Palette.GOLD, _t(pos.x, y + 1.78, pos.z))
	mb.add_limb(Vector3(pos.x - side * 0.3, y + 0.6, pos.z + 0.2), Vector3(pos.x - side * 0.35, y + 1.9, pos.z + 0.3), 0.04, 0.02, 4, Palette.ROCK)
