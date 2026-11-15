class_name HelpGuide
extends CanvasLayer
## Trợ giúp + hướng dẫn nhập môn (mục 52).
## - Phím F1 (`toggle_help`): bảng trợ giúp giữa màn hình, các trang phím theo từng hoạt động (cơ bản, nhập vai, dân làng,
##   chợ & túi đồ, sông nước, đá bóng, trò dân gian, thời gian). A / D hoặc bấm mục để lật trang, F1 / Esc đóng,
##   E bật / tắt hướng dẫn nhập môn.
## - Hướng dẫn nhập môn: khung nhỏ bên trái màn hình, từng bước một (xoay camera → nhập vai → đi lại → trò chuyện → túi đồ
##   → bản đồ → sổ tay → trợ giúp); làm xong bước nào thì tự sang bước sau. Xong hết (hoặc tắt) thì lưu lại cùng game.
##   Chạy bằng `-s` (bài thử, chụp ảnh) thì không hiện, trừ khi `force_guide`.

signal step_done(index: int)

@export var first_person: FirstPerson
@export var outdoor_rig: CameraRig
@export var dialogue: Dialogue
@export var inventory: Inventory
@export var notebook: Notebook
@export var minimap: MiniMap
@export var hud: Hud
## Bật hướng dẫn cả khi chạy bằng `-s` (bài thử).
@export var force_guide: bool = false
## Đi bao nhiêu mét thì xong bước "đi lại".
@export var walk_goal: float = 12.0

const PAGES: Array[String] = ["Cơ bản", "Nhập vai", "Dân làng", "Chợ & túi đồ", "Sông nước", "Đá bóng", "Trò dân gian", "Thời gian"]
## Các bước hướng dẫn: [việc cần làm, gợi ý thêm].
const STEPS: Array = [
	["Giữ chuột phải rồi kéo để xoay, lăn chuột để phóng to / thu nhỏ", "Chuột giữa hoặc W A S D để dời chỗ nhìn."],
	["Nhấn V để nhập vai — xuống đi bộ trong làng", "Nhấn V lần nữa (hoặc Esc) để quay lại ngắm cảnh từ trên cao."],
	["Dùng W A S D để đi, giữ Shift để chạy — đi thử một quãng", "Di chuột để nhìn quanh. Space để nhảy."],
	["Nhìn vào một người dân rồi nhấn E để trò chuyện", "Chọn câu hỏi bằng phím 1–4. Ai có dấu ! vàng trên đầu là đang cần giúp."],
	["Nhấn I để mở túi đồ", "Trong túi có tiền và đồ; chọn món rồi nhấn E để dùng. I hoặc Esc để gấp lại."],
	["Nhấn M để mở bản đồ lớn", "Trên bản đồ có chợ, sân bóng, bến sông, trường học. Nhấn M tiếp để đổi cỡ / ẩn."],
	["Nhấn B để mở sổ tay", "Sổ tay ghi kỷ lục, cá đã câu, người quen, việc đang làm."],
	["Nhấn F1 để xem mọi phím và mọi trò trong làng", "Quên phím lúc nào cũng nhấn F1 được."],
]

var open: bool = false
var page: int = 0
## Bước hướng dẫn hiện tại; = STEPS.size() là đã xong.
var step: int = 0
var guide_on: bool = true
var _root: Control
var _tabs: Array[Button] = []
var _body: RichTextLabel
var _foot: Label
var _guide_panel: PanelContainer
var _guide_title: Label
var _guide_text: Label
var _guide_tip: Label
var _from_fp: bool = false
var _rig_was_active: bool = false
var _yaw0: float = 0.0
var _dist0: float = 0.0
var _walked: float = 0.0
var _last_pos := Vector3.INF
var _flash: float = 0.0
var _scripted: bool = false


func _ready() -> void:
	layer = 17
	var args := OS.get_cmdline_args()
	_scripted = args.has("-s") or args.has("--script")
	_build()
	_root.visible = false
	if outdoor_rig != null:
		_yaw0 = outdoor_rig.yaw_deg
		_dist0 = outdoor_rig.distance
	_update_guide()


## Hướng dẫn đã xong hoặc đã tắt (SaveGame lưu / nạp).
func done() -> bool:
	return not guide_on or step >= STEPS.size()


func set_done(v: bool) -> void:
	if v:
		step = STEPS.size()
	_update_guide()


func _guide_active() -> bool:
	return guide_on and step < STEPS.size() and (force_guide or not _scripted)


# --- Hướng dẫn nhập môn -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	if not _guide_active():
		if _guide_panel.visible and _flash <= 0.0:
			_guide_panel.visible = false
		return
	if _step_complete(step):
		step_done.emit(step)
		step += 1
		_flash = 2.5 if step >= STEPS.size() else 0.0
		# Bỏ qua những bước đã làm sẵn (vd. đang nhập vai thì không cần học xoay camera)
		while step < STEPS.size() and step <= 1 and _step_complete(step):
			step += 1
	_update_guide()


func _step_complete(i: int) -> bool:
	var fp_on := first_person != null and first_person.active
	match i:
		0:
			if fp_on:
				return true
			return outdoor_rig != null and (absf(angle_difference(deg_to_rad(outdoor_rig.yaw_deg), deg_to_rad(_yaw0))) > 0.3
					or absf(outdoor_rig.distance - _dist0) > 3.0)
		1:
			return fp_on
		2:
			if not fp_on:
				_last_pos = Vector3.INF
				return false
			var p := first_person.global_position
			if _last_pos != Vector3.INF and p.distance_to(_last_pos) < 3.0:
				_walked += Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
			_last_pos = p
			return _walked >= walk_goal
		3:
			return dialogue != null and (dialogue.talking or not dialogue._met.is_empty())
		4:
			return inventory != null and inventory.open
		5:
			return minimap != null and minimap.mode == MiniMap.Mode.LARGE
		6:
			return notebook != null and notebook.open
		7:
			return open
	return true


func _update_guide() -> void:
	if _guide_panel == null:
		return
	var show := _guide_active() or _flash > 0.0
	# Ẩn khi HUD chung ẩn (đang chơi một trò có giao diện riêng) hoặc đang mở bảng khác
	if hud != null and not hud.visible:
		show = false
	if open or (notebook != null and notebook.open) or (inventory != null and inventory.open) or (dialogue != null and dialogue.talking):
		show = false
	_guide_panel.visible = show
	if not show:
		return
	if step >= STEPS.size():
		_guide_title.text = "Xong hướng dẫn!"
		_guide_text.text = "Giờ thì cứ dạo quanh làng: ra chợ phiên, câu cá, chèo đò, đá bóng…"
		_guide_tip.text = "Nhấn F1 bất cứ lúc nào để xem lại phím."
		return
	_guide_title.text = "Hướng dẫn  ·  bước %d / %d" % [step + 1, STEPS.size()]
	_guide_text.text = str(STEPS[step][0])
	var tip := str(STEPS[step][1])
	if step == 2:
		tip += "  (%d / %d m)" % [int(_walked), int(walk_goal)]
	_guide_tip.text = tip + "\nF1 rồi E: tắt hướng dẫn."


# --- Bảng trợ giúp -----------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		if open:
			close()
		else:
			show_help()
		get_viewport().set_input_as_handled()
		return
	if not open:
		return
	if event.is_action_pressed("exit_interior"):
		close()
	elif event.is_action_pressed("cam_left"):
		set_page((page + PAGES.size() - 1) % PAGES.size())
	elif event.is_action_pressed("cam_right"):
		set_page((page + 1) % PAGES.size())
	elif event.is_action_pressed("interact"):
		guide_on = not guide_on
		if guide_on and step >= STEPS.size():
			step = 0                    # bật lại sau khi đã xong: học lại từ đầu
			_walked = 0.0
		_refresh_foot()
	elif not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()


## Mở bảng trợ giúp (không mở khi đang trò chuyện / đang mở sổ tay, túi đồ / đang chơi một trò).
func show_help() -> bool:
	if open or (dialogue != null and dialogue.talking) or (notebook != null and notebook.open) or (inventory != null and inventory.open):
		return false
	_from_fp = first_person != null and first_person.active
	if _from_fp:
		if first_person._suspended != "":
			return false
		first_person._suspend("help")
	open = true
	_root.visible = true
	if outdoor_rig != null and not _from_fp:
		_rig_was_active = outdoor_rig.active
		outdoor_rig.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Mở đúng trang hợp với việc đang làm
	set_page(1 if _from_fp else page)
	return true


func close() -> void:
	if not open:
		return
	open = false
	_root.visible = false
	if outdoor_rig != null and not _from_fp:
		outdoor_rig.active = _rig_was_active
	if _from_fp and first_person != null and first_person._suspended == "help":
		first_person._resume()


func set_page(i: int) -> void:
	page = i
	for k in _tabs.size():
		_tabs[k].button_pressed = k == i
	_body.text = page_text(i)
	_body.scroll_to_line(0)
	_refresh_foot()


func _refresh_foot() -> void:
	_foot.text = "A / D hoặc bấm mục: lật trang   ·   F1 / Esc: đóng   ·   E: %s hướng dẫn nhập môn" % ("tắt" if guide_on and step < STEPS.size() else "bật lại")


static func _key(k: String, what: String) -> String:
	return "[b]%s[/b]   %s\n" % [k, what]


static func _head(t: String) -> String:
	return "[color=#%s][b]%s[/b][/color]\n" % [Notebook.ACCENT.to_html(false), t]


func page_text(i: int) -> String:
	var t := ""
	match i:
		0:
			t += _head("Ngắm cảnh từ trên cao")
			t += _key("Chuột phải kéo", "xoay quanh chỗ đang nhìn")
			t += _key("Lăn chuột", "phóng to / thu nhỏ")
			t += _key("Chuột giữa kéo, W A S D", "dời chỗ nhìn")
			t += _key("P", "đổi phối cảnh / trực giao")
			t += _key("Bấm chuột trái", "vào cửa nhà, ngồi câu cá, xem tin một người, sút bóng, chèo đò")
			t += "\n" + _head("Bảng và màn hình")
			t += _key("V", "nhập vai — xuống đi bộ trong làng")
			t += _key("M", "bản đồ: nhỏ → lớn → ẩn")
			t += _key("B", "sổ tay (kỷ lục, cá, người quen, việc)")
			t += _key("I", "túi đồ và tiền")
			t += _key("F1", "bảng trợ giúp này")
			t += _key("H", "ẩn / hiện chữ trên màn hình")
			t += _key("G", "mức đồ hoạ: Nhẹ / Vừa / Cao      [b]N[/b]  tắt / bật tiếng")
		1:
			t += _head("Đi lại")
			t += _key("Chuột", "nhìn quanh (bấm vào cửa sổ game nếu chuột chưa bị giữ)")
			t += _key("W A S D", "đi      [b]Shift[/b]  chạy      [b]Space[/b]  nhảy")
			t += _key("V hoặc Esc", "thôi nhập vai, về ngắm cảnh")
			t += "\n" + _head("Tương tác — nhìn vào rồi nhấn E")
			t += _key("Cửa nhà, đình, chùa, lớp học", "vào trong đi bộ; bước ra cửa hoặc Esc để ra")
			t += _key("Người dân", "trò chuyện")
			t += _key("Ghế câu ở bến sông", "ngồi câu cá")
			t += _key("Con đò", "lên đò; đứng trên đò nhấn E để chèo")
			t += _key("Quả bóng", "sút; đứng trên sân nhấn E để xin vào đá")
			t += _key("Trẻ con đang chơi", "xin chơi cùng (nhảy dây, đánh khăng, kéo co…)")
			t += "\nDòng chữ ở giữa phía dưới màn hình luôn cho biết nhấn E lúc này sẽ làm gì.\n"
		2:
			t += _head("Trò chuyện")
			t += _key("E", "bắt chuyện với người đang nhìn; E / Space hiện hết câu")
			t += _key("1 – 4", "chọn câu hỏi      [b]Esc[/b]  thôi")
			t += "Hỏi chuyện nhiều thì quen thân hơn (xem trang Người quen trong sổ tay).\n"
			t += "\n" + _head("Việc nhờ")
			t += "Ai có dấu [b]![/b] vàng trên đầu là đang cần giúp: hỏi \"có cần giúp gì không\" rồi nhận lời.\n"
			t += "Hình thoi vàng chỉ chỗ cần tới; khung bên phải ghi bước đang làm.\n"
			t += "Xong việc quay lại báo: được quà, người lớn trả thêm tiền công.\n"
			t += "\n" + _head("Biếu quà")
			t += "Mùa cấy, lúc lúa đang lên, mùa gặt: ra đồng hỏi bác nông dân \"có cần người … thuê không\" để làm thuê lấy công — bấm Space đúng nhịp tay.\n"
			t += "Trò chuyện (+1) và biếu quà (+2, đúng món thích +3) làm thân dần: quen → thân (6 điểm) → thân thiết (14 điểm). Người thân kể chuyện riêng, bán hàng bớt giá, trả thêm công; thân thiết thì mỗi ngày cho quà. Xem ở sổ tay, trang Người quen.\n"
			t += "Trong túi có đồ thì khi trò chuyện có câu \"biếu chút quà\". Biếu đúng món người ta thích thì họ quý hơn.\n"
		3:
			t += _head("Chợ phiên")
			t += "Họp buổi sáng các ngày âm lịch mùng 1, 6, 11, 16, 21, 26, ở bãi ngoài cổng làng phía đông nam.\n"
			t += _key("E vào người bán", "xem hàng, mua; bán lại đồ cùng loại (nửa giá); hàng cá mua cá bạn câu")
			t += "\n" + _head("Túi đồ — phím I")
			t += _key("A / D", "đổi ngăn      [b]W / S[/b]  chọn món      [b]E[/b]  dùng      [b]I / Esc[/b]  gấp")
			t += _key("Đồ ăn, chè", "no bụng một lúc: chạy nhanh hơn, chèo đua thuyền và kéo co đỡ mệt")
			t += _key("Hộp mồi giun", "5 lượt câu cá cắn nhanh hơn")
			t += _key("Diều giấy", "tự thả diều ở chỗ thoáng (đứt dây là mất)")
			t += _key("Sáo trúc", "thổi một khúc sáo")
			t += _key("Ngăn Nấu ăn", "về NHÀ MÌNH rồi mở túi: nấu cơm, đồ xôi, nướng khoai, rán trứng, canh, cá kho, mâm cơm")
			t += "\n" + _head("Kiếm tiền")
			t += "Bán cá, giúp việc dân làng, làm thuê ngoài đồng, nhất đua thuyền, mừng tuổi ngày Tết.\n"
		4:
			t += _head("Câu cá — ở ghế câu các bến sông và trên mũi đò")
			t += _key("Giữ chuột trái / Space", "lấy đà; thả ra để quăng phao")
			t += _key("Phao chìm hẳn", "bấm ngay để giật cần (phao mới nhấp thì đừng giật)")
			t += _key("Kéo cá", "giữ để cuộn dây, thả khi dây căng")
			t += _key("Esc / E", "thôi câu")
			t += "\n" + _head("Chèo đò")
			t += _key("Lên đò", "đi qua ván cầu, hoặc nhìn đò từ bờ rồi nhấn E; ngắm cảnh thì bấm vào đò")
			t += _key("E khi đứng trên đò", "cầm chèo")
			t += _key("W / S", "tới / lùi      [b]A / D[/b]  rẽ      [b]Shift[/b]  chèo nhanh      [b]E / Esc[/b]  thôi chèo")
			t += "\n" + _head("Bơi")
			t += "Lội xuống sông sâu một chút là tự bơi: W A S D bơi, Shift bơi sải. Lên gần bờ thì đi bộ lại.\n"
			t += _key("Giữ C (hoặc Ctrl) khi đang bơi", "lặn xuống đáy — nín thở được chừng 14 giây, hết hơi thì tự ngoi lên")
			t += _key("E khi đang lặn", "nhặt ốc, trai nằm dưới đáy quanh các bến (đem nấu hoặc bán cho hàng cá)")
			t += "\n" + _head("Đua thuyền")
			t += "Bấm bến đua (cờ ba màu, trống) ở bến sông phía bắc. Giữ W chèo, Space đúng nhịp trống, A / D lái.\n"
		5:
			t += _head("Sân bóng — bãi ngoài cổng làng phía đông, 11 đấu 11")
			t += _key("E khi đứng trên sân", "xin vào đá; thiếu quân thì người làng bên vào cho đủ")
			t += _key("Chạy vào bóng", "dẫn bóng")
			t += _key("Chuột trái", "giữ lấy lực rồi thả để sút (nhìn lên thì bóng bổng)")
			t += _key("Chuột trái lúc bóng bổng ngang đầu", "đánh đầu theo hướng nhìn")
			t += _key("Chuột phải", "chuyền cho đồng đội gần hướng nhìn nhất")
			t += _key("Q", "gọi đồng đội chuyền cho mình")
			t += _key("V / Esc", "rời sân")
			t += "\nKhi đang đá: vòng trắng là quả bóng, chữ vàng \"SÚT VÀO ĐÂY\" là khung thành đối phương, dấu tam giác đậm là đồng đội.\n"
			t += "Dòng chữ to phía dưới luôn nói việc nên làm; góc dưới phải là sa bàn sân.\n"
		6:
			t += _head("Rủ chơi")
			t += "Trò chuyện với trẻ con → \"Chơi gì không em?\" rồi chọn trò. Hoặc nhìn bọn trẻ đang chơi rồi nhấn E để xin vào.\n\n"
			t += _key("Ô ăn quan", "bấm ô hoặc W / S chọn ô, A / D rải sang trái / phải")
			t += _key("Trốn tìm", "bạn đi tìm: nhìn thấy đứa nào là bắt được")
			t += _key("Thả diều", "giữ Space giật dây, W thả dây, S thu dây, A / D lái")
			t += _key("Nhảy dây", "Space nhảy đúng lúc dây chạm đất")
			t += _key("Đánh khăng", "giữ Space lấy lực rồi thả; bấm để vụt")
			t += _key("Kéo co", "Space đúng nhịp hò")
			t += _key("Đá cầu, bắn bi, chơi chuyền", "Space đúng lúc; bắn bi thì A / D ngắm")
			t += _key("Bịt mắt bắt dê, rồng rắn", "W A S D để chạy")
			t += "\nTrò nào cũng nhấn [b]Esc[/b] để thôi. Kỷ lục ghi trong sổ tay.\n"
		7:
			t += _head("Giờ và ngày")
			t += _key("[  ]", "lùi / tiến giờ      [b], .[/b]  lùi / tiến một ngày")
			t += _key("T", "bật / tắt tự chạy giờ (một ngày = 15 phút thật)")
			t += _key("R", "đổi thời tiết")
			t += "\n" + _head("Làng theo thời gian")
			t += "Sáng trẻ con đi học, người lớn ra đồng; chiều đá bóng, kéo co, mùa hè tắm sông; tối về nhà.\n"
			t += "Lúa một vụ 90 ngày: cày, cấy, trổ bông, chín, gặt. Lá cây đổi màu theo bốn mùa.\n"
			t += "Mùng 1 và rằm dân làng đi lễ đình. Tết có cây nêu, pháo, mừng tuổi; rằm tháng Tám trẻ con rước đèn.\n"
			t += "\n" + _head("Lưu game")
			t += _key("F5", "lưu ngay (game cũng tự lưu mỗi phút và khi đóng cửa sổ)")
			t += _key("Ctrl + F5", "xoá file lưu, lần mở sau chơi lại từ đầu")
	return t


# --- Giao diện ---------------------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -540
	panel.offset_top = -330
	panel.offset_right = 540
	panel.offset_bottom = 330
	var sb := StyleBoxFlat.new()
	sb.bg_color = Notebook.PAPER
	sb.border_color = Palette.WOOD
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 18
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(_label(true, 28, Notebook.ACCENT, "Trợ giúp"))
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	col.add_child(tabs)
	for i in PAGES.size():
		var b := Button.new()
		b.text = PAGES[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", Hud.font(true))
		b.add_theme_font_size_override("font_size", 16)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var s := StyleBoxFlat.new()
			s.bg_color = Notebook.ACCENT if st.contains("pressed") else Notebook.PAPER.darkened(0.12 if st == "hover" else 0.06)
			s.set_corner_radius_all(6)
			s.content_margin_left = 12
			s.content_margin_right = 12
			s.content_margin_top = 5
			s.content_margin_bottom = 5
			b.add_theme_stylebox_override(st, s)
		b.add_theme_color_override("font_color", Notebook.INK)
		b.add_theme_color_override("font_hover_color", Notebook.INK)
		b.add_theme_color_override("font_pressed_color", Notebook.PAPER)
		b.add_theme_color_override("font_hover_pressed_color", Notebook.PAPER)
		b.pressed.connect(set_page.bind(i))
		tabs.add_child(b)
		_tabs.append(b)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_override("normal_font", Hud.font(false))
	_body.add_theme_font_override("bold_font", Hud.font(true))
	_body.add_theme_font_size_override("normal_font_size", 18)
	_body.add_theme_font_size_override("bold_font_size", 18)
	_body.add_theme_color_override("default_color", Notebook.INK)
	_body.add_theme_constant_override("line_separation", 7)
	col.add_child(_body)
	_foot = _label(false, 14, Notebook.INK_SOFT, "")
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_foot)
	# Khung hướng dẫn nhập môn (bên trái, dưới khung giờ)
	_guide_panel = PanelContainer.new()
	var gs := StyleBoxFlat.new()
	gs.bg_color = Palette.HUD_BG
	gs.border_color = Palette.FLOWER_YELLOW
	gs.border_width_left = 5
	gs.set_corner_radius_all(10)
	gs.content_margin_left = 16
	gs.content_margin_right = 16
	gs.content_margin_top = 10
	gs.content_margin_bottom = 10
	_guide_panel.add_theme_stylebox_override("panel", gs)
	_guide_panel.position = Vector2(20, 156)
	_guide_panel.custom_minimum_size = Vector2(430, 0)
	_guide_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_guide_panel)
	var gbox := VBoxContainer.new()
	gbox.add_theme_constant_override("separation", 3)
	_guide_panel.add_child(gbox)
	_guide_title = _label(true, 14, Palette.FLOWER_YELLOW, "")
	gbox.add_child(_guide_title)
	_guide_text = _label(true, 19, Palette.HUD_TEXT, "")
	_guide_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_text.custom_minimum_size = Vector2(400, 0)
	gbox.add_child(_guide_text)
	_guide_tip = _label(false, 14, Palette.HUD_SUBTEXT, "")
	_guide_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_tip.custom_minimum_size = Vector2(400, 0)
	gbox.add_child(_guide_tip)


func _label(bold: bool, sz: int, c: Color, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Hud.font(bold))
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	return l
