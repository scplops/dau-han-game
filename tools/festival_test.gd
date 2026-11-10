extends SceneTree
## Thử lễ hội (mục 41), headless: ngày thường (không trang trí) → 28 Chạp (Tết: cây nêu, đào, cờ) → giao thừa + sáng
## mùng 1 (đốt pháo) → chúc Tết người lớn (được mừng tuổi) / trẻ con (mừng tuổi 1 nghìn), mỗi người một lần → rằm tháng
## Giêng (cờ hội) → rằm tháng Tám 19:00 (trẻ con rước đèn ông sao dọc đường trục, quay đầu ở hai đầu) → 21:00 tan.
## Dùng: godot --headless --path . -s tools/festival_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _goto(cal: LunarCalendar, m: int, d: int) -> void:
	for i in 420:
		var l := cal.lunar()
		if int(l.month) == m and int(l.day) == d and not bool(l.leap):
			return
		cal.add_days(1)

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
	var fe := scene.get_node("Festival") as Festival
	var vs := scene.get_node("World/Villagers") as Villagers
	var mk := scene.get_node("World/Market") as Market
	var dlg := scene.get_node("Dialogue") as Dialogue
	dn.time_of_day = 10.0
	await _frames(70)
	print("Hôm nay %s: lễ '%s' · Tết %s · cờ %s · Trung thu %s" % [cal.date_text(), fe.mode, fe._tet.visible, fe._bunting.visible, fe._moon.visible])
	_goto(cal, 12, 28)
	await _frames(70)
	print("1) %s: lễ '%s' · cây nêu + đào %s · cờ %s · chúc Tết được chưa %s · sổ tay: %s" % [cal.date_text(), fe.mode, fe._tet.visible, fe._bunting.visible, fe.is_tet_days(), fe.status_text()])
	# Giao thừa
	_goto(cal, 12, 29)
	var l := cal.lunar_at(cal.jd + 1)
	if int(l.month) == 12:
		cal.add_days(1)
	dn.time_of_day = 23.9
	await _frames(70)
	dn.time_of_day = 23.99
	cal.add_days(1)
	dn.time_of_day = 0.05
	await _frames(80)
	var f1 := fe.firecrackers
	dn.time_of_day = 5.9
	await _frames(70)
	dn.time_of_day = 6.05
	await _frames(80)
	print("2) %s: pháo giao thừa %d đợt, thêm sáng mùng 1 → %d đợt · đang nổ %s" % [cal.date_text(), f1, fe.firecrackers, fe._crack_t > 0.0])
	# Chúc Tết
	var adult: Villager = null
	var kid: Villager = null
	for v in vs.people:
		if v.role == "farmer" and adult == null:
			adult = v
		if v.role == "kid" and kid == null:
			kid = v
	var m0 := mk.money
	dlg.npc = adult
	var o := fe.dialog_options(adult, dlg)
	var a1 := dlg._fill((o[0].answer as Callable).call()) if not o.is_empty() else "KHÔNG CÓ CÂU"
	print("3) Chúc Tết %s: \"%s\" · tiền %d → %d · chúc lần nữa còn câu %s" % [adult.display_name, a1, m0, mk.money, not fe.dialog_options(adult, dlg).is_empty()])
	dlg.npc = kid
	var m1 := mk.money
	o = fe.dialog_options(kid, dlg)
	print("   Chúc Tết %s: \"%s\" · tiền %d → %d" % [kid.display_name, dlg._fill((o[0].answer as Callable).call()), m1, mk.money])
	_goto(cal, 1, 15)
	await _frames(70)
	print("4) %s: lễ '%s' · cờ %s · cây nêu %s" % [cal.date_text(), fe.mode, fe._bunting.visible, fe._tet.visible])
	# Trung thu
	_goto(cal, 8, 15)
	dn.time_of_day = 18.6
	vs.replan()
	await _frames(70)
	Engine.time_scale = 4.0
	var max_par := 0
	var turned := 0
	var zmin := 0.0
	var zmax := -999.0
	for i in 60 * 40:
		await physics_frame
		if i % 60 == 0:
			var n := 0
			for v in vs.people:
				if v.activity == "trungthu" and v.get_node_or_null("StarLantern") != null and (v.get_node("StarLantern") as Node3D).visible:
					n += 1
					zmin = minf(zmin, v.global_position.z)
					zmax = maxf(zmax, v.global_position.z)
					if v.has_meta("parade_to_gate") and not bool(v.get_meta("parade_to_gate")):
						turned += 1
			max_par = maxi(max_par, n)
	Engine.time_scale = 1.0
	var walking := 0
	for v in vs.people:
		if v.activity == "trungthu":
			walking += 1
	print("5) %s 18:36, 160 s: lễ '%s' · trẻ đi rước đèn %d · nhiều nhất %d đứa cầm đèn ông sao · đi suốt z %.0f…%.0f · mâm cỗ %s" % [cal.date_text(), fe.mode, walking, max_par, zmax, zmin, fe._moon.visible])
	dn.time_of_day = 21.0
	Engine.time_scale = 4.0
	await _frames(60 * 45)
	Engine.time_scale = 1.0
	var left := 0
	var lit := 0
	for v in vs.people:
		if v.activity == "trungthu":
			left += 1
		var sl := v.get_node_or_null("StarLantern") as Node3D
		if sl != null and sl.visible:
			lit += 1
	print("   21:00 sau 180 s: còn rước %d · đèn còn sáng %d" % [left, lit])
	quit()
