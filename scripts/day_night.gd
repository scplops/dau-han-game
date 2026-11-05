class_name DayNight
extends Node
## Chu kỳ ngày đêm: xoay mặt trời/mặt trăng theo giờ, chuyển màu trời, sương, ánh sáng
## môi trường; ban đêm bật đèn cửa sổ (nhóm "night_light"), ô cửa phát sáng
## (nhóm "night_glow") và đom đóm. Khói bếp bốc lên quanh ngày.
## Phím: [ / ] lùi/tiến giờ (giữ phím), T bật/tắt tự chạy.

signal time_changed(hour: float)
## Đồng hồ qua nửa đêm: +1 (sang ngày mới) hoặc −1 (lùi giờ qua 0h). LunarCalendar đổi ngày theo.
signal day_rolled(days: int)

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var house: House

@export_range(0.0, 24.0, 0.01) var time_of_day: float = 17.0:
	set = set_time_of_day
@export var auto_run: bool = false
@export var day_length_seconds: float = 120.0     # 1 ngày = 2 phút
@export var key_hours_per_second: float = 3.0     # tốc độ khi giữ [ hoặc ]

@export_group("Mặt trời & mặt trăng")
@export var max_sun_elevation_deg: float = 62.0
@export var max_moon_elevation_deg: float = 45.0
@export var min_light_elevation_deg: float = 6.0
## Độ lệch về phía sau cảnh của quỹ đạo (0 = đi thẳng qua đỉnh đầu).
@export_range(0.0, 1.5) var orbit_tilt: float = 0.6

@export_group("Ban đêm")
## Ánh sáng môi trường tối thiểu để ban đêm vẫn nhìn rõ cảnh.
@export_range(0.0, 2.0) var night_ambient_min: float = 0.55
@export var window_glow_energy: float = 2.5
@export_range(0, 300) var firefly_count: int = 70
@export var firefly_area: AABB = AABB(Vector3(-19.0, 0.3, -8.0), Vector3(40.0, 2.0, 28.0))

@export_group("Khói bếp")
@export_range(0, 60) var smoke_amount: int = 16
@export var smoke_lifetime: float = 7.0
@export var smoke_drift: Vector3 = Vector3(0.12, 0.0, 0.05)

# Mốc màu theo giờ: [giờ, màu đèn, cường độ đèn, trời ngang, đỉnh trời, ambient, cường độ ambient, sương]
const KEYS: Array = [
	[0.0, Palette.MOON, 0.22, Palette.SKY_NIGHT, Palette.SKY_NIGHT_TOP, Palette.AMBIENT_NIGHT, 0.5, Palette.FOG_NIGHT],
	[4.6, Palette.MOON, 0.22, Palette.SKY_NIGHT, Palette.SKY_NIGHT_TOP, Palette.AMBIENT_NIGHT, 0.5, Palette.FOG_NIGHT],
	[5.6, Palette.MOON_DUSK, 0.15, Palette.SKY_DUSK, Palette.SKY_DUSK_TOP, Palette.AMBIENT_DUSK, 0.45, Palette.FOG_DUSK],
	[6.6, Palette.SUN_DAWN, 0.75, Palette.SKY_DAWN, Palette.SKY_DAWN_TOP, Palette.AMBIENT_DAWN, 0.4, Palette.FOG_DAWN],
	[9.0, Palette.SUN_NOON, 1.0, Palette.SKY_NOON, Palette.SKY_NOON_TOP, Palette.AMBIENT_NOON, 0.45, Palette.FOG_NOON],
	[12.0, Palette.SUN_NOON, 1.05, Palette.SKY_NOON, Palette.SKY_NOON_TOP, Palette.AMBIENT_NOON, 0.42, Palette.FOG_NOON],
	[15.0, Palette.SUN_NOON, 1.0, Palette.SKY_NOON, Palette.SKY_NOON_TOP, Palette.AMBIENT_NOON, 0.42, Palette.FOG_NOON],
	[17.0, Palette.SUN, 1.1, Palette.SKY, Palette.SKY_TOP, Palette.AMBIENT, 0.45, Palette.FOG],
	[18.3, Palette.SUN_SUNSET, 0.75, Palette.SKY_SUNSET, Palette.SKY_SUNSET_TOP, Palette.AMBIENT_SUNSET, 0.4, Palette.FOG_SUNSET],
	[19.3, Palette.MOON_DUSK, 0.18, Palette.SKY_DUSK, Palette.SKY_DUSK_TOP, Palette.AMBIENT_DUSK, 0.45, Palette.FOG_DUSK],
	[20.5, Palette.MOON, 0.22, Palette.SKY_NIGHT, Palette.SKY_NIGHT_TOP, Palette.AMBIENT_NIGHT, 0.5, Palette.FOG_NIGHT],
	[24.0, Palette.MOON, 0.22, Palette.SKY_NIGHT, Palette.SKY_NIGHT_TOP, Palette.AMBIENT_NIGHT, 0.5, Palette.FOG_NIGHT],
]

var night_factor: float = 0.0
## Độ phủ mây 0..1 (Weather đặt): làm yếu nắng, trời và sương ngả xám, trời tối thì bật đèn sớm.
var weather_cover: float = 0.0
## Mức sương mù 0..1 (Weather đặt): màu sương ngả trắng đục.
var weather_mist: float = 0.0
var _fireflies: Node3D
var _glow_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	for node in get_tree().get_nodes_in_group("night_glow"):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if mat != null:
				_glow_materials.append(mat)
	_fireflies = _make_particles("Fireflies", _firefly_particles())
	if house != null:
		_make_particles("KitchenSmoke", _smoke_particles())
	_apply()


func set_time_of_day(value: float) -> void:
	var days := int(floor(value / 24.0))
	time_of_day = wrapf(value, 0.0, 24.0)
	if days != 0 and is_inside_tree():
		day_rolled.emit(days)
	if is_inside_tree():
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_time"):
		auto_run = not auto_run


func _process(delta: float) -> void:
	var step := 0.0
	if auto_run:
		step += 24.0 / day_length_seconds * delta
	if Input.is_action_pressed("time_forward"):
		step += key_hours_per_second * delta
	if Input.is_action_pressed("time_back"):
		step -= key_hours_per_second * delta
	if step != 0.0:
		time_of_day += step


## Áp lại ánh sáng theo giờ hiện tại (khi vừa thêm đèn / ô cửa mới vào cảnh).
func refresh() -> void:
	_glow_materials.clear()
	for node in get_tree().get_nodes_in_group("night_glow"):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if mat != null:
				_glow_materials.append(mat)
	_apply()


## Chuỗi giờ dạng "17:05".
func time_text() -> String:
	var total := int(time_of_day * 60.0)
	return "%02d:%02d" % [total / 60 % 24, total % 60]


# --- Áp dụng ------------------------------------------------------------------------

func _apply() -> void:
	var h := time_of_day
	var k := _sample_keys(h)
	night_factor = smoothstep(17.8, 19.4, h) if h >= 12.0 else 1.0 - smoothstep(5.0, 6.6, h)

	var cover := weather_cover
	if sun != null:
		sun.light_color = (k[0] as Color).lerp(Palette.OVERCAST, cover * 0.6)
		sun.light_energy = k[1] * (1.0 - 0.85 * cover)
		var dir := _light_direction(h)
		sun.global_basis = Basis.looking_at(-dir, Vector3.UP)

	if world_environment != null:
		var env := world_environment.environment
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		var horizon := _overcast(k[2], cover)
		if sky_mat != null:
			sky_mat.sky_horizon_color = horizon
			sky_mat.sky_top_color = _overcast(k[3], cover)
			sky_mat.ground_horizon_color = horizon
			sky_mat.ground_bottom_color = horizon.darkened(0.3)
		env.ambient_light_color = _overcast(k[4], cover * 0.8)
		# Trời âm u: ánh sáng môi trường gánh phần lớn (bóng mờ đi), nhưng tổng thể tối hơn
		env.ambient_light_energy = lerpf(k[5], maxf(k[5], night_ambient_min), night_factor) * (1.0 + 0.3 * cover - 0.35 * smoothstep(0.7, 1.0, cover))
		var fog_col := _overcast(k[6], cover)
		var mist_col := Palette.MIST.lerp(k[6], 0.4).darkened(night_factor * 0.65)
		env.fog_light_color = fog_col.lerp(mist_col, weather_mist)

	# Trời giông tối sầm: các nhà thắp đèn sớm
	var lit := maxf(night_factor, smoothstep(0.75, 1.0, cover) * 0.6)
	for node in get_tree().get_nodes_in_group("day_fill"):
		var fl := node as Light3D
		if fl != null:
			fl.light_energy = float(fl.get_meta("max_energy", 0.6)) * (1.0 - night_factor) * (1.0 - 0.5 * cover)
	for node in get_tree().get_nodes_in_group("night_light"):
		var light := node as Light3D
		if light != null:
			light.light_energy = float(light.get_meta("max_energy", 1.0)) * lit
	for mat in _glow_materials:
		mat.emission_energy_multiplier = window_glow_energy * lit
	if _fireflies != null:
		_fireflies.visible = night_factor > 0.35
		_fireflies.set("emitting", night_factor > 0.35)

	time_changed.emit(h)


## Màu ngả xám theo độ phủ mây, giữ độ sáng tương ứng giờ trong ngày.
static func _overcast(c: Color, cover: float) -> Color:
	var l := c.get_luminance()
	var grey := Palette.OVERCAST * (l / maxf(Palette.OVERCAST.get_luminance(), 0.001)) * 0.85
	grey.a = 1.0
	return c.lerp(grey, clampf(cover, 0.0, 1.0) * 0.85)


## Nội suy mốc màu: trả về [màu đèn, cường độ, trời ngang, đỉnh trời, ambient, cường độ ambient, sương].
func _sample_keys(h: float) -> Array:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			var t := smoothstep(0.0, 1.0, (h - a[0]) / maxf(b[0] - a[0], 0.001))
			return [
				(a[1] as Color).lerp(b[1], t), lerpf(a[2], b[2], t),
				(a[3] as Color).lerp(b[3], t), (a[4] as Color).lerp(b[4], t),
				(a[5] as Color).lerp(b[5], t), lerpf(a[6], b[6], t),
				(a[7] as Color).lerp(b[7], t),
			]
	var last: Array = KEYS[KEYS.size() - 1]
	return [last[1], last[2], last[3], last[4], last[5], last[6], last[7]]


## Hướng TỚI nguồn sáng: mặt trời 6h–18h (mọc +x, lặn -x), ngoài giờ đó là mặt trăng.
func _light_direction(h: float) -> Vector3:
	var angle: float
	var max_el: float
	if h >= 6.0 and h <= 18.0:
		angle = (h - 6.0) / 12.0 * PI
		max_el = max_sun_elevation_deg
	else:
		var moon_h := h - 18.0 if h > 18.0 else h + 6.0
		angle = moon_h / 12.0 * PI
		max_el = max_moon_elevation_deg
	var el := deg_to_rad(maxf(sin(angle) * max_el, min_light_elevation_deg))
	var horiz := Vector3(cos(angle), 0.0, -sin(angle) * orbit_tilt).normalized()
	return (horiz * cos(el) + Vector3.UP * sin(el)).normalized()


# --- Hạt: đom đóm, khói bếp -----------------------------------------------------------

## Dùng GPUParticles3D ở Forward+, CPUParticles3D ở Compatibility.
func _make_particles(node_name: String, cpu: CPUParticles3D) -> Node3D:
	cpu.name = node_name
	var node: Node3D = cpu
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		var gpu := GPUParticles3D.new()
		gpu.name = node_name
		gpu.convert_from_particles(cpu)
		gpu.position = cpu.position
		gpu.visibility_aabb = AABB(Vector3(-25, -5, -25), Vector3(50, 20, 50))
		cpu.free()
		node = gpu
	add_child(node)
	return node


func _firefly_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = firefly_count
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.position = firefly_area.get_center()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = firefly_area.size * 0.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.08
	p.initial_velocity_max = 0.3
	p.scale_amount_curve = _fade_curve(0.0, 1.0, 0.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Palette.FIREFLY
	mesh.material = mat
	p.mesh = mesh
	return p


func _smoke_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = smoke_amount
	p.lifetime = smoke_lifetime
	p.preprocess = smoke_lifetime
	p.position = house.smoke_point
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = smoke_drift
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.45
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _fade_curve(0.35, 1.0, 1.8)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(Palette.SMOKE, 0.75))
	ramp.set_color(1, Color(Palette.SMOKE, 0.0))
	p.color_ramp = ramp
	# Cụm khói low-poly: khối 20 mặt
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mb := MeshBuilder.new(77, 0.0)
	mb.add_blob(Vector3(0.35, 0.3, 0.35), Color.WHITE, rng, 0.15, Transform3D(Basis(), Vector3(0, -0.3, 0)))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.disable_receive_shadows = true
	p.mesh = mb.commit(mat)
	return p


## Đường cong 3 điểm: đầu → giữa → cuối (dùng cho kích thước hạt theo vòng đời).
static func _fade_curve(start: float, mid: float, end: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(maxf(start, mid), maxf(end, 1.0))
	c.add_point(Vector2(0.0, start))
	c.add_point(Vector2(0.25, mid))
	c.add_point(Vector2(0.75, mid))
	c.add_point(Vector2(1.0, end))
	return c
