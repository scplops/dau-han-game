class_name FarmWork
extends Node3D
## Làm thuê mùa vụ (mục 54): mùa cấy đi cấy thuê, lúa đang lên thì làm cỏ thuê, mùa gặt đi gặt thuê.
## Hỏi một bác nông dân đang ở ngoài đồng (nhập vai) → xuống ruộng làm một buổi `work_seconds` giây:
## bấm Space / chuột trái ĐÚNG NHỊP TAY (chấm trắng vào vùng vàng) là xong một khóm; đều tay thì nhịp nhanh dần,
## lệch tay thì khựng lại. Hết buổi được trả công theo số khóm (tiền; mùa gặt thêm gạo).
## Bác chủ ruộng làm luống bên cạnh với nhịp đều để so.

signal finished(kind: String, cells: int, pay: int)

@export var farming: Farming
@export var first_person: FirstPerson
@export var dialogue: Dialogue
@export var hud: Hud
@export var day_night: DayNight
@export var weather: Weather
@export var villagers: Villagers
@export var inventory: Inventory

@export_group("Luống ruộng")
## Số khóm mỗi hàng ngang và số hàng của một luống.
@export var cols: int = 6
@export var rows: int = 20
@export var spacing: float = 0.42
## Người chơi phải đứng cách ruộng không quá ngần này mét mới xin làm được.
@export var field_reach: float = 15.0
@export_group("Nhịp tay")
## Một buổi làm (giây thật).
@export var work_seconds: float = 60.0
## Chu kỳ nhịp lúc đầu → lúc đều tay nhất (giây).
@export var beat_period: Vector2 = Vector2(0.85, 0.5)
## Bấm lệch nhịp không quá ngần này giây là trúng.
@export var beat_window: float = 0.09
## Chuỗi đều tay ngần này khóm thì nhịp nhanh hết cỡ.
@export var streak_full: int = 24
## Lệch tay thì khựng lại (giây).
@export var stumble: float = 0.35
## Nhịp của bác chủ ruộng (giây / khóm).
@export var npc_period: float = 0.8
@export_group("Tiền công")
## Số khóm cho một nghìn đồng (cấy / làm cỏ).
@export var cells_per_thousand: float = 12.0
## Mùa gặt: số khóm cho một nghìn đồng và cho một cân gạo.
@export var reap_cells_per_thousand: float = 20.0
@export var reap_cells_per_rice: float = 45.0
## Làm ít hơn ngần này khóm thì không được công.
@export var min_cells: int = 10
@export var hours: Vector2 = Vector2(6.0, 17.5)

const KINDS := {
	"plant": {"name": "cấy lúa", "ask": "cấy", "verb": "Cấy", "anim": "plant", "hit": "Thẳng hàng!", "miss": "Lệch tay!"},
	"weed": {"name": "làm cỏ lúa", "ask": "làm cỏ", "verb": "Nhổ cỏ", "anim": "plant", "hit": "Sạch cỏ!", "miss": "Hụt tay!"},
	"reap": {"name": "gặt lúa", "ask": "gặt", "verb": "Gặt", "anim": "reap", "hit": "Ngọt tay!", "miss": "Lệch liềm!"},
}
const C_WEED := Color("#4d6b2a")

var playing: bool = false
var kind: String = ""
var phase: String = ""            # ready / work / done
var done_cells: int = 0
var npc_cells: int = 0
var streak: int = 0
var best_streak: int = 0
var misses: int = 0
var last_pay: int = 0
var last_rice: int = 0
var stats: Dictionary = {"sessions": 0}

var _t: float = 0.0
var _phi: float = 0.0             # pha nhịp 0…1, trúng nhịp ở 0,5
var _beat_used: bool = false
var _stun: float = 0.0
var _npc_t: float = 0.0
var _origin := Vector3.ZERO
var _adv := Vector3.FORWARD       # hướng luống tiến dần
var _side := Vector3.RIGHT
var _boss: Villager
var _avatar: Villager
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _cam: Camera3D
var _ui: CanvasLayer
var _top: Label
var _sub: Label
var _big: Label
var _beat_dot: ColorRect
var _zone: ColorRect
var _msg: String = ""
var _msg_t: float = 0.0
var _back_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 5454
	_cam = Camera3D.new()
	_cam.name = "FarmCam"
	_cam.fov = 60.0
	add_child(_cam)
	# Các khóm lúa / cỏ của hai luống (người chơi + bác chủ ruộng): một MultiMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.015
	mesh.bottom_radius = 0.075
	mesh.height = 1.0
	mesh.radial_segments = 5
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mesh.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = cols * rows * 2
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "WorkPlot"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.visible = false
	add_child(_mmi)
	_build_ui()


# --- Điều kiện ---------------------------------------------------------------------------------

## Việc đang có ngoài đồng theo giai đoạn của vụ ("" = không có việc thuê).
func kind_now() -> String:
	if farming == null:
		return ""
	match farming.stage_key():
		"transplant": return "plant"
		"young", "maiden": return "weed"
		"harvest": return "reap"
	return ""


## Ô ruộng gần chỗ `p` nhất: {rect, dist}.
func nearest_field(p: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	if farming == null:
		return best
	var q := Vector2(p.x, p.z)
	for o: Dictionary in farming._outer:
		var r: Rect2 = o.rect
		var c := Vector2(clampf(q.x, r.position.x, r.end.x), clampf(q.y, r.position.y, r.end.y))
		var d := c.distance_to(q)
		if d < best_d and minf(r.size.x, r.size.y) > cols * spacing * 2.0 + 6.0:
			best_d = d
			best = {"rect": r, "dist": d}
	return best


## Lý do không thuê được ("" = được). `at` là chỗ người chơi đứng.
func refusal(v: Villager, at: Vector3) -> String:
	if v == null or v.role != "farmer" or v.has_meta("proxy_of"):
		return "Việc đồng áng thì {you} hỏi các bác nông dân ấy."
	var k := kind_now()
	if k == "":
		match farming.stage_key() if farming != null else "":
			"plow": return "Ruộng đang cày bừa ngâm nước, chưa có việc gì thuê đâu {you}. Vài hôm nữa cấy thì ra giúp {self} nhé."
			"heading", "ripe": return "Lúa đang trổ, đang chín, chỉ chờ ngày gặt thôi. Mùa gặt {you} ra gặt giúp {self}!"
		return "Gặt xong cả rồi, đồng đang nghỉ. Vụ sau {you} ra làm với {self}."
	var h := day_night.time_of_day if day_night != null else 12.0
	if h < hours.x or h > hours.y:
		return "Giờ này ai còn làm đồng nữa. Sáng mai {you} ra sớm nhé."
	if weather != null and weather.rain > 0.15:
		return "Mưa thế này thì nghỉ thôi, tạnh rồi hẵng làm."
	var f := nearest_field(at)
	if f.is_empty() or float(f.dist) > field_reach:
		return "Ruộng ở ngoài đồng cơ. {You} ra bờ ruộng gặp {self} rồi {self} chỉ luống cho mà làm."
	return ""


## Câu hỏi xin làm thuê thêm vào khung thoại (nông dân, khi đồng đang có việc).
func dialog_options(v: Villager, dlg: Dialogue) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if playing or v.role != "farmer" or v.has_meta("proxy_of") or first_person == null or not first_person.active:
		return out
	var k := kind_now()
	if k == "":
		return out
	out.append({"key": "farmwork", "repeat": true, "text": "{Npc} có cần người %s thuê không{a}?" % str(KINDS[k].ask),
			"answer": func() -> String:
				var no := refusal(v, first_person.global_position)
				if no != "":
					return no
				return "Có chứ, đang thiếu người đây! Làm một buổi, %s được bao nhiêu khóm {self} trả công bấy nhiêu. Nhớ làm đều tay." % str(KINDS[k].ask),
			"next": func() -> Array[Dictionary]:
				if refusal(v, first_person.global_position) != "":
					return [{"text": "Vâng, để lúc khác{a}.", "end": true}]
				return [{"text": "(Xắn quần lội xuống ruộng)", "end": true, "then": func() -> void: start(v)},
						{"text": "Thôi, để lúc khác{a}.", "end": true}]})
	return out


# --- Bắt đầu / kết thúc -------------------------------------------------------------------------

## Xuống ruộng làm một buổi với bác `v` (bài thử truyền `force_kind` để không phụ thuộc mùa vụ).
func start(v: Villager, force_kind: String = "") -> bool:
	if playing or first_person == null:
		return false
	var k := force_kind if force_kind != "" else kind_now()
	if k == "":
		return false
	var fp := first_person.global_position
	var f := nearest_field(fp)
	if f.is_empty():
		return false
	kind = k
	var r: Rect2 = f.rect
	# Luống chạy dọc theo chiều dài ô ruộng, nằm gọn trong ruộng, gần chỗ người chơi đứng nhất
	var along_x := r.size.x >= r.size.y
	_adv = Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	_side = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var half_w := cols * spacing + 1.2            # hai luống cạnh nhau
	var length := rows * spacing
	var inner := r.grow(-2.0)
	var q := Vector2(clampf(fp.x, inner.position.x, inner.end.x), clampf(fp.z, inner.position.y, inner.end.y))
	var a := q.x if along_x else q.y              # toạ độ dọc luống
	var s := q.y if along_x else q.x              # toạ độ ngang
	var a_lo := inner.position.x if along_x else inner.position.y
	var a_hi := (inner.end.x if along_x else inner.end.y) - length
	var s_lo := (inner.position.y if along_x else inner.position.x) + half_w
	var s_hi := (inner.end.y if along_x else inner.end.x) - half_w
	a = clampf(a, a_lo, maxf(a_lo, a_hi))
	s = clampf(s, s_lo, maxf(s_lo, s_hi))
	_origin = _adv * a + _side * s + Vector3(0, 0.06, 0)
	_back_pos = fp
	playing = true
	phase = "ready"
	_t = 0.0
	done_cells = 0
	npc_cells = 0
	streak = 0
	best_streak = 0
	misses = 0
	_phi = 0.0
	_beat_used = false
	_stun = 0.0
	_npc_t = 0.0
	_msg_t = 0.0
	_fill_plot()
	_mmi.visible = true
	# Bác chủ ruộng làm luống bên cạnh
	_boss = v
	if is_instance_valid(_boss):
		_boss.set_meta("talking", true)
		_boss.set_meta("farm_work", true)
		_boss.work_anim = str(KINDS[kind].anim)
		if _boss.prop_node != null:
			_boss.prop_node.visible = false
	first_person._suspend("farm")
	if _avatar == null:
		_avatar = GameKit.make_avatar(self, villagers, dialogue, "FarmPlayer")
	_avatar.visible = true
	_avatar.work_anim = str(KINDS[kind].anim)
	_place_workers()
	if hud != null:
		hud.visible = false
	_ui.visible = true
	_cam.make_current()
	_update_camera(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


## Thôi làm (Esc giữa buổi: vẫn được trả công phần đã làm).
func stop() -> void:
	if not playing:
		return
	if phase == "work":
		_finish()
	playing = false
	phase = ""
	_mmi.visible = false
	_avatar.visible = false
	_ui.visible = false
	if hud != null:
		hud.visible = true
	if is_instance_valid(_boss):
		_boss.remove_meta("talking")
		_boss.remove_meta("farm_work")
		_boss.work_anim = "idle"
		_boss.dwell = 0.0
		if _boss.prop_node != null:
			_boss.prop_node.visible = true
	_boss = null
	first_person.global_position = _back_pos
	first_person._resume()


## Hết buổi: tính công.
func _finish() -> void:
	phase = "done"
	last_pay = 0
	last_rice = 0
	if done_cells >= min_cells:
		if kind == "reap":
			last_pay = int(round(done_cells / reap_cells_per_thousand))
			last_rice = int(done_cells / reap_cells_per_rice)
		else:
			last_pay = int(round(done_cells / cells_per_thousand))
	if inventory != null:
		if last_pay > 0:
			inventory.earn(last_pay, "làm thuê")
		if last_rice > 0:
			inventory.add("gao_tam", last_rice)
	stats.sessions = int(stats.sessions) + 1
	finished.emit(kind, done_cells, last_pay)


# --- Luống ruộng ---------------------------------------------------------------------------------

## Toạ độ khóm thứ `k` của luống `strip` (0 = người chơi, 1 = bác chủ ruộng); đi kiểu con rắn.
func cell_pos(strip: int, k: int) -> Vector3:
	var r := k / cols
	var c := k % cols
	if r % 2 == 1:
		c = cols - 1 - c
	var lateral := (float(c) - (cols - 1) * 0.5) * spacing + (-1.0 if strip == 0 else 1.0) * (cols * spacing * 0.5 + 0.6)
	return _origin + _side * lateral + _adv * (r * spacing)


func _cell_xf(strip: int, k: int, height: float) -> Transform3D:
	var p := cell_pos(strip, k)
	if height <= 0.0:
		return Transform3D(Basis.from_scale(Vector3.ZERO), p)
	var yaw := float((k * 37 + strip * 11) % 17)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(1.0, height, 1.0))
	return Transform3D(b, p + Vector3(0, height * 0.5, 0))


## Đặt khóm thứ `k` theo trạng thái đã làm / chưa làm.
func _set_cell(strip: int, k: int, done: bool) -> void:
	var i := strip * cols * rows + k
	var h := 0.0
	var col := Farming.C_YOUNG
	match kind:
		"plant":
			h = 0.26 if done else 0.0
		"weed":
			h = 0.0 if done else 0.2 + float((k * 13) % 5) * 0.03
			col = C_WEED
		"reap":
			h = 0.07 if done else 0.6
			col = Farming.C_STUBBLE if done else Farming.C_GOLD
	_mm.set_instance_transform(i, to_local_xf(_cell_xf(strip, k, h)))
	_mm.set_instance_color(i, col)


func to_local_xf(xf: Transform3D) -> Transform3D:
	return _mmi.global_transform.affine_inverse() * xf


func _fill_plot() -> void:
	for strip in 2:
		for k in cols * rows:
			_set_cell(strip, k, false)


## Chỗ đứng + hướng mặt của người làm ở khóm `k`: cấy thì đi giật lùi (mặt quay về phần đã cấy).
func _worker_xf(strip: int, k: int) -> Array:
	var face := -_adv if kind == "plant" else _adv
	var kk := mini(k, cols * rows - 1)
	return [cell_pos(strip, kk) - face * 0.42, face]


func _place_workers() -> void:
	var w := _worker_xf(0, done_cells)
	var pos: Vector3 = w[0]
	var face: Vector3 = w[1]
	_avatar.global_position = _avatar.global_position.lerp(pos, 0.35) if _avatar.global_position.distance_to(pos) < 2.0 else pos
	_avatar.rotation.y = atan2(face.x, face.z)
	if is_instance_valid(_boss):
		var wb := _worker_xf(1, npc_cells)
		var bp: Vector3 = wb[0]
		_boss.global_position = _boss.global_position.lerp(bp, 0.35) if _boss.global_position.distance_to(bp) < 2.0 else bp
		_boss.rotation.y = atan2(face.x, face.z)


# --- Điều khiển ----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event.is_action_pressed("exit_interior"):
		stop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fish_reel"):
		press()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and phase == "done":
		# Làm tiếp buổi nữa nếu còn làm được
		var boss := _boss
		var back := _back_pos
		stop()
		if boss != null and refusal(boss, back) == "":
			start(boss)
		get_viewport().set_input_as_handled()


## Chu kỳ nhịp hiện tại: càng đều tay càng nhanh.
func period() -> float:
	return lerpf(beat_period.x, beat_period.y, clampf(float(streak) / float(streak_full), 0.0, 1.0))


## Người chơi ra tay một nhịp.
func press() -> void:
	if not playing or phase != "work" or _stun > 0.0:
		return
	var off := absf(_phi - 0.5) * period()
	if off <= beat_window and not _beat_used:
		_beat_used = true
		_set_cell(0, done_cells, true)
		done_cells += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		_say("%s ×%d" % [str(KINDS[kind].hit), streak])
		if done_cells >= cols * rows:
			_finish()
	else:
		streak = 0
		misses += 1
		_stun = stumble
		_say(str(KINDS[kind].miss))


func _say(text: String) -> void:
	_msg = text
	_msg_t = 0.7


# --- Mỗi khung hình ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not playing:
		return
	var dt := minf(delta, 0.05)
	step(dt)
	if not playing:
		return
	_place_workers()
	# Dáng cúi cấy / gặt (hết buổi thì đứng thẳng lên); bác chủ ruộng: ghi đè dáng "trò chuyện" của Villagers
	var anim := str(KINDS[kind].anim) if phase == "work" else "idle"
	_avatar.work_anim = anim
	_avatar._walk_amount = 0.0
	GameKit.animate_owned(_avatar, self, _avatar, dt)
	if is_instance_valid(_boss):
		_boss.work_anim = anim
		_boss._walk_amount = 0.0
		_boss._animate(0.0)
	_update_camera(dt)
	_update_ui()


## Một bước mô phỏng (bài thử gọi thẳng).
func step(dt: float) -> void:
	_t += dt
	_msg_t = maxf(_msg_t - dt, 0.0)
	_stun = maxf(_stun - dt, 0.0)
	match phase:
		"ready":
			if _t >= 2.5:
				phase = "work"
				_t = 0.0
		"work":
			_phi += dt / period()
			if _phi >= 1.0:
				_phi -= 1.0
				_beat_used = false
			# Bác chủ ruộng làm đều tay
			_npc_t += dt
			if _npc_t >= npc_period and npc_cells < cols * rows:
				_npc_t -= npc_period
				_set_cell(1, npc_cells, true)
				npc_cells += 1
			if _t >= work_seconds:
				_finish()
			# Trời đổ mưa / hết giờ làm thì nghỉ sớm
			elif weather != null and weather.rain > 0.5:
				_finish()


func _update_camera(dt: float) -> void:
	var face := -_adv if kind == "plant" else _adv
	var at := _avatar.global_position
	var want := at - face * 3.4 + Vector3(0, 2.6, 0) + _side * 1.6
	var k := 1.0 - exp(-5.0 * dt)
	_cam.global_position = _cam.global_position.lerp(want, k) if dt < 0.9 else want
	_cam.look_at(at + face * 1.3 + _side * 0.9 + Vector3(0, 0.3, 0), Vector3.UP)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	var box := GameKit.top_panel(_ui)
	_top = GameKit.label(true, 24, Palette.HUD_TEXT)
	_sub = GameKit.label(false, 16, Palette.HUD_SUBTEXT)
	box.add_child(_top)
	box.add_child(_sub)
	# Thước nhịp: chấm trắng chạy, vùng vàng = lúc ra tay
	var beat := GameKit.bar(box)
	_zone = ColorRect.new()
	_zone.color = Color(Palette.FLOWER_YELLOW, 0.6)
	_zone.size = Vector2(40, 14)
	beat.add_child(_zone)
	_beat_dot = ColorRect.new()
	_beat_dot.color = Color.WHITE
	_beat_dot.size = Vector2(6, 14)
	beat.add_child(_beat_dot)
	box.add_child(GameKit.label(false, 15, Palette.HUD_SUBTEXT,
			"Space / chuột trái: ra tay ĐÚNG NHỊP (chấm trắng vào vùng vàng)  ·  đều tay thì nhịp nhanh dần  ·  Esc: nghỉ"))
	_big = GameKit.big_label(_ui, 56, -300, 12)


func _update_ui() -> void:
	var info: Dictionary = KINDS[kind]
	_top.text = "Làm thuê: %s  ·  %d khóm  ·  còn %d giây" % [str(info.name), done_cells,
			maxi(0, int(ceil(work_seconds - _t))) if phase == "work" else int(work_seconds)]
	_sub.text = "Đều tay ×%d (dài nhất ×%d)  ·  lệch %d lần  ·  bác chủ ruộng: %d khóm" % [streak, best_streak, misses, npc_cells]
	var p := period()
	var zw := 320.0 * 2.0 * beat_window / p
	_zone.size.x = zw
	_zone.position.x = 160.0 - zw * 0.5
	_beat_dot.position.x = 320.0 * _phi - 3.0
	_beat_dot.color = Color.WHITE if _stun <= 0.0 else Palette.FLAG_RED
	match phase:
		"ready":
			_big.text = "Xuống ruộng… %d" % maxi(1, 3 - int(_t))
		"work":
			_big.text = _msg if _msg_t > 0.0 else ""
		"done":
			var pay := "Chưa được %d khóm — chưa có công." % min_cells
			if last_pay > 0 or last_rice > 0:
				pay = "Tiền công: %d nghìn đồng" % last_pay
				if last_rice > 0:
					pay += " + %d cân gạo tám" % last_rice
			_big.text = "Hết buổi! %s được %d khóm (bác chủ %d)\n%s\nE: làm buổi nữa  ·  Esc: nghỉ" % [str(info.verb), done_cells, npc_cells, pay]
		_:
			_big.text = ""
