class_name KiteFlying
extends Node3D
## Trò chơi dân gian Thả diều (mục 30). Rủ qua hội thoại với trẻ con / trẻ chăn trâu: "Cho {me} mượn con
## diều thả với!" → "(Thả diều)". Phải đứng chỗ thoáng (bờ ruộng, bãi đất, đê) — dưới tán cây / giữa nhà
## thì đứa trẻ bảo ra chỗ trống. Người chơi đứng yên, camera riêng nhìn theo diều; đứa trẻ đứng cạnh xem.
## - Mô hình: diều nằm trên mặt cầu bán kính `line` quanh tay, xuôi theo gió (`wind_dir_deg`), góc ngẩng
##   `el`, góc lệch `az`. Gió = `wind_base` × √(Weather.wind) × (mạnh dần theo độ cao) × cơn giật / lặng gió.
##   Gió biểu kiến lớn hơn `lift_need` thì diều lên, nhỏ hơn thì rơi; lệch khỏi hướng gió thì kém gió.
## - Điều khiển: giữ Space / chuột trái (fish_reel) kéo giật dây — tăng gió biểu kiến, dây ngắn lại chút ít;
##   W thả thêm dây (diều lên cao xa, mất sức căng); S thu dây; A / D lái diều trái / phải; Esc thu diều về.
## - Sức căng `tension` (= (gió biểu kiến / `tension_ref`)²): quá 1 thì dây bị "mỏi" dần, mỏi hết là đứt dây,
##   diều bay mất. Diều chạm đất là rơi. Kết quả: độ cao cao nhất, thời gian bay; E thả lại, Esc thôi.

signal finished(max_height: float, seconds: float, reason: String)

@export var first_person: FirstPerson
@export var dialogue: Dialogue
@export var hud: Hud
@export var day_night: DayNight
@export var weather: Weather
## Bọn trẻ tự thả diều ngoài bờ ruộng khi không có người chơi (mục 36).
@export var terrain: Terrain
@export_group("Bọn trẻ tự thả")
## Mỗi chỗ thả tối đa mấy đứa.
@export var ambient_per_site: int = 2
## Thả bao lâu thì về (giây thật).
@export var ambient_seconds: Vector2 = Vector2(150.0, 300.0)
## Dây diều của bọn trẻ dài bao nhiêu (m).
@export var ambient_line: Vector2 = Vector2(25.0, 48.0)
@export_group("")
## Hướng gió thổi tới (độ, 0 = thổi về −z / phía bắc): gió nồm đông nam.
@export var wind_dir_deg: float = 145.0
@export var wind_base: float = 5.0
@export var lift_need: float = 3.6
@export var tension_ref: float = 9.0
@export var max_line: float = 120.0
@export var pull_boost: float = 4.0
@export var let_out_speed: float = 3.2
@export var reel_speed: float = 2.4
@export var steer_rate: float = 0.7
@export var gust_every: Vector2 = Vector2(6.0, 13.0)
@export var random_seed: int = 0
## Cỡ con diều (1 = cao 1,75 m).
@export var kite_scale: float = 1.6

enum Phase { OFF, FLY, LOST, RESULT }

const KITE_COLORS: Array[Color] = [Color("#d8392f"), Color("#f2c94c"), Color("#3f7fc4"), Color("#e86fa0"), Color("#47a15a")]
const TAIL_N := 10
const TAIL_SEG := 0.8

var phase: Phase = Phase.OFF
var kid: Villager
var line: float = 10.0
var el: float = 0.35
var az: float = 0.0
var tension: float = 0.0
var strain: float = 0.0
var wind_now: float = 0.0
var apparent: float = 0.0
var max_height: float = 0.0
var flight_time: float = 0.0
var reason: String = ""
var _hand: Vector3
var _down: Vector3          # hướng xuôi gió (nằm ngang)
var _t: float = 0.0
var _gust: float = 0.0       # cơn giật hiện tại (0…)
var _gust_amp: float = 0.0
var _gust_t: float = 0.0
var _next_gust: float = 8.0
var _rng := RandomNumberGenerator.new()
var _cheered: Dictionary = {}
var _lost_vel: Vector3
var _kite_pos: Vector3
var _tail: Array[Vector3] = []

## Diều bọn trẻ đang thả: {kid, site, node, line (ImmediateMesh), tail (ImmediateMesh), len, t, t_left, ph, color}.
var ambient: Array[Dictionary] = []
## Chỗ thả diều: trên đường đất giữa các ô ruộng (thoáng, không vướng cây, mái nhà).
var sites: Array[Vector3] = []
var _amb_root: Node3D
var _line_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D

var _kite: Node3D
var _line_mesh: ImmediateMesh
var _tail_mesh: ImmediateMesh
var _cam: Camera3D
var _ui: CanvasLayer
var _top: Label
var _sub: Label
var _tension_bar: ColorRect
var _wind_label: Label
var _result: PanelContainer
var _result_label: Label


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_cam = Camera3D.new()
	_cam.name = "KiteCam"
	_cam.top_level = true
	_cam.fov = 70.0
	_cam.far = 1500.0
	add_child(_cam)
	_build_kite(0)
	var lm := MeshInstance3D.new()
	lm.name = "Line"
	_line_mesh = ImmediateMesh.new()
	lm.mesh = _line_mesh
	lm.top_level = true
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#f4efe2")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lm.material_override = mat
	add_child(lm)
	var tm := MeshInstance3D.new()
	tm.name = "Tail"
	_tail_mesh = ImmediateMesh.new()
	tm.mesh = _tail_mesh
	tm.top_level = true
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.vertex_color_is_srgb = true
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tmat.roughness = 1.0
	tm.material_override = tmat
	add_child(tm)
	_build_ui()
	visible = false
	_line_mat = mat
	_tail_mat = tmat
	# Diều của bọn trẻ nằm ngoài node này (node này ẩn khi người chơi không thả)
	_amb_root = Node3D.new()
	_amb_root.name = "AmbientKites"
	get_parent().add_child.call_deferred(_amb_root)
	if terrain != null:
		for r in terrain.roads:
			for z in [26.0, 64.0]:
				sites.append(_road_point(r, z))


## Con diều hình thoi: giấy dán hai màu, khung tre chữ thập, sáo diều ở giữa.
func _build_kite(variant: int) -> void:
	if _kite != null:
		_kite.queue_free()
	_kite = Node3D.new()
	_kite.name = "Kite"
	_kite.top_level = true
	add_child(_kite)
	var a := KITE_COLORS[variant % KITE_COLORS.size()]
	var b := KITE_COLORS[(variant + 2) % KITE_COLORS.size()]
	var mb := MeshBuilder.new(31 + variant, 0.03)
	# Mặt diều nằm trong mặt phẳng XY cục bộ, mặt trước hướng +z (về phía người thả)
	var top := Vector3(0, 0.75, 0)
	var bottom := Vector3(0, -1.0, 0)
	var left := Vector3(-0.62, 0.15, 0)
	var right := Vector3(0.62, 0.15, 0)
	var c := Vector3(0, 0.15, 0)
	for side: float in [1.0, -1.0]:
		var inside := Vector3(0, 0, -0.1 * side)
		mb.add_triangle(top, left, c, a, inside)
		mb.add_triangle(top, right, c, b, inside)
		mb.add_triangle(bottom, left, c, b, inside)
		mb.add_triangle(bottom, right, c, a, inside)
	mb.add_limb(bottom + Vector3(0, 0, 0.02), top + Vector3(0, 0, 0.02), 0.015, 0.012, 4, Palette.BAMBOO_STEM)
	mb.add_limb(left + Vector3(0, 0, 0.02), right + Vector3(0, 0, 0.02), 0.013, 0.013, 4, Palette.BAMBOO_STEM)
	# Sáo diều: ống tre ngang trước mặt diều
	mb.add_limb(Vector3(-0.22, 0.32, 0.08), Vector3(0.22, 0.32, 0.08), 0.04, 0.04, 6, Palette.HAT)
	_kite.add_child(mb.commit_instance("KiteMesh"))
	var mat := (_kite.get_child(0) as MeshInstance3D)
	mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mat.material_override = null
	var m := MeshBuilder.material()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.mesh.surface_set_material(0, m)


# --- Bắt đầu / kết thúc -------------------------------------------------------------------------

## Lời từ chối (rỗng = đồng ý cho mượn diều).
func refusal(v: Villager, at: Vector3 = Vector3.INF) -> String:
	if not v.role in ["kid", "herder"]:
		return "Diều là của bọn trẻ con, {you} hỏi chúng nó mà mượn."
	if v.has_meta("in_class"):
		return "Đang giờ học mà {you}!"
	var h := day_night.time_of_day if day_night != null else 15.0
	if h >= 18.5 or h < 6.0:
		return "Tối rồi, thả diều sao thấy. Mai {you} ra sớm nhé!"
	if weather != null and weather.kind in ["storm", "drizzle"]:
		return "Mưa thế này ướt hết giấy diều, rách mất!"
	if weather != null and weather.kind == "fog":
		return "Sương mù lặng gió thế này, diều không lên được đâu {you}."
	if at != Vector3.INF and not open_area(at):
		return "Chỗ này lắm cây với mái nhà, diều mắc mất. Ra bờ ruộng hay chỗ trống mà thả {you} ạ!".replace(" {you} ạ", " {you}")
	return ""


## Lời báo khi người chơi tự thả diều của mình (túi đồ, mục 48): rỗng = thả được.
func self_refusal(at: Vector3) -> String:
	var h := day_night.time_of_day if day_night != null else 15.0
	if h >= 18.5 or h < 6.0:
		return "Tối rồi, thả diều sao thấy. Mai ra sớm mà thả."
	if weather != null and weather.kind in ["storm", "drizzle"]:
		return "Mưa thế này ướt hết giấy diều mất."
	if weather != null and weather.kind == "fog":
		return "Sương mù lặng gió, diều không lên được."
	if not open_area(at):
		return "Chỗ này lắm cây với mái nhà — ra bờ ruộng hay chỗ trống mà thả."
	return ""


## Chỗ thoáng: phía trên trống, xung quanh ít vật che ở tầm cao 3–6 m.
func open_area(at: Vector3) -> bool:
	if first_person == null:
		return true
	var space := first_person.get_world_3d().direct_space_state
	var mask := 1 << (FirstPerson.SOLID_LAYER - 1)
	var up := PhysicsRayQueryParameters3D.create(at + Vector3(0, 2.0, 0), at + Vector3(0, 40.0, 0), mask)
	if not space.intersect_ray(up).is_empty():
		return false
	# Tán lá (shader gió) không có va chạm: xét khối bao của chúng
	for box: AABB in _leaf_boxes():
		if at.x > box.position.x and at.x < box.end.x and at.z > box.position.z and at.z < box.end.z \
				and box.end.y > at.y + 2.5 and box.position.y < at.y + 30.0:
			return false
	var blocked := 0
	for k in 8:
		var d := Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0))
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 4.0, 0), at + Vector3(0, 6.0, 0) + d * 10.0, mask)
		if not space.intersect_ray(q).is_empty():
			blocked += 1
	# Phía xuôi gió phải trống (diều bay về đó)
	var dn := _down_dir()
	var q2 := PhysicsRayQueryParameters3D.create(at + Vector3(0, 3.0, 0), at + Vector3(0, 12.0, 0) + dn * 18.0, mask)
	return blocked <= 2 and space.intersect_ray(q2).is_empty()


var _leaves: Array[AABB] = []
var _leaves_done: bool = false


## Khối bao (nới 2 m) của mọi mesh lá cây dùng shader gió dưới `World` — tính một lần.
func _leaf_boxes() -> Array[AABB]:
	if _leaves_done:
		return _leaves
	_leaves_done = true
	var world := get_tree().current_scene.get_node_or_null("World") if get_tree().current_scene != null else null
	if world == null:
		world = get_parent().get_node_or_null("World")
	if world == null:
		return _leaves
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "Clouds" or n is Villager:
			continue
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mat: Material = mi.material_override
		if mat == null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			var box := mi.global_transform * mi.get_aabb()
			if box.size.y > 1.5:
				_leaves.append(box.grow(2.0))
	return _leaves


func _down_dir() -> Vector3:
	var a := deg_to_rad(wind_dir_deg)
	# Gió thổi TỚI từ hướng wind_dir_deg → diều bay về phía ngược lại
	return -Vector3(sin(a), 0, -cos(a))


func start(v: Villager) -> void:
	if phase != Phase.OFF or first_person == null:
		return
	# Đứa trẻ đang thả diều của nó: thu diều về đưa cho người chơi thả lại từ đầu
	var was_ambient := false
	for f in ambient.duplicate():
		if f.kid == v:
			_end_ambient(f, true)
			was_ambient = true
	if was_ambient:
		v.set_meta("kite_lent", true)
	kid = v                       # null: người chơi thả diều của mình (túi đồ)
	first_person._suspend("kite")
	_down = _down_dir()
	var fp := first_person.global_position
	if kid != null:
		kid.set_meta("talking", true)
		# Đứa trẻ đứng cạnh, lệch sang bên tay phải người thả
		var side := _down.cross(Vector3.UP).normalized()
		var spot := fp + side * 1.3 - _down * 0.4
		kid.global_position = Vector3(spot.x, kid.global_position.y if absf(kid.global_position.y - fp.y) < 0.6 else fp.y, spot.z)
		kid.work_anim = ""
	_build_kite(_rng.randi_range(0, KITE_COLORS.size() - 1))
	visible = true
	_ui.visible = true
	if hud != null:
		hud.visible = false
	_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_launch()
	_bark("Thả lên đi {you}! Gió đang lên đấy!")


func _launch() -> void:
	_hand = first_person.global_position + Vector3(0, 1.25, 0) + _down * 0.35
	line = 9.0
	el = 0.6
	az = 0.0
	strain = 0.0
	tension = 0.0
	max_height = 0.0
	flight_time = 0.0
	reason = ""
	_cheered.clear()
	_gust = 0.0
	_gust_amp = 0.0
	_next_gust = _rng.randf_range(gust_every.x, gust_every.y)
	_kite_pos = _kite_target()
	_tail.clear()
	for i in TAIL_N:
		_tail.append(_kite_pos - Vector3(0, 1.0 + i * TAIL_SEG, 0))
	_kite.visible = true
	_result.visible = false
	phase = Phase.FLY
	_update_camera(1.0)


func stop() -> void:
	if phase == Phase.OFF:
		return
	phase = Phase.OFF
	visible = false
	_ui.visible = false
	_line_mesh.clear_surfaces()
	_tail_mesh.clear_surfaces()
	if hud != null:
		hud.visible = true
	if is_instance_valid(kid):
		kid.remove_meta("talking")
		kid.work_anim = ""
		if kid.has_meta("kite_lent"):
			kid.remove_meta("kite_lent")
			kid.dwell = 0.0          # trả diều rồi thì đi chơi việc khác
	kid = null
	first_person._resume()


func _end(why: String) -> void:
	reason = why
	phase = Phase.RESULT if why != "snap" else Phase.LOST
	_t = 0.0
	match why:
		"snap":
			_lost_vel = _down * 6.0 + Vector3(0, 2.5, 0)
			_bark("Ối! Đứt dây rồi! Diều bay mất rồi {you} ơi!")
		"crash":
			_bark("Rơi rồi! Thả lại đi {you}!")
		"reel":
			_bark("Diều {you} thả lên cao ghê!" if max_height > 30.0 else "Lần sau thả cao hơn nhé!")
	if why != "snap":
		_show_result()
	finished.emit(max_height, flight_time, why)


func _show_result() -> void:
	phase = Phase.RESULT
	var title: String = {"snap": "Đứt dây — diều bay mất!", "crash": "Diều rơi xuống đất!", "reel": "Thu diều về"}.get(reason, "")
	var comment := "Diều no gió, lên tít tận mây xanh!" if max_height >= 50.0 else (
			"Cao lắm rồi đấy!" if max_height >= 30.0 else ("Cũng được, gió thế mà." if max_height >= 15.0 else "Diều chưa kịp no gió."))
	_result_label.text = "%s\n\nCao nhất  %d m\nBay được  %d giây\n%s\n\nE: thả lại   ·   Esc: trả diều" % [
			title, int(max_height), int(flight_time), comment]
	_result.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.OFF:
		return
	if event.is_action_pressed("exit_interior"):
		if phase == Phase.FLY:
			_end("reel")
		else:
			stop()
		get_viewport().set_input_as_handled()
	elif phase == Phase.RESULT and event.is_action_pressed("interact"):
		_build_kite(_rng.randi_range(0, KITE_COLORS.size() - 1))
		_launch()
		get_viewport().set_input_as_handled()
	elif phase == Phase.FLY and (event.is_action("fish_reel") or event.is_action("cam_forward")):
		get_viewport().set_input_as_handled()


# --- Mỗi khung hình --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_process_ambient(delta)
	if phase == Phase.OFF:
		return
	if phase == Phase.FLY:
		var steer := Input.get_axis("cam_left", "cam_right")
		var reel := 0.0
		if Input.is_action_pressed("cam_forward"):
			reel = 1.0
		elif Input.is_action_pressed("cam_back"):
			reel = -1.0
		step(delta, Input.is_action_pressed("fish_reel"), reel, steer)
	elif phase == Phase.LOST:
		_t += delta
		_lost_vel += (_down * 3.0 - _lost_vel) * 0.4 * delta + Vector3(0, -1.2, 0) * delta
		_kite_pos += _lost_vel * delta
		if _t > 3.5:
			_kite.visible = false
			_show_result()
	_place_kite(delta)
	_update_camera(delta)
	_update_ui()
	if is_instance_valid(kid):
		kid.look_at(Vector3(_kite_pos.x, kid.global_position.y, _kite_pos.z), Vector3.UP, true)


## Một bước bay: `pulling` = giữ Space, `reel` +1 thả dây / −1 thu dây, `steer` −1…1. Tách riêng cho bài thử.
func step(delta: float, pulling: bool, reel: float, steer: float) -> void:
	_t += delta
	flight_time += delta
	# Gió: dao động chậm + cơn giật ngẫu nhiên (lên nhanh, tắt dần)
	_next_gust -= delta
	if _next_gust <= 0.0:
		_gust_amp = _rng.randf_range(0.35, 0.75) if _rng.randf() < 0.7 else -_rng.randf_range(0.3, 0.5)   # giật / lặng
		_gust_t = 0.0
		_next_gust = _rng.randf_range(gust_every.x, gust_every.y)
	_gust_t += delta
	_gust = _gust_amp * sin(clampf(_gust_t / 2.8, 0.0, 1.0) * PI)
	var wf := sqrt(weather.wind) if weather != null else 1.0
	var h := line * sin(el)
	var shear := 0.75 + 0.3 * minf(h / 30.0, 1.6)
	wind_now = maxf(wind_base * wf * shear * (1.0 + 0.12 * sin(_t * 0.6) + 0.07 * sin(_t * 1.7) + _gust), 0.0)
	# Gió biểu kiến: kéo dây thì tăng, thả dây thì diều trôi theo gió nên giảm
	var app := wind_now
	if pulling:
		app += pull_boost
		line = maxf(line - 1.0 * delta, 3.0)
	if reel > 0.0:
		app -= let_out_speed * 1.4
		line = minf(line + let_out_speed * delta, max_line)
	elif reel < 0.0:
		app += reel_speed * 0.8
		line = maxf(line - reel_speed * delta, 3.0)
	# Rìa "cửa sổ gió": lệch hướng gió hoặc ngẩng quá cao thì kém gió
	var window := cos(az) * (1.0 - 0.35 * maxf(el - 0.9, 0.0))
	apparent = maxf(app, 0.0) * maxf(window, 0.05)
	var d_el := clampf((apparent - lift_need) * 0.09, -0.32, 0.24)
	d_el = minf(d_el, (1.25 - el) * 1.5)
	el = clampf(el + d_el * delta, -0.2, 1.3)
	az = clampf(az + (steer * steer_rate - az * 0.25 + 0.05 * sin(_t * 0.9)) * delta, -1.3, 1.3)
	tension = pow(apparent / tension_ref, 2.0) * (0.6 + 0.4 * cos(az))
	if tension > 1.0:
		strain += (tension - 1.0) * 1.6 * delta
	else:
		strain = maxf(strain - 0.25 * delta, 0.0)
	h = line * sin(el)
	max_height = maxf(max_height, h + 1.25)
	# Câu reo của đứa trẻ
	if _gust > 0.25 and not _cheered.has("gust%d" % int(_t / 10.0)):
		_cheered["gust%d" % int(_t / 10.0)] = true
		if tension > 0.7:
			_bark("Gió giật đấy! Thả dây ra {you} ơi!")
	if _gust < -0.2 and el < 0.45 and not _cheered.has("lull%d" % int(_t / 10.0)):
		_cheered["lull%d" % int(_t / 10.0)] = true
		_bark("Lặng gió rồi, giật dây đi {you}!")
	for mark in [20, 40, 60]:
		if h >= mark and not _cheered.has(mark):
			_cheered[mark] = true
			_bark(["Lên rồi! Lên rồi!", "Cao quá! Nghe tiếng sáo vi vu kìa!", "Diều lên tận mây rồi {you} ơi!"][[20, 40, 60].find(mark)])
	if strain >= 1.0:
		_end("snap")
	elif h < -0.6:
		_end("crash")
	elif line <= 3.0 and reel < 0.0:
		_end("reel")


func _kite_target() -> Vector3:
	var side := _down.cross(Vector3.UP).normalized()
	var horiz := (_down * cos(az) + side * sin(az)) * cos(el)
	return _hand + (horiz + Vector3(0, sin(el), 0)) * line


func _place_kite(delta: float) -> void:
	if phase == Phase.FLY or phase == Phase.RESULT and reason != "snap":
		var want := _kite_target()
		if phase == Phase.RESULT:
			want = _hand + Vector3(0, -1.0, 0) + _down * 2.0 if reason == "reel" else Vector3(want.x, _hand.y - 1.0, want.z)
		_kite_pos = _kite_pos.lerp(want, 1.0 - exp(-6.0 * delta)) if delta < 0.9 else want
	# Mặt diều quay về phía tay người thả, chao theo gió
	var to_hand := (_hand - _kite_pos).normalized()
	var wob := 0.12 * sin(_t * 3.1) * (0.4 + tension)
	var basis := Basis.looking_at(-to_hand, Vector3.UP)
	basis = basis.rotated(to_hand, wob)
	_kite.global_transform = Transform3D(basis, _kite_pos)
	_kite.scale = Vector3.ONE * kite_scale
	_draw_line()
	_sim_tail(delta)


## Dây diều: đường cong võng xuống (võng nhiều khi dây chùng), dải mỏng quay về camera.
func _draw_line() -> void:
	_line_mesh.clear_surfaces()
	if phase == Phase.LOST and _t > 0.0:
		return
	var a := _hand
	var b := _kite_pos + _kite.global_transform.basis * Vector3(0, 0.15, 0.05)
	var sag := clampf(0.1 - tension * 0.06, 0.02, 0.1) * a.distance_to(b)
	var n := 24
	var cam := _cam.global_position
	_line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		var dir := (p - prev).normalized()
		var w := 0.012 + 0.0025 * prev.distance_to(cam) * 0.4
		var side := dir.cross((cam - prev).normalized()).normalized() * w
		_line_mesh.surface_add_vertex(prev - side)
		_line_mesh.surface_add_vertex(prev + side)
		_line_mesh.surface_add_vertex(p + side)
		_line_mesh.surface_add_vertex(prev - side)
		_line_mesh.surface_add_vertex(p + side)
		_line_mesh.surface_add_vertex(p - side)
		prev = p
	_line_mesh.surface_end()


## Đuôi diều: chuỗi điểm bám theo nhau (verlet đơn giản), bị gió thổi về sau.
func _sim_tail(delta: float) -> void:
	_tail_mesh.clear_surfaces()
	if not _kite.visible or _tail.is_empty():
		return
	var root := _kite_pos + _kite.global_transform.basis * Vector3(0, -1.0, 0)   # basis đã gồm cỡ diều
	_tail[0] = root
	var push := (_down * (0.6 + wind_now * 0.08) + Vector3(0, -0.5, 0)) * TAIL_SEG
	for i in range(1, _tail.size()):
		var want := _tail[i - 1] + (_tail[i] - _tail[i - 1]).normalized() * TAIL_SEG
		want = want.lerp(_tail[i - 1] + push.normalized() * TAIL_SEG, 0.25)
		want += Vector3(0, 0, 0.0)
		var wave := _down.cross(Vector3.UP).normalized() * 0.08 * sin(_t * 5.0 - i * 0.8)
		_tail[i] = _tail[i].lerp(want + wave, 1.0 - exp(-14.0 * maxf(delta, 0.016)))
		_tail[i] = _tail[i - 1] + (_tail[i] - _tail[i - 1]).normalized() * TAIL_SEG
	var cam := _cam.global_position
	_tail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, _tail.size()):
		var p0 := _tail[i - 1]
		var p1 := _tail[i]
		var w := 0.13 * (1.0 - 0.06 * i)
		var side := (p1 - p0).normalized().cross((cam - p0).normalized()).normalized() * w
		var col := KITE_COLORS[i % 2] if i % 2 == 0 else Color("#f4efe2")
		for v in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
			_tail_mesh.surface_set_color(col)
			_tail_mesh.surface_add_vertex(v)
	_tail_mesh.surface_end()


## Camera đứng sau lưng người thả, ngửa nhìn theo diều (giữ cả tay cầm dây trong khung).
func _update_camera(delta: float) -> void:
	var side := _down.cross(Vector3.UP).normalized()
	var want := _hand - _down * 3.4 + Vector3(0, 0.45, 0) - side * 0.9
	var t := 1.0 - exp(-3.0 * delta)
	_cam.global_position = _cam.global_position.lerp(want, t) if delta < 0.9 else want
	# Ngước theo diều nhưng giữ đường chân trời ở mép dưới khung hình
	var to := _kite_pos - _cam.global_position
	var flat := Vector2(to.x, to.z).length()
	var ek := atan2(to.y, maxf(flat, 0.1))
	var pitch := clampf(ek - deg_to_rad(20.0), deg_to_rad(6.0), deg_to_rad(36.0))
	var yaw := atan2(-to.x, -to.z)
	var target := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var cur := _cam.global_transform.basis.orthonormalized()
	_cam.global_transform.basis = cur.slerp(target, t) if delta < 0.9 else target


func _bark(text: String) -> void:
	if dialogue != null and is_instance_valid(kid):
		dialogue.bark(kid, dialogue.fill_for(kid, text))


# --- Giao diện ------------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style())
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 16
	_ui.add_child(top)
	var box := VBoxContainer.new()
	top.add_child(box)
	_top = _label(true, 24, Palette.HUD_TEXT)
	_sub = _label(false, 16, Palette.FLOWER_YELLOW)
	for l in [_top, _sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 20
	panel.offset_bottom = -20
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(320, 0)
	panel.add_child(col)
	col.add_child(_label(false, 15, Palette.HUD_SUBTEXT, "Sức căng dây (đỏ quá lâu là đứt)"))
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.custom_minimum_size = Vector2(300, 14)
	bg.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bg)
	var red := ColorRect.new()
	red.color = Color(Palette.FLAG_RED, 0.35)
	red.position = Vector2(300.0 / 1.5, 0)
	red.size = Vector2(300.0 - 300.0 / 1.5, 14)
	bg.add_child(red)
	_tension_bar = ColorRect.new()
	_tension_bar.size = Vector2(0, 14)
	bg.add_child(_tension_bar)
	_wind_label = _label(false, 15, Palette.HUD_SUBTEXT)
	col.add_child(_wind_label)
	col.add_child(_label(false, 14, Palette.HUD_SUBTEXT, "Giữ Space / chuột trái: giật dây  ·  W: thả dây  ·  S: thu dây"))
	col.add_child(_label(false, 14, Palette.HUD_SUBTEXT, "A / D: lái diều  ·  Esc: thu diều"))
	_result = PanelContainer.new()
	_result.add_theme_stylebox_override("panel", _style())
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result.visible = false
	_ui.add_child(_result)
	_result_label = _label(true, 22, Palette.HUD_TEXT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_child(_result_label)


func _style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _label(bold: bool, size: int, col: Color, text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Hud.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _update_ui() -> void:
	var h := maxf(line * sin(el) + 1.25, 0.0) if phase == Phase.FLY else 0.0
	_top.text = "Thả diều  ·  cao %d m  ·  dây %d m  ·  %d s" % [int(h), int(line), int(flight_time)]
	var hint := ""
	if phase == Phase.FLY:
		if strain > 0.35:
			hint = "Dây căng quá! Thả dây ra (W)!"
		elif el < 0.25:
			hint = "Diều sắp rơi! Giật dây (Space)!"
		elif _gust > 0.2:
			hint = "Gió giật!"
		elif _gust < -0.15:
			hint = "Lặng gió…"
	_sub.text = hint
	var tv := clampf(tension / 1.5, 0.0, 1.0)
	_tension_bar.size.x = 300.0 * tv
	_tension_bar.color = Palette.LILY if tension < 0.75 else (Palette.FLOWER_YELLOW if tension < 1.0 else Palette.FLAG_RED)
	var ws := "lặng" if wind_now < 3.5 else ("nhẹ" if wind_now < 5.5 else ("vừa" if wind_now < 7.5 else "mạnh"))
	_wind_label.text = "Gió: %s (%.1f m/s)%s" % [ws, wind_now, "  — giật!" if _gust > 0.2 else ""]

# --- Bọn trẻ tự thả diều (không có người chơi) ---------------------------------------------------

## Điểm trên đường đất `r` (polyline x, z) ở độ sâu z.
static func _road_point(r: PackedVector2Array, z: float) -> Vector3:
	for i in r.size() - 1:
		var a := r[i]
		var b := r[i + 1]
		if (z - a.y) * (z - b.y) <= 0.0 and a.y != b.y:
			return Vector3(lerpf(a.x, b.x, (z - a.y) / (b.y - a.y)), 0.05, z)
	return Vector3(r[r.size() - 1].x, 0.05, r[r.size() - 1].y)


func ambient_ok(h: float) -> bool:
	if sites.is_empty() or h < 7.0 or h >= 17.8:
		return false
	return weather == null or weather.kind in ["clear", "cloudy"]


func site_target(v: Villager) -> Vector3:
	var best := -1
	for i in sites.size():
		var n := 0
		for f in ambient:
			if int(f.site) == i:
				n += 1
		if n >= ambient_per_site:
			continue
		if best < 0 or v.global_position.distance_to(sites[i]) < v.global_position.distance_to(sites[best]):
			best = i
	if best < 0:
		best = _rng.randi_range(0, sites.size() - 1)
	return sites[best] + Vector3(0, 0, _rng.randf_range(-4.0, 4.0))


func is_ambient_member(v: Villager) -> bool:
	return v.has_meta("kite_amb")


## Villagers gọi khi một đứa (việc `kite`) ra tới bờ ruộng: thả diều lên.
func ambient_arrive(v: Villager) -> void:
	var best := 0
	for i in sites.size():
		if v.global_position.distance_to(sites[i]) < v.global_position.distance_to(sites[best]):
			best = i
	var n := 0
	for f in ambient:
		if int(f.site) == best:
			n += 1
	if n >= ambient_per_site or v.global_position.distance_to(sites[best]) > 12.0:
		v.dwell = 0.0
		return
	v.set_meta("kite_amb", true)
	v.set_meta("talking", true)
	v.state = Villager.State.IDLE
	v.dwell = 1.0e6
	v.work_anim = "idle"
	if v.prop_node != null:
		v.prop_node.visible = false
	v.activity_text = "đang thả diều"
	var color := _rng.randi_range(0, KITE_COLORS.size() - 1)
	var node := _make_ambient_kite(color)
	var line := ImmediateMesh.new()
	var lm := MeshInstance3D.new()
	lm.mesh = line
	lm.material_override = _line_mat
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(lm)
	lm.top_level = true
	var tail := ImmediateMesh.new()
	var tmi := MeshInstance3D.new()
	tmi.mesh = tail
	tmi.material_override = _tail_mat
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(tmi)
	tmi.top_level = true
	ambient.append({"kid": v, "site": best, "node": node, "line": line, "tail": tail, "color": color,
			"len": _rng.randf_range(ambient_line.x, ambient_line.y), "t": 0.0, "ph": _rng.randf() * TAU,
			"t_left": _rng.randf_range(ambient_seconds.x, ambient_seconds.y), "pos": v.global_position + Vector3(0, 2, 0)})


func _make_ambient_kite(variant: int) -> Node3D:
	var root := Node3D.new()
	root.name = "KidKite"
	_amb_root.add_child(root)
	var a := KITE_COLORS[variant % KITE_COLORS.size()]
	var b := KITE_COLORS[(variant + 2) % KITE_COLORS.size()]
	var mb := MeshBuilder.new(41 + variant, 0.03)
	var top := Vector3(0, 0.75, 0)
	var bottom := Vector3(0, -1.0, 0)
	var left := Vector3(-0.62, 0.15, 0)
	var right := Vector3(0.62, 0.15, 0)
	var c := Vector3(0, 0.15, 0)
	for side: float in [1.0, -1.0]:
		var inside := Vector3(0, 0, -0.1 * side)
		mb.add_triangle(top, left, c, a, inside)
		mb.add_triangle(top, right, c, b, inside)
		mb.add_triangle(bottom, left, c, b, inside)
		mb.add_triangle(bottom, right, c, a, inside)
	mb.add_limb(bottom + Vector3(0, 0, 0.02), top + Vector3(0, 0, 0.02), 0.015, 0.012, 4, Palette.BAMBOO_STEM)
	mb.add_limb(left + Vector3(0, 0, 0.02), right + Vector3(0, 0, 0.02), 0.013, 0.013, 4, Palette.BAMBOO_STEM)
	var mi := mb.commit_instance("KiteMesh")
	var m := MeshBuilder.material()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.mesh.surface_set_material(0, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.name = "Body"
	root.add_child(mi)
	return root


func _end_ambient(f: Dictionary, keep_kid: bool = false) -> void:
	var v: Villager = f.kid
	if is_instance_valid(v):
		v.remove_meta("kite_amb")
		v.remove_meta("talking")
		if v.prop_node != null:
			v.prop_node.visible = true
		if not keep_kid:
			v.dwell = 0.0
	(f.node as Node).queue_free()
	ambient.erase(f)


func _process_ambient(delta: float) -> void:
	if ambient.is_empty():
		return
	var h := day_night.time_of_day if day_night != null else 15.0
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	var down := _down_dir()
	var side := down.cross(Vector3.UP).normalized()
	var w := weather.wind if weather != null else 1.0
	for f in ambient.duplicate():
		var v: Villager = f.kid
		f.t_left = float(f.t_left) - delta
		if not is_instance_valid(v) or v.activity != "kite" or float(f.t_left) <= 0.0 or not ambient_ok(h):
			_end_ambient(f)
			continue
		f.t = float(f.t) + delta
		var t := float(f.t)
		var ph := float(f.ph)
		# Diều lên dần (dây thả ra trong ~10 s), rồi chao lượn theo gió
		var ln := float(f.len) * clampf(0.15 + t / 10.0, 0.15, 1.0)
		var el := 0.95 + 0.08 * sin(t * 0.4 + ph) - 0.1 * (1.0 - clampf(w, 0.3, 1.5))
		var az := 0.25 * sin(t * 0.23 + ph) + 0.08 * sin(t * 1.1 + ph * 2.0)
		var hand := v.global_position + Vector3(0, 1.0, 0) + down * 0.3
		var want := hand + ((down * cos(az) + side * sin(az)) * cos(el) + Vector3(0, sin(el), 0)) * ln
		var pos: Vector3 = (f.pos as Vector3).lerp(want, 1.0 - exp(-2.0 * delta))
		f.pos = pos
		v.look_at(Vector3(pos.x, v.global_position.y, pos.z), Vector3.UP, true)
		var node := f.node as Node3D
		var body := node.get_node("Body") as Node3D
		var to_hand := (hand - pos).normalized()
		var bs := Basis.looking_at(-to_hand, Vector3.UP).rotated(to_hand, 0.15 * sin(t * 2.7 + ph))
		body.global_transform = Transform3D(bs.scaled(Vector3.ONE * kite_scale), pos)
		var near := cam_pos.distance_to(pos) < 260.0
		node.visible = near
		if near:
			_draw_amb_line(f.line, hand, pos, cam_pos)
			_draw_amb_tail(f.tail, pos + bs * Vector3(0, -1.0 * kite_scale, 0), down, t + ph, cam_pos, int(f.color))


func _draw_amb_line(im: ImmediateMesh, a: Vector3, b: Vector3, cam: Vector3) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var prev := a
	var sag := 0.06 * a.distance_to(b)
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		var dir := (p - prev).normalized()
		var wd := 0.012 + 0.001 * prev.distance_to(cam)
		var sd := dir.cross((cam - prev).normalized()).normalized() * wd
		for q in [prev - sd, prev + sd, p + sd, prev - sd, p + sd, p - sd]:
			im.surface_add_vertex(q)
		prev = p
	im.surface_end()


func _draw_amb_tail(im: ImmediateMesh, root: Vector3, down: Vector3, t: float, cam: Vector3, color: int) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := down.cross(Vector3.UP).normalized()
	var prev := root
	for i in range(1, 8):
		var p := root + (down * 0.75 + Vector3(0, -0.65, 0)) * TAIL_SEG * i + side * 0.18 * sin(t * 5.0 - i * 0.8)
		var wd := 0.12 * (1.0 - 0.07 * i)
		var sd := (p - prev).normalized().cross((cam - prev).normalized()).normalized() * wd
		var col := KITE_COLORS[(color + i) % KITE_COLORS.size()] if i % 2 == 0 else Color("#f4efe2")
		for q in [prev - sd, prev + sd, p + sd, prev - sd, p + sd, p - sd]:
			im.surface_set_color(col)
			im.surface_add_vertex(q)
		prev = p
	im.surface_end()
