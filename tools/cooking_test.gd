extends SceneTree
## Thử nấu ăn (mục 55), headless: ngoài sân không nấu được; vào nhà mình: nấu cơm, trứng rán (trứng gà hoặc vịt), canh,
## cá kho bằng cá trong giỏ, mâm cơm; thiếu nguyên liệu thì không nấu; ăn mâm cơm no lâu; lưu / nạp.
## Dùng: timeout 110 godot --headless --path . -s tools/cooking_test.gd

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(name_s: String, ok: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["OK" if ok else "SAI", name_s, ("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(name_s)


func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var inv := scene.get_node("Inventory") as Inventory
	var he := scene.get_node("HouseEntry") as HouseEntry
	var fishing := scene.get_node("Fishing") as Fishing
	inv.reset()
	var ok_cat := true
	for r: Dictionary in Inventory.RECIPES:
		ok_cat = ok_cat and Inventory.ITEMS.has(str(r.gives))
		for need: Array in r.needs:
			for alt: String in need[0]:
				ok_cat = ok_cat and (alt == "@fish" or Inventory.ITEMS.has(alt))
	_check("9 công thức, nguyên liệu và món đều có trong danh mục", ok_cat and Inventory.RECIPES.size() == 9)
	inv.add("gao_tam", 1)
	inv.add("trung_vit", 1)
	inv.add("hanh", 2)
	inv.add("rau_cai", 1)
	inv.add("tep", 1)
	fishing.basket.append({"name": "Cá diếc", "kg": 0.2})
	fishing.basket.append({"name": "Cá chép", "kg": 1.4})
	fishing.basket.append({"name": "Cá trê", "kg": 0.6})
	_check("ngoài sân: không nấu được", not inv.at_kitchen() and inv.can_cook("com") and inv.cook("com") == "" and inv.count("gao_tam") == 1)
	he.enter_house(true, he.find_entry("house_3"))
	for i in 5:
		await process_frame
	_check("nhà người khác: không nấu được", he.inside and not inv.at_kitchen())
	he.exit_house(true)
	for i in 5:
		await process_frame
	he.enter_house(true)
	for i in 5:
		await process_frame
	_check("trong nhà mình: có bếp", inv.at_kitchen())
	_check("nấu cơm: 1 cân gạo → 4 bát", inv.cook("com") != "" and inv.count("com") == 4 and inv.count("gao_tam") == 0)
	_check("hết gạo: không nấu cơm nữa", not inv.can_cook("com") and inv.cook("com") == "")
	_check("trứng rán bằng trứng vịt + hành", inv.cook("trung") != "" and inv.count("trung_ran") == 2 and inv.count("trung_vit") == 0 and inv.count("hanh") == 1)
	_check("canh rau cải + tép", inv.cook("canh") != "" and inv.count("canh_rau") == 2)
	_check("cá kho: lấy con cá nhỏ nhất đủ cân trong giỏ (cá trê 0,6 kg)", inv.cook("ca_kho") != "" and inv.count("ca_kho") == 1
			and fishing.basket.size() == 2 and str(fishing.basket[1].name) == "Cá chép" and inv.count("hanh") == 0)
	_check("hết hành: không kho cá nữa", not inv.can_cook("ca_kho"))
	_check("mâm cơm: 2 cơm + cá kho + canh", inv.cook("mam") != "" and inv.count("mam_com") == 1 and inv.count("com") == 2
			and inv.count("ca_kho") == 0 and inv.count("canh_rau") == 1)
	inv.energy = 0.0
	inv.use("mam_com")
	_check("ăn mâm cơm: no căng", inv.energy == inv.energy_cap and inv.count("mam_com") == 0, "no %d giây" % int(inv.energy))
	# Màn hình: ngăn Nấu ăn
	var opened := inv.show_inventory()
	inv.set_tab(5)
	_check("mở túi trong nhà, ngăn Nấu ăn có 9 công thức", opened and inv._entries.size() == 9
			and str(inv._entries[0].kind) == "recipe")
	inv.add("khoai", 1)
	inv._refresh()
	inv._select(2)
	inv._use_selected()
	_check("E trong ngăn Nấu ăn: nướng khoai", inv.count("khoai_nuong") == 3 and inv.count("khoai") == 0 and inv.cooked == 6, "đã nấu %d lần" % inv.cooked)
	inv.close()
	var snap := inv.snapshot()
	inv.reset()
	inv.load_data(snap)
	_check("lưu / nạp", inv.count("khoai_nuong") == 3 and inv.cooked == 6)
	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
