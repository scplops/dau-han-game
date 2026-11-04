class_name Hud
extends CanvasLayer
## HUD tối giản: góc trên trái là giờ + buổi trong ngày; dưới cùng là phím tắt;
## giữa phía dưới là gợi ý khi rê chuột vào cửa; trong nhà có nút "Ra sân" góc trên phải.
## Phím H ẩn/hiện. Font Be Vietnam Pro (đủ dấu tiếng Việt).

signal exit_requested

@export var day_night: DayNight
@export var weather: Weather
@export var show_fps: bool = true
@export var time_font_size: int = 34
@export var text_font_size: int = 15

const FONT_REGULAR := "res://assets/fonts/BeVietnamPro-Regular.ttf"
const FONT_SEMIBOLD := "res://assets/fonts/BeVietnamPro-SemiBold.ttf"
const SHORTCUTS_OUT := "Chuột phải: xoay    Lăn chuột: zoom    Chuột giữa / WASD: di chuyển    Bấm cửa, chỗ câu / E: vào nhà, ngồi câu    Bấm người: xem tin    Bấm bóng: sút    P: phối cảnh / trực giao    [ ]: chỉnh giờ    T: tự chạy giờ    R: đổi thời tiết    V: nhập vai    M: bản đồ    H: ẩn / hiện"
const SHORTCUTS_FISH := "Giữ chuột trái / Space: lấy đà, cuộn dây    Thả: quăng cần, nhả dây    Chuột phải: xoay    Lăn chuột: zoom    Esc / E: thôi câu    [ ]: chỉnh giờ    T: tự chạy giờ    R: đổi thời tiết    H: ẩn / hiện"
const SHORTCUTS_FP := "Chuột: nhìn    WASD: đi    Shift: chạy    Space: nhảy    E / chuột trái: tương tác    V / Esc: thôi nhập vai    [ ]: chỉnh giờ    T: tự chạy giờ    R: đổi thời tiết    M: bản đồ    H: ẩn / hiện"
const SHORTCUTS_FP_IN := "Chuột: nhìn    WASD: đi    Shift: chạy    E / chuột trái: tương tác    Esc / bước ra cửa: ra sân    V: xem kiểu nhà búp bê    [ ]: chỉnh giờ    H: ẩn / hiện"
const SHORTCUTS_BOAT := "W / S: chèo tới / lùi    A / D: rẽ    Shift: chèo nhanh    Chuột phải: xoay    Lăn chuột: zoom    E / Esc: lên bờ (khi sát bờ)    [ ]: chỉnh giờ    T: tự chạy giờ    R: đổi thời tiết    M: bản đồ    H: ẩn / hiện"
const SHORTCUTS_IN := "Chuột phải: xoay    Lăn chuột: zoom    Chuột giữa / WASD: di chuyển    Esc / E: ra sân    P: phối cảnh / trực giao    [ ]: chỉnh giờ    T: tự chạy giờ    R: đổi thời tiết    H: ẩn / hiện"

var _time_label: Label
var _info_label: Label
var _keys_label: Label
var _keys_panel: PanelContainer
var _hint_panel: PanelContainer
var _hint_label: Label
var _exit_button: Button
var _info_panel: PanelContainer
var _info_title: Label
var _info_body: Label
var _inside: bool = false
var _place: String = ""
var _fish_place: String = ""
var _first_person: bool = false
var _boat: bool = false
var _refresh: float = 0.0


func _ready() -> void:
	var regular := load(FONT_REGULAR) as Font
	var semibold := load(FONT_SEMIBOLD) as Font

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Góc trên trái: giờ
	var top := _panel()
	top.position = Vector2(20, 18)
	root.add_child(top)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	top.add_child(box)
	_time_label = _label(semibold, time_font_size, Palette.HUD_TEXT)
	box.add_child(_time_label)
	_info_label = _label(regular, text_font_size, Palette.HUD_SUBTEXT)
	box.add_child(_info_label)

	# Dưới cùng: phím tắt, tự xuống dòng khi cửa sổ hẹp
	var bottom := _panel()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -16
	root.add_child(bottom)
	_keys_panel = bottom
	_keys_label = _label(regular, text_font_size, Palette.HUD_TEXT)
	_keys_label.text = SHORTCUTS_OUT
	_keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_keys_label)
	_fit_bottom(bottom, _keys_label)
	get_viewport().size_changed.connect(func() -> void: _fit_bottom(_keys_panel, _keys_label))

	# Gợi ý khi rê chuột vào cửa (giữa, phía trên dải phím tắt)
	_hint_panel = _panel()
	_hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_panel.offset_bottom = -80
	_hint_panel.visible = false
	root.add_child(_hint_panel)
	_hint_label = _label(semibold, text_font_size + 3, Palette.HUD_TEXT)
	_hint_panel.add_child(_hint_label)

	# Nút ra sân (chỉ hiện khi ở trong nhà)
	_exit_button = Button.new()
	_exit_button.text = "Ra sân  (Esc)"
	_exit_button.focus_mode = Control.FOCUS_NONE
	_exit_button.add_theme_font_override("font", semibold)
	_exit_button.add_theme_font_size_override("font_size", text_font_size + 2)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.HUD_BG if state == "normal" else Color(Palette.HUD_BG, 0.8)
		if state == "hover":
			sb.border_color = Palette.WINDOW_GLOW
			sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		_exit_button.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		_exit_button.add_theme_color_override(c, Palette.HUD_TEXT)
	_exit_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_exit_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_exit_button.offset_right = -20
	_exit_button.offset_top = 18
	_exit_button.visible = false
	_exit_button.pressed.connect(func() -> void: exit_requested.emit())
	root.add_child(_exit_button)

	# Khung thông tin NPC đang chọn (góc trên phải)
	_info_panel = _panel()
	_info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_info_panel.offset_right = -20
	_info_panel.offset_top = 18
	_info_panel.custom_minimum_size.x = 300
	_info_panel.visible = false
	root.add_child(_info_panel)
	var ib := VBoxContainer.new()
	ib.add_theme_constant_override("separation", 2)
	_info_panel.add_child(ib)
	_info_title = _label(semibold, text_font_size + 7, Palette.HUD_TEXT)
	ib.add_child(_info_title)
	_info_body = _label(regular, text_font_size, Palette.HUD_SUBTEXT)
	ib.add_child(_info_body)

	_update_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud"):
		visible = not visible


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_update_text()


func _update_text() -> void:
	if day_night == null:
		return
	_time_label.text = day_night.time_text()
	var where := ((_place if _place != "" else "Trong nhà") if _inside
			else ("Trên đò" if _boat else (_fish_place if _fish_place != "" else ("Nhập vai" if _first_person else "Ngoài sân"))))
	var parts: Array[String] = [where, _period_name(day_night.time_of_day)]
	if weather != null:
		parts.append(weather.display_name())
	parts.append("Tự chạy: bật" if day_night.auto_run else "Tự chạy: tắt")
	if show_fps:
		parts.append("%d FPS" % Engine.get_frames_per_second())
	_info_label.text = "  ·  ".join(parts)


## Đổi giao diện khi vào / ra nhà.
func set_inside(value: bool, place: String = "") -> void:
	_inside = value
	_place = place
	if _exit_button == null:
		return
	_exit_button.visible = value
	if value:
		hide_info()
	_keys_label.text = SHORTCUTS_IN if value else SHORTCUTS_OUT
	_fit_bottom(_keys_panel, _keys_label)
	set_hint("")
	_update_text()


## Đổi giao diện khi bắt đầu / thôi câu cá (`place` = tên bến, rỗng = thôi câu).
func set_fishing(place: String) -> void:
	_fish_place = place
	if _keys_label == null:
		return
	_keys_label.text = SHORTCUTS_FISH if place != "" else (SHORTCUTS_IN if _inside else SHORTCUTS_OUT)
	_fit_bottom(_keys_panel, _keys_label)
	if place != "":
		hide_info()
	set_hint("")
	_update_text()


## Đổi giao diện khi bật / tắt nhập vai góc nhìn thứ nhất.
func set_first_person(on: bool) -> void:
	_first_person = on
	if _keys_label == null:
		return
	if on:
		_keys_label.text = SHORTCUTS_FP_IN if _inside else SHORTCUTS_FP
	else:
		_keys_label.text = SHORTCUTS_IN if _inside else SHORTCUTS_OUT
	_exit_button.visible = _inside and not on   # đi bộ trong nhà: chuột bị giữ, ra bằng Esc / cửa
	_fit_bottom(_keys_panel, _keys_label)
	_update_text()


## Đổi giao diện khi lên / xuống đò (mục 24).
func set_boat(on: bool) -> void:
	_boat = on
	if _keys_label == null:
		return
	if on:
		_keys_label.text = SHORTCUTS_BOAT
		hide_info()
	else:
		_keys_label.text = SHORTCUTS_FP if _first_person else SHORTCUTS_OUT
	_fit_bottom(_keys_panel, _keys_label)
	_update_text()


## Font dùng chung cho các khung khác (mini-game).
static func font(semibold: bool) -> Font:
	return load(FONT_SEMIBOLD if semibold else FONT_REGULAR) as Font


## Hiện khung thông tin (tên + các dòng mô tả).
func show_info(title: String, lines: Array[String]) -> void:
	if _info_panel == null:
		return
	_info_title.text = title
	_info_body.text = "\n".join(lines)
	_info_panel.visible = not _inside


func hide_info() -> void:
	if _info_panel != null:
		_info_panel.visible = false


## Gợi ý giữa màn hình (rỗng = ẩn).
func set_hint(text: String) -> void:
	if _hint_panel == null:
		return
	_hint_label.text = text
	_hint_panel.visible = text != ""
	_hint_panel.reset_size()
	_hint_panel.offset_left = -_hint_panel.size.x * 0.5
	_hint_panel.offset_right = _hint_panel.size.x * 0.5


static func _period_name(h: float) -> String:
	if h < 5.0:
		return "Đêm khuya"
	if h < 7.0:
		return "Bình minh"
	if h < 11.0:
		return "Buổi sáng"
	if h < 13.0:
		return "Buổi trưa"
	if h < 17.0:
		return "Buổi chiều"
	if h < 18.5:
		return "Chiều muộn"
	if h < 19.5:
		return "Hoàng hôn"
	return "Buổi tối"


## Khung phím tắt: rộng tối đa 92% màn hình, chữ tự xuống dòng.
func _fit_bottom(panel: PanelContainer, label: Label) -> void:
	var w := get_viewport().get_visible_rect().size.x
	var natural := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size("font_size")).x + 40.0
	var target := minf(natural, w * 0.92)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if natural > w * 0.92 else TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = target - 32.0
	panel.offset_left = -target * 0.5
	panel.offset_right = target * 0.5


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


func _label(font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l
