class_name TipCat
extends Node3D
## Trò chơi dân gian Đánh khăng (mục 32). Mỗi đứa có một khăng cái (que dài cầm tay); khăng con (que ngắn) đặt
## ngang miệng lỗ khăng. Người đánh lần lượt:
##  1) **Hất khăng**: hất khăng con bay ra phía trước. Bên đỡ (những đứa còn lại) chạy theo bắt — bắt được trên
##     không thì người đánh **chết**.
##  2) **Ném vào lỗ**: không bắt được thì đứa gần nhất nhặt khăng ném về lỗ; người đánh được **vụt đỡ** khăng
##     ra xa (bên đỡ lại có thể bắt). Khăng rơi cách lỗ không quá một khăng cái (`khang_len`) → **chết**.
##  3) **Đánh khăng** (`strikes` lần): gõ đầu khăng con cho nảy lên rồi vụt khi nó đang lơ lửng — vụt đúng lúc
##     khăng lên cao nhất thì bay xa; vụt hụt mất một lần. Hết lượt đo từ lỗ tới khăng con theo khăng cái:
##     **được N khăng** (điểm). Mỗi chuyến bay đều có thể bị bên đỡ bắt.
## - Trẻ con tự chơi: việc `khang` của Villagers ở `sites` (bãi đất trống, hướng đánh `site_dirs`), đủ 2 đứa là
##   chơi, lần lượt làm người đánh; meta `khang` + `talking`; tan sau `game_seconds`, tối / mưa / giờ học.
## - Người chơi: nhìn một đứa đang chơi "E: Xin đánh khăng cùng" (`join_at`) hoặc rủ qua hội thoại
##   (`start_with` — bày lỗ khăng ngay trước mặt). Chơi `rounds` vòng, ai nhiều khăng nhất thắng. Space / chuột
##   trái (`fish_reel`): giữ lấy lực rồi thả để hất; bấm để vụt đỡ; bấm gõ khăng nảy, bấm lần nữa để vụt. A / D
##   ngắm hướng. Lượt của bọn trẻ: xem, E để tua nhanh. Esc: thôi.

signal turn_done(who: String, points: int, out: bool)

@export var villagers: Villagers
@export var first_person: FirstPerson
@export var dialogue: Dialogue
@export var hud: Hud
@export var day_night: DayNight
@export var weather: Weather
@export var village: Village
@export_group("Luật")
## Độ dài khăng cái (m) — đơn vị đo điểm và bán kính "chết" quanh lỗ.
@export var khang_len: float = 0.6
@export var strikes: int = 3
@export var rounds: int = 3
@export var catch_radius: float = 0.8
## Nhân vào kỹ năng khi bắt khăng (1 = đứa giỏi bắt dính gần hết).
@export var catch_skill: float = 0.8
@export_group("Lực")
@export var flick_speed: Vector2 = Vector2(7.0, 15.0)
@export var strike_speed: Vector2 = Vector2(4.5, 11.0)
@export var hop_speed: float = 4.2
## Vụt lệch đỉnh nảy quá chừng này giây thì hụt.
@export var strike_window: float = 0.22
@export var charge_time: float = 1.1
@export_group("Trẻ con")
@export var kid_skill: Vector2 = Vector2(0.45, 0.85)
@export var run_speed: float = 3.6
@export var game_seconds: Vector2 = Vector2(45.0, 85.0)
@export var random_seed: int = 4242

const TEMP_NAMES: Array[String] = ["Cu Bin", "Cu Tũn", "Cu Sóc", "Bé Mít", "Cu Bờm", "Cu Tèo"]
const G := 9.8

var sites: Array[Vector3] = []
var site_dirs: Array[Vector3] = []
var games: Array[Dictionary] = []
var player_game: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _avatar: Villager
var _cam: Camera3D
var _temps: Array[Villager] = []
var _ui: CanvasLayer
var _top: Label
var _sub: Label
var _big: Label
var _power_bar: ColorRect
var _power_bg: ColorRect
var _big_t: float = 0.0
var _charging: bool = false
var _charge: float = 0.0
var _fast: bool = false


func _ready() -> void:
	_rng.seed = random_seed
	_cam = Camera3D.new()
	_cam.name = "KhangCam"
	_cam.top_level = true
	_cam.fov = 62.0
	add_child(_cam)
	_build_ui()
	if village != null:
		# Sân đình phía đông (bãi nhảy dây ở phía tây), đánh về phía nam; bãi cỏ đầu làng phía tây cổng
		sites.append(village.dinh_spot + Vector3(9.0, 0.0, -1.0))
		site_dirs.append(Vector3(0, 0, 1))
		sites.append(Vector3(village.center.x - 16.0, 0.0, village.center.y + village.radii.y + 8.0))
		site_dirs.append(Vector3(-0.35, 0, 1).normalized())


# --- Trẻ con tự chơi --------------------------------------------------------------------------------

func ambient_ok(h: float) -> bool:
	if sites.is_empty() or h < 7.0 or h >= 17.5 or (h >= 11.0 and h < 13.0):
		return false
	return weather == null or not weather.kind in ["storm", "drizzle"]


func site_target(v: Villager) -> Vector3:
	var i := _nearest_site(v.global_position)
	var side := site_dirs[i].cross(Vector3.UP)
	return sites[i] + side * _rng.randf_range(1.5, 3.0) * (1.0 if _rng.randf() < 0.5 else -1.0) + Vector3(0, 0.05, 0)


func _nearest_site(p: Vector3) -> int:
	var best := 0
	for i in sites.size():
		if sites[i].distance_to(p) < sites[best].distance_to(p):
			best = i
	return best


func on_arrive(v: Villager) -> void:
	var i := _nearest_site(v.global_position)
	var g := _game_at(sites[i])
	if g.is_empty():
		g = _new_game(sites[i], site_dirs[i], true)
	_add_member(g, v)


func is_member(v: Villager) -> bool:
	return v != null and v.has_meta("khang")


func _game_at(p: Vector3) -> Dictionary:
	for g in games:
		if (g.hole as Vector3).distance_to(p) < 3.0:
			return g
	return {}


func _new_game(hole: Vector3, dir: Vector3, ambient: bool) -> Dictionary:
	var g := {"hole": hole, "dir": dir.normalized(), "members": [], "order": [], "turn_i": -1, "striker": null,
			"phase": "idle", "t": 1.5, "pos": hole, "vel": Vector3.ZERO, "flying": false, "catchable": false,
			"tried": [], "strikes_left": strikes, "score": {}, "round": 1, "aim": 0.0, "pts": 0, "ambient": ambient,
			"t_left": _rng.randf_range(game_seconds.x, game_seconds.y), "skill": {}, "thrower": null,
			"hop_t": -1.0, "strike_at": -1.0, "bat_tried": false, "msg": "", "turns": 0, "done": false}
	var root := Node3D.new()
	root.name = "KhangGame"
	root.top_level = true
	add_child(root)
	g.root = root
	var mb := MeshBuilder.new(random_seed + games.size(), 0.04)
	var side := (g.dir as Vector3).cross(Vector3.UP)
	var b := Basis(side, Vector3.UP, g.dir as Vector3)
	# Lỗ khăng: rãnh đất sẫm dọc hướng đánh, đất bới hai bên
	mb.add_box(Vector3(0.09, 0.012, 0.32), Palette.WINDOW_DARK, Transform3D(b, hole + Vector3(0, 0.01, 0)))
	for s: float in [-1.0, 1.0]:
		mb.add_blob(Vector3(0.09, 0.03, 0.12), Palette.EARTH, _rng, 0.3, Transform3D(b, hole + side * s * 0.13))
	root.add_child(mb.commit_instance("Hole"))
	var sm := MeshBuilder.new(77, 0.02)
	# Khăng con: que ngắn vót nhọn hai đầu, màu tre khô (làm to hơn thật một chút cho dễ nhìn)
	sm.add_limb(Vector3(-0.12, 0, 0), Vector3(0.12, 0, 0), 0.03, 0.03, 6, Palette.STRAW)
	sm.add_limb(Vector3(0.12, 0, 0), Vector3(0.17, 0, 0), 0.03, 0.006, 6, Palette.STRAW.darkened(0.15))
	sm.add_limb(Vector3(-0.12, 0, 0), Vector3(-0.17, 0, 0), 0.03, 0.006, 6, Palette.STRAW.darkened(0.15))
	var stick := MeshInstance3D.new()
	stick.name = "KhangCon"
	stick.mesh = sm.commit()
	stick.top_level = true
	root.add_child(stick)
	g.stick = stick
	var lb := Label3D.new()
	lb.font = Hud.font(true)
	lb.font_size = 60
	lb.pixel_size = 0.006
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Palette.FLOWER_YELLOW
	lb.outline_size = 10
	lb.outline_modulate = Palette.WINDOW_DARK
	lb.top_level = true
	lb.visible = false
	root.add_child(lb)
	g.label = lb
	_reset_stick(g)
	games.append(g)
	return g


func _add_member(g: Dictionary, v: Variant) -> void:
	(g.members as Array).append(v)
	(g.order as Array).append(v)
	var name_ := _name(v)
	(g.score as Dictionary)[name_] = int((g.score as Dictionary).get(name_, 0))
	(g.skill as Dictionary)[name_] = 0.0 if v is String else _rng.randf_range(kid_skill.x, kid_skill.y)
	if v is Villager:
		var k := v as Villager
		k.set_meta("khang", true)
		k.set_meta("talking", true)
		k.state = Villager.State.IDLE
		k.visible = true
		k.dwell = 1.0e6
		k.work_anim = "idle"
		if k.prop_node != null:
			k.prop_node.visible = false
		k.activity_text = "đang chơi đánh khăng"
		_give_bat(k)


## Khăng cái cầm ở tay phải (gắn vào cẳng tay).
func _give_bat(v: Villager) -> void:
	if v.elbows.size() < 2 or v.elbows[1].get_node_or_null("KhangCai") != null:
		return
	var s: float = float((v.get("_look") as Dictionary).get("scale", 1.0)) if v.get("_look") is Dictionary else 1.0
	var mb := MeshBuilder.new(5, 0.02)
	mb.add_limb(Vector3(0, 0, -0.08), Vector3(0, 0, khang_len - 0.08), 0.02, 0.016, 5, Palette.WOOD_LIGHT)
	var mi := mb.commit_instance("KhangCai")
	mi.position = Vector3(0, -0.3 * s, 0.02)
	mi.rotation.x = 0.35
	v.elbows[1].add_child(mi)


func _end_game(g: Dictionary) -> void:
	for v: Variant in g.members:
		if not (v is Villager) or not is_instance_valid(v):
			continue
		var k := v as Villager
		k.remove_meta("khang")
		k.remove_meta("talking")
		var bat := k.elbows[1].get_node_or_null("KhangCai") if k.elbows.size() > 1 else null
		if bat != null:
			bat.get_parent().remove_child(bat)
			bat.queue_free()
		if k.prop_node != null:
			k.prop_node.visible = true
		k.work_anim = "idle"
		if _temps.has(k):
			_temps.erase(k)
			k.queue_free()
		else:
			k.dwell = 0.0
	(g.root as Node).queue_free()
	games.erase(g)


# --- Người chơi -------------------------------------------------------------------------------------

func refusal(v: Villager, at: Vector3 = Vector3.INF, dir: Vector3 = Vector3.ZERO) -> String:
	if not v.role in ["kid", "herder"]:
		return "Người lớn ai đánh khăng! Rủ bọn trẻ con ấy."
	if v.has_meta("in_class"):
		return "Đang giờ học mà {you}!"
	var h := day_night.time_of_day if day_night != null else 15.0
	if h >= 18.5 or h < 6.0:
		return "Tối rồi, khăng bay đâu tìm không thấy. Mai chơi nhé!"
	if weather != null and weather.kind in ["storm", "drizzle"]:
		return "Mưa ướt hết, đánh khăng trơn tay lắm!"
	if v.state == Villager.State.WALK and v.activity in ["school", "graze"]:
		return "{Self} đang phải đi, lúc khác chơi nhé!"
	if at != Vector3.INF and dir != Vector3.ZERO and not open_field(at, dir):
		return "Chỗ này hẹp quá, khăng bay vào nhà người ta mất. Ra bãi rộng mà chơi {you}!"
	return ""


## Phía trước đủ rộng cho khăng bay: tia ngang tầm 1 m trong 14 m ở 3 hướng toả quạt không vướng gì.
func open_field(at: Vector3, dir: Vector3) -> bool:
	if first_person == null:
		return true
	var space := first_person.get_world_3d().direct_space_state
	var mask := 1 << (FirstPerson.SOLID_LAYER - 1)
	for a: float in [-0.35, 0.0, 0.35]:
		var d := dir.rotated(Vector3.UP, a).normalized()
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.0, 0), at + Vector3(0, 1.0, 0) + d * 14.0, mask)
		if not space.intersect_ray(q).is_empty():
			return false
	return true


func _look_dir() -> Vector3:
	var fwd := -first_person.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized()


func join_at(v: Villager) -> void:
	for g in games:
		if (g.members as Array).has(v):
			_start_player(g)
			return


func start_with(v: Villager) -> void:
	if not player_game.is_empty() or first_person == null:
		return
	var dir := _look_dir()
	var hole := first_person.global_position + dir * 1.2
	hole.y = first_person.global_position.y
	var g := _new_game(hole, dir, false)
	for og in games.duplicate():
		if og != g and (og.members as Array).has(v):
			_end_game(og)
	_add_member(g, v)
	if villagers != null:
		var near: Array[Villager] = []
		for p in villagers.people:
			if p != v and p.visible and p.role in ["kid", "herder"] and p.global_position.distance_to(hole) < 30.0 \
					and refusal(p) == "" and not p.has_meta("talking") and not p.has_meta("at_school"):
				near.append(p)
		near.sort_custom(func(a: Villager, b: Villager) -> bool: return a.global_position.distance_to(hole) < b.global_position.distance_to(hole))
		for p in near.slice(0, 2):
			_add_member(g, p)
	var k := 0
	while (g.members as Array).size() < 2:
		_add_member(g, _make_temp(k, hole))
		k += 1
	_start_player(g)


func _start_player(g: Dictionary) -> void:
	if not player_game.is_empty():
		return
	player_game = g
	g.ambient = false
	g.t_left = 1.0e9
	g.round = 1
	if _avatar == null:
		_avatar = _make_avatar()
	_avatar.visible = true
	_avatar.global_position = (g.hole as Vector3) - (g.dir as Vector3) * 1.5
	_add_member(g, "player")
	# Người chơi vào thì chơi lại từ đầu: xoá điểm, vòng 1, người chơi đánh trước
	(g.order as Array).erase("player")
	(g.order as Array).push_front("player")
	for nm in (g.score as Dictionary).keys():
		g.score[nm] = 0
	g.turns = 0
	g.turn_i = -1
	g.done = false
	g.thrower = null
	(g.tried as Array).clear()
	_next_turn(g)
	for k in g.members:
		if k is Villager:
			_bark(k as Villager, "Chơi lại từ đầu! {You} đánh trước đi!")
			break
	first_person._suspend("khang")
	if hud != null:
		hud.visible = false
	_ui.visible = true
	_cam.make_current()
	_update_camera(g, 1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func stop_player() -> void:
	if player_game.is_empty():
		return
	var g := player_game
	player_game = {}
	_charging = false
	_fast = false
	Engine.time_scale = 1.0
	(g.members as Array).erase("player")
	(g.order as Array).erase("player")
	_avatar.visible = false
	_ui.visible = false
	if hud != null:
		hud.visible = true
	var at_site := false
	for s in sites:
		if (g.hole as Vector3).distance_to(s) < 3.0:
			at_site = true
	if at_site:
		g.ambient = true
		g.done = false
		g.round = 1
		g.t_left = _rng.randf_range(20.0, 40.0)
		if g.striker is String:
			_next_turn(g)
		first_person.global_position = (g.hole as Vector3) - (g.dir as Vector3) * 2.5 + Vector3(0, 0.1, 0)
	else:
		_end_game(g)
	first_person._resume()


func _make_avatar() -> Villager:
	var female: bool = dialogue != null and dialogue.player_female
	var a := Villager.new()
	a.name = "KhangPlayer"
	a.role = "farmer"
	a.display_name = "Bạn"
	a.home = {"name": "", "key": ""}
	a.set_meta("female", female)
	add_child(a)
	var look: Dictionary = villagers._look("farmer", female) if villagers != null else {}
	look["hat"] = "none"
	look["prop"] = "none"
	look["scale"] = 0.86
	a.build_person(look)
	_give_bat(a)
	return a


func _make_temp(k: int, hole: Vector3) -> Villager:
	var t := Villager.new()
	t.name = "KhangKid%d" % k
	t.role = "kid"
	t.role_name = "Trẻ con nhà bên"
	t.display_name = TEMP_NAMES[(k + _rng.randi_range(0, 5)) % TEMP_NAMES.size()]
	t.home = {"name": "Nhà bên", "key": ""}
	t.set_meta("female", false)
	add_child(t)
	t.build_person(villagers._look("kid", false) if villagers != null else {})
	var a := _rng.randf() * TAU
	t.global_position = hole + Vector3(cos(a), 0, sin(a)) * 8.0
	_temps.append(t)
	return t


func _unhandled_input(event: InputEvent) -> void:
	if player_game.is_empty():
		return
	var g := player_game
	if event.is_action_pressed("exit_interior") or (g.done and event.is_action_pressed("interact")):
		stop_player()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fish_reel"):
		player_press()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("fish_reel"):
		player_release()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not (g.striker is String):
		_fast = not _fast          # tua nhanh lượt của bọn trẻ
		Engine.time_scale = 3.0 if _fast else 1.0
		get_viewport().set_input_as_handled()


## Space / chuột trái nhấn: bắt đầu lấy lực (hất), vụt đỡ, gõ khăng nảy, vụt khăng.
func player_press() -> void:
	var g := player_game
	if g.is_empty() or not (g.striker is String):
		return
	match String(g.phase):
		"flick_ready":
			_charging = true
			_charge = 0.0
		"throw_flight":
			_try_bat(g, 1.0)
		"strike_ready":
			_tap(g)
		"hop":
			_strike(g, float(g.hop_t))


func player_release() -> void:
	var g := player_game
	if g.is_empty() or not _charging:
		return
	_charging = false
	if String(g.phase) == "flick_ready" and g.striker is String:
		_flick(g, _charge)


# --- Diễn biến một lượt ------------------------------------------------------------------------------

func _name(v: Variant) -> String:
	return "Bạn" if v is String else (v as Villager).display_name


func _skill(g: Dictionary, v: Variant) -> float:
	return float((g.skill as Dictionary).get(_name(v), 0.6))


func _aim_dir(g: Dictionary) -> Vector3:
	return (g.dir as Vector3).rotated(Vector3.UP, float(g.aim))


func _fielders(g: Dictionary) -> Array[Villager]:
	var out: Array[Villager] = []
	for v: Variant in g.members:
		if v is Villager and not is_same(v, g.striker):
			out.append(v)
	return out


func _reset_stick(g: Dictionary) -> void:
	g.pos = (g.hole as Vector3) + Vector3(0, 0.03, 0)
	g.vel = Vector3.ZERO
	g.flying = false
	var st := g.stick as Node3D
	st.global_position = g.pos
	st.rotation = Vector3(0, atan2((g.dir as Vector3).x, (g.dir as Vector3).z) + PI * 0.5, 0)
	st.visible = true


func _next_turn(g: Dictionary) -> void:
	var order: Array = g.order
	if order.is_empty():
		return
	g.turn_i = (int(g.turn_i) + 1) % order.size()
	if int(g.turn_i) == 0 and int(g.turns) > 0:
		g.round = int(g.round) + 1
	g.striker = order[g.turn_i]
	g.turns = int(g.turns) + 1
	g.strikes_left = strikes
	g.aim = 0.0
	g.pts = 0
	g.msg = ""
	_reset_stick(g)
	# Bên đỡ toả ra phía trước
	var side := (g.dir as Vector3).cross(Vector3.UP)
	var k := 0
	for f in _fielders(g):
		f.set_meta("khang_home", (g.hole as Vector3) + (g.dir as Vector3) * _rng.randf_range(7.0, 15.0) + side * (k * 3.5 - 3.5 + _rng.randf_range(-1.0, 1.0)))
		k += 1
	g.phase = "flick_ready"
	g.t = 1.4
	if g.striker is Villager:
		_bark(g.striker as Villager, ["Đến lượt {self}!", "Xem {self} hất này!", "Đứng xa ra!"][_rng.randi_range(0, 2)])
	if player_game == g and g.striker is String:
		_fast = false
		Engine.time_scale = 1.0


## Hất khăng: lực 0…1.
func _flick(g: Dictionary, power: float) -> void:
	var d := _aim_dir(g)
	var sp := lerpf(flick_speed.x, flick_speed.y, clampf(power, 0.0, 1.0))
	g.vel = d * sp + Vector3(0, 3.5 + 3.0 * power, 0)
	g.pos = (g.hole as Vector3) + Vector3(0, 0.08, 0) + d * 0.15
	_launch(g, "flick_flight")
	_swing(g.striker)


func _launch(g: Dictionary, phase: String) -> void:
	g.phase = phase
	g.flying = true
	g.catchable = phase != "throw_flight"
	g.tried = []
	# Bên đỡ chạy tới chỗ khăng sắp rơi (máy đoán điểm rơi)
	var land := _predict(g.pos as Vector3, g.vel as Vector3, float((g.hole as Vector3).y))
	g.land = land


func _predict(p: Vector3, v: Vector3, ground: float) -> Vector3:
	var pp := p
	var vv := v
	for i in 400:
		vv.y -= G / 60.0
		pp += vv / 60.0
		if pp.y <= ground + 0.03 and vv.y < 0.0:
			break
	return pp


func _tap(g: Dictionary) -> void:
	g.vel = _aim_dir(g) * 0.4 + Vector3(0, hop_speed, 0)
	g.pos = (g.pos as Vector3) + Vector3(0, 0.05, 0)
	g.hop_t = 0.0
	g.flying = true
	g.catchable = false
	g.phase = "hop"
	_swing(g.striker, 0.5)


## Vụt khăng đang nảy; `t` = thời gian từ lúc gõ. Gần đỉnh nảy (vy = 0) thì bay xa nhất.
func _strike(g: Dictionary, t: float) -> void:
	var apex := hop_speed / G
	var q := 1.0 - absf(t - apex) / strike_window
	_swing(g.striker)
	if q <= 0.0:
		g.msg = "Vụt hụt!"
		g.hop_t = -2.0          # đã vụt (hụt): chờ khăng rơi
		return
	g.vel = _aim_dir(g) * lerpf(strike_speed.x, strike_speed.y, q) + Vector3(0, 1.6 + 2.6 * q, 0)
	g.msg = "Vụt trúng!" if q < 0.75 else "Vụt đẹp!"
	_launch(g, "strike_flight")


## Vụt đỡ khăng bị ném về (người chơi bấm, máy thì theo kỹ năng). Chỉ vụt được khi khăng tới gần.
func _try_bat(g: Dictionary, skill: float) -> void:
	if bool(g.bat_tried):
		return
	var p := g.pos as Vector3
	var bat_at := g.hole as Vector3
	var d := Vector2(p.x - bat_at.x, p.z - bat_at.z).length()
	g.bat_tried = true
	_swing(g.striker)
	if d > 2.2 or d < 0.15 or p.y > (bat_at.y + 1.6) or _rng.randf() > skill:
		g.msg = "Đỡ hụt!"
		return
	var away := _aim_dir(g).rotated(Vector3.UP, _rng.randf_range(-0.4, 0.4))
	g.vel = away * _rng.randf_range(7.0, 12.0) + Vector3(0, 3.5, 0)
	g.msg = "Đỡ được!"
	_launch(g, "bat_flight")


func _swing(v: Variant, amount: float = 1.0) -> void:
	var k: Villager = _avatar if v is String else v as Villager
	if k != null:
		k.set_meta("swing_t", 0.0)
		k.set_meta("swing_amt", amount)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	for g in games.duplicate():
		step(g, dt)
	if not player_game.is_empty():
		if _charging:
			_charge = minf(_charge + dt / charge_time, 1.0)
		_update_camera(player_game, dt)
		_update_ui(player_game, dt)


## Một bước của một cuộc chơi (tách riêng cho bài thử).
func step(g: Dictionary, dt: float) -> void:
	var h := day_night.time_of_day if day_night != null else 15.0
	g.age = float(g.get("age", 0.0)) + dt
	if g.ambient:
		g.t_left = float(g.t_left) - dt
		var bad := weather != null and weather.kind in ["storm", "drizzle"]
		var school := villagers != null and villagers.school_day != null and villagers.school_day.wants_pupils(h)
		var lonely := (g.members as Array).size() < 2 and float(g.age) > 30.0   # chờ bạn tới tối đa 30 s
		if float(g.t_left) <= 0.0 or h >= 18.0 or bad or school or lonely:
			_end_game(g)
			return
	elif weather != null and weather.kind == "storm":
		stop_player()
		if games.has(g):
			_end_game(g)
		return
	if (g.members as Array).size() < 2:
		_pose(g, dt)
		return
	if g.striker == null:
		_next_turn(g)
	g.t = float(g.t) - dt
	var striker: Variant = g.striker
	var ai: bool = striker is Villager
	match String(g.phase):
		"flick_ready":
			if ai and float(g.t) <= 0.0:
				var sk := _skill(g, striker)
				g.aim = _rng.randf_range(-0.35, 0.35)
				_flick(g, clampf(_rng.randf_range(0.35, 1.0) * (0.6 + 0.5 * sk), 0.2, 1.0))
		"flick_flight", "bat_flight", "strike_flight", "throw_flight", "hop":
			_fly(g, dt)
		"pickup":
			var th := g.thrower as Villager
			var p := g.pos as Vector3
			if Vector2(th.global_position.x - p.x, th.global_position.z - p.z).length() < 0.5:
				# Tới nơi: cúi nhặt (0,5 s) rồi ném
				g.pick_wait = float(g.get("pick_wait", 0.5)) - dt
				if float(g.pick_wait) <= 0.0:
					g.erase("pick_wait")
					_throw_back(g)
		"strike_walk":
			var sv: Villager = _avatar if striker is String else striker as Villager
			var p2 := g.pos as Vector3
			if Vector2(sv.global_position.x - p2.x, sv.global_position.z - p2.z).length() < 0.9:
				g.phase = "strike_ready"
				g.t = 1.0
				g.hop_t = -1.0
		"strike_ready":
			if ai and float(g.t) <= 0.0:
				_tap(g)
		"result":
			if float(g.t) <= 0.0:
				_next_turn(g)
	# Máy vụt khăng đang nảy / vụt đỡ khăng ném về
	if ai and String(g.phase) == "hop" and float(g.hop_t) >= 0.0:
		var sk2 := _skill(g, striker)
		if not g.has("ai_strike_at"):
			g.ai_strike_at = hop_speed / G + _rng.randfn(0.0, 0.05 + 0.2 * (1.0 - sk2))
		if float(g.hop_t) >= float(g.ai_strike_at):
			g.erase("ai_strike_at")
			_strike(g, float(g.hop_t))
	if ai and String(g.phase) == "throw_flight" and not bool(g.bat_tried):
		var p3 := g.pos as Vector3
		var hh := g.hole as Vector3
		if Vector2(p3.x - hh.x, p3.z - hh.z).length() < 1.8 and float((g.vel as Vector3).y) < 0.0:
			g.aim = _rng.randf_range(-0.4, 0.4)
			_try_bat(g, _skill(g, striker) * 0.75)
	_pose(g, dt)
	var lb := g.label as Label3D
	lb.global_position = (g.hole as Vector3) + Vector3(0, 2.4, 0)
	lb.visible = player_game != g and String(g.phase) == "result"


func _fly(g: Dictionary, dt: float) -> void:
	var v := g.vel as Vector3
	var p := g.pos as Vector3
	v.y -= G * dt
	v.x *= 1.0 - 0.05 * dt
	v.z *= 1.0 - 0.05 * dt
	p += v * dt
	if float(g.hop_t) >= 0.0 and String(g.phase) == "hop":
		g.hop_t = float(g.hop_t) + dt
	elif String(g.phase) == "hop":
		g.hop_t = float(g.hop_t)   # đã vụt hụt: chờ rơi
	var ground := float((g.hole as Vector3).y)
	var st := g.stick as Node3D
	st.rotate_object_local(Vector3.FORWARD, dt * v.length() * 2.0)
	# Bên đỡ bắt khăng đang rơi
	if bool(g.catchable) and v.y < 0.0:
		for f in _fielders(g):
			if (g.tried as Array).has(f):
				continue
			var fp := f.global_position
			if Vector2(fp.x - p.x, fp.z - p.z).length() < catch_radius and p.y - fp.y > 0.3 and p.y - fp.y < 1.8:
				(g.tried as Array).append(f)
				f.set_meta("catch_t", 0.0)
				if _rng.randf() < _skill(g, f) * catch_skill:
					_caught(g, f)
					return
				_bark(f, ["Tuột tay rồi!", "Ối, trượt!"][_rng.randi_range(0, 1)])
	if p.y <= ground + 0.03 and v.y < 0.0:
		p.y = ground + 0.03
		if v.y < -2.5:
			v = Vector3(v.x * 0.35, -v.y * 0.2, v.z * 0.35)     # nảy nhẹ trên đất
		else:
			g.pos = p
			g.vel = Vector3.ZERO
			g.flying = false
			st.global_position = p
			_landed(g)
			return
	g.pos = p
	g.vel = v
	st.global_position = p


func _caught(g: Dictionary, f: Villager) -> void:
	g.flying = false
	(g.stick as Node3D).visible = false
	_bark(f, ["Bắt được rồi! Chết nhé!", "Ha ha, bắt dính!", "Vào tay {self} rồi!"][_rng.randi_range(0, 2)])
	_finish_turn(g, 0, true, "%s bắt được khăng — chết!" % f.display_name)


func _landed(g: Dictionary) -> void:
	var phase := String(g.phase)
	var hole := g.hole as Vector3
	var p := g.pos as Vector3
	var d := Vector2(p.x - hole.x, p.z - hole.z).length()
	match phase:
		"flick_flight":
			# Đứa đỡ gần nhất chạy tới nhặt, ném về lỗ
			var best: Villager = null
			for f in _fielders(g):
				if best == null or f.global_position.distance_to(p) < best.global_position.distance_to(p):
					best = f
			g.thrower = best
			g.phase = "pickup"
			g.t = 0.6
		"throw_flight":
			if d <= khang_len:
				_finish_turn(g, 0, true, "Khăng rơi sát lỗ — chết!")
				if g.thrower is Villager:
					_bark(g.thrower as Villager, ["Trúng lỗ rồi!", "Chết nhé!"][_rng.randi_range(0, 1)])
			else:
				_begin_strikes(g)
		"bat_flight":
			_begin_strikes(g)
		"hop":
			# Gõ nảy mà không vụt (hoặc vụt hụt): mất một lần đánh
			if String(g.msg) != "Vụt hụt!":
				g.msg = "Không vụt kịp!"
			_after_strike(g)
		"strike_flight":
			_after_strike(g)


func _throw_back(g: Dictionary) -> void:
	var th := g.thrower as Villager
	var p := th.global_position + Vector3(0, 1.0, 0)
	var hole := g.hole as Vector3
	var err := 0.4 + 1.4 * (1.0 - _skill(g, th))
	var target := hole + Vector3(_rng.randfn(0.0, err), 0, _rng.randfn(0.0, err))
	var flat := Vector2(target.x - p.x, target.z - p.z)
	var T := clampf(flat.length() / 8.0, 0.7, 1.8)
	g.pos = p
	g.vel = Vector3(flat.x / T, (target.y - p.y + 0.5 * G * T * T) / T, flat.y / T)
	g.bat_tried = false
	(g.stick as Node3D).visible = true
	_swing(th)
	_launch(g, "throw_flight")


func _begin_strikes(g: Dictionary) -> void:
	g.phase = "strike_walk"
	g.strikes_left = strikes


func _after_strike(g: Dictionary) -> void:
	g.strikes_left = int(g.strikes_left) - 1
	if int(g.strikes_left) > 0:
		g.phase = "strike_walk"
	else:
		var hole := g.hole as Vector3
		var p := g.pos as Vector3
		var pts := int(floorf(Vector2(p.x - hole.x, p.z - hole.z).length() / khang_len))
		_finish_turn(g, pts, false, "Được %d khăng!" % pts)


func _finish_turn(g: Dictionary, pts: int, out: bool, msg: String) -> void:
	var who := _name(g.striker)
	var sc := g.score as Dictionary
	sc[who] = int(sc.get(who, 0)) + pts
	g.pts = pts
	g.msg = msg
	g.phase = "result"
	g.t = 2.4
	g.flying = false
	(g.label as Label3D).text = "%s: %s" % [who, "chết" if out else "%d khăng" % pts]
	turn_done.emit(who, pts, out)
	if g.striker is Villager and not out:
		_bark(g.striker as Villager, ["Được %d khăng nhé!" % pts, "Đếm đi, %d khăng!" % pts][_rng.randi_range(0, 1)])
	_big_t = 2.2
	# Hết số vòng (cuộc chơi có người chơi): tổng kết
	if player_game == g and int(g.turn_i) == (g.order as Array).size() - 1 and int(g.round) >= rounds:
		g.done = true
		g.t = 1.0e9
		var names := sc.keys()
		names.sort_custom(func(a: String, b: String) -> bool: return int(sc[a]) > int(sc[b]))
		g.msg = "Hết %d vòng! %s thắng với %d khăng." % [rounds, names[0], int(sc[names[0]])]
		_fast = false
		Engine.time_scale = 1.0


# --- Dáng, vị trí ------------------------------------------------------------------------------------

func _pose(g: Dictionary, dt: float) -> void:
	var hole := g.hole as Vector3
	var dir := g.dir as Vector3
	var striker: Variant = g.striker
	var phase := String(g.phase)
	for v: Variant in g.members:
		var k: Villager = _avatar if v is String else v as Villager
		if k == null:
			continue
		var to := hole - dir * 0.55 + dir.cross(Vector3.UP) * 0.25
		var face := hole + dir * 5.0
		var speed := 1.8
		if is_same(v, striker):
			if phase in ["strike_walk", "strike_ready", "hop"] or (phase in ["strike_flight", "result"] and int(g.strikes_left) < strikes):
				var p := g.pos as Vector3
				to = Vector3(p.x, hole.y, p.z) - _aim_dir(g) * 0.55 + _aim_dir(g).cross(Vector3.UP) * 0.25
				face = to + _aim_dir(g) * 5.0
				speed = 2.6
			else:
				face = hole + _aim_dir(g) * 5.0
		else:
			var fk := k as Villager
			if fk.has_meta("khang_home"):
				to = fk.get_meta("khang_home")
			face = g.pos as Vector3
			if phase in ["flick_flight", "bat_flight", "strike_flight"] and g.has("land"):
				var land := g.land as Vector3
				if land.distance_to(fk.global_position) < 9.0:
					to = land
					speed = run_speed
			elif phase == "pickup" and is_same(g.thrower, fk):
				to = g.pos as Vector3
				speed = run_speed
		_walk_to(k, Vector3(to.x, hole.y, to.z), face, speed, dt)
		# Khăng cái: vụt (vung tay), cầm chờ (tay đưa xuống trước), bắt (giơ tay)
		if k.arms.size() == 2:
			var sw := float(k.get_meta("swing_t", -1.0))
			if sw >= 0.0:
				sw += dt
				k.set_meta("swing_t", sw if sw < 0.35 else -1.0)
				var u := clampf(sw / 0.3, 0.0, 1.0)
				var amt := float(k.get_meta("swing_amt", 1.0))
				k.arms[1].rotation.x = lerpf(-2.0 * amt, 0.7 * amt, ease(u, 0.4))
			elif is_same(v, striker):
				k.arms[1].rotation.x = -0.45
			var ct := float(k.get_meta("catch_t", -1.0))
			if ct >= 0.0:
				ct += dt
				k.set_meta("catch_t", ct if ct < 0.6 else -1.0)
				k.arms[0].rotation.x = -2.6
				k.arms[1].rotation.x = -2.6
	if g.striker != null and g.flying == false and phase in ["flick_ready"]:
		_reset_stick(g)


func _walk_to(v: Villager, to: Vector3, face: Vector3, speed: float, dt: float) -> void:
	var p := v.global_position
	p.y = to.y
	var d := Vector3(to.x - p.x, 0, to.z - p.z)
	if d.length() > 0.08:
		var stp := minf(d.length(), speed * dt)
		v.global_position = p + d.normalized() * stp
		v.rotation.y = atan2(d.x, d.z)
		v._walk_amount = move_toward(v._walk_amount, clampf(speed / 2.0, 0.5, 1.0), dt * 6.0)
		v.speed_mul = 1.0 + (1.0 if speed > 2.5 else 0.0)
	else:
		v.global_position = p
		var f := face - p
		v.rotation.y = lerp_angle(v.rotation.y, atan2(f.x, f.z), minf(dt * 6.0, 1.0))
		v._walk_amount = move_toward(v._walk_amount, 0.0, dt * 6.0)
	if v.get_parent() == self and v != _avatar:
		v.state = Villager.State.IDLE
		v.tick(dt, true)
	elif v == _avatar:
		v._animate(dt)


func _bark(v: Villager, text: String) -> void:
	if dialogue != null and is_instance_valid(v):
		dialogue.bark(v, dialogue.fill_for(v, text))


# --- Camera, giao diện -------------------------------------------------------------------------------

func _update_camera(g: Dictionary, dt: float) -> void:
	var hole := g.hole as Vector3
	var aim := _aim_dir(g)
	var sv: Villager = _avatar if g.striker is String else (g.striker as Villager if g.striker is Villager else _avatar)
	var base := sv.global_position if sv != null else hole
	# Camera đứng lệch sang phía khăng con (người đánh đứng lệch phía kia) để thấy khăng nảy
	var want := base - aim * 3.4 + Vector3(0, 2.1, 0) - aim.cross(Vector3.UP) * 1.4
	var look := base + aim * 7.0
	if bool(g.flying) and String(g.phase) != "hop":
		var p := g.pos as Vector3
		want = base - aim * 5.0 + Vector3(0, 4.2, 0)
		look = p.lerp(base, 0.25)
	var t := 1.0 - exp(-4.0 * dt)
	_cam.global_position = _cam.global_position.lerp(want, t) if dt < 0.9 else want
	var cur := _cam.global_transform.basis.orthonormalized()
	var target := Basis.looking_at(look - _cam.global_position, Vector3.UP)
	_cam.global_transform.basis = cur.slerp(target, t) if dt < 0.9 else target


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	var top := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	top.add_theme_stylebox_override("panel", sb)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 16
	_ui.add_child(top)
	var box := VBoxContainer.new()
	top.add_child(box)
	_top = _label(true, 24, Palette.HUD_TEXT)
	_sub = _label(false, 16, Palette.HUD_SUBTEXT)
	box.add_child(_top)
	box.add_child(_sub)
	_power_bg = ColorRect.new()
	_power_bg.color = Color(0, 0, 0, 0.4)
	_power_bg.custom_minimum_size = Vector2(320, 14)
	_power_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_power_bg)
	_power_bar = ColorRect.new()
	_power_bar.color = Palette.FLOWER_YELLOW
	_power_bar.size = Vector2(0, 14)
	_power_bg.add_child(_power_bar)
	_big = _label(true, 64, Palette.HUD_TEXT)
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_big.grow_vertical = Control.GROW_DIRECTION_BOTH
	_big.offset_top = -300
	_big.add_theme_constant_override("outline_size", 12)
	_big.add_theme_color_override("font_outline_color", Palette.WINDOW_DARK)
	_ui.add_child(_big)


func _label(bold: bool, size: int, col: Color, text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", Hud.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _update_ui(g: Dictionary, dt: float) -> void:
	var striker: Variant = g.striker
	var who := _name(striker) if striker != null else "…"
	var mine: bool = striker is String
	_top.text = "Đánh khăng  ·  vòng %d/%d  ·  lượt: %s%s" % [mini(int(g.round), rounds), rounds, who,
			("  ·  còn %d lần đánh" % int(g.strikes_left)) if String(g.phase) in ["strike_walk", "strike_ready", "hop", "strike_flight"] else ""]
	var sc := g.score as Dictionary
	var names := sc.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return int(sc[a]) > int(sc[b]))
	var rows: Array[String] = []
	for n: String in names:
		rows.append("%s %d" % [n, int(sc[n])])
	var how := ""
	if g.done:
		how = "E / Esc: thôi chơi"
	elif mine:
		how = {"flick_ready": "Hất khăng: A / D ngắm hướng, giữ Space / chuột trái lấy lực rồi thả",
				"flick_flight": "Khăng đang bay — bọn trẻ chạy theo bắt…",
				"pickup": "Bọn trẻ nhặt khăng ném về lỗ — sẵn sàng vụt đỡ!",
				"throw_flight": "Khăng đang bay về — bấm Space / chuột trái để vụt đỡ khi khăng tới gần!",
				"bat_flight": "Khăng bay xa — bọn trẻ chạy theo bắt…",
				"strike_walk": "Ra chỗ khăng nằm…",
				"strike_ready": "Đánh khăng: bấm để gõ khăng nảy lên, bấm lần nữa vụt lúc khăng lên cao nhất (A / D ngắm)",
				"hop": "VỤT! (bấm lúc khăng lên cao nhất)",
				"strike_flight": "Khăng bay…",
				"result": ""}.get(String(g.phase), "")
	else:
		how = "Lượt của %s — E: tua nhanh%s  ·  Esc: thôi" % [who, " (đang tua)" if _fast else ""]
	_sub.text = "Điểm: %s\n%s" % [", ".join(rows), how]
	_power_bg.visible = mine and String(g.phase) == "flick_ready"
	_power_bar.size.x = 320.0 * _charge
	_big_t = maxf(_big_t - dt, 0.0)
	if g.done:
		_big.text = String(g.msg)
	elif String(g.msg) != "" and (_big_t > 0.0 or String(g.phase) in ["hop", "strike_walk", "strike_ready"]):
		_big.text = String(g.msg)
	else:
		_big.text = ""
