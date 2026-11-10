class_name Weather
extends Node
## Thời tiết: nắng, nhiều mây, mưa phùn, mưa giông (sấm chớp), sương mù.
## Mọi thông số chuyển dần (`transition_time`) nên đổi thời tiết không bị giật.
## - Độ phủ mây → DayNight (nắng yếu, trời/sương ngả xám, nhà thắp đèn sớm) + Clouds.
## - Mưa: hạt mưa + tia nước bắn trên mặt đất, đi theo tâm camera ngoài sân (ẩn khi vào nhà).
## - Gió, mưa trên mặt nước: biến toàn cục của shader `weather_wind`, `weather_rain`.
## - Sương: kéo vùng sương lại gần (fog_depth_begin/end).
## - Chớp: loé sáng toàn cảnh (adjustment_brightness) từng đợt khi giông.
## Thời tiết luôn ngẫu nhiên: lúc mở game bắt đầu bằng một kiểu bất kỳ, rồi tự đổi theo
## AUTO_WEIGHTS; mỗi lần chạy mỗi khác. Phím R: đổi ngay sang một kiểu ngẫu nhiên khác.

signal weather_changed(kind: String)
## Chớp loé (Soundscape phát tiếng sấm sau đó một lúc).
signal lightning

const ORDER: Array[String] = ["clear", "cloudy", "drizzle", "storm", "fog"]
const NAMES := {"clear": "Nắng", "cloudy": "Nhiều mây", "drizzle": "Mưa phùn", "storm": "Mưa giông", "fog": "Sương mù"}
## Thông số từng kiểu: độ phủ mây, lượng mưa, hệ số gió, sương (0 = như trời quang, 1 = mù đặc).
const PRESETS := {
	"clear":   {"cover": 0.0,  "rain": 0.0,  "wind": 1.0, "mist": 0.0},
	"cloudy":  {"cover": 0.6,  "rain": 0.0,  "wind": 1.5, "mist": 0.15},
	"drizzle": {"cover": 0.78, "rain": 0.32, "wind": 1.2, "mist": 0.35},
	"storm":   {"cover": 1.0,  "rain": 1.0,  "wind": 3.2, "mist": 0.45},
	"fog":     {"cover": 0.35, "rain": 0.0,  "wind": 0.4, "mist": 1.0},
}
## Xác suất kiểu tiếp theo khi tự đổi (tổng không cần bằng 1).
const AUTO_WEIGHTS := {"clear": 4.0, "cloudy": 3.0, "drizzle": 2.0, "storm": 1.0, "fog": 1.0}

@export var day_night: DayNight
@export var world_environment: WorldEnvironment
@export var clouds: Clouds
@export var outdoor_rig: CameraRig
@export var house_entry: HouseEntry

@export var kind: String = "clear"
## Mùa hiện tại (Seasons đặt): "spring" / "summer" / "autumn" / "winter" và hệ số thời tiết theo mùa.
var season: String = ""
var season_weights: Dictionary = {}
@export var auto_change: bool = true
## Thời gian (giây thật) giữa hai lần tự đổi thời tiết.
@export var auto_interval: Vector2 = Vector2(70.0, 140.0)
@export var transition_time: float = 8.0
@export var random_seed: int = 77
## Bật để thời tiết lặp lại y hệt mỗi lần chạy (dùng `random_seed`); tắt = mỗi lần một khác.
@export var fixed_seed: bool = false
## Lúc mở game chọn ngẫu nhiên kiểu thời tiết (tắt = bắt đầu bằng `kind`).
@export var random_start: bool = true

@export_group("Mưa")
@export_range(0, 20000) var rain_drops: int = 9000
@export_range(0, 5000) var splash_count: int = 1800
@export var rain_height: float = 22.0
@export var rain_speed: float = 17.0
@export_range(0.5, 1.0) var compat_particle_ratio: float = 0.35   # bớt hạt khi chạy Compatibility

@export_group("Sương")
@export var mist_fog_begin: float = 4.0
@export var mist_fog_end: float = 110.0
@export_range(0.0, 1.0) var mist_fog_max: float = 0.93

@export_group("Chớp")
@export var lightning_interval: Vector2 = Vector2(4.0, 11.0)
@export var lightning_strength: float = 1.15

# Thông số hiện tại (đang chuyển dần về PRESETS[kind])
var cover: float = 0.0
var rain: float = 0.0
var wind: float = 1.0
var mist: float = 0.0

var _rng := RandomNumberGenerator.new()
var _rain: Node3D
var _splash: Node3D
var _auto_timer: float = 0.0
var _flash_timer: float = 0.0
var _flash: float = 0.0
var _flash_queue: Array[float] = []
var _base_fog := Vector3(110.0, 520.0, 0.8)   # begin, end, max — lấy từ Environment lúc đầu
var _gpu: bool = true
var _brightness: float = 1.0   # độ sáng nền theo mây (chớp cộng thêm vào)


func _ready() -> void:
	if fixed_seed:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	if random_start:
		kind = _pick_weighted("")
	_gpu = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	if world_environment != null:
		var env := world_environment.environment
		_base_fog = Vector3(env.fog_depth_begin, env.fog_depth_end, env.fog_density)
	_rain = _make_particles("Rain", _rain_particles())
	_splash = _make_particles("RainSplash", _splash_particles())
	_auto_timer = _rng.randf_range(auto_interval.x, auto_interval.y)
	_flash_timer = _rng.randf_range(lightning_interval.x, lightning_interval.y)
	set_weather(kind, true)


## Tên hiển thị ("Mưa giông"…).
func display_name() -> String:
	return str(NAMES.get(kind, kind))


## Đổi thời tiết. `instant` = nhảy ngay, không chuyển dần (dùng khi chụp ảnh).
func set_weather(new_kind: String, instant: bool = false) -> void:
	if not PRESETS.has(new_kind):
		return
	kind = new_kind
	if instant:
		var p: Dictionary = PRESETS[kind]
		cover = p.cover
		rain = p.rain
		wind = p.wind
		mist = p.mist
	_apply()
	weather_changed.emit(kind)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_weather"):
		# Đổi ngay sang kiểu ngẫu nhiên khác, vẫn tiếp tục tự đổi sau đó
		_auto_timer = _rng.randf_range(auto_interval.x, auto_interval.y)
		set_weather(_pick_next())


func _process(delta: float) -> void:
	if auto_change:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_auto_timer = _rng.randf_range(auto_interval.x, auto_interval.y)
			set_weather(_pick_next())

	# Chuyển dần về thông số đích
	var p: Dictionary = PRESETS[kind]
	var step := delta / maxf(transition_time, 0.01)
	var changed := false
	for key in ["cover", "rain", "wind", "mist"]:
		var cur: float = get(key)
		var target: float = p[key]
		if not is_equal_approx(cur, target):
			set(key, move_toward(cur, target, step * maxf(absf(target - cur), 0.15) * 3.0))
			changed = true
	if changed:
		_apply()

	_update_lightning(delta)
	_follow_camera()


func _pick_next() -> String:
	return _pick_weighted(kind)


## Trọng số một kiểu thời tiết: AUTO_WEIGHTS × hệ số theo mùa (Seasons đặt `season_weights`).
func weight_of(k: String) -> float:
	return float(AUTO_WEIGHTS[k]) * float(season_weights.get(k, 1.0))


## Chọn kiểu theo AUTO_WEIGHTS, bỏ qua `exclude`.
func _pick_weighted(exclude: String) -> String:
	var total := 0.0
	for k in AUTO_WEIGHTS:
		if k != exclude:
			total += weight_of(k)
	var r := _rng.randf() * total
	for k in AUTO_WEIGHTS:
		if k == exclude:
			continue
		r -= weight_of(k)
		if r <= 0.0:
			return k
	return "clear"


func _apply() -> void:
	if day_night != null:
		day_night.weather_cover = cover
		day_night.weather_mist = mist
		day_night.refresh()
	if clouds != null:
		clouds.coverage = cover
	RenderingServer.global_shader_parameter_set("weather_wind", wind)
	RenderingServer.global_shader_parameter_set("weather_rain", rain)
	if world_environment != null:
		var env := world_environment.environment
		# Mưa và sương đều kéo vùng sương lại gần
		var murk := maxf(mist, rain * 0.6)
		env.fog_depth_begin = lerpf(_base_fog.x, mist_fog_begin, murk)
		env.fog_depth_end = lerpf(_base_fog.y, mist_fog_end, murk)
		env.fog_density = lerpf(_base_fog.z, mist_fog_max, murk)
		# Mây càng dày cảnh càng tối và bớt rực màu
		env.adjustment_saturation = lerpf(1.1, 0.68, smoothstep(0.3, 1.0, cover))
		_brightness = 1.0 - 0.38 * smoothstep(0.4, 1.0, cover)
		env.adjustment_brightness = _brightness + _flash * lightning_strength
	_set_rain_amount(rain)


# --- Mưa ----------------------------------------------------------------------------

func _set_rain_amount(r: float) -> void:
	for node in [_rain, _splash]:
		if node == null:
			continue
		var on := r > 0.01
		node.set("emitting", on)
		node.visible = on and (house_entry == null or not house_entry.inside)
		if node is GPUParticles3D:
			(node as GPUParticles3D).amount_ratio = clampf(r, 0.02, 1.0)
	# Mưa phùn: hạt ngắn, rơi chậm; giông: hạt dài, rơi nhanh, xiên theo gió
	var mat := _rain_process()
	if mat != null:
		mat.initial_velocity_min = rain_speed * lerpf(0.45, 1.0, r)
		mat.initial_velocity_max = rain_speed * lerpf(0.55, 1.15, r)
		mat.direction = Vector3(0.12 * wind, -1.0, 0.05 * wind).normalized()


func _rain_process() -> ParticleProcessMaterial:
	if _rain is GPUParticles3D:
		return (_rain as GPUParticles3D).process_material as ParticleProcessMaterial
	return null


## Mưa đi theo tâm camera ngoài sân; vùng mưa rộng theo độ xa camera.
func _follow_camera() -> void:
	if outdoor_rig == null or _rain == null:
		return
	var inside := house_entry != null and house_entry.inside
	_rain.visible = rain > 0.01 and not inside
	_splash.visible = _rain.visible
	if inside:
		return
	var c := outdoor_rig.global_position
	var extent := clampf(outdoor_rig.distance * 0.75, 25.0, 90.0)
	_rain.global_position = Vector3(c.x, rain_height, c.z)
	_splash.global_position = Vector3(c.x, 0.06, c.z)
	_set_extent(_rain, Vector3(extent, 1.0, extent))
	_set_extent(_splash, Vector3(extent, 0.0, extent))


func _set_extent(node: Node3D, ext: Vector3) -> void:
	if node is GPUParticles3D:
		var pm := (node as GPUParticles3D).process_material as ParticleProcessMaterial
		pm.emission_box_extents = ext
	elif node is CPUParticles3D:
		(node as CPUParticles3D).emission_box_extents = ext


## GPUParticles3D ở Forward+, CPUParticles3D (ít hạt hơn) ở Compatibility.
func _make_particles(node_name: String, cpu: CPUParticles3D) -> Node3D:
	cpu.name = node_name
	var node: Node3D = cpu
	if _gpu:
		var gpu := GPUParticles3D.new()
		gpu.name = node_name
		gpu.convert_from_particles(cpu)
		gpu.visibility_aabb = AABB(Vector3(-100, -30, -100), Vector3(200, 60, 200))
		gpu.local_coords = false
		cpu.free()
		node = gpu
	else:
		cpu.amount = maxi(1, int(cpu.amount * compat_particle_ratio))
	node.visible = false
	node.set("emitting", false)
	add_child(node)
	return node


func _rain_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = rain_drops
	p.lifetime = (rain_height + 2.0) / rain_speed
	p.preprocess = p.lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(45, 1, 45)
	p.direction = Vector3(0.1, -1.0, 0.05).normalized()
	p.spread = 2.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = rain_speed
	p.initial_velocity_max = rain_speed * 1.15
	# Hạt mưa: vệt mảnh dựng đứng, luôn quay về camera (billboard trục y)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.025, 0.7)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.albedo_color = Color(Palette.RAIN, 0.42)
	mat.disable_receive_shadows = true
	mesh.material = mat
	p.mesh = mesh
	return p


func _splash_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = splash_count
	p.lifetime = 0.35
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(45, 0, 45)
	p.direction = Vector3.UP
	p.spread = 0.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(Palette.RAIN, 0.6))
	ramp.set_color(1, Color(Palette.RAIN, 0.0))
	p.color_ramp = ramp
	# Vòng nước bắn: hình xuyến dẹt
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.07
	mesh.outer_radius = 0.1
	mesh.rings = 8
	mesh.ring_segments = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	mesh.material = mat
	p.mesh = mesh
	return p


# --- Chớp ---------------------------------------------------------------------------

func _update_lightning(delta: float) -> void:
	if world_environment == null:
		return
	var env := world_environment.environment
	if kind == "storm" and rain > 0.6:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = _rng.randf_range(lightning_interval.x, lightning_interval.y)
			# Một hoặc hai cú loé liền nhau
			_flash_queue = [0.0]
			if _rng.randf() < 0.6:
				_flash_queue.append(_rng.randf_range(0.12, 0.25))
	for i in range(_flash_queue.size() - 1, -1, -1):
		_flash_queue[i] -= delta
		if _flash_queue[i] <= 0.0:
			if _flash < 0.3:
				lightning.emit()
			_flash = 1.0
			_flash_queue.remove_at(i)
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	env.adjustment_brightness = _brightness + _flash * lightning_strength


## Cho công cụ chụp ảnh: loé chớp ngay.
func flash_now() -> void:
	_flash = 1.0
	if world_environment != null:
		world_environment.environment.adjustment_brightness = _brightness + lightning_strength
