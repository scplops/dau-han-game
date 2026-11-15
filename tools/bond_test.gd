extends SceneTree
## Thử mức thân quen (mục 56), headless: điểm → mức; lên bậc thì báo; chào khác đi; chuyện riêng (thân); quà mỗi ngày
## (thân thiết); chợ bớt giá; việc nhờ trả thêm công; sổ tay ghi mức.
## Dùng: timeout 110 godot --headless --path . -s tools/bond_test.gd

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(name_s: String, ok: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["OK" if ok else "SAI", name_s, ("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(name_s)


func _keys(dlg: Dialogue) -> Array:
	var out := []
	for o: Dictionary in dlg._build_options():
		out.append(str(o.get("key", "")))
	return out


func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var dlg := scene.get_node("Dialogue") as Dialogue
	var inv := scene.get_node("Inventory") as Inventory
	var market := scene.get_node("World/Market") as Market
	var qs := scene.get_node("Quests") as Quests
	var nb := scene.get_node("Notebook") as Notebook
	var cal := scene.get_node("Calendar") as LunarCalendar
	var vs := scene.get_node("World/Villagers") as Villagers
	var dn := scene.get_node("DayNight") as DayNight
	dn.auto_run = false
	dn.time_of_day = 10.0
	inv.reset()
	var farmer: Villager = null
	var carrier: Villager = null
	for v in vs.people:
		if v.role == "farmer" and farmer == null and not v.get_meta("female", false):
			farmer = v
		if v.role == "carrier" and carrier == null:
			carrier = v
	_check("điểm → mức", Dialogue.bond_of(0) == 0 and Dialogue.bond_of(1) == 1 and Dialogue.bond_of(5) == 1 and Dialogue.bond_of(6) == 2
			and Dialogue.bond_of(13) == 2 and Dialogue.bond_of(14) == 3 and Dialogue.bond_of(99) == 3)
	var ups := []
	dlg.bond_changed.connect(func(v: Villager, lv: int) -> void: ups.append([v.display_name, lv]))
	dlg.npc = farmer
	dlg.add_bond(farmer, 1)
	var g1 := dlg.fill_for(farmer, dlg._greeting())
	_check("mới quen: chưa có chuyện riêng", dlg.bond(farmer) == 1 and not _keys(dlg).has("story") and ups.is_empty(), g1)
	dlg.add_bond(farmer, 5)
	dlg._asked.clear()
	var g2 := dlg.fill_for(farmer, dlg._greeting())
	_check("6 điểm: thân — báo lên bậc, chào thân mật, có câu kể chuyện riêng", dlg.bond(farmer) == 2 and ups == [[farmer.display_name, 2]]
			and _keys(dlg).has("story") and not _keys(dlg).has("treat") and g2 != g1, g2)
	var story := dlg.fill_for(farmer, dlg._ans_story())
	_check("chuyện riêng theo vai, mỗi người một chuyện cố định", story.length() > 40 and story == dlg.fill_for(farmer, dlg._ans_story()), story.left(80))
	dlg.add_bond(farmer, 8)
	dlg._asked.clear()
	_check("14 điểm: thân thiết — có câu hỏi thăm", dlg.bond(farmer) == 3 and ups.size() == 2 and _keys(dlg).has("treat"))
	var n0 := inv.order.size()
	var treat := dlg.fill_for(farmer, dlg._ans_treat())
	dlg._asked.clear()
	_check("hỏi thăm: được dúi quà, hôm nay không cho nữa", inv.order.size() == n0 + 1 and not _keys(dlg).has("treat"), treat.left(80))
	cal.add_days(1)
	_check("hôm sau lại cho", _keys(dlg).has("treat"))
	# Chợ bớt giá
	dlg.npc = carrier
	var base := Inventory.price_of("non_la")
	var p0 := market.price_for("non_la", dlg)
	dlg.add_bond(carrier, 6)
	var p2 := market.price_for("non_la", dlg)
	dlg.add_bond(carrier, 8)
	var p3 := market.price_for("non_la", dlg)
	_check("người bán thân thì bớt giá 10 % / 20 %", p0 == base and p2 == int(round(base * 0.9)) and p3 == int(round(base * 0.8)), "%d → %d → %d nghìn" % [p0, p2, p3])
	inv.money = 50
	market.buy("non_la", p3)
	_check("mua theo giá đã bớt", inv.money == 50 - p3 and inv.count("non_la") == 1)
	# Việc nhờ trả thêm công
	var q := qs.make_quest(farmer, "message")
	if q.is_empty():
		q = qs.make_quest(farmer, "lost")
	qs.active.append(q)
	var pay := int(q.pay)
	var m0 := inv.money
	qs._finish(q)
	_check("người thân thiết trả thêm 3 nghìn công", pay > 0 and inv.money == m0 + pay + 3, "công %d + 3" % pay)
	var page := nb.page_text(2)
	_check("sổ tay ghi mức thân", page.contains("thân thiết") and page.contains("điểm"))
	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
