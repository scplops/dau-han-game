class_name Seasons
extends Node3D
## Bốn mùa miền Bắc (mục 42), tính theo ngày dương lịch của `Calendar`:
## xuân (tháng 2–4), hạ (5–7), thu (8–10), đông (11–1); giáp ranh hai mùa thì chuyển dần trong `blend_days`.
## - Lá cây ngả màu qua biến toàn cục shader `season_leaf` / `season_mix` (wind_sway.gdshader); hoa phượng chỉ đỏ
##   mùa hạ (`season_bloom`); nền cỏ ngả màu nhẹ (vật liệu riêng của Terrain/Ground).
## - Thời tiết theo mùa: `Weather.season_weights` (xuân mưa phùn, hạ giông, thu nắng hanh, đông mây mù).
## - Lá rụng mùa thu / đông, cánh hoa bay mùa xuân (hạt quanh camera); ve kêu mùa hạ (Soundscape.cicada_level).
## - Trẻ con chỉ tắm sông khi trời ấm (Villagers.season).

signal season_changed(season: String)

const ORDER: Array[String] = ["spring", "summer", "autumn", "winter"]
const NAMES := {"spring": "Mùa xuân", "summer": "Mùa hạ", "autumn": "Mùa thu", "winter": "Mùa đông"}
## Ngày giữa mùa (thứ tự ngày trong năm): 17/3, 16/6, 16/9, 16/12.
const CENTERS := {"spring": 76.0, "summer": 167.0, "autumn": 259.0, "winter": 350.0}
## Màu lá ngả tới + mức ngả (0 = giữ màu gốc).
const LEAF := {
	"spring": [Color(0.52, 0.76, 0.30), 0.40],
	"summer": [Color(0.40, 0.60, 0.26), 0.0],
	"autumn": [Color(0.78, 0.64, 0.24), 0.42],
	"winter": [Color(0.55, 0.52, 0.32), 0.55],
}
## Màu nhân vào nền cỏ.
const GROUND := {
	"spring": Color(0.96, 1.0, 0.92), "summer": Color(1, 1, 1),
	"autumn": Color(1.0, 0.96, 0.84), "winter": Color(0.95, 0.91, 0.79),
}
## Hệ số nhân vào Weather.AUTO_WEIGHTS.
const WEATHER := {
	"spring": {"clear": 0.7, "cloudy": 1.0, "drizzle": 2.4, "storm": 0.3, "fog": 1.6},
	"summer": {"clear": 1.3, "cloudy": 0.9, "drizzle": 0.5, "storm": 2.4, "fog": 0.15},
	"autumn": {"clear": 1.5, "cloudy": 1.0, "drizzle": 0.6, "storm": 0.5, "fog": 1.0},
	"winter": {"clear": 0.6, "cloudy": 1.6, "drizzle": 1.5, "storm": 0.1, "fog": 2.2},
}
## Câu nói thêm về mùa khi hỏi chuyện thời tiết.
const TALK := {
	"spring": "Tiết xuân mưa phùn ẩm ướt, nhưng cây cối đâm chồi nảy lộc, nhìn mát cả mắt.",
	"summer": "Mùa hạ nắng như đổ lửa, ve kêu inh ỏi, chiều hay có giông đấy.",
	"autumn": "Trời thu hanh hao, gió heo may về rồi, lá bắt đầu rụng.",
	"winter": "Mùa đông gió bấc rét mướt, sáng ra sương mù mịt, ra đường nhớ mặc ấm.",
}

@export var calendar: LunarCalendar
@export var day_night: DayNight
@export var weather: Weather
@export var terrain: Terrain
@export var outdoor_rig: CameraRig
@export var house_entry: HouseEntry
@export var soundscape: Soundscape
@export var hud: Hud
@export var villagers: Villagers

## Số ngày chuyển dần quanh ngày giáp ranh hai mùa (mỗi bên một nửa).
@export var blend_days: float = 30.0
@export var update_interval: float = 1.0
## Hạt bay quanh camera (lá rụng / cánh hoa): số hạt tối đa, bán kính vùng rơi.
@export var drift_amount: int = 70
@export var drift_radius: float = 26.0
@export var drift_height: float = 9.0

var season: String = ""
## Trọng số từng mùa lúc này (tổng = 1).
var weights: Dictionary = {"spring": 0.0, "summer": 1.0, "autumn": 0.0, "winter": 0.0}
var leaf_mix: float = 0.0
var leaf_color: Color = Color(0.4, 0.6, 0.26)
var bloom: float = 1.0
var drift: float = 0.0            # mật độ hạt bay (0…1)
var _t: float = 0.0
var _last_key: int = -1
var _ground_mat: StandardMaterial3D
var _drift: CPUParticles3D
var _drift_mat: StandardMaterial3D


func _ready() -> void:
	_build_drift()
	_setup_ground.call_deferred()
	if calendar != null:
		calendar.date_changed.connect(refresh)
	refresh.call_deferred()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = update_interval
		refresh()
	# Hạt bay theo tâm camera ngoài sân, ẩn khi vào nhà / trời mưa
	if _drift != null:
		var inside := house_entry != null and house_entry.inside
		var rain := weather.rain if weather != null else 0.0
		var night := day_night != null and (day_night.time_of_day < 5.5 or day_night.time_of_day > 19.0)
		_drift.emitting = drift > 0.05 and not inside and rain < 0.3
		_drift.visible = not inside
		_drift_mat.albedo_color.a = 0.35 if night else 1.0
		if outdoor_rig != null:
			var f := outdoor_rig.global_position
			_drift.global_position = Vector3(f.x, drift_height, f.z)


## Thứ tự ngày trong năm (1…366) của ngày hiện tại.
func day_of_year() -> float:
	if calendar == null:
		return 167.0
	var s := calendar.solar()
	return float(calendar.jd - LunarCalendar.jd_from_date(1, 1, s[2]) + 1)


## Trọng số bốn mùa ở một ngày trong năm (tổng = 1): giữa mùa = 1, quanh ngày giáp ranh chuyển tuyến tính.
static func weights_at(doy: float, blend: float = 30.0) -> Dictionary:
	var out := {}
	var total := 0.0
	for k: String in ORDER:
		var d := absf(doy - float(CENTERS[k]))
		d = minf(d, 365.25 - d)
		var w := clampf((365.25 / 8.0 + blend * 0.5 - d) / maxf(blend, 0.01), 0.0, 1.0)
		out[k] = w
		total += w
	for k: String in ORDER:
		out[k] = float(out[k]) / maxf(total, 0.001)
	return out


static func season_at(doy: float) -> String:
	var w := weights_at(doy, 0.01)
	var best := "summer"
	for k: String in ORDER:
		if float(w[k]) > float(w[best]):
			best = k
	return best


func name_text() -> String:
	return str(NAMES.get(season, ""))


## Tính lại mùa theo ngày hiện tại và đẩy sang các phần khác.
func refresh() -> void:
	var doy := day_of_year()
	var key := int(doy)
	if key == _last_key:
		return
	_last_key = key
	weights = weights_at(doy, blend_days)
	var now := season_at(doy)
	# Màu lá: trung bình các màu theo (trọng số × mức ngả)
	var mix := 0.0
	var col := Vector3.ZERO
	var ground := Vector3.ZERO
	var ww := {"clear": 0.0, "cloudy": 0.0, "drizzle": 0.0, "storm": 0.0, "fog": 0.0}
	for k: String in ORDER:
		var w := float(weights[k])
		var lc: Color = LEAF[k][0]
		var m := float(LEAF[k][1]) * w
		mix += m
		col += Vector3(lc.r, lc.g, lc.b) * m
		var g: Color = GROUND[k]
		ground += Vector3(g.r, g.g, g.b) * w
		for wk: String in ww:
			ww[wk] = float(ww[wk]) + float(WEATHER[k][wk]) * w
	if mix > 0.001:
		col /= mix
	else:
		col = Vector3(0.4, 0.6, 0.26)
	leaf_mix = mix
	leaf_color = Color(col.x, col.y, col.z)
	bloom = clampf(float(weights.summer) * 1.6, 0.0, 1.0)
	drift = clampf(float(weights.autumn) * 1.0 + float(weights.winter) * 0.35 + float(weights.spring) * 0.45, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("season_leaf", col)
	RenderingServer.global_shader_parameter_set("season_mix", leaf_mix)
	RenderingServer.global_shader_parameter_set("season_bloom", bloom)
	if _ground_mat != null:
		_ground_mat.albedo_color = Color(ground.x, ground.y, ground.z)
	if _drift != null:
		var want := maxi(4, int(drift_amount * drift))
		if _drift.amount != want:
			_drift.amount = want            # đổi số hạt là phát lại từ đầu — chỉ đổi khi sang ngày khác
		# Xuân: cánh hoa hồng; thu: lá vàng; đông: lá nâu
		var petal := Color(0.95, 0.72, 0.80)
		var yellow := Color(0.85, 0.66, 0.22)
		var brown := Color(0.58, 0.44, 0.24)
		var c := yellow
		if float(weights.spring) > 0.5:
			c = petal
		elif float(weights.winter) > 0.5:
			c = brown
		_drift_mat.albedo_color = Color(c.r, c.g, c.b, _drift_mat.albedo_color.a)
	if weather != null:
		weather.season = now
		weather.season_weights = ww
	if soundscape != null:
		soundscape.cicada_level = clampf(float(weights.summer) * 1.4 - 0.2, 0.0, 1.0)
	if villagers != null:
		villagers.season = now
	if hud != null:
		hud.season_text = str(NAMES[now])
	if now != season:
		season = now
		season_changed.emit(season)


## Nền cỏ nhà mình + đồng dùng vật liệu riêng để ngả màu theo mùa (màu đỉnh × albedo).
func _setup_ground() -> void:
	if terrain == null:
		return
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.vertex_color_use_as_albedo = true
	_ground_mat.vertex_color_is_srgb = true
	_ground_mat.roughness = 1.0
	_ground_mat.metallic = 0.0
	for nm: String in ["Ground", "FlatGround"]:
		var mi := terrain.get_node_or_null(nm) as MeshInstance3D
		if mi != null:
			mi.material_override = _ground_mat
	_last_key = -1
	refresh()


## Lá rụng / cánh hoa: mảnh nhỏ xoay lảo đảo rơi chậm quanh camera (CPUParticles3D — chạy cả ở Compatibility).
func _build_drift() -> void:
	_drift = CPUParticles3D.new()
	_drift.name = "SeasonDrift"
	_drift.top_level = true
	_drift.amount = drift_amount
	_drift.lifetime = 7.0
	_drift.preprocess = 7.0
	_drift.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drift.emission_box_extents = Vector3(drift_radius, 2.5, drift_radius)
	_drift.direction = Vector3(1.0, -0.6, 0.35)
	_drift.spread = 35.0
	_drift.gravity = Vector3(0.25, -0.9, 0.1)
	_drift.initial_velocity_min = 0.4
	_drift.initial_velocity_max = 1.3
	_drift.angular_velocity_min = -160.0
	_drift.angular_velocity_max = 160.0
	_drift.angle_max = 360.0
	_drift.scale_amount_min = 0.6
	_drift.scale_amount_max = 1.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.07)
	_drift_mat = StandardMaterial3D.new()
	_drift_mat.albedo_color = Color(0.85, 0.66, 0.22)
	_drift_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_drift_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drift_mat.roughness = 1.0
	_drift_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = _drift_mat
	_drift.mesh = quad
	_drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drift.emitting = false
	add_child(_drift)
