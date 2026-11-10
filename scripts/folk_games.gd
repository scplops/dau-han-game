class_name FolkGames
extends Node3D
## Năm trò chơi dân gian nhỏ của trẻ con (mục 44): đá cầu, bắn bi, chơi chuyền, bịt mắt bắt dê, rồng rắn lên mây.
## - Trẻ con tự chơi: việc `folk` của Villagers → `site_target` chọn trò còn thiếu người → `on_arrive` vào nhóm ở bãi
##   của trò đó; đủ người thì chơi, hết `game_seconds` thì tan.
## - Người chơi: nhìn một đứa đang chơi "E: Xin chơi … cùng" (`join_at` — chơi lại từ đầu) hoặc rủ qua hội thoại
##   (`start_with(v, kind)`, bày trò ngay trước mặt). Esc thôi chơi.
## - Mỗi nhóm là một từ điển (`groups`): kind, center, members (Villager; người chơi là hình nhân `_avatar`), st (trạng
##   thái riêng từng trò). `step(g, dt)` tách riêng cho bài thử.

signal finished(kind: String, score: int)

const KINDS := {
	"da_cau": {"name": "đá cầu", "min": 3, "max": 4, "weight": 1.2},
	"ban_bi": {"name": "bắn bi", "min": 2, "max": 3, "weight": 1.0},
	"chuyen": {"name": "chơi chuyền", "min": 2, "max": 3, "weight": 1.0},
	"bit_mat": {"name": "bịt mắt bắt dê", "min": 4, "max": 6, "weight": 1.2},
	"rong_ran": {"name": "rồng rắn lên mây", "min": 5, "max": 7, "weight": 1.2},
}
const ORDER: Array[String] = ["da_cau", "ban_bi", "chuyen", "bit_mat", "rong_ran"]
const TEMP_NAMES: Array[String] = ["Cu Tèo", "Bé Mận", "Cu Đen", "Bé Hoa", "Cu Tí", "Bé Sen", "Cu Bờm", "Bé Thơm"]
const CHANT: Array[String] = ["Rồng rắn lên mây…", "Có cây núc nác…", "Có nhà hiển vinh…", "Thầy thuốc có nhà hay không?"]

@export var villagers: Villagers
@export var first_person: FirstPerson
@export var dialogue: Dialogue
@export var hud: Hud
@export var day_night: DayNight
@export var weather: Weather
## Bãi chơi từng trò (cỏ trống quanh cổng làng và nhà mình).
@export var sites: Dictionary = {
	"da_cau": Vector3(-6.0, 0.05, -21.5), "ban_bi": Vector3(-12.5, 0.05, -22.5), "chuyen": Vector3(-36.0, 0.05, -26.5),
	"bit_mat": Vector3(0.5, 0.05, -2.0), "rong_ran": Vector3(21.0, 0.05, -9.0),
}
@export var game_seconds: Vector2 = Vector2(50.0, 90.0)
@export var gather_wait: float = 40.0
@export_group("Đá cầu")
@export var cau_radius: float = 1.7
@export var cau_flight: Vector2 = Vector2(0.95, 1.2)
@export var cau_window: float = 0.14
@export var cau_miss: float = 0.12
@export_group("Bắn bi")
@export var bi_ring: float = 0.55
@export var bi_line: float = 2.2
@export var bi_speed: Vector2 = Vector2(2.4, 5.2)
@export var bi_friction: float = 2.4
@export var bi_radius: float = 0.045
@export_group("Chơi chuyền")
@export var chuyen_flight: float = 1.15
@export var chuyen_max_ban: int = 5
@export_group("Bịt mắt bắt dê")
@export var goat_ring: float = 2.6
@export var catcher_speed: float = 1.35
@export var goat_speed: float = 1.5
@export var catch_dist: float = 0.55
@export var blind_seconds: float = 60.0
@export_group("Rồng rắn")
@export var dragon_ring: float = 4.5
@export var dragon_gap: float = 0.62
@export var doctor_speed: float = 2.5
@export var head_speed: float = 2.1
@export var chase_seconds: float = 30.0
@export var player_speed: float = 3.0
@export var random_seed: int = 4444

var groups: Array[Dictionary] = []
var pg: Dictionary = {}                 # nhóm người chơi đang chơi cùng
var stats: Dictionary = {}              # đếm sự kiện từng trò (bài thử đọc)
var _rng := RandomNumberGenerator.new()
var _avatar: Villager
var _temps: Array[Villager] = []
var _cam: Camera3D
var _cam_dir: Vector3 = Vector3(0, 0, 1)
var _ui: CanvasLayer
var _top: Label
var _sub: Label
var _big: Label
var _dark: ColorRect
var _bar: ColorRect
var _fill: ColorRect
var _hear: Array[Label] = []
var _msg: String = ""
var _msg_t: float = 0.0
var _charging: bool = false


func _ready() -> void:
	_rng.seed = random_seed
	_cam = Camera3D.new()
	_cam.name = "FolkCam"
	_cam.top_level = true
	_cam.fov = 55.0
	add_child(_cam)
	_build_ui()


func _stat(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n


# --- Trẻ con tự chơi -----------------------------------------------------------------------------

func ambient_ok(h: float) -> bool:
	if h < 7.0 or h >= 17.6 or (h >= 11.0 and h < 13.0):
		return false
	return weather == null or not weather.kind in ["storm", "drizzle"]


func _group_of_kind(kind: String) -> Dictionary:
	for g in groups:
		if str(g.kind) == kind and bool(g.site):
			return g
	return {}


## Chọn trò cho một đứa trẻ (ưu tiên nhóm đang thiếu người) và trả về chỗ đứng chờ ở bãi đó.
func site_target(v: Villager) -> Vector3:
	var best := ""
	var best_w := -1.0
	for kind: String in ORDER:
		var g := _group_of_kind(kind)
		var n := (g.members as Array).size() if not g.is_empty() else 0
		if n >= int(KINDS[kind].max) or (not g.is_empty() and bool(g.get("player", false))):
			continue
		var d := (sites[kind] as Vector3).distance_to(v.global_position)
		var w := float(KINDS[kind].weight) * (2.5 if n > 0 and n < int(KINDS[kind].min) else 1.0) * _rng.randf_range(0.5, 1.5) / (1.0 + d / 80.0)
		if kind == "chuyen" and not v.get_meta("female", false):
			w *= 0.25           # chơi chuyền là trò của con gái
		if kind == "ban_bi" and v.get_meta("female", false):
			w *= 0.3
		if w > best_w:
			best_w = w
			best = kind
	if best == "":
		best = "da_cau"
	v.set_meta("folk_kind", best)
	return (sites[best] as Vector3) + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))


## Villagers gọi khi một đứa tới bãi.
func on_arrive(v: Villager) -> void:
	var kind := str(v.get_meta("folk_kind", "da_cau"))
	var g := _group_of_kind(kind)
	if g.is_empty():
		g = _new_group(kind, sites[kind] as Vector3, true)
	if (g.members as Array).size() >= int(KINDS[kind].max):
		v.dwell = 0.0
		return
	_add_member(g, v)


func is_member(v: Villager) -> bool:
	return v != null and v.has_meta("folk")


func kind_name(v: Villager) -> String:
	return str(KINDS[str(v.get_meta("folk", "da_cau"))].name)


func _new_group(kind: String, center: Vector3, site: bool) -> Dictionary:
	var g := {"kind": kind, "center": center, "members": [], "t": 0.0, "wait": 0.0, "site": site, "player": false,
			"started": false, "t_left": _rng.randf_range(game_seconds.x, game_seconds.y), "st": {}, "pi": -1}
	var root := Node3D.new()
	root.name = "Folk_" + kind
	root.top_level = true
	add_child(root)
	root.global_position = center
	g["root"] = root
	_build_props(g)
	groups.append(g)
	return g


func _add_member(g: Dictionary, v: Villager) -> void:
	v.set_meta("folk", str(g.kind))
	v.set_meta("talking", true)
	v.state = Villager.State.IDLE
	v.visible = true
	v.dwell = 1.0e6
	v.work_anim = "idle"
	if v.prop_node != null:
		v.prop_node.visible = false
	v.activity_text = "đang chơi " + str(KINDS[str(g.kind)].name)
	(g.members as Array).append(v)


func _end_group(g: Dictionary) -> void:
	for v: Villager in g.members:
		if not is_instance_valid(v) or v == _avatar:
			continue
		_release(v)
	(g.root as Node).queue_free()
	groups.erase(g)


func _release(v: Villager) -> void:
	v.remove_meta("folk")
	v.remove_meta("talking")
	var bf := v.get_node_or_null("Blindfold")
	if bf != null:
		v.remove_child(bf)
		bf.queue_free()
	if v.prop_node != null:
		v.prop_node.visible = true
	v.work_anim = "idle"
	if _temps.has(v):
		_temps.erase(v)
		v.queue_free()
	else:
		v.dwell = 0.0


# --- Người chơi ------------------------------------------------------------------------------------

func refusal(v: Villager) -> String:
	if not v.role in ["kid", "herder"]:
		return "Trò trẻ con ấy mà, rủ bọn trẻ chơi đi."
	if v.has_meta("in_class"):
		return "Đang giờ học mà {you}!"
	var h := day_night.time_of_day if day_night != null else 15.0
	if h >= 19.0 or h < 6.0:
		return "Tối rồi, mai chơi nhé!"
	if weather != null and weather.kind in ["storm", "drizzle"]:
		return "Mưa ướt hết, không chơi được đâu!"
	if v.state == Villager.State.WALK and v.activity in ["school", "graze"]:
		return "{Self} đang phải đi, lúc khác chơi nhé!"
	return ""


## Nhìn một đứa đang chơi + E: vào chơi cùng (chơi lại từ đầu).
func join_at(v: Villager) -> void:
	for g in groups:
		if (g.members as Array).has(v):
			_start_player(g)
			return


## Rủ qua hội thoại: bày trò ngay trước mặt người chơi.
func start_with(v: Villager, kind: String) -> void:
	if not pg.is_empty() or first_person == null:
		return
	if is_member(v):
		join_at(v)
		return
	var fp := first_person.global_position
	var fwd := -first_person.global_transform.basis.z
	fwd.y = 0.0
	var center := fp + fwd.normalized() * (2.2 if kind in ["chuyen", "ban_bi", "da_cau"] else 4.0)
	center.y = fp.y
	var g := _new_group(kind, center, false)
	_add_member(g, v)
	var need := int(KINDS[kind].min) - 1          # người chơi tính là một
	if villagers != null:
		var near: Array[Villager] = []
		for p in villagers.people:
			if p != v and p.visible and p.role in ["kid", "herder"] and p.global_position.distance_to(center) < 30.0 \
					and not p.has_meta("talking") and not p.has_meta("at_school") and refusal(p) == "":
				near.append(p)
		near.sort_custom(func(a: Villager, b: Villager) -> bool: return a.global_position.distance_to(center) < b.global_position.distance_to(center))
		for p in near.slice(0, maxi(0, int(KINDS[kind].max) - 2)):
			_add_member(g, p)
	var k := 0
	while (g.members as Array).size() < need:
		_add_member(g, _make_temp(k, center))
		k += 1
	_start_player(g)


func _start_player(g: Dictionary) -> void:
	if not pg.is_empty():
		return
	pg = g
	g.player = true
	g.t_left = 1.0e9
	var members: Array = g.members
	while members.size() >= int(KINDS[str(g.kind)].max) and members.size() > 1:
		_release(members.pop_back() as Villager)       # nhường một chỗ cho người chơi
	var fp := first_person.global_position
	_cam_dir = fp - (g.center as Vector3)
	_cam_dir.y = 0.0
	_cam_dir = _cam_dir.normalized() if _cam_dir.length() > 0.5 else Vector3(0, 0, 1)
	first_person._suspend("folk")
	if _avatar == null:
		_avatar = _make_avatar()
	_avatar.visible = true
	_avatar.global_position = Vector3(fp.x, (g.center as Vector3).y, fp.z)
	members.push_front(_avatar)
	g.pi = 0
	_restart(g)
	for m: Villager in members:
		if m != _avatar:
			_bark(m, "Chơi lại từ đầu nhé! {You} vào đây!")
			break
	if hud != null:
		hud.visible = false
	_ui.visible = true
	_cam.make_current()
	_update_camera(g, 1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func stop_player() -> void:
	if pg.is_empty():
		return
	var g := pg
	pg = {}
	finished.emit(str(g.kind), int((g.st as Dictionary).get("score", 0)))
	(g.members as Array).erase(_avatar)
	var bf := _avatar.get_node_or_null("Blindfold")
	if bf != null:
		_avatar.remove_child(bf)
		bf.queue_free()
	g.player = false
	g.pi = -1
	_avatar.visible = false
	_ui.visible = false
	_dark.visible = false
	Engine.time_scale = 1.0
	if hud != null:
		hud.visible = true
	if bool(g.site) and (g.members as Array).size() >= int(KINDS[str(g.kind)].min):
		g.t_left = _rng.randf_range(20.0, 40.0)
		_restart(g)
	else:
		_end_group(g)
	first_person._resume()


func _make_avatar() -> Villager:
	return GameKit.make_avatar(self, villagers, dialogue, "FolkPlayer", 0.9)


func _make_temp(k: int, center: Vector3) -> Villager:
	var t := GameKit.make_person(self, villagers, "FolkKid%d" % k, "kid", TEMP_NAMES[(k + _rng.randi_range(0, 7)) % TEMP_NAMES.size()],
			_rng.randf() < 0.5, {"role_name": "Trẻ con nhà bên", "home_name": "Nhà bên", "keep_hat": true})
	var a := _rng.randf() * TAU
	t.global_position = center + Vector3(cos(a), 0, sin(a)) * 7.0
	_temps.append(t)
	return t


func _unhandled_input(event: InputEvent) -> void:
	if pg.is_empty():
		return
	if event.is_action_pressed("exit_interior"):
		stop_player()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fish_reel"):
		press()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("fish_reel"):
		release()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and bool((pg.st as Dictionary).get("over", false)):
		_restart(pg)
		get_viewport().set_input_as_handled()


func _say(text: String, t: float = 0.9) -> void:
	_msg = text
	_msg_t = t


func _bark(v: Villager, text: String) -> void:
	if dialogue != null and is_instance_valid(v) and v != _avatar:
		dialogue.bark(v, dialogue.fill_for(v, text))


func _name(v: Villager) -> String:
	return "Bạn" if v == _avatar else v.display_name


# --- Mỗi khung hình --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_msg_t = maxf(_msg_t - dt, 0.0)
	var h := day_night.time_of_day if day_night != null else 15.0
	for g in groups.duplicate():
		step(g, dt)
		if not groups.has(g):
			continue
		if not bool(g.player) and (float(g.t_left) <= 0.0 or (bool(g.site) and not ambient_ok(h) and float(g.t) > 4.0)):
			_end_group(g)
	if not pg.is_empty():
		var steer := Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_forward", "cam_back"))
		_player_move(pg, steer, dt)
		_update_camera(pg, dt)
		_update_ui(pg)


## Một bước mô phỏng của một nhóm.
func step(g: Dictionary, dt: float) -> void:
	g.t = float(g.t) + dt
	var members: Array = g.members
	var kind := str(g.kind)
	if not bool(g.started):
		# Chờ đủ người: đứng quanh bãi
		for i in members.size():
			var a := TAU * i / maxf(members.size(), 1.0)
			_walk_to(members[i], (g.center as Vector3) + Vector3(cos(a), 0, sin(a)) * 1.6, g.center, dt)
		if members.size() >= int(KINDS[kind].min) and (float(g.t) > 3.0 or members.size() >= int(KINDS[kind].max)):
			_restart(g)
		elif float(g.t) > gather_wait and not bool(g.player):
			_end_group(g)
		return
	g.t_left = float(g.t_left) - dt
	match kind:
		"da_cau": _step_cau(g, dt)
		"ban_bi": _step_bi(g, dt)
		"chuyen": _step_chuyen(g, dt)
		"bit_mat": _step_goat(g, dt)
		"rong_ran": _step_dragon(g, dt)


## Bắt đầu (lại) từ đầu.
func _restart(g: Dictionary) -> void:
	g.started = true
	g.t = 0.0
	var n := (g.members as Array).size()
	for v: Villager in g.members:
		var bf := v.get_node_or_null("Blindfold")
		if bf != null:
			v.remove_child(bf)
			bf.queue_free()
	match str(g.kind):
		"da_cau":
			g.st = {"count": 0, "score": 0, "from": 0, "to": 1 % n, "ft": 0.0, "dur": 1.0, "wait": 1.2, "press": -9.0, "kick": [-9.0, 0]}
		"ban_bi":
			g.st = {"turn": -1, "phase": "next", "wait": 0.8, "pts": [], "score": 0, "aim": 0.0, "power": 0.5, "round": 1, "over": false}
			for i in n:
				(g.st.pts as Array).append(0)
			_bi_rack(g)
		"chuyen":
			g.st = {"turn": 0, "ban": [], "picked": 0, "ft": -1.0, "taps": 0, "wait": 1.0, "score": 0, "over": false}
			for i in n:
				(g.st.ban as Array).append(1)
		"bit_mat":
			var pi := int(g.pi)
			g.st = {"catcher": pi if pi >= 0 else _rng.randi_range(0, n - 1), "pos": [], "heard": Vector3.ZERO, "hear_t": 0.0, "bark": [],
					"pause": 1.5, "time": 0.0, "score": 0, "over": false, "caught": 0}
			for i in n:
				var a := TAU * i / n
				(g.st.pos as Array).append(Vector3(cos(a), 0, sin(a)) * goat_ring * 0.85)
				(g.st.bark as Array).append(_rng.randf_range(0.5, 2.5))
			(g.st.pos as Array)[int(g.st.catcher)] = Vector3.ZERO
			_blindfold(g.members[int(g.st.catcher)] as Villager)
		"rong_ran":
			var pd := int(g.pi)
			g.st = {"doctor": pd if pd >= 0 else n - 1, "phase": "chant", "t": 0.0, "pos": [], "line_i": 0, "ang": 0.0,
					"score": 0, "over": false, "time": 0.0, "caught": 0}
			for i in n:
				(g.st.pos as Array).append(Vector3(-0.5 * i, 0, 2.0))
			(g.st.pos as Array)[int(g.st.doctor)] = Vector3(0, 0, -1.0)
	_refresh_props(g)


# --- Đá cầu -----------------------------------------------------------------------------------------

func _cau_slot(g: Dictionary, i: int) -> Vector3:
	var n := (g.members as Array).size()
	var a := TAU * i / n + PI * 0.5
	var base := Vector3(cos(a), 0, sin(a)) * cau_radius
	if i == int(g.pi) and n > 0:
		base = _cam_dir * cau_radius            # người chơi đứng phía camera
	return (g.center as Vector3) + base


func _step_cau(g: Dictionary, dt: float) -> void:
	var st: Dictionary = g.st
	var members: Array = g.members
	var n := members.size()
	for i in n:
		_walk_to(members[i], _cau_slot(g, i), g.center, dt)
	var cau := (g.root as Node3D).get_node("Cau") as Node3D
	var a := _cau_slot(g, int(st.from)) + Vector3(0, 0.25, 0)
	var b := _cau_slot(g, int(st.to) % n) + Vector3(0, 0.25, 0)
	if float(st.wait) > 0.0:
		st.wait = float(st.wait) - dt
		cau.global_position = a + Vector3(0, -0.2, 0)
		if float(st.wait) <= 0.0:
			_cau_kick(g, int(st.from))
		return
	st.ft = float(st.ft) + dt
	var u := clampf(float(st.ft) / float(st.dur), 0.0, 1.0)
	cau.global_position = a.lerp(b, u) + Vector3(0, 2.3 * 4.0 * u * (1.0 - u), 0)
	cau.rotation.x = PI * (1.0 - u) if u < 0.5 else 0.0
	# Dáng đá: chân phải vung lên một nhịp
	var kick: Array = st.kick
	var kt := float(g.t) - float(kick[0])
	if kt < 0.3 and int(kick[1]) < n:
		var kv := members[int(kick[1])] as Villager
		if kv.legs.size() == 2:
			kv.legs[1].rotation.x = -1.2 * sin(PI * kt / 0.3)
	if u < 1.0:
		return
	# Cầu rơi tới chân người nhận
	var to := int(st.to) % n
	var ok: bool
	if to == int(g.pi):
		ok = absf(float(st.press) - float(g.t)) <= cau_window
	else:
		ok = _rng.randf() > cau_miss
	if ok:
		st.count = int(st.count) + 1
		st.score = maxi(int(st.score), int(st.count)) if bool(g.player) else int(st.count)
		st.from = to
		_stat("cau_kicks")
		_cau_kick(g, to)
		if to == int(g.pi):
			_say("Đẹp! %d" % int(st.count))
		elif int(st.count) % 8 == 0:
			_bark(members[to] as Villager, "%d rồi! Giữ nhé!" % int(st.count))
	else:
		_stat("cau_drops")
		if to == int(g.pi):
			_say("Rơi cầu rồi!")
		else:
			_bark(members[to] as Villager, ["Ối, rơi rồi!", "Trượt mất!", "Đá lại nào!"][_rng.randi_range(0, 2)])
		st.count = 0
		st.from = to
		st.wait = 1.3


func _cau_kick(g: Dictionary, from: int) -> void:
	var st: Dictionary = g.st
	var n := (g.members as Array).size()
	var to := (from + _rng.randi_range(1, n - 1)) % n
	st.from = from
	st.to = to
	st.ft = 0.0
	st.dur = _rng.randf_range(cau_flight.x, cau_flight.y)
	st.kick = [float(g.t), from]
	st.press = -9.0


# --- Bắn bi -----------------------------------------------------------------------------------------

func _bi_rack(g: Dictionary) -> void:
	var st: Dictionary = g.st
	var m: Array = []
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var r := bi_ring * (0.0 if i == 0 else 0.5)
		m.append({"p": Vector2(cos(a), sin(a)) * r, "v": Vector2.ZERO, "alive": true, "shooter": false})
	st["marbles"] = m


func _bi_dir(g: Dictionary) -> Vector2:
	# Hướng "ra xa camera" (người chơi) hoặc cố định (tự chơi): vạch bắn ở phía +dir
	var d := Vector2(_cam_dir.x, _cam_dir.z) if bool(g.player) else Vector2(0, 1)
	return d.normalized()


func _step_bi(g: Dictionary, dt: float) -> void:
	var st: Dictionary = g.st
	var members: Array = g.members
	var n := members.size()
	var dir := _bi_dir(g)
	var line := dir * bi_line
	var side := Vector2(-dir.y, dir.x)
	var c := g.center as Vector3
	var turn := int(st.turn)
	for i in n:
		var v := members[i] as Villager
		if i == turn and str(st.phase) in ["aim", "roll"]:
			_walk_to(v, c + Vector3(line.x, 0, line.y) + Vector3(dir.x, 0, dir.y) * 0.45, c, dt)
			if v._walk_amount < 0.3:
				v.work_anim = "squat"
		else:
			v.work_anim = "idle"
			var off := side * (1.1 + 0.8 * i) * (1.0 if i % 2 == 0 else -1.0) + dir * 1.3
			_walk_to(v, c + Vector3(off.x, 0, off.y), c, dt)
	var marbles: Array = st.marbles
	match str(st.phase):
		"next":
			st.wait = float(st.wait) - dt
			if float(st.wait) > 0.0:
				return
			var alive := 0
			for m: Dictionary in marbles:
				if bool(m.alive) and not bool(m.shooter):
					alive += 1
			if alive == 0:
				# Hết bi trong vòng: xong một ván
				var best := 0
				for i in n:
					if int(st.pts[i]) > int(st.pts[best]):
						best = i
				_stat("bi_rounds")
				if bool(g.player):
					st.over = true
					st.score = int(st.pts[int(g.pi)])
					st.phase = "over"
					_say("%s thắng ván này!" % _name(members[best] as Villager), 3.0)
					return
				_bark(members[best] as Villager, "Tớ ăn %d viên!" % int(st.pts[best]))
				for i in n:
					st.pts[i] = 0
				_bi_rack(g)
			st.turn = (turn + 1) % n
			st.phase = "aim"
			st.wait = _rng.randf_range(1.0, 1.8)
			st.aim = 0.0
			st.power = 0.0
			_charging = false
		"aim":
			if int(st.turn) == int(g.pi):
				if _charging:
					st.power = fmod(float(st.power) + dt / 1.1, 2.0)
				var steer := Input.get_axis("cam_left", "cam_right")
				st.aim = clampf(float(st.aim) + steer * dt * 0.6, -0.6, 0.6)
				return
			st.wait = float(st.wait) - dt
			if float(st.wait) <= 0.0:
				# Máy ngắm một viên còn trong vòng, lệch tay chút ít
				var targets: Array = []
				for m: Dictionary in marbles:
					if bool(m.alive):
						targets.append(m.p)
				var tp: Vector2 = targets[_rng.randi_range(0, targets.size() - 1)]
				var ang := (tp - line).angle() + _rng.randfn(0.0, 0.035)
				_bi_shoot(g, Vector2(cos(ang), sin(ang)) * _rng.randf_range(3.2, 4.2))
		"roll":
			var moving := false
			var sub := 4
			for k in sub:
				var h := dt / sub
				for m: Dictionary in marbles:
					if not bool(m.alive):
						continue
					var vel: Vector2 = m.v
					var sp := vel.length()
					if sp > 0.02:
						moving = true
						m.p = (m.p as Vector2) + vel * h
						m.v = vel.normalized() * maxf(sp - bi_friction * h, 0.0)
					else:
						m.v = Vector2.ZERO
				# Va chạm đàn hồi giữa các viên bi (cùng khối lượng)
				for i in marbles.size():
					for j in range(i + 1, marbles.size()):
						var ma: Dictionary = marbles[i]
						var mb2: Dictionary = marbles[j]
						if not bool(ma.alive) or not bool(mb2.alive):
							continue
						var d: Vector2 = (mb2.p as Vector2) - (ma.p as Vector2)
						var dist := d.length()
						if dist < bi_radius * 2.0 and dist > 0.0001:
							var nrm := d / dist
							var rel := ((ma.v as Vector2) - (mb2.v as Vector2)).dot(nrm)
							if rel > 0.0:
								ma.v = (ma.v as Vector2) - nrm * rel * 0.95
								mb2.v = (mb2.v as Vector2) + nrm * rel * 0.95
								_stat("bi_hits")
							var push := (bi_radius * 2.0 - dist) * 0.5
							ma.p = (ma.p as Vector2) - nrm * push
							mb2.p = (mb2.p as Vector2) + nrm * push
			# Bi ra khỏi vòng: ăn điểm
			for m: Dictionary in marbles:
				if bool(m.alive) and not bool(m.shooter) and (m.p as Vector2).length() > bi_ring + bi_radius:
					m.alive = false
					st.pts[int(st.turn)] = int(st.pts[int(st.turn)]) + 1
					_stat("bi_out")
					if int(st.turn) == int(g.pi):
						_say("Ăn một viên!")
			st.wait = float(st.wait) + dt
			if not moving or float(st.wait) > 6.0:
				for i in range(marbles.size() - 1, -1, -1):
					if bool(marbles[i].shooter):
						marbles.remove_at(i)
				st.phase = "next"
				st.wait = 0.7
		"over":
			pass
	_refresh_props(g)


func _bi_shoot(g: Dictionary, vel: Vector2) -> void:
	var st: Dictionary = g.st
	(st.marbles as Array).append({"p": _bi_dir(g) * bi_line, "v": vel, "alive": true, "shooter": true})
	st.phase = "roll"
	st.wait = 0.0
	_stat("bi_shots")


# --- Chơi chuyền ------------------------------------------------------------------------------------

func _chuyen_need(st: Dictionary) -> int:
	return mini(int(st.ban[int(st.turn)]), 10 - int(st.picked))


func _step_chuyen(g: Dictionary, dt: float) -> void:
	var st: Dictionary = g.st
	var members: Array = g.members
	var n := members.size()
	var c := g.center as Vector3
	for i in n:
		var a := TAU * i / n + PI * 0.5
		var off := Vector3(cos(a), 0, sin(a)) * 0.85
		if i == int(g.pi):
			off = _cam_dir * 0.85
		var v := members[i] as Villager
		_walk_to(v, c + off, c, dt)
		if v._walk_amount < 0.3:
			v.work_anim = "squat"
	var turn := int(st.turn) % n
	var ball := (g.root as Node3D).get_node("Ball") as Node3D
	var hand := (members[turn] as Villager).global_position.lerp(c, 0.45) + Vector3(0, 0.42, 0)
	if bool(st.over):
		ball.global_position = hand
		return
	if float(st.ft) < 0.0:
		ball.global_position = hand
		st.wait = float(st.wait) - dt
		if turn != int(g.pi) and float(st.wait) <= 0.0:
			_chuyen_toss(g)
		return
	st.ft = float(st.ft) + dt
	var u := clampf(float(st.ft) / chuyen_flight, 0.0, 1.0)
	ball.global_position = hand + Vector3(0, 1.5 * 4.0 * u * (1.0 - u), 0)
	if u < 1.0:
		return
	# Quả chuyền rơi về tay: nhặt đủ que chưa?
	var need := _chuyen_need(st)
	var ok: bool
	if turn == int(g.pi):
		ok = int(st.taps) == need
	else:
		ok = _rng.randf() < 0.95 - 0.07 * int(st.ban[turn])
	st.ft = -1.0
	st.wait = _rng.randf_range(0.5, 0.9)
	if ok:
		st.picked = int(st.picked) + need
		_stat("chuyen_ok")
		if int(st.picked) >= 10:
			var done := int(st.ban[turn])
			st.picked = 0
			if turn == int(g.pi):
				st.score = done
				_say("Xong bàn %d!" % done, 1.4)
			else:
				_bark(members[turn] as Villager, "Xong bàn %d rồi nhé!" % done)
			if done >= chuyen_max_ban:
				_stat("chuyen_finish")
				if bool(g.player):
					st.over = true
					_say("%s chơi hết %d bàn — thắng!" % [_name(members[turn] as Villager), chuyen_max_ban], 4.0)
				else:
					for i in n:
						st.ban[i] = 1
			else:
				st.ban[turn] = done + 1
	else:
		_stat("chuyen_fail")
		if turn == int(g.pi):
			_say("Hỏng rồi! Nhặt %d que, cần %d" % [int(st.taps), need], 1.4)
		else:
			_bark(members[turn] as Villager, ["Ối, rơi mất!", "Hỏng rồi, đến lượt cậu!"][_rng.randi_range(0, 1)])
		st.picked = 0
		st.turn = (turn + 1) % n
	_refresh_props(g)


func _chuyen_toss(g: Dictionary) -> void:
	g.st.ft = 0.0
	g.st.taps = 0


# --- Bịt mắt bắt dê ---------------------------------------------------------------------------------

func _blindfold(v: Villager) -> void:
	if v.get_node_or_null("Blindfold") != null:
		return
	var s := float(v._look.get("scale", 1.0)) if v._look is Dictionary else 1.0
	var mb := MeshBuilder.new(1, 0.0)
	mb.add_prism(0.118 * s, 0.118 * s, 0.05 * s, 10, Palette.FLAG_RED, Transform3D(Basis(), Vector3(0, 1.545 * s, 0.0)))
	var mi := mb.commit_instance("Blindfold")
	v.add_child(mi)


func _step_goat(g: Dictionary, dt: float) -> void:
	var st: Dictionary = g.st
	var members: Array = g.members
	var n := members.size()
	var c := g.center as Vector3
	var pos: Array = st.pos
	var ci := int(st.catcher)
	var cp: Vector3 = pos[ci]
	var paused := float(st.pause) > 0.0
	st.pause = maxf(float(st.pause) - dt, 0.0)
	if not bool(st.over):
		if not paused:
			st.time = float(st.time) + dt
		# Dê kêu "be be" — người bịt mắt nghe tiếng mà lần theo
		for i in n:
			if i == ci:
				continue
			st.bark[i] = float(st.bark[i]) - dt
			if float(st.bark[i]) <= 0.0:
				st.bark[i] = _rng.randf_range(1.6, 3.4)
				_bark(members[i] as Villager, "Be… be…!")
				if ci == int(g.pi):
					_hear_at(c + (pos[i] as Vector3))
				elif (pos[i] as Vector3).distance_to(cp) < (st.heard as Vector3).distance_to(cp) or float(st.hear_t) <= 0.0:
					st.heard = (pos[i] as Vector3) + Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4))
					st.hear_t = 2.5
		st.hear_t = float(st.hear_t) - dt
		if ci != int(g.pi) and not paused:
			var to: Vector3 = (st.heard as Vector3) - cp
			if to.length() > 0.1 and float(st.hear_t) > -1.0:
				cp += to.normalized() * minf(catcher_speed * 1.3 * dt, to.length())
		# Dê né khi người bắt tới gần, không ra khỏi vòng
		for i in n:
			if i == ci:
				continue
			var p: Vector3 = pos[i]
			var away := p - cp
			if away.length() < 2.0:
				var tang := away.normalized().cross(Vector3.UP) * (0.7 if i % 2 == 0 else -0.7)
				p += (away.normalized() + tang).normalized() * goat_speed * (0.9 if ci == int(g.pi) else 0.8) * dt
			if p.length() > goat_ring - 0.25:
				p = p.normalized() * (goat_ring - 0.25)
				if away.length() < 2.0:
					# Bị dồn ra mép vòng: chạy men theo vòng về phía xa người bắt
					var tg := p.normalized().cross(Vector3.UP)
					if tg.dot(away) < 0.0:
						tg = -tg
					p = (p + tg * goat_speed * 0.8 * dt).normalized() * (goat_ring - 0.25)
			pos[i] = p
		if cp.length() > goat_ring - 0.2:
			cp = cp.normalized() * (goat_ring - 0.2)
		pos[ci] = cp
		for i in n:
			if i != ci and not paused and (pos[i] as Vector3).distance_to(cp) < catch_dist:
				_stat("goat_caught")
				st.caught = int(st.caught) + 1
				if ci == int(g.pi):
					st.over = true
					st.score = maxi(1, int(blind_seconds - float(st.time)))
					_say("Bắt được %s sau %.0f giây!" % [_name(members[i] as Villager), float(st.time)], 4.0)
				else:
					_bark(members[i] as Villager, "Á, bị bắt rồi!")
					var old := members[ci] as Villager
					var bf := old.get_node_or_null("Blindfold")
					if bf != null:
						old.remove_child(bf)
						bf.queue_free()
					st.catcher = i
					_blindfold(members[i] as Villager)
					st.pause = 3.0                 # người bắt mới đứng xoay vài vòng cho dê chạy ra xa
					st.hear_t = 0.0
					st.heard = pos[i]
				break
		if ci == int(g.pi) and not bool(st.over) and float(st.time) >= blind_seconds:
			st.over = true
			st.score = 0
			_say("Hết giờ, chưa bắt được con dê nào!", 4.0)
	for i in n:
		var v := members[i] as Villager
		var target := c + (pos[i] as Vector3)
		var face := c + cp if i != int(st.catcher) else c + (st.heard as Vector3)
		_walk_to(v, target, face, dt, true)
		if i == int(st.catcher) and v.arms.size() == 2:
			# Hai tay quờ quạng phía trước
			v.arms[0].rotation.x = -1.3 + 0.2 * sin(float(g.t) * 5.0)
			v.arms[1].rotation.x = -1.3 - 0.2 * sin(float(g.t) * 5.0)


# --- Rồng rắn lên mây -------------------------------------------------------------------------------

func _dragon_line(g: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for i in (g.members as Array).size():
		if i != int(g.st.doctor):
			out.append(i)
	return out


func _step_dragon(g: Dictionary, dt: float) -> void:
	var st: Dictionary = g.st
	var members: Array = g.members
	var c := g.center as Vector3
	var pos: Array = st.pos
	var line := _dragon_line(g)
	var di := int(st.doctor)
	var dp: Vector3 = pos[di]
	var head: Vector3 = pos[line[0]]
	st.t = float(st.t) + dt
	if bool(st.over):
		pass
	elif str(st.phase) == "chant":
		# Đầu rồng dẫn cả đoàn lượn vòng quanh thầy thuốc, vừa đi vừa hát
		st.ang = float(st.ang) + dt * 0.55
		var want := Vector3(cos(float(st.ang)), 0, sin(float(st.ang))) * 2.8
		head += (want - head).limit_length(head_speed * 0.8 * dt)
		if di != int(g.pi):
			dp += (Vector3.ZERO - dp).limit_length(1.5 * dt)
		var li := int(float(st.t) / 2.2)
		if li != int(st.line_i) and li < CHANT.size():
			st.line_i = li
			_bark(members[line[0]] as Villager, CHANT[li])
		if float(st.t) > 2.2 * CHANT.size() + 0.5:
			st.phase = "chase"
			st.t = 0.0
			_bark(members[line[0]] as Villager, "Tha hồ mà đuổi!")
			if di == int(g.pi):
				_say("Xin khúc đuôi! Đuổi bắt đứa cuối hàng đi!", 2.0)
			else:
				_bark(members[di] as Villager, "Có! Xin khúc đuôi!")
	else:
		st.time = float(st.time) + dt
		var tail: Vector3 = pos[line[line.size() - 1]]
		var ready := float(st.t) > 1.5          # đầu rồng kịp dàn hàng trước khi thầy thuốc đuổi
		# Thầy thuốc (máy) chạy vòng qua đầu rồng để chộp đuôi
		if di != int(g.pi) and ready:
			var to := tail - dp
			var around := (dp - head)
			var steer := to.normalized()
			if around.length() < 1.6:
				steer = (steer + around.normalized() * 1.2).normalized()
			# Chạy vòng một phía quanh hàng (đổi phía mỗi lượt) thay vì lao thẳng vào đầu rồng
			steer = (steer + steer.cross(Vector3.UP) * (0.7 if int(st.caught) % 2 == 0 else -0.7)).normalized()
			dp += steer * doctor_speed * 1.2 * dt
		# Đầu rồng dang tay chắn: luôn xoay về phía thầy thuốc
		var mid := Vector3.ZERO
		for li2: int in line:
			mid += pos[li2] as Vector3
		mid /= float(line.size())
		var half := dragon_gap * (line.size() - 1) * 0.5
		var front := mid + (dp - mid).normalized() * half if mid.distance_to(dp) > 0.05 else head
		head += (front - head).limit_length(head_speed * dt)
		if head.distance_to(dp) < 0.7:
			dp = head + (dp - head).normalized() * 0.7            # không chạy xuyên qua đầu rồng
		if ready and dp.distance_to(tail) < 0.6:
			_stat("dragon_caught")
			st.caught = int(st.caught) + 1
			var ti := line[line.size() - 1]
			if di == int(g.pi):
				st.over = true
				st.score = maxi(1, int(chase_seconds - float(st.time)))
				_say("Bắt được khúc đuôi (%s) sau %.0f giây!" % [_name(members[ti] as Villager), float(st.time)], 4.0)
			else:
				_bark(members[ti] as Villager, "Á! Bị bắt mất rồi!")
				st.doctor = ti                   # đứa bị bắt làm thầy thuốc, thầy thuốc cũ nối vào hàng
				st.phase = "chant"
				st.t = 0.0
				st.line_i = -1
				st.time = 0.0
		elif float(st.time) >= chase_seconds:
			_stat("dragon_escape")
			if di == int(g.pi):
				st.over = true
				st.score = 0
				_say("Hết giờ! Rồng rắn giữ được đuôi.", 4.0)
			else:
				st.phase = "chant"
				st.t = 0.0
				st.line_i = -1
				st.time = 0.0
	if head.length() > dragon_ring:
		head = head.normalized() * dragon_ring
	if dp.length() > dragon_ring + 0.5:
		dp = dp.normalized() * (dragon_ring + 0.5)
	pos[int(st.doctor)] = dp if int(st.doctor) == di else pos[int(st.doctor)]
	pos[di] = dp
	line = _dragon_line(g)
	if line[0] != di:
		pos[line[0]] = head if int(st.doctor) == di else pos[line[0]]
	# Cả hàng bám vai nhau: mỗi đứa giữ khoảng cách với đứa trước
	for k in range(1, line.size()):
		var prev: Vector3 = pos[line[k - 1]]
		var cur: Vector3 = pos[line[k]]
		var d := cur - prev
		if d.length() < 0.01:
			d = Vector3(0, 0, 1)
		pos[line[k]] = prev + d.normalized() * dragon_gap
	for i in members.size():
		var v := members[i] as Villager
		var face := c + (pos[int(st.doctor)] as Vector3)
		var k := line.find(i)
		if k > 0:
			face = c + (pos[line[k - 1]] as Vector3)
		elif i == int(st.doctor):
			face = c + (pos[line[line.size() - 1]] as Vector3)
		_walk_to(v, c + (pos[i] as Vector3), face, dt, true)
		if v.arms.size() == 2:
			if k > 0:
				v.arms[0].rotation.x = -1.25         # bám vai đứa trước
				v.arms[1].rotation.x = -1.25
			elif k == 0 and str(st.phase) == "chase":
				v.arms[0].rotation.z = 1.2           # đầu rồng dang tay chắn
				v.arms[1].rotation.z = -1.2


# --- Người chơi điều khiển --------------------------------------------------------------------------

## Space / chuột trái nhấn xuống.
func press() -> void:
	var g := pg
	if g.is_empty() or not bool(g.started):
		return
	var st: Dictionary = g.st
	match str(g.kind):
		"da_cau":
			st.press = float(g.t)
			st.kick = [float(g.t), int(g.pi)]
		"ban_bi":
			if str(st.phase) == "aim" and int(st.turn) == int(g.pi):
				_charging = true
				st.power = 0.0
		"chuyen":
			if bool(st.over) or int(st.turn) % (g.members as Array).size() != int(g.pi):
				return
			if float(st.ft) < 0.0:
				_chuyen_toss(g)
			else:
				st.taps = int(st.taps) + 1


## Space / chuột trái thả ra (bắn bi: bắn với lực đang có).
func release() -> void:
	var g := pg
	if g.is_empty() or str(g.kind) != "ban_bi" or not _charging:
		return
	_charging = false
	var st: Dictionary = g.st
	if str(st.phase) != "aim" or int(st.turn) != int(g.pi):
		return
	var p := float(st.power)
	p = p if p <= 1.0 else 2.0 - p
	var dir := -_bi_dir(g).rotated(float(st.aim))
	_bi_shoot(g, dir * lerpf(bi_speed.x, bi_speed.y, p))


## WASD: chạy (bịt mắt bắt dê, rồng rắn) theo hướng camera.
func _player_move(g: Dictionary, steer: Vector2, dt: float) -> void:
	if not bool(g.started) or not str(g.kind) in ["bit_mat", "rong_ran"] or steer.length() < 0.1:
		return
	var st: Dictionary = g.st
	if bool(st.over):
		return
	var kind := str(g.kind)
	if kind == "bit_mat" and float(st.pause) > 0.0:
		return
	if kind == "rong_ran" and (str(st.phase) != "chase" or float(st.t) <= 1.5):
		return
	var fwd := -_cam_dir
	var right := fwd.cross(Vector3.UP)
	var mv := (right * steer.x - fwd * steer.y).normalized()
	var i := int(st.catcher) if kind == "bit_mat" else int(st.doctor)
	var sp := catcher_speed * 1.25 if kind == "bit_mat" else player_speed
	(st.pos as Array)[i] = ((st.pos as Array)[i] as Vector3) + mv * sp * dt
	if kind == "bit_mat":
		st.heard = ((st.pos as Array)[i] as Vector3) + mv


func _hear_at(world: Vector3) -> void:
	if _cam == null or not _cam.is_inside_tree():
		return
	var p := _cam.unproject_position(world + Vector3(0, 1.0, 0))
	for l in _hear:
		if not l.visible:
			l.position = p - Vector2(60, 16)
			l.visible = true
			l.modulate.a = 1.0
			return


# --- Di chuyển, đạo cụ -------------------------------------------------------------------------------

func _walk_to(m: Variant, to: Vector3, face: Vector3, dt: float, snap: bool = false) -> void:
	var v := m as Villager
	if v == null or not is_instance_valid(v):
		return
	var p := v.global_position
	p.y = to.y
	var d := Vector3(to.x - p.x, 0, to.z - p.z)
	var far := d.length() > (0.6 if snap else 0.1)
	if far:
		var stp := minf(d.length(), 2.6 * dt)
		v.global_position = p + d.normalized() * stp
		v.rotation.y = atan2(d.x, d.z)
		v._walk_amount = move_toward(v._walk_amount, 1.0, dt * 6.0)
	else:
		var moved := d.length() / maxf(dt, 0.001)
		if snap:
			v.global_position = to
		var f := face - to
		if f.length() > 0.05:
			v.rotation.y = lerp_angle(v.rotation.y, atan2(f.x, f.z), minf(dt * 8.0, 1.0))
		v._walk_amount = move_toward(v._walk_amount, clampf(moved / 1.5, 0.0, 1.0) if snap else 0.0, dt * 6.0)
	GameKit.animate_owned(v, self, _avatar, dt)


## Đạo cụ từng trò (con của g.root, toạ độ quanh tâm bãi).
func _build_props(g: Dictionary) -> void:
	var root := g.root as Node3D
	var mb := MeshBuilder.new(random_seed, 0.02)
	var chalk := Color(0.95, 0.94, 0.88)
	match str(g.kind):
		"da_cau":
			var cb := MeshBuilder.new(2, 0.0)
			cb.add_prism(0.06, 0.06, 0.03, 8, Color(0.25, 0.22, 0.2))
			for k in 4:
				var a := TAU * k / 4.0
				cb.add_box(Vector3(0.02, 0.24, 0.07), [Color(0.95, 0.3, 0.3), Color(0.98, 0.85, 0.3), Color(0.3, 0.6, 0.9), Color.WHITE][k],
						Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.02, 0)))
			var cau := cb.commit_instance("Cau")
			cau.top_level = true
			root.add_child(cau)
			return
		"ban_bi":
			_ring(mb, bi_ring, chalk, 20, 0.03)
			mb.add_box(Vector3(1.2, 0.012, 0.04), chalk, Transform3D(Basis(), Vector3(0, 0, bi_line)))
			mb.add_box(Vector3(0.04, 0.012, 1.2), chalk, Transform3D(Basis(), Vector3(bi_line, 0, 0)))
			mb.add_box(Vector3(1.2, 0.012, 0.04), chalk, Transform3D(Basis(), Vector3(0, 0, -bi_line)))
			mb.add_box(Vector3(0.04, 0.012, 1.2), chalk, Transform3D(Basis(), Vector3(-bi_line, 0, 0)))
			var cols: Array[Color] = [Color(0.2, 0.5, 0.9), Color(0.9, 0.3, 0.25), Color(0.25, 0.7, 0.35), Color(0.95, 0.8, 0.25), Color(0.7, 0.4, 0.8), Color.WHITE]
			for k in 6:
				var sb := MeshBuilder.new(k, 0.0)
				sb.add_ellipsoid(Vector3.ONE * bi_radius, cols[k], Transform3D(Basis(), Vector3(0, 0, 0)), 8, 5)
				var mi := sb.commit_instance("Bi%d" % k)
				root.add_child(mi)
			var aim := MeshInstance3D.new()
			aim.name = "Aim"
			aim.top_level = true
			aim.mesh = ImmediateMesh.new()
			var am := StandardMaterial3D.new()
			am.albedo_color = Palette.FLOWER_YELLOW
			am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			am.cull_mode = BaseMaterial3D.CULL_DISABLED
			aim.material_override = am
			root.add_child(aim)
			aim.global_transform = Transform3D.IDENTITY
		"chuyen":
			mb.add_prism(0.75, 0.75, 0.012, 14, Palette.EARTH.lightened(0.12))
			for k in 10:
				var sb := MeshBuilder.new(k, 0.03)
				sb.add_box(Vector3(0.012, 0.012, 0.3), Color(0.82, 0.7, 0.42),
						Transform3D(Basis(Vector3.UP, _rng.randf() * PI), Vector3(_rng.randf_range(-0.22, 0.22), 0.014, _rng.randf_range(-0.22, 0.22))))
				root.add_child(sb.commit_instance("Stick%d" % k))
			var bb := MeshBuilder.new(3, 0.0)
			bb.add_ellipsoid(Vector3.ONE * 0.05, Color(0.45, 0.7, 0.3), Transform3D.IDENTITY, 8, 5)
			var ball := bb.commit_instance("Ball")
			ball.top_level = true
			root.add_child(ball)
		"bit_mat":
			_ring(mb, goat_ring, chalk, 28, 0.05)
		"rong_ran":
			_ring(mb, 0.5, chalk, 12, 0.04)
	root.add_child(mb.commit_instance("Marks"))


func _ring(mb: MeshBuilder, r: float, col: Color, n: int, w: float) -> void:
	for k in n:
		var a := TAU * (k + 0.5) / n
		mb.add_box(Vector3(TAU * r / n * 1.02, 0.012, w), col,
				Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a) * r, 0, sin(a) * r)))


func _refresh_props(g: Dictionary) -> void:
	var root := g.root as Node3D
	var st: Dictionary = g.st
	match str(g.kind):
		"ban_bi":
			var marbles: Array = st.get("marbles", [])
			var shown := 0
			for k in 6:
				var mi := root.get_node("Bi%d" % k) as MeshInstance3D
				mi.visible = false
			for m: Dictionary in marbles:
				if not bool(m.alive):
					continue
				var idx := 5 if bool(m.shooter) else shown
				if not bool(m.shooter):
					shown += 1
				var mi := root.get_node("Bi%d" % idx) as MeshInstance3D
				mi.visible = true
				mi.position = Vector3((m.p as Vector2).x, 0.0, (m.p as Vector2).y)
		"chuyen":
			for k in 10:
				(root.get_node("Stick%d" % k) as Node3D).visible = k >= int(st.get("picked", 0))


func _draw_aim(g: Dictionary) -> void:
	var aim := (g.root as Node3D).get_node_or_null("Aim") as MeshInstance3D
	if aim == null:
		return
	var im := aim.mesh as ImmediateMesh
	im.clear_surfaces()
	var st: Dictionary = g.st
	if not bool(g.player) or str(st.get("phase", "")) != "aim" or int(st.turn) != int(g.pi):
		return
	var dir2 := -_bi_dir(g).rotated(float(st.aim))
	var from2 := _bi_dir(g) * bi_line
	var c := g.center as Vector3
	var a := c + Vector3(from2.x, 0.03, from2.y)
	var b := a + Vector3(dir2.x, 0, dir2.y) * (bi_line + bi_ring)
	var o := Vector3(dir2.y, 0, -dir2.x) * 0.012
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in [a - o, a + o, b + o, a - o, b + o, b - o]:
		im.surface_add_vertex(p)
	im.surface_end()


# --- Camera, giao diện -------------------------------------------------------------------------------

func _update_camera(g: Dictionary, dt: float) -> void:
	var c := g.center as Vector3
	var cfg := {"da_cau": [5.2, 2.2, 1.0], "ban_bi": [4.6, 2.6, 0.1], "chuyen": [3.0, 1.6, 0.4], "bit_mat": [6.2, 5.2, 0.3], "rong_ran": [9.5, 7.5, 0.3]}
	var k: Array = cfg[str(g.kind)]
	var want := c + _cam_dir * float(k[0]) + Vector3(0, float(k[1]), 0)
	var t := 1.0 - exp(-4.0 * dt)
	_cam.global_position = _cam.global_position.lerp(want, t) if dt < 0.9 else want
	_cam.look_at(c + Vector3(0, float(k[2]), 0), Vector3.UP)
	if str(g.kind) == "ban_bi":
		_draw_aim(g)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	_dark = ColorRect.new()
	_dark.color = Color(0, 0, 0, 0.9)
	_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark.visible = false
	_ui.add_child(_dark)
	for i in 6:
		var l := _label(true, 26, Palette.FLOWER_YELLOW, "Be… be…!")
		l.visible = false
		_ui.add_child(l)
		_hear.append(l)
	var box := GameKit.top_panel(_ui)
	_top = _label(true, 24, Palette.HUD_TEXT)
	_sub = _label(false, 16, Palette.HUD_SUBTEXT)
	box.add_child(_top)
	box.add_child(_sub)
	_bar = ColorRect.new()
	_bar.color = Color(0, 0, 0, 0.4)
	_bar.custom_minimum_size = Vector2(320, 14)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_bar)
	_fill = ColorRect.new()
	_fill.color = Palette.FLOWER_YELLOW
	_fill.size = Vector2(0, 14)
	_bar.add_child(_fill)
	_big = GameKit.big_label(_ui, 60, -300, 12)


func _label(bold: bool, size: int, col: Color, text: String = "") -> Label:
	return GameKit.label(bold, size, col, text)


func _update_ui(g: Dictionary) -> void:
	var st: Dictionary = g.st
	var kind := str(g.kind)
	var members: Array = g.members
	var n := members.size()
	var title := str(KINDS[kind].name).capitalize()
	var frac := 0.0
	_dark.visible = false
	for l in _hear:
		if l.visible:
			l.modulate.a -= get_process_delta_time() / 0.9
			l.visible = l.modulate.a > 0.0
	if not bool(g.started):
		_top.text = title + "  ·  chờ đủ người…"
		_sub.text = "Esc: thôi chơi"
		_big.text = ""
		return
	match kind:
		"da_cau":
			_top.text = "Đá cầu  ·  %d chạm liên tiếp  ·  cao nhất %d" % [int(st.count), int(st.score)]
			var mine := int(st.to) % n == int(g.pi) and float(st.wait) <= 0.0
			_sub.text = ("Cầu đang tới CHỖ BẠN — " if mine else "") + "Space / chuột trái: đá đúng lúc cầu rơi tới chân (thanh đầy)  ·  Esc: thôi"
			frac = clampf(float(st.ft) / float(st.dur), 0.0, 1.0) if mine else 0.0
		"ban_bi":
			var rows: Array[String] = []
			for i in n:
				rows.append("%s %d" % [_name(members[i] as Villager), int(st.pts[i])])
			var who := _name(members[int(st.turn) % n] as Villager) if int(st.turn) >= 0 else "…"
			_top.text = "Bắn bi  ·  lượt: %s  ·  %s" % [who, "  ".join(rows)]
			_sub.text = "A / D: ngắm  ·  giữ Space / chuột trái lấy lực, thả để bắn — đẩy bi ra khỏi vòng là ăn  ·  Esc: thôi" if not bool(st.over) else "E: ván mới  ·  Esc: thôi"
			var p := float(st.power)
			frac = (p if p <= 1.0 else 2.0 - p) if _charging else 0.0
		"chuyen":
			var turn := int(st.turn) % n
			_top.text = "Chơi chuyền  ·  lượt: %s  ·  bàn %d  ·  đã nhặt %d / 10 que" % [_name(members[turn] as Villager), int(st.ban[turn]), int(st.picked)]
			if bool(st.over):
				_sub.text = "E: chơi lại  ·  Esc: thôi"
			elif turn == int(g.pi):
				_sub.text = ("Space: tung quả chuyền" if float(st.ft) < 0.0 else "Bấm Space đúng %d lần trước khi quả rơi (đã bấm %d)" % [_chuyen_need(st), int(st.taps)]) + "  ·  Esc: thôi"
				frac = clampf(float(st.ft) / chuyen_flight, 0.0, 1.0)
			else:
				_sub.text = "Chờ tới lượt bạn…  ·  Esc: thôi"
		"bit_mat":
			_top.text = "Bịt mắt bắt dê  ·  %.0f giây" % maxf(blind_seconds - float(st.time), 0.0)
			_sub.text = "Bạn bị bịt mắt! W A S D: lần theo tiếng \"be be\" mà bắt  ·  Esc: thôi" if not bool(st.over) else "E: chơi lại  ·  Esc: thôi"
			_dark.visible = not bool(st.over)
			frac = clampf(float(st.time) / blind_seconds, 0.0, 1.0)
		"rong_ran":
			_top.text = "Rồng rắn lên mây  ·  %s" % ("đang hát…" if str(st.phase) == "chant" else "còn %.0f giây" % maxf(chase_seconds - float(st.time), 0.0))
			_sub.text = "Bạn là thầy thuốc: W A S D chạy vòng qua đầu rồng, chạm đứa cuối hàng  ·  Esc: thôi" if not bool(st.over) else "E: chơi lại  ·  Esc: thôi"
			frac = clampf(float(st.time) / chase_seconds, 0.0, 1.0)
	_fill.size.x = 320.0 * frac
	_big.text = _msg if _msg_t > 0.0 else ""
