class_name Fishing
extends Node3D
## Mini-game câu cá ở các bến sông (mục 16). Không có nhân vật điều khiển đi lại:
## người câu là hình ngồi cố định trên ghế đẩu cạnh cầu ván, chỉ hiện khi đang câu.
## - Ngoài sân: bấm vào chỗ ngồi câu (hoặc E khi ở gần) để bắt đầu; Esc / E để thôi.
## - Giữ chuột trái / Space để lấy đà → thả để quăng phao → chờ cá THẬT trong sông bơi tới
##   → phao nhấp (giật lúc này là sớm) → phao chìm: bấm ngay để giật cần
##   → kéo cá: giữ để cuộn dây, thả khi dây căng; căng quá thì đứt, chùng lâu thì cá sổng.
## - Cá ăn mạnh lúc sáng sớm, chiều muộn; kém buổi trưa, ban đêm; mưa phùn ăn hơn; giông thì nghỉ.

## Thôi câu (người nhập vai lấy lại camera).
signal stopped

enum State { OFF, READY, CHARGE, CAST, WAIT, NIBBLE, BITE, REEL, CAUGHT, LOST }

## Loài cá theo thứ tự màu cá trong River (cam, đỏ, vàng, xám, xám sẫm, trắng).
## kg: khoảng cân nặng; len: hệ số chiều dài (cm ≈ len × căn bậc ba của kg);
## pull: độ giãy khoẻ; window: hệ số thời gian kịp giật cần.
const SPECIES: Array = [
	{"name": "Cá chép", "kg": Vector2(0.6, 3.0), "len": 36.0, "pull": 0.75, "window": 1.0},
	{"name": "Cá chép đỏ", "kg": Vector2(0.5, 2.5), "len": 35.0, "pull": 0.7, "window": 1.0},
	{"name": "Cá diếc", "kg": Vector2(0.1, 0.5), "len": 31.0, "pull": 0.35, "window": 0.75},
	{"name": "Cá trắm cỏ", "kg": Vector2(1.0, 5.0), "len": 42.0, "pull": 1.0, "window": 1.1},
	{"name": "Cá trê", "kg": Vector2(0.3, 1.5), "len": 47.0, "pull": 0.85, "window": 0.9},
	{"name": "Cá mè trắng", "kg": Vector2(0.8, 4.0), "len": 40.0, "pull": 0.8, "window": 1.0},
]

@export var river: River
@export var house_entry: HouseEntry
@export var outdoor_rig: CameraRig
@export var day_night: DayNight
@export var weather: Weather
@export var hud: Hud
@export var villagers: Villagers

@export_group("Câu")
## Thời gian chờ cá để ý tới mồi (giây), nhân với hệ số theo giờ và thời tiết.
@export var wait_time: Vector2 = Vector2(4.0, 10.0)
## Cá trong bán kính này quanh phao mới bơi tới.
@export var lure_radius: float = 16.0
@export var approach_speed: float = 0.9
@export var nibble_count: Vector2i = Vector2i(1, 3)
## Thời gian kịp giật cần khi phao chìm (giây).
@export var bite_window: float = 0.9
## Một chu kỳ lực quăng 0 → 1 → 0 (giây).
@export var charge_period: float = 1.6
## Phao rơi cách bờ từ … tới … (m), không quá lòng sông.
@export var cast_range: Vector2 = Vector2(2.5, 13.0)
@export var cast_time: float = 0.8

@export_group("Kéo cá")
@export var reel_speed: float = 0.2
@export var tension_rise: float = 0.55
@export var tension_fall: float = 1.1
## Dây chùng quá lâu (giây) thì cá sổng.
@export var slack_escape: float = 3.0

@export_group("Camera")
@export var cam_distance: float = 9.5
@export var cam_pitch: float = -30.0
@export var cam_side_deg: float = -30.0

var state: State = State.OFF
var _spot: int = -1
var _spots: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _t: float = 0.0
var _power: float = 0.0
var _wait_timer: float = 0.0
var _nibbles: int = 0
var _dip: float = 0.0
var _leave_timer: float = -1.0
var _freeze: bool = false        # dừng diễn biến theo thời gian (công cụ chụp ảnh)
var _debug_hold: bool = false

# Phao, cá
var _bob_pos := Vector3.ZERO
var _cast_from := Vector3.ZERO
var _cast_to := Vector3.ZERO
var _fish: int = -1
var _fish_pos := Vector3.ZERO
var _fish_yaw: float = 0.0
var _fish_kind: int = 0
var _fish_size: float = 1.0
var _fish_kg: float = 0.0
var _fish_cm: float = 0.0
var _hook_pos := Vector3.ZERO
var _leap_from := Vector3.ZERO

# Kéo cá
var _tension: float = 0.0
var _progress: float = 0.0
var _slack: float = 0.0
var _surge: float = 0.0          # 0..1: cá đang vùng chạy
var _surge_timer: float = 0.0
var _splash_timer: float = 0.0
var _strength: float = 0.7
var _side: float = 1.0

# Sổ câu: loài → {count, best}
var _log: Dictionary = {}
var _total: int = 0

# Hình
var _angler: Node3D
var _body: Node3D
var _rod: Node3D
var _tip: Node3D
var _bobber: Node3D
var _line: MeshInstance3D
var _line_mesh := ImmediateMesh.new()
var _line_mat: StandardMaterial3D

# Camera trước khi câu
var _saved_cam: Dictionary = {}

# Giao diện
var _ui: CanvasLayer
var _prompt_panel: PanelContainer
var _prompt: Label
var _toast: String = ""
var _toast_timer: float = 0.0
var _meter_panel: PanelContainer
var _meter_a: Label
var _bar_a: ColorRect
var _bar_a_bg: ColorRect
var _meter_b: Label
var _bar_b: ColorRect
var _bar_b_bg: ColorRect
var _danger: ColorRect
var _card: PanelContainer
var _card_title: Label
var _card_body: Label
var _log_panel: PanelContainer
var _log_label: Label


func _ready() -> void:
	_rng.randomize()   # diễn biến câu mỗi lần một khác (cảnh vẫn sinh theo seed cố định)
	_build_angler()
	_build_bobber_and_line()
	_build_ui()
	if river != null:
		for i in river.landings.size():
			_make_spot(i, river.landings[i])
	_set_visuals(false)


# --- Dựng hình ------------------------------------------------------------------------

static func _t3(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


func _make_spot(i: int, landing: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "FishSpot%d" % i
	node.transform = Transform3D(Basis(Vector3.UP, float(landing.face)), landing.fish_spot)
	add_child(node)
	# Cần tre dựng nghiêng chờ sẵn trên cọc (ẩn khi đang câu)
	var mb := MeshBuilder.new(70 + i, 0.04)
	mb.add_limb(Vector3(0.42, 0.02, -0.4), Vector3(0.3, 1.9, 2.2), 0.022, 0.009, 5, Palette.BAMBOO_STEM)
	for k in 4:
		var p := Vector3(0.42, 0.02, -0.4).lerp(Vector3(0.3, 1.9, 2.2), 0.15 + k * 0.2)
		mb.add_limb(p, p + Vector3(0.3, 1.9, 2.2).direction_to(Vector3(0.42, 0.02, -0.4)) * -0.03,
				0.024 - k * 0.003, 0.024 - k * 0.003, 5, Palette.BAMBOO_NODE)
	var idle := mb.commit_instance("IdleRod")
	node.add_child(idle)
	var target := HouseEntry.make_click_target(node, _t3(0.0, 0.55, 0.1), Vector3(1.6, 1.2, 1.6),
			"Ngồi câu cá  ·  " + str(landing.name))
	target.set_meta("activate", start.bind(i))
	target.add_to_group(HouseEntry.ACTIVATE_GROUP)
	_spots.append({"node": node, "idle": idle, "landing": landing})


## Người câu ngồi ghế đẩu, quay mặt ra sông (+z cục bộ). Cần câu gắn ở tay, hai khúc
## (gốc + ngọn) để ngọn cong xuống khi dây căng.
func _build_angler() -> void:
	_angler = Node3D.new()
	_angler.name = "Angler"
	add_child(_angler)
	var h := river.stool_height if river != null else 0.3
	_body = Node3D.new()
	_angler.add_child(_body)
	var mb := MeshBuilder.new(61, 0.03)
	var shirt := Palette.FARMER_SHIRT
	var pants := Palette.FARMER_PANTS
	var skin := Palette.FARMER_SKIN
	var hip_y := h + 0.04
	for sx: float in [-1.0, 1.0]:
		var hip := Vector3(sx * 0.09, hip_y, -0.12)
		var knee := Vector3(sx * 0.11, hip_y + 0.08, 0.22)
		var foot := Vector3(sx * 0.12, 0.05, 0.28)
		mb.add_limb(hip, knee, 0.068, 0.058, 6, pants)
		mb.add_limb(knee, foot, 0.055, 0.045, 6, pants)
		mb.add_box(Vector3(0.08, 0.05, 0.17), skin, _t3(foot.x, 0.0, foot.z + 0.04))
	var lean := Basis(Vector3.RIGHT, 0.2)
	var torso := Transform3D(lean, Vector3(0, hip_y - 0.02, -0.14))
	mb.add_prism(0.15, 0.17, 0.46, 6, shirt, torso)
	mb.add_prism(0.17, 0.12, 0.08, 6, shirt, torso * _t3(0, 0.44, 0))
	var neck := torso * Vector3(0, 0.5, 0)
	mb.add_limb(neck, neck + Vector3(0, 0.06, 0.01), 0.045, 0.045, 5, skin)
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	var head := neck + Vector3(0, 0.04, 0.02)
	mb.add_blob(Vector3(0.1, 0.11, 0.1), skin, rng, 0.08, _t3(head.x, head.y, head.z))
	# Nón lá
	mb.add_pyramid(0.3, 0.19, 12, Palette.HAT, _t3(head.x, head.y + 0.15, head.z))
	mb.add_prism(0.3, 0.3, 0.012, 12, Palette.HAT_DARK, _t3(head.x, head.y + 0.14, head.z))
	# Hai tay đưa ra trước cầm cần
	for sx: float in [-1.0, 1.0]:
		var sh := torso * Vector3(sx * 0.16, 0.4, 0.0)
		var el := Vector3(sx * 0.17, hip_y + 0.18, 0.1)
		var ha := Vector3(sx * 0.05, hip_y + 0.22, 0.32 - (0.1 if sx < 0 else 0.0))
		mb.add_limb(sh, el, 0.045, 0.04, 5, shirt)
		mb.add_limb(el, ha, 0.04, 0.035, 5, shirt)
		mb.add_blob(Vector3(0.04, 0.04, 0.04), skin, rng, 0.05, _t3(ha.x, ha.y - 0.04, ha.z))
	var mi := mb.commit_instance("Body")
	_body.add_child(mi)

	_rod = Node3D.new()
	_rod.name = "Rod"
	_rod.position = Vector3(0.0, hip_y + 0.22, 0.27)
	_angler.add_child(_rod)
	var rb := MeshBuilder.new(63, 0.03)
	rb.add_limb(Vector3(0, 0, -0.38), Vector3(0, 0, 1.9), 0.024, 0.014, 6, Palette.BAMBOO_STEM)
	for k in 5:
		var z := -0.2 + k * 0.45
		var r := 0.026 - k * 0.002
		rb.add_prism(r, r, 0.03, 6, Palette.BAMBOO_NODE, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, z)))
	rb.add_prism(0.03, 0.03, 0.14, 6, Palette.WOOD, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.38)))
	_rod.add_child(rb.commit_instance("RodBase"))
	_tip = Node3D.new()
	_tip.position = Vector3(0, 0, 1.9)
	_rod.add_child(_tip)
	var tb := MeshBuilder.new(64, 0.03)
	tb.add_limb(Vector3.ZERO, Vector3(0, 0, 1.5), 0.013, 0.005, 5, Palette.BAMBOO_STEM.lightened(0.1))
	_tip.add_child(tb.commit_instance("RodTip"))
	_set_rod(deg_to_rad(35.0), 0.0)


func _build_bobber_and_line() -> void:
	_bobber = Node3D.new()
	_bobber.name = "Bobber"
	_bobber.top_level = true
	add_child(_bobber)
	var mb := MeshBuilder.new(65, 0.0)
	mb.add_prism(0.012, 0.035, 0.05, 8, Palette.FLOWER_WHITE, _t3(0, -0.05, 0))
	mb.add_prism(0.035, 0.012, 0.07, 8, Palette.FLAG_RED, _t3(0, 0.0, 0))
	mb.add_limb(Vector3(0, 0.06, 0), Vector3(0, 0.14, 0), 0.006, 0.004, 4, Palette.FLAG_RED)
	var bi := mb.commit_instance("BobberMesh")
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bobber.add_child(bi)

	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.albedo_color = Color(Palette.FLOWER_WHITE, 0.85)
	_line = MeshInstance3D.new()
	_line.name = "FishingLine"
	_line.top_level = true
	_line.mesh = _line_mesh
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


func _set_visuals(on: bool) -> void:
	_angler.visible = on
	_bobber.visible = on
	_line.visible = on
	for i in _spots.size():
		(_spots[i].idle as Node3D).visible = not (on and i == _spot)


## Góc cần (rad, ngẩng lên so với mặt nằm ngang) và độ cong ngọn (rad, chúc xuống).
func _set_rod(elev: float, bend: float) -> void:
	_rod.basis = Basis(Vector3.RIGHT, -elev)
	_tip.basis = Basis(Vector3.RIGHT, bend)


func _rod_tip() -> Vector3:
	return _tip.global_transform * Vector3(0, 0, 1.5)


# --- Bắt đầu / kết thúc ---------------------------------------------------------------

## Ngồi câu ở bến thứ `i`.
func start(i: int, instant: bool = false) -> void:
	if state != State.OFF or i < 0 or i >= _spots.size():
		return
	if weather != null and weather.kind == "storm":
		_show_toast("Trời đang giông, không ra bến câu được.", 2.5)
		return
	_spot = i
	var node: Node3D = _spots[i].node
	_angler.reparent(node, false)
	_angler.transform = Transform3D.IDENTITY
	if house_entry != null:
		house_entry.locked = true
	if villagers != null:
		villagers.select_villager(null)
	if hud != null:
		hud.set_fishing("Câu cá · " + str(_spots[i].landing.name))
	if outdoor_rig != null:
		_saved_cam = {"yaw": outdoor_rig.yaw_deg, "pitch": outdoor_rig.pitch_deg,
				"distance": outdoor_rig.distance, "focus": outdoor_rig.global_position}
		var face := float(_spots[i].landing.face)
		var fwd := Vector3(sin(face), 0.0, cos(face))
		outdoor_rig.pan_locked = true
		outdoor_rig.yaw_deg = wrapf(rad_to_deg(face + PI) + cam_side_deg, -180.0, 180.0)
		outdoor_rig.pitch_deg = cam_pitch
		outdoor_rig.distance = cam_distance
		outdoor_rig.set_focus(node.global_position + fwd * 3.2 + Vector3(0, 0.3, 0))
		if instant:
			outdoor_rig.snap()
	_log_panel.visible = true
	_leave_timer = -1.0
	_set_visuals(true)
	_enter_ready()


## Thôi câu: trả cá (nếu có), trả camera, mở khoá vào nhà.
func stop() -> void:
	if state == State.OFF:
		return
	_drop_fish()
	state = State.OFF
	_freeze = false
	_debug_hold = false
	_set_visuals(false)
	_spot = -1
	_meter_panel.visible = false
	_card.visible = false
	_log_panel.visible = false
	if house_entry != null:
		house_entry.locked = false
	if hud != null:
		hud.set_fishing("")
	if outdoor_rig != null and not _saved_cam.is_empty():
		outdoor_rig.pan_locked = false
		outdoor_rig.yaw_deg = _saved_cam.yaw
		outdoor_rig.pitch_deg = _saved_cam.pitch
		outdoor_rig.distance = _saved_cam.distance
		outdoor_rig.set_focus(_saved_cam.focus)
	stopped.emit()


func _enter_ready() -> void:
	state = State.READY
	_card.visible = state == State.CAUGHT
	_meter_panel.visible = false


# --- Điều khiển -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == State.OFF:
		return
	if event.is_action_pressed("exit_interior") or event.is_action_pressed("interact"):
		stop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("fish_reel"):
		_on_press()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("fish_reel"):
		if state == State.CHARGE and not _debug_hold:
			_cast(maxf(_power, 0.12))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()   # không để chuột trái chọn dân làng khi đang câu


func _on_press() -> void:
	match state:
		State.READY:
			state = State.CHARGE
			_t = 0.0
			_power = 0.0
		State.WAIT:
			_drop_fish()
			_show_toast("Thu cần, quăng lại.", 1.2)
			_enter_ready()
		State.NIBBLE:
			_drop_fish()
			_show_toast("Giật sớm quá — cá hoảng bỏ đi rồi!", 2.0)
			state = State.WAIT
			_wait_timer = _roll_wait() + 2.0
		State.BITE:
			_hook()
		State.CAUGHT, State.LOST:
			_enter_ready()


func _cast(power: float) -> void:
	state = State.CAST
	_t = 0.0
	_power = power
	var node: Node3D = _spots[_spot].node
	var face := float(_spots[_spot].landing.face)
	var fwd := Vector2(sin(face), cos(face))
	var origin := Vector2(node.global_position.x, node.global_position.z)
	# Tầm xa nhất còn là nước (lòng sông cong, rộng hẹp khác nhau)
	var max_d := cast_range.x
	var d := cast_range.x
	while d <= cast_range.y:
		if river.is_water(origin + fwd * d, 1.0):
			max_d = d
		elif d > cast_range.x + 1.0:
			break
		d += 0.5
	var dist := lerpf(cast_range.x, max_d, power)
	var side := fwd.orthogonal() * _rng.randf_range(-0.6, 0.6)
	var land := origin + fwd * dist + side
	if not river.is_water(land, 0.6):
		land = origin + fwd * dist
	_cast_from = _rod_tip()
	_cast_to = Vector3(land.x, river.water_level, land.y)


func _roll_wait() -> float:
	return _rng.randf_range(wait_time.x, wait_time.y) * bite_factor()


## Hệ số thời gian chờ (nhỏ = cá ăn mạnh) theo giờ và thời tiết.
func bite_factor() -> float:
	var h := day_night.time_of_day if day_night != null else 17.0
	var k := 1.0
	if h >= 5.0 and h < 8.5:
		k = 0.55            # sáng sớm
	elif h >= 16.0 and h < 19.0:
		k = 0.6             # chiều muộn
	elif h >= 11.0 and h < 14.0:
		k = 1.4             # trưa nắng
	elif h >= 21.0 or h < 4.0:
		k = 1.9             # đêm khuya
	if weather != null:
		match weather.kind:
			"drizzle": k *= 0.7
			"cloudy": k *= 0.85
	return k


func _appetite_text() -> String:
	var k := bite_factor()
	if k < 0.7:
		return "Cá đang ăn mạnh"
	if k < 1.2:
		return "Cá ăn vừa"
	return "Cá ăn kém"


# --- Mỗi khung hình --------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _toast_timer > 0.0:
		_toast_timer -= delta
	if state == State.OFF:
		_update_prompt()
		return
	# Giông kéo tới: báo rồi tự thu cần
	if weather != null and weather.kind == "storm" and _leave_timer < 0.0:
		_show_toast("Giông kéo tới rồi, thu cần về thôi!", 2.0)
		_drop_fish()
		_enter_ready()
		_leave_timer = 1.8
	if _leave_timer >= 0.0:
		_leave_timer -= delta
		if _leave_timer < 0.0:
			stop()
			return
	_body.scale = Vector3(1.0, 1.0 + 0.012 * sin(_time * 1.6), 1.0)   # thở nhẹ
	match state:
		State.READY: _do_ready()
		State.CHARGE: _do_charge(delta)
		State.CAST: _do_cast(delta)
		State.WAIT: _do_wait(delta)
		State.NIBBLE: _do_nibble(delta)
		State.BITE: _do_bite(delta)
		State.REEL: _do_reel(delta)
		State.CAUGHT: _do_caught(delta)
		State.LOST: _do_lost(delta)
	_draw_line()
	_update_prompt()
	_update_log()


func _do_ready() -> void:
	_set_rod(deg_to_rad(38.0 + 2.0 * sin(_time * 1.3)), 0.05)
	_bob_pos = _rod_tip() + Vector3(0, -0.55 + 0.03 * sin(_time * 2.0), 0)


func _do_charge(delta: float) -> void:
	if not _freeze:
		_t += delta
		_power = pingpong(_t * 2.0 / charge_period, 1.0)
	_set_rod(deg_to_rad(lerpf(40.0, 110.0, _power)), 0.08 + 0.15 * _power)
	_bob_pos = _rod_tip() + Vector3(0, -0.5, 0)
	_show_meter("Lực quăng", _power, Palette.FLOWER_YELLOW, "", -1.0)
	if not _freeze and not _debug_hold and not Input.is_action_pressed("fish_reel"):
		_cast(maxf(_power, 0.12))   # lỡ mất sự kiện thả phím


func _do_cast(delta: float) -> void:
	_t = minf(_t + delta / cast_time, 1.0)
	var swing := clampf(_t / 0.3, 0.0, 1.0)
	var elev := lerpf(lerpf(40.0, 110.0, _power), 12.0, ease(swing, 0.4))
	if _t > 0.3:
		elev = lerpf(12.0, 32.0, (_t - 0.3) / 0.7)
	_set_rod(deg_to_rad(elev), 0.25 * (1.0 - swing) - 0.1 * swing * (1.0 - _t))
	var arc := 1.2 + _cast_from.distance_to(_cast_to) * 0.25
	var p := _cast_from.lerp(_cast_to, _t)
	p.y += arc * 4.0 * _t * (1.0 - _t)
	_bob_pos = p
	_meter_panel.visible = false
	if _t >= 1.0:
		river.splash(_cast_to)
		state = State.WAIT
		_wait_timer = _roll_wait()
		_bob_pos = _cast_to


func _bob_float() -> Vector3:
	return Vector3(_cast_to.x, river.water_level + 0.012 * sin(_time * 2.2), _cast_to.z)


func _do_wait(delta: float) -> void:
	_set_rod(deg_to_rad(32.0), 0.04 + 0.01 * sin(_time))
	_bob_pos = _bob_float()
	if _fish < 0:
		if _freeze:
			return
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			var idx := river.fish_near(_cast_to, lure_radius)
			if idx >= 0:
				_take_fish(idx)
			else:
				_wait_timer = 2.0
		return
	# Cá đang bơi tới mồi
	var target := _mouth_target()
	var step := approach_speed * delta
	var to := target - _fish_pos
	if to.length() <= step + 0.02:
		_fish_pos = target
		state = State.NIBBLE
		_nibbles = _rng.randi_range(nibble_count.x, nibble_count.y)
		_t = _rng.randf_range(0.4, 1.0)
	else:
		_fish_pos += to.normalized() * step
		_fish_yaw = lerp_angle(_fish_yaw, atan2(to.x, to.z), minf(delta * 4.0, 1.0))
	river.pose_fish(_fish, _fish_pos, _fish_yaw)


## Chỗ miệng cá dừng: ngay dưới phao, phía con cá bơi tới.
func _mouth_target() -> Vector3:
	var d := Vector2(_fish_pos.x - _cast_to.x, _fish_pos.z - _cast_to.z)
	if d.length() < 0.01:
		d = Vector2(0, 1)
	d = d.normalized() * 0.3
	return Vector3(_cast_to.x + d.x, river.water_level - 0.14, _cast_to.z + d.y)


func _do_nibble(delta: float) -> void:
	_set_rod(deg_to_rad(32.0), 0.05 + 0.04 * _dip)
	_dip = maxf(_dip - delta * 5.0, 0.0)
	_bob_pos = _bob_float() + Vector3(0, -0.06 * _dip, 0)
	var nose := _fish_pos + Vector3(sin(_fish_yaw), 0, cos(_fish_yaw)) * 0.04 * _dip
	river.pose_fish(_fish, nose, _fish_yaw + 0.1 * sin(_time * 9.0), -0.15 * _dip)
	if _freeze:
		return
	_t -= delta
	if _t <= 0.0:
		if _nibbles > 0:
			_nibbles -= 1
			_dip = 1.0
			_t = _rng.randf_range(0.6, 1.3)
		else:
			state = State.BITE
			_t = bite_window * float(SPECIES[_fish_kind].window)


func _do_bite(delta: float) -> void:
	_set_rod(deg_to_rad(30.0), 0.12)
	# Phao bị kéo chìm, trôi theo hướng cá
	var away := Vector3(-sin(_fish_yaw), 0, -cos(_fish_yaw))
	_bob_pos = _bob_pos.lerp(Vector3(_bob_pos.x, river.water_level - 0.13, _bob_pos.z), minf(delta * 10.0, 1.0))
	if not _freeze:
		_bob_pos += away * 0.25 * delta
		_fish_pos += away * 0.25 * delta
		_t -= delta
	river.pose_fish(_fish, _fish_pos, _fish_yaw + 0.2 * sin(_time * 12.0), 0.1)
	if not _freeze and _t <= 0.0:
		_drop_fish()
		_lose("Cá đớp mất mồi rồi! Quăng lại nhé.")


## Giật cần đúng lúc: bắt đầu kéo cá.
func _hook() -> void:
	state = State.REEL
	var sp: Dictionary = SPECIES[_fish_kind]
	var tz := clampf((_fish_size - 1.0) / 0.7, 0.0, 1.0)
	var kg: Vector2 = sp.kg
	_fish_kg = lerpf(kg.x, kg.y, pow(tz, 1.4)) * _rng.randf_range(0.9, 1.1)
	_fish_cm = float(sp.len) * pow(_fish_kg, 1.0 / 3.0)
	_strength = float(sp.pull) * (0.75 + 0.35 * tz)
	_hook_pos = Vector3(_bob_pos.x, river.water_level, _bob_pos.z)
	_tension = 0.35
	_progress = 0.22
	_slack = 0.0
	_surge = 0.0
	_surge_timer = _rng.randf_range(0.8, 2.0)
	_side = -1.0 if _rng.randf() < 0.5 else 1.0
	river.splash(_hook_pos)
	_show_toast("Dính rồi! %s." % sp.name, 1.2)


func _do_reel(delta: float) -> void:
	var reeling := _debug_hold or Input.is_action_pressed("fish_reel")
	var s := _strength
	if not _freeze:
		# Cá vùng chạy từng đợt
		_surge_timer -= delta
		if _surge_timer <= 0.0:
			if _surge > 0.5:
				_surge = 0.0
				_surge_timer = _rng.randf_range(1.0, 2.6) / (0.6 + s)
			else:
				_surge = 1.0
				_surge_timer = _rng.randf_range(0.6, 1.3) * (0.6 + s)
				_side = -_side
		var u := _surge
		if reeling:
			_tension += (tension_rise * (0.6 + 0.6 * s) + u * 0.6 * s) * delta
			_progress += reel_speed * (1.0 - 0.5 * u) / (0.65 + 0.35 * s) * delta
		else:
			_tension += (u * 0.35 * s - tension_fall) * delta
			_progress -= (0.015 + 0.025 * s + u * 0.04 * s) * delta
		_tension = maxf(_tension, 0.0)
		_slack = _slack + delta if _tension < 0.1 else 0.0
		if _tension >= 1.0:
			_drop_fish()
			_lose("Phựt! Dây căng quá nên đứt mất rồi.")
			return
		if _progress <= 0.0 or _slack > slack_escape:
			_drop_fish()
			_lose("Dây chùng, cá sổng mất rồi!")
			return
		if _progress >= 1.0:
			_land_fish()
			return
	# Cá giãy: càng gần bờ càng ít lượn; phao bị lôi theo
	var node: Node3D = _spots[_spot].node
	var face := float(_spots[_spot].landing.face)
	var fwd := Vector3(sin(face), 0, cos(face))
	var near := node.global_position + fwd * 1.3
	near.y = river.water_level
	var base := _hook_pos.lerp(near, clampf(_progress, 0.0, 1.0))
	var lat := fwd.cross(Vector3.UP) * (_side * (0.4 + 1.2 * _surge) + 0.3 * sin(_time * 2.3)) * (1.0 - _progress) * s
	var p := base + lat
	if not river.is_water(Vector2(p.x, p.z), 0.4):
		p = base
	_fish_pos = _fish_pos.lerp(Vector3(p.x, river.water_level - 0.07, p.z), minf(delta * 3.0, 1.0))
	var away := _fish_pos - node.global_position
	_fish_yaw = atan2(away.x, away.z) + 0.5 * sin(_time * (9.0 + 8.0 * _surge))
	river.pose_fish(_fish, _fish_pos, _fish_yaw, 0.0, 0.3 * sin(_time * 7.0))
	_bob_pos = Vector3(_fish_pos.x, river.water_level - 0.02, _fish_pos.z)
	_splash_timer -= delta
	if _splash_timer <= 0.0:
		_splash_timer = 0.3 if _surge > 0.5 else 0.6
		river.splash(_fish_pos)
	# Cần ngả theo lực dây, rung khi cá vùng
	_set_rod(deg_to_rad(lerpf(45.0, 26.0, _tension)),
			0.1 + 0.55 * _tension + 0.05 * _surge * sin(_time * 30.0))
	var col := Palette.LILY.lerp(Palette.FLOWER_YELLOW, smoothstep(0.4, 0.7, _tension)).lerp(Palette.FLAG_RED, smoothstep(0.7, 0.9, _tension))
	_show_meter("Độ căng dây", _tension, col, "Kéo vào bờ", _progress)


## Cá lên bờ: bay một vòng vào giỏ, ghi sổ, hiện thẻ.
func _land_fish() -> void:
	state = State.CAUGHT
	_t = 0.0
	_leap_from = _fish_pos
	_meter_panel.visible = false
	var sp: Dictionary = SPECIES[_fish_kind]
	var name_s: String = sp.name
	var rec: Dictionary = _log.get(name_s, {"count": 0, "best": 0.0})
	var record := _fish_kg > float(rec.best)
	rec.count = int(rec.count) + 1
	rec.best = maxf(float(rec.best), _fish_kg)
	_log[name_s] = rec
	_total += 1
	_card_title.text = name_s
	var lines: Array[String] = ["%s  ·  %d cm" % [_kg(_fish_kg), roundi(_fish_cm)]]
	if record and int(rec.count) > 1:
		lines.append("Con %s nặng nhất từ trước tới giờ!" % name_s.to_lower())
	elif int(rec.count) == 1:
		lines.append("Con %s đầu tiên!" % name_s.to_lower())
	lines.append("Giỏ đã có %d con" % _total)
	_card_body.text = "\n".join(lines)
	_card.visible = true
	_card.reset_size()
	_card.offset_left = -_card.size.x * 0.5
	_card.offset_right = _card.size.x * 0.5
	river.splash(_fish_pos)


func _do_caught(delta: float) -> void:
	var node: Node3D = _spots[_spot].node
	var basket := node.global_transform * Vector3(-0.55, 0.35, 0.05)
	if not _freeze:
		_t += delta
	var k := clampf(_t / 0.9, 0.0, 1.0)
	if _freeze:
		k = 0.45
	_set_rod(deg_to_rad(lerpf(30.0, 70.0, sin(k * PI))), 0.2 * (1.0 - k))
	if _fish >= 0:
		var p := _leap_from.lerp(basket, k)
		p.y += 1.6 * 4.0 * k * (1.0 - k)
		river.pose_fish(_fish, p, _fish_yaw + k * 5.0, -1.2 + k * 0.8, 0.4 * sin(_time * 20.0))
		_bob_pos = p + Vector3(0, 0.12, 0)
		if k >= 1.0:
			river.respawn_fish(_fish, basket)
			_fish = -1
	else:
		_do_ready()
	if not _freeze and _t > 3.2:
		_enter_ready()
		_card.visible = false


func _lose(msg: String) -> void:
	state = State.LOST
	_t = 1.6
	_meter_panel.visible = false
	_show_toast(msg, 1.8)


func _do_lost(delta: float) -> void:
	_set_rod(deg_to_rad(40.0), 0.0)
	_bob_pos = _bob_pos.lerp(_rod_tip() + Vector3(0, -0.55, 0), minf(delta * 3.0, 1.0))
	_t -= delta
	if _t <= 0.0:
		_enter_ready()


func _take_fish(idx: int) -> void:
	var info := river.grab_fish(idx)
	_fish = idx
	_fish_pos = info.pos
	_fish_yaw = info.yaw
	_fish_kind = clampi(int(info.kind), 0, SPECIES.size() - 1)
	_fish_size = info.size


## Trả con cá đang giữ về sông (bơi đi chỗ khác).
func _drop_fish() -> void:
	if _fish >= 0 and river != null:
		var node: Node3D = _spots[_spot].node if _spot >= 0 else null
		river.release_fish(_fish, node.global_position if node != null else _fish_pos)
	_fish = -1


# --- Dây câu ---------------------------------------------------------------------------

func _draw_line() -> void:
	_bobber.global_position = _bob_pos
	var a := _rod_tip()
	var b := _bob_pos + Vector3(0, 0.13, 0)
	var dist := a.distance_to(b)
	var sag := 0.0
	match state:
		State.READY, State.CHARGE, State.LOST:
			sag = 0.0
		State.CAST:
			sag = 0.05 * dist
		State.REEL:
			sag = (1.0 - _tension) * 0.12 * dist
		_:
			sag = 0.1 * dist
	var mid := (a + b) * 0.5 + Vector3(0, -sag, 0)
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _line_mat)
	for i in 13:
		var t := i / 12.0
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		p.y = maxf(p.y, river.water_level - 0.15)
		_line_mesh.surface_add_vertex(p)
	_line_mesh.surface_end()


# --- Giao diện -------------------------------------------------------------------------

static func _kg(w: float) -> String:
	return ("%.2f kg" % w).replace(".", ",")


func _show_toast(text: String, seconds: float) -> void:
	_toast = text
	_toast_timer = seconds


func _update_prompt() -> void:
	var text := ""
	if _toast_timer > 0.0:
		text = _toast
	else:
		match state:
			State.READY: text = "Giữ chuột trái / Space để lấy đà, thả ra để quăng cần"
			State.CHARGE: text = "Thả ra để quăng!"
			State.CAST: text = ""
			State.WAIT: text = "Chờ cá cắn câu…" if _fish < 0 else "Có cá đang bơi lại gần phao…"
			State.NIBBLE: text = "Phao nhấp… chờ phao chìm hẳn!"
			State.BITE: text = "Phao chìm! Giật cần ngay!"
			State.REEL: text = "Giữ để cuộn dây — thả ra khi dây căng đỏ"
			State.CAUGHT: text = "Bấm để câu tiếp"
	_prompt.text = text
	_prompt_panel.visible = text != ""
	_prompt_panel.reset_size()
	_prompt_panel.offset_left = -_prompt_panel.size.x * 0.5
	_prompt_panel.offset_right = _prompt_panel.size.x * 0.5
	var urgent := state == State.BITE and _toast_timer <= 0.0
	_prompt.add_theme_color_override("font_color", Palette.FLOWER_YELLOW if urgent else Palette.HUD_TEXT)


func _show_meter(title_a: String, a: float, col_a: Color, title_b: String, b: float) -> void:
	_meter_panel.visible = true
	_meter_a.text = title_a
	_bar_a.color = col_a
	_bar_a.size = Vector2(_bar_a_bg.size.x * clampf(a, 0.0, 1.0), _bar_a_bg.size.y)
	_danger.visible = title_b != ""
	_danger.position = Vector2(_bar_a_bg.size.x * 0.85, 0)
	var show_b := b >= 0.0
	_meter_b.visible = show_b
	_bar_b_bg.visible = show_b
	if show_b:
		_meter_b.text = title_b
		_bar_b.size = Vector2(_bar_b_bg.size.x * clampf(b, 0.0, 1.0), _bar_b_bg.size.y)


func _update_log() -> void:
	_log_panel.visible = hud == null or hud.visible
	var lines: Array[String] = [_appetite_text()]
	if _log.is_empty():
		lines.append("Giỏ còn trống")
	else:
		for name_s: String in _log:
			var rec: Dictionary = _log[name_s]
			lines.append("%s × %d  ·  to nhất %s" % [name_s, int(rec.count), _kg(float(rec.best))])
	_log_label.text = "\n".join(lines)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 6
	add_child(_ui)
	var regular := Hud.font(false)
	var semibold := Hud.font(true)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# Lời nhắc giữa phía dưới (cùng chỗ gợi ý cửa của HUD)
	_prompt_panel = _panel()
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_panel.offset_bottom = -80
	root.add_child(_prompt_panel)
	_prompt = _label(semibold, 19, Palette.HUD_TEXT)
	_prompt_panel.add_child(_prompt)

	# Thanh đo: lực quăng / độ căng dây + quãng kéo vào bờ
	_meter_panel = _panel()
	_meter_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_meter_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_meter_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_meter_panel.offset_bottom = -138
	_meter_panel.offset_left = -190
	_meter_panel.offset_right = 190
	root.add_child(_meter_panel)
	var mbox := VBoxContainer.new()
	mbox.add_theme_constant_override("separation", 4)
	_meter_panel.add_child(mbox)
	_meter_a = _label(regular, 15, Palette.HUD_SUBTEXT)
	mbox.add_child(_meter_a)
	var pa := _bar()
	_bar_a_bg = pa[0]
	_bar_a = pa[1]
	mbox.add_child(_bar_a_bg)
	_danger = ColorRect.new()
	_danger.color = Color(Palette.HUD_TEXT, 0.8)
	_danger.size = Vector2(2, 16)
	_danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_a_bg.add_child(_danger)
	_meter_b = _label(regular, 15, Palette.HUD_SUBTEXT)
	mbox.add_child(_meter_b)
	var pb := _bar()
	_bar_b_bg = pb[0]
	_bar_b = pb[1]
	_bar_b.color = Palette.WATER_LIGHT
	mbox.add_child(_bar_b_bg)
	_meter_panel.visible = false

	# Thẻ cá vừa câu được (giữa phía trên)
	_card = _panel()
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 110
	root.add_child(_card)
	var cbox := VBoxContainer.new()
	cbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(cbox)
	_card_title = _label(semibold, 30, Palette.FLOWER_YELLOW)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(_card_title)
	_card_body = _label(regular, 17, Palette.HUD_TEXT)
	_card_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(_card_body)
	_card.visible = false

	# Sổ câu (góc trên phải)
	_log_panel = _panel()
	_log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_log_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_log_panel.offset_right = -20
	_log_panel.offset_top = 18
	_log_panel.custom_minimum_size.x = 300
	root.add_child(_log_panel)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 2)
	_log_panel.add_child(lbox)
	lbox.add_child(_label(semibold, 22, Palette.HUD_TEXT))
	(lbox.get_child(0) as Label).text = "Giỏ cá"
	_log_label = _label(regular, 15, Palette.HUD_SUBTEXT)
	lbox.add_child(_log_label)
	_log_panel.visible = false


func _bar() -> Array[ColorRect]:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.35)
	bg.custom_minimum_size = Vector2(340, 16)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size = Vector2(0, 16)
	bg.add_child(fill)
	return [bg, fill]


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(f: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


# --- Công cụ chụp ảnh ------------------------------------------------------------------

## Dựng sẵn một trạng thái để chụp: charge | wait | nibble | bite | reel | caught.
func debug_state(name_s: String) -> void:
	if state == State.OFF:
		return
	_freeze = true
	if name_s == "charge":
		state = State.CHARGE
		_power = 0.7
		_debug_hold = true
		return
	_cast(0.65)
	_bob_pos = _cast_to
	state = State.WAIT
	if name_s == "wait":
		return
	var idx := river.fish_near(_cast_to, 80.0)
	if idx < 0:
		return
	_take_fish(idx)
	_fish_pos = _mouth_target()
	_fish_yaw = atan2(_cast_to.x - _fish_pos.x, _cast_to.z - _fish_pos.z)
	match name_s:
		"nibble":
			state = State.NIBBLE
			_dip = 0.8
		"bite":
			state = State.BITE
			_bob_pos.y = river.water_level - 0.12
		"reel", "caught":
			_hook()
			_progress = 0.45
			_tension = 0.72
			_surge = 1.0
			state = State.REEL
			_toast_timer = 0.0
			if name_s == "caught":
				_fish_pos = _hook_pos.lerp(_spots[_spot].node.global_position, 0.6)
				_fish_pos.y = river.water_level
				_land_fish()
