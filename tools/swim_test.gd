extends SceneTree
## Thử tắm sông + người chơi bơi (mục 49), headless:
## 1) Lịch: trọng số việc tắm sông của trẻ con theo mùa / giờ / ngày nghỉ / mưa.
## 2) Chiều hè ngày đi học 16:36: để làng tự chạy (tua ×4) — trẻ tan học chạy ra bến, nhảy xuống, bơi (nằm sấp, trong
##    nước), con trai cởi trần; 19:00 lên bờ, gỡ sạch meta, đứng thẳng, mặc áo lại.
## 3) Người chơi: xuống sông thì bơi (mắt sát mặt nước, tốc độ bơi / bơi sải), bọn trẻ gọi; lên bờ thì đi bộ lại.
## Dùng: timeout 500 godot --headless --path . -s tools/swim_test.gd

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
	var cal := scene.get_node("Calendar") as LunarCalendar
	var dn := scene.get_node("DayNight") as DayNight
	dn.auto_run = false
	var vs := scene.get_node("World/Villagers") as Villagers
	var sd := scene.get_node("SchoolDay") as SchoolDay
	var rs := scene.get_node("RiverSwim") as RiverSwim
	var river := scene.get_node("World/River") as River
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	var hud := scene.get_node("HUD") as Hud
	var kid: Villager = null
	for v in vs.people:
		if v.role == "kid":
			kid = v
			break

	print("1) Lịch tắm sông")
	cal.set_date_string("2027-06-22")       # thứ Ba, mùa hạ
	await _frames(70)
	_check("mùa hạ, ngày đi học", vs.season == "summer" and cal.is_school_day() and cal.weekday() == 2, "%s · %s" % [vs.season, cal.date_text()])
	_check("17:00 sau giờ học: rất muốn tắm", rs.weight(kid, 17.0) == rs.summer_weight and rs.swim_time(17.0))
	_check("15:00 ngày đi học: chưa tới giờ", rs.weight(kid, 15.0) == rs.summer_off_weight and not rs.swim_time(15.0))
	_check("18:30: muộn rồi không rủ đi nữa", rs.weight(kid, 18.3) == rs.summer_off_weight)
	w.set_weather("drizzle", true)
	await _frames(3)
	_check("mưa phùn: không tắm", rs.weight(kid, 17.0) == 0.0)
	w.set_weather("clear", true)
	cal.set_date_string("2027-06-27")       # Chủ nhật
	await _frames(70)
	_check("Chủ nhật 15:00: tắm từ đầu giờ chiều", rs.weight(kid, 15.0) == rs.summer_weight, cal.date_text())
	cal.set_date_string("2027-01-12")
	await _frames(70)
	_check("mùa đông: không tắm", vs.season == "winter" and rs.weight(kid, 17.0) == 0.0, vs.season)
	cal.set_date_string("2027-10-05")
	await _frames(70)
	_check("mùa thu buổi chiều: thỉnh thoảng", rs.weight(kid, 15.0) == rs.mild_weight, vs.season)

	print("2) Chiều hè tan học")
	cal.set_date_string("2027-06-22")
	dn.time_of_day = 16.6
	await _frames(70)
	vs.replan()
	await process_frame
	sd.replan()
	Engine.time_scale = 4.0
	var max_swim := 0
	var going_max := 0
	for step in 14:
		await _frames(150)                  # ~10 s mô phỏng mỗi nhịp
		dn.time_of_day = minf(16.6 + step * 0.13, 18.4)
		var going := 0
		for v in vs.people:
			if v.activity == "swim" and not v.has_meta("swimming"):
				going += 1
		going_max = maxi(going_max, going)
		max_swim = maxi(max_swim, rs.swimmers.size())
		if step % 3 == 2:
			print("   %4.1f h: đang chạy ra sông %d · đang tắm %d · đã xuống %d · đã lên %d" % [dn.time_of_day, going, rs.swimmers.size(), int(rs.stats.joined), int(rs.stats.left)])
	# Số đứa "đang trên đường" chỉ lấy mẫu 10 s một lần nên dao động; tổng số đã xuống sông mới ổn định
	_check("trẻ con rủ nhau chạy ra sông", going_max >= 3 and int(rs.stats.joined) >= 14,
			"nhiều nhất %d đứa cùng trên đường · tổng %d lượt xuống sông" % [going_max, int(rs.stats.joined)])
	_check("nhiều đứa cùng tắm", max_swim >= 6, "nhiều nhất %d đứa" % max_swim)
	var in_water := 0
	var prone := 0
	var boys := 0
	var bare := 0
	var girls_dressed := true
	var by_landing := {}
	for s: Dictionary in rs.swimmers:
		var v: Villager = s.v
		by_landing[int(s.li)] = int(by_landing.get(int(s.li), 0)) + 1
		if str(s.phase) == "enter":
			continue
		if river.is_water(Vector2(v.global_position.x, v.global_position.z), 0.3):
			in_water += 1
		if str(s.phase) == "swim" and v.rotation.x > 1.0 and absf(v.global_position.y - (river.water_level + rs.swim_feet)) < 0.08 and v.work_anim == "swim":
			prone += 1
		if v.get_meta("female", false):
			girls_dressed = girls_dressed and v.outfit != "shirtless"
		else:
			boys += 1
			if v.outfit == "shirtless":
				bare += 1
	var swim_phase := 0
	var settled := 0
	for s: Dictionary in rs.swimmers:
		if str(s.phase) != "enter":
			settled += 1
		if str(s.phase) == "swim":
			swim_phase += 1
	_check("ai đã xuống đều ở trong nước", in_water == settled and settled > 0, "%d / %d · theo bến %s" % [in_water, settled, by_landing])
	_check("đang bơi thì nằm sấp sát mặt nước, dáng bơi", prone >= maxi(swim_phase - 2, 1), "%d / %d đứa đang bơi" % [prone, swim_phase])
	_check("con trai cởi trần, con gái mặc áo", bare == boys and girls_dressed, "%d / %d con trai" % [bare, boys])
	_check("có té nước, có reo", int(rs.stats.splashes) > 20 and int(rs.stats.barks) > 0, "%d gợn nước · %d câu reo" % [int(rs.stats.splashes), int(rs.stats.barks)])

	print("3) Người chơi bơi")
	Engine.time_scale = 1.0
	var s0: Dictionary = rs.swimmers[0] if not rs.swimmers.is_empty() else {}
	var li := int(s0.get("li", 0))
	var edge: Vector3 = river.landings[li].edge
	rig.set_focus(Vector3(edge.x, 0, edge.z))
	rig.snap()
	fp.enter()
	await _frames(10)
	_check("đứng trên bờ: không bơi", not fp.swimming and absf(fp.camera.position.y - fp.eye_height) < 0.1)
	var z: Dictionary = rs._zones[li]
	var smp := river.sample(float(z.s0))
	var hw := river.half_width(float(z.s0))
	var n := (smp[1] as Vector2).orthogonal() * float(z.side)
	var q := (smp[0] as Vector2) + n * (hw - 5.0)        # cách mép nước 5 m
	fp.global_position = Vector3(q.x, river.water_level, q.y)
	fp.velocity = Vector3.ZERO
	await _frames(60)
	var eye_y := fp.camera.global_position.y
	_check("xuống sông: bơi, mắt sát mặt nước", fp.swimming and absf(eye_y - (river.water_level + fp.swim_eye)) < 0.08,
			"mắt cao %.2f m (mặt nước %.2f) · HUD \"%s\"" % [eye_y, river.water_level, hud._info_label.text.split("  ·  ")[0]])
	# Bơi dọc sông
	fp.rotation.y = atan2(-(smp[1] as Vector2).x, -(smp[1] as Vector2).y)
	Input.action_press("cam_forward")
	await _frames(60)
	var a := fp.global_position
	await _frames(120)
	var sp := a.distance_to(fp.global_position) / 2.0
	Input.action_press("fp_run")
	await _frames(60)
	a = fp.global_position
	await _frames(120)
	var sp_fast := a.distance_to(fp.global_position) / 2.0
	Input.action_release("fp_run")
	Input.action_release("cam_forward")
	_check("tốc độ bơi / bơi sải", absf(sp - fp.swim_speed) < 0.15 and absf(sp_fast - fp.swim_fast_speed) < 0.25 and fp.swimming,
			"%.2f m/s · sải %.2f m/s (đi bộ %.1f)" % [sp, sp_fast, fp.walk_speed])
	Input.action_press("fp_jump")
	await _frames(3)
	Input.action_release("fp_jump")
	await _frames(10)
	_check("đang bơi không nhảy được", fp.global_position.y < river.water_level)
	# Bơi lại gần bọn trẻ
	if not rs.swimmers.is_empty():
		var kv: Villager = rs.swimmers[0].v
		fp.global_position = Vector3(kv.global_position.x + 2.0, river.water_level, kv.global_position.z)
		rs._greet_t = 0.0
		await _frames(30)
		_check("bọn trẻ gọi người chơi", int(rs.stats.greets) >= 1)
	# Lên bờ
	fp.global_position = fp._ground_spawn(Vector3(edge.x, 0, edge.z) + Vector3(n.x, 0, n.y) * 6.0)
	await _frames(60)
	_check("lên bờ: đi bộ lại, mắt cao như cũ", not fp.swimming and absf(fp.camera.position.y - fp.eye_height) < 0.1,
			"mắt %.2f" % fp.camera.position.y)
	fp.exit()

	print("4) Chập tối lên bờ")
	var were: Array[Villager] = []
	for s: Dictionary in rs.swimmers:
		were.append(s.v)
	dn.time_of_day = 19.0
	Engine.time_scale = 4.0
	await _frames(500)
	Engine.time_scale = 1.0
	var clean := true
	var home := 0
	for v in were:
		if v.has_meta("swimming") or v.has_meta("talking") or absf(v.rotation.x) > 0.01 or v.outfit == "shirtless" or v.work_anim == "swim":
			clean = false
		if v.activity in ["inside", "shelter"]:
			home += 1
	_check("19:00 lên bờ hết, gỡ sạch", rs.swimmers.is_empty() and clean and not were.is_empty(), "%d đứa, %d đang về nhà" % [were.size(), home])

	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
