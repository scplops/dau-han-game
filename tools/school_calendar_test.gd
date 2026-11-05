extends SceneTree
## Thử thời khoá biểu trường học + ngày lễ đình (headless, tua nhanh thời gian thật, giờ trong game đứng yên):
## - Thứ Hai đi học: 7:10 chào cờ, 8:00 trong lớp, 9:25 ra chơi, 12:00 về hết; Chủ nhật: không ai đến.
## - Vào lớp học lúc 8:00: có học sinh ngồi bàn + cô giáo.
## - Ngày rằm 7:00: người lớn ra đình lễ; vào đình thấy người đứng vái hương án. Ngày thường: không ai.
## Dùng: godot --headless --path . -s tools/school_calendar_test.gd
const SPEED := 4.0

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var dn := scene.get_node("DayNight") as DayNight
	dn.auto_run = false
	var cal := scene.get_node("Calendar") as LunarCalendar
	var sd := scene.get_node("SchoolDay") as SchoolDay
	var vs := scene.get_node("World/Villagers") as Villagers
	var he := scene.get_node("HouseEntry") as HouseEntry
	var folk := scene.get_node("IndoorFolk") as IndoorFolk
	var school := scene.get_node("World/School") as School
	Engine.time_scale = SPEED
	print("Hôm nay: %s" % cal.date_text())
	# Thứ Hai đi học, không phải ngày lễ
	var j := cal.jd
	while (j + 1) % 7 != 1 or int(cal.lunar_at(j).day) in [1, 15]:
		j += 1
	cal.set_jd(j)
	print("Ngày thử trường: %s · trường: %s" % [cal.date_text(), "mở" if cal.is_school_day() else "nghỉ"])
	for step: Array in [[6.2, 5], [6.6, 25], [7.2, 25], [8.0, 30], [9.35, 25], [10.0, 25], [12.0, 30]]:
		dn.time_of_day = float(step[0])
		await _frames(int(float(step[1]) * 60.0 / SPEED))
		var vis := 0
		var cls := 0
		var near_flag := 0
		var walking := 0
		for p in sd.pupils:
			if p.visible: vis += 1
			if p.has_meta("in_class"): cls += 1
			if p.visible and p.global_position.distance_to(school.flag_pos) < 9.0 and p.state == Villager.State.IDLE: near_flag += 1
			if p.state == Villager.State.WALK: walking += 1
		var kids_school := 0
		var kids_class := 0
		for v in vs.people:
			if v.has_meta("at_school"): kids_school += 1
			if v.has_meta("in_class"): kids_class += 1
		print("  %5.2fh [%s]  HS làng bên: hiện %d, trong lớp %d, đang đi %d, đứng quanh cột cờ %d | trẻ trong làng: ở trường %d, trong lớp %d" % [
				dn.time_of_day, sd.phase(dn.time_of_day), vis, cls, walking, near_flag, kids_school, kids_class])
		if is_equal_approx(float(step[0]), 8.0):
			# Vào lớp học xem bên trong
			he.enter_house(true, he.find_entry("school"))
			await _frames(30)
			var seated := 0
			var teacher := ""
			for f in folk._folk:
				if f.get("keeper", false):
					teacher = (f.proxy as Villager).display_name + " (" + (f.proxy as Villager).work_anim + ")"
				elif (f.proxy as Villager).work_anim == "study":
					seated += 1
			print("       trong lớp học: %d em ngồi học, giáo viên: %s" % [seated, teacher if teacher != "" else "không có"])
			he.exit_house(true)
			await _frames(10)
	# Chủ nhật
	var sunday := j + 6
	cal.set_jd(sunday)
	dn.time_of_day = 8.0
	sd.replan()
	vs.replan()
	await _frames(int(20.0 * 60.0 / SPEED))
	var vis_sun := 0
	for p in sd.pupils:
		if p.visible or p.has_meta("in_class"): vis_sun += 1
	var kids_sun := 0
	for v in vs.people:
		if v.has_meta("at_school") or v.activity == "school": kids_sun += 1
	print("Chủ nhật %s 8:00 [%s]: học sinh ở trường %d, trẻ trong làng đi học %d" % [cal.solar_text(), sd.phase(8.0), vis_sun, kids_sun])

	# Ngày rằm và ngày thường lúc 7:00
	for want_worship: bool in [false, true]:
		var k := cal.jd
		while (int(cal.lunar_at(k).day) in [1, 15]) != want_worship:
			k += 1
		cal.set_jd(k)
		dn.time_of_day = 7.0
		vs.replan()
		await _frames(int(45.0 * 60.0 / SPEED))
		var going := 0
		var inside := 0
		for v in vs.people:
			if v.activity == "worship": going += 1
			if v.has_meta("at_dinh"): inside += 1
		var decor := (scene.get_node("World/Village/WorshipDecor") as Node3D).visible
		print("%s 7:00: đi lễ đình %d người (đang trong đình %d), cờ hội + đỉnh hương: %s" % [cal.date_text(), going, inside, "có" if decor else "không"])
		if want_worship:
			he.enter_house(true, he.find_entry("dinh"))
			await _frames(30)
			var praying := 0
			for f in folk._folk:
				if not f.get("keeper", false) and (f.real as Villager).has_meta("at_dinh"):
					praying += 1
			print("       trong đình: %d người đang lễ, %d người tất cả (kể cả ông thủ từ)" % [praying, folk._folk.size()])
			he.exit_house(true)
			await _frames(10)
	Engine.time_scale = 1.0
	quit()
