class_name BoatRide
extends Node3D
## Lên đò và chèo đò trên sông (mục 24).
## - Lên đò: đang nhập vai thì nhìn vào đò "E: lên đò"; đang ngắm cảnh thì bấm vào đò.
## - Chèo: W / S chèo tới / lùi, A / D rẽ, Shift chèo nhanh. Camera đi theo sau đò:
##   chuột phải kéo để xoay, lăn chuột để zoom.
## - Đò chỉ đi trong lòng sông (chạm bờ thì khựng lại, trượt dọc bờ), trôi nhẹ theo dòng,
##   nhấp nhô, nghiêng khi rẽ, để lại gợn nước sau đuôi.
## - Lên bờ: E / Esc khi đò đã sát bờ (gần bến thì lên đúng bến). Đò neo lại chỗ vừa rời.
## Người chèo là một hình người đứng ở đuôi đò, tay đẩy mái chèo theo nhịp.

signal boarded
signal left

@export var river: River
@export var first_person: FirstPerson
@export var outdoor_rig: CameraRig
@export var house_entry: HouseEntry
@export var hud: Hud
@export var day_night: DayNight

@export_group("Chèo")
@export var max_speed: float = 3.2
@export var fast_speed: float = 5.0
@export var reverse_speed: float = 1.4
@export var accel: float = 1.6
@export var drag: float = 0.55
## Rẽ (rad/s) khi đứng yên / khi đang đi nhanh.
@export var turn_still: float = 0.55
@export var turn_moving: float = 0.65
## Dòng sông trôi (m/s).
@export var current: float = 0.25
## Cách mép nước tối thiểu (m) — nửa bề ngang + mũi đò.
@export var bank_margin: float = 1.4
## Lên bờ được khi đò cách mép nước dưới khoảng này (m).
@export var dock_distance: float = 3.2
## Đò cách bến (cầu ván) dưới khoảng này thì lên thẳng bến.
@export var landing_distance: float = 9.0

@export_group("Camera")
@export var cam_distance: float = 8.0
@export var cam_height: float = 3.2
@export var cam_min: float = 4.0
@export var cam_max: float = 18.0

var active: bool = false
var boat: Node3D
var _index: int = -1
var _speed: float = 0.0
var _yaw: float = 0.0
var _turn: float = 0.0
var _time: float = 0.0
var _wake: float = 0.0
var _from_fp: bool = false
var _rower: Villager
var _oar: MeshInstance3D
var _stroke: float = 0.0
var _cam: Camera3D
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
var _orbiting: bool = false
var _hint_timer: float = 0.0


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.name = "BoatCam"
	_cam.fov = 55.0
	_cam.near = 0.1
	_cam.far = 1200.0
	_cam.top_level = true
	add_child(_cam)
	if river != null:
		for i in river.boat_nodes.size():
			var target := river.boat_nodes[i].get_node_or_null("ClickTarget") as StaticBody3D
			if target != null:
				target.set_meta("activate", board.bind(i))
				target.add_to_group(HouseEntry.ACTIVATE_GROUP)
			_add_lantern(river.boat_nodes[i])
		if day_night != null:
			day_night.refresh.call_deferred()


## Đèn bão treo ở đầu mui: tối thì sáng (nhóm `night_light`), đò neo hay đang chèo đều thấy.
func _add_lantern(b: Node3D) -> void:
	var lamp := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.42, 2.34))
	var mb := MeshBuilder.new(77, 0.02)
	mb.add_limb(Vector3(0, 0.4, -0.06), Vector3(0, 0.3, 0), 0.006, 0.006, 3, Palette.WINDOW_DARK, lamp)
	mb.add_prism(0.06, 0.06, 0.03, 6, Palette.WINDOW_DARK, lamp)
	mb.add_prism(0.048, 0.04, 0.15, 6, Palette.WINDOW_GLOW.lightened(0.2), lamp * Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)))
	mb.add_prism(0.045, 0.025, 0.06, 6, Palette.WINDOW_DARK, lamp * Transform3D(Basis.IDENTITY, Vector3(0, 0.18, 0)))
	var mi := mb.commit_instance("Lantern")
	b.add_child(mi)
	var light := OmniLight3D.new()
	light.name = "BoatLantern"
	light.light_color = Palette.WINDOW_GLOW
	light.omni_range = 6.0
	light.light_energy = 0.0
	light.set_meta("max_energy", 1.4)
	light.shadow_enabled = false
	light.position = lamp.origin + Vector3(0, 0.1, 0)
	light.add_to_group("night_light")
	b.add_child(light)


# --- Lên / xuống đò -----------------------------------------------------------------------

## Lên con đò thứ `i` (từ nhập vai hoặc từ camera ngắm cảnh).
func board(i: int) -> void:
	if active or river == null or i < 0 or i >= river.boat_nodes.size():
		return
	_index = i
	boat = river.boat_nodes[i]
	_yaw = boat.rotation.y
	_speed = 0.0
	_cam_yaw = 0.0
	_cam_pitch = 0.0
	_from_fp = first_person != null and first_person.active
	if _from_fp:
		first_person._suspend("boat")
	if outdoor_rig != null:
		outdoor_rig.active = false
	if house_entry != null:
		house_entry.locked = true
	(boat.get_node("Pole") as Node3D).visible = false
	(boat.get_node("ClickTarget") as Node3D).process_mode = Node.PROCESS_MODE_DISABLED
	_make_rower()
	active = true
	_cam.global_position = _cam_target()
	_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud != null:
		hud.set_boat(true)
	boarded.emit()


## Lên bờ ở chỗ gần nhất (bến nếu ở gần). Trả về false nếu đò còn xa bờ.
func disembark() -> bool:
	if not active:
		return false
	var p := Vector2(boat.global_position.x, boat.global_position.z)
	var s := river.nearest_s(p)
	var smp := river.sample(s)
	var c: Vector2 = smp[0]
	var n: Vector2 = (smp[1] as Vector2).orthogonal()
	var lat := (p - c).dot(n)
	var hw := river.half_width(s)
	var side := signf(lat) if absf(lat) > 0.01 else 1.0
	var ground := Vector3.ZERO
	var fp_yaw := 0.0
	var found := false
	# Gần bến thì lên thẳng cầu ván (cầu chìa ra sông nên không cần sát mép), nhìn vào bờ
	for l: Dictionary in river.landings:
		var spot: Vector3 = l.spot
		if Vector2(spot.x, spot.z).distance_to(p) < landing_distance:
			ground = spot + Vector3(0, 0.05, 0)
			fp_yaw = float(l.face)
			found = true
			break
	if not found:
		if hw - absf(lat) > dock_distance:
			_hint("Chèo vào sát bờ rồi mới lên được")
			return false
		var land := c + n * side * (hw + 2.6)             # mặt đê
		ground = Vector3(land.x, river.bank_height(2.6) + 0.05, land.y)
		# Nhập vai nhìn về −z cục bộ: quay mặt vào bờ (hướng n * side)
		fp_yaw = atan2(-n.x * side, -n.y * side)
	_leave_boat()
	if _from_fp and first_person != null:
		first_person.global_position = ground
		first_person.rotation = Vector3(0, fp_yaw, 0)
		first_person.velocity = Vector3.ZERO
		first_person._resume()
	else:
		if outdoor_rig != null:
			outdoor_rig.active = true
			outdoor_rig.set_focus(Vector3(ground.x, 0.0, ground.z))
			outdoor_rig.camera.make_current()
		if house_entry != null:
			house_entry.locked = false
	left.emit()
	return true


func _leave_boat() -> void:
	active = false
	_speed = 0.0
	if _rower != null:
		_rower.queue_free()
		_rower = null
	(boat.get_node("Pole") as Node3D).visible = true
	(boat.get_node("ClickTarget") as Node3D).process_mode = Node.PROCESS_MODE_INHERIT
	boat.rotation = Vector3(0, _yaw, 0)
	boat.position.y = river.water_level - 0.15
	if hud != null:
		hud.set_boat(false)
		hud.set_hint("")


## Người chèo đứng ở đuôi đò, cầm mái chèo.
func _make_rower() -> void:
	_rower = Villager.new()
	_rower.name = "Rower"
	_rower.role = "farmer"
	_rower.display_name = "Bạn"
	boat.add_child(_rower)
	_rower.build_person({"shirt": Palette.FARMER_SHIRT, "pants": Palette.FARMER_PANTS, "skin": Palette.FARMER_SKIN,
			"hat": "non", "scale": 1.0, "female": false, "prop": "none"})
	_rower.position = Vector3(0.0, 0.41, -1.05)
	_rower.work_anim = "idle"
	# Người chèo không bấm chọn được như dân làng
	for ch in _rower.get_children():
		if ch is StaticBody3D:
			ch.queue_free()
	# Mái chèo: khớp ở tầm tay bên phải, cán tre chéo xuống nước sau đuôi, lá chèo gỗ
	var mb := MeshBuilder.new(41, 0.03)
	mb.add_limb(Vector3(0, 0.25, 0.1), Vector3(0, -1.55, -1.1), 0.024, 0.02, 5, Palette.BAMBOO_STEM)
	mb.add_box(Vector3(0.05, 0.16, 0.42), Palette.WOOD_LIGHT,
			Transform3D(Basis(Vector3.RIGHT, 0.58), Vector3(0, -1.72, -1.28)))
	_oar = mb.commit_instance("Oar")
	_oar.position = Vector3(0.28, 1.0, 0.15)
	_rower.add_child(_oar)


# --- Điều khiển ----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("exit_interior"):
		disembark()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				cam_distance = clampf(cam_distance / 1.1, cam_min, cam_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				cam_distance = clampf(cam_distance * 1.1, cam_min, cam_max)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.006
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.004, -0.35, 0.6)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_first_person") or event.is_action_pressed("follow_npc") \
			or event.is_action_pressed("toggle_projection"):
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not active:
		return
	var input := Input.get_vector("cam_left", "cam_right", "cam_forward", "cam_back")
	step(delta, -input.y, -input.x, Input.is_action_pressed("fp_run"))


## Một bước chèo: `throttle` −1…1 (tới / lùi), `steer` −1…1 (trái / phải). Tách riêng để bài thử gọi.
func step(delta: float, throttle: float, steer: float, fast: bool) -> void:
	_time += delta
	var top := fast_speed if fast else max_speed
	var target := throttle * (top if throttle >= 0.0 else reverse_speed)
	if absf(throttle) > 0.05:
		_speed = move_toward(_speed, target, accel * delta)
	else:
		_speed = move_toward(_speed, 0.0, drag * delta)
	# Rẽ: chèo một bên là đò quay được cả khi đứng yên, đi nhanh thì rẽ ngọt hơn
	var rate := lerpf(turn_still, turn_moving, clampf(absf(_speed) / max_speed, 0.0, 1.0))
	_turn = lerpf(_turn, steer * rate * (1.0 if _speed >= -0.05 else -1.0), 1.0 - exp(-4.0 * delta))
	_yaw += _turn * delta
	var fwd := Vector2(sin(_yaw), cos(_yaw))
	var p := Vector2(boat.global_position.x, boat.global_position.z)
	# Dòng chảy theo tiếp tuyến sông
	var s := river.nearest_s(p)
	var smp := river.sample(s)
	var tan: Vector2 = smp[1]
	p += (fwd * _speed + tan * current) * delta
	# Giữ đò trong lòng sông: ra quá mép thì đẩy về, mất đà
	s = river.nearest_s(p)
	smp = river.sample(s)
	var c: Vector2 = smp[0]
	var n: Vector2 = (smp[1] as Vector2).orthogonal()
	var lat := (p - c).dot(n)
	# Hai đầu sông (chảy ra xa ngoài đồng): không chèo quá điểm cuối
	var along := (p - c).dot(smp[1] as Vector2)
	if (s < 2.0 and along < 0.0) or (s > river.length - 2.0 and along > 0.0):
		p -= (smp[1] as Vector2) * along
	var lim := river.half_width(s) - bank_margin
	if absf(lat) > lim:
		p -= n * (lat - signf(lat) * lim)
		_speed *= 0.6
		if absf(_speed) > 0.8:
			river.splash(Vector3(p.x, 0, p.y))
	# Nhấp nhô, nghiêng theo lúc rẽ, chúi mũi nhẹ khi tăng tốc
	var bob := 0.03 * sin(_time * 1.7) + 0.015 * sin(_time * 3.1)
	boat.global_position = Vector3(p.x, river.water_level - 0.15 + bob, p.y)
	boat.rotation = Vector3(-0.02 * _speed / max_speed + 0.015 * sin(_time * 1.3), _yaw, -_turn * 0.12 + 0.02 * sin(_time * 1.1))
	# Gợn nước sau đuôi khi đang chèo
	_wake -= delta * absf(_speed)
	if _wake <= 0.0 and absf(_speed) > 0.4:
		_wake = 2.2
		var stern := p - fwd * 1.8 * signf(_speed)
		river.splash(Vector3(stern.x, 0, stern.y))
	# Người chèo: đẩy mái chèo khi có lực chèo
	if _rower != null:
		var rowing := absf(throttle) > 0.05 or absf(steer) > 0.05
		_rower.work_anim = "work" if rowing else "idle"
		_rower.tick(delta, true)
		# Mái chèo quạt theo nhịp đẩy tay (rẽ thì ngả sang một bên)
		_stroke += delta * (2.2 if rowing else 0.0)
		_oar.rotation = Vector3(0.35 * sin(_stroke) * (1.0 if rowing else 0.2), steer * 0.35, 0.12)
	# Mưa, dân làng, bản đồ bám theo đò
	if outdoor_rig != null:
		outdoor_rig.global_position = Vector3(p.x, 0.0, p.y)
	_update_camera(delta)
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0 and hud != null:
			hud.set_hint("")


func _cam_target() -> Vector3:
	var a := _yaw + PI + _cam_yaw
	var d := cam_distance
	var h := cam_height * (d / 8.0) + d * _cam_pitch
	return boat.global_position + Vector3(sin(a) * d, h, cos(a) * d)


func _update_camera(delta: float) -> void:
	var t := 1.0 - exp(-4.0 * delta)
	_cam.global_position = _cam.global_position.lerp(_cam_target(), t)
	_cam.look_at(boat.global_position + Vector3(0, 0.8, 0), Vector3.UP)


func _hint(text: String) -> void:
	if hud != null:
		hud.set_hint(text)
	_hint_timer = 2.2


## Hướng đò theo quy ước yaw của nhập vai (nhìn về −z) — cho bản đồ nhỏ vẽ mũi tên.
func heading_for_map() -> float:
	return _yaw + PI
