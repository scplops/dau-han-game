class_name FirstPerson
extends CharacterBody3D
## Nhập vai góc nhìn thứ nhất (mục 18). Phím V bật / tắt; bật thì người chơi đứng ở chỗ
## tâm camera ngắm cảnh đang nhìn, tắt thì camera ngắm cảnh quay về chỗ người chơi đứng.
## - Chuột: nhìn quanh (chuột bị giữ giữa màn hình). WASD: đi, Shift: chạy, Space: nhảy.
## - Tâm ngắm giữa màn hình: nhìn vào cửa / chỗ câu / quả bóng / người trong tầm với
##   thì hiện gợi ý; E (hoặc chuột trái) để làm: vào nhà, ngồi câu, sút bóng, xem tin.
## - Đi vào quả bóng thì dẫn bóng theo chân.
## Va chạm: lấy thẳng từ các mesh tĩnh đã dựng (tường, cột, thân cây, mặt đất, bờ đê) thành
## ConcavePolygonShape3D ở lớp `SOLID_LAYER`, chỉ dựng lần đầu bật nhập vai.

const SOLID_LAYER := 4

@export var outdoor_rig: CameraRig
@export var house_entry: HouseEntry
@export var fishing: Fishing
@export var football: Football
@export var villagers: Villagers
@export var hud: Hud
@export var world: Node3D

@export_group("Di chuyển")
@export var walk_speed: float = 2.4
@export var run_speed: float = 5.2
@export var jump_speed: float = 4.2
@export var gravity: float = 11.0
@export var acceleration: float = 12.0
## Bậc cao nhất tự bước lên được (thềm nhà, bậc đá).
@export var step_height: float = 0.35
@export var eye_height: float = 1.6
@export var mouse_sensitivity: float = 0.0025
@export var fov: float = 72.0

@export_group("Tương tác")
@export var reach: float = 3.2
@export var dribble_distance: float = 0.55

var active: bool = false
var camera: Camera3D
var _pitch: float = 0.0
var _colliders_built: bool = false
var _suspended: String = ""        # "house" | "fish" khi đang tạm nhường camera
var _look_target: Object = null
var _crosshair: Control
var _bob: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << (SOLID_LAYER - 1)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	shape.shape = cap
	shape.position.y = 0.875
	add_child(shape)
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.05
	camera.far = 1200.0
	camera.position.y = eye_height
	add_child(camera)
	_build_crosshair()
	visible = false
	set_physics_process(false)
	if house_entry != null:
		house_entry.inside_changed.connect(_on_inside_changed)
	if fishing != null:
		fishing.stopped.connect(_on_fishing_stopped)


# --- Bật / tắt ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_first_person"):
		if _suspended != "":
			return
		if active:
			exit()
		elif not (house_entry != null and house_entry.inside) and not (fishing != null and fishing.state != Fishing.State.OFF):
			enter()
		get_viewport().set_input_as_handled()
		return
	if not active or _suspended != "":
		return
	if event.is_action_pressed("exit_interior"):
		exit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotation.y -= mm.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, -1.45, 1.45)
		camera.rotation.x = _pitch
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_act()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				_act()
		# Chuột không đi xuống camera ngắm cảnh / dân làng / cửa khi đang nhập vai
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("follow_npc") or event.is_action_pressed("toggle_projection"):
		get_viewport().set_input_as_handled()


## Bắt đầu nhập vai ở chỗ tâm camera ngắm cảnh đang nhìn.
func enter() -> void:
	if not _colliders_built:
		_build_colliders()
	var p := outdoor_rig.global_position if outdoor_rig != null else Vector3.ZERO
	global_position = _ground_spawn(p)
	rotation = Vector3(0, deg_to_rad(outdoor_rig.yaw_deg) if outdoor_rig != null else 0.0, 0)
	_pitch = -0.1
	camera.rotation.x = _pitch
	velocity = Vector3.ZERO
	active = true
	_resume()


## Thôi nhập vai: camera ngắm cảnh quay về chỗ đang đứng.
func exit() -> void:
	active = false
	_suspended = ""
	set_physics_process(false)
	visible = false
	_crosshair.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if house_entry != null:
		house_entry.locked = false
	if outdoor_rig != null:
		outdoor_rig.active = true
		outdoor_rig.set_focus(Vector3(global_position.x, 0.0, global_position.z))
		outdoor_rig.yaw_deg = wrapf(rad_to_deg(rotation.y), -180.0, 180.0)
		outdoor_rig.distance = 24.0
		outdoor_rig.camera.make_current()
	if hud != null:
		hud.set_first_person(false)
		hud.set_hint("")


## Lấy lại camera, chuột, khoá vào nhà bằng chuột (sau khi vào nhà / câu cá xong).
func _resume() -> void:
	_suspended = ""
	visible = true
	set_physics_process(true)
	camera.make_current()
	_crosshair.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if outdoor_rig != null:
		outdoor_rig.active = false
	if house_entry != null:
		house_entry.locked = true
	if hud != null:
		hud.set_first_person(true)


func _on_inside_changed(inside: bool) -> void:
	if not active:
		return
	if not inside and _suspended == "house":
		_resume.call_deferred()


func _on_fishing_stopped() -> void:
	if active and _suspended == "fish":
		_resume.call_deferred()


# --- Mỗi bước vật lý --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active or _suspended != "":
		return
	var input := Input.get_vector("cam_left", "cam_right", "cam_forward", "cam_back")
	var wish := (global_transform.basis * Vector3(input.x, 0, input.y))
	wish.y = 0.0
	wish = wish.normalized() * (run_speed if Input.is_action_pressed("fp_run") else walk_speed) * minf(input.length(), 1.0)
	var t := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, wish.x, t)
	velocity.z = lerpf(velocity.z, wish.z, t)
	if is_on_floor():
		if Input.is_action_just_pressed("fp_jump"):
			velocity.y = jump_speed
	else:
		velocity.y -= gravity * delta
	var before := global_position
	_step_up(delta)
	move_and_slide()
	# Rơi khỏi thế giới (lỗ trên mesh) thì đưa lên lại mặt đất
	if global_position.y < -5.0:
		global_position = _ground_spawn(before)
		velocity = Vector3.ZERO
	# Nhún nhẹ theo bước chân
	var hs := Vector2(velocity.x, velocity.z).length()
	_bob += hs * delta * 2.2
	camera.position.y = eye_height + (sin(_bob * PI) * 0.025 * clampf(hs / walk_speed, 0.0, 1.5) if is_on_floor() else 0.0)
	# Camera ngắm cảnh, mưa đi theo người chơi
	if outdoor_rig != null:
		outdoor_rig.global_position = Vector3(global_position.x, 0.0, global_position.z)
	_dribble(hs)
	_update_look()


## Bước lên bậc thấp: bị chặn ngang mà nâng lên `step_height` thì đi tiếp được → nâng lên.
func _step_up(delta: float) -> void:
	if not is_on_floor():
		return
	var motion := Vector3(velocity.x, 0, velocity.z) * delta
	if motion.length() < 0.001:
		return
	if not test_move(global_transform, motion):
		return
	var up := global_transform.translated(Vector3(0, step_height, 0))
	if test_move(global_transform, Vector3(0, step_height, 0)) or test_move(up, motion):
		return
	global_position.y += step_height
	apply_floor_snap()


# --- Tương tác ---------------------------------------------------------------------------

## Vật trong tầm với ở tâm màn hình: vùng bấm (cửa, chỗ câu, bóng) hoặc dân làng.
func _update_look() -> void:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var mask := (1 << (HouseEntry.CLICK_LAYER - 1)) | (1 << (Villager.CLICK_LAYER - 1)) | (1 << (SOLID_LAYER - 1))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, mask)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Object = null
	var hint := ""
	if not hit.is_empty():
		var col := hit.get("collider") as Node
		if col != null and col.has_meta("villager"):
			target = col.get_meta("villager")
			hint = "E: xem tin  ·  " + (target as Villager).display_name
		elif col != null and col.has_meta("hint"):
			target = col
			hint = "E: " + str(col.get_meta("hint")).split("  ·  ")[0]
			if col.has_meta("spec"):
				hint = "E: vào  ·  " + str((col.get_meta("spec") as Dictionary).get("name", ""))
			elif col.get_meta("hint") is String and str(col.get_meta("hint")).begins_with("Ngồi câu"):
				hint = "E: ngồi câu cá"
			elif football != null and col.get_parent() == football.ball_node():
				hint = "E / chuột trái: sút bóng"
	_look_target = target
	if hud != null:
		hud.set_hint(hint)


func _act() -> void:
	if _look_target == null:
		return
	if _look_target is Villager:
		if villagers != null:
			villagers.select_villager(_look_target as Villager)
		return
	var body := _look_target as StaticBody3D
	if body == null:
		return
	if football != null and body.get_parent() == football.ball_node():
		var d := -camera.global_transform.basis.z
		football.kick_from_player(Vector3(d.x, 0, d.z), clampf(d.y + 0.25, 0.05, 0.6))
		return
	if body.has_meta("spec") and house_entry != null:
		_suspend("house")
		house_entry.locked = false
		house_entry.enter_house(false, body)
	elif body.has_meta("activate"):
		if fishing != null and str(body.get_meta("hint", "")).begins_with("Ngồi câu"):
			_suspend("fish")
			# Câu cá dùng camera ngắm cảnh (đặt sau lưng người câu)
			if outdoor_rig != null:
				outdoor_rig.active = true
				outdoor_rig.camera.make_current()
		(body.get_meta("activate") as Callable).call()
		# Không vào được (vd. trời giông) thì nhập vai tiếp
		if _suspended == "fish" and fishing.state == Fishing.State.OFF:
			_resume()


## Nhường camera tạm thời (vào nhà, ngồi câu).
func _suspend(why: String) -> void:
	_suspended = why
	set_physics_process(false)
	visible = false
	_crosshair.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud != null:
		hud.set_hint("")
		hud.set_first_person(false)


## Đi vào bóng thì đẩy bóng theo hướng chân (dẫn bóng).
func _dribble(speed: float) -> void:
	if football == null or speed < 0.3:
		return
	var b := football.ball_position()
	var to := Vector2(b.x - global_position.x, b.z - global_position.z)
	if to.length() < dribble_distance and absf(b.y - global_position.y) < 0.6:
		var dir := Vector3(velocity.x, 0, velocity.z).normalized()
		if dir.dot(Vector3(to.x, 0, to.y).normalized()) > 0.2:
			football.nudge(dir, speed * 1.35)


# --- Va chạm từ mesh tĩnh ----------------------------------------------------------------

## Mesh tĩnh dưới `world` thành va chạm (bỏ lá cây có gió, mặt nước, dân làng, mây, bóng).
func _build_colliders() -> void:
	_colliders_built = true
	if world == null:
		return
	var t0 := Time.get_ticks_msec()
	var count := 0
	var tris := 0
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Villagers or n is Clouds or n.name == "Ball":
			continue
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or not (mi.mesh is ArrayMesh) or not mi.visible or mi.mesh.get_surface_count() == 0:
			continue
		if mi.material_override is ShaderMaterial or mi.mesh.surface_get_material(0) is ShaderMaterial:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "Solid"
		body.collision_layer = 1 << (SOLID_LAYER - 1)
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
		count += 1
		tris += (shape as ConcavePolygonShape3D).get_faces().size() / 3
	print("FirstPerson: %d khối va chạm, %d tam giác, %d ms" % [count, tris, Time.get_ticks_msec() - t0])


## Điểm đứng trên mặt đất gần `p` (dò tia từ trên xuống), lệch dần ra nếu đang kẹt trong tường.
func _ground_spawn(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	for ring in 12:
		for k in maxi(1, ring * 6):
			var a := TAU * k / maxf(ring * 6, 1)
			var q := p + Vector3(cos(a), 0, sin(a)) * ring * 1.2
			var ray := PhysicsRayQueryParameters3D.create(q + Vector3(0, 40, 0), q + Vector3(0, -10, 0), 1 << (SOLID_LAYER - 1))
			var hit := space.intersect_ray(ray)
			var y := float(hit.position.y) if not hit.is_empty() else 0.0
			# Chỉ nhận chỗ thấp (mặt đất), không đứng lên mái nhà / tán cây
			if y > 1.2:
				continue
			var xf := Transform3D(Basis(), Vector3(q.x, y + 0.05, q.z))
			if not test_move(xf, Vector3(0, 0.1, 0)):
				return xf.origin
	return Vector3(p.x, 0.1, p.z)


func _build_crosshair() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_crosshair)
	for sz: Vector2 in [Vector2(6, 6), Vector2(4, 4)]:
		var r := ColorRect.new()
		r.size = sz
		r.position = -sz * 0.5
		r.color = Color(0, 0, 0, 0.45) if sz.x > 5 else Palette.HUD_TEXT
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.add_child(r)
	_crosshair.visible = false
