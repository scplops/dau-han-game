extends SceneTree
## Thử bảng trợ giúp + hướng dẫn nhập môn (mục 52), headless:
## 1) Hướng dẫn: lần lượt làm từng bước (xoay camera, nhập vai, đi, trò chuyện, túi đồ, bản đồ, sổ tay, F1) → xong, lưu được.
## 2) Bảng trợ giúp: mở / đóng ở ngắm cảnh và nhập vai, 8 trang đều có nội dung, không mở khi đang trò chuyện, E tắt hướng dẫn.
## Dùng: timeout 300 godot --headless --path . -s tools/help_test.gd

var _fails: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _check(name_s: String, ok: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["OK" if ok else "SAI", name_s, ("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(name_s)

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _wait(8)
	var hg := scene.get_node("HelpGuide") as HelpGuide
	var rig := scene.get_node("CameraRig") as CameraRig
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var dlg := scene.get_node("Dialogue") as Dialogue
	var inv := scene.get_node("Inventory") as Inventory
	var nb := scene.get_node("Notebook") as Notebook
	var mm := scene.get_node("HUD/MiniMap") as MiniMap
	var sg := scene.get_node("SaveGame") as SaveGame
	var vs := scene.get_node("World/Villagers") as Villagers
	print("1) Hướng dẫn nhập môn")
	_check("chạy bằng -s thì không hiện", not hg._guide_panel.visible and hg.step == 0)
	hg.force_guide = true
	await _wait(3)
	_check("bật lên: bước 1, khung hiện", hg.step == 0 and hg._guide_panel.visible, hg._guide_text.text)
	rig.yaw_deg += 40.0
	await _wait(3)
	_check("xoay camera → bước 2", hg.step == 1, hg._guide_text.text)
	fp.enter()
	await _wait(10)
	_check("nhập vai → bước 3", hg.step == 2, hg._guide_text.text)
	for i in 40:
		fp.global_position += Vector3(0.4, 0, 0)
		await process_frame
	_check("đi đủ quãng → bước 4", hg.step == 3, "đã đi %.0f m · %s" % [hg._walked, hg._guide_text.text])
	dlg._met[vs.people[0]] = 1
	await _wait(3)
	_check("trò chuyện → bước 5", hg.step == 4, hg._guide_text.text)
	inv.show_inventory()
	await _wait(3)
	inv.close()
	_check("mở túi đồ → bước 6", hg.step == 5, hg._guide_text.text)
	mm.mode = MiniMap.Mode.LARGE
	await _wait(3)
	mm.mode = MiniMap.Mode.SMALL
	_check("bản đồ lớn → bước 7", hg.step == 6, hg._guide_text.text)
	nb.show_notebook()
	await _wait(3)
	nb.close()
	_check("mở sổ tay → bước 8", hg.step == 7, hg._guide_text.text)
	_check("mở trợ giúp khi nhập vai: đứng lại, mở trang Nhập vai", hg.show_help() and fp._suspended == "help" and hg.page == 1)
	await _wait(3)
	_check("xong hướng dẫn", hg.step == HelpGuide.STEPS.size() and hg.done())
	hg.close()
	_check("đóng trợ giúp thì đi tiếp", fp._suspended == "" and not hg.open)
	_check("lưu trạng thái hướng dẫn", bool(sg.snapshot().get("guide_done", false)))
	hg.step = 0
	sg.apply({"guide_done": true})
	_check("nạp lại: không hiện nữa", hg.done())
	print("2) Bảng trợ giúp")
	var short := ""
	for i in HelpGuide.PAGES.size():
		if hg.page_text(i).length() < 250:
			short += HelpGuide.PAGES[i] + " "
	_check("8 trang đều có nội dung", HelpGuide.PAGES.size() == 8 and short == "", short)
	fp.exit()
	await _wait(3)
	var was := rig.active
	_check("ngắm cảnh: mở được, khoá camera", hg.show_help() and not rig.active and was)
	hg.set_page(5)
	_check("lật trang Đá bóng", hg._body.text.contains("11 đấu 11"))
	hg.guide_on = true
	hg.step = 2
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	hg._unhandled_input(ev)
	_check("E tắt hướng dẫn", not hg.guide_on and hg.done())
	hg.close()
	_check("đóng: camera chạy lại", rig.active)
	fp.enter()
	await _wait(5)
	dlg.start(vs.people[0], fp)
	_check("đang trò chuyện không mở trợ giúp", not hg.show_help())
	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
