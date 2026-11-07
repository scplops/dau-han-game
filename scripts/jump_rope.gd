class_name JumpRope
extends Node3D
## Trò chơi dân gian Nhảy dây (mục 31). Dây dài: hai đứa đứng hai đầu quay dây, những đứa khác xếp hàng
## lần lượt vào giữa nhảy; ai vướng dây thì ra thay một người quay (người quay lâu nhất vào hàng).
## - Trẻ con tự chơi: việc `jumprope` của Villagers (ban ngày, trời không mưa) ở các bãi `sites` (sân đình,
##   gốc đa đầu làng). Tới nơi thì `on_arrive` cho vào cuộc chơi ở bãi gần nhất (meta `jumprope` + `talking`
##   — Villagers chỉ diễn hoạt, không dắt đi). Đủ 3 đứa mới nhảy; 2 đứa thì quay dây chậm chờ bạn. Chơi
##   `game_seconds` giây thật, hoặc tới khi tối / mưa thì tản đi (dwell 0 → Villagers chọn việc khác).
## - Người chơi: nhập vai nhìn một đứa đang chơi "E: Xin nhảy dây" (`join_at`), hoặc rủ qua hội thoại
##   "Chơi nhảy dây không em?" (`start_with` — bày cuộc chơi ngay chỗ đứng, gọi thêm trẻ quanh đây, thiếu
##   người quay thì trẻ nhà bên chạy sang). Người chơi là người nhảy (hình nhân `_avatar`), camera nhìn ngang.
##   Space / chuột trái (`fish_reel`) để nhảy: phải đang lơ lửng khi dây quét qua chân (`clearance`). Dây
##   quay nhanh dần (`start_rev` → `max_rev` vòng/giây, mỗi `speed_every` lần nhảy). Vướng dây → tới lượt
##   bọn trẻ trong hàng, rồi lại tới bạn. Bảng kỷ lục từng người. Esc: thôi chơi.
## - Dây: cung tròn giữa hai bàn tay người quay, bán kính `hand_height` (đáy dây sát đất, đỉnh trên đầu),
##   pha `phi` (0 = đáy dây chạm đất giữa hai người), vẽ bằng ImmediateMesh mỗi khung.

signal turn_over(who: String, count: int)

@export var villagers: Villagers
@export var first_person: FirstPerson
@export var dialogue: Dialogue
@export var hud: Hud
@export var day_night: DayNight
@export var weather: Weather
@export var village: Village
@export_group("Dây")
## Khoảng cách giữa hai người quay dây (m).
@export var rope_gap: float = 4.0
@export var hand_height: float = 1.02
@export var start_rev: float = 0.85
@export var max_rev: float = 2.3
@export var speed_every: int = 4
@export var speed_step: float = 0.08
@export_group("Nhảy")
## Thời gian lơ lửng một cú nhảy (s) và độ cao (m).
@export var jump_air: float = 0.32
@export var jump_height: float = 0.2
## Chân phải cao hơn chừng này khi dây quét qua (m) …
@export var clearance: float = 0.1
## … cộng thêm chừng này cho mỗi vòng/giây dây quay nhanh hơn lúc đầu (dây càng nhanh càng phải nhảy chuẩn).
@export var clearance_per_rev: float = 0.035
@export_group("Trẻ con tự chơi")
## Chơi bao lâu (giây thật; 1 ngày = 15 phút nên 60 s ≈ 1,6 giờ trong game).
@export var game_seconds: Vector2 = Vector2(40.0, 80.0)
## Trẻ con nhảy được bao nhiêu lần thì vướng (ngẫu nhiên trong khoảng).
@export var kid_skill: Vector2i = Vector2i(3, 28)
@export var random_seed: int = 3131

const TEMP_NAMES: Array[String] = ["Cu Bin", "Bé Na", "Cu Tũn", "Bé Mít", "Cu Sóc", "Bé Bông"]
const CHANTS: Array[String] = ["Nhảy đi! Nhảy đi!", "Nhanh lên này!", "Giỏi thế!", "Quay nhanh nữa nào!", "Cố lên!"]

## Bãi chơi tự động (toạ độ thế giới), dựng trong `_ready` từ Village.
var sites: Array[Vector3] = []
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
var _beat_dot: ColorRect
var _hint_t: float = 0.0


func _ready() -> void:
	_rng.seed = random_seed
	_cam = Camera3D.new()
	_cam.name = "RopeCam"
	_cam.top_level = true
	_cam.fov = 55.0
	add_child(_cam)
	_build_ui()
	if village != null:
		sites.append(village.dinh_spot + Vector3(-9.0, 0.0, 1.5))     # sân đình (lát gạch, rộng)
		# Bãi đất đầu làng, ngoài cổng phía nam, lệch khỏi đường trục (dưới gốc đa thì tán lá che hết)
		sites.append(Vector3(village.center.x + 5.0, 0.0, village.center.y + village.radii.y + 9.0))


# --- Trẻ con tự chơi -----------------------------------------------------------------------------

## Có nên rủ nhau nhảy dây giờ này không (Villagers hỏi khi chọn việc).
func ambient_ok(h: float) -> bool:
	if sites.is_empty() or h < 7.0 or h >= 17.5 or (h >= 11.0 and h < 13.0):
		return false
	return weather == null or not weather.kind in ["storm", "drizzle"]


## Chỗ đứng chờ ở bãi gần nhất (Villagers dùng làm đích của việc `jumprope`).
func site_target(v: Villager) -> Vector3:
	var best := sites[0]
	for s in sites:
		if s.distance_to(v.global_position) < best.distance_to(v.global_position):
			best = s
	return best + Vector3(_rng.randf_range(-1.5, 1.5), 0.05, 2.2 + _rng.randf_range(0.0, 0.8))


## Villagers gọi khi một đứa tới bãi.
func on_arrive(v: Villager) -> void:
	var site := sites[0]
	for s in sites:
		if s.distance_to(v.global_position) < site.distance_to(v.global_position):
			site = s
	var g := _game_at(site)
	if g.is_empty():
		g = _new_game(site, Vector3.RIGHT, true)
	_add_member(g, v)


## Đang ở trong một cuộc nhảy dây (đừng mở khung thoại).
func is_member(v: Villager) -> bool:
	return v != null and v.has_meta("jumprope")


func _game_at(site: Vector3) -> Dictionary:
	for g in games:
		if (g.center as Vector3).distance_to(site) < 3.0:
			return g
	return {}


func _new_game(center: Vector3, axis: Vector3, ambient: bool) -> Dictionary:
	var g := {"center": center, "axis": axis.normalized(), "turners": [], "queue": [], "jumper": null,
			"phi": 0.0, "rev": start_rev * 0.6, "count": 0, "best": {}, "ambient": ambient, "air": -1.0,
			"plan": 0, "wait": 1.5, "t_left": _rng.randf_range(game_seconds.x, game_seconds.y),
			"turn_since": [0.0, 0.0], "label": null, "mesh": null, "pass_count": 0}
	var mi := MeshInstance3D.new()
	mi.name = "Rope"
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var im := ImmediateMesh.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#d8b35a")
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)
	g.mesh = mi
	var lb := Label3D.new()
	lb.font = Hud.font(true)
	lb.font_size = 72
	lb.pixel_size = 0.006
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Palette.FLOWER_YELLOW
	lb.outline_size = 10
	lb.outline_modulate = Palette.WINDOW_DARK
	lb.top_level = true
	add_child(lb)
	lb.global_position = center + Vector3(0, 2.6, 0)
	lb.visible = false
	g.label = lb
	games.append(g)
	return g


func _add_member(g: Dictionary, v: Villager) -> void:
	v.set_meta("jumprope", true)
	v.set_meta("talking", true)
	v.state = Villager.State.IDLE
	v.visible = true
	v.dwell = 1.0e6
	v.work_anim = "idle"
	if v.prop_node != null:
		v.prop_node.visible = false
	v.activity_text = "đang chơi nhảy dây"
	if (g.turners as Array).size() < 2:
		(g.turners as Array).append(v)
	else:
		(g.queue as Array).append(v)


## Tan cuộc: trả các con về Villagers, xoá trẻ tạm, dây.
func _end_game(g: Dictionary) -> void:
	var all: Array = (g.turners as Array) + (g.queue as Array)
	if g.jumper is Villager:
		all.append(g.jumper)
	for v: Villager in all:
		if not is_instance_valid(v):
			continue
		v.remove_meta("jumprope")
		v.remove_meta("talking")
		if v.prop_node != null:
			v.prop_node.visible = true
		v.global_position.y = (g.center as Vector3).y
		v.work_anim = "idle"
		if _temps.has(v):
			_temps.erase(v)
			v.queue_free()
		else:
			v.dwell = 0.0
	(g.mesh as Node).queue_free()
	(g.label as Node).queue_free()
	games.erase(g)


# --- Người chơi -------------------------------------------------------------------------------

## Lời từ chối khi rủ (rỗng = đồng ý).
func refusal(v: Villager, at: Vector3 = Vector3.INF) -> String:
	if not v.role in ["kid", "herder"]:
		return "Người lớn ai nhảy dây! Rủ bọn trẻ con ấy."
	if v.has_meta("in_class"):
		return "Đang giờ học mà {you}!"
	var h := day_night.time_of_day if day_night != null else 15.0
	if h >= 19.0 or h < 6.0:
		return "Tối rồi, không thấy dây đâu. Mai chơi nhé!"
	if weather != null and weather.kind in ["storm", "drizzle"]:
		return "Mưa trơn lắm, ngã chết!"
	if v.state == Villager.State.WALK and v.activity in ["school", "graze"]:
		return "{Self} đang phải đi, lúc khác chơi nhé!"
	if at != Vector3.INF and not open_ground(at):
		return "Chỗ này chật quá, quay dây vướng hết. Ra chỗ rộng mà chơi {you}!"
	return ""


## Đủ rộng để quay dây: ngang tầm 0,5–1,8 m quanh chỗ đứng không vướng gì trong `rope_gap`/2 + 0,8 m.
func open_ground(at: Vector3) -> bool:
	if first_person == null:
		return true
	var space := first_person.get_world_3d().direct_space_state
	var mask := 1 << (FirstPerson.SOLID_LAYER - 1)
	var r := rope_gap * 0.5 + 0.8
	for k in 8:
		var d := Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0))
		for hgt: float in [0.5, 1.8]:
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, hgt, 0), at + Vector3(0, hgt, 0) + d * r, mask)
			if not space.intersect_ray(q).is_empty():
				return false
	return true


## Nhìn một đứa đang nhảy dây + E: xin vào nhảy ở cuộc chơi đó.
func join_at(v: Villager) -> void:
	for g in games:
		var members: Array = (g.turners as Array) + (g.queue as Array)
		if members.has(v) or g.jumper == v:
			_start_player(g)
			_bark(v, "Vào đây! %s nhảy sau đứa này nhé!" % "{You}")
			return


## Rủ qua hội thoại: bày cuộc chơi ở chỗ người chơi đứng.
func start_with(v: Villager) -> void:
	if not player_game.is_empty() or first_person == null:
		return
	var fp := first_person.global_position
	var fwd := -first_person.global_transform.basis.z
	fwd.y = 0.0
	var axis := fwd.normalized().cross(Vector3.UP)    # dây quay ngang trước mặt
	var center := fp + fwd.normalized() * 2.5
	center.y = fp.y
	var g := _new_game(center, axis, false)
	if is_member(v):
		for og in games:
			if og != g and ((og.turners as Array).has(v) or (og.queue as Array).has(v)):
				_end_game(og)
				break
	_add_member(g, v)
	# Gọi thêm trẻ con rảnh quanh đây; thiếu người quay thì trẻ nhà bên chạy sang
	if villagers != null:
		var near: Array[Villager] = []
		for p in villagers.people:
			if p != v and p.visible and p.role in ["kid", "herder"] and p.global_position.distance_to(center) < 30.0 \
					and refusal(p) == "" and not p.has_meta("talking") and not p.has_meta("at_school") and not p.has_meta("jumprope"):
				near.append(p)
		near.sort_custom(func(a: Villager, b: Villager) -> bool: return a.global_position.distance_to(center) < b.global_position.distance_to(center))
		for p in near.slice(0, 3):
			_add_member(g, p)
	var k := 0
	while (g.turners as Array).size() < 2:
		_add_member(g, _make_temp(k, center))
		k += 1
	_start_player(g)


func _start_player(g: Dictionary) -> void:
	if not player_game.is_empty():
		return
	player_game = g
	g.ambient = false
	g.t_left = 1.0e9
	(g.queue as Array).push_front("player")
	if not (g.jumper is Villager):
		g.wait = 1.2
	first_person._suspend("rope")
	if _avatar == null:
		_avatar = _make_avatar()
	_avatar.visible = true
	_avatar.global_position = _queue_slot(g, 0)
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
	(g.queue as Array).erase("player")
	if g.jumper is String:
		g.jumper = null
		g.wait = 1.0
	_avatar.visible = false
	_ui.visible = false
	if hud != null:
		hud.visible = true
	# Cuộc chơi người chơi bày ra thì tan luôn; cuộc chơi sẵn có thì bọn trẻ chơi tiếp
	if not _site_game(g):
		_end_game(g)
	else:
		g.ambient = true
		g.t_left = _rng.randf_range(20.0, 40.0)
	first_person.global_position = _queue_slot(g, 0) + Vector3(0, 0.1, 0) if _site_game(g) else first_person.global_position
	first_person._resume()


func _site_game(g: Dictionary) -> bool:
	for s in sites:
		if (g.center as Vector3).distance_to(s) < 3.0:
			return true
	return false


func _make_avatar() -> Villager:
	var female: bool = dialogue != null and dialogue.player_female
	var a := Villager.new()
	a.name = "RopePlayer"
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
	return a


func _make_temp(k: int, center: Vector3) -> Villager:
	var female := _rng.randf() < 0.5
	var t := Villager.new()
	t.name = "RopeKid%d" % k
	t.role = "kid"
	t.role_name = "Trẻ con nhà bên"
	t.display_name = TEMP_NAMES[(k + _rng.randi_range(0, 5)) % TEMP_NAMES.size()]
	t.home = {"name": "Nhà bên", "key": ""}
	t.set_meta("female", female)
	add_child(t)
	var look: Dictionary = villagers._look("kid", female) if villagers != null else {}
	t.build_person(look)
	var a := _rng.randf() * TAU
	t.global_position = center + Vector3(cos(a), 0, sin(a)) * 7.0
	_temps.append(t)
	return t


func _unhandled_input(event: InputEvent) -> void:
	if player_game.is_empty():
		return
	if event.is_action_pressed("exit_interior"):
		stop_player()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fish_reel"):
		player_jump()
		get_viewport().set_input_as_handled()


## Người chơi nhảy (chỉ khi đang ở lượt mình và chân chạm đất).
func player_jump() -> void:
	var g := player_game
	if g.is_empty() or not (g.jumper is String) or float(g.air) >= 0.0 or float(g.wait) > 0.0:
		return
	g.air = 0.0


# --- Mỗi khung hình --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	for g in games.duplicate():
		step(g, dt)
	_hint_t = maxf(_hint_t - dt, 0.0)
	if not player_game.is_empty():
		_update_camera(player_game, dt)
		_update_ui(player_game)


## Một bước của một cuộc chơi (tách riêng cho bài thử).
func step(g: Dictionary, dt: float) -> void:
	var h := day_night.time_of_day if day_night != null else 15.0
	# Tan cuộc tự chơi: hết giờ chơi, tối, mưa; người chơi đang nhảy thì chỉ tan khi giông
	if g.ambient:
		g.t_left = float(g.t_left) - dt
		var bad := weather != null and weather.kind in ["storm", "drizzle"]
		var school := villagers != null and villagers.school_day != null and villagers.school_day.wants_pupils(h)
		if float(g.t_left) <= 0.0 or h >= 18.0 or bad or school:
			_end_game(g)
			return
	elif weather != null and weather.kind == "storm":
		stop_player()
		if games.has(g):
			_end_game(g)
		return
	var turners: Array = g.turners
	var queue: Array = g.queue
	if turners.size() < 2 and queue.size() > 0 and queue[0] is Villager:
		turners.append(queue.pop_front())
	if turners.size() < 2:
		# Chưa đủ hai người quay: đứng chờ bạn tới (dây chưa căng)
		if turners.is_empty():
			if g.ambient:
				_end_game(g)
			return
		_walk_to(turners[0] as Villager, (g.center as Vector3) - (g.axis as Vector3) * rope_gap * 0.5, g.center as Vector3, dt)
		(g.mesh.mesh as ImmediateMesh).clear_surfaces()
		return
	var playing: bool = g.jumper != null
	# Dây quay: chậm khi chờ người, nhanh dần theo số lần nhảy
	var target_rev := start_rev + speed_step * floorf(float(g.count) / speed_every) if playing else start_rev * 0.6
	g.rev = move_toward(float(g.rev), minf(target_rev, max_rev), dt * 0.5)
	var prev := float(g.phi)
	g.phi = prev + TAU * float(g.rev) * dt
	# Người nhảy tiếp theo vào giữa
	if not playing:
		g.wait = float(g.wait) - dt
		if float(g.wait) <= 0.0 and queue.size() > 0:
			var nxt: Variant = queue.pop_front()
			g.jumper = nxt
			g.count = 0
			g.air = -1.0
			g.wait = 0.9          # đứng vào giữa, đợi một vòng dây rồi mới bắt đầu đếm
			g.plan = _rng.randi_range(kid_skill.x, kid_skill.y)
			if nxt is Villager:
				_bark(nxt as Villager, ["Đến lượt {self}!", "Xem {self} nhảy này!", "Quay đi!"][_rng.randi_range(0, 2)])
	else:
		_step_jumper(g, prev, dt)
	_pose_members(g, dt)
	_draw_rope(g)


func _step_jumper(g: Dictionary, prev_phi: float, dt: float) -> void:
	var is_player: bool = g.jumper is String
	if float(g.wait) > 0.0:
		g.wait = float(g.wait) - dt
		if float(g.wait) <= 0.0:
			# bắt đầu tính từ lần dây chạm đất tới
			g.phi = fmod(float(g.phi), TAU)
		return
	# Máy nhảy đúng lúc (trước khi dây chạm đất nửa thời gian lơ lửng), tới "số phận" thì nhảy hụt
	if not is_player and float(g.air) < 0.0:
		var to_bottom := TAU - fmod(float(g.phi), TAU)
		var t_bottom := to_bottom / (TAU * float(g.rev))
		var lead := jump_air * 0.5
		if int(g.count) >= int(g.plan):
			lead = jump_air * (1.15 if _rng.randf() < 0.5 else -0.2)   # nhảy sớm quá / muộn quá
		if t_bottom <= lead and t_bottom > lead - dt * 1.5:
			g.air = 0.0
	if float(g.air) >= 0.0:
		g.air = float(g.air) + dt
		if float(g.air) >= jump_air:
			g.air = -1.0
	# Dây quét qua chân (pha qua bội số của 2π)
	if floorf(float(g.phi) / TAU) > floorf(prev_phi / TAU):
		if _jump_height(g) < need_clearance(g):
			_trip(g)
		else:
			g.count = int(g.count) + 1
			if g.label != null:
				(g.label as Label3D).text = str(g.count)
				(g.label as Label3D).visible = player_game != g   # người chơi đang chơi: số to trên màn hình rồi
			if int(g.count) % 10 == 0 and not (g.turners as Array).is_empty():
				_bark((g.turners as Array)[_rng.randi_range(0, 1)], CHANTS[_rng.randi_range(0, CHANTS.size() - 1)])


func need_clearance(g: Dictionary) -> float:
	return clearance + clearance_per_rev * maxf(float(g.rev) - start_rev, 0.0)


func _jump_height(g: Dictionary) -> float:
	var a := float(g.air)
	if a < 0.0:
		return 0.0
	var u := a / jump_air
	return 4.0 * jump_height * u * (1.0 - u)


## Vướng dây: ghi kỷ lục; trẻ con vướng thì ra thay người quay lâu nhất, người đó vào hàng.
func _trip(g: Dictionary) -> void:
	var who: Variant = g.jumper
	var name_: String = "Bạn" if who is String else (who as Villager).display_name
	var best: Dictionary = g.best
	best[name_] = maxi(int(best.get(name_, 0)), int(g.count))
	turn_over.emit(name_, int(g.count))
	if g.label != null:
		(g.label as Label3D).text = "Vướng! %d" % int(g.count)
	g.jumper = null
	g.air = -1.0
	g.wait = 1.6
	g.rev = start_rev * 0.6
	var turners: Array = g.turners
	if who is Villager:
		_bark(who as Villager, ["Ối, vướng rồi!", "Thôi chết, tuột chân!", "Được %d cái thôi…" % int(g.count)][_rng.randi_range(0, 2)])
		var out: Villager = turners[0]
		turners[0] = turners[1]
		turners[1] = who
		(g.queue as Array).append(out)
	else:
		_bark(turners[0], ["Anh vướng rồi! Được %d cái." % int(g.count), "Hụt rồi! %d cái nhé!" % int(g.count)][_rng.randi_range(0, 1)])
		(g.queue as Array).append("player")   # khách được nhảy tiếp, không phải quay dây


# --- Vị trí, dáng, dây -------------------------------------------------------------------------------

func _side(g: Dictionary) -> Vector3:
	return (g.axis as Vector3).cross(Vector3.UP).normalized()


func _queue_slot(g: Dictionary, k: int) -> Vector3:
	return (g.center as Vector3) + _side(g) * (2.2 + 0.1 * k) + (g.axis as Vector3) * (-1.2 + 0.8 * k)


func _hands(g: Dictionary) -> Array[Vector3]:
	var c := g.center as Vector3
	var ax := g.axis as Vector3
	var a := c - ax * rope_gap * 0.5 + Vector3(0, hand_height, 0)
	var b := c + ax * rope_gap * 0.5 + Vector3(0, hand_height, 0)
	return [a + ax * 0.32, b - ax * 0.32]


func _pose_members(g: Dictionary, dt: float) -> void:
	var c := g.center as Vector3
	var ax := g.axis as Vector3
	var turners: Array = g.turners
	for i in turners.size():
		var v: Villager = turners[i]
		var s := -1.0 if i == 0 else 1.0
		_walk_to(v, c + ax * s * (rope_gap * 0.5 + 0.1), c, dt)
		# Tay phải đưa ra trước, quay vòng theo dây
		if v.arms.size() == 2 and v._walk_amount < 0.3:
			var ph := float(g.phi)
			v.arms[1].rotation.x = -1.0 + 0.45 * cos(ph)
			v.arms[1].rotation.z = 0.4 * sin(ph) * s
			v.arms[0].rotation.x = -0.4
			for e in v.elbows:
				e.rotation.x = -0.3
	var k := 0
	for q: Variant in g.queue:
		var slot := _queue_slot(g, k)
		if q is Villager:
			_walk_to(q as Villager, slot, c, dt)
			(q as Villager).work_anim = "chat" if k > 0 else "idle"
		elif q is String and _avatar != null:
			_walk_to(_avatar, slot, c, dt)
		k += 1
	var j: Variant = g.jumper
	var jv: Villager = _avatar if j is String else (j as Villager if j is Villager else null)
	if jv != null:
		_walk_to(jv, c, c + _side(g) * 5.0, dt)
		var hgt := _jump_height(g)
		jv.global_position.y = c.y + hgt
		if jv.knees.size() == 2:
			var tuck := clampf(hgt / 0.12, 0.0, 1.0)
			for kn in jv.knees:
				kn.rotation.x = 0.9 * tuck
			for lg in jv.legs:
				lg.rotation.x = -0.5 * tuck
		if jv.arms.size() == 2:
			jv.arms[0].rotation.z = 0.5
			jv.arms[1].rotation.z = -0.5


## Đi thẳng tới chỗ (trẻ con trong cuộc chơi Villagers không dắt nữa), tới nơi thì quay mặt về `face`.
func _walk_to(v: Villager, to: Vector3, face: Vector3, dt: float) -> void:
	var p := v.global_position
	p.y = to.y          # đứng đúng mặt bãi (người vừa nhảy xong rơi về đất)
	var d := Vector3(to.x - p.x, 0, to.z - p.z)
	if d.length() > 0.08:
		var stp := minf(d.length(), 2.2 * dt)
		v.global_position = p + d.normalized() * stp
		v.rotation.y = atan2(d.x, d.z)
		v._walk_amount = move_toward(v._walk_amount, 1.0, dt * 6.0)
	else:
		var f := face - p
		v.rotation.y = lerp_angle(v.rotation.y, atan2(f.x, f.z), minf(dt * 6.0, 1.0))
		v._walk_amount = move_toward(v._walk_amount, 0.0, dt * 6.0)
	if v.get_parent() == self and v != _avatar:
		v.state = Villager.State.IDLE
		v.tick(dt, true)       # trẻ tạm không thuộc Villagers: tự diễn hoạt
	elif v == _avatar:
		v._animate(dt)


## Dây: cung tròn quay quanh đường nối hai bàn tay, đáy chạm đất ở pha 0.
func _draw_rope(g: Dictionary) -> void:
	var mi := g.mesh as MeshInstance3D
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(g.center as Vector3) > 70.0:
		return
	var hs := _hands(g)
	var up := Vector3.UP
	var side := _side(g)
	var ph := float(g.phi)
	var rad := hand_height - 0.03
	var n := 20
	var pts: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / n
		var r := rad * sin(PI * t)
		pts.append(hs[0].lerp(hs[1], t) + (-cos(ph) * up + sin(ph) * side) * r)
	var w := 0.022
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		var o1 := dir.cross((cam.global_position - a).normalized()).normalized() * w
		for v in [a - o1, a + o1, b + o1, a - o1, b + o1, b - o1]:
			im.surface_add_vertex(v)
	im.surface_end()


func _bark(v: Villager, text: String) -> void:
	if dialogue != null and is_instance_valid(v):
		dialogue.bark(v, dialogue.fill_for(v, text))


# --- Camera, giao diện -------------------------------------------------------------------------------

func _update_camera(g: Dictionary, dt: float) -> void:
	var c := g.center as Vector3
	var want := c + _side(g) * 5.2 + Vector3(0, 1.45, 0)
	var t := 1.0 - exp(-4.0 * dt)
	_cam.global_position = _cam.global_position.lerp(want, t) if dt < 0.9 else want
	_cam.look_at(c + Vector3(0, 0.75, 0), Vector3.UP)


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
	# Thước nhịp: chấm chạy theo pha dây, vạch vàng = lúc dây chạm đất
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.4)
	bar.custom_minimum_size = Vector2(320, 14)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)
	var zone := ColorRect.new()
	zone.color = Color(Palette.FLOWER_YELLOW, 0.6)
	zone.position = Vector2(320 - 6, 0)
	zone.size = Vector2(6, 14)
	bar.add_child(zone)
	_beat_dot = ColorRect.new()
	_beat_dot.color = Palette.FLAG_RED
	_beat_dot.size = Vector2(8, 14)
	bar.add_child(_beat_dot)
	var hint := _label(false, 15, Palette.HUD_SUBTEXT, "Space / chuột trái: nhảy — nhảy khi dây sắp quét xuống đất (chấm đỏ gần vạch vàng)  ·  Esc: thôi chơi")
	box.add_child(hint)
	_big = _label(true, 110, Palette.HUD_TEXT)
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_big.grow_vertical = Control.GROW_DIRECTION_BOTH
	_big.offset_top = -340
	_big.add_theme_constant_override("outline_size", 14)
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


func _update_ui(g: Dictionary) -> void:
	var j: Variant = g.jumper
	var who := "Bạn" if j is String else ((j as Villager).display_name if j is Villager else "…")
	var turn := "Lượt: %s" % who if j != null else "Chuẩn bị lượt mới"
	var rev := float(g.rev)
	_top.text = "Nhảy dây  ·  %s  ·  %d lần  ·  dây %.1f vòng/giây" % [turn, int(g.count), rev]
	var best: Dictionary = g.best
	var names := best.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return int(best[a]) > int(best[b]))
	var rows: Array[String] = []
	for n: String in names.slice(0, 5):
		rows.append("%s %d" % [n, int(best[n])])
	var q: Array[String] = []
	for x: Variant in g.queue:
		q.append("Bạn" if x is String else (x as Villager).display_name)
	_sub.text = "Kỷ lục: %s\nHàng chờ: %s" % [", ".join(rows) if not rows.is_empty() else "chưa có", " → ".join(q) if not q.is_empty() else "—"]
	var frac := fmod(float(g.phi), TAU) / TAU
	_beat_dot.position.x = 320.0 * frac - 4.0
	_big.text = str(int(g.count)) if j is String and float(g.wait) <= 0.0 else ("Sẵn sàng…" if j is String else "")
