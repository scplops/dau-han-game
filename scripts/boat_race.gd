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
## - Về đích: bảng xếp hạng + thời gian; E / Esc về bến.

signal finished(place: int, time: float)

@export var river: River
@export var first_person: FirstPerson
@export var outdoor_rig: CameraRig
@export var house_entry: HouseEntry
@export var hud: Hud
@export var dialogue: Dialogue
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
@export_group("Máy")
@export var ai_speed: Vector2 = Vector2(5.5, 6.1)
@export var random_seed: int = 1802

enum Phase { IDLE, COUNTDOWN, RACE, RESULT }

const TEAM_COLORS: Array[Color] = [Color("#c8402f"), Color("#2f6fb8"), Color("#e2b234"), Color("#3e8f4e")]
const TEAM_NAMES: Array[String] = ["Thuyền Đỏ (bạn)", "Thuyền Xanh — xóm Đông", "Thuyền Vàng — xóm Đoài", "Thuyền Lục — xóm Chợ"]

var phase: Phase = Phase.IDLE
var boats: Array[Dictionary] = []    # {node, s, lat, head, speed, stamina, done, time, paddles, boost, combo}
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


func _ready() -> void:
	_rng.seed = random_seed
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
	_course.visible = false
	# Bốn thuyền đua (neo ở vạch xuất phát khi chưa đua)
	for i in 4:
		var node := _make_boat(i)
		var paddles: Array[Node3D] = []
		for ch in node.get_children():
			if ch.name.begins_with("Paddle"):
				paddles.append(ch)
		boats.append({"node": node, "s": start_s, "lat": 0.0, "head": 0.0, "speed": 0.0, "stamina": 1.0,
				"done": false, "time": 0.0, "paddles": paddles, "boost": 0.0, "combo": 0, "stroke": 0.0, "pace": 0.0})
	_reset_boats()


func _lane(i: int) -> float:
	var hw := river.half_width(start_s)
	var gap := minf(2.6, (hw - 2.0) / 1.75)
	return (i - 1.5) * gap


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
		b.pace = _rng.randf_range(ai_speed.x, ai_speed.y)
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


# --- Bắt đầu / kết thúc --------------------------------------------------------------------------

func start() -> void:
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
	_reset_boats()
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
	_reset_boats()
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
	if phase == Phase.IDLE:
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
	if phase == Phase.IDLE:
		for b in boats:
			_place(b, Time.get_ticks_msec() / 1000.0)
		return
	match phase:
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
	_update_camera(delta)
	if _feedback_t > 0.0:
		_feedback_t -= delta
	_update_ui()


## Một bước đua: `rowing` = đang giữ W, `steer` −1…1. Tách riêng để bài thử gọi.
func step(delta: float, rowing: bool, steer: float) -> void:
	_clock += delta
	_beat_t += delta
	for i in boats.size():
		var b: Dictionary = boats[i]
		if b.done:
			b.speed = move_toward(float(b.speed), 0.0, drag * delta)
			b.s = float(b.s) + dir * float(b.speed) * delta
			continue
		var target: float
		if i == 0:
			var tired := float(b.stamina) < 0.12
			target = (tired_speed if tired else row_speed) if rowing else 0.0
			b.stamina = clampf(float(b.stamina) + (-stamina_drain if rowing else stamina_regen) * delta, 0.0, 1.0)
			b.head = clampf(float(b.head) + steer * steer_rate * delta, -0.6, 0.6)
			b.head = float(b.head) * (1.0 - 0.4 * delta)   # tự thẳng lại chút ít
		else:
			var left := course_length - absf(float(b.s) - start_s)
			var wave := 0.35 * sin(_clock * 0.7 + i * 2.1) + 0.2 * sin(_clock * 1.9 + i)
			target = float(b.pace) + wave + (0.7 if left < 60.0 else 0.0)
			# Lái về làn của mình
			var want := _lane(i)
			b.head = clampf(float(b.head) + clampf((float(b.lat) - want) * 0.25, -0.4, 0.4) * delta * 2.0 - float(b.head) * delta, -0.4, 0.4)
		b.boost = maxf(float(b.boost) - 0.8 * delta, 0.0)
		var rate := accel if target > float(b.speed) else drag
		b.speed = move_toward(float(b.speed), target, rate * delta)
		var v := float(b.speed) + float(b.boost)
		b.s = float(b.s) + dir * v * cos(float(b.head)) * delta
		b.lat = float(b.lat) - v * sin(float(b.head)) * delta
		# Bờ sông: đẩy ra, mất đà
		var lim := river.half_width(float(b.s)) - 1.4
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
			if absf(float(A.s) - float(C.s)) < 6.0 and absf(float(A.lat) - float(C.lat)) < 1.1:
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
	if boats[0].done and phase == Phase.RACE:
		_finish()


func _finish() -> void:
	phase = Phase.RESULT
	var lines: Array[String] = []
	var ranks := ["Nhất", "Nhì", "Ba", "Tư"]
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
		lines.append("%s  ·  %s  ·  %s" % [ranks[k], TEAM_NAMES[i], ("%.1f s" % t) if t > 0.0 else "còn %d m" % ceili(left)])
	var place := all.find(0) + 1
	_result_label.text = ("Thuyền bạn về %s!" % ranks[place - 1].to_lower()) + "\n\n" + "\n".join(lines) + "\n\nE / Esc: về bến"
	_result.visible = true
	finished.emit(place, float(boats[0].time))


func _animate_paddles(b: Dictionary, delta: float) -> void:
	var v := float(b.speed) + float(b.boost)
	b.stroke = float(b.stroke) + delta * (2.0 + v * 0.9) * (1.0 if v > 0.3 else 0.0)
	var k := 0
	for p: Node3D in b.paddles:
		var side := 1.0 if k % 2 == 0 else -1.0
		p.rotation.x = -0.6 * sin(float(b.stroke) * TAU / (beat_period * 2.6) + k * 0.4) if v > 0.3 else -0.2
		p.rotation.z = side * 0.35
		k += 1
	if v > 1.5 and fmod(float(b.stroke), 1.7) < delta * 3.0:
		var n := b.node as Node3D
		river.splash(n.global_position - n.global_transform.basis.z * 3.5)


func _update_camera(delta: float) -> void:
	if boats.is_empty():
		return
	var n := boats[0].node as Node3D
	var fwd := n.global_transform.basis.z   # mũi thuyền hướng +z cục bộ
	var want := n.global_position - fwd * 7.5 + Vector3(0, 3.0, 0)
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
	var box := VBoxContainer.new()
	top.add_child(box)
	_top = _label(true, 24, Palette.HUD_TEXT)
	_sub = _label(false, 16, Palette.FLOWER_YELLOW)
	for l in [_top, _sub]:
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
	_top.text = "Đua thuyền  ·  %d / %d m  ·  hạng %d / %d  ·  %.1f s" % [int(dist), int(course_length), player_place(), boats.size(), _clock]
	_sub.text = _feedback if _feedback_t > 0.0 else ("Giữ W chèo, Space theo nhịp trống!" if phase == Phase.RACE else "")
	_stamina_bar.size.x = 300.0 * float(b.stamina)
	_stamina_bar.color = Palette.LILY if float(b.stamina) > 0.25 else Palette.FLAG_RED
	_beat_dot.position.x = 300.0 * fmod(_beat_t, beat_period) / beat_period - 5.0
