extends SceneTree
## Thử túi đồ + tiền (mục 48), headless:
## 1) Danh mục: hàng ở mọi sạp chợ, quà của việc nhờ đều có trong `Inventory.ITEMS`; tên cũ (file lưu bản trước) ra đúng mã.
## 2) Mua / bán lại ở chợ (trừ / cộng tiền, nửa giá), không đủ tiền thì không mua.
## 3) Ăn → no bụng: chạy nhanh hơn, đua thuyền / kéo co đỡ mệt; hết no thì về như cũ.
## 4) Mồi giun: quăng cần tốn một lượt, thời gian chờ cá ngắn lại.
## 5) Biếu quà (đúng món thích thì quen thêm 3, không thì 2). Việc nhờ xong: quà vào túi + tiền công (người lớn).
## 6) Thưởng: nhất đua thuyền, thắng kéo co, thắng ô ăn quan.
## 7) Tự thả diều của mình ở bờ ruộng; đứt dây thì mất diều. Sáo trúc có tiếng.
## 8) Màn hình túi đồ: mở / gấp khi nhập vai, đổi ngăn, không mở khi đang trò chuyện.
## 9) Nạp file lưu bản trước (tiền + túi đồ chợ + quà dạng tên).
## Dùng: timeout 300 godot --headless --path . -s tools/inventory_test.gd

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(name_s: String, ok: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["OK" if ok else "SAI", name_s, ("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(name_s)


func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var dn := scene.get_node("DayNight") as DayNight
	dn.auto_run = false
	dn.time_of_day = 10.0
	var inv := scene.get_node("Inventory") as Inventory
	var mk := scene.get_node("World/Market") as Market
	var fish := scene.get_node("Fishing") as Fishing
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var race := scene.get_node("BoatRace") as BoatRace
	var tug := scene.get_node("TugOfWar") as TugOfWar
	var oaq := scene.get_node("OAnQuan") as OAnQuan
	var kite := scene.get_node("KiteFlying") as KiteFlying
	var dlg := scene.get_node("Dialogue") as Dialogue
	var qs := scene.get_node("Quests") as Quests
	var vs := scene.get_node("World/Villagers") as Villagers
	var snd := scene.get_node("Soundscape") as Soundscape
	var rig := scene.get_node("CameraRig") as CameraRig
	inv.reset()

	print("1) Danh mục: %d món" % Inventory.ITEMS.size())
	var missing: Array[String] = []
	for st: Dictionary in Market.STALLS:
		for id: String in st.items:
			if not Inventory.ITEMS.has(id):
				missing.append(id)
	for role: String in Quests.GIFTS:
		for id: String in Quests.GIFTS[role]:
			if not Inventory.ITEMS.has(id):
				missing.append(id)
	_check("hàng chợ + quà việc nhờ đều có trong danh mục", missing.is_empty(), ", ".join(missing))
	_check("tên cũ → mã", Inventory.id_of("nải chuối tiêu") == "chuoi" and Inventory.id_of("mấy viên bi") == "bi"
			and Inventory.id_of("Cái nón lá") == "non_la" and Inventory.id_of("không có") == "")

	print("2) Mua / bán ở chợ")
	inv.money = 20
	var r1 := mk.buy("non_la")
	_check("mua nón lá 15 nghìn", inv.money == 5 and inv.count("non_la") == 1, r1.left(50))
	var r2 := mk.buy("chum")
	_check("không đủ tiền mua chum", inv.money == 5 and inv.count("chum") == 0, r2.left(50))
	var hats: Dictionary = {}
	for st in mk.stalls:
		if st.kind == "hats":
			hats = st
	_check("hàng nón quạt mua lại nón", mk.sellable(hats) == ["non_la"])
	mk.sell_item("non_la")
	_check("bán lại nửa giá (7 nghìn)", inv.money == 12 and inv.count("non_la") == 0, "tiền %d" % inv.money)
	fish.basket.clear()
	fish.basket.append({"name": "Cá chép", "kg": 1.0})
	mk.sell_fish()
	_check("bán cá 1 kg chép = 25 nghìn", inv.money == 37 and fish.basket.is_empty(), "tiền %d" % inv.money)
	_check("đã kiếm / đã tiêu", inv.earned == 32 and inv.spent == 15, "%d / %d" % [inv.earned, inv.spent])

	print("3) Ăn uống")
	inv.add("chuoi", 2)
	inv.use("chuoi")
	await process_frame          # hiệu ứng đẩy sang trong _process (bước vật lý có thể dồn nhiều lần một khung)
	await process_frame
	_check("no bụng 90 s, còn 1 nải", inv.energy > 85.0 and inv.count("chuoi") == 1, "%.1f s" % inv.energy)
	_check("chạy nhanh hơn / chèo, kéo co đỡ mệt", fp.run_boost > 1.0 and race.stamina_scale < 1.0 and tug.decay_scale < 1.0,
			"%.2f / %.2f / %.2f" % [fp.run_boost, race.stamina_scale, tug.decay_scale])
	inv.energy = 0.01
	for i in 3:
		await process_frame
	_check("hết no thì về như cũ", fp.run_boost == 1.0 and race.stamina_scale == 1.0 and tug.decay_scale == 1.0)
	inv.energy = 300.0
	inv.add("buoi", 3)
	inv.use("buoi")
	_check("no bụng không quá trần", inv.energy <= inv.energy_cap + 0.01, "%.0f s" % inv.energy)
	inv.energy = 0.0

	print("4) Mồi giun")
	inv.add("moi")
	inv.use("moi")
	_check("hộp mồi = 5 lượt", fish.bait == 5 and inv.count("moi") == 0)
	var plain := 0.0
	var baited := 0.0
	fish._rng.seed = 7
	for i in 40:
		plain += fish._roll_wait()
	fish._spot = 0
	fish._cast_from = Vector3.ZERO
	fish._cast_to = Vector3(0, 0.3, 1)
	fish.state = Fishing.State.CAST
	fish._t = 0.999
	fish._do_cast(1.0)
	baited = fish._wait_timer
	_check("quăng cần tốn 1 lượt mồi", fish.bait == 4 and fish._baited)
	_check("có mồi chờ ngắn hơn", baited <= fish.wait_time.y * fish.bite_factor() * fish.bait_factor + 0.01,
			"chờ %.1f s (không mồi trung bình %.1f s)" % [baited, plain / 40.0])
	fish.state = Fishing.State.OFF
	fish._baited = false

	print("5) Biếu quà, việc nhờ")
	var kid: Villager = null
	var elder: Villager = null
	for v in vs.people:
		if v.role == "kid" and kid == null:
			kid = v
		if v.role == "elder" and elder == null:
			elder = v
	inv.add("keo_keo")
	inv.add("gao_tam")
	var m0 := int(dlg._met.get(kid, 0))
	inv.give(kid, "keo_keo", dlg)
	var m1 := int(dlg._met.get(kid, 0))
	inv.give(kid, "gao_tam", dlg)
	_check("trẻ con thích kẹo kéo +3, gạo +2", m1 - m0 == 3 and int(dlg._met.get(kid, 0)) - m1 == 2)
	dlg.npc = elder
	var opts := inv.dialog_options(elder, dlg)
	inv.add("chuoi", 1)
	_check("có câu biếu quà khi túi có đồ", opts.size() == 1 and str(opts[0].key) == "inv_gift")
	var money0 := inv.money
	var q := qs.make_quest(elder, "message")
	if q.is_empty():
		q = qs.make_quest(elder, "lost")
	qs.active.append(q)
	var reply := qs._finish(q)
	var gid := str(q.gift_id)
	_check("xong việc: quà vào túi + tiền công", inv.count(gid) >= 1 and inv.money - money0 == int(q.pay) and int(q.pay) >= 4,
			"%s + %d nghìn · \"%s\"" % [q.gift, int(q.pay), dlg.fill_for(elder, reply).left(70)])
	var kq := qs.make_quest(kid, "lost")
	_check("trẻ con nhờ việc không trả tiền", int(kq.get("pay", -1)) == 0)

	print("6) Thưởng trò chơi")
	var m2 := inv.money
	race.mode = "team"
	race.finished.emit(1, 49.0)
	_check("nhất đua thuyền rồng +10", inv.money - m2 == 10)
	race.finished.emit(3, 55.0)
	_check("về ba không có giải", inv.money - m2 == 10)
	var kl := inv.count("keo_lac")
	tug.finished.emit(true, 2, 0)
	tug.finished.emit(false, 1, 2)
	_check("thắng kéo co được gói kẹo lạc", inv.count("keo_lac") == kl + 1)
	var bd := inv.count("banh_da")
	oaq.over = true
	oaq.finished.emit(40, 30)
	oaq.over = false
	oaq.finished.emit(40, 30)        # bỏ dở: không tính
	_check("thắng ô ăn quan được bánh đa (bỏ dở không tính)", inv.count("banh_da") == bd + 1)

	print("7) Diều, sáo")
	rig.set_focus(Vector3(-8, 0, 14))
	rig.snap()
	fp.enter()
	await _frames(10)
	fp.global_position = Vector3(-8, fp.global_position.y, 14)
	await _frames(5)
	inv.add("dieu")
	_check("mở túi khi nhập vai", inv.show_inventory() and fp._suspended == "inventory")
	inv.use("dieu")
	await _frames(3)
	_check("thả diều của mình (túi gấp lại)", kite.phase != KiteFlying.Phase.OFF and not inv.open and kite.kid == null,
			"phase %d, %s" % [kite.phase, kite.self_refusal(fp.global_position)])
	await _frames(60)
	kite.finished.emit(12.0, 3.0, "snap")
	_check("đứt dây thì mất diều", inv.count("dieu") == 0)
	kite.stop()
	await _frames(3)
	_check("thôi thả diều thì đi tiếp", fp._suspended == "", fp._suspended)
	for i in 60:
		if snd.sounds.has("flute"):
			break
		await process_frame
	var fl: AudioStreamWAV = snd.sounds.get("flute")
	_check("tiếng sáo đã tổng hợp", fl != null and fl.data.size() > 16000 * 2 * 4, "%.1f s" % (fl.data.size() / 32000.0 if fl != null else 0.0))
	inv.add("sao")
	var p0 := int(snd.played.get("flute", 0))
	inv.use("sao")
	_check("thổi sáo phát tiếng, sáo còn trong túi", int(snd.played.get("flute", 0)) == p0 + 1 and inv.count("sao") == 1)

	print("8) Màn hình túi đồ")
	inv.show_inventory()
	inv.set_tab(1)
	var foods := inv._entries.size()
	inv.set_tab(4)
	fish.basket.append({"name": "Cá trê", "kg": 0.5})
	inv._refresh()
	_check("ngăn đồ ăn / giỏ cá", foods >= 2 and inv._entries.size() == 1 and inv._grid.get_child_count() == 1,
			"đồ ăn %d, cá %d" % [foods, inv._entries.size()])
	inv.close()
	_check("gấp túi thì đi tiếp", not inv.open and fp._suspended == "")
	dlg.start(elder, fp)
	_check("đang trò chuyện không mở túi", not inv.show_inventory())
	dlg.end()
	fp._resume()

	print("9) File lưu bản trước")
	inv.load_legacy({"money": 33, "bag": ["nải chuối", "cái nón lá", "nải chuối"], "gifts": ["gói chè Thái", "mấy viên bi"]})
	_check("tiền + đồ chợ + quà thành vật phẩm", inv.money == 33 and inv.count("chuoi") == 2 and inv.count("non_la") == 1
			and inv.count("che") == 1 and inv.count("bi") == 1, str(inv.items))

	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
