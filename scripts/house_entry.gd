class_name HouseEntry
extends Node
## Vào / ra ngôi nhà, không cần nhân vật:
## - Ngoài sân: rê chuột vào cửa nhà → cửa sáng viền + gợi ý; bấm chuột trái hoặc nhấn E để vào.
## - Trong nhà: Esc, E, nút "Ra sân" trên HUD hoặc bấm vào ô cửa để ra.
## Chuyển cảnh mờ dần qua màu đen; chỉ đổi camera, ẩn/hiện và HUD nên giờ vẫn chạy liên tục.

signal inside_changed(inside: bool)

## Lớp va chạm dành riêng cho các vùng bấm được (cửa).
const CLICK_LAYER := 2

@export var outdoor_rig: CameraRig
@export var interior_rig: CameraRig
@export var outdoor_root: Node3D
@export var interior: Node3D
@export var hud: Hud
@export var fade_time: float = 0.35
@export var ray_length: float = 250.0

var inside: bool = false
var _hovered: StaticBody3D
var _busy: bool = false
var _fade: ColorRect
var _mouse_moved: bool = true


## Tạo vùng bấm (StaticBody3D) kèm khối sáng viền hiện khi rê chuột vào.
## `hint` là chữ gợi ý hiện trên HUD.
static func make_click_target(parent: Node3D, xform: Transform3D, size: Vector3,
		hint: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "ClickTarget"
	body.collision_layer = 1 << (CLICK_LAYER - 1)
	body.collision_mask = 0
	body.transform = xform
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var glow := MeshInstance3D.new()
	glow.name = "Highlight"
	var mesh := BoxMesh.new()
	mesh.size = size + Vector3(0.06, 0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(Palette.WINDOW_GLOW, 0.32)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	glow.mesh = mesh
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visible = false
	body.add_child(glow)

	body.set_meta("hint", hint)
	body.set_meta("highlight", glow)
	parent.add_child(body)
	return body


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(Palette.FADE, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	if hud != null:
		hud.exit_requested.connect(func() -> void: exit_house())
	_apply_state()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseMotion:
		_mouse_moved = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _hovered != null:
			_toggle()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_toggle()
	elif event.is_action_pressed("exit_interior") and inside:
		exit_house()


func _physics_process(_delta: float) -> void:
	# Dò tia từ chuột vào cảnh (chỉ lớp vùng bấm) để biết đang rê vào cửa nào
	if _busy or not _mouse_moved:
		return
	_mouse_moved = false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 << (CLICK_LAYER - 1))
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	_set_hovered(hit.get("collider") as StaticBody3D if not hit.is_empty() else null)


func enter_house(instant: bool = false) -> void:
	if not inside:
		_switch(true, instant)


func exit_house(instant: bool = false) -> void:
	if inside:
		_switch(false, instant)


func _toggle() -> void:
	if inside:
		exit_house()
	else:
		enter_house()


func _set_hovered(body: StaticBody3D) -> void:
	if body == _hovered:
		return
	if _hovered != null and is_instance_valid(_hovered):
		(_hovered.get_meta("highlight") as Node3D).visible = false
	_hovered = body
	if _hovered != null:
		(_hovered.get_meta("highlight") as Node3D).visible = true
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if _hovered != null else Input.CURSOR_ARROW)
	if hud != null:
		hud.set_hint(str(_hovered.get_meta("hint")) if _hovered != null else "")


func _switch(to_inside: bool, instant: bool) -> void:
	_busy = true
	_set_hovered(null)
	if not instant:
		var t := create_tween()
		t.tween_property(_fade, "color:a", 1.0, fade_time)
		await t.finished
	inside = to_inside
	_apply_state()
	inside_changed.emit(inside)
	if not instant:
		var t2 := create_tween()
		t2.tween_property(_fade, "color:a", 0.0, fade_time)
		await t2.finished
	_busy = false
	_mouse_moved = true


func _apply_state() -> void:
	if outdoor_rig != null:
		outdoor_rig.active = not inside
	if interior_rig != null:
		interior_rig.active = inside
	var rig := interior_rig if inside else outdoor_rig
	if rig != null:
		rig.camera.make_current()
	if interior != null:
		interior.visible = inside
	if outdoor_root != null:
		outdoor_root.visible = not inside
	if hud != null:
		hud.set_inside(inside)
