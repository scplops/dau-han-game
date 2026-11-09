class_name BoatRace
extends Node3D
## Trò chơi dân gian Đua thuyền (mục 29). Bến đua ở bến sông `station_landing`: cột cờ, trống cái, biển
## "ĐUA THUYỀN" (vùng bấm "Đua thuyền"). Bốn thuyền đua dài sơn bốn màu đội, mỗi thuyền 4 tay chèo;
## người chơi cầm thuyền đỏ. Đường đua `course_length` m xuôi theo sông, cổng "XUẤT PHÁT" / "ĐÍCH"
## bắc ngang sông, phao báo khoảng cách mỗi 50 m.
## - Toạ độ đua: `s` = độ dài dọc tim sông (River.sample), `lat` = lệch ngang khỏi tim sông, `head` =
##   góc mũi thuyền so với chiều đua. Khúc sông cong tự đi theo, chỉ phải lái giữ làn.
## - Chèo: giữ W (cam_forward) → tốc độ lên tới `row_speed`, tốn sức (`stamina_drain` / s), thả ra hồi
##   sức. Hết sức thì chỉ chèo nổi `tired_speed`. Nhấn Space / chuột trái (fish_reel) đúng nhịp trống
##   (cách mỗi `beat_period` s, trong ±`beat_window`) → "Đều tay!": cộng `beat_boost` (giảm dần), hồi
##   chút sức, nhịp đúng liên tiếp cộng thêm; lệch nhịp thì chậm lại. A / D (cam_left/right) lái.
## - Đâm bờ / va thuyền khác: bị đẩy ra, mất đà. Máy chèo theo nhịp riêng, nước rút 60 m cuối.
## - Hai kiểu đua (chọn ở bảng lúc vào bến): thuyền rồng 4 đội (4 tay chèo / thuyền) hoặc thuyền đơn —
##   mỗi người một thuyền nhỏ, 2…`max_solo_boats` thuyền một lần chơi (`solo_speed_scale` chậm hơn).
## - Chướng ngại vật (bật / tắt ở bảng chọn, `obstacle_count`): khúc gỗ trôi dạt ngang sông (va: mất
##   nhiều đà), đám bèo tây (đi vào: chậm hẳn), hàng cọc đăng chắn một phần sông từ một bờ (va: gần như
##   đứng lại). Máy nhìn trước `ai_look_ahead` m để né, mỗi chướng ngại có `ai_miss_chance` không kịp né.
## - Về đích: bảng xếp hạng + thời gian + số lần va; E / Esc về bến.

signal finished(place: int, time: float)

@export var river: River
@export var first_person: FirstPerson
@export var outdoor_rig: CameraRig
@export var house_entry: HouseEntry
@export var hud: Hud
@export var dialogue: Dialogue
## Dân làng tự đua (không có người chơi) vào ban ngày, trời không mưa (mục 36).
@export var day_night: DayNight
@export var weather: Weather
@export_group("Dân làng tự đua")
@export var ambient_races: bool = true
## Nghỉ giữa hai cuộc đua của dân làng (giây thật).
@export var ambient_interval: Vector2 = Vector2(60.0, 150.0)
## Giờ trong ngày có đua.
@export var ambient_hours: Vector2 = Vector2(7.5, 17.3)
@export_group("")
## Bến sông đặt bến đua (chỉ số trong River.landings).
@export var station_landing: int = 2
@export var course_length: float = 300.0
@export_group("Chèo")
@export var row_speed: float = 6.4
@export var tired_speed: float = 3.4
@export var accel: float = 1.4
@export var drag: float = 0.9
@export var stamina_drain: float = 0.026
@export var stamina_regen: float = 0.12
@export var beat_period: float = 0.72
@export var beat_window: float = 0.13
@export var beat_boost: float = 0.28
## Trần cộng tốc độ do gõ trúng nhịp.
@export var boost_cap: float = 0.9
@export var steer_rate: float = 0.9
@export_group("Thuyền đơn")
@export var max_solo_boats: int = 10
@export var solo_boats_default: int = 6
## Thuyền đơn một người chèo nên chậm hơn thuyền rồng (nhân vào mọi tốc độ).
@export var solo_speed_scale: float = 0.8
@export_group("Chướng ngại vật")
@export var obstacle_count: int = 12
## Trong đám bèo chỉ đi được chừng này phần tốc độ.
@export var weed_slow: float = 0.5
@export var log_hit_keep: float = 0.35
@export var stakes_hit_keep: float = 0.12
@export_group("Máy")
@export var ai_speed: Vector2 = Vector2(5.5, 6.1)
@export var ai_look_ahead: float = 18.0
@export var ai_miss_chance: float = 0.15
@export var random_seed: int = 1802

enum Phase { IDLE, SETUP, COUNTDOWN, RACE, RESULT }

const TEAM_COLORS: Array[Color] = [Color("#c8402f"), Color("#2f6fb8"), Color("#e2b234"), Color("#3e8f4e")]
const TEAM_NAMES: Array[String] = ["Thuyền Đỏ (bạn)", "Thuyền Xanh — xóm Đông", "Thuyền Vàng — xóm Đoài", "Thuyền Lục — xóm Chợ"]
const SOLO_COLORS: Array[Color] = [Color("#c8402f"), Color("#2f6fb8"), Color("#e2b234"), Color("#3e8f4e"), Color("#8a4fb0"),
		Color("#e07b2e"), Color("#2aa3a0"), Color("#d8578f"), Color("#6b6f2a"), Color("#f2efe6")]
const SOLO_NAMES: Array[String] = ["Bạn", "Anh Tú", "Chị Lan", "Anh Hùng", "Cu Tí", "Anh Dũng", "Chị Mai", "Bác Tâm", "Anh Bình", "Cô Hoa"]
const RANKS: Array[String] = ["Nhất", "Nhì", "Ba", "Tư", "Năm", "Sáu", "Bảy", "Tám", "Chín", "Mười"]
const OBSTACLE_NAMES := {"log": "khúc gỗ trôi", "weed": "đám bèo", "stakes": "cọc đăng"}

var phase: Phase = Phase.IDLE
## Đang là cuộc đua dân làng tự đua (không camera, không giao diện; thuyền Đỏ cũng do máy chèo).
var ambient: bool = false
var _amb_wait: float = 20.0
var boats: Array[Dictionary] = []    # thuyền đang dùng (thuyền rồng hoặc thuyền đơn), [0] = người chơi
var team_boats: Array[Dictionary] = []
var solo_boats: Array[Dictionary] = []
var mode: String = "team"             # "team" | "solo"
var solo_count: int = 6
var obstacles_on: bool = true
var obstacles: Array[Dictionary] = [] # {kind, d (m từ vạch xuất phát), lat, hs, hl, base, amp, w, ph, node}
var start_s: float = 0.0
var dir: float = 1.0
var order: Array[int] = []

var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _clock: float = 0.0
var _beat_t: float = 0.0
var _from_fp: bool = false
var _cam: Camera3D
var _station: Node3D
var _course: Node3D
var _feedback: String = ""
var _feedback_t: float = 0.0
var _obs_root: Node3D
# Giao diện
var _ui: CanvasLayer
var _top: Label
var _sub: Label
var _stamina_bar: ColorRect
var _beat_bar: ColorRect
var _beat_dot: ColorRect
var _big: Label
var _result: PanelContainer
var _result_label: Label
var _top_panel: PanelContainer
var _bottom_panel: PanelContainer
var _setup: PanelContainer
var _setup_label: Label
var _warn: Label


func _ready() -> void:
	_rng.seed = random_seed
	solo_count = clampi(solo_boats_default, 2, max_solo_boats)
	_cam = Camera3D.new()
	_cam.name = "RaceCam"
	_cam.top_level = true
	_cam.fov = 60.0
	_cam.far = 1500.0
	add_child(_cam)
	_build_ui()
	if river != null and not river.landings.is_empty():
		_setup_course()


# --- Bến đua, đường đua -----------------------------------------------------------------------

func _setup_course() -> void:
	var li := clampi(station_landing, 0, river.landings.size() - 1)
	var l: Dictionary = river.landings[li]
	var e: Vector3 = l.edge
	var s_l := river.nearest_s(Vector2(e.x, e.z))
	dir = 1.0 if s_l + 25.0 + course_length < river.length - 20.0 else -1.0
	start_s = s_l + dir * 25.0
	# Bến đua: cột cờ, trống trên giá, biển tên — trên đê cạnh bến
	var n: Vector2 = (river.sample(s_l)[1] as Vector2).orthogonal()
	var c: Vector2 = river.sample(s_l)[0]
	if (Vector2(e.x, e.z) - c).dot(n) < 0.0:
		n = -n
	var spot2 := Vector2(e.x, e.z) + n * 3.4 + (river.sample(s_l)[1] as Vector2) * dir * 4.0
	var spot := Vector3(spot2.x, river.bank_height(3.4), spot2.y)
	_station = Node3D.new()
	_station.name = "RaceStation"
	add_child(_station)
	_station.global_position = spot
	var mb := MeshBuilder.new(random_seed, 0.04)
	mb.add_prism(0.06, 0.05, 5.0, 6, Palette.BAMBOO_STEM)
	for k in 3:
		mb.add_box(Vector3(0.03, 0.5 - k * 0.08, 0.8 - k * 0.12), TEAM_COLORS[k], _xf(0.0, 4.4 - k * 0.55, 0.42))
	# Trống cái trên giá gỗ
	for sx in [-0.5, 0.5]:
		mb.add_box(Vector3(0.08, 1.0, 0.08), Palette.WOOD, _xf(1.4 + sx, 0, 0))
	mb.add_box(Vector3(1.1, 0.08, 0.1), Palette.WOOD, _xf(1.4, 1.0, 0))
	var drum := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.4 + 0.42, 1.45, 0))
	mb.add_prism(0.42, 0.42, 0.84, 14, Palette.ALTAR_RED, drum)
	mb.add_prism(0.4, 0.4, 0.86, 14, Palette.PILLOW.darkened(0.1), drum * _xf(0, -0.01, 0))
	mb.add_box(Vector3(1.6, 0.6, 0.06), Palette.WOOD_LIGHT, _xf(-1.4, 1.0, 0))
	for sx in [-0.7, 0.7]:
		mb.add_box(Vector3(0.07, 1.6, 0.07), Palette.WOOD, _xf(-1.4 + sx, 0, 0))
	_station.add_child(mb.commit_instance("Station"))
	var sign := Label3D.new()
	sign.text = "ĐUA THUYỀN"
	sign.font = Hud.font(true)
	sign.font_size = 64
	sign.pixel_size = 0.004
	sign.modulate = Palette.ALTAR_RED
	sign.position = Vector3(-1.4, 1.3, 0.05)
	_station.add_child(sign)
	_station.look_at(Vector3(c.x, spot.y, c.y), Vector3.UP)
	_station.rotate_object_local(Vector3.UP, PI)
	var target := HouseEntry.make_click_target(_station, _xf(0, 1.2, 0), Vector3(4.2, 2.6, 1.4), "Đua thuyền")
	target.set_meta("activate", start)
	target.add_to_group(HouseEntry.ACTIVATE_GROUP)
	# Đường đua: cổng xuất phát / đích, phao báo khoảng cách
	_course = Node3D.new()
	_course.name = "Course"
	add_child(_course)
	_gate(start_s, "XUẤT PHÁT")
	_gate(start_s + dir * course_length, "ĐÍCH")
	var k := 50
	while k < course_length:
		_buoy(start_s + dir * k, "%d m" % k)
		k += 50
	_obs_root = Node3D.new()
	_obs_root.name = "Obstacles"
	_course.add_child(_obs_root)
	_course.visible = false
	# Bốn thuyền rồng (neo ở vạch xuất phát khi chưa đua) + thuyền đơn (ẩn tới khi đua kiểu đơn)
	for i in 4:
		team_boats.append(_boat_state(_make_boat(i), TEAM_NAMES[i], 1.0, 3.7, 0.94, false))
	for i in maxi(max_solo_boats, 2):
		var node := _make_solo_boat(i)
		node.visible = false
		solo_boats.append(_boat_state(node, SOLO_NAMES[i % SOLO_NAMES.size()] if i < SOLO_NAMES.size() else "Thuyền %d" % (i + 1),
				solo_speed_scale, 2.0, 0.66, true))
	boats = team_boats
	_reset_boats()


func _boat_state(node: Node3D, name_: String, scale: float, half_len: float, beam: float, solo: bool) -> Dictionary:
	var paddles: Array[Node3D] = []
	for ch in node.get_children():
		if ch.name.begins_with("Paddle"):
			paddles.append(ch)
	return {"node": node, "name": name_, "scale": scale, "half_len": half_len, "beam": beam, "solo": solo,
			"s": start_s, "lat": 0.0, "head": 0.0, "speed": 0.0, "stamina": 1.0, "done": false, "time": 0.0,
			"paddles": paddles, "boost": 0.0, "combo": 0, "stroke": 0.0, "pace": 0.0, "hits": 0,
			"touching": {}, "miss": {}}


## Làn của thuyền thứ i ở vị trí dọc sông `s` (mặc định vạch xuất phát): dàn đều ngang sông theo số
## thuyền, co lại ở khúc sông hẹp (làn cố định theo chỗ rộng thì làn ngoài cùng sát bờ, thuyền va bờ mãi).
func _lane(i: int, s: float = NAN) -> float:
	var n := boats.size()
	if n <= 1:
		return 0.0
	var b: Dictionary = boats[0]
	var at := start_s if is_nan(s) else s
	var lim := river.half_width(at) - (float(b.beam) * 0.5 + 1.3)
	var gap := minf(1.9 if b.solo else 2.6, 2.0 * lim / (n - 1))
	return (i - (n - 1) * 0.5) * gap


## Giới hạn lệch ngang (mép sông trừ nửa bề ngang thuyền).
func _lat_limit(b: Dictionary) -> float:
	return river.half_width(float(b.s)) - (float(b.beam) * 0.5 + 0.95)


static func _xf(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


func _reset_boats() -> void:
	for i in boats.size():
		var b: Dictionary = boats[i]
		b.s = start_s - dir * 3.0
		b.lat = _lane(i)
		b.head = 0.0
		b.speed = 0.0
		b.stamina = 1.0
		b.done = false
		b.time = 0.0
		b.boost = 0.0
		b.combo = 0
		b.hits = 0
		b.touching = {}
		b.miss = {}
		# Thuyền đơn: tay chèo khoẻ yếu chênh nhau nhiều hơn (có người sát nút người chơi)
		var lo := ai_speed.x - (0.4 if b.solo else 0.0)
		var hi := ai_speed.y + (0.25 if b.solo else 0.0)
		b.pace = _rng.randf_range(lo, hi) * float(b.scale)
		_place(b, 0.0)


func _place(b: Dictionary, t: float) -> void:
	var smp := river.sample(b.s)
	var c: Vector2 = smp[0]
	var tan: Vector2 = (smp[1] as Vector2) * dir
	var n := tan.orthogonal()
	var p := c + n * float(b.lat)
	var yaw := atan2(tan.x, tan.y) - float(b.head)
	var bob := 0.025 * sin(t * 2.0 + float(b.lat))
	(b.node as Node3D).global_position = Vector3(p.x, river.water_level - 0.08 + bob, p.y)
	(b.node as Node3D).rotation = Vector3(0, yaw, -float(b.head) * 0.15)


func _gate(s: float, text: String) -> void:
	var smp := river.sample(s)
	var c: Vector2 = smp[0]
	var n: Vector2 = (smp[1] as Vector2).orthogonal()
	var hw := river.half_width(s)
	var mb := MeshBuilder.new(random_seed + int(s), 0.04)
	var a := c + n * (hw + 1.0)
	var b := c - n * (hw + 1.0)
	for p: Vector2 in [a, b]:
		mb.add_prism(0.09, 0.07, 5.5, 6, Palette.BAMBOO_STEM, _xf(p.x, 0.2, p.y))
	var mid := (a + b) * 0.5
	var span := a - b
	var basis := Basis(Vector3.UP, -atan2(span.y, span.x))
	mb.add_box(Vector3(span.length(), 0.05, 0.05), Palette.WOOD, Transform3D(basis, Vector3(mid.x, 5.3, mid.y)))
	mb.add_box(Vector3(minf(span.length() * 0.45, 9.0), 0.9, 0.04), Palette.FLAG_RED, Transform3D(basis, Vector3(mid.x, 4.3, mid.y)))
	_course.add_child(mb.commit_instance("Gate"))
	for side in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = text
		l.font = Hud.font(true)
		l.font_size = 96
		l.pixel_size = 0.008
		l.modulate = Palette.FLOWER_YELLOW
		l.outline_size = 12
		l.outline_modulate = Palette.WINDOW_DARK
		var ang := -atan2(span.y, span.x)
		var nrm: Vector3 = Vector3(sin(ang), 0, cos(ang)) * float(side) * 0.07   # nhô ra khỏi mặt băng rôn
		l.position = Vector3(mid.x, 4.75, mid.y) + nrm
		l.rotation.y = ang + (0.0 if side > 0 else PI)
		_course.add_child(l)


func _buoy(s: float, text: String) -> void:
	var smp := river.sample(s)
	var c: Vector2 = smp[0]
	var n: Vector2 = (smp[1] as Vector2).orthogonal()
	var hw := river.half_width(s)
	var mb := MeshBuilder.new(random_seed + int(s) + 3, 0.03)
	for side: float in [-1.0, 1.0]:
		var p := c + n * side * (hw - 0.9)
		mb.add_prism(0.28, 0.2, 0.32, 8, Palette.FLAG_RED, _xf(p.x, river.water_level - 0.12, p.y))
		mb.add_prism(0.2, 0.02, 0.2, 8, Palette.FLOWER_WHITE, _xf(p.x, river.water_level + 0.2, p.y))
		var l := Label3D.new()
		l.text = text
		l.font = Hud.font(true)
		l.font_size = 48
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Palette.HUD_TEXT
		l.outline_size = 8
		l.outline_modulate = Palette.WINDOW_DARK
		l.position = Vector3(p.x, river.water_level + 0.9, p.y)
		_course.add_child(l)
	_course.add_child(mb.commit_instance("Buoys"))


## Thuyền đua dài, mũi cong, sơn màu đội, 4 tay chèo (mái chèo là node riêng để quạt theo nhịp).
func _make_boat(i: int) -> Node3D:
	var node := Node3D.new()
	node.name = "RaceBoat%d" % i
	add_child(node)
	var col := TEAM_COLORS[i]
	var mb := MeshBuilder.new(random_seed + 40 + i, 0.04)
	var L := 6.4
	mb.add_box(Vector3(0.9, 0.32, L), Palette.WOOD.darkened(0.1))
	mb.add_box(Vector3(0.94, 0.08, L + 0.02), col, _xf(0, 0.24, 0))
	for e: float in [-1.0, 1.0]:
		var tip := Transform3D(Basis(Vector3.RIGHT, e * (PI * 0.5 - 0.35)), Vector3(0, 0.1, e * L * 0.5))
		mb.add_pyramid(0.45, 1.1, 4, Palette.WOOD.darkened(0.1), tip)
	# Mũi cong như đầu rồng (khối gỗ sơn) + đuôi vểnh
	mb.add_limb(Vector3(0, 0.3, L * 0.5 + 0.6), Vector3(0, 1.1, L * 0.5 + 0.95), 0.09, 0.06, 5, col)
	mb.add_ellipsoid(Vector3(0.12, 0.1, 0.2), Palette.GOLD, _xf(0, 1.12, L * 0.5 + 1.05), 6, 3, false)
	mb.add_limb(Vector3(0, 0.3, -L * 0.5 - 0.6), Vector3(0, 0.9, -L * 0.5 - 0.85), 0.07, 0.04, 5, col)
	# Tay chèo ngồi thành hàng: thân, đầu, khăn / nón
	for k in 4:
		var z := -1.9 + k * 1.15
		var shirt := col.lightened(0.15) if k % 2 == 0 else Palette.FLOWER_WHITE
		mb.add_capsule(Vector3(0, 0.3, z), Vector3(0, 0.78, z + 0.05), 0.15, 0.13, 7, shirt)
		mb.add_ellipsoid(Vector3(0.1, 0.12, 0.1), Palette.FARMER_SKIN, _xf(0, 0.9, z + 0.06), 7, 4)
		mb.add_box(Vector3(0.22, 0.06, 0.22), col.darkened(0.2), _xf(0, 0.98, z + 0.06))
	node.add_child(mb.commit_instance("Hull"))
	var pm := MeshBuilder.new(77, 0.02)
	pm.add_limb(Vector3(0, 0, 0), Vector3(0, -0.9, 0.25), 0.02, 0.02, 4, Palette.BAMBOO_STEM)
	pm.add_box(Vector3(0.04, 0.38, 0.14), Palette.WOOD_LIGHT, _xf(0, -1.2, 0.33))
	var paddle_mesh := pm.commit()
	for k in 4:
		var p := MeshInstance3D.new()
		p.name = "Paddle%d" % k
		p.mesh = paddle_mesh
		var side := 1.0 if k % 2 == 0 else -1.0
		p.position = Vector3(side * 0.42, 0.62, -1.75 + k * 1.15)
		p.rotation.z = side * 0.35
		node.add_child(p)
	return node


## Thuyền đơn: thuyền nhỏ dài 3,4 m, một người ngồi chèo mái chèo đơn (đổi bên theo nhịp).
func _make_solo_boat(i: int) -> Node3D:
	var node := Node3D.new()
	node.name = "SoloBoat%d" % i
	add_child(node)
	var col := SOLO_COLORS[i % SOLO_COLORS.size()]
	var mb := MeshBuilder.new(random_seed + 90 + i, 0.04)
	var L := 3.4
	mb.add_box(Vector3(0.62, 0.26, L), Palette.WOOD.darkened(0.05))
	mb.add_box(Vector3(0.66, 0.06, L + 0.02), col, _xf(0, 0.2, 0))
	for e: float in [-1.0, 1.0]:
		var tip := Transform3D(Basis(Vector3.RIGHT, e * (PI * 0.5 - 0.3)), Vector3(0, 0.08, e * L * 0.5))
		mb.add_pyramid(0.31, 0.75, 4, Palette.WOOD.darkened(0.05), tip)
	mb.add_limb(Vector3(0, 0.22, L * 0.5 + 0.45), Vector3(0, 0.62, L * 0.5 + 0.62), 0.05, 0.03, 5, col)
	mb.add_box(Vector3(0.5, 0.05, 0.3), Palette.WOOD_LIGHT, _xf(0, 0.24, -0.35))   # ván ngồi
	# Người chèo: áo màu thuyền, nón lá hoặc khăn
	var shirt := col.lightened(0.2) if col.get_luminance() < 0.8 else Palette.FARMER_SHIRT
	mb.add_capsule(Vector3(0, 0.3, -0.35), Vector3(0, 0.78, -0.3), 0.15, 0.13, 7, shirt)
	mb.add_ellipsoid(Vector3(0.1, 0.12, 0.1), Palette.FARMER_SKIN, _xf(0, 0.9, -0.29), 7, 4)
	if i % 3 == 1:
		mb.add_box(Vector3(0.22, 0.06, 0.22), col.darkened(0.25), _xf(0, 0.98, -0.29))
	else:
		mb.add_prism(0.26, 0.0, 0.17, 10, Palette.HAT, _xf(0, 0.98, -0.29))
	node.add_child(mb.commit_instance("Hull"))
	var pm := MeshBuilder.new(78, 0.02)
	pm.add_limb(Vector3(0, 0, 0), Vector3(0, -0.85, 0.22), 0.02, 0.02, 4, Palette.BAMBOO_STEM)
	pm.add_box(Vector3(0.04, 0.34, 0.13), Palette.WOOD_LIGHT, _xf(0, -1.12, 0.29))
	var p := MeshInstance3D.new()
	p.name = "Paddle0"
	p.mesh = pm.commit()
	p.position = Vector3(0.34, 0.66, -0.1)
	node.add_child(p)
	return node


# --- Chướng ngại vật -------------------------------------------------------------------------------

## Rải chướng ngại dọc đường đua (mỗi lần đua một kiểu, theo `_rng`).
func _build_obstacles() -> void:
	for o in obstacles:
		(o.node as Node).queue_free()
	obstacles.clear()
	if not obstacles_on or obstacle_count <= 0:
		return
	var first := 40.0
	var span := course_length - first - 20.0
	var last_stake_side := 0.0
	for k in obstacle_count:
		var d := first + span * (k + _rng.randf_range(0.15, 0.85)) / obstacle_count
		var s := start_s + dir * d
		var hw := river.half_width(s)
		var lim := hw - 1.2
		var r := _rng.randf()
		var o := {"d": d, "base": 0.0, "amp": 0.0, "w": 0.0, "ph": _rng.randf() * TAU}
		if r < 0.42:
			o.kind = "log"
			o.hl = _rng.randf_range(0.9, 1.25)
			o.hs = 0.3
			o.base = _rng.randf_range(-lim + 1.5, lim - 1.5)
			o.amp = _rng.randf_range(0.5, 1.6)
			o.w = _rng.randf_range(0.25, 0.5)
		elif r < 0.75:
			o.kind = "weed"
			o.hl = _rng.randf_range(1.3, 2.1)
			o.hs = _rng.randf_range(1.6, 2.6)
			o.base = _rng.randf_range(-lim + o.hl, lim - o.hl)
		else:
			# Cọc đăng chắn 35–50 % bề ngang từ một bờ (đổi bờ so với hàng cọc trước để còn lối đi)
			o.kind = "stakes"
			var side := -last_stake_side if last_stake_side != 0.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
			last_stake_side = side
			var width := 2.0 * hw * _rng.randf_range(0.35, 0.5)
			o.hl = width * 0.5
			o.hs = 0.25
			o.base = side * (hw - o.hl)
		o.lat = o.base
		o.node = _obstacle_mesh(o, k)
		_obs_root.add_child(o.node)
		obstacles.append(o)
		_place_obstacle(o)
	# Mỗi thuyền máy có vài chướng ngại "không kịp né"
	for i in range(1, boats.size()):
		var miss := {}
		for k in obstacles.size():
			if _rng.randf() < ai_miss_chance:
				miss[k] = true
		boats[i].miss = miss


func _obstacle_mesh(o: Dictionary, k: int) -> Node3D:
	var mb := MeshBuilder.new(random_seed + 300 + k, 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed + 300 + k
	var hl := float(o.hl)
	var hs := float(o.hs)
	match String(o.kind):
		"log":
			var tilt := Basis(Vector3.UP, rng.randf_range(-0.25, 0.25))
			mb.add_limb(tilt * Vector3(-hl, 0.05, 0), tilt * Vector3(hl, 0.08, 0), 0.22, 0.17, 7, Palette.BANYAN_TRUNK)
			mb.add_limb(tilt * Vector3(hl * 0.3, 0.12, 0), tilt * Vector3(hl * 0.5, 0.55, 0.35), 0.07, 0.04, 5, Palette.BANYAN_TRUNK)
			mb.add_blob(Vector3(0.28, 0.2, 0.28), Palette.BANYAN_LEAF_2, rng, 0.25, Transform3D(tilt, tilt * Vector3(hl * 0.5, 0.45, 0.4)))
			mb.add_prism(0.2, 0.2, 0.02, 7, Palette.WOOD_LIGHT, Transform3D(tilt * Basis(Vector3.BACK, PI * 0.5), tilt * Vector3(hl + 0.01, 0.06, 0)))
		"weed":
			var n := int(hl * hs * 2.2) + 4
			for j in n:
				var a := rng.randf() * TAU
				var rr := sqrt(rng.randf())
				var x := cos(a) * rr * (hl - 0.3)
				var z := sin(a) * rr * (hs - 0.3)
				mb.add_blob(Vector3(0.42, 0.16, 0.42) * rng.randf_range(0.7, 1.2), Palette.HYACINTH, rng, 0.3, _xf(x, -0.04, z))
				if j % 3 == 0:
					mb.add_prism(0.06, 0.02, 0.32, 5, Palette.HYACINTH_FLOWER, _xf(x, 0.18, z))
		"stakes":
			var x := -hl
			while x <= hl + 0.01:
				var h := rng.randf_range(1.3, 1.7)
				mb.add_prism(0.05, 0.04, h, 5, Palette.BAMBOO_STEM, _xf(x, -0.4, rng.randf_range(-0.05, 0.05)))
				x += 0.45
			mb.add_box(Vector3(hl * 2.0, 0.05, 0.05), Palette.BAMBOO_NODE, _xf(0, 0.75, 0))
			mb.add_box(Vector3(hl * 2.0, 0.05, 0.05), Palette.BAMBOO_NODE, _xf(0, 0.3, 0))
			mb.add_box(Vector3(hl * 2.0, 0.5, 0.02), Color(0.36, 0.31, 0.22), _xf(0, -0.1, 0))   # lưới đăng
			# Cờ đỏ ở đầu hàng cọc phía lòng sông để báo
			var tip := -signf(float(o.base)) * hl
			mb.add_prism(0.04, 0.03, 2.3, 5, Palette.BAMBOO_STEM, _xf(tip, -0.4, 0))
			mb.add_box(Vector3(0.02, 0.32, 0.5), Palette.FLAG_RED, _xf(tip, 1.55, 0.27))
	var node := Node3D.new()
	node.name = "Obstacle_%s_%d" % [o.kind, k]
	node.add_child(mb.commit_instance("Mesh"))
	return node


## Toạ độ đua (d, lat) → thế giới; trục x cục bộ = chiều ngang sông, z = chiều đua.
func _place_obstacle(o: Dictionary) -> void:
	var s := start_s + dir * float(o.d)
	var smp := river.sample(s)
	var tan: Vector2 = (smp[1] as Vector2) * dir
	var p: Vector2 = (smp[0] as Vector2) + tan.orthogonal() * float(o.lat)
	var bob := 0.03 * sin(_clock * 1.3 + float(o.ph)) if o.kind == "log" else 0.0
	var node := o.node as Node3D
	node.global_position = Vector3(p.x, river.water_level - 0.05 + bob, p.y)
	node.rotation = Vector3(0, atan2(tan.x, tan.y), 0)


## Chướng ngại gần nhất phía trước, nằm trên đường thuyền đang đi (để nhắc người chơi).
func _obstacle_ahead(b: Dictionary, within: float) -> Dictionary:
	var d := (float(b.s) - start_s) * dir
	var best := {}
	var best_ahead := within
	for o in obstacles:
		var ahead := float(o.d) - d - float(b.half_len)
		if ahead < 0.0 or ahead > best_ahead:
			continue
		if absf(float(b.lat) - float(o.lat)) < float(o.hl) + float(b.beam) * 0.5 + 0.3:
			best = o
			best_ahead = ahead
	return best


## Làn máy muốn đi: làn của mình, né mọi chướng ngại phía trước cùng lúc (trừ cái "không kịp né"). Mỗi
## chướng ngại chặn một khoảng ngang; chọn điểm trống gần làn mình nhất (và gần chỗ đang đi). Không còn chỗ
## trống thì bỏ dần chướng ngại xa nhất. Né từng cái một thì dễ né cái sau lại lao vào cái trước.
func ai_target_lat(b: Dictionary, i: int) -> float:
	var want := _lane(i, float(b.s))
	var d := (float(b.s) - start_s) * dir
	var lim := _lat_limit(b)
	var blocks: Array = []   # [lat thấp, lat cao, khoảng cách phía trước]
	for k in obstacles.size():
		var o: Dictionary = obstacles[k]
		var ahead := float(o.d) - d
		# "Không kịp né": chỉ thấy khi đã sát mũi (va rồi mới lách ra)
		var look := float(o.hs) + float(b.half_len) + 2.5 if b.miss.get(k, false) else ai_look_ahead
		if ahead < -(float(o.hs) + float(b.half_len)) or ahead > look:
			continue
		var m := float(b.beam) * 0.5 + float(o.hl) + 0.5
		blocks.append([float(o.lat) - m, float(o.lat) + m, ahead])
	blocks.sort_custom(func(x: Array, y: Array) -> bool: return float(x[2]) < float(y[2]))
	while true:
		var best := NAN
		var best_cost := INF
		var cands: Array[float] = [want]
		for bl in blocks:
			cands.append(float(bl[0]))
			cands.append(float(bl[1]))
		for x in cands:
			if x < -lim or x > lim:
				continue
			var free := true
			for bl in blocks:
				if x > float(bl[0]) + 0.01 and x < float(bl[1]) - 0.01:
					free = false
					break
			if free:
				var cost := absf(x - want) + 0.6 * absf(x - float(b.lat))
				if cost < best_cost:
					best_cost = cost
					best = x
		if not is_nan(best) or blocks.is_empty():
			return clampf(want if is_nan(best) else best, -lim, lim)
		blocks.pop_back()
	return want


## Va chướng ngại cứng (gỗ, cọc): mất đà một lần mỗi lần chạm, đẩy ra theo phía chồng ít hơn.
func _collide_obstacles(b: Dictionary, i: int) -> void:
	var d := (float(b.s) - start_s) * dir
	for k in obstacles.size():
		var o: Dictionary = obstacles[k]
		if o.kind == "weed":
			continue
		var od := float(o.d)
		var pen_s := float(b.half_len) + float(o.hs) - absf(d - od)
		var pen_l := float(b.beam) * 0.5 + float(o.hl) - absf(float(b.lat) - float(o.lat))
		if pen_s > 0.0 and pen_l > 0.0:
			if not b.touching.has(k):
				b.touching[k] = true
				b.speed = float(b.speed) * (log_hit_keep if o.kind == "log" else stakes_hit_keep)
				b.boost = 0.0
				b.combo = 0
				b.hits = int(b.hits) + 1
				if i == 0:
					_feedback = "Va %s!" % OBSTACLE_NAMES[o.kind]
					_feedback_t = 1.0
			if pen_l < pen_s:
				var side := signf(float(b.lat) - float(o.lat))
				b.lat = float(b.lat) + (side if side != 0.0 else 1.0) * (pen_l + 0.02)
			else:
				d = od - (float(b.half_len) + float(o.hs) + 0.02) if d < od else od + (float(b.half_len) + float(o.hs) + 0.02)
				b.s = start_s + d * dir
		elif pen_s < -0.5 or pen_l < -0.3:
			b.touching.erase(k)


func _in_weed(b: Dictionary) -> bool:
	var d := (float(b.s) - start_s) * dir
	for o in obstacles:
		if o.kind == "weed" and absf(d - float(o.d)) < float(o.hs) + float(b.half_len) * 0.4 \
				and absf(float(b.lat) - float(o.lat)) < float(o.hl):
			return true
	return false


# --- Bắt đầu / kết thúc --------------------------------------------------------------------------

## Bấm vào bến đua: mở bảng chọn kiểu đua (thuyền rồng / thuyền đơn, số thuyền, chướng ngại).
func start() -> void:
	if ambient:
		_end_ambient()           # dân làng đang đua: dừng lại, người chơi vào thì đua lại từ đầu
	if phase != Phase.IDLE or boats.is_empty():
		return
	_from_fp = first_person != null and first_person.active
	if _from_fp:
		first_person._suspend("race")
	if outdoor_rig != null:
		outdoor_rig.active = false
	if house_entry != null:
		house_entry.locked = true
	if hud != null:
		hud.visible = false
	phase = Phase.SETUP
	_ui.visible = true
	_result.visible = false
	_top_panel.visible = false
	_bottom_panel.visible = false
	_big.text = ""
	_setup.visible = true
	_use_mode(mode, solo_count)
	_course.visible = true
	_cam.make_current()
	_update_camera(1.0)
	_update_setup()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Chọn bộ thuyền theo kiểu đua; thuyền không dùng thì ẩn.
func _use_mode(m: String, count: int) -> void:
	mode = m
	solo_count = clampi(count, 2, mini(max_solo_boats, solo_boats.size()))
	for b in team_boats:
		(b.node as Node3D).visible = mode == "team"
	for i in solo_boats.size():
		(solo_boats[i].node as Node3D).visible = mode == "solo" and i < solo_count
	if mode == "team":
		boats = team_boats
	else:
		boats = solo_boats.slice(0, solo_count)
	_reset_boats()


## Vào đua thật (sau bảng chọn; bài thử / công cụ chụp ảnh gọi thẳng).
func begin(m: String = "team", count: int = 4, with_obstacles: bool = true) -> void:
	if phase == Phase.IDLE:
		start()
	obstacles_on = with_obstacles
	_use_mode(m, count)
	_build_obstacles()
	_setup.visible = false
	_top_panel.visible = true
	_bottom_panel.visible = true
	_course.visible = true
	order.clear()
	phase = Phase.COUNTDOWN
	_t = 3.6
	_clock = 0.0
	_beat_t = 0.0
	_ui.visible = true
	_result.visible = false
	_cam.make_current()
	_update_camera(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func stop() -> void:
	if phase == Phase.IDLE:
		return
	phase = Phase.IDLE
	_ui.visible = false
	_course.visible = false
	obstacles_on = false
	_build_obstacles()
	_use_mode("team", solo_count)
	obstacles_on = true
	if hud != null:
		hud.visible = true
	if house_entry != null:
		house_entry.locked = false
	if _from_fp and first_person != null:
		var p := _station.global_transform * Vector3(0, 0.05, 1.8)
		first_person.global_position = p
		first_person.velocity = Vector3.ZERO
		first_person._resume()
	elif outdoor_rig != null:
		outdoor_rig.active = true
		outdoor_rig.set_focus(_station.global_position)
		outdoor_rig.camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.IDLE or ambient:
		return                 # dân làng tự đua: không nhận phím của người chơi
	if phase == Phase.SETUP:
		var used := true
		if event.is_action_pressed("dialog_1"):
			_use_mode("team", solo_count)
		elif event.is_action_pressed("dialog_2"):
			_use_mode("solo", solo_count)
		elif event.is_action_pressed("dialog_3"):
			obstacles_on = not obstacles_on
		elif event.is_action_pressed("cam_left") and mode == "solo":
			_use_mode("solo", solo_count - 1)
		elif event.is_action_pressed("cam_right") and mode == "solo":
			_use_mode("solo", solo_count + 1)
		elif event.is_action_pressed("interact") or event.is_action_pressed("fish_reel"):
			begin(mode, solo_count, obstacles_on)
		elif event.is_action_pressed("exit_interior"):
			stop()
		else:
			used = false
		if used:
			if phase == Phase.SETUP:
				_update_setup()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("exit_interior") or (phase == Phase.RESULT and event.is_action_pressed("interact")):
		stop()
		get_viewport().set_input_as_handled()
	elif phase == Phase.RACE and event.is_action_pressed("fish_reel"):
		press_beat()
		get_viewport().set_input_as_handled()


## Gõ nhịp (Space / chuột trái): trúng nhịp trống thì "Đều tay!".
func press_beat() -> void:
	if phase != Phase.RACE or boats.is_empty():
		return
	var b: Dictionary = boats[0]
	var off := fmod(_beat_t, beat_period)
	var err := minf(off, beat_period - off)
	if err <= beat_window:
		b.combo = mini(int(b.combo) + 1, 6)
		b.boost = minf(float(b.boost) + beat_boost * (1.0 + 0.12 * int(b.combo)), boost_cap)
		b.stamina = minf(float(b.stamina) + 0.02, 1.0)
		_feedback = "Đều tay!" + ("  ×%d" % int(b.combo) if int(b.combo) > 1 else "")
	else:
		b.combo = 0
		b.speed = maxf(float(b.speed) - 0.25, 0.0)
		_feedback = "Lệch nhịp!"
	_feedback_t = 0.6


# --- Mỗi khung hình --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if boats.is_empty():
		return
	if ambient:
		_process_ambient(delta)
		return
	if phase == Phase.IDLE:
		for b in boats:
			_place(b, Time.get_ticks_msec() / 1000.0)
		if ambient_ok():
			_amb_wait -= delta
			if _amb_wait <= 0.0:
				begin_ambient()
		return
	match phase:
		Phase.SETUP:
			_clock += delta
		Phase.COUNTDOWN:
			_t -= delta
			_big.text = str(int(ceil(_t - 0.6))) if _t > 0.6 else "Bắt đầu!"
			if _t <= 0.0:
				phase = Phase.RACE
				_big.text = ""
		Phase.RACE:
			step(delta, Input.is_action_pressed("cam_forward"),
					Input.get_axis("cam_left", "cam_right"))
		Phase.RESULT:
			pass
	for b in boats:
		_place(b, _clock)
		_animate_paddles(b, delta)
	for o in obstacles:
		_place_obstacle(o)
	_update_camera(delta)
	if _feedback_t > 0.0:
		_feedback_t -= delta
	if phase != Phase.SETUP:
		_update_ui()


## Một bước đua: `rowing` = đang giữ W, `steer` −1…1. Tách riêng để bài thử gọi.
func step(delta: float, rowing: bool, steer: float) -> void:
	_clock += delta
	_beat_t += delta
	for o in obstacles:
		if o.kind == "log":   # khúc gỗ dạt qua dạt lại theo dòng
			o.lat = float(o.base) + float(o.amp) * sin(_clock * float(o.w) + float(o.ph))
	for i in boats.size():
		var b: Dictionary = boats[i]
		if b.done:
			b.speed = move_toward(float(b.speed), 0.0, drag * delta)
			b.s = float(b.s) + dir * float(b.speed) * delta
			continue
		var target: float
		var sc := float(b.scale)
		if i == 0 and not ambient:
			var tired := float(b.stamina) < 0.12
			target = ((tired_speed if tired else row_speed) if rowing else 0.0) * sc
			b.stamina = clampf(float(b.stamina) + (-stamina_drain if rowing else stamina_regen) * delta, 0.0, 1.0)
			b.head = clampf(float(b.head) + steer * steer_rate * delta, -0.6, 0.6)
			b.head = float(b.head) * (1.0 - 0.4 * delta)   # tự thẳng lại chút ít
		else:
			var left := course_length - absf(float(b.s) - start_s)
			var wave := 0.35 * sin(_clock * 0.7 + i * 2.1) + 0.2 * sin(_clock * 1.9 + i)
			target = float(b.pace) + (wave + (0.7 if left < 60.0 else 0.0)) * sc
			# Lái về làn của mình, né chướng ngại phía trước
			var want := ai_target_lat(b, i)
			var head_want := clampf((float(b.lat) - want) * 0.35, -0.45, 0.45)
			b.head = move_toward(float(b.head), head_want, 1.3 * delta)
		var weed := _in_weed(b)
		if weed:
			target *= weed_slow
			if i == 0 and _feedback_t <= 0.0:
				_feedback = "Vướng bèo!"
				_feedback_t = 0.4
		b.boost = maxf(float(b.boost) - 0.8 * delta, 0.0)
		var rate := accel if target > float(b.speed) else (drag * (3.0 if weed else 1.0))
		b.speed = move_toward(float(b.speed), target, rate * delta)
		var v := float(b.speed) + float(b.boost) * sc * (weed_slow if weed else 1.0)
		b.s = float(b.s) + dir * v * cos(float(b.head)) * delta
		b.lat = float(b.lat) - v * sin(float(b.head)) * delta
		# Bờ sông: đẩy ra, mất đà
		_collide_obstacles(b, i)
		var lim := _lat_limit(b)
		if absf(float(b.lat)) > lim:
			b.lat = signf(float(b.lat)) * lim
			# Mũi đâm vào bờ bao nhiêu thì mất đà bấy nhiêu (mỗi lần va chỉ tính một lần)
			var into := -signf(float(b.lat)) * sin(float(b.head))
			if into > 0.0:
				b.head = -float(b.head) * 0.3
				if not b.get("touch", false):
					b.speed = float(b.speed) * (1.0 - clampf(into * 1.6, 0.15, 0.6))
					if i == 0:
						_feedback = "Va bờ!"
						_feedback_t = 0.8
			b.touch = true
		else:
			b.touch = false
		# Về đích
		if absf(float(b.s) - start_s) >= course_length and not b.done:
			b.done = true
			b.time = _clock
			order.append(i)
	# Va nhau: đẩy ra hai bên, cùng chậm lại
	for a in boats.size():
		for c in range(a + 1, boats.size()):
			var A: Dictionary = boats[a]
			var C: Dictionary = boats[c]
			if absf(float(A.s) - float(C.s)) < float(A.half_len) + float(C.half_len) - 0.6 \
					and absf(float(A.lat) - float(C.lat)) < (float(A.beam) + float(C.beam)) * 0.5 + 0.15:
				var push := signf(float(A.lat) - float(C.lat))
				if push == 0.0:
					push = 1.0
				A.lat = float(A.lat) + push * 0.6 * delta * 4.0
				C.lat = float(C.lat) - push * 0.6 * delta * 4.0
				A.speed = float(A.speed) * (1.0 - 0.6 * delta)
				C.speed = float(C.speed) * (1.0 - 0.6 * delta)
				if a == 0:
					_feedback = "Va thuyền!"
					_feedback_t = 0.6
	if boats[0].done and phase == Phase.RACE and not ambient:
		_finish()


func _finish() -> void:
	phase = Phase.RESULT
	var lines: Array[String] = []
	var all := order.duplicate()
	# Thuyền chưa về: xếp theo quãng đã đi
	var rest: Array = []
	for i in boats.size():
		if not all.has(i):
			rest.append(i)
	rest.sort_custom(func(a: int, b: int) -> bool: return absf(float(boats[a].s) - start_s) > absf(float(boats[b].s) - start_s))
	all.append_array(rest)
	for k in all.size():
		var i: int = all[k]
		var t := float(boats[i].time)
		var left := course_length - absf(float(boats[i].s) - start_s)
		var nm: String = boats[i].name
		if i == 0 and mode == "solo":
			nm = "Bạn"
		var hits := int(boats[i].hits)
		lines.append("%s  ·  %s  ·  %s%s" % [RANKS[k] if k < RANKS.size() else str(k + 1), nm,
				("%.1f s" % t) if t > 0.0 else "còn %d m" % ceili(left), ("  ·  va %d lần" % hits) if obstacles_on and hits > 0 else ""])
	var place := all.find(0) + 1
	var title := ("Thuyền bạn về %s!" if mode == "team" else "Bạn về %s!") % (RANKS[place - 1] if place <= RANKS.size() else str(place)).to_lower()
	_result_label.text = title + "\n\n" + "\n".join(lines) + "\n\nE / Esc: về bến"
	_result.visible = true
	finished.emit(place, float(boats[0].time))


func _animate_paddles(b: Dictionary, delta: float) -> void:
	var v := float(b.speed) + float(b.boost)
	b.stroke = float(b.stroke) + delta * (2.0 + v * 0.9) * (1.0 if v > 0.3 else 0.0)
	var k := 0
	var ph := float(b.stroke) * TAU / (beat_period * 2.6)
	for p: Node3D in b.paddles:
		var side := 1.0 if k % 2 == 0 else -1.0
		if b.solo:   # mái chèo đơn đổi bên mỗi nhát
			side = 1.0 if fmod(ph / TAU, 2.0) < 1.0 else -1.0
			p.position.x = side * 0.34
		p.rotation.x = -0.6 * sin(ph + k * 0.4) if v > 0.3 else -0.2
		p.rotation.z = side * 0.35
		k += 1
	if v > 1.5 and fmod(float(b.stroke), 1.7) < delta * 3.0:
		var n := b.node as Node3D
		river.splash(n.global_position - n.global_transform.basis.z * (float(b.half_len) - 0.2))


func _update_camera(delta: float) -> void:
	if boats.is_empty():
		return
	var n := boats[0].node as Node3D
	var fwd := n.global_transform.basis.z   # mũi thuyền hướng +z cục bộ
	var hl := float(boats[0].half_len)
	var want := n.global_position - fwd * (3.8 + hl) + Vector3(0, 1.6 + hl * 0.38, 0)
	var t := 1.0 - exp(-4.0 * delta)
	_cam.global_position = _cam.global_position.lerp(want, t) if delta < 0.9 else want
	_cam.look_at(n.global_position + fwd * 7.0 + Vector3(0, 0.6, 0), Vector3.UP)


# --- Giao diện ------------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style())
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 16
	_ui.add_child(top)
	_top_panel = top
	var box := VBoxContainer.new()
	top.add_child(box)
	_top = _label(true, 24, Palette.HUD_TEXT)
	_sub = _label(false, 16, Palette.FLOWER_YELLOW)
	_warn = _label(true, 18, Color("#ff8a70"))
	for l in [_top, _sub, _warn]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	# Thanh sức + thước nhịp trống (góc dưới trái)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 20
	panel.offset_bottom = -20
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(panel)
	_bottom_panel = panel
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(320, 0)
	panel.add_child(col)
	col.add_child(_label(false, 15, Palette.HUD_SUBTEXT, "Sức chèo (giữ W)"))
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.custom_minimum_size = Vector2(300, 14)
	bg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bg)
	_stamina_bar = ColorRect.new()
	_stamina_bar.color = Palette.LILY
	_stamina_bar.size = Vector2(300, 14)
	bg.add_child(_stamina_bar)
	col.add_child(_label(false, 15, Palette.HUD_SUBTEXT, "Nhịp trống (Space đúng lúc chấm tới vạch)"))
	_beat_bar = ColorRect.new()
	_beat_bar.color = Color(0, 0, 0, 0.4)
	_beat_bar.custom_minimum_size = Vector2(300, 18)
	_beat_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_beat_bar)
	var zone := ColorRect.new()
	zone.color = Color(Palette.FLOWER_YELLOW, 0.45)
	zone.position = Vector2(300 - 300 * beat_window / beat_period, 0)
	zone.size = Vector2(300 * beat_window / beat_period, 18)
	_beat_bar.add_child(zone)
	_beat_dot = ColorRect.new()
	_beat_dot.color = Palette.FLAG_RED
	_beat_dot.size = Vector2(10, 18)
	_beat_bar.add_child(_beat_dot)
	col.add_child(_label(false, 14, Palette.HUD_SUBTEXT, "A / D: lái  ·  Esc: bỏ cuộc"))
	_big = _label(true, 96, Palette.HUD_TEXT)
	_big.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.add_theme_constant_override("outline_size", 14)
	_big.add_theme_color_override("font_outline_color", Palette.WINDOW_DARK)
	_ui.add_child(_big)
	_result = PanelContainer.new()
	_result.add_theme_stylebox_override("panel", _style())
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result.visible = false
	_ui.add_child(_result)
	_result_label = _label(true, 22, Palette.HUD_TEXT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_child(_result_label)
	# Bảng chọn kiểu đua
	_setup = PanelContainer.new()
	_setup.add_theme_stylebox_override("panel", _style())
	_setup.set_anchors_preset(Control.PRESET_CENTER)
	_setup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_setup.grow_vertical = Control.GROW_DIRECTION_BOTH
	_setup.visible = false
	_ui.add_child(_setup)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 8)
	_setup.add_child(sbox)
	var title := _label(true, 30, Palette.FLOWER_YELLOW, "ĐUA THUYỀN")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sbox.add_child(title)
	_setup_label = _label(false, 20, Palette.HUD_TEXT)
	_setup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sbox.add_child(_setup_label)
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	sbox.add_child(row1)
	row1.add_child(_button("1 · Thuyền rồng", func() -> void: _use_mode("team", solo_count); _update_setup()))
	row1.add_child(_button("2 · Thuyền đơn", func() -> void: _use_mode("solo", solo_count); _update_setup()))
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	sbox.add_child(row2)
	row2.add_child(_button("◀ Bớt thuyền (A)", func() -> void: _use_mode("solo", solo_count - 1); _update_setup()))
	row2.add_child(_button("Thêm thuyền (D) ▶", func() -> void: _use_mode("solo", solo_count + 1); _update_setup()))
	row2.add_child(_button("3 · Chướng ngại vật", func() -> void: obstacles_on = not obstacles_on; _update_setup()))
	var row3 := HBoxContainer.new()
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	sbox.add_child(row3)
	row3.add_child(_button("Bắt đầu (E)", func() -> void: begin(mode, solo_count, obstacles_on)))
	row3.add_child(_button("Thôi (Esc)", stop))


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Hud.font(true))
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func _update_setup() -> void:
	var kind := "Thuyền rồng — 4 đội, mỗi thuyền 4 tay chèo, bạn cầm thuyền Đỏ" if mode == "team" \
			else "Thuyền đơn — mỗi người một thuyền, %d thuyền (tối đa %d)" % [solo_count, mini(max_solo_boats, solo_boats.size())]
	var obs := "Chướng ngại vật: CÓ (khúc gỗ trôi, đám bèo, cọc đăng)" if obstacles_on else "Chướng ngại vật: KHÔNG"
	_setup_label.text = "%s\n%s\n\n1 / 2: kiểu đua  ·  A / D: số thuyền đơn  ·  3: chướng ngại  ·  E: bắt đầu  ·  Esc: thôi" % [kind, obs]


func _style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _label(bold: bool, size: int, col: Color, text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Hud.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Hạng hiện tại của thuyền người chơi (1 = dẫn đầu).
func player_place() -> int:
	var mine := absf(float(boats[0].s) - start_s)
	var p := 1
	for i in range(1, boats.size()):
		if absf(float(boats[i].s) - start_s) > mine:
			p += 1
	return p


func _update_ui() -> void:
	if boats.is_empty():
		return
	var b: Dictionary = boats[0]
	var dist := clampf(absf(float(b.s) - start_s), 0.0, course_length)
	_top.text = ("Đua thuyền rồng" if mode == "team" else "Đua thuyền đơn") + ("  ·  %d / %d m  ·  hạng %d / %d  ·  %.1f s" % [int(dist), int(course_length), player_place(), boats.size(), _clock])
	var warn := ""
	if phase == Phase.RACE:
		var o := _obstacle_ahead(b, 30.0)
		if not o.is_empty():
			warn = "Phía trước: %s! (A / D để né)" % OBSTACLE_NAMES[o.kind]
	_warn.text = warn
	_warn.visible = warn != ""
	_sub.text = _feedback if _feedback_t > 0.0 else ("Giữ W chèo, Space theo nhịp trống!" if phase == Phase.RACE else "")
	_stamina_bar.size.x = 300.0 * float(b.stamina)
	_stamina_bar.color = Palette.LILY if float(b.stamina) > 0.25 else Palette.FLAG_RED
	_beat_dot.position.x = 300.0 * fmod(_beat_t, beat_period) / beat_period - 5.0

# --- Dân làng tự đua ---------------------------------------------------------------------------------

func ambient_ok() -> bool:
	if not ambient_races or day_night == null:
		return false
	var h := day_night.time_of_day
	if h < ambient_hours.x or h >= ambient_hours.y:
		return false
	return weather == null or not weather.kind in ["drizzle", "storm", "fog"]


## Bốn thuyền rồng của bốn xóm đua với nhau (không chướng ngại), xong thì về lại vạch xuất phát.
func begin_ambient() -> void:
	if phase != Phase.IDLE or boats.is_empty():
		return
	ambient = true
	obstacles_on = false
	_use_mode("team", solo_count)
	_build_obstacles()
	_course.visible = true
	order.clear()
	phase = Phase.COUNTDOWN
	_t = 3.6
	_clock = 0.0
	_beat_t = 0.0


func _process_ambient(delta: float) -> void:
	match phase:
		Phase.COUNTDOWN:
			_t -= delta
			if _t <= 0.0:
				phase = Phase.RACE
		Phase.RACE:
			step(delta, false, 0.0)
			if order.size() >= boats.size():
				phase = Phase.RESULT
				_t = 10.0
		Phase.RESULT:
			_clock += delta
			_t -= delta
			for b in boats:
				b.speed = move_toward(float(b.speed), 0.0, drag * delta)
			if _t <= 0.0:
				_end_ambient()
				return
	if not ambient_ok() and phase == Phase.COUNTDOWN:
		_end_ambient()
		return
	for b in boats:
		_place(b, _clock)
		_animate_paddles(b, delta)


func _end_ambient() -> void:
	ambient = false
	phase = Phase.IDLE
	_course.visible = false
	obstacles_on = true
	order.clear()
	_use_mode("team", solo_count)    # về lại vạch xuất phát
	_amb_wait = _rng.randf_range(ambient_interval.x, ambient_interval.y)

