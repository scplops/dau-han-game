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
	base = first_person.global_position
	found.clear()
	escaped.clear()
	hiders.clear()
	# Gọi thêm trẻ con quanh đây (đang rảnh), thiếu thì trẻ nhà bên chạy sang
	hiders.append(v)
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
