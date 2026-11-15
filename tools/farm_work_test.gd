extends SceneTree
## Thử làm thuê mùa vụ (mục 54), headless:
## 1) Việc theo giai đoạn của vụ; lời từ chối (không phải nông dân, hết mùa, tối, mưa, xa ruộng).
## 2) Xin làm qua hội thoại → xuống ruộng; bot bấm với độ lệch tay khác nhau: số khóm, tiền công.
## 3) Mùa gặt được thêm gạo; Esc dọn sạch; kỷ lục.
## Dùng: timeout 300 godot --headless --path . -s tools/farm_work_test.gd

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(name_s: String, ok: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["OK" if ok else "SAI", name_s, ("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(name_s)


## Chơi trọn một buổi: bấm mỗi nhịp một lần, lệch tay ngẫu nhiên trong ±jitter giây (jitter < 0: không bấm).
func _session(fw: FarmWork, rng: RandomNumberGenerator, jitter: float) -> void:
	fw.step(3.0)
	var dt := 1.0 / 60.0
	var want := 0.5
	var pressed := false
	while fw.phase == "work":
		var before := fw._phi
		fw.step(dt)
		if fw._phi < before:
			pressed = false
			want = 0.5 + rng.randf_range(-jitter, jitter) / fw.period()
		if jitter >= 0.0 and not pressed and fw._phi >= want:
			pressed = true
			fw.press()


func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	for i in 5:
		await process_frame
	var dn := scene.get_node("DayNight") as DayNight
	dn.auto_run = false
	dn.time_of_day = 9.0
	var farming := scene.get_node("Farming") as Farming
	var fw := scene.get_node("FarmWork") as FarmWork
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	var inv := scene.get_node("Inventory") as Inventory
	var dlg := scene.get_node("Dialogue") as Dialogue
	var vs := scene.get_node("World/Villagers") as Villagers
	var save := scene.get_node("SaveGame") as SaveGame
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var farmer: Villager = null
	var kid: Villager = null
	for v in vs.people:
		if v.role == "farmer" and farmer == null:
			farmer = v
		if v.role == "kid" and kid == null:
			kid = v

	print("1) Việc theo mùa vụ, lời từ chối")
	var kinds := {}
	for d: float in [2.0, 8.0, 20.0, 40.0, 60.0, 76.0, 83.0, 89.0]:
		farming.set_cycle_day(d)
		kinds[d] = fw.kind_now()
	_check("việc theo giai đoạn", kinds[2.0] == "" and kinds[8.0] == "plant" and kinds[20.0] == "weed" and kinds[40.0] == "weed"
			and kinds[60.0] == "" and kinds[76.0] == "" and kinds[83.0] == "reap" and kinds[89.0] == "", str(kinds))
	# Đứng ở bờ ruộng ngoài đồng
	var f0: Rect2 = farming._outer[0].rect
	var spot := Vector3(f0.get_center().x, 0, f0.position.y - 1.0)
	rig.set_focus(spot)
	rig.snap()
	fp.enter()
	for i in 10:
		await physics_frame
	farming.set_cycle_day(8.0)
	_check("bờ ruộng, mùa cấy, ban ngày: được", fw.refusal(farmer, fp.global_position) == "", "cách ruộng %.1f m" % float(fw.nearest_field(fp.global_position).dist))
	_check("trẻ con: không thuê", fw.refusal(kid, fp.global_position) != "" and fw.dialog_options(kid, dlg).is_empty())
	_check("giữa làng: xa ruộng", fw.refusal(farmer, Vector3(0, 0, -100)) != "")
	dn.time_of_day = 19.5
	_check("tối: nghỉ", fw.refusal(farmer, fp.global_position) != "")
	dn.time_of_day = 9.0
	w.set_weather("storm", true)
	for i in 3:
		await process_frame
	_check("mưa giông: nghỉ", fw.refusal(farmer, fp.global_position) != "")
	w.set_weather("clear", true)
	for i in 3:
		await process_frame
	farming.set_cycle_day(60.0)
	_check("lúa trổ: không có việc, không có câu hỏi", fw.refusal(farmer, fp.global_position) != "" and fw.dialog_options(farmer, dlg).is_empty())

	print("2) Xin cấy thuê qua hội thoại")
	farming.set_cycle_day(8.0)
	farmer.visible = true
	farmer.global_position = fp.global_position + Vector3(1.5, 0, 0)
	var opts := fw.dialog_options(farmer, dlg)
	_check("có câu xin cấy thuê", opts.size() == 1 and String(opts[0].text).contains("cấy"), String(opts[0].text) if not opts.is_empty() else "")
	var ans := String((opts[0].answer as Callable).call())
	var nxt: Array = (opts[0].next as Callable).call()
	_check("bác nhận lời", ans.begins_with("Có chứ") and nxt.size() == 2 and nxt[0].has("then"), ans)
	var money0 := inv.money
	(nxt[0].then as Callable).call()
	_check("xuống ruộng", fw.playing and fw.kind == "plant" and fw.phase == "ready" and fp._suspended == "farm" and farmer.has_meta("talking")
			and f0.grow(0.5).has_point(Vector2(fw._avatar.global_position.x, fw._avatar.global_position.z)),
			"chỗ làm (%.1f, %.1f)" % [fw._avatar.global_position.x, fw._avatar.global_position.z])
	_session(fw, rng, 0.03)
	var good := fw.done_cells
	_check("đều tay (lệch ±0,03 s): nhiều khóm, nhịp nhanh dần, có công", good >= 80 and fw.misses <= 2 and fw.last_pay == int(round(good / fw.cells_per_thousand))
			and inv.money == money0 + fw.last_pay and fw.phase == "done",
			"%d khóm · lệch %d · chuỗi dài nhất %d · bác chủ %d khóm · công %d nghìn" % [good, fw.misses, fw.best_streak, fw.npc_cells, fw.last_pay])
	fw.stop()
	_check("Esc: dọn sạch", not fw.playing and fp._suspended == "" and not farmer.has_meta("talking") and not farmer.has_meta("farm_work") and not fw._mmi.visible)
	var res := {}
	for jit: float in [0.11, 0.2, -1.0]:
		fw.start(farmer, "weed")
		_session(fw, rng, jit)
		res[jit] = [fw.done_cells, fw.misses, fw.last_pay]
		fw.stop()
	_check("tay vừa (±0,11 s) kém hơn, tay vụng (±0,2 s) kém nữa, không bấm thì không có công",
			int(res[0.11][0]) < good and int(res[0.2][0]) < int(res[0.11][0]) and int(res[-1.0][0]) == 0 and int(res[-1.0][2]) == 0,
			"±0,11: %s · ±0,2: %s · không bấm: %s" % [res[0.11], res[0.2], res[-1.0]])

	print("3) Mùa gặt")
	farming.set_cycle_day(83.0)
	var rice0 := inv.count("gao_tam")
	money0 = inv.money
	_check("mùa gặt: câu xin gặt thuê", String(fw.dialog_options(farmer, dlg)[0].text).contains("gặt"))
	fw.start(farmer)
	_session(fw, rng, 0.04)
	_check("gặt: công tiền + gạo", fw.kind == "reap" and fw.last_rice >= 1 and inv.count("gao_tam") == rice0 + fw.last_rice and inv.money == money0 + fw.last_pay,
			"%d khóm · %d nghìn + %d cân gạo" % [fw.done_cells, fw.last_pay, fw.last_rice])
	fw.stop()
	fw.start(farmer)
	fw.step(3.0)
	for i in 300:
		fw.step(1.0 / 60.0)
	fw.stop()         # nghỉ giữa buổi
	_check("kỷ lục ghi vào sổ", int(save.records.farm_sessions) == 6 and int(save.records.farm_best) == good, str([save.records.farm_sessions, save.records.farm_best, save.records.farm_pay]))
	fp.exit()
	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
