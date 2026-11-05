extends SceneTree
## Thử Đua thuyền (headless, bước 1/60 s, không cần render):
## 1) Thuyền rồng, không chướng ngại: từng cách chèo (không chèo / giữ W / trúng nhịp / trúng 70 % / gõ bừa).
## 2) Thuyền rồng có chướng ngại (5 lần rải khác nhau): chèo trúng nhịp + né vs chỉ giữ làn — hạng, thời gian,
##    số lần va của người chơi và của máy.
## 3) Thuyền đơn 10 thuyền có chướng ngại: làn xuất phát không chồng nhau, trong sông; các cách chơi × 5 lần.
## 4) Thuyền đơn 2 thuyền. 5) Lái đâm bờ. 6) Từ nhập vai: bảng chọn (phím 2, D, 3, E) → đua 10 thuyền → Esc.
## Dùng: godot --headless --path . -s tools/boat_race_test.gd
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

## Một cuộc đua trọn vẹn. strategy: none | hold | beat | beat70 | spam; steering: lane | dodge.
func _race(r: BoatRace, m: String, count: int, obs: bool, strategy: String, steering: String, seed_: int) -> Dictionary:
	r._rng.seed = seed_
	r.begin(m, count, obs)
	r.set_process(false)
	r.phase = BoatRace.Phase.RACE
	var dt := 1.0 / 60.0
	var next_spam := 0.0
	var t := 0.0
	while r.phase == BoatRace.Phase.RACE and t < 240.0:
		var b: Dictionary = r.boats[0]
		var want := r.ai_target_lat(b, 0) if steering == "dodge" else r._lane(0, float(b.s))
		var steer := clampf((0.3 * (float(b.lat) - want) - float(b.head)) * 3.0, -1.0, 1.0)
		r.step(dt, strategy != "none", steer)
		t += dt
		if strategy in ["beat", "beat70"]:
			if fmod(r._beat_t, r.beat_period) < dt and (strategy != "beat70" or randf() < 0.7):
				r.press_beat()
		elif strategy == "spam" and t >= next_spam:
			r.press_beat()
			next_spam = t + 0.12
	if r.phase == BoatRace.Phase.RACE and steering == "dodge":
		var b0: Dictionary = r.boats[0]
		var d0 := (float(b0.s) - r.start_s) * r.dir
		print("KẸT seed %d: d=%.1f lat=%.2f head=%.2f sp=%.2f want=%.2f lim=%.2f" % [seed_, d0, b0.lat, b0.head, b0.speed, r.ai_target_lat(b0, 0), r._lat_limit(b0)])
		for o in r.obstacles:
			if absf(float(o.d) - d0) < 12.0:
				print("   %s d=%.1f lat=%.2f hl=%.2f hs=%.2f" % [o.kind, o.d, o.lat, o.hl, o.hs])
		for i in range(1, r.boats.size()):
			var bb: Dictionary = r.boats[i]
			if absf((float(bb.s) - r.start_s) * r.dir - d0) < 6.0:
				print("   thuyền %d d=%.1f lat=%.2f" % [i, (float(bb.s) - r.start_s) * r.dir, bb.lat])
	var extra := 0.0
	while r.order.size() < r.boats.size() and extra < 60.0:
		r.step(dt, false, 0.0)
		extra += dt
	var place := r.order.find(0) + 1
	if place == 0:
		place = r.player_place()
	var ai_hits := 0
	var ai_left := 0
	var ai_times: Array[String] = []
	for i in range(1, r.boats.size()):
		ai_hits += int(r.boats[i].hits)
		ai_left += int(not r.boats[i].done)
		ai_times.append("%.0f" % float(r.boats[i].time))
	var res := {"place": place, "time": float(r.boats[0].time), "hits": int(r.boats[0].hits), "ai_hits": ai_hits,
			"ai_times": ", ".join(ai_times), "obstacles": r.obstacles.size(), "ai_left": ai_left}
	r.stop()
	r.set_process(true)
	return res

func _avg(r: BoatRace, m: String, count: int, obs: bool, strategy: String, steering: String) -> String:
	var places: Array[String] = []
	var tsum := 0.0
	var hsum := 0
	var aisum := 0
	var left := 0
	for k in 5:
		var res := await _race(r, m, count, obs, strategy, steering, 500 + k)
		places.append(str(res.place))
		tsum += float(res.time)
		hsum += int(res.hits)
		aisum += int(res.ai_hits)
		left += int(res.ai_left)
	return "%-6s %-5s hạng %s · TB %.1f s · bạn va %.1f lần · máy va TB %.1f lần/thuyền · máy không về %d" % [
			strategy, steering, "/".join(places), tsum / 5.0, hsum / 5.0, aisum / 5.0 / maxf(count - 1, 1), left]

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var r := scene.get_node("BoatRace") as BoatRace
	print("Bến đua ở %s, xuất phát s=%.0f, chiều %+d, dài %d m, sông dài %.0f m" % [
			r._station.global_position, r.start_s, int(r.dir), int(r.course_length), r.river.length])
	seed(7)
	# 1) Thuyền rồng, không chướng ngại
	print("1) Thuyền rồng 4 đội, không chướng ngại:")
	for strat in ["none", "hold", "beat", "beat70", "spam"]:
		var res := await _race(r, "team", 4, false, strat, "lane", 1802)
		print("   %-6s hạng %d · %.1f s · máy %s" % [strat, res.place, res.time, res.ai_times])
	# 2) Thuyền rồng có chướng ngại
	var probe := await _race(r, "team", 4, true, "none", "lane", 500)
	print("2) Thuyền rồng có chướng ngại (%d cái / đường đua):" % probe.obstacles)
	for st in [["beat", "dodge"], ["beat", "lane"], ["beat70", "dodge"], ["hold", "dodge"]]:
		print("   " + await _avg(r, "team", 4, true, st[0], st[1]))
	# 3) Thuyền đơn 10 thuyền
	r._use_mode("solo", 99)
	var lanes: Array[float] = []
	for i in r.boats.size():
		lanes.append(r._lane(i))
	var min_gap := 99.0
	for i in range(1, lanes.size()):
		min_gap = minf(min_gap, lanes[i] - lanes[i - 1])
	var lim := r._lat_limit(r.boats[0])
	print("3) Thuyền đơn: số thuyền tối đa %d, làn %.1f…%.1f m (giới hạn ±%.1f), khe hẹp nhất %.2f m (thuyền rộng %.2f m)" % [
			r.boats.size(), lanes[0], lanes[-1], lim, min_gap, float(r.boats[0].beam)])
	for st in [["beat", "dodge"], ["beat70", "dodge"], ["hold", "dodge"], ["beat", "lane"]]:
		print("   " + await _avg(r, "solo", 10, true, st[0], st[1]))
	var nob := await _race(r, "solo", 10, false, "beat", "lane", 77)
	print("   không chướng ngại, trúng nhịp: hạng %d · %.1f s · máy %s" % [nob.place, nob.time, nob.ai_times])
	# 4) Thuyền đơn 2 thuyền
	var two := await _race(r, "solo", 2, true, "beat70", "dodge", 9)
	print("4) Thuyền đơn 2 thuyền: hạng %d · %.1f s · máy %s" % [two.place, two.time, two.ai_times])
	r._use_mode("solo", 1)
	print("   xin 1 thuyền → còn %d thuyền (tối thiểu 2)" % r.boats.size())
	r._use_mode("team", 4)
	# 5) Lái đâm bờ
	r.begin("team", 4, false)
	r.set_process(false)
	r.phase = BoatRace.Phase.RACE
	var max_out := 0.0
	for k in 600:
		r.step(1.0 / 60.0, true, 1.0)
		max_out = maxf(max_out, absf(float(r.boats[0].lat)) - r._lat_limit(r.boats[0]))
	print("5) Lái hết lái 10 s: vượt mép %.2f m (≤ 0), tốc độ %.1f m/s" % [max_out, float(r.boats[0].speed)])
	r.stop()
	r.set_process(true)
	# 6) Từ nhập vai, qua bảng chọn
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	var st := r._station.global_transform * Vector3(0, 0.1, 1.8)
	rig.global_position = st
	fp.enter()
	fp.global_position = st
	await _frames(10)
	var tgt: Node = r._station.find_child("ClickTarget", true, false)
	(tgt.get_meta("activate") as Callable).call()
	await _frames(3)
	print("6) Bấm bến đua: %s, bảng chọn hiện %s, nhập vai tạm dừng '%s'" % [BoatRace.Phase.keys()[r.phase], r._setup.visible, fp._suspended])
	_key("dialog_2")
	await _frames(2)
	for k in 8:
		_key("cam_right")
		await _frames(2)
	var on_before := r.obstacles_on
	_key("dialog_3")
	await _frames(2)
	_key("dialog_3")
	await _frames(2)
	print("   phím 2 → %s, D × 8 → %d thuyền, phím 3 hai lần → chướng ngại %s→%s" % [r.mode, r.boats.size(), on_before, r.obstacles_on])
	_key("interact")
	await _frames(5)
	var vis := 0
	for b in r.solo_boats:
		vis += int((b.node as Node3D).visible)
	print("   E: %s, %d thuyền đơn hiện, thuyền rồng ẩn %s, %d chướng ngại, camera đua %s" % [
			BoatRace.Phase.keys()[r.phase], vis, not (r.team_boats[0].node as Node3D).visible, r.obstacles.size(), r._cam.current])
	_key("exit_interior")
	await _frames(5)
	vis = 0
	for b in r.solo_boats:
		vis += int((b.node as Node3D).visible)
	print("   Esc: %s, thuyền đơn hiện %d, thuyền rồng hiện %s, chướng ngại %d, nhập vai tiếp %s, camera nhập vai %s" % [
			BoatRace.Phase.keys()[r.phase], vis, (r.team_boats[0].node as Node3D).visible, r.obstacles.size(),
			fp._suspended == "" and fp.active, fp.camera.current])
	quit()
