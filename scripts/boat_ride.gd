class_name BoatRide
extends Node3D
## Đò trên sông (mục 24). Đò to, đi bộ lên được (nhập vai): ván cầu bắc lên đê, bậc gỗ hai bên
## mạn để từ dưới nước trèo lên, mui cao đứng thẳng được.
## - Nhập vai: đi lên đò (hoặc nhìn đò từ bờ "E: Lên đò" để bước lên ngay), tới đuôi đò nhìn
##   mái chèo "E: Cầm chèo" để chèo. Ngắm cảnh: bấm vào đò là chèo luôn.
## - Chèo: W / S chèo tới / lùi, A / D rẽ, Shift chèo nhanh. Camera đi theo sau đò:
##   chuột phải kéo để xoay, lăn chuột để zoom.
## - Đò chỉ đi trong lòng sông (chạm bờ thì khựng lại, trượt dọc bờ), trôi nhẹ theo dòng,
##   nhấp nhô, nghiêng khi rẽ, để lại gợn nước sau đuôi.
## - Thôi chèo: E / Esc — đứng lại ở đuôi đò (nhập vai) hoặc camera ngắm cảnh nhìn vào đò. Đò sát
##   bờ thì tự bắc ván lên đê; xa bờ thì lội xuống nước, trèo lên lại bằng bậc mạn.
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
## Tim đò cách mép nước tối thiểu (m) — nửa bề ngang đò + khoảng hở.
@export var bank_margin: float = 2.0
## Mạn đò cách mép nước dưới khoảng này (m) thì bắc ván lên đê khi neo.
@export var plank_reach: float = 2.6

@export_group("Camera")
@export var cam_distance: float = 13.0
@export var cam_height: float = 4.8
@export var cam_min: float = 6.0
@export var cam_max: float = 28.0

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
			var b := river.boat_nodes[i]
			var target := b.get_node_or_null("ClickTarget") as StaticBody3D
			if target != null:
				target.set_meta("activate", _on_hull.bind(i))
				target.add_to_group(HouseEntry.ACTIVATE_GROUP)
			var oar := b.get_node_or_null("OarTarget") as StaticBody3D
			if oar != null:
				oar.set_meta("activate", board.bind(i))
				oar.add_to_group(HouseEntry.ACTIVATE_GROUP)
			_add_lantern(b)
			deploy_plank(b)
		if day_night != null:
			day_night.refresh.call_deferred()


## Đèn bão treo ở đầu mui: tối thì sáng (nhóm `night_light`), đò neo hay đang chèo đều thấy.
func _add_lantern(b: Node3D) -> void:
	var lamp := Transform3D(Basis.IDENTITY, Vector3(-0.72, River.BOAT_DECK + 1.05, River.BOAT_CABIN.y + 0.2))   # treo lệch một bên, không chắn tầm nhìn từ trong mui
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
	light.omni_range = 8.0
	light.light_energy = 0.0
	light.set_meta("max_energy", 0.85)
	light.shadow_enabled = false
	light.position = lamp.origin + Vector3(0, 0.1, 0)
	light.add_to_group("night_light")
	b.add_child(light)


# --- Lên / xuống đò -----------------------------------------------------------------------

## Vùng bấm cả con đò: ngắm cảnh thì chèo luôn; nhập vai (đứng trên bờ) thì bước lên đò.
func _on_hull(i: int) -> void:
	if first_person != null and first_person.active:
		step_aboard(i)
	else:
		board(i)


## Con đò mà người nhập vai đang đứng trên sàn (−1 nếu không đứng trên đò nào): đứng đâu trên đò cũng nhấn E chèo được.
func boat_under(pos: Vector3) -> int:
	if river == null or active:
		return -1
	for i in river.boat_nodes.size():
		var lp := river.boat_nodes[i].to_local(pos)
		if absf(lp.x) < river.boat_beam * 0.5 + 0.1 and absf(lp.z) < 4.9 and lp.y > River.BOAT_DECK - 0.2 and lp.y < River.BOAT_DECK + 1.2:
			return i
	return -1


## Nhập vai: bước lên sàn đò chỗ khe mạn, nhìn về phía mũi.
func step_aboard(i: int) -> void:
	var b := river.boat_nodes[i]
	first_person.global_position = b.to_global(Vector3(0, River.BOAT_DECK + 0.05, River.BOAT_GAP_Z))
	first_person.rotation = Vector3(0, b.rotation.y + PI, 0)
	first_person.velocity = Vector3.ZERO


## Cầm chèo con đò thứ `i` (từ nhập vai hoặc từ camera ngắm cảnh).
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
	_set_plank(boat, null)
	(boat.get_node("Pole") as Node3D).visible = false
	for t: String in ["ClickTarget", "OarTarget", "FishSpot/FishTarget"]:
		var tn := boat.get_node_or_null(t) as Node3D
		if tn != null:
			tn.process_mode = Node.PROCESS_MODE_DISABLED
	_make_rower()
	active = true
	_cam.global_position = _cam_target()
	_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud != null:
		hud.set_boat(true)
	boarded.emit()


## Thôi chèo: đò neo tại chỗ (sát bờ thì bắc ván). Nhập vai thì đứng ở đuôi đò, nhìn về mũi.
func disembark() -> bool:
	if not active:
		return false
	_leave_boat()
	if _from_fp and first_person != null:
		first_person.global_position = boat.to_global(Vector3(0, River.BOAT_DECK + 0.05, -2.2))
		first_person.rotation = Vector3(0, _yaw + PI, 0)   # nhập vai nhìn về −z cục bộ
		first_person.velocity = Vector3.ZERO
		first_person._resume()
	else:
		if outdoor_rig != null:
			outdoor_rig.active = true
			outdoor_rig.set_focus(Vector3(boat.global_position.x, 0.0, boat.global_position.z))
			outdoor_rig.camera.make_current()
		if house_entry != null:
			house_entry.locked = false
	left.emit()
	return true


func _leave_boat() -> void:
	active = false
	_speed = 0.0
	_turn = 0.0
	if _rower != null:
		_rower.queue_free()
		_rower = null
	(boat.get_node("Pole") as Node3D).visible = true
	for t: String in ["ClickTarget", "OarTarget", "FishSpot/FishTarget"]:
		var tn := boat.get_node_or_null(t) as Node3D
		if tn != null:
			tn.process_mode = Node.PROCESS_MODE_INHERIT
	boat.rotation = Vector3(0, _yaw, 0)
	boat.position.y = river.water_level - 0.15
	deploy_plank(boat)
	if hud != null:
		hud.set_boat(false)
		hud.set_hint("")


## Bắc ván từ khe mạn lên mặt đê phía bờ gần hơn (nếu mạn đò đủ gần mép nước), không thì cất ván.
func deploy_plank(b: Node3D) -> void:
	var p := Vector2(b.global_position.x, b.global_position.z)
	var s := river.nearest_s(p)
	var smp := river.sample(s)
	var n: Vector2 = (smp[1] as Vector2).orthogonal()
	var lat := (p - (smp[0] as Vector2)).dot(n)
	var bank_dir := n * (signf(lat) if absf(lat) > 0.01 else 1.0)
	var bx := Vector2(b.global_transform.basis.x.x, b.global_transform.basis.x.z)
	var side := signf(bx.dot(bank_dir))
	# Khoảng hở từ mạn đò (chỗ khe) tới mép nước, đo theo hướng ra bờ
	var gap_pt := b.to_global(Vector3(side * river.boat_beam * 0.5, 0, River.BOAT_GAP_Z))
	var g2 := Vector2(gap_pt.x, gap_pt.z)
	var sg := river.nearest_s(g2)
	var sm2 := river.sample(sg)
	var gap := river.half_width(sg) - absf((g2 - (sm2[0] as Vector2)).dot((sm2[1] as Vector2).orthogonal()))
	if gap > plank_reach or absf(bx.dot(bank_dir)) < 0.5:
		_set_plank(b, null)
		return
	# Đầu ván đặt trên mặt đê (cách mép nước 2 m), đo theo hướng ngang của đò
	var run := (gap + 2.0) / absf(bx.dot(bank_dir))
	var end_world_y := river.bank_height(2.0) + 0.03
	var start := Vector3(side * river.boat_beam * 0.5, River.BOAT_DECK, River.BOAT_GAP_Z)
	var end := Vector3(side * (river.boat_beam * 0.5 + run), end_world_y - b.global_position.y, River.BOAT_GAP_Z)
	_set_plank(b, [start, end])


## Dựng lại tấm ván (mesh + va chạm) giữa hai điểm cục bộ của đò; `ends` = null thì cất ván.
func _set_plank(b: Node3D, ends: Variant) -> void:
	var old := b.get_node_or_null("Plank")
	if old != null:
		b.remove_child(old)
		old.queue_free()
	if ends == null:
		return
	var a: Vector3 = ends[0]
	var e: Vector3 = ends[1]
	var x_axis := (e - a).normalized()
	var z_axis := Vector3(0, 0, 1)
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	var plen := a.distance_to(e) + 0.2
	var center := (a + e) * 0.5
	var node := Node3D.new()
	node.name = "Plank"
	node.transform = Transform3D(basis, center)
	b.add_child(node)
	var mb := MeshBuilder.new(55, 0.04)
	mb.add_box(Vector3(plen, 0.06, 0.62), Palette.WOOD_LIGHT, Transform3D(Basis(), Vector3(0, -0.06, 0)))
	for k in 5:
		var x := -plen * 0.5 + 0.2 + k * (plen - 0.4) / 4.0
		mb.add_box(Vector3(0.05, 0.025, 0.62), Palette.WOOD, Transform3D(Basis(), Vector3(x, 0.0, 0)))
	node.add_child(mb.commit_instance("PlankMesh"))
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (FirstPerson.SOLID_LAYER - 1)
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(plen, 0.06, 0.62)
	cs.shape = bs
	cs.position = Vector3(0, -0.03, 0)
	body.add_child(cs)
	node.add_child(body)


## Người chèo đứng ở đuôi đò, cầm mái chèo.
func _make_rower() -> void:
	_rower = Villager.new()
	_rower.name = "Rower"
	_rower.role = "farmer"
	_rower.display_name = "Bạn"
	boat.add_child(_rower)
	_rower.build_person({"shirt": Palette.FARMER_SHIRT, "pants": Palette.FARMER_PANTS, "skin": Palette.FARMER_SKIN,
			"hat": "non", "scale": 1.0, "female": false, "prop": "none"})
	_rower.position = Vector3(0.1, River.BOAT_DECK, -2.4)
	_rower.work_anim = "idle"
	# Người chèo không bấm chọn được như dân làng
	for ch in _rower.get_children():
		if ch is StaticBody3D:
			ch.queue_free()
	# Mái chèo: khớp ở tầm tay bên phải, cán tre chéo xuống nước sau đuôi, lá chèo gỗ
	var mb := MeshBuilder.new(41, 0.03)
	mb.add_limb(Vector3(-0.15, 0.1, 0.45), Vector3(0, -2.0, -1.9), 0.032, 0.028, 5, Palette.BAMBOO_STEM)
	mb.add_box(Vector3(0.06, 0.24, 0.6), Palette.WOOD_LIGHT,
			Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0, -2.2, -2.1)))
	_oar = mb.commit_instance("Oar")
	_oar.position = Vector3(0.5, 1.0, -0.55)        # tựa trên đầu cọc chèo
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
		# Chỉ mất đà khi mũi (hoặc đuôi, lúc lùi) đâm vào bờ; chạy dọc bờ thì trượt tiếp
		var into := clampf(fwd.dot(n * signf(lat)) * signf(_speed), 0.0, 1.0)
		if into > 0.2:
			_speed *= 1.0 - 0.4 * into
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
		var stern := p - fwd * 4.6 * signf(_speed)
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
	var h := cam_height * (d / 13.0) + d * _cam_pitch
	return boat.global_position + Vector3(sin(a) * d, h, cos(a) * d)


func _update_camera(delta: float) -> void:
	var t := 1.0 - exp(-4.0 * delta)
	_cam.global_position = _cam.global_position.lerp(_cam_target(), t)
	_cam.look_at(boat.global_position + Vector3(0, 1.4, 0), Vector3.UP)


func _hint(text: String) -> void:
	if hud != null:
		hud.set_hint(text)
	_hint_timer = 2.2


## Hướng đò theo quy ước yaw của nhập vai (nhìn về −z) — cho bản đồ nhỏ vẽ mũi tên.
func heading_for_map() -> float:
	return _yaw + PI
