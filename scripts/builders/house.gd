class_name House
extends Node3D
## Nhà mái ngói 3 gian (có hiên, cột gỗ, cửa, cửa sổ), gian bếp nhỏ và sân gạch.
## Đặt sẵn đèn cửa sổ (nhóm "night_light") và ô cửa phát sáng (nhóm "night_glow")
## để chu kỳ ngày đêm bật lên khi tối. `smoke_point` là chỗ khói bếp bốc lên.

@export var terrain: Terrain
@export var random_seed: int = 4104

@export_group("Nhà chính")
@export var house_position: Vector3 = Vector3(-11.8, 0.0, -13.6)
@export_range(-45.0, 45.0) var house_yaw_deg: float = 8.0
@export var length: float = 10.0
@export var depth: float = 5.6
@export var veranda_depth: float = 1.6
@export var wall_height: float = 2.6
@export var plinth_height: float = 0.4
@export var roof_rise: float = 2.3
@export var roof_overhang: float = 0.6
@export var gable_overhang: float = 0.35
@export var tile_spacing: float = 0.32

@export_group("Bếp")
@export var kitchen_position: Vector3 = Vector3(-3.4, 0.0, -15.8)
@export var kitchen_yaw_deg: float = -82.0
@export var kitchen_length: float = 3.8
@export var kitchen_depth: float = 3.0
@export var kitchen_wall_height: float = 2.1
@export var kitchen_roof_rise: float = 1.5

@export_group("Sân")
@export var yard_tile_size: float = 0.55
@export var yard_grout: float = 0.05

@export_group("Đèn đêm")
@export var window_light_energy: float = 1.6
@export var window_light_range: float = 7.0

## Điểm khói bếp (toạ độ world), có sau khi build().
var smoke_point: Vector3 = Vector3.ZERO


func build() -> void:
	var mb := MeshBuilder.new(random_seed, 0.04)
	mb.contact_shade_height = 0.7
	mb.contact_shade_strength = 0.2
	var glow := MeshBuilder.new(random_seed + 1, 0.0)
	var light_points: Array[Vector3] = []

	var hx := Transform3D(Basis(Vector3.UP, deg_to_rad(house_yaw_deg)), house_position)
	_build_main_house(mb, glow, hx, light_points)

	var kx := Transform3D(Basis(Vector3.UP, deg_to_rad(kitchen_yaw_deg)), kitchen_position)
	_build_kitchen(mb, glow, kx, light_points)

	add_child(mb.commit_instance("HouseMesh"))

	var glow_node := glow.commit_instance("WindowGlow", _glow_material())
	glow_node.add_to_group("night_glow")
	add_child(glow_node)

	var yard := MeshBuilder.new(random_seed + 2, 0.08)
	_build_yard(yard)
	var yard_node := yard.commit_instance("Yard")
	yard_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(yard_node)

	for i in light_points.size():
		var light := OmniLight3D.new()
		light.name = "NightLight%d" % i
		light.position = light_points[i]
		light.light_color = Palette.FIRE_GLOW if i == light_points.size() - 1 else Palette.WINDOW_GLOW
		light.omni_range = window_light_range
		light.light_energy = 0.0
		light.set_meta("max_energy", window_light_energy)
		light.add_to_group("night_light")
		add_child(light)


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


static func _glow_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = Palette.WINDOW_GLOW
	mat.emission_energy_multiplier = 0.0  # DayNight tăng lên khi trời tối
	return mat


# --- Nhà chính ----------------------------------------------------------------------

func _build_main_house(mb: MeshBuilder, glow: MeshBuilder, xf: Transform3D,
		light_points: Array[Vector3]) -> void:
	var p := plinth_height
	var h := wall_height
	var core_depth := depth - veranda_depth
	var core_z := -depth * 0.5 + core_depth * 0.5
	var front_z := -depth * 0.5 + core_depth      # mặt tường trước

	# Nền nhà + bậc thềm
	mb.add_box(Vector3(length + 0.9, p, depth + 0.9), Palette.PLINTH, xf)
	var step_z := (depth + 0.9) * 0.5
	mb.add_box(Vector3(2.8, p * 0.5, 0.5), Palette.PLINTH, xf * _t(0.0, 0.0, step_z + 0.25))

	# Tường + chân tường tối màu
	mb.add_box(Vector3(length, h, core_depth), Palette.WALL, xf * _t(0.0, p, core_z))
	mb.add_box(Vector3(length + 0.06, 0.35, core_depth + 0.06), Palette.WALL_DARK, xf * _t(0.0, p, core_z))

	# Hiên: 4 cột gỗ có chân đá, xà ngang
	var col_z := depth * 0.5 - 0.25
	for i in 4:
		var x := lerpf(-length * 0.5 + 0.3, length * 0.5 - 0.3, i / 3.0)
		mb.add_box(Vector3(0.36, 0.14, 0.36), Palette.PLINTH, xf * _t(x, p, col_z))
		mb.add_prism(0.12, 0.11, h, 6, Palette.WOOD, xf * _t(x, p + 0.14, col_z))
	mb.add_box(Vector3(length, 0.22, 0.24), Palette.WOOD, xf * _t(0.0, p + h - 0.22, col_z))

	# Cửa chính (gian giữa): khung + 2 cánh + nẹp ngang
	mb.add_box(Vector3(1.6, 2.15, 0.1), Palette.WOOD, xf * _t(0.0, p, front_z))
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.66, 1.95, 0.08), Palette.WOOD_LIGHT, xf * _t(s * 0.36, p + 0.05, front_z + 0.06))
		for yy in [0.5, 1.3]:
			mb.add_box(Vector3(0.6, 0.06, 0.04), Palette.WOOD, xf * _t(s * 0.36, p + yy, front_z + 0.12))

	# Cửa sổ (2 gian bên): khung gỗ, ô tối/phát sáng, song dọc
	for s in [-1.0, 1.0]:
		var wx: float = s * length / 3.0
		mb.add_box(Vector3(1.3, 1.1, 0.1), Palette.WOOD, xf * _t(wx, p + 0.9, front_z))
		glow.add_box(Vector3(1.06, 0.86, 0.04), Palette.WINDOW_DARK, xf * _t(wx, p + 1.02, front_z + 0.07))
		for k in 5:
			var bx := wx + lerpf(-0.42, 0.42, k / 4.0)
			mb.add_box(Vector3(0.06, 0.86, 0.06), Palette.WOOD, xf * _t(bx, p + 1.02, front_z + 0.11))
		light_points.append(xf * Vector3(wx, p + 1.5, front_z + 1.0))

	_build_roof(mb, xf, length, depth, p + h, roof_rise, roof_overhang, gable_overhang)


# --- Bếp ----------------------------------------------------------------------------

func _build_kitchen(mb: MeshBuilder, glow: MeshBuilder, xf: Transform3D,
		light_points: Array[Vector3]) -> void:
	var p := 0.2
	var h := kitchen_wall_height
	mb.add_box(Vector3(kitchen_length + 0.5, p, kitchen_depth + 0.5), Palette.PLINTH, xf)
	mb.add_box(Vector3(kitchen_length, h, kitchen_depth), Palette.WALL_DARK, xf * _t(0.0, p, 0.0))
	mb.add_box(Vector3(kitchen_length + 0.06, 0.3, kitchen_depth + 0.06), Palette.WOOD, xf * _t(0.0, p, 0.0))
	# Cửa bếp ở đầu hồi quay ra sân (+x cục bộ): hắt ánh lửa khi tối
	var ex := kitchen_length * 0.5
	mb.add_box(Vector3(0.1, 1.8, 1.1), Palette.WOOD, xf * _t(ex, p, 0.0))
	glow.add_box(Vector3(0.04, 1.65, 0.9), Palette.WINDOW_DARK, xf * _t(ex + 0.06, p + 0.02, 0.0))
	_build_roof(mb, xf, kitchen_length, kitchen_depth, p + h, kitchen_roof_rise, 0.55, 0.25)
	smoke_point = xf * Vector3(-kitchen_length * 0.25, p + h + kitchen_roof_rise + 0.25, 0.0)
	light_points.append(xf * Vector3(ex + 0.9, p + 1.2, 0.0))


# --- Mái ngói -----------------------------------------------------------------------

## Mái hai dốc trên tường cao `top_y`: hồi tường, tấm mái, hàng ngói nổi, bờ nóc, đầu đao.
func _build_roof(mb: MeshBuilder, xf: Transform3D, len_: float, dep: float, top_y: float,
		rise: float, over: float, gover: float) -> void:
	# Khối hồi (tam giác tường hai đầu) lấp kín gầm mái
	mb.add_wedge(Vector3(len_, rise, dep), Palette.WALL_DARK, xf * _t(0.0, top_y, 0.0), Palette.WALL)

	var half := dep * 0.5
	var tan_a := rise / half
	var a := atan(tan_a)
	var run := half + over
	var slope_len := run / cos(a)
	var roof_len := len_ + gover * 2.0
	var thick := 0.14
	for s in [1.0, -1.0]:
		var basis := Basis(Vector3.RIGHT, s * a)
		var mid := Vector3(0.0, top_y + rise - run * 0.5 * tan_a, s * run * 0.5)
		var sx := xf * Transform3D(basis, mid)
		mb.add_box(Vector3(roof_len, thick, slope_len), Palette.ROOF, sx)
		# Hàng ngói ống chạy từ nóc xuống diềm
		var x := -roof_len * 0.5 + tile_spacing * 0.5
		var k := 0
		while x < roof_len * 0.5:
			var col := Palette.ROOF_DARK if k % 2 == 0 else Palette.ROOF
			mb.add_box(Vector3(tile_spacing * 0.42, 0.07, slope_len), col, sx * _t(x, thick, 0.0))
			x += tile_spacing
			k += 1
		# Diềm mái
		mb.add_box(Vector3(roof_len, 0.1, 0.16), Palette.ROOF_DARK, sx * _t(0.0, thick, slope_len * 0.5 - 0.08))

	# Bờ nóc + đầu đao cong lên ở hai đầu
	var ridge_y := top_y + rise - 0.05
	mb.add_box(Vector3(roof_len + 0.2, 0.34, 0.42), Palette.ROOF_DARK, xf * _t(0.0, ridge_y, 0.0))
	for s in [-1.0, 1.0]:
		var tip := Transform3D(Basis(Vector3.FORWARD, s * 0.55),
				Vector3(s * (roof_len * 0.5 + 0.05), ridge_y + 0.2, 0.0))
		mb.add_prism(0.2, 0.05, 0.6, 4, Palette.ROOF_DARK, xf * tip, PI / 4.0)


# --- Sân gạch -----------------------------------------------------------------------

func _build_yard(mb: MeshBuilder) -> void:
	if terrain == null:
		return
	var yr := terrain.yard_rect
	var x0 := yr.position.x + 0.3
	var x1 := yr.end.x - 0.3
	var z0 := house_position.z + depth * 0.5 + 0.2
	var z1 := yr.end.y - 0.3
	var below := Vector3(0, -1, 0)
	# Lớp vữa
	mb.add_quad(Vector3(x0, 0.02, z0), Vector3(x1, 0.02, z0), Vector3(x1, 0.02, z1),
			Vector3(x0, 0.02, z1), Palette.GROUT, Vector3((x0 + x1) * 0.5, -1.0, (z0 + z1) * 0.5))
	# Gạch vuông, hàng so le
	var ts := yard_tile_size
	var g := yard_grout * 0.5
	var row := 0
	var z := z0
	while z < z1 - 0.01:
		var ze := minf(z + ts, z1)
		var x := x0 - (ts * 0.5 if row % 2 == 1 else 0.0)
		while x < x1 - 0.01:
			var xa := maxf(x, x0) + g
			var xb := minf(x + ts, x1) - g
			if xb > xa:
				var y := 0.04
				mb.add_quad(Vector3(xa, y, z + g), Vector3(xb, y, z + g), Vector3(xb, y, ze - g),
						Vector3(xa, y, ze - g), Palette.YARD, Vector3(xa, -1.0, z) + below)
			x += ts
		z = ze
		row += 1
	# Bó vỉa quanh sân
	var e := 0.18
	var bh := 0.12
	mb.add_box(Vector3(x1 - x0 + e, bh, e), Palette.WALL_DARK, _t((x0 + x1) * 0.5, 0.0, z1))
	mb.add_box(Vector3(e, bh, z1 - z0), Palette.WALL_DARK, _t(x0, 0.0, (z0 + z1) * 0.5))
	mb.add_box(Vector3(e, bh, z1 - z0), Palette.WALL_DARK, _t(x1, 0.0, (z0 + z1) * 0.5))
