class_name School
extends Node3D
## Trường tiểu học nông thôn kiểu những năm 2000, phía tây khu nhà mình:
## - Dãy lớp học 2 tầng: tường vôi vàng, viền trắng, hành lang cột vuông, lan can con tiện,
##   cửa chớp xanh lá, mái ngói đỏ 4 mái, cầu thang ngoài ở đầu hồi, trống trường ở hiên.
## - Dãy hiệu bộ 1 tầng, nhà để xe mái tôn có xe đạp, khu vệ sinh.
## - Sân xi măng, cột cờ, bồn hoa, cây bàng, cây phượng; tường rào vàng, cổng có biển tên.
## Cổng mở ra đường đất phía đông (Terrain.roads[0]).

@export var random_seed: int = 2000
@export var site: Rect2 = Rect2(-98.0, -42.0, 56.0, 38.0)   # x, z, rộng, sâu
@export var gate_z: float = -20.0
@export var road_x: float = -24.5
@export var school_name: String = "TRƯỜNG TIỂU HỌC"

@export_group("Dãy lớp học")
@export_range(3, 8) var classrooms: int = 5
@export var room_width: float = 7.2
@export var room_depth: float = 6.5
@export var corridor: float = 2.0
@export var floor_height: float = 3.4
@export var plinth: float = 0.45

## Đường từ đường đất vào cổng tới giữa sân (cho dân làng), có sau build().
var entry_path := PackedVector2Array()
## Các chỗ đứng chơi trong sân trường.
var yard_spots: Array[Vector3] = []
## Điểm cho học sinh (SchoolDay, mục 26): trước cửa từng lớp tầng 1 (trên hành lang), mép sân trước
## hành lang, cột cờ, cổng trong / ngoài.
var classroom_doors: Array[Vector3] = []
var classroom_fronts: Array[Vector3] = []
var flag_pos: Vector3
var gate_in: Vector3
var gate_out: Vector3

var _rng := RandomNumberGenerator.new()
var _glow_mat: StandardMaterial3D


func build() -> void:
	_rng.seed = random_seed
	var mb := MeshBuilder.new(random_seed, 0.03)
	mb.contact_shade_height = 0.6
	mb.contact_shade_strength = 0.15
	var glow := MeshBuilder.new(random_seed + 1, 0.0)
	var ground := MeshBuilder.new(random_seed + 2, 0.05)
	var leaves := MeshBuilder.new(random_seed + 3, 0.06)

	var cx := site.get_center().x
	_build_yard(ground)
	_build_fence_and_gate(mb)
	# Dãy lớp học chạy dọc mép bắc, quay mặt ra sân (hướng nam, +z)
	var L := classrooms * room_width
	var D := room_depth + corridor
	var main_xf := _t(cx + 3.0, 0.0, site.position.y + D * 0.5 + 1.5)
	_build_block(mb, glow, main_xf, classrooms, room_width, room_depth, 2, true)
	# Dãy hiệu bộ 1 tầng ở mép tây, quay mặt ra sân (hướng đông)
	var off_xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(site.position.x + 5.5, 0.0, site.position.y + 21.0))
	_build_block(mb, glow, off_xf, 3, 5.0, 5.5, 1, false)
	_build_flagpole(mb, Vector3(cx + 3.0, 0.0, gate_z + 1.0))
	_build_bike_shed(mb, Vector3(site.end.x - 9.0, 0.0, site.end.y - 3.2))
	_build_toilet(mb, Vector3(site.position.x + 4.0, 0.0, site.end.y - 4.0))
	_build_trees(mb, leaves)

	add_child(mb.commit_instance("SchoolBuildings"))
	var g := ground.commit_instance("SchoolYard")
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	var tree_mat := MeshBuilder.wind_material(0.1, 2.0, 6.0, 0.9)
	tree_mat.set_shader_parameter("flower_season", 1.0)     # hoa phượng chỉ đỏ mùa hạ (Seasons)
	add_child(leaves.commit_instance("SchoolTrees", tree_mat))
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.vertex_color_use_as_albedo = true
	_glow_mat.vertex_color_is_srgb = true
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Palette.WINDOW_GLOW
	_glow_mat.emission_energy_multiplier = 0.0
	var gl := glow.commit_instance("SchoolWindows", _glow_mat)
	gl.add_to_group("night_glow")
	add_child(gl)
	_build_sign()

	# Cửa vào một lớp học (phòng giữa tầng 1)
	var mid := classrooms >> 1
	var door_x := -L * 0.5 + room_width * (mid + 0.75)
	var door_z := -D * 0.5 + room_depth
	HouseEntry.make_entry_target(self, main_xf * _t(door_x, plinth + 1.05, door_z + 0.15), Vector3(1.4, 2.1, 0.4),
			"Vào lớp học  ·  bấm chuột hoặc E",
			{"kind": "school", "name": "Lớp học · " + school_name.capitalize(), "length": room_width + 1.0,
			"depth": D, "veranda": corridor, "height": floor_height - 0.3, "plinth": plinth,
			"wall": "school", "seed": random_seed + 7}, "school")

	entry_path = PackedVector2Array([Vector2(road_x, gate_z), Vector2(site.end.x + 1.0, gate_z),
			Vector2(site.end.x - 6.0, gate_z), Vector2(cx + 3.0, gate_z + 4.0)])
	for i in classrooms:
		var dx := -L * 0.5 + room_width * (i + 0.75)
		classroom_doors.append(main_xf * Vector3(dx, plinth, -D * 0.5 + room_depth + 0.7))
		classroom_fronts.append(main_xf * Vector3(dx, 0.06, D * 0.5 + 1.4))
	flag_pos = Vector3(cx + 3.0, 0.06, gate_z + 1.0)
	gate_out = Vector3(road_x + 1.0, 0.06, gate_z)
	gate_in = Vector3(site.end.x - 3.0, 0.06, gate_z)
	for i in 26:
		yard_spots.append(Vector3(_rng.randf_range(cx - 14.0, cx + 16.0), 0.06, _rng.randf_range(gate_z - 4.0, gate_z + 10.0)))


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


# --- Sân, rào, cổng ----------------------------------------------------------------------

func _build_yard(mb: MeshBuilder) -> void:
	var r := site.grow(-0.4)
	var y := 0.04
	# Sân xi măng kẻ ô lớn
	var cell := 3.0
	var z := r.position.y
	while z < r.end.y - 0.01:
		var ze := minf(z + cell, r.end.y)
		var x := r.position.x
		while x < r.end.x - 0.01:
			var xe := minf(x + cell, r.end.x)
			mb.add_quad(Vector3(x + 0.03, y, z + 0.03), Vector3(xe - 0.03, y, z + 0.03),
					Vector3(xe - 0.03, y, ze - 0.03), Vector3(x + 0.03, y, ze - 0.03), Palette.SCHOOL_YARD, Vector3(x, -1, z))
			x = xe
		z = ze
	mb.add_quad(Vector3(r.position.x, 0.03, r.position.y), Vector3(r.end.x, 0.03, r.position.y),
			Vector3(r.end.x, 0.03, r.end.y), Vector3(r.position.x, 0.03, r.end.y), Palette.SCHOOL_YARD.darkened(0.15), Vector3(0, -1, -30))
	# Lối xi măng từ cổng ra đường đất
	mb.add_quad(Vector3(site.end.x, y, gate_z - 2.2), Vector3(road_x - 1.5, y, gate_z - 2.2),
			Vector3(road_x - 1.5, y, gate_z + 2.2), Vector3(site.end.x, y, gate_z + 2.2), Palette.SCHOOL_YARD, Vector3(-30, -1, gate_z))


func _build_fence_and_gate(mb: MeshBuilder) -> void:
	var r := site
	var corners := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y),
			Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 1:
			# Mép đông có cổng: chia hai đoạn
			_fence_run(mb, a, Vector2(a.x, gate_z - 2.6))
			_fence_run(mb, Vector2(a.x, gate_z + 2.6), b)
		else:
			_fence_run(mb, a, b)
	# Cổng: hai trụ vuông có mũ, cánh cổng sắt song đứng (mở vào trong)
	for s in [-1.0, 1.0]:
		var pz: float = gate_z + s * 2.6
		mb.add_box(Vector3(0.7, 2.6, 0.7), Palette.SCHOOL_WALL, _t(r.end.x, 0.0, pz))
		mb.add_box(Vector3(0.85, 0.18, 0.85), Palette.SCHOOL_TRIM, _t(r.end.x, 2.6, pz))
		mb.add_pyramid(0.5, 0.35, 4, Palette.SCHOOL_TRIM, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(r.end.x, 2.78, pz)))
		var leaf := Transform3D(Basis(Vector3.UP, s * 1.2), Vector3(r.end.x - 0.1, 0.0, pz - s * 0.35))
		mb.add_box(Vector3(0.04, 0.05, 2.0), Palette.SIGN_BLUE, leaf * _t(0, 1.55, -s * 1.0))
		mb.add_box(Vector3(0.04, 0.05, 2.0), Palette.SIGN_BLUE, leaf * _t(0, 0.15, -s * 1.0))
		for k in 9:
			mb.add_box(Vector3(0.03, 1.45, 0.03), Palette.SIGN_BLUE, leaf * _t(0, 0.15, -s * (0.1 + k * 0.22)))
	# Biển tên cổng: thanh ngang trên hai trụ
	mb.add_box(Vector3(0.35, 0.9, 6.4), Palette.SIGN_BLUE, _t(r.end.x, 2.95, gate_z))
	mb.add_box(Vector3(0.4, 0.1, 6.6), Palette.SCHOOL_TRIM, _t(r.end.x, 3.85, gate_z))


func _fence_run(mb: MeshBuilder, a: Vector2, b: Vector2) -> void:
	var len_ := a.distance_to(b)
	if len_ < 0.2:
		return
	var dir := (b - a) / len_
	var yaw := atan2(dir.x, dir.y)
	var mid := (a + b) * 0.5
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0, mid.y))
	mb.add_box(Vector3(0.22, 0.75, len_), Palette.SCHOOL_WALL, xf)
	mb.add_box(Vector3(0.28, 0.06, len_), Palette.SCHOOL_TRIM, xf * _t(0, 0.75, 0))
	# Trụ + song sắt phía trên tường thấp
	var n := maxi(1, int(len_ / 3.0))
	for i in n + 1:
		var z := -len_ * 0.5 + len_ * i / n
		mb.add_box(Vector3(0.32, 1.7, 0.32), Palette.SCHOOL_WALL, xf * _t(0, 0, z))
		mb.add_box(Vector3(0.38, 0.06, 0.38), Palette.SCHOOL_TRIM, xf * _t(0, 1.7, z))
	mb.add_box(Vector3(0.05, 0.05, len_), Palette.SHUTTER.darkened(0.2), xf * _t(0, 1.55, 0))
	var k := 0.0
	while k < len_ - 0.1:
		mb.add_box(Vector3(0.03, 0.75, 0.03), Palette.SHUTTER.darkened(0.2), xf * _t(0, 0.8, -len_ * 0.5 + k + 0.15))
		k += 0.3


func _build_sign() -> void:
	var font := load("res://assets/fonts/BeVietnamPro-SemiBold.ttf") as Font
	var label := Label3D.new()
	label.text = school_name
	label.font = font
	label.font_size = 64
	label.pixel_size = 0.0075
	label.modulate = Palette.SCHOOL_TRIM
	label.outline_size = 0
	label.position = Vector3(site.end.x + 0.19, 3.4, gate_z)
	label.rotation.y = PI * 0.5      # mặt chữ quay ra đường (hướng +x)
	label.double_sided = false
	add_child(label)


# --- Dãy nhà ---------------------------------------------------------------------------

## Dãy phòng: `rooms` phòng rộng `rw`, sâu `rd`, hành lang phía trước (+z), `floors` tầng.
func _build_block(mb: MeshBuilder, glow: MeshBuilder, xf: Transform3D, rooms: int, rw: float, rd: float,
		floors: int, with_stairs: bool) -> void:
	var L := rooms * rw
	var D := rd + corridor
	var H := floor_height
	var wall := Palette.SCHOOL_WALL
	var trim := Palette.SCHOOL_TRIM
	var core_z := -D * 0.5 + rd * 0.5
	var front_z := -D * 0.5 + rd
	# Nền + bậc thềm
	mb.add_box(Vector3(L + 0.6, plinth, D + 0.6), Palette.PLINTH, xf)
	for k in 2:
		mb.add_box(Vector3(3.0 - k * 0.6, plinth * (0.5 - k * 0.25), 0.4), Palette.PLINTH, xf * _t(0, 0, D * 0.5 + 0.3 + (1 - k) * 0.4))
	var top := plinth + floors * H
	# Khối tường lớp học
	mb.add_box(Vector3(L, floors * H, rd), wall, xf * _t(0, plinth, core_z))
	mb.add_box(Vector3(L + 0.05, 0.6, rd + 0.05), Palette.SCHOOL_WALL_DARK, xf * _t(0, plinth, core_z))   # chân tường
	for f in floors:
		var y0 := plinth + f * H
		# Sàn / mái hiên bê tông viền trắng, đua ra phủ hành lang
		if f > 0:
			mb.add_box(Vector3(L + 0.3, 0.22, D + 0.25), trim, xf * _t(0, y0 - 0.11, 0))
		for i in rooms:
			var x0 := -L * 0.5 + rw * i
			# Cửa ra vào (lệch về một bên) + 2 cửa sổ trước, 2 cửa sổ sau
			var dx := x0 + rw * 0.75
			mb.add_box(Vector3(1.1, 2.2, 0.08), Palette.SHUTTER.darkened(0.1), xf * _t(dx, y0, front_z + 0.02))
			mb.add_box(Vector3(1.3, 2.35, 0.06), trim, xf * _t(dx, y0, front_z + 0.005))
			for wx in [x0 + rw * 0.22, x0 + rw * 0.48]:
				_window(mb, glow, xf, Vector3(wx, y0 + 0.95, front_z), 1.0)
			for wx in [x0 + rw * 0.3, x0 + rw * 0.7]:
				_window(mb, glow, xf, Vector3(wx, y0 + 0.95, -D * 0.5), -1.0)
			# Vách ngăn giữa các lớp: gờ trắng trên mặt tường
			if i > 0:
				mb.add_box(Vector3(0.18, H, 0.06), trim, xf * _t(x0, y0, front_z + 0.03))
		# Cột hành lang
		for i in rooms + 1:
			var x := -L * 0.5 + rw * i
			mb.add_box(Vector3(0.36, H, 0.36), trim, xf * _t(clampf(x, -L * 0.5 + 0.18, L * 0.5 - 0.18), y0, D * 0.5 - 0.18))
		# Lan can con tiện ở các tầng trên
		if f > 0:
			mb.add_box(Vector3(L, 0.12, 0.16), trim, xf * _t(0, y0 + 0.95, D * 0.5 - 0.18))
			mb.add_box(Vector3(L, 0.1, 0.18), trim, xf * _t(0, y0 + 0.1, D * 0.5 - 0.18))
			var x := -L * 0.5 + 0.35
			while x < L * 0.5 - 0.3:
				mb.add_prism(0.055, 0.04, 0.75, 6, Palette.SHUTTER, xf * _t(x, y0 + 0.2, D * 0.5 - 0.18))
				x += 0.24
	# Diềm mái + mái ngói đỏ 4 mái
	mb.add_box(Vector3(L + 0.4, 0.3, D + 0.35), trim, xf * _t(0, top - 0.3, 0))
	_hip_roof(mb, xf, L, D, top, 2.0 if floors > 1 else 1.5, 0.7)
	# Trống trường treo ở hiên tầng 1, cạnh phòng đầu
	if with_stairs:
		var drum := xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-L * 0.5 + 1.2, plinth + 1.5, D * 0.5 - 0.9))
		mb.add_box(Vector3(0.9, 0.06, 0.06), Palette.WOOD, xf * _t(-L * 0.5 + 1.2, plinth + 2.1, D * 0.5 - 0.9))
		mb.add_prism(0.38, 0.38, 0.6, 12, Palette.ALTAR_RED, drum * _t(0, -0.3, 0))
		mb.add_prism(0.35, 0.35, 0.62, 12, Palette.PILLOW.darkened(0.1), drum * _t(0, -0.31, 0))
		_build_stairs(mb, xf, L, D, floors)


func _window(mb: MeshBuilder, glow: MeshBuilder, xf: Transform3D, p: Vector3, face: float) -> void:
	var w := 1.15
	var h := 1.35
	var z := p.z + face * 0.02
	mb.add_box(Vector3(w + 0.22, h + 0.22, 0.06), Palette.SCHOOL_TRIM, xf * _t(p.x, p.y - 0.11, z))
	glow.add_box(Vector3(w, h, 0.04), Palette.WINDOW_DARK, xf * _t(p.x, p.y, z + face * 0.03))
	# Song sắt dọc + hai cánh chớp mở ra hai bên
	for k in 4:
		mb.add_box(Vector3(0.025, h, 0.025), Palette.SHUTTER.darkened(0.3), xf * _t(p.x - w * 0.375 + k * w * 0.25, p.y, z + face * 0.06))
	for s in [-1.0, 1.0]:
		var hinge := xf * Transform3D(Basis(Vector3.UP, -s * face * 1.25), Vector3(p.x + s * (w * 0.5 + 0.1), p.y, z + face * 0.05))
		mb.add_box(Vector3(0.04, h, w * 0.5), Palette.SHUTTER, hinge * _t(0, 0, face * w * 0.25))
		for k in 5:
			mb.add_box(Vector3(0.05, 0.02, w * 0.46), Palette.SHUTTER.darkened(0.2), hinge * _t(0, 0.15 + k * 0.25, face * w * 0.25))


## Mái 4 mái ngói đỏ không trang trí (kiểu trường học), có gờ ngói và bờ nóc.
func _hip_roof(mb: MeshBuilder, xf: Transform3D, L: float, D: float, y: float, rise: float, over: float) -> void:
	var ex := L * 0.5 + over
	var ez := D * 0.5 + over
	var rl := maxf(ex - ez, 0.3)
	var top := y + rise
	var c := [Vector3(-ex, y, ez), Vector3(ex, y, ez), Vector3(ex, y, -ez), Vector3(-ex, y, -ez)]
	var r0 := Vector3(-rl, top, 0)
	var r1 := Vector3(rl, top, 0)
	var inside := Vector3(0, y + rise * 0.3, 0)
	mb.add_quad(c[0], c[1], r1, r0, Palette.ROOF, inside, xf)
	mb.add_quad(c[3], c[2], r1, r0, Palette.ROOF, inside, xf)
	mb.add_triangle(c[0], c[3], r0, Palette.ROOF_DARK, inside, xf)
	mb.add_triangle(c[1], c[2], r1, Palette.ROOF_DARK, inside, xf)
	mb.add_quad(c[0], c[1], c[2], c[3], Palette.ROOF_DARK, inside, xf)
	# Gờ ngói chạy dọc dốc mái trước và sau
	var slope := Vector2(ez, rise).length()
	var ang := atan2(rise, ez)
	var x := -ex + 0.3
	while x < ex - 0.2:
		var l := slope * clampf((ex - absf(x)) / maxf(ex - rl, 0.01), 0.0, 1.0) if absf(x) > rl else slope
		if l > 0.4:
			for s in [1.0, -1.0]:
				var b := Basis(Vector3.RIGHT, s * ang)
				var start := Vector3(x, y, s * ez)
				var mid := start + b * Vector3(0, 0, -s) * (l * 0.5)
				mb.add_box(Vector3(0.1, 0.05, l), Palette.ROOF_DARK, xf * Transform3D(b, mid))
		x += 0.45
	mb.add_box(Vector3(rl * 2.0 + 0.4, 0.22, 0.3), Palette.ROOF_DARK, xf * _t(0, top - 0.05, 0))


## Cầu thang ngoài ở đầu hồi phía đông: bậc chạy từ sau ra trước, chiếu nghỉ nối hành lang.
func _build_stairs(mb: MeshBuilder, xf: Transform3D, L: float, D: float, floors: int) -> void:
	var x := L * 0.5 + 0.95
	var rise := floor_height / 18.0
	for f in range(1, floors):
		var y_base := plinth + (f - 1) * floor_height
		for i in 18:
			var z := -D * 0.5 + 0.4 + i * 0.3
			var h := y_base + rise * (i + 1)
			mb.add_box(Vector3(1.4, 0.18, 0.3), Palette.SCHOOL_TRIM.darkened(0.06), xf * _t(x, h - 0.18, z))
		# Dầm thang (đặc) dưới bậc + chiếu nghỉ
		var run := 18 * 0.3
		var ang := atan2(floor_height, run)
		var mid := Vector3(x, y_base + floor_height * 0.5 - 0.35, -D * 0.5 + 0.4 + run * 0.5)
		mb.add_box(Vector3(1.4, 0.3, Vector2(run, floor_height).length()), Palette.SCHOOL_WALL,
				xf * Transform3D(Basis(Vector3.RIGHT, -ang), mid))
		mb.add_box(Vector3(1.6, 0.22, 2.2), Palette.SCHOOL_TRIM, xf * _t(x - 0.1, y_base + floor_height - 0.22, D * 0.5 - 1.1))
		# Tay vịn
		mb.add_box(Vector3(0.08, 0.08, Vector2(run, floor_height).length()), Palette.SHUTTER,
				xf * Transform3D(Basis(Vector3.RIGHT, -ang), mid + Vector3(0.68, 1.15, 0)))
		mb.add_box(Vector3(0.3, plinth + floor_height, 0.3), Palette.SCHOOL_TRIM, xf * _t(x + 0.62, 0.0, D * 0.5 - 0.15))


# --- Sân: cột cờ, nhà xe, vệ sinh, cây ---------------------------------------------------

func _build_flagpole(mb: MeshBuilder, p: Vector3) -> void:
	var xf := Transform3D(Basis(), p)
	for k in 3:
		mb.add_box(Vector3(2.4 - k * 0.6, 0.18, 2.4 - k * 0.6), Palette.SCHOOL_TRIM.darkened(0.05 * k), xf * _t(0, k * 0.18, 0))
	mb.add_prism(0.06, 0.045, 8.0, 8, Palette.SCHOOL_TRIM, xf * _t(0, 0.54, 0))
	mb.add_prism(0.1, 0.1, 0.12, 8, Palette.FLAG_STAR, xf * _t(0, 8.54, 0))
	# Cờ đỏ sao vàng, mặt cờ hướng ra cổng (+x)
	var fw := 2.1
	var fh := 1.4
	var fx := xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 8.4 - fh, 0))
	mb.add_box(Vector3(fw, fh, 0.03), Palette.FLAG_RED, fx * _t(fw * 0.5 + 0.06, 0, 0))
	for side in [1.0, -1.0]:
		var center := Vector3(fw * 0.5 + 0.06, fh * 0.5, side * 0.02)
		_star(mb, fx, center, fh * 0.3, side)


## Ngôi sao 5 cánh phẳng (cho cờ), mặt hướng theo `side` (+z hoặc -z cục bộ).
func _star(mb: MeshBuilder, xf: Transform3D, c: Vector3, r: float, side: float) -> void:
	var pts: Array[Vector3] = []
	for i in 10:
		var a := PI * 0.5 + TAU * i / 10.0
		var rr := r if i % 2 == 0 else r * 0.38
		pts.append(c + Vector3(cos(a) * rr, sin(a) * rr, 0))
	var behind := c - Vector3(0, 0, side)
	for i in 10:
		mb.add_triangle(c, pts[i], pts[(i + 1) % 10], Palette.FLAG_STAR, behind, xf)


func _build_bike_shed(mb: MeshBuilder, p: Vector3) -> void:
	var xf := Transform3D(Basis(), p)
	var w := 12.0
	var d := 3.2
	for i in 5:
		var x := -w * 0.5 + w * i / 4.0
		mb.add_prism(0.06, 0.06, 2.4, 6, Palette.ROCK_DARK, xf * _t(x, 0, -d * 0.4))
		mb.add_prism(0.06, 0.06, 2.0, 6, Palette.ROCK_DARK, xf * _t(x, 0, d * 0.4))
	# Mái tôn dốc một phía, có sóng
	var roof := xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 2.25, 0))
	mb.add_box(Vector3(w + 0.6, 0.04, d + 0.6), Palette.TIN_ROOF, roof)
	var x := -w * 0.5
	while x < w * 0.5:
		mb.add_box(Vector3(0.06, 0.05, d + 0.6), Palette.TIN_ROOF.darkened(0.12), roof * _t(x, 0.03, 0))
		x += 0.35
	# Xe đạp dựng hàng
	var cols: Array[Color] = [Palette.SIGN_BLUE, Palette.FLAG_RED, Palette.WINDOW_DARK, Palette.SHUTTER, Palette.ROCK_DARK]
	for i in 9:
		var bx := -w * 0.5 + 0.9 + i * 1.25
		_bicycle(mb, xf * Transform3D(Basis(Vector3.UP, PI * 0.5 + _rng.randf_range(-0.1, 0.1)), Vector3(bx, 0, 0)), cols[i % cols.size()])


func _bicycle(mb: MeshBuilder, xf: Transform3D, col: Color) -> void:
	var r := 0.33
	for z in [-0.52, 0.52]:
		var wheel := xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, r, z))
		mb.add_prism(r, r, 0.04, 12, Palette.WINDOW_DARK, wheel * _t(0, -0.02, 0), 0.0, false)
		mb.add_prism(r * 0.85, r * 0.85, 0.05, 12, Palette.ROCK, wheel * _t(0, -0.025, 0), 0.0, false)
	var seat := Vector3(0, 0.82, -0.25)
	var bar := Vector3(0, 0.88, 0.38)
	var crank := Vector3(0, r, -0.02)
	mb.add_limb(Vector3(0, r, -0.52), seat, 0.02, 0.02, 4, col, xf)
	mb.add_limb(crank, seat, 0.022, 0.022, 4, col, xf)
	mb.add_limb(crank, bar, 0.022, 0.022, 4, col, xf)
	mb.add_limb(seat, bar - Vector3(0, 0.06, 0), 0.02, 0.02, 4, col, xf)
	mb.add_limb(Vector3(0, r, 0.52), bar, 0.02, 0.02, 4, col, xf)
	mb.add_box(Vector3(0.12, 0.05, 0.24), Palette.WINDOW_DARK, xf * _t(0, 0.84, -0.27))
	mb.add_box(Vector3(0.55, 0.03, 0.03), Palette.ROCK, xf * _t(0, 0.9, 0.38))
	# Giỏ xe phía trước
	mb.add_box(Vector3(0.3, 0.2, 0.22), Palette.STRAW.darkened(0.1), xf * _t(0, 0.72, 0.6))


func _build_toilet(mb: MeshBuilder, p: Vector3) -> void:
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), p)
	mb.add_box(Vector3(4.5, 0.2, 2.8), Palette.PLINTH, xf)
	mb.add_box(Vector3(4.2, 2.4, 2.4), Palette.SCHOOL_WALL, xf * _t(0, 0.2, 0))
	mb.add_box(Vector3(4.25, 0.5, 2.45), Palette.SCHOOL_WALL_DARK, xf * _t(0, 0.2, 0))
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.8, 1.8, 0.06), Palette.SHUTTER, xf * _t(s * 1.0, 0.2, 1.22))
	mb.add_box(Vector3(4.8, 0.06, 3.0), Palette.TIN_ROOF, xf * Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(0, 2.7, 0)))


func _build_trees(mb: MeshBuilder, leaves: MeshBuilder) -> void:
	var r := site
	var cx := r.get_center().x
	# Phượng dọc mép nam sân, bàng hai bên cột cờ; mỗi cây có bồn gạch
	var phuong: Array[Vector2] = [Vector2(r.position.x + 13, r.end.y - 2.5), Vector2(cx - 2, r.end.y - 2.5), Vector2(cx + 10, r.end.y - 6.5)]
	var bang: Array[Vector2] = [Vector2(cx - 9, gate_z - 3.0), Vector2(cx + 15, gate_z - 3.0)]
	for p in phuong:
		_planter(mb, p)
		_phuong(mb, leaves, Vector3(p.x, 0.35, p.y))
	for p in bang:
		_planter(mb, p)
		_bang(mb, leaves, Vector3(p.x, 0.35, p.y))
	# Bồn hoa dài trước dãy lớp
	for k in 3:
		var bx := cx - 10.0 + k * 10.0
		var bz := r.position.y + room_depth + corridor + 3.6
		mb.add_box(Vector3(4.0, 0.4, 1.0), Palette.SCHOOL_TRIM, _t(bx, 0, bz))
		mb.add_box(Vector3(3.8, 0.05, 0.8), Palette.EARTH.darkened(0.2), _t(bx, 0.4, bz))
		for f in 8:
			var col := [Palette.FLOWER_YELLOW, Palette.HIBISCUS, Palette.FLOWER_PINK, Palette.FLOWER_WHITE][f % 4] as Color
			leaves.add_blob(Vector3(0.22, 0.2, 0.22), Palette.VEGETABLE, _rng, 0.2, _t(bx - 1.6 + f * 0.45, 0.4, bz))
			leaves.add_blob(Vector3(0.08, 0.07, 0.08), col, _rng, 0.15, _t(bx - 1.6 + f * 0.45, 0.62, bz + _rng.randf_range(-0.15, 0.15)))


func _planter(mb: MeshBuilder, p: Vector2) -> void:
	mb.add_prism(1.3, 1.3, 0.35, 8, Palette.SCHOOL_TRIM, _t(p.x, 0, p.y))
	mb.add_prism(1.15, 1.15, 0.37, 8, Palette.EARTH.darkened(0.2), _t(p.x, 0, p.y), 0.0, false)


## Cây phượng: thân xoè, tán rộng dẹt, điểm hoa đỏ.
func _phuong(mb: MeshBuilder, leaves: MeshBuilder, p: Vector3) -> void:
	var xf := Transform3D(Basis(), p)
	mb.add_prism(0.28, 0.2, 2.6, 7, Palette.BANYAN_TRUNK, xf)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var tip := Vector3(cos(a) * 2.2, 4.1, sin(a) * 2.2)
		mb.add_limb(Vector3(0, 2.4, 0), tip, 0.16, 0.08, 5, Palette.BANYAN_TRUNK, xf)
	for i in 7:
		var a := TAU * i / 7.0
		var d := 0.0 if i == 0 else _rng.randf_range(1.8, 3.0)
		var c := Vector3(cos(a) * d, _rng.randf_range(3.8, 4.5), sin(a) * d)
		leaves.add_blob(Vector3(2.0, 0.75, 2.0), Palette.BANYAN_LEAF_2 if i % 2 == 0 else Palette.BANYAN_LEAF_1, _rng, 0.18, xf * _t(c.x, c.y, c.z))
		for k in 7:
			var fa := _rng.randf() * TAU
			var fd := _rng.randf_range(0.3, 1.6)
			leaves.add_blob(Vector3(0.26, 0.14, 0.26), Palette.PHUONG.darkened(_rng.randf_range(0.0, 0.15)), _rng, 0.25,
					xf * _t(c.x + cos(fa) * fd, c.y + 1.2 - fd * 0.25, c.z + sin(fa) * fd))


## Cây bàng: thân thẳng, tán xếp tầng nằm ngang như những chiếc đĩa.
func _bang(mb: MeshBuilder, leaves: MeshBuilder, p: Vector3) -> void:
	var xf := Transform3D(Basis(), p)
	mb.add_prism(0.3, 0.2, 6.2, 7, Palette.BANYAN_TRUNK, xf)
	for t in 3:
		var y := 2.6 + t * 1.5
		var r := 3.4 - t * 0.9
		for i in 5:
			var a := TAU * i / 5.0 + t * 0.6
			mb.add_limb(Vector3(0, y, 0), Vector3(cos(a) * r * 0.8, y + 0.15, sin(a) * r * 0.8), 0.09, 0.04, 4, Palette.BANYAN_TRUNK, xf)
		leaves.add_prism(r, r * 0.8, 0.5, 9, Palette.BANYAN_LEAF_1 if t % 2 == 0 else Palette.BAMBOO_LEAF, xf * _t(0, y + 0.1, 0), _rng.randf())
