class_name GameKit
extends RefCounted
## Đồ dùng chung cho các trò chơi dân gian (nhảy dây, đánh khăng, kéo co, năm trò nhỏ… — mục 46): dựng hình nhân của
## người chơi / "trẻ nhà bên", khung giao diện phía trên màn hình, nhãn chữ, câu nói ngắn. Trước đây mỗi trò chép
## lại một bản gần giống nhau.


## Nhãn chữ căn giữa bằng font của HUD.
static func label(bold: bool, size: int, col: Color, text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", Hud.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Khung nền mờ bo góc ở giữa mép trên màn hình; trả về hộp dọc để xếp các dòng vào.
static func top_panel(ui: CanvasLayer) -> VBoxContainer:
	var top := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	top.add_theme_stylebox_override("panel", sb)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 16
	ui.add_child(top)
	var box := VBoxContainer.new()
	top.add_child(box)
	return box


## Dòng chữ to có viền ở giữa màn hình (đếm số, "Thắng rồi!"…).
static func big_label(ui: CanvasLayer, size: int, offset_top: float = -300.0, outline: int = 12) -> Label:
	var l := label(true, size, Palette.HUD_TEXT)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.offset_top = offset_top
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Palette.WINDOW_DARK)
	ui.add_child(l)
	return l


## Thanh nền tối (thước nhịp, thanh lực…) trong hộp `box`.
static func bar(box: Container, width: float = 320.0, height: float = 14.0) -> ColorRect:
	var b := ColorRect.new()
	b.color = Color(0, 0, 0, 0.4)
	b.custom_minimum_size = Vector2(width, height)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(b)
	return b


## Dựng một người tạm (không thuộc Villagers) làm con của `owner`: hình nhân người chơi hoặc người làng bên.
## `opts`: scale, role_name, home_name, keep_hat (mặc định bỏ nón và đồ cầm tay).
static func make_person(owner: Node, villagers: Villagers, node_name: String, role: String, display: String,
		female: bool, opts: Dictionary = {}) -> Villager:
	var v := Villager.new()
	v.name = node_name
	v.role = role
	v.display_name = display
	if opts.has("role_name"):
		v.role_name = str(opts.role_name)
	v.home = {"name": str(opts.get("home_name", "")), "key": ""}
	v.set_meta("female", female)
	owner.add_child(v)
	var look: Dictionary = villagers._look(role, female) if villagers != null else {
			"shirt": Palette.SIGN_BLUE, "pants": Palette.WINDOW_DARK, "skin": Palette.FARMER_SKIN,
			"hat": "none", "scale": 0.66 if role == "kid" else 1.0, "female": female, "prop": "none"}
	if not bool(opts.get("keep_hat", false)):
		look["hat"] = "none"
		look["prop"] = "none"
	if opts.has("scale"):
		look["scale"] = float(opts.scale)
	v.build_person(look)
	return v


## Hình nhân của người chơi (dáng người lớn, không nón, tên "Bạn").
static func make_avatar(owner: Node, villagers: Villagers, dialogue: Dialogue, node_name: String, scale: float = 0.0) -> Villager:
	var female: bool = dialogue != null and dialogue.player_female
	var opts := {}
	if scale > 0.0:
		opts["scale"] = scale
	return make_person(owner, villagers, node_name, "farmer", "Bạn", female, opts)


## Người do trò chơi tự dắt (con của `owner`) không được Villagers diễn hoạt — tự diễn hoạt ở đây.
static func animate_owned(v: Villager, owner: Node, avatar: Villager, dt: float) -> void:
	if v == avatar:
		v._animate(dt)
	elif v.get_parent() == owner:
		v.state = Villager.State.IDLE
		v.tick(dt, true)


## Câu nói ngắn trên đầu, đã điền xưng hô.
static func bark(dialogue: Dialogue, v: Villager, text: String) -> void:
	if dialogue != null and is_instance_valid(v):
		dialogue.bark(v, dialogue.fill_for(v, text))
