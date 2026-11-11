class_name TugOfWar
extends Node3D
## Trò chơi dân gian kéo co (mục 43). Hai đội nắm hai đầu dây thừng, giữa dây buộc dải vải đỏ; đội nào kéo dải đỏ
## qua vạch của mình (`win_dist`) thì thắng hiệp; thắng 2 trong 3 hiệp là thắng cuộc.
## - Dân làng tự chơi: việc `tug` của Villagers (trẻ con, trẻ chăn trâu, đàn ông) ở bãi `site` ngoài cổng làng phía tây
##   lúc chiều (ngày hội thì cả buổi sáng); đủ mỗi bên 3 người là kéo.
## - Người chơi: nhìn người đang kéo "E: Xin kéo co cùng" (`join_at` — chơi lại từ đầu) hoặc rủ qua hội thoại
##   (`start_with`). Bấm Space / chuột trái ĐÚNG NHỊP hò "Hò dô ta!" để dồn sức (`power`); bấm lệch thì hụt hơi.
## - `step(dt)` tách riêng cho bài thử.

signal finished(won: bool, mine: int, theirs: int)

@export var villagers: Villagers
@export var first_person: FirstPerson
@export var dialogue: Dialogue
@export var hud: Hud
@export var day_night: DayNight
@export var weather: Weather
@export var village: Village
@export var festival: Festival
@export_group("Dây")
## Tâm bãi kéo co (giữa tường trường và đường đất, phía tây cổng làng) và hướng dây.
@export var site: Vector3 = Vector3(-34.0, 0.05, -10.5)
@export var site_axis: Vector3 = Vector3(0, 0, 1)
@export var team_size: int = 4
@export var spacing: float = 0.95
@export var front_gap: float = 1.7
@export var rope_height: float = 0.92
## Dải đỏ lệch quá chừng này (m) là thắng hiệp.
@export var win_dist: float = 2.2
@export var pull_speed: float = 1.15
@export var round_seconds: float = 40.0
@export var rounds_to_win: int = 2
@export_group("Người chơi")
## Nhịp hò (giây) và độ lệch cho phép.
@export var beat_period: float = 0.9
@export var beat_window: float = 0.14
@export var hit_gain: float = 0.22
@export var miss_loss: float = 0.08
@export var power_decay: float = 0.10
## Hệ số sức kéo tụt (Inventory đặt khi người chơi no bụng, mục 48).
var decay_scale: float = 1.0
## Sức đội mình = base + gain × power; đội kia = base + dao động + cơn rướn.
@export var my_base: float = 0.72
@export var my_gain: float = 0.6
@export var their_base: float = 0.95
@export_group("Dân làng tự chơi")
@export var ambient_hours: Vector2 = Vector2(15.5, 17.7)
@export var gather_wait: float = 35.0
@export var random_seed: int = 4343

const TEMP_NAMES: Array[String] = ["Anh Tí", "Chú Sửu", "Cu Dần", "Anh Mão", "Cu Thìn", "Chú Tị"]
const CHEERS: Array[String] = ["Hò dô ta!", "Kéo đi! Kéo đi!", "Cố lên!", "Ghì chặt vào!", "Dô ta nào!"]

## Cuộc kéo co đang diễn ra (rỗng = không có). teams[0] ở phía −axis, teams[1] ở phía +axis; "player" luôn ở đội 0.
var g: Dictionary = {}
var playing: bool = false          # người chơi đang kéo
var power: float = 0.0
var streak: int = 0
var stats: Dictionary = {"rounds": 0, "matches": 0}
var _rng := RandomNumberGenerator.new()
var _avatar: Villager
var _temps: Array[Villager] = []
var _cam: Camera3D
var _ui: CanvasLayer
var _top: Label
var _sub: Label
var _big: Label
var _pos_mark: ColorRect
var _beat_dot: ColorRect
var _power_bar: ColorRect
var _beat_t: float = 0.0
var _beat_used: bool = false
var _msg: String = ""
var _msg_t: float = 0.0


func _ready() -> void:
	_rng.seed = random_seed
	_cam = Camera3D.new()
	_cam.name = "TugCam"
	_cam.top_level = true
	_cam.fov = 55.0
	add_child(_cam)
	_build_ui()


# --- Dân làng tự chơi ----------------------------------------------------------------------------

## Có nên rủ nhau ra kéo co giờ này không (Villagers hỏi khi chọn việc).
func ambient_ok(h: float) -> bool:
	if weather != null and weather.kind in ["storm", "drizzle"]:
		return false
	if playing or (not g.is_empty() and (_count(0) >= team_size and _count(1) >= team_size)):
		return false
	if not g.is_empty() and not _site_game():
		return false
	var fest := festival != null and festival.mode != ""
	return (h >= ambient_hours.x and h < ambient_hours.y) or (fest and h >= 8.0 and h < 11.0)


func site_target(_v: Villager) -> Vector3:
	return site + Vector3(_rng.randf_range(2.0, 3.5), 0.0, _rng.randf_range(-3.0, 3.0))


## Villagers gọi khi một người tới bãi.
func on_arrive(v: Villager) -> void:
	if g.is_empty():
		_new_game(site, site_axis, true)
	if not _site_game() or (_count(0) >= team_size and _count(1) >= team_size) or str(g.phase) != "gather":
		v.dwell = 0.0
		return
	_add_member(v, 0 if _count(0) <= _count(1) else 1)


func is_member(v: Villager) -> bool:
	return v != null and v.has_meta("tug")


func _count(t: int) -> int:
	return (g.teams[t] as Array).size() if not g.is_empty() else 0


func _site_game() -> bool:
	return not g.is_empty() and (g.center as Vector3).distance_to(site) < 2.0


func _new_game(center: Vector3, axis: Vector3, ambient: bool) -> void:
	g = {"center": center, "axis": axis.normalized(), "teams": [[], []], "x": 0.0, "vel": 0.0, "score": [0, 0],
			"round": 1, "phase": "gather", "t": 0.0, "ambient": ambient, "bias": [0.0, 0.0],
			"ph": [_rng.randf() * TAU, _rng.randf() * TAU], "surge": 0.0, "surge_in": 5.0, "cheer": 2.0}
	var root := Node3D.new()
	root.name = "TugGame"
	root.top_level = true
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(-g.axis, Vector3.UP), center)
	# Vạch vôi: vạch giữa + hai vạch thắng
	var mb := MeshBuilder.new(random_seed, 0.02)
	for z: float in [0.0, -win_dist, win_dist]:
		mb.add_box(Vector3(2.4, 0.012, 0.07), Color(0.95, 0.94, 0.88) if z == 0.0 else Palette.FLAG_RED.lerp(Color.WHITE, 0.55),
				Transform3D(Basis(), Vector3(0, 0.0, z)))
	root.add_child(mb.commit_instance("Marks"))
	var mi := MeshInstance3D.new()
	mi.name = "Rope"
	mi.top_level = true
	mi.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	var lb := Label3D.new()
	lb.font = Hud.font(true)
	lb.font_size = 64
	lb.pixel_size = 0.006
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Palette.FLOWER_YELLOW
	lb.outline_size = 10
	lb.outline_modulate = Palette.WINDOW_DARK
	lb.position = Vector3(0, 2.7, 0)
	root.add_child(lb)
	g["root"] = root
	g["rope"] = mi
	g["label"] = lb


func _add_member(v: Villager, t: int) -> void:
	v.set_meta("tug", true)
	v.set_meta("talking", true)
	v.state = Villager.State.IDLE
	v.visible = true
	v.dwell = 1.0e6
	v.work_anim = "idle"
	if v.prop_node != null:
		v.prop_node.visible = false
	v.activity_text = "đang chơi kéo co"
	(g.teams[t] as Array).append(v)


## Tan cuộc: trả mọi người về Villagers, xoá người tạm, dây, vạch.
func _end_game() -> void:
	if g.is_empty():
		return
	for t in 2:
		for m: Variant in g.teams[t]:
			if not (m is Villager) or not is_instance_valid(m):
				continue
			var v := m as Villager
			v.remove_meta("tug")
			v.remove_meta("talking")
			if v.prop_node != null:
				v.prop_node.visible = true
			v.work_anim = "idle"
			if v.body != null:
				v.body.rotation.x = 0.0
			if _temps.has(v):
				_temps.erase(v)
				v.queue_free()
			else:
				v.dwell = 0.0
	(g.root as Node).queue_free()
	g = {}


# --- Người chơi ------------------------------------------------------------------------------------

## Lời từ chối khi rủ (rỗng = đồng ý).
func refusal(v: Villager, at: Vector3 = Vector3.INF, fwd: Vector3 = Vector3.ZERO) -> String:
	if not v.role in ["kid", "herder", "farmer"]:
		return "Già rồi, kéo sao nổi! Rủ bọn thanh niên ấy." if v.role == "elder" else "{Self} đang bận gánh hàng, rủ người khác nhé."
	if v.has_meta("in_class"):
		return "Đang giờ học mà {you}!"
	var h := day_night.time_of_day if day_night != null else 15.0
	if h >= 19.0 or h < 6.0:
		return "Tối rồi, mai ra bãi mà kéo!"
	if weather != null and weather.kind in ["storm", "drizzle"]:
		return "Mưa trơn thế này kéo là ngã dúi dụi!"
	if v.state == Villager.State.WALK and v.activity in ["school", "graze", "worship", "market_sell"]:
		return "{Self} đang dở việc, lúc khác chơi nhé!"
	if at != Vector3.INF and not open_ground(at, fwd):
		return "Chỗ này chật, không đủ chỗ căng dây. Ra bãi rộng đi {you}!"
	return ""


## Đủ chỗ căng dây: dọc hai phía (ngang so với hướng nhìn) 6,5 m không vướng gì ở tầm 0,5 và 1,4 m.
func open_ground(at: Vector3, fwd: Vector3) -> bool:
	if first_person == null or fwd == Vector3.ZERO:
		return true
	var space := first_person.get_world_3d().direct_space_state
	var mask := 1 << (FirstPerson.SOLID_LAYER - 1)
	var c := at + fwd.normalized() * 3.0
	var ax := fwd.normalized().cross(Vector3.UP)
	for s: float in [-1.0, 1.0]:
		for hgt: float in [0.5, 1.4]:
			var from := c + Vector3(0, hgt, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + ax * s * 6.5, mask)
			if not space.intersect_ray(q).is_empty():
				return false
	return true


## Nhìn một người đang kéo co + E: xin vào, chơi lại từ đầu.
func join_at(v: Villager) -> void:
	if not g.is_empty() and is_member(v):
		_start_player()


## Rủ qua hội thoại: căng dây ngang trước mặt người chơi.
func start_with(v: Villager) -> void:
	if playing or first_person == null:
		return
	if is_member(v):
		_start_player()
		return
	if not g.is_empty():
		_end_game()
	var fp := first_person.global_position
	var fwd := -first_person.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var center := fp + fwd * 3.0
	center.y = fp.y
	_new_game(center, fwd.cross(Vector3.UP), false)
	_add_member(v, 0)
	if villagers != null:
		var near: Array[Villager] = []
		for p in villagers.people:
			if p != v and p.visible and p.role in ["kid", "herder", "farmer"] and p.global_position.distance_to(center) < 35.0 \
					and not p.has_meta("talking") and not p.has_meta("at_school") and refusal(p) == "":
				near.append(p)
		near.sort_custom(func(a: Villager, b: Villager) -> bool: return a.global_position.distance_to(center) < b.global_position.distance_to(center))
		for p in near.slice(0, 5):
			_add_member(p, 1 if _count(1) < 3 else 0)
	var k := 0
	while _count(1) < 3 or _count(0) < 2:
		_add_member(_make_temp(k, center), 1 if _count(1) < 3 else 0)
		k += 1
	_start_player()


func _start_player() -> void:
	if playing or g.is_empty():
		return
	playing = true
	g.ambient = false
	# Người chơi luôn ở đội 0; đội 0 đông hơn thì chuyển bớt một người sang đội kia
	var t0: Array = g.teams[0]
	var t1: Array = g.teams[1]
	while t0.size() + 1 > t1.size() and t0.size() > 1:
		t1.append(t0.pop_back())
	while t1.size() > t0.size() + 1 and t1.size() > 1:
		t0.append(t1.pop_back())
	t0.push_front("player")
	_reset_match()
	for m: Variant in t0 + t1:
		if m is Villager:
			_bark(m as Villager, "Chơi lại từ đầu nhé! {You} vào đội này!")
			break
	first_person._suspend("tug")
	if _avatar == null:
		_avatar = _make_avatar()
	_avatar.visible = true
	_avatar.global_position = _slot(0, 0)
	if hud != null:
		hud.visible = false
	_ui.visible = true
	_cam.make_current()
	_update_camera(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _reset_match() -> void:
	g.score = [0, 0]
	g.round = 1
	_begin_round()


func _begin_round() -> void:
	g.x = 0.0
	g.vel = 0.0
	g.phase = "ready"
	g.t = 0.0
	g.bias = [_rng.randf_range(-0.07, 0.07), _rng.randf_range(-0.07, 0.07)]
	g.surge = 0.0
	g.surge_in = _rng.randf_range(4.0, 8.0)
	power = 0.25
	streak = 0
	_beat_t = 0.0


func stop_player() -> void:
	if not playing:
		return
	playing = false
	(g.teams[0] as Array).erase("player")
	_avatar.visible = false
	_ui.visible = false
	if hud != null:
		hud.visible = true
	if _site_game():
		g.ambient = true
		_reset_match()
		first_person.global_position = (g.center as Vector3) + _side() * 3.0 + Vector3(0, 0.1, 0)
	else:
		_end_game()
	first_person._resume()


func _make_avatar() -> Villager:
	return GameKit.make_avatar(self, villagers, dialogue, "TugPlayer")


func _make_temp(k: int, center: Vector3) -> Villager:
	var t := GameKit.make_person(self, villagers, "TugTemp%d" % k, "kid" if k % 2 == 1 else "farmer", TEMP_NAMES[k % TEMP_NAMES.size()],
			false, {"role_name": "Người làng bên", "home_name": "Làng bên"})
	var a := _rng.randf() * TAU
	t.global_position = center + Vector3(cos(a), 0, sin(a)) * 8.0
	_temps.append(t)
	return t


func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event.is_action_pressed("exit_interior"):
		stop_player()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fish_reel"):
		player_pull()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and str(g.phase) == "done":
		_reset_match()
		get_viewport().set_input_as_handled()


## Người chơi dồn sức một nhịp: đúng nhịp hò thì thêm lực, lệch thì hụt hơi.
func player_pull() -> void:
	if not playing or str(g.phase) != "pull":
		return
	var off := fmod(_beat_t, beat_period)
	off = minf(off, beat_period - off)
	if off <= beat_window and not _beat_used:
		_beat_used = true
		streak += 1
		power = minf(power + hit_gain, 1.0)
		_say("Hò dô ta! ×%d" % streak)
	else:
		streak = 0
		power = maxf(power - miss_loss, 0.0)
		_say("Lệch nhịp!")


func _say(text: String) -> void:
	_msg = text
	_msg_t = 0.7


# --- Mỗi khung hình --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if g.is_empty():
		return
	var dt := minf(delta, 0.05)
	step(dt)
	if g.is_empty():
		return
	_pose(dt)
	_draw_rope()
	if playing:
		_update_camera(dt)
		_update_ui()


## Một bước mô phỏng (bài thử gọi trực tiếp).
func step(dt: float) -> void:
	if g.is_empty():
		return
	g.t = float(g.t) + dt
	_msg_t = maxf(_msg_t - dt, 0.0)
	var lb := g.label as Label3D
	lb.text = "%d – %d" % [int(g.score[0]), int(g.score[1])]
	lb.visible = str(g.phase) != "gather" and not playing
	match str(g.phase):
		"gather":
			var h := day_night.time_of_day if day_night != null else 16.0
			if _count(0) >= 3 and _count(1) >= 3 and (float(g.t) > 6.0 or _count(0) + _count(1) >= team_size * 2):
				_reset_match()
			elif float(g.t) > gather_wait and _count(0) >= 2 and _count(1) >= 2:
				_reset_match()
			elif float(g.t) > gather_wait * 1.8 or (float(g.t) > 5.0 and not _hours_ok(h)):
				_end_game()
		"ready":
			if float(g.t) > 2.5:
				g.phase = "pull"
				g.t = 0.0
				_beat_t = 0.0
		"pull":
			_step_pull(dt)
		"win":
			if float(g.t) > 3.0:
				if int(g.score[0]) >= rounds_to_win or int(g.score[1]) >= rounds_to_win:
					stats.matches = int(stats.matches) + 1
					if playing:
						g.phase = "done"
						finished.emit(int(g.score[0]) > int(g.score[1]), int(g.score[0]), int(g.score[1]))
					else:
						_end_game()
				else:
					g.round = int(g.round) + 1
					_begin_round()
		"done":
			pass


func _hours_ok(h: float) -> bool:
	if weather != null and weather.kind in ["storm", "drizzle"]:
		return false
	return h >= 6.0 and h < 18.2


func _step_pull(dt: float) -> void:
	var t := float(g.t)
	var prev_beat := int(_beat_t / beat_period)
	_beat_t += dt
	if int(_beat_t / beat_period + 0.5) != int((_beat_t - dt) / beat_period + 0.5):
		_beat_used = false         # qua giữa hai nhịp: nhịp mới lại bấm được
	if int(_beat_t / beat_period) != prev_beat and playing:
		g.cheer = 0.0
	# Cơn rướn của đội kia
	g.surge_in = float(g.surge_in) - dt
	if float(g.surge_in) <= 0.0:
		g.surge = 2.0
		g.surge_in = _rng.randf_range(6.0, 10.0)
	g.surge = maxf(float(g.surge) - dt, 0.0)
	var f0: float
	var f1: float
	if playing:
		power = maxf(power - power_decay * decay_scale * dt, 0.0)
		f0 = my_base + my_gain * power
		f1 = their_base + float(g.bias[1]) + 0.12 * sin(t * 1.3 + float(g.ph[1])) + (0.22 if float(g.surge) > 0.0 else 0.0)
	else:
		f0 = 1.0 + float(g.bias[0]) + 0.2 * sin(t * 1.1 + float(g.ph[0])) + 0.1 * sin(t * 2.7)
		f1 = 1.0 + float(g.bias[1]) + 0.2 * sin(t * 0.9 + float(g.ph[1])) + (0.2 if float(g.surge) > 0.0 else 0.0)
	# Dải đỏ dịch về phía đội khoẻ hơn (đội 0 ở phía âm)
	g.vel = lerpf(float(g.vel), (f1 - f0) * pull_speed, minf(dt * 3.0, 1.0))
	g.x = float(g.x) + float(g.vel) * dt
	g.cheer = float(g.cheer) - dt
	if float(g.cheer) <= 0.0:
		g.cheer = _rng.randf_range(2.5, 5.0) if not playing else 99.0
		var tm: Array = g.teams[_rng.randi_range(0, 1)]
		if not tm.is_empty() and tm[tm.size() - 1] is Villager:
			_bark(tm[tm.size() - 1] as Villager, CHEERS[_rng.randi_range(0, CHEERS.size() - 1)])
	var winner := -1
	if float(g.x) <= -win_dist:
		winner = 0
	elif float(g.x) >= win_dist:
		winner = 1
	elif t >= round_seconds:
		winner = 0 if float(g.x) < 0.0 else 1
	if winner >= 0:
		g.score[winner] = int(g.score[winner]) + 1
		g.phase = "win"
		g.t = 0.0
		g.vel = 0.0
		g["last_winner"] = winner
		stats.rounds = int(stats.rounds) + 1
		for m: Variant in g.teams[winner]:
			if m is Villager:
				_bark(m as Villager, ["Thắng rồi!", "Dô ta! Được rồi!", "Khoẻ chưa!"][_rng.randi_range(0, 2)])
				break


func _side() -> Vector3:
	return (g.axis as Vector3).cross(Vector3.UP).normalized()


## Chỗ đứng của người thứ k trong đội t (dịch theo dải đỏ).
func _slot(t: int, k: int) -> Vector3:
	var s := -1.0 if t == 0 else 1.0
	return (g.center as Vector3) + (g.axis as Vector3) * (float(g.x) + s * (front_gap + spacing * k)) \
			+ _side() * (0.16 if k % 2 == 0 else -0.16) * s


func _pose(dt: float) -> void:
	if g.is_empty():
		return
	var phase := str(g.phase)
	var pulling := phase == "pull"
	var pulse := sin(float(g.t) * TAU / beat_period) if pulling else 0.0
	for t in 2:
		var s := -1.0 if t == 0 else 1.0
		var tm: Array = g.teams[t]
		for k in tm.size():
			var m: Variant = tm[k]
			var v: Villager = _avatar if m is String else (m as Villager)
			if v == null or not is_instance_valid(v):
				continue
			var slot := _slot(t, k)
			var face := slot - (g.axis as Vector3) * s * 5.0
			var won := phase in ["win", "done"] and int(g.get("last_winner", -1)) == t
			_walk_to(v, slot, face, dt)
			if v._walk_amount > 0.3 or v.body == null:
				continue
			if won:
				# Đội thắng giơ tay reo
				if v.arms.size() == 2:
					v.arms[0].rotation.x = -2.8
					v.arms[1].rotation.x = -2.8
				continue
			if phase == "gather":
				continue
			# Ngả người ra sau, hai tay nắm dây phía trước, chân choãi
			var lean := 0.34 + 0.07 * pulse * (1.0 if t == 0 else -1.0) if pulling else 0.12
			v.body.rotation.x = -lean
			for l in v.legs:
				l.rotation.x = lean - 0.55
			if v.knees.size() == 2:
				v.knees[0].rotation.x = 0.5
				v.knees[1].rotation.x = 0.25
			if v.arms.size() == 2:
				v.arms[0].rotation.x = -1.25 + lean
				v.arms[1].rotation.x = -1.25 + lean
				v.arms[0].rotation.z = 0.2
				v.arms[1].rotation.z = -0.2
			for e in v.elbows:
				e.rotation.x = -0.25


## Đi thẳng tới chỗ, tới nơi thì quay mặt về `face` (như JumpRope._walk_to).
func _walk_to(v: Villager, to: Vector3, face: Vector3, dt: float) -> void:
	var p := v.global_position
	p.y = to.y
	var d := Vector3(to.x - p.x, 0, to.z - p.z)
	if d.length() > 0.25:
		var stp := minf(d.length(), 2.4 * dt)
		v.global_position = p + d.normalized() * stp
		v.rotation.y = atan2(d.x, d.z)
		v._walk_amount = move_toward(v._walk_amount, 1.0, dt * 6.0)
	else:
		v.global_position = to            # đang kéo: trượt theo dây
		var f := face - to
		v.rotation.y = lerp_angle(v.rotation.y, atan2(f.x, f.z), minf(dt * 8.0, 1.0))
		v._walk_amount = move_toward(v._walk_amount, 0.0, dt * 6.0)
	GameKit.animate_owned(v, self, _avatar, dt)


## Dây thừng: dải mỏng quay về camera nối hai người cuối, dải vải đỏ ở giữa.
func _draw_rope() -> void:
	var im := (g.rope as MeshInstance3D).mesh as ImmediateMesh
	im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(g.center as Vector3) > 90.0 or str(g.phase) == "gather":
		return
	var ax := g.axis as Vector3
	var mid := (g.center as Vector3) + ax * float(g.x) + Vector3(0, rope_height, 0)
	var n0 := maxi(_count(0), 1)
	var n1 := maxi(_count(1), 1)
	var a := mid - ax * (front_gap + spacing * (n0 - 1) + 0.7)
	var b := mid + ax * (front_gap + spacing * (n1 - 1) + 0.7)
	var o := ax.cross((cam.global_position - mid).normalized()).normalized()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(im, a, b, o * 0.028, Color(0.78, 0.66, 0.42))
	_quad(im, mid - ax * 0.06, mid + ax * 0.06, o * 0.05, Palette.FLAG_RED)
	_quad(im, mid + Vector3(0, -0.34, 0) - ax * 0.05, mid + Vector3(0, -0.34, 0) + ax * 0.05, Vector3(0, 0.34, 0), Palette.FLAG_RED)
	im.surface_end()


func _quad(im: ImmediateMesh, a: Vector3, b: Vector3, o: Vector3, col: Color) -> void:
	for p: Vector3 in [a - o, a + o, b + o, a - o, b + o, b - o]:
		im.surface_set_color(col)
		im.surface_add_vertex(p)


func _bark(v: Villager, text: String) -> void:
	if dialogue != null and is_instance_valid(v):
		dialogue.bark(v, dialogue.fill_for(v, text))


# --- Camera, giao diện -------------------------------------------------------------------------------

func _update_camera(dt: float) -> void:
	var c := (g.center as Vector3) + (g.axis as Vector3) * float(g.x) * 0.5
	var want := c + _side() * 8.5 + Vector3(0, 2.5, 0) - (g.axis as Vector3) * 1.5
	var k := 1.0 - exp(-4.0 * dt)
	_cam.global_position = _cam.global_position.lerp(want, k) if dt < 0.9 else want
	_cam.look_at(c + Vector3(0, 0.9, 0), Vector3.UP)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	var box := GameKit.top_panel(_ui)
	_top = _label(true, 24, Palette.HUD_TEXT)
	_sub = _label(false, 16, Palette.HUD_SUBTEXT)
	box.add_child(_top)
	box.add_child(_sub)
	# Thước dây: chấm đỏ = dải vải, hai mép = vạch thắng (trái: đội bạn)
	var bar := _bar(box, Color(0, 0, 0, 0.4))
	_pos_mark = ColorRect.new()
	_pos_mark.color = Palette.FLAG_RED
	_pos_mark.size = Vector2(10, 14)
	bar.add_child(_pos_mark)
	# Thước nhịp: chấm chạy, vùng vàng = lúc hò
	var beat := _bar(box, Color(0, 0, 0, 0.4))
	var zone := ColorRect.new()
	zone.color = Color(Palette.FLOWER_YELLOW, 0.6)
	zone.position = Vector2(320.0 * (0.5 - beat_window / beat_period), 0)
	zone.size = Vector2(320.0 * 2.0 * beat_window / beat_period, 14)
	beat.add_child(zone)
	_beat_dot = ColorRect.new()
	_beat_dot.color = Color.WHITE
	_beat_dot.size = Vector2(6, 14)
	beat.add_child(_beat_dot)
	var pw := _bar(box, Color(0, 0, 0, 0.4))
	_power_bar = ColorRect.new()
	_power_bar.color = Palette.FLOWER_YELLOW
	_power_bar.size = Vector2(0, 14)
	pw.add_child(_power_bar)
	box.add_child(_label(false, 15, Palette.HUD_SUBTEXT,
			"Space / chuột trái: dồn sức ĐÚNG NHỊP (chấm trắng vào vùng vàng)  ·  thanh vàng: sức đội bạn  ·  Esc: thôi chơi"))
	_big = GameKit.big_label(_ui, 64, -300, 12)


func _bar(box: VBoxContainer, col: Color) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(320, 14)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)
	return bar


func _label(bold: bool, size: int, col: Color, text: String = "") -> Label:
	return GameKit.label(bold, size, col, text)


func _update_ui() -> void:
	var phase := str(g.phase)
	_top.text = "Kéo co  ·  Hiệp %d  ·  Đội bạn %d – %d Đội bên kia" % [int(g.round), int(g.score[0]), int(g.score[1])]
	_sub.text = "Dải đỏ lệch %.1f m về phía %s  ·  còn %d giây" % [absf(float(g.x)), "đội bạn" if float(g.x) < 0.0 else "đội bên kia",
			maxi(0, int(round_seconds - float(g.t)))] if phase == "pull" else "Kéo dải đỏ qua vạch bên mình là thắng hiệp · thắng 2 hiệp là thắng"
	_pos_mark.position.x = clampf(160.0 + float(g.x) / win_dist * 160.0, 0.0, 310.0) - 5.0
	var frac := fmod(_beat_t + beat_period * 0.5, beat_period) / beat_period
	_beat_dot.position.x = 320.0 * frac - 3.0
	_power_bar.size.x = 320.0 * power
	match phase:
		"ready": _big.text = "Sẵn sàng… %d" % maxi(1, 3 - int(float(g.t)))
		"pull": _big.text = _msg if _msg_t > 0.0 else ""
		"win": _big.text = "Đội bạn thắng hiệp!" if int(g.get("last_winner", -1)) == 0 else "Thua hiệp này!"
		"done": _big.text = ("THẮNG RỒI! %d – %d" if int(g.score[0]) > int(g.score[1]) else "Thua mất rồi… %d – %d") % [int(g.score[0]), int(g.score[1])] + "\nE: kéo lại  ·  Esc: thôi"
		_: _big.text = ""
