class_name Notebook
extends CanvasLayer
## Sổ tay người chơi (mục 39) — phím B (action `toggle_notebook`). Một cuốn sổ giấy nằm giữa màn hình, 5 trang:
## - Kỷ lục: các trò dân gian + đá bóng (từ `SaveGame.records`, được lưu).
## - Câu cá: số con, con to nhất từng loài, loài chưa câu được, cá trong giỏ.
## - Người quen: ai đã trò chuyện (số lần), nhà ở đâu, quan hệ trong nhà; đã quen bao nhiêu / cả làng.
## - Quà & việc: số việc đã giúp, việc đang làm, quà đã nhận (gộp theo món).
## - Làng hôm nay: ngày dương / âm, lễ, mùa vụ, thời tiết, số hộ, thời gian đã chơi.
## A / D hoặc bấm tab để lật trang; B / Esc gấp sổ. Đang nhập vai thì người chơi đứng lại, hiện chuột.

@export var save_game: SaveGame
@export var fishing: Fishing
@export var quests: Quests
@export var dialogue: Dialogue
@export var villagers: Villagers
@export var calendar: LunarCalendar
@export var day_night: DayNight
@export var weather: Weather
@export var farming: Farming
@export var first_person: FirstPerson
@export var hud: Hud
@export var outdoor_rig: CameraRig
@export var market: Market

const PAGES: Array[String] = ["Kỷ lục", "Câu cá", "Người quen", "Quà & đồ", "Làng hôm nay"]
const PAPER := Color("#f3e6c4")
const INK := Color("#3b2a1a")
const INK_SOFT := Color("#7a5a3a")
const ACCENT := Color("#a8432f")

var open: bool = false
var page: int = 0
var _root: Control
var _tabs: Array[Button] = []
var _body: RichTextLabel
var _title: Label
var _from_fp: bool = false
var _rig_was_active: bool = false


func _ready() -> void:
	layer = 18
	_build()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_notebook"):
		if open:
			close()
		else:
			show_notebook()
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
	elif not (event is InputEventKey):
		return                 # chuột: để nút / cuộn trang tự xử lý
	# Sổ đang mở: không cho phím nào lọt xuống (camera, giờ, thời tiết…)
	get_viewport().set_input_as_handled()


## Mở sổ (không mở khi đang chơi một trò / đang trò chuyện).
func show_notebook() -> void:
	if dialogue != null and dialogue.talking:
		return
	_from_fp = first_person != null and first_person.active
	if _from_fp:
		if first_person._suspended != "":
			return
		first_person._suspend("notebook")
	open = true
	_root.visible = true
	if outdoor_rig != null and not _from_fp:
		_rig_was_active = outdoor_rig.active
		outdoor_rig.active = false        # camera ngắm cảnh đọc phím trực tiếp: tạm khoá
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_page(page)


func close() -> void:
	if not open:
		return
	open = false
	_root.visible = false
	if outdoor_rig != null and not _from_fp:
		outdoor_rig.active = _rig_was_active
	if _from_fp and first_person != null and first_person._suspended == "notebook":
		first_person._resume()


func set_page(i: int) -> void:
	page = i
	for k in _tabs.size():
		_tabs[k].button_pressed = k == i
	_title.text = "Sổ tay  ·  " + PAGES[i]
	_body.text = page_text(i)
	_body.scroll_to_line(0)


func _process(_delta: float) -> void:
	if open and Engine.get_process_frames() % 30 == 0:
		_body.text = page_text(page)          # trang "Làng hôm nay" có giờ chạy


# --- Nội dung các trang ---------------------------------------------------------------------------

func page_text(i: int) -> String:
	match i:
		0: return _records_text()
		1: return _fish_text()
		2: return _people_text()
		3: return _gifts_text()
		4: return _village_text()
	return ""


static func _h(t: String) -> String:
	return "[font_size=24][b][color=#%s]%s[/color][/b][/font_size]\n" % [ACCENT.to_html(false), t]


static func _row(label: String, value: String) -> String:
	return "[color=#%s]%s[/color]   [b]%s[/b]\n" % [INK_SOFT.to_html(false), label, value]


static func _soft(t: String) -> String:
	return "[color=#%s][i]%s[/i][/color]\n" % [INK_SOFT.to_html(false), t]


func _records_text() -> String:
	if save_game == null:
		return _soft("Chưa có sổ kỷ lục.")
	var r := save_game.records
	var t := _h("Trò chơi dân gian")
	t += _row("Nhảy dây", ("nhảy liền %d lần  ·  %d lượt" % [int(r.rope_best), int(r.rope_games)]) if int(r.rope_games) > 0 else "chưa chơi")
	t += _row("Đánh khăng", ("lượt cao nhất %d khăng  ·  %d lượt" % [int(r.khang_best), int(r.khang_turns)]) if int(r.khang_turns) > 0 else "chưa chơi")
	var race := "chưa đua"
	if int(r.races) > 0:
		var parts: Array[String] = []
		if float(r.race_best_team) > 0.0:
			parts.append("thuyền rồng %s" % _secs(float(r.race_best_team)))
		if float(r.race_best_solo) > 0.0:
			parts.append("thuyền đơn %s" % _secs(float(r.race_best_solo)))
		parts.append("về nhất %d / %d cuộc" % [int(r.race_wins), int(r.races)])
		race = "  ·  ".join(parts)
	t += _row("Đua thuyền", race)
	t += _row("Thả diều", ("cao nhất %s m  ·  %d lần thả" % [_num(float(r.kite_best)), int(r.kites)]) if int(r.kites) > 0 else "chưa thả")
	var games := int(r.oaq_wins) + int(r.oaq_losses) + int(r.oaq_draws)
	t += _row("Ô ăn quan", ("thắng %d  ·  thua %d  ·  hoà %d" % [int(r.oaq_wins), int(r.oaq_losses), int(r.oaq_draws)]) if games > 0 else "chưa chơi ván nào trọn")
	t += _row("Trốn tìm", ("%d ván  ·  tìm được %d bạn  ·  %d ván bắt hết" % [int(r.hs_games), int(r.hs_found), int(r.hs_all_found)]) if int(r.hs_games) > 0 else "chưa chơi")
	t += "\n" + _h("Sân bóng làng")
	t += _row("Bàn thắng của bạn", str(int(r.goals)))
	return t


func _fish_text() -> String:
	if fishing == null:
		return ""
	var t := _h("Sổ câu  ·  %d con" % fishing._total)
	var caught := 0
	for sp: Dictionary in Fishing.SPECIES:
		var nm: String = sp.name
		if fishing._log.has(nm):
			caught += 1
			var rec: Dictionary = fishing._log[nm]
			t += _row(nm, "%d con  ·  to nhất %s" % [int(rec.count), Fishing._kg(float(rec.best))])
		else:
			t += "[color=#%s]%s   — chưa câu được[/color]\n" % [INK_SOFT.to_html(false), nm]
	t += _soft("Đã câu được %d / %d loài cá trong sông." % [caught, Fishing.SPECIES.size()])
	t += "\n" + _h("Trong giỏ")
	if fishing.basket.is_empty():
		t += _soft("Giỏ đang trống.")
	else:
		var total_kg := 0.0
		for b: Dictionary in fishing.basket:
			total_kg += float(b.kg)
			t += "•  %s  %s\n" % [b.name, Fishing._kg(float(b.kg))]
		t += _soft("Cả giỏ nặng %s. Có người nhờ câu cá thì đem cá trong giỏ ra đưa." % Fishing._kg(total_kg))
	return t


func _people_text() -> String:
	if dialogue == null:
		return ""
	var met: Array = []
	for v: Variant in dialogue._met:
		if is_instance_valid(v) and v is Villager:
			met.append(v)
	met.sort_custom(func(a: Villager, b: Villager) -> bool: return int(dialogue._met[a]) > int(dialogue._met[b]))
	var total := villagers.people.size() if villagers != null else 0
	var t := _h("Người quen  ·  %d / %d người trong làng" % [met.size(), total])
	if met.is_empty():
		return t + _soft("Chưa quen ai. Nhập vai (V), nhìn vào một người rồi nhấn E để trò chuyện.")
	for v: Villager in met:
		var home := str(v.home.get("name", "")).to_lower()
		var rel := str(v.get_meta("relation", ""))
		var who := v.role_name.to_lower()
		if rel != "":
			who += " (%s trong nhà)" % rel
		t += "[b]%s[/b]  —  %s\n" % [v.display_name, who]
		t += "[color=#%s]    %s  ·  đã nói chuyện %d lần[/color]\n" % [INK_SOFT.to_html(false), home, int(dialogue._met[v])]
	return t


func _gifts_text() -> String:
	if quests == null:
		return ""
	var t := ""
	if market != null:
		t += _h("Túi tiền  ·  %d nghìn đồng" % market.money)
		if market.bag.is_empty():
			t += _soft("Chưa mua gì. Sáng ngày phiên chợ ra bãi cỏ ngoài cổng làng mua bán; câu cá bán cho hàng cá lấy tiền.")
		else:
			var cnt := {}
			var order: Array[String] = []
			for it in market.bag:
				if not cnt.has(it):
					order.append(it)
				cnt[it] = int(cnt.get(it, 0)) + 1
			t += "[color=#%s]Đồ đã mua (đem biếu dân làng được):[/color]\n" % INK_SOFT.to_html(false)
			for it in order:
				t += "•  %s%s\n" % [it, ("  × %d" % int(cnt[it])) if int(cnt[it]) > 1 else ""]
		t += "\n"
	t += _h("Việc giúp dân làng  ·  %d việc đã xong" % quests.done_count)
	if quests.active.is_empty():
		t += _soft("Không có việc nào đang làm. Ai có dấu \"!\" vàng trên đầu là đang cần người giúp.")
	else:
		for q: Dictionary in quests.active:
			t += "•  %s\n" % str(q.get("title", "Việc được nhờ"))
	t += "\n" + _h("Quà đã nhận  ·  %d món" % quests.gifts.size())
	if quests.gifts.is_empty():
		t += _soft("Chưa có quà nào.")
	else:
		var count := {}
		var order: Array[String] = []
		for g in quests.gifts:
			if not count.has(g):
				order.append(g)
			count[g] = int(count.get(g, 0)) + 1
		for g in order:
			t += "•  %s%s\n" % [g, ("  × %d" % int(count[g])) if int(count[g]) > 1 else ""]
	return t


func _village_text() -> String:
	var t := _h("Làng hôm nay")
	if calendar != null:
		t += _row("Ngày", calendar.date_text())
		var hol := calendar.holiday_name()
		if hol != "" and not calendar.date_text().contains(hol):
			t += _row("Lễ", hol)
	if day_night != null:
		var h := day_night.time_of_day
		t += _row("Giờ", "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)])
	if weather != null:
		t += _row("Trời", weather.display_name())
	if farming != null:
		t += _row("Đồng", farming.stage_text().trim_prefix("Đồng: "))
	if market != null:
		t += _row("Chợ", market.status_text())
	if villagers != null:
		t += _row("Dân làng", "%d hộ  ·  %d người  ·  %d con vật" % [villagers.households, villagers.people.size(), villagers.animals.size()])
	if save_game != null:
		t += "\n" + _h("Bạn")
		t += _row("Đã chơi", _duration(float(save_game.records.get("play_seconds", 0.0))))
		t += _row("Lưu lần cuối", save_game.last_saved if save_game.last_saved != "" else "chưa lưu (F5 để lưu)")
	return t


static func _secs(s: float) -> String:
	return ("%.1f giây" % s).replace(".", ",")


static func _num(v: float) -> String:
	return ("%.1f" % v).replace(".", ",")


static func _duration(s: float) -> String:
	var m := int(s / 60.0)
	if m < 60:
		return "%d phút" % m
	return "%d giờ %d phút" % [m / 60, m % 60]


# --- Giao diện ----------------------------------------------------------------------------------------

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
	panel.custom_minimum_size = Vector2(960, 640)
	panel.offset_left = -480
	panel.offset_top = -320
	panel.offset_right = 480
	panel.offset_bottom = 320
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = Color("#7a5233")
	sb.set_border_width_all(6)
	sb.border_width_left = 22          # gáy sổ
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 40
	sb.content_margin_right = 30
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 12
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	_title = Label.new()
	_title.add_theme_font_override("font", Hud.font(true))
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", INK)
	col.add_child(_title)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	for i in PAGES.size():
		var b := Button.new()
		b.text = PAGES[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", Hud.font(true))
		b.add_theme_font_size_override("font_size", 18)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var s := StyleBoxFlat.new()
			s.bg_color = ACCENT if st.begins_with("pressed") or st == "hover_pressed" else (PAPER.darkened(0.12) if st == "hover" else PAPER.darkened(0.06))
			s.set_corner_radius_all(6)
			s.content_margin_left = 14
			s.content_margin_right = 14
			s.content_margin_top = 6
			s.content_margin_bottom = 6
			b.add_theme_stylebox_override(st, s)
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", PAPER)
		b.add_theme_color_override("font_hover_pressed_color", PAPER)
		b.pressed.connect(set_page.bind(i))
		tabs.add_child(b)
		_tabs.append(b)
	var line := ColorRect.new()
	line.color = INK_SOFT
	line.custom_minimum_size = Vector2(0, 2)
	col.add_child(line)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.scroll_active = true
	_body.add_theme_font_override("normal_font", Hud.font(false))
	_body.add_theme_font_override("bold_font", Hud.font(true))
	_body.add_theme_font_override("italics_font", Hud.font(false))
	_body.add_theme_font_size_override("normal_font_size", 19)
	_body.add_theme_font_size_override("bold_font_size", 19)
	_body.add_theme_font_size_override("italics_font_size", 18)
	_body.add_theme_color_override("default_color", INK)
	_body.add_theme_constant_override("line_separation", 6)
	col.add_child(_body)
	var foot := Label.new()
	foot.text = "A / D hoặc bấm mục để lật trang   ·   B / Esc: gấp sổ"
	foot.add_theme_font_override("font", Hud.font(false))
	foot.add_theme_font_size_override("font_size", 15)
	foot.add_theme_color_override("font_color", INK_SOFT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)
