extends SceneTree
## Thử Đua thuyền (headless):
## 1) Cân bằng: mô phỏng cả cuộc đua với từng cách chèo của người chơi (bước 1/60 s, không cần render):
##    không chèo / giữ W suốt / giữ W + gõ trúng nhịp / chèo có nghỉ lấy sức + trúng nhịp / gõ bừa liên tục.
## 2) Lái đâm bờ: bị đẩy lại trong sông, mất đà.
## 3) Vào từ nhập vai: bấm bến đua → đếm ngược → Esc → nhập vai tiếp ở bến.
## Dùng: godot --headless --path . -s tools/boat_race_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _race(r: BoatRace, strategy: String) -> String:
	r.start()
	r.set_process(false)
	r.phase = BoatRace.Phase.RACE
	var dt := 1.0 / 60.0
	var resting := false
	var next_spam := 0.0
	var hits := 0
	var t := 0.0
	while r.phase == BoatRace.Phase.RACE and t < 240.0:
		var b: Dictionary = r.boats[0]
		var rowing := strategy != "none"
		if strategy == "rest":
			if float(b.stamina) < 0.15:
				resting = true
			elif float(b.stamina) > 0.45:
				resting = false
			rowing = not resting
		# Giữ thuyền giữa làn
		var steer := clampf((0.12 * (float(b.lat) - r._lane(0)) - float(b.head)) * 3.0, -1.0, 1.0)
		r.step(dt, rowing, steer)
		t += dt
		if strategy in ["beat", "rest", "beat70"]:
			var off := fmod(r._beat_t, r.beat_period)
			if off < dt and (strategy != "beat70" or randf() < 0.7):
				var before := int(b.combo)
				r.press_beat()
				hits += int(int(b.combo) > before or int(b.combo) == 6)
		elif strategy == "spam" and t >= next_spam:
			r.press_beat()
			next_spam = t + 0.12
	var extra := 0.0
	while r.order.size() < r.boats.size() and extra < 40.0:
		r.step(dt, false, 0.0)
		extra += dt
	var place := r.order.find(0) + 1
	if place == 0:
		r._finish()
		place = r.player_place()
	var s := "%-6s hạng %d · %.1f s · thời gian máy %s" % [strategy, place, float(r.boats[0].time),
			", ".join(r.boats.slice(1).map(func(x: Dictionary) -> String: return "%.1f" % float(x.time)))]
	r.stop()
	r.set_process(true)
	return s

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
	# 1) Cân bằng
	seed(7)
	for strat in ["none", "hold", "beat", "beat70", "rest", "spam"]:
		print(await _race(r, strat))
	# 2) Lái đâm bờ
	r.start()
	r.set_process(false)
	r.phase = BoatRace.Phase.RACE
	var max_out := 0.0
	var bumps := 0
	for k in 600:
		r.step(1.0 / 60.0, true, 1.0)
		var lim: float = r.river.half_width(float(r.boats[0].s)) - 1.4
		max_out = maxf(max_out, absf(float(r.boats[0].lat)) - lim)
		if r._feedback == "Va bờ!" and r._feedback_t > 0.79:
			bumps += 1
			r._feedback_t = 0.0
	print("Lái hết lái 10 s: vượt mép %.2f m (≤ 0), va bờ %d lần, tốc độ %.1f m/s" % [max_out, bumps, float(r.boats[0].speed)])
	r.stop()
	r.set_process(true)
	# 3) Từ nhập vai
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	var st := r._station.global_transform * Vector3(0, 0.1, 1.8)
	rig.global_position = st
	fp.enter()
	fp.global_position = st
	await _frames(10)
	var tgt: Node = r._station.find_child("ClickTarget", true, false)
	(tgt.get_meta("activate") as Callable).call()
	await _frames(20)
	print("Vào đua: giai đoạn %s, camera đua %s, nhập vai tạm dừng '%s', đường đua hiện %s" % [
			BoatRace.Phase.keys()[r.phase], r._cam.current, fp._suspended, r._course.visible])
	var ev := InputEventAction.new()
	ev.action = "exit_interior"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(5)
	print("Esc: giai đoạn %s, nhập vai tiếp %s, camera nhập vai %s, cách bến %.1f m" % [
			BoatRace.Phase.keys()[r.phase], fp._suspended == "" and fp.active, fp.camera.current,
			fp.global_position.distance_to(r._station.global_position)])
	quit()
