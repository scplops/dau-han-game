extends SceneTree
## Thử chợ phiên (mục 40), headless:
## 1) Ngày phiên (âm lịch chia 5 dư 1) 6:30 → chợ mở, hàng bày ra, người bán ngồi đủ các sạp, người đi chợ tới (tua ×4).
## 2) Trò chuyện với người bán (nhập vai): xem hàng → mua (trừ tiền, vào giỏ đồ) → không đủ tiền thì không bán; hàng cá
##    mua cá trong giỏ (cân × giá); biếu quà cho một người khác (bớt giỏ, quen thêm).
## 3) 11:30 tan chợ: hàng cất, người bán về; ngày không có phiên thì đóng, sổ tay báo phiên tới.
## 4) Lưu / nạp tiền + giỏ đồ.
## Dùng: godot --headless --path . -s tools/market_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _opt(dlg: Dialogue, key: String) -> int:
	for i in dlg._options.size():
		if str(dlg._options[i].get("key", "")) == key:
			return i
	return -1

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var cal := scene.get_node("Calendar") as LunarCalendar
	var dn := scene.get_node("DayNight") as DayNight
	dn.auto_run = false
	var mk := scene.get_node("World/Market") as Market
	var inv := scene.get_node("Inventory") as Inventory
	var vs := scene.get_node("World/Villagers") as Villagers
	while int(cal.lunar().day) % 5 != 1 or cal.weekday() == 0:
		cal.add_days(1)
	dn.time_of_day = 6.3
	vs.replan()
	await _frames(70)
	print("Ngày %s · phiên chợ %s · %d sạp" % [cal.date_text(), mk.is_market_day(), mk.stalls.size()])
	# 1) Chợ họp
	Engine.time_scale = 4.0
	for i in 60 * 30:
		await physics_frame
	Engine.time_scale = 1.0
	var seated := 0
	for st in mk.stalls:
		var s: Villager = st.seller
		if s != null and s.has_meta("market_seller") and s.work_anim == "sit":
			seated += 1
	var shoppers := 0
	for v in vs.people:
		if v.activity == "market" and v.visible and v.global_position.distance_to(mk.origin) < 12.0:
			shoppers += 1
	print("1) 6:30 chợ mở %s · hàng bày %s · người bán ngồi sạp %d/%d · người đi chợ đang ở chợ %d" % [mk.is_open, mk._goods.visible, seated, mk.stalls.size(), shoppers])
	# 2) Mua bán
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var dlg := scene.get_node("Dialogue") as Dialogue
	var fish := scene.get_node("Fishing") as Fishing
	var rig := scene.get_node("CameraRig") as CameraRig
	rig.global_position = mk.origin
	fp.enter()
	await _frames(5)
	var sweets: Dictionary = {}
	var fishst: Dictionary = {}
	for st in mk.stalls:
		if st.kind == "sweets":
			sweets = st
		if st.kind == "fish":
			fishst = st
	var seller: Villager = sweets.seller
	if seller == null:
		print("2) KHÔNG có người bán hàng bánh kẹo")
		quit()
		return
	fp.global_position = (sweets.front as Vector3) + Vector3(0, 0.1, 0)
	await _frames(3)
	var m0 := inv.money
	dlg.start(seller, fp)
	fp._suspend("talk")
	dlg._options = dlg._build_options()
	var i_buy := _opt(dlg, "mk_buy")
	print("2) Nói chuyện với %s (%s): có câu xem hàng %s" % [seller.display_name, sweets.name, i_buy >= 0])
	dlg._choose(i_buy)
	var item_txt := str(dlg._options[0].text)
	dlg._choose(0)
	print("   %s → tiền %d → %d, túi đồ %s" % [item_txt, m0, inv.money, inv.items])
	inv.money = 0
	dlg._choose(1)
	print("   hết tiền mua tiếp: túi đồ vẫn %d món, lời người bán: \"%s\"" % [inv.total_items(), dlg._text_label.text.left(70)])
	dlg.end()
	fp._resume()
	# Bán cá
	fish.basket.clear()
	fish.basket.append({"name": "Cá chép", "kg": 1.5})
	fish.basket.append({"name": "Cá diếc", "kg": 0.3})
	var fs: Villager = fishst.seller
	dlg.start(fs, fp)
	fp._suspend("talk")
	dlg._options = dlg._build_options()
	var i_sell := _opt(dlg, "mk_sell")
	dlg._choose(i_sell)
	dlg._choose(0)                      # "Bán cá trong giỏ"
	print("   hàng cá mua giỏ cá (chép 1,5 kg + diếc 0,3 kg): có câu %s · tiền %d nghìn (mong đợi ~44) · giỏ cá còn %d" % [i_sell >= 0, inv.money, fish.basket.size()])
	dlg.end()
	fp._resume()
	# Biếu quà
	var friend: Villager = null
	for v in vs.people:
		if v.role == "elder" and v.visible and not v.has_meta("market_seller"):
			friend = v
			break
	friend.global_position = fp.global_position + Vector3(1.2, 0, 0)
	var met0 := int(dlg._met.get(friend, 0))
	dlg.start(friend, fp)
	fp._suspend("talk")
	dlg._options = dlg._build_options()
	var i_gift := _opt(dlg, "inv_gift")
	dlg._choose(i_gift)
	dlg._choose(0)
	print("   biếu %s: có câu %s · túi đồ còn %d · quen thêm %d" % [friend.display_name, i_gift >= 0, inv.total_items(), int(dlg._met.get(friend, 0)) - met0])
	dlg.end()
	fp._resume()
	# 4) Lưu / nạp
	var sg := scene.get_node("SaveGame") as SaveGame
	inv.add("non_la")
	var snap := sg.snapshot()
	var before := [inv.money, inv.items.duplicate()]
	inv.reset()
	sg.apply(snap)
	print("4) Lưu / nạp: tiền %d · túi đồ %s · khớp %s" % [inv.money, inv.items, [inv.money, inv.items] == before])
	# 3) Tan chợ
	dn.time_of_day = 11.6
	await _frames(90)
	var still := 0
	for v in vs.people:
		if v.has_meta("market_seller"):
			still += 1
	print("3) 11:36 tan chợ: mở %s · hàng cất %s · còn ngồi bán %d" % [mk.is_open, not mk._goods.visible, still])
	cal.add_days(1)
	dn.time_of_day = 8.0
	await _frames(90)
	print("   hôm sau 8:00: phiên chợ %s · mở %s · sổ tay: \"%s\"" % [mk.is_market_day(), mk.is_open, mk.status_text()])
	quit()
