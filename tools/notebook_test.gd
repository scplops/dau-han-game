extends SceneTree
## Thử sổ tay (mục 39), headless: mở / gấp bằng phím B ở chế độ ngắm cảnh và khi nhập vai (người chơi đứng lại,
## hiện chuột, gấp sổ thì đi tiếp), lật trang A / D, phím khác không lọt xuống camera, không mở khi đang trò chuyện,
## nội dung từng trang có số liệu thật (kỷ lục từ tín hiệu, cá, người quen, quà).
## Dùng: godot --headless --path . -s tools/notebook_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(5)
	var nb := scene.get_node("Notebook") as Notebook
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	var dlg := scene.get_node("Dialogue") as Dialogue
	var vs := scene.get_node("World/Villagers") as Villagers
	# Dữ liệu thật qua tín hiệu / hội thoại
	(scene.get_node("JumpRope") as JumpRope).turn_over.emit("Bạn", 25)
	(scene.get_node("KiteFlying") as KiteFlying).finished.emit(51.0, 60.0, "reel")
	var fish := scene.get_node("Fishing") as Fishing
	fish._log = {"Cá diếc": {"count": 2, "best": 0.3}}
	fish._total = 2
	dlg._met[vs.people[2]] = 3
	# 1) Ngắm cảnh
	await _key("toggle_notebook")
	print("1) Ngắm cảnh: B mở sổ %s · trang '%s'" % [nb.open, Notebook.PAGES[nb.page]])
	var f0 := rig._target_focus
	await _key("cam_forward")
	print("   W khi đang mở sổ: camera không chạy %s" % (rig._target_focus.distance_to(f0) < 0.01))
	await _key("cam_right")
	await _key("cam_right")
	print("   D D: lật tới trang '%s'" % Notebook.PAGES[nb.page])
	await _key("cam_left")
	print("   A: về trang '%s'" % Notebook.PAGES[nb.page])
	for i in Notebook.PAGES.size():
		nb.set_page(i)
		var txt := nb._body.get_parsed_text()
		print("   trang %-14s %3d dòng · %s" % [Notebook.PAGES[i], txt.count("\n"), txt.split("\n")[1].strip_edges() if txt.count("\n") > 1 else txt])
	var rec := nb.page_text(0)
	print("   kỷ lục có nhảy dây 25: %s · diều 51 m: %s · cá diếc: %s · người quen 1: %s" % [rec.contains("nhảy liền 25"), rec.contains("51,0 m"),
			nb.page_text(1).contains("Cá diếc   [b]2 con") or nb.page_text(1).contains("2 con"), nb.page_text(2).contains("1 / ")])
	await _key("exit_interior")
	print("   Esc gấp sổ: %s" % (not nb.open))
	# 2) Nhập vai
	rig.global_position = Vector3(-8, 0, 14)
	fp.enter()
	await _frames(8)
	await _key("toggle_notebook")
	print("2) Nhập vai: mở sổ %s · người chơi đứng lại '%s' · chuột hiện %s" % [nb.open, fp._suspended, Input.mouse_mode == Input.MOUSE_MODE_VISIBLE])
	await _key("toggle_notebook")
	print("   B gấp sổ: %s · đi tiếp %s · camera nhập vai %s" % [not nb.open, fp._suspended == "" and fp.active, fp.camera.current])
	# 3) Đang trò chuyện thì không mở
	var v := vs.people[2]
	v.global_position = fp.global_position + Vector3(0, 0, -1.5)
	v.visible = true
	dlg.start(v, fp)
	fp._suspend("talk")
	nb.show_notebook()
	print("3) Đang trò chuyện: sổ không mở %s" % (not nb.open))
	quit()
