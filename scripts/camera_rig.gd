class_name CameraRig
extends Node3D
## Camera ngắm cảnh: xoay quanh tâm, zoom, kéo tâm, đổi phối cảnh/trực giao.
## Đặt node này ở tâm cảnh, có một Camera3D con.

@export_group("Góc nhìn")
@export_range(-180.0, 180.0) var yaw_deg: float = 0.0
@export_range(-80.0, -10.0) var pitch_deg: float = -36.0
@export_range(-80.0, -10.0) var min_pitch_deg: float = -55.0
@export_range(-80.0, -10.0) var max_pitch_deg: float = -25.0

@export_group("Zoom")
@export var distance: float = 46.0
@export var min_distance: float = 8.0
@export var max_distance: float = 70.0
@export_range(1.01, 1.5) var zoom_step: float = 1.12
## Ở chế độ trực giao, camera đứng cố định ở khoảng cách này; zoom đổi `size`.
@export var ortho_camera_distance: float = 90.0

@export_group("Di chuyển")
@export var rotate_sensitivity: float = 0.25   # độ / pixel
@export var pan_speed: float = 0.6             # tỉ lệ theo khoảng cách, mỗi giây
@export var focus_limit: float = 30.0          # tâm không ra khỏi vị trí ban đầu ±giới hạn
## Nếu có kích thước, tâm bị giới hạn trong hình chữ nhật này (x, z; tính từ vị trí ban đầu).
@export var focus_bounds: Rect2 = Rect2()
@export var smoothing: float = 10.0            # càng lớn càng bám nhanh

@export var orthographic: bool = false
## Chỉ camera đang dùng mới nhận chuột/phím (ngoài sân hoặc trong nhà).
@export var active: bool = true

@onready var camera: Camera3D = $Camera3D

# Giá trị hiện tại (được nội suy dần về giá trị đích)
var _yaw: float
var _pitch: float
var _distance: float
var _focus: Vector3
var _target_focus: Vector3
var _home: Vector3
var _rotating: bool = false
var _panning: bool = false


func _ready() -> void:
	_home = global_position
	_target_focus = global_position
	snap()


## Nhảy thẳng tới giá trị đích, bỏ qua nội suy (dùng khi chụp ảnh).
func snap() -> void:
	_yaw = yaw_deg
	_pitch = pitch_deg
	_distance = distance
	_focus = _target_focus
	_update_camera()


func set_focus(point: Vector3) -> void:
	_target_focus = point


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		_rotating = false
		_panning = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = clampf(distance / zoom_step, min_distance, max_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = clampf(distance * zoom_step, min_distance, max_distance)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			yaw_deg = wrapf(yaw_deg - mm.relative.x * rotate_sensitivity, -180.0, 180.0)
			pitch_deg = clampf(pitch_deg - mm.relative.y * rotate_sensitivity,
					min_pitch_deg, max_pitch_deg)
		elif _panning:
			# Kéo chuột: cảnh đi theo tay, tốc độ tỉ lệ với độ xa camera
			var px_to_world := distance / 600.0
			_move_focus(Vector2(-mm.relative.x, -mm.relative.y) * px_to_world)
	elif event.is_action_pressed("toggle_projection"):
		orthographic = not orthographic


func _process(delta: float) -> void:
	if not active:
		return
	# WASD / phím mũi tên: di chuyển tâm trên mặt đất
	var dir := Input.get_vector("cam_left", "cam_right", "cam_forward", "cam_back")
	if dir != Vector2.ZERO:
		_move_focus(dir * pan_speed * distance * delta)

	# Nội suy mượt, không phụ thuộc FPS
	var t := 1.0 - exp(-smoothing * delta)
	_yaw = lerp_angle(deg_to_rad(_yaw), deg_to_rad(yaw_deg), t)
	_yaw = rad_to_deg(_yaw)
	_pitch = lerpf(_pitch, pitch_deg, t)
	_distance = lerpf(_distance, distance, t)
	_focus = _focus.lerp(_target_focus, t)
	_update_camera()


## Dời tâm theo hướng nhìn hiện tại (x: sang phải, y: lùi về phía camera).
func _move_focus(offset: Vector2) -> void:
	var basis_y := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var move := basis_y * Vector3(offset.x, 0.0, offset.y)
	_target_focus += move
	if focus_bounds.has_area():
		_target_focus.x = clampf(_target_focus.x, _home.x + focus_bounds.position.x, _home.x + focus_bounds.end.x)
		_target_focus.z = clampf(_target_focus.z, _home.z + focus_bounds.position.y, _home.z + focus_bounds.end.y)
	else:
		_target_focus.x = clampf(_target_focus.x, _home.x - focus_limit, _home.x + focus_limit)
		_target_focus.z = clampf(_target_focus.z, _home.z - focus_limit, _home.z + focus_limit)


func _update_camera() -> void:
	global_position = _focus
	var dir := Vector3.BACK \
			.rotated(Vector3.RIGHT, deg_to_rad(_pitch)) \
			.rotated(Vector3.UP, deg_to_rad(_yaw))
	if orthographic:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		# Kích thước khung trực giao tương đương khung phối cảnh ở cùng khoảng cách
		camera.size = 2.0 * _distance * tan(deg_to_rad(camera.fov) * 0.5)
		camera.global_position = _focus + dir * ortho_camera_distance
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.global_position = _focus + dir * _distance
	camera.look_at(_focus, Vector3.UP)
