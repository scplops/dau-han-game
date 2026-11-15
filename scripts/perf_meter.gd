class_name PerfMeter
extends CanvasLayer
## Đo hiệu năng trên máy người chơi (mục 59) — máy cloud dựng hình bằng phần mềm nên không đo được FPS thật.
## - F3 (`toggle_perf`): bảng nhỏ góc trên phải — FPS, thời gian khung (trung bình / khung chậm nhất gần đây), số lệnh vẽ,
##   số tam giác, số vật thể, mức đồ hoạ.
## - F4 (`run_benchmark`): bài đo tự động ở chế độ ngắm cảnh — với từng mức đồ hoạ (Nhẹ, Vừa, Cao) camera lần lượt tới 4 góc
##   nhìn (nhà mình, cổng làng, giữa làng, cả làng từ xa), xoay chậm `bench_seconds` giây mỗi góc; xong hiện bảng kết quả
##   (FPS trung bình, 1 % khung chậm nhất), gợi ý nên dùng mức nào, và ghi thêm vào file `out_path`. Esc: huỷ / đóng bảng.

signal benchmark_done(results: Array)

const VIEWS: Array = [["Nhà mình", Vector3(0, 0, 0), 28.0], ["Cổng làng", Vector3(0, 0, -45), 40.0],
		["Giữa làng", Vector3(0, 0, -100), 60.0], ["Cả làng từ xa", Vector3(0, 0, -100), 150.0]]

@export var outdoor_rig: CameraRig
@export var graphics: Graphics
@export var first_person: FirstPerson
@export var house_entry: HouseEntry
@export var hud: Hud
## Thời gian đo mỗi góc nhìn (giây) và thời gian chờ cảnh ổn định trước khi đo.
@export var bench_seconds: float = 4.0
@export var settle_seconds: float = 1.0
## Camera xoay bao nhiêu độ mỗi giây trong lúc đo.
@export var spin_deg: float = 14.0
## FPS trung bình từ ngần này trở lên thì coi là mượt (để gợi ý mức đồ hoạ).
@export var target_fps: float = 50.0
@export var out_path: String = "user://benchmark.txt"

var overlay: bool = false
var running: bool = false
## Kết quả bài đo gần nhất: [{quality, view, avg, low, frames}].
var results: Array = []
var recommended: int = -1
var _frames: PackedFloat32Array = PackedFloat32Array()   # thời gian các khung gần đây (bảng F3)
var _panel: PanelContainer
var _text: Label
var _result_panel: PanelContainer
var _result_text: RichTextLabel
var _status: Label
var _level: int = 0
var _view: int = 0
var _t: float = 0.0
var _samples: PackedFloat32Array = PackedFloat32Array()
var _saved := {}


func _ready() -> void:
	layer = 20
	_panel = _make_panel(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -330.0
	_panel.offset_top = 70.0
	_panel.offset_right = -20.0
	_text = GameKit.label(false, 15, Palette.HUD_TEXT)
	_panel.add_child(_text)
	_panel.visible = false
	_status = GameKit.label(true, 22, Palette.FLOWER_YELLOW)
	_status.add_theme_color_override("font_outline_color", Palette.WINDOW_DARK)
	_status.add_theme_constant_override("outline_size", 6)
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.offset_top = 20.0
	_status.visible = false
	add_child(_status)
	_result_panel = _make_panel(Control.PRESET_CENTER)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_text = RichTextLabel.new()
	_result_text.bbcode_enabled = true
	_result_text.fit_content = true
	_result_text.custom_minimum_size = Vector2(640, 0)
	_result_text.add_theme_font_override("normal_font", Hud.font(false))
	_result_text.add_theme_font_override("bold_font", Hud.font(true))
	_result_text.add_theme_font_size_override("normal_font_size", 17)
	_result_text.add_theme_font_size_override("bold_font_size", 17)
	_result_text.add_theme_color_override("default_color", Palette.HUD_TEXT)
	_result_panel.add_child(_result_text)
	_result_panel.visible = false


func _make_panel(preset: Control.LayoutPreset) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 0.72)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(preset)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_perf"):
		overlay = not overlay
		_panel.visible = overlay
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("run_benchmark"):
		if running:
			cancel()
		elif _result_panel.visible:
			_result_panel.visible = false
		else:
			start_benchmark()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("exit_interior") and (running or _result_panel.visible):
		if running:
			cancel()
		_result_panel.visible = false
		get_viewport().set_input_as_handled()


## Vì sao chưa đo được ("" = đo được): bài đo cần camera ngắm cảnh ngoài sân.
func blocked() -> String:
	if outdoor_rig == null:
		return "không có camera ngắm cảnh"
	if first_person != null and first_person.active:
		return "Thôi nhập vai (V) rồi hãy bấm F4 để đo"
	if house_entry != null and house_entry.inside:
		return "Ra sân rồi hãy bấm F4 để đo"
	return ""


func start_benchmark() -> bool:
	var why := blocked()
	if why != "":
		_status.text = why
		_status.visible = true
		_t = -2.5              # hiện lời nhắc một lúc
		return false
	running = true
	results = []
	recommended = -1
	_result_panel.visible = false
	_saved = {"focus": outdoor_rig._target_focus, "yaw": outdoor_rig.yaw_deg, "distance": outdoor_rig.distance,
			"active": outdoor_rig.active, "quality": graphics.quality if graphics != null else -1,
			"hud": hud.visible if hud != null else true}
	outdoor_rig.active = false
	if hud != null:
		hud.visible = false
	_level = 0
	_view = 0
	_begin_view()
	return true


func cancel() -> void:
	if not running:
		return
	running = false
	_restore()
	_status.visible = false


func _restore() -> void:
	outdoor_rig.set_focus(_saved.focus as Vector3)
	outdoor_rig.yaw_deg = float(_saved.yaw)
	outdoor_rig.distance = float(_saved.distance)
	outdoor_rig.snap()
	outdoor_rig.active = bool(_saved.active)
	if graphics != null and int(_saved.quality) >= 0:
		graphics.set_quality(int(_saved.quality))
	if hud != null:
		hud.visible = bool(_saved.hud)


func _levels() -> int:
	return Graphics.NAMES.size() if graphics != null else 1


func _begin_view() -> void:
	if graphics != null:
		graphics.set_quality(_level)
	var v: Array = VIEWS[_view]
	outdoor_rig.set_focus(v[1] as Vector3)
	outdoor_rig.distance = float(v[2])
	outdoor_rig.yaw_deg = 0.0
	outdoor_rig.snap()
	_t = 0.0
	_samples = PackedFloat32Array()


func _process(delta: float) -> void:
	_frames.append(delta)
	if _frames.size() > 120:
		_frames = _frames.slice(_frames.size() - 120)
	if overlay:
		_update_overlay()
	if not running:
		# Lời nhắc "thôi nhập vai rồi hãy đo" tự tắt
		if _status.visible:
			_t += delta
			if _t >= 0.0:
				_status.visible = false
		return
	_t += delta
	outdoor_rig.yaw_deg = wrapf(outdoor_rig.yaw_deg + spin_deg * delta, -180.0, 180.0)
	outdoor_rig.snap()
	_status.visible = true
	var done_n := _level * VIEWS.size() + _view
	_status.text = "Đang đo hiệu năng %d / %d  ·  mức %s  ·  %s   (Esc: huỷ)" % [done_n + 1, _levels() * VIEWS.size(),
			Graphics.NAMES[_level] if graphics != null else "—", str(VIEWS[_view][0])]
	if _t < settle_seconds:
		return
	_samples.append(delta)
	if _t >= settle_seconds + bench_seconds:
		results.append(summarize(_level, str(VIEWS[_view][0]), _samples))
		_view += 1
		if _view >= VIEWS.size():
			_view = 0
			_level += 1
		if _level >= _levels():
			_finish()
		else:
			_begin_view()


## Tóm tắt một lượt đo: FPS trung bình và FPS của 1 % khung chậm nhất.
static func summarize(level: int, view: String, samples: PackedFloat32Array) -> Dictionary:
	var total := 0.0
	for d in samples:
		total += d
	var sorted := Array(samples)
	sorted.sort()
	var n := sorted.size()
	var worst := maxi(1, int(ceil(n * 0.01)))
	var slow := 0.0
	for i in worst:
		slow += float(sorted[n - 1 - i])
	return {"quality": level, "view": view, "frames": n, "avg": float(n) / maxf(total, 0.0001) if n > 0 else 0.0,
			"low": float(worst) / maxf(slow, 0.0001) if n > 0 else 0.0}


## FPS trung bình của một mức đồ hoạ qua mọi góc nhìn (lấy góc CHẬM NHẤT — chỗ nặng nhất mới là chỗ người chơi thấy giật).
func level_fps(level: int) -> float:
	var worst := INF
	for r: Dictionary in results:
		if int(r.quality) == level:
			worst = minf(worst, float(r.avg))
	return worst if worst < INF else 0.0


func _finish() -> void:
	running = false
	_status.visible = false
	_restore()
	# Mức cao nhất mà góc nặng nhất vẫn đạt `target_fps`; không mức nào đạt thì mức Nhẹ
	recommended = 0
	for lv in _levels():
		if level_fps(lv) >= target_fps:
			recommended = lv
	_result_text.text = report(true)
	_result_panel.visible = true
	var f := FileAccess.open(out_path, FileAccess.READ_WRITE) if FileAccess.file_exists(out_path) else FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_string(report(false) + "\n")
		f.close()
	benchmark_done.emit(results)


## Bảng kết quả (bbcode = true: để hiện trong game; false: chữ thường để ghi file).
func report(bbcode: bool) -> String:
	var b0 := "[b]" if bbcode else ""
	var b1 := "[/b]" if bbcode else ""
	var size := DisplayServer.window_get_size()
	var lines: Array[String] = []
	lines.append("%sKết quả đo hiệu năng%s  ·  %s  ·  %d × %d  ·  %s" % [b0, b1, Time.get_datetime_string_from_system(false, true),
			size.x, size.y, RenderingServer.get_video_adapter_name()])
	lines.append("")
	for lv in _levels():
		var parts: Array[String] = []
		for r: Dictionary in results:
			if int(r.quality) == lv:
				parts.append("%s %.0f (chậm nhất %.0f)" % [str(r.view), float(r.avg), float(r.low)])
		lines.append("%sMức %s%s — FPS: %s" % [b0, Graphics.NAMES[lv] if graphics != null else "—", b1, "  ·  ".join(parts)])
	lines.append("")
	if recommended >= 0 and graphics != null:
		var fps := level_fps(recommended)
		if fps >= target_fps:
			lines.append("%sNên dùng mức %s%s (góc nặng nhất vẫn đạt %.0f FPS). Bấm G để đổi mức." % [b0, Graphics.NAMES[recommended], b1, fps])
		else:
			lines.append("%sMáy hơi yếu%s: ngay mức Nhẹ góc nặng nhất chỉ %.0f FPS. Dùng mức Nhẹ (G), thu nhỏ cửa sổ, hoặc chạy bằng Compatibility." % [b0, b1, fps])
	if bbcode:
		lines.append("")
		lines.append("Đã ghi vào %s  ·  F4 / Esc: đóng" % ProjectSettings.globalize_path(out_path))
	return "\n".join(lines)


func _update_overlay() -> void:
	var total := 0.0
	var worst := 0.0
	for d in _frames:
		total += d
		worst = maxf(worst, d)
	var avg := total / maxf(float(_frames.size()), 1.0)
	_text.text = "FPS %d   ·   khung %.1f ms (chậm nhất %.1f ms)\nLệnh vẽ %d   ·   tam giác %s   ·   vật thể %d\nMức đồ hoạ: %s (G)   ·   F4: đo tự động" % [
			int(Performance.get_monitor(Performance.TIME_FPS)), avg * 1000.0, worst * 1000.0,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			_thousands(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			Graphics.NAMES[graphics.quality] if graphics != null else "—"]


static func _thousands(n: int) -> String:
	if n >= 1000000:
		return "%.2f triệu" % (n / 1000000.0)
	if n >= 1000:
		return "%d nghìn" % (n / 1000)
	return str(n)
