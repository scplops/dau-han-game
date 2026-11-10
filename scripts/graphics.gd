class_name Graphics
extends Node
## Chất lượng đồ hoạ (mục 47): bầu trời có quầng mặt trời / trăng sao, đổ bóng tiếp xúc (SSAO), ánh sáng dội (SSIL),
## quầng sáng nhẹ (glow), sương thể tích (tia nắng, quầng đèn ban đêm), bóng mềm dần theo khoảng cách.
## Ba mức `quality`: 0 Nhẹ (như trước, cho máy yếu / Compatibility) · 1 Vừa · 2 Cao. Phím G (`cycle_quality`) đổi mức.

signal quality_changed(level: int)

const NAMES: Array[String] = ["Nhẹ", "Vừa", "Cao"]

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var day_night: DayNight
@export var terrain: Terrain
@export_range(0, 2) var quality: int = 2
@export_group("Đổ bóng tiếp xúc (SSAO)")
@export var ssao_radius: float = 1.4
@export var ssao_intensity: float = 1.7
@export var ssao_power: float = 1.6
@export_group("Quầng sáng")
@export var glow_intensity: float = 0.42
@export var glow_bloom: float = 0.03
@export var glow_threshold: float = 1.05
@export_group("Sương thể tích")
@export var volumetric_density: float = 0.0035
@export var volumetric_mist_density: float = 0.02
@export var volumetric_length: float = 140.0
@export_group("Vân bề mặt")
## Vân sần nhẹ trên đất, tường, mái (nhiễu tạo bằng code, phủ ba chiều theo toạ độ thế giới): 0 = phẳng lì như cũ.
@export_range(0.0, 0.4) var grain_strength: float = 0.16
@export var grain_scale: float = 0.45
@export_group("Mặt trời")
## Góc đĩa mặt trời (độ): bóng sắc ở chân vật, nhoè dần khi xa vật (mức Cao).
@export var sun_angular_distance: float = 0.55
@export var cloud_drift: Vector2 = Vector2(0.004, 0.0015)

var sky_material: ShaderMaterial
var _toast: Label
var _toast_t: float = 0.0
var _shift: Vector2 = Vector2.ZERO
var _sky_t: float = 0.0
var _forward: bool = true
var _grain: NoiseTexture2D
var _ground_done: bool = false


func _ready() -> void:
	_forward = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	_setup_sky()
	var layer := CanvasLayer.new()
	layer.layer = 19
	add_child(layer)
	_toast = GameKit.label(true, 20, Palette.FLOWER_YELLOW)
	_toast.add_theme_color_override("font_outline_color", Palette.WINDOW_DARK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 104.0
	_toast.visible = false
	layer.add_child(_toast)
	apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_quality"):
		set_quality((quality + 1) % NAMES.size(), true)
		get_viewport().set_input_as_handled()


func set_quality(level: int, announce: bool = false) -> void:
	quality = clampi(level, 0, NAMES.size() - 1)
	apply()
	quality_changed.emit(quality)
	if announce:
		_toast.text = "Đồ hoạ: %s%s" % [NAMES[quality], "" if _forward or quality == 0 else " (renderer Compatibility: chỉ có một phần hiệu ứng)"]
		_toast.visible = true
		_toast.modulate.a = 1.0
		_toast_t = 2.4


func quality_name() -> String:
	return NAMES[quality]


## Thay vật liệu trời mặc định bằng shader có quầng mặt trời, trăng sao, mây ti (DayNight đặt màu theo giờ).
func _setup_sky() -> void:
	if world_environment == null or world_environment.environment == null or world_environment.environment.sky == null:
		return
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader") as Shader
	var sky := world_environment.environment.sky
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if day_night != null:
		day_night.refresh()


## Bật / tắt các hiệu ứng theo mức chất lượng.
func apply() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var env := world_environment.environment
	var mid := quality >= 1
	var high := quality >= 2
	env.ssao_enabled = mid and _forward
	env.ssao_radius = ssao_radius
	env.ssao_intensity = ssao_intensity
	env.ssao_power = ssao_power
	env.ssao_light_affect = 0.25            # nắng gắt vẫn thấy chỗ khuất tối hơn một chút
	env.ssil_enabled = high and _forward
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.glow_enabled = mid
	env.glow_intensity = glow_intensity
	env.glow_bloom = glow_bloom
	env.glow_hdr_threshold = glow_threshold
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.volumetric_fog_enabled = high and _forward
	env.volumetric_fog_length = volumetric_length
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_sky_affect = 0.15
	if sun != null:
		sun.light_angular_distance = sun_angular_distance if high else 0.0
		sun.light_volumetric_fog_energy = 1.4
	if sky_material != null:
		sky_material.set_shader_parameter("cirrus", 0.35 if mid else 0.0)
		sky_material.set_shader_parameter("star_density", 0.012 if mid else 0.006)
	_apply_grain(MeshBuilder.material(), mid)
	_ground_done = false
	_update_fog()


## Phủ / gỡ lớp vân sần lên một vật liệu dùng màu đỉnh (màu đỉnh × vân, nên bảng màu chỉ sẫm đi vài phần trăm).
func _apply_grain(mat: StandardMaterial3D, on: bool) -> void:
	if mat == null:
		return
	if not on or grain_strength <= 0.0:
		mat.albedo_texture = null
		mat.uv1_triplanar = false
		return
	if _grain == null:
		var noise := FastNoiseLite.new()
		noise.seed = 4747
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.035
		noise.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1).darkened(grain_strength))
		ramp.set_color(1, Color(1, 1, 1))
		_grain = NoiseTexture2D.new()
		_grain.width = 256
		_grain.height = 256
		_grain.seamless = true
		_grain.generate_mipmaps = true
		_grain.noise = noise
		_grain.color_ramp = ramp
	mat.albedo_texture = _grain
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * grain_scale


func _update_fog() -> void:
	var env := world_environment.environment
	if not env.volumetric_fog_enabled:
		return
	var mist := day_night.weather_mist if day_night != null else 0.0
	var night := day_night.night_factor if day_night != null else 0.0
	env.volumetric_fog_density = lerpf(volumetric_density, volumetric_mist_density, mist)
	env.volumetric_fog_albedo = env.fog_light_color.lerp(Color.WHITE, 0.5)
	env.volumetric_fog_emission_energy = 0.0
	env.volumetric_fog_gi_inject = 0.0
	# Ban đêm sương bắt sáng đèn lồng, đèn cửa sổ nhiều hơn
	env.volumetric_fog_ambient_inject = lerpf(0.25, 0.08, night)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		_toast.visible = _toast_t > 0.0
	# Nền cỏ dùng vật liệu riêng do Seasons tạo trễ — phủ vân khi nó đã có
	if not _ground_done and terrain != null:
		var gm := terrain.get_node_or_null("Ground") as MeshInstance3D
		if gm != null and gm.material_override is StandardMaterial3D:
			_apply_grain(gm.material_override as StandardMaterial3D, quality >= 1)
			_ground_done = true
	_sky_t -= delta
	_shift += cloud_drift * delta
	if _sky_t <= 0.0 and world_environment != null:
		_sky_t = 0.5
		if sky_material != null:
			sky_material.set_shader_parameter("cloud_shift", _shift)
		_update_fog()
