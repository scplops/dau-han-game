class_name HideSeek
extends Node3D
## Trò chơi dân gian Trốn tìm (mục 28) — người chơi đi tìm, bọn trẻ đi trốn.
## - Rủ một đứa trẻ qua hội thoại (nhập vai). Nó gọi thêm trẻ con quanh đó (tới `hider_count`), thiếu thì
##   "trẻ nhà bên" chạy sang (Villager tạm, chơi xong thì về). Chỗ người chơi đứng là "cột" (vòng phấn).
## - Bịt mắt đếm `count_seconds` giây (màn hình tối, đếm "Một… Mười"): bọn trẻ chạy đi trốn ở những chỗ
##   khuất (`_find_spots`: mặt đất ngang cột, không kẹt trong vật, tia nhìn từ cột bị chắn, sát một vật
##   che). Hết đếm ai chưa tới chỗ thì đặt luôn vào chỗ (người chơi đang nhắm mắt). Trốn: ngồi thụp
##   (`squat`), meta `hiding`.
## - Đi tìm (`seek_seconds`): nhìn thấy (trong `spot_distance`, gần giữa tầm nhìn, không bị che) là bắt
##   được; hoặc nhìn vào và nhấn E. Thỉnh thoảng có tiếng cười khúc khích chỉ hướng. Người chơi đi xa cột
##   thì đứa chưa bị bắt có thể lén chạy về "đập cột" (thoát) — bắt được giữa đường vẫn tính.
## - Hết giờ / tìm hết / ai cũng về cột: hiện kết quả, bọn trẻ trở lại việc của mình. Esc: thôi chơi.

signal finished(found: int, escaped: int, total: int)

@export var first_person: FirstPerson
@export var villagers: Villagers
@export var dialogue: Dialogue
@export var hud: Hud
@export var day_night: DayNight
@export var weather: Weather
## Bọn trẻ tự chơi trốn tìm trong ngõ khi không có người chơi (mục 36).
@export var village: Village
@export_group("Bọn trẻ tự chơi")
## Chơi bao lâu thì tan (giây thật).
@export var ambient_seconds: Vector2 = Vector2(200.0, 360.0)
## Chỗ trốn cách cột trong khoảng này (m).
@export var ambient_spot_range: Vector2 = Vector2(8.0, 32.0)
## Mỗi giây, đứa đang trốn có khả năng lén về đập cột khi người đi tìm ở xa cột.
@export var ambient_escape_rate: float = 0.03
@export_group("")
@export_range(1, 8) var hider_count: int = 4
@export var count_seconds: float = 10.0
@export var seek_seconds: float = 150.0
## Chỗ trốn cách cột trong khoảng này (m).
@export var spot_range: Vector2 = Vector2(9.0, 28.0)
## Nhìn thấy trong tầm này thì bắt được.
@export var spot_distance: float = 7.0
## Người chơi đi xa cột hơn chừng này thì bọn trẻ có thể lén về đập cột.
@export var escape_distance: float = 16.0
@export var hint_interval: float = 35.0
@export var random_seed: int = 1990

enum Phase { OFF, COUNT, SEEK, RESULT }

var phase: Phase = Phase.OFF
var base: Vector3
var hiders: Array[Villager] = []
var found: Array[Villager] = []
var escaped: Array[Villager] = []

var _rng := RandomNumberGenerator.new()
var _temps: Array[Villager] = []
var _t: float = 0.0
var _hint_t: float = 0.0
var _escape_t: float = 0.0
var _result_t: float = 0.0
var _marker: MeshInstance3D
var _ui: CanvasLayer
var _blind: ColorRect
var _count_label: Label
var _panel: PanelContainer
var _status: Label
var _sub: Label
var _hint_text: String = ""
var _hint_timer: float = 0.0
## Các ván bọn trẻ tự chơi: {base, members, seeker, hiders, spots {Villager: Vector3}, phase (gather / count /
## seek / back), t, t_left, visits (chỗ người đi tìm sẽ tới), found, escaped, next_seeker}.
var ambient: Array[Dictionary] = []
## Chỗ làm cột (giữa đường trục, chỗ ngõ rẽ) và chỗ trốn quanh làng (cạnh cổng các nhà, gốc đa, giếng).
var ambient_bases: Array[Vector3] = []
var _amb_spots: Array[Vector3] = []

const TEMP_NAMES := ["Cái Hến", "Thằng Cún", "Cu Bi", "Cái Mận", "Thằng Tũn", "Cái Bống", "Cu Tủn"]
const COUNT_WORDS := ["Một", "Hai", "Ba", "Bốn", "Năm", "Sáu", "Bảy", "Tám", "Chín", "Mười"]


func _ready() -> void:
	_rng.randomize()   # mỗi ván trốn một kiểu (cảnh vẫn sinh theo seed cố định)
	_build_ui()
	_build_marker()


# --- Bắt đầu --------------------------------------------------------------------------------

## Lời từ chối của `v` (rỗng = chịu chơi).
func refusal(v: Villager) -> String:
	if not v.role in ["kid", "herder"]:
		return "Người lớn ai chơi trốn tìm! Rủ bọn trẻ con ấy."
	if v.has_meta("in_class"):
		return "Đang giờ học mà {you}!"
	var h := day_night.time_of_day if day_night != null else 15.0
	if h >= 19.0 or h < 6.0:
		return "Tối rồi, mẹ {self} gọi về ăn cơm. Mai chơi nhé!"
	if weather != null and weather.kind == "storm":
		return "Mưa to thế này chơi gì, ướt hết!"
	if v.state == Villager.State.WALK and v.activity in ["school", "graze"]:
		return "{Self} đang phải đi, lúc khác chơi nhé!"
	return ""


func start(v: Villager) -> void:
	if phase != Phase.OFF or first_person == null:
		return
	var ag := _ambient_of(v)
	var former: Array = []
	if not ag.is_empty():
		former = (ag.members as Array).duplicate()
		_end_ambient(ag)          # bọn trẻ đang chơi dở: tan ván đó, chơi lại từ đầu với người chơi
	base = first_person.global_position
	found.clear()
	escaped.clear()
	hiders.clear()
	# Gọi thêm trẻ con quanh đây (đang rảnh), thiếu thì trẻ nhà bên chạy sang
	hiders.append(v)
	# Cả nhóm đang chơi dở vào chơi tiếp với người chơi (dù đang nấp ở xa)
	for p in former:
		if hiders.size() < hider_count and p != v and is_instance_valid(p) and refusal(p) == "":
			hiders.append(p)
	if villagers != null:
		var near: Array[Villager] = []
		for p in villagers.people:
			if p != v and p.visible and p.role in ["kid", "herder"] and p.global_position.distance_to(base) < 45.0 \
					and refusal(p) == "" and not p.has_meta("talking") and not p.has_meta("at_school"):
				near.append(p)
		near.sort_custom(func(a: Villager, b: Villager) -> bool: return a.global_position.distance_to(base) < b.global_position.distance_to(base))
		for p in near:
			if hiders.size() >= hider_count:
				break
			if not hiders.has(p):
				hiders.append(p)
	var k := 0
	while hiders.size() < hider_count:
		hiders.append(_make_temp(k))
		k += 1
	var spots := _find_spots(base, hiders.size())
	for i in hiders.size():
		var h := hiders[i]
		var spot: Vector3 = spots[i] if i < spots.size() else base + Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12))
		h.set_meta("hs_spot", spot)
		h.set_meta("hs_player", true)
		_run_to(h, spot, "đang chạy đi trốn")
	# Bịt mắt đếm
	phase = Phase.COUNT
	_t = count_seconds
	_marker.global_position = base + Vector3(0, 0.02, 0)
	_marker.visible = true
	first_person._suspend("count")
	_ui.visible = true
	_blind.visible = true
	_panel.visible = false
	if hud != null:
		hud.set_hint("")
	_say(v, _pick(["Bịt mắt vào, đếm đến mười nhé! Không được ăn gian đâu!", "Đếm to lên nhé! Chạy thôi các bạn ơi!"]))


func _make_temp(k: int) -> Villager:
	var female := _rng.randf() < 0.5
	var t := Villager.new()
	t.name = "HideSeekKid%d" % k
	t.role = "kid"
	t.role_name = "Trẻ con nhà bên"
	t.display_name = TEMP_NAMES[(k + _rng.randi_range(0, 3)) % TEMP_NAMES.size()]
	t.home = {"name": "Nhà bên", "key": ""}
	t.speed = _rng.randf_range(1.8, 2.3)
	t.set_meta("female", female)
	add_child(t)
	var look: Dictionary = villagers._look("kid", female) if villagers != null else {"shirt": Palette.SIGN_BLUE, "pants": Palette.WINDOW_DARK, "skin": Palette.FARMER_SKIN, "hat": "none", "scale": 0.66, "female": female, "prop": "none"}
	t.build_person(look)
	var a := _rng.randf() * TAU
	t.global_position = base + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.5, 3.0)
	t.global_position.y = base.y
	_temps.append(t)
	return t


## Cho `h` chạy tới `to` (người thật trong làng: theo đồ thị đường; trẻ tạm: thẳng tới).
func _run_to(h: Villager, to: Vector3, text: String) -> void:
	h.remove_meta("talking")
	h.remove_meta("hiding")
	h.visible = true
	h.state = Villager.State.IDLE
	var p := PackedVector3Array()
	if villagers != null and villagers.people.has(h) and h.global_position.distance_to(to) > 6.0:
		p = villagers.find_path(h.global_position, to)
	p.append(to)
	if villagers != null and villagers.people.has(h):
		h.activity = "hideseek"
		h.dwell = 1.0e6
	h.walk_path(p)
	h.speed_mul = 1.8
	h.work_anim = "idle"
	h.activity_text = text


# --- Tìm chỗ trốn ----------------------------------------------------------------------------

## `n` chỗ trốn quanh `b`: mặt đất cùng độ cao, không kẹt trong vật, đứng ở cột không nhìn thấy,
## sát một vật che; cách nhau ít nhất 5 m.
func _find_spots(b: Vector3, n: int) -> Array[Vector3]:
	var space := get_world_3d().direct_space_state
	var mask := 1 << (FirstPerson.SOLID_LAYER - 1)
	var eye := b + Vector3(0, 1.6, 0)
	var out: Array[Vector3] = []
	var backup: Array[Vector3] = []
	for attempt in 500:
		if out.size() >= n:
			break
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(spot_range.x, spot_range.y)
		var q := b + Vector3(cos(a) * r, 0, sin(a) * r)
		var down := PhysicsRayQueryParameters3D.create(Vector3(q.x, b.y + 1.4, q.z), Vector3(q.x, b.y - 1.5, q.z), mask)
		var hit := space.intersect_ray(down)
		if hit.is_empty():
			continue
		var gy := float(hit.position.y)
		if absf(gy - b.y) > 0.6:
			continue                     # bậc cao / lòng ao, sông
		var p := Vector3(q.x, gy, q.z)
		# Không kẹt trong vật
		var shape := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.32
		shape.shape = sph
		shape.transform = Transform3D(Basis(), p + Vector3(0, 0.55, 0))
		shape.collision_mask = mask
		if not space.intersect_shape(shape, 1).is_empty():
			continue
		var crowd := false
		for o in out:
			if o.distance_to(p) < 5.0:
				crowd = true
				break
		if crowd:
			continue
		# Đứng ở cột không nhìn thấy (đầu người ngồi thụp ~0,7 m)
		var see := PhysicsRayQueryParameters3D.create(eye, p + Vector3(0, 0.7, 0), mask)
		if space.intersect_ray(see).is_empty():
			if backup.size() < n:
				backup.append(p)
			continue
		# Sát một vật che (tường, rào, đống rơm…)
		var near := false
		for k in 8:
			var d := Vector3(cos(k * PI / 4.0), 0, sin(k * PI / 4.0))
			var probe := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.5, 0), p + Vector3(0, 0.5, 0) + d * 1.4, mask)
			if not space.intersect_ray(probe).is_empty():
				near = true
				break
		if near:
			out.append(p)
	while out.size() < n and not backup.is_empty():
		out.append(backup.pop_back())
	return out


# --- Diễn biến ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_process_ambient(delta)
	if phase == Phase.OFF:
		return
	for t in _temps:
		if is_instance_valid(t):
			var was := t.state == Villager.State.WALK
			t.tick(delta, true)
			if was and t.state == Villager.State.IDLE:
				on_arrive(t)
	match phase:
		Phase.COUNT:
			_t -= delta
			var n := clampi(int(floor(count_seconds - _t)) , 0, 9)
			_count_label.text = "Bịt mắt đếm…\n\n" + COUNT_WORDS[n] + "!"
			if _t <= 0.0:
				_begin_seek()
		Phase.SEEK:
			_seek(delta)
		Phase.RESULT:
			_result_t -= delta
			if _result_t <= 0.0:
				stop()
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint_text = ""
	_update_ui()


## Hết đếm: ai chưa tới chỗ thì đặt luôn vào chỗ, ngồi thụp xuống trốn.
func _begin_seek() -> void:
	for h in hiders:
		if not h.has_meta("hiding"):
			h.global_position = h.get_meta("hs_spot")
			h.path = PackedVector3Array()
			h.state = Villager.State.IDLE
			_hide(h)
	phase = Phase.SEEK
	_t = seek_seconds
	_hint_t = hint_interval * 0.6
	_escape_t = 25.0
	_blind.visible = false
	_panel.visible = true
	first_person._resume()
	_hint_text = "Trốn kỹ chưa? Tìm đây!"
	_hint_timer = 3.0


func _hide(h: Villager) -> void:
	h.set_meta("hiding", true)
	h.set_meta("talking", true)            # Villagers / SchoolDay để yên
	h.work_anim = "squat"
	h.activity_text = "đang trốn"
	# Quay lưng ra phía cột cho có vẻ đang nấp
	var d := h.global_position - base
	h.rotation.y = atan2(d.x, d.z) + _rng.randf_range(-0.6, 0.6)


## Người trốn (trẻ trong làng, việc `hideseek`) chạy tới nơi — Villagers gọi.
func on_arrive(h: Villager) -> void:
	if not hiders.has(h):
		return
	if h.has_meta("hs_escaping"):
		h.remove_meta("hs_escaping")
		if not found.has(h):
			escaped.append(h)
			h.set_meta("hs_done", true)
			_say(h, _pick(["Đập cột! Hì hì!", "Về cột rồi nhé!", "Không bắt được {self} đâu!"]))
		_cheer(h)
		_check_end()
		return
	if h.has_meta("hs_done"):
		_cheer(h)
		return
	if phase == Phase.COUNT or phase == Phase.SEEK:
		_hide(h)


func _cheer(h: Villager) -> void:
	h.set_meta("talking", true)
	h.work_anim = "play"
	var d := first_person.global_position - h.global_position if first_person != null else Vector3.FORWARD
	h.rotation.y = atan2(d.x, d.z)


func _seek(delta: float) -> void:
	_t -= delta
	if first_person == null or not first_person.active:
		stop()
		return
	var cam := first_person.camera
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var mask := 1 << (FirstPerson.SOLID_LAYER - 1)
	for h in hiders:
		if h.has_meta("hs_done"):
			continue
		var target := h.global_position + Vector3(0, 0.6, 0)
		var to := target - eye
		var dist := to.length()
		if dist < spot_distance and fwd.dot(to / dist) > 0.82:
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target, mask)).is_empty():
				spot(h)
	# Lén về đập cột khi người tìm đi xa
	_escape_t -= delta
	if _escape_t <= 0.0:
		_escape_t = 2.0
		var pd := Vector2(first_person.global_position.x - base.x, first_person.global_position.z - base.z).length()
		if pd > escape_distance:
			for h in hiders:
				if h.has_meta("hiding") and _rng.randf() < 0.07:
					var hv := h.global_position + Vector3(0, 0.6, 0) - eye
					if fwd.dot(hv.normalized()) < 0.5:
						h.set_meta("hs_escaping", true)
						_run_to(h, base + Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.8, 0.8)), "đang lén chạy về đập cột")
						h.speed_mul = 2.0
						_hint_text = "Có đứa đang lén chạy về cột!"
						_hint_timer = 3.0
						break
	# Tiếng cười khúc khích chỉ hướng
	_hint_t -= delta
	if _hint_t <= 0.0:
		_hint_t = hint_interval
		var left: Array[Villager] = []
		for h in hiders:
			if h.has_meta("hiding"):
				left.append(h)
		if not left.is_empty():
			var h: Villager = left[_rng.randi_range(0, left.size() - 1)]
			_hint_text = "Có tiếng cười khúc khích ở %s…" % _direction(h.global_position)
			_hint_timer = 5.0
	if _t <= 0.0:
		_end_round()


## Hướng của điểm `p` so với chỗ người chơi đang nhìn.
func _direction(p: Vector3) -> String:
	var cam := first_person.camera
	var to := p - cam.global_position
	to.y = 0
	var f := -cam.global_transform.basis.z
	f.y = 0
	var ang := rad_to_deg(f.normalized().signed_angle_to(to.normalized(), Vector3.UP))
	if absf(ang) < 40.0:
		return "phía trước"
	if absf(ang) > 135.0:
		return "phía sau lưng"
	return "bên trái" if ang > 0.0 else "bên phải"


## Bắt được `h` (nhìn thấy, hoặc nhìn vào nhấn E).
func spot(h: Villager) -> void:
	if phase != Phase.SEEK or h.has_meta("hs_done") or not hiders.has(h):
		return
	h.set_meta("hs_done", true)
	found.append(h)
	h.remove_meta("hs_escaping")
	_say(h, _pick(["Ối, bị tìm thấy rồi!", "Hừ, {you} tinh mắt thế!", "Sao {you} biết {self} trốn ở đây?"]))
	_hint_text = "Tìm thấy %s rồi!" % h.display_name
	_hint_timer = 2.5
	_run_to(h, base + Vector3(_rng.randf_range(-2.0, 2.0), 0, _rng.randf_range(-2.0, 2.0)), "đã bị tìm thấy, đang về cột")
	h.speed_mul = 1.2
	_check_end()


func _check_end() -> void:
	if phase == Phase.SEEK and found.size() + escaped.size() >= hiders.size():
		_end_round()


func _end_round() -> void:
	phase = Phase.RESULT
	_result_t = 5.0
	var miss := hiders.size() - found.size() - escaped.size()
	var line := "Tìm thấy %d / %d bạn" % [found.size(), hiders.size()]
	if not escaped.is_empty():
		line += "  ·  %d bạn về đập cột" % escaped.size()
	if miss > 0:
		line += "  ·  %d bạn chưa tìm ra" % miss
	_count_label.text = line
	_blind.visible = true
	_blind.color = Color(0, 0, 0, 0.45)
	if found.size() == hiders.size() and not hiders.is_empty():
		_say(hiders[0], _pick(["Giỏi quá! Ván sau đến lượt {you} trốn nhé!", "{You} tìm nhanh thế!"]))
	elif miss > 0:
		_say(hiders[0], "Hết giờ rồi! Bọn {self} trốn giỏi chưa?")
		for h in hiders:
			if h.has_meta("hiding"):
				_say(h, "Em ở đây này!" if h.role == "kid" else "Ở đây cơ!")
				_cheer(h)


## Thôi chơi / hết ván: trả bọn trẻ về việc của mình, trẻ nhà bên đi về.
func stop() -> void:
	if phase == Phase.OFF:
		return
	var was := phase
	phase = Phase.OFF
	_ui.visible = false
	_marker.visible = false
	_blind.color = Color(0, 0, 0, 0.9)
	for h in hiders:
		if not is_instance_valid(h):
			continue
		for m in ["hiding", "talking", "hs_spot", "hs_done", "hs_escaping", "hs_player"]:
			h.remove_meta(m)
		h.visible = true
		h.speed_mul = 1.0
		h.work_anim = "idle"
		if villagers != null and villagers.people.has(h):
			h.state = Villager.State.IDLE
			h.path = PackedVector3Array()
			h.dwell = 0.0              # Villagers chọn việc tiếp theo
	for t in _temps:
		if is_instance_valid(t):
			t.queue_free()
	_temps.clear()
	if first_person != null and was == Phase.COUNT:
		first_person._resume()
	finished.emit(found.size(), escaped.size(), hiders.size())
	hiders.clear()


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.OFF:
		return
	if event.is_action_pressed("exit_interior"):
		stop()
		get_viewport().set_input_as_handled()


# --- Hình, giao diện ----------------------------------------------------------------------------

func _build_marker() -> void:
	var mb := MeshBuilder.new(5, 0.0)
	for k in 16:
		var a0 := TAU * k / 16.0
		var a1 := TAU * (k + 1) / 16.0
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.9
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.9
		var mid := (p0 + p1) * 0.5
		var seg := p1 - p0
		mb.add_box(Vector3(seg.length() + 0.01, 0.01, 0.05), Palette.FLOWER_WHITE, Transform3D(Basis(Vector3.UP, -atan2(seg.z, seg.x)), mid))
	_marker = mb.commit_instance("BaseMark")
	_marker.top_level = true
	_marker.visible = false
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 4
	_ui.visible = false
	add_child(_ui)
	_blind = ColorRect.new()
	_blind.color = Color(0, 0, 0, 0.9)
	_blind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_blind)
	_count_label = Label.new()
	_count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_override("font", Hud.font(true))
	_count_label.add_theme_font_size_override("font_size", 46)
	_count_label.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_blind.add_child(_count_label)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = 70
	_ui.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_status = Label.new()
	_status.add_theme_font_override("font", Hud.font(true))
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	_sub = Label.new()
	_sub.add_theme_font_override("font", Hud.font(false))
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", Palette.FLOWER_YELLOW)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)


func _update_ui() -> void:
	if phase == Phase.SEEK:
		var s := int(maxf(_t, 0.0))
		_status.text = "Trốn tìm  ·  tìm thấy %d / %d  ·  còn %d:%02d" % [found.size(), hiders.size(), s / 60, s % 60]
		_sub.text = _hint_text if _hint_text != "" else "Nhìn thấy là bắt được  ·  Esc: thôi chơi"


func _say(v: Villager, text: String) -> void:
	if dialogue != null and is_instance_valid(v):
		dialogue.bark(v, dialogue.fill_for(v, text))


func _pick(arr: Array) -> String:
	return str(arr[_rng.randi_range(0, arr.size() - 1)])

# --- Bọn trẻ tự chơi (không có người chơi) --------------------------------------------------------

func ambient_ok(h: float) -> bool:
	if village == null or h < 7.0 or h >= 18.0 or (h >= 11.3 and h < 13.3):
		return false
	return weather == null or not weather.kind in ["drizzle", "storm"]


func _ensure_ambient_sites() -> void:
	if not ambient_bases.is_empty() or village == null:
		return
	for k in [1, 3]:
		var z: float = village.alley_z[mini(k, village.alley_z.size() - 1)]
		ambient_bases.append(Vector3(village.lane_x(z), 0.05, z))
	# Chỗ trốn: nấp sau rào ngay cạnh cổng các nhà (đi qua cổng rồi rẽ sang), sau gốc đa, cạnh giếng
	for hm in village.homes:
		var fwd: Vector3 = hm.forward
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		var gate: Vector3 = hm.gate
		for sg in [-1.0, 1.0]:
			_amb_spots.append(Vector3(gate.x, 0.05, gate.z) - fwd * 1.5 + side * sg * 1.5)
	_amb_spots.append(village.banyan_position + Vector3(0, 0.05, -2.2))
	_amb_spots.append(village.well_position + Vector3(-1.6, 0.05, -1.2))


func site_target(v: Villager) -> Vector3:
	_ensure_ambient_sites()
	var best := 0
	for i in ambient_bases.size():
		if v.global_position.distance_to(ambient_bases[i]) < v.global_position.distance_to(ambient_bases[best]):
			best = i
	var a := _rng.randf() * TAU
	return ambient_bases[best] + Vector3(cos(a), 0, sin(a)) * 1.2


func _ambient_of(v: Villager) -> Dictionary:
	for g in ambient:
		if (g.members as Array).has(v):
			return g
	return {}


func is_ambient_member(v: Villager) -> bool:
	return v.has_meta("hs_amb")


## Villagers gọi khi một đứa (việc `hs_play`) đi tới nơi: tới cột để vào chơi, tới chỗ trốn, về cột,
## hoặc người đi tìm tới một chỗ nghi có người trốn.
func ambient_arrive(v: Villager) -> void:
	var g := _ambient_of(v)
	if g.is_empty():
		_ensure_ambient_sites()
		var best := 0
		for i in ambient_bases.size():
			if v.global_position.distance_to(ambient_bases[i]) < v.global_position.distance_to(ambient_bases[best]):
				best = i
		for og in ambient:
			if (og.base as Vector3).distance_to(ambient_bases[best]) < 1.0:
				g = og
		if g.is_empty():
			g = {"base": ambient_bases[best], "members": [], "seeker": null, "hiders": [], "spots": {},
					"phase": "gather", "t": 6.0, "t_left": _rng.randf_range(ambient_seconds.x, ambient_seconds.y),
					"visits": [], "found": [], "escaped": [], "next_seeker": null, "wait": 0.0}
			ambient.append(g)
		if (g.members as Array).size() >= 6:
			v.dwell = 0.0
			return
		(g.members as Array).append(v)
		v.set_meta("hs_amb", true)
		v.dwell = 1.0e6
		_amb_idle(g, v, "play")
		return
	v.dwell = 1.0e6
	match str(g.phase):
		"count", "seek", "back":
			if v == g.seeker:
				_amb_seeker_arrived(g)
			elif v.has_meta("hs_back"):
				_amb_home(g, v)
			elif (g.hiders as Array).has(v):
				_amb_hide(g, v)
		_:
			_amb_idle(g, v, "play")


## Đứng chơi quanh cột (đứng yên: Villagers chỉ diễn hoạt).
func _amb_idle(g: Dictionary, v: Villager, anim: String) -> void:
	v.set_meta("talking", true)
	v.state = Villager.State.IDLE
	v.work_anim = anim
	v.speed_mul = 1.0
	v.activity_text = "đang chơi trốn tìm"
	var d := (g.base as Vector3) - v.global_position
	if d.length() > 0.3:
		v.rotation.y = atan2(d.x, d.z)


func _amb_run(v: Villager, to: Vector3, text: String) -> void:
	v.remove_meta("talking")
	v.state = Villager.State.IDLE
	var p := PackedVector3Array()
	if villagers != null and v.global_position.distance_to(to) > 6.0:
		p = villagers.find_path(v.global_position, to)
	p.append(to)
	v.activity = "hs_play"
	v.dwell = 1.0e6
	v.walk_path(p)
	v.speed_mul = 1.8
	v.work_anim = "idle"
	v.activity_text = text


func _amb_hide(g: Dictionary, v: Villager) -> void:
	v.set_meta("talking", true)
	v.set_meta("hs_hidden", true)
	v.state = Villager.State.IDLE
	v.work_anim = "squat"
	v.speed_mul = 1.0
	v.activity_text = "đang trốn"
	var d := v.global_position - (g.base as Vector3)
	v.rotation.y = atan2(d.x, d.z)


func _amb_home(g: Dictionary, v: Villager) -> void:
	v.remove_meta("hs_back")
	_amb_idle(g, v, "play")
	_check_ambient_round(g)


func _process_ambient(delta: float) -> void:
	var h := day_night.time_of_day if day_night != null else 15.0
	for g in ambient.duplicate():
		var members: Array = g.members
		# Ai bị Villagers gọi đi (tối, mưa, đi học…) thì rời cuộc chơi
		for v: Villager in members.duplicate():
			if not is_instance_valid(v) or v.activity != "hs_play":
				_amb_drop(g, v)
		g.t_left = float(g.t_left) - delta
		if not ambient_ok(h) or (float(g.t_left) <= 0.0 and str(g.phase) == "gather"):
			_end_ambient(g)
			continue
		match str(g.phase):
			"gather":
				g.t = float(g.t) - delta
				if members.size() < 3:
					g.wait = float(g.wait) + delta
					if float(g.wait) > 50.0:
						_end_ambient(g)
				elif float(g.t) <= 0.0:
					_amb_round(g)
			"count":
				g.t = float(g.t) - delta
				if float(g.t) <= 0.0:
					_amb_begin_seek(g)
			"seek":
				g.t = float(g.t) - delta
				var seeker: Villager = g.seeker
				var far := seeker.global_position.distance_to(g.base) > 14.0
				for v: Villager in g.hiders:
					if v.has_meta("hs_hidden") and far and _rng.randf() < ambient_escape_rate * delta:
						v.remove_meta("hs_hidden")
						v.set_meta("hs_back", true)
						(g.escaped as Array).append(v)
						_say(v, _pick(["Đập cột! Hì hì!", "Về cột rồi nhé!"]))
						_amb_run(v, (g.base as Vector3) + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2)), "đang chạy về đập cột")
				if float(g.t) <= 0.0:
					_amb_give_up(g)
			"back":
				_check_ambient_round(g)


## Bắt đầu một vòng: một đứa bịt mắt đếm ở cột, những đứa khác chạy đi trốn.
func _amb_round(g: Dictionary) -> void:
	var members: Array = g.members
	var seeker: Villager = g.next_seeker if g.next_seeker != null and members.has(g.next_seeker) else members[_rng.randi_range(0, members.size() - 1)]
	g.seeker = seeker
	g.next_seeker = null
	g.hiders = []
	g.spots = {}
	g.found = []
	g.escaped = []
	var base: Vector3 = g.base
	var cand: Array[Vector3] = []
	for p in _amb_spots:
		var d := Vector2(p.x - base.x, p.z - base.z).length()
		if d >= ambient_spot_range.x and d <= ambient_spot_range.y:
			cand.append(p)
	cand.shuffle()
	for v: Villager in members:
		if v == seeker:
			continue
		(g.hiders as Array).append(v)
		var spot: Vector3 = cand.pop_back() if not cand.is_empty() else base + Vector3(_rng.randf_range(-15, 15), 0, _rng.randf_range(-15, 15))
		g.spots[v] = spot
		v.remove_meta("hs_hidden")
		_amb_run(v, spot, "đang chạy đi trốn")
	g.visits = cand.slice(0, 2)            # vài chỗ không có ai, đi tìm nhầm
	_amb_idle(g, seeker, "pray")             # bịt mắt đếm
	seeker.activity_text = "đang bịt mắt đếm"
	seeker.rotation.y = _rng.randf() * TAU
	_say(seeker, _pick(["Một… hai… ba… Trốn đi!", "Đếm đến mười nhé! Một… hai…"]))
	g.phase = "count"
	g.t = count_seconds


func _amb_begin_seek(g: Dictionary) -> void:
	for v: Villager in g.hiders:
		if not v.has_meta("hs_hidden"):
			v.global_position = g.spots[v]
			v.path = PackedVector3Array()
			_amb_hide(g, v)
	# Lộ trình đi tìm: chỗ trốn thật + vài chỗ trống, chỗ nào gần đi trước
	var todo: Array = (g.visits as Array).duplicate()
	for v: Villager in g.hiders:
		todo.append(g.spots[v])
	var route: Array = []
	var at: Vector3 = g.base
	while not todo.is_empty():
		var bi := 0
		for i in todo.size():
			if at.distance_to(todo[i]) < at.distance_to(todo[bi]):
				bi = i
		at = todo[bi]
		route.append(at)
		todo.remove_at(bi)
	g.visits = route
	g.phase = "seek"
	g.t = 150.0
	var seeker: Villager = g.seeker
	_say(seeker, "Trốn kỹ chưa? Tìm đây!")
	_amb_next_visit(g)


func _amb_next_visit(g: Dictionary) -> void:
	var seeker: Villager = g.seeker
	var visits: Array = g.visits
	var left := 0
	for v: Villager in g.hiders:
		if v.has_meta("hs_hidden"):
			left += 1
	if visits.is_empty() or left == 0:
		g.phase = "back"
		_amb_run(seeker, (g.base as Vector3) + Vector3(0.8, 0, 0.8), "đang về cột")
		return
	var to: Vector3 = visits.pop_front()
	_amb_run(seeker, to, "đang đi tìm")
	seeker.speed_mul = 1.3


## Người đi tìm tới một chỗ: ai trốn ở đó thì bị bắt, chạy về cột.
func _amb_seeker_arrived(g: Dictionary) -> void:
	var seeker: Villager = g.seeker
	if str(g.phase) == "back":
		_amb_idle(g, seeker, "play")
		_check_ambient_round(g)
		return
	var caught := false
	for v: Villager in g.hiders:
		if v.has_meta("hs_hidden") and v.global_position.distance_to(seeker.global_position) < 2.0:
			v.remove_meta("hs_hidden")
			v.set_meta("hs_back", true)
			(g.found as Array).append(v)
			if g.next_seeker == null:
				g.next_seeker = v          # đứa bị bắt đầu tiên đi tìm vòng sau
			caught = true
			_say(v, _pick(["Ối, bị bắt rồi!", "Sao tìm ra hay thế!", "Hừ, lần sau trốn kỹ hơn!"]))
			_amb_run(v, (g.base as Vector3) + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2)), "đang về cột")
	if caught:
		_say(seeker, _pick(["Thấy rồi nhé!", "Bắt được rồi!"]))
	_amb_next_visit(g)


## Hết giờ tìm: những đứa còn trốn tự ra.
func _amb_give_up(g: Dictionary) -> void:
	_say(g.seeker, "Thôi chịu, ra đi!")
	for v: Villager in g.hiders:
		if v.has_meta("hs_hidden"):
			v.remove_meta("hs_hidden")
			v.set_meta("hs_back", true)
			_say(v, "Em ở đây này!")
			_amb_run(v, (g.base as Vector3) + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2)), "đang về cột")
	g.visits = []
	_amb_next_visit(g)


## Vòng xong khi mọi đứa đã về cột → nghỉ một chút rồi vòng mới (hết giờ chơi thì tan).
func _check_ambient_round(g: Dictionary) -> void:
	if str(g.phase) != "back" and str(g.phase) != "seek":
		return
	var seeker: Villager = g.seeker
	if seeker.state == Villager.State.WALK or seeker.global_position.distance_to(g.base) > 3.0:
		return
	for v: Villager in g.hiders:
		if v.has_meta("hs_hidden") or v.has_meta("hs_back"):
			return
	g.phase = "gather"
	g.t = 5.0
	g.wait = 0.0


func _amb_drop(g: Dictionary, v: Villager) -> void:
	(g.members as Array).erase(v)
	(g.hiders as Array).erase(v)
	if is_instance_valid(v):
		for m in ["hs_amb", "hs_hidden", "hs_back"]:
			v.remove_meta(m)
		v.speed_mul = 1.0
	if g.seeker == v:
		g.seeker = null
		_end_ambient(g)


func _end_ambient(g: Dictionary) -> void:
	for v: Villager in g.members:
		if not is_instance_valid(v):
			continue
		for m in ["hs_amb", "hs_hidden", "hs_back", "talking"]:
			v.remove_meta(m)
		v.speed_mul = 1.0
		v.work_anim = "idle"
		v.state = Villager.State.IDLE
		v.path = PackedVector3Array()
		v.dwell = 0.0
	ambient.erase(g)


## Nhập vai nhìn một đứa đang chơi: "E: Xin chơi trốn tìm" → tan ván dở, chơi lại từ đầu, người chơi đi tìm.
func join_ambient(v: Villager) -> void:
	if phase != Phase.OFF or refusal(v) != "":
		return
	start(v)

