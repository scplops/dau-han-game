extends SceneTree
## Thử Thả diều (headless):
## 1) Mô phỏng 90 s bay (bước 1/60 s) với từng cách chơi × thời tiết, mỗi ô 6 lần gieo gió khác nhau:
##    để mặc / giật dây suốt / thả dây suốt / chơi khéo (thả dây khi căng, giật khi diều chúc xuống).
## 2) Trong game: chỗ thoáng (bờ ruộng) và dưới gốc đa → lời trẻ con; rủ qua hội thoại → thả → Esc thu
##    diều → bảng kết quả → Esc trả diều → nhập vai tiếp.
## Dùng: godot --headless --path . -s tools/kite_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _fly(k: KiteFlying, policy: String, seed_: int) -> Array:
	k._rng.seed = seed_
	k._down = k._down_dir()
	k._hand = Vector3(0, 1.25, 0)
	k._launch()
	var dt := 1.0 / 60.0
	var t := 0.0
	var letting := false
	while k.phase == KiteFlying.Phase.FLY and t < 90.0:
		var pull := false
		var reel := 0.0
		match policy:
			"pull":
				pull = true
			"letout":
				reel = 1.0
			"climb":    # khéo tới 60 m dây rồi để mặc
				if k.line < 60.0:
					if k.tension > 0.85 or k.strain > 0.2:
						reel = 1.0
					elif k.el < 0.5:
						pull = true
					elif k.tension < 0.55 and k.el > 0.7:
						reel = 1.0
			"smart":
				if k.tension > 0.85 or k.strain > 0.2:
					reel = 1.0
				elif k.el < 0.5:
					pull = true
				elif k.tension < 0.55 and k.el > 0.7:
					reel = 1.0
		k.step(dt, pull, reel, 0.0)
		t += dt
	var r: String = k.reason if k.reason != "" else "bay"
	return [k.max_height, t, r]

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	await _frames(5)
	var k := scene.get_node("KiteFlying") as KiteFlying
	k.set_process(false)
	# 1) Mô phỏng
	for kind in ["clear", "cloudy"]:
		w.set_weather(kind, true)
		w.wind = Weather.PRESETS[kind].wind
		for policy in ["idle", "pull", "letout", "climb", "smart"]:
			var hs: Array[String] = []
			var ends := {}
			var best := 0.0
			var total := 0.0
			for s in 6:
				var r := _fly(k, policy, 100 + s)
				hs.append("%d" % int(r[0]))
				ends[r[2]] = int(ends.get(r[2], 0)) + 1
				best = maxf(best, float(r[0]))
				total += float(r[1])
			print("%-7s %-7s cao nhất %s m · bay TB %.0f s · kết thúc %s" % [kind, policy, "/".join(hs), total / 6.0, ends])
	k.phase = KiteFlying.Phase.OFF
	k.set_process(true)
	# 2) Trong game
	w.set_weather("clear", true)
	var dn := scene.get_node("DayNight") as DayNight
	dn.time_of_day = 15.0
	var vs := scene.get_node("World/Villagers") as Villagers
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var dlg := scene.get_node("Dialogue") as Dialogue
	var rig := scene.get_node("CameraRig") as CameraRig
	var kid: Villager = null
	for v in vs.people:
		if v.role == "kid" and not v.has_meta("in_class"):
			kid = v
			break
	var field := Vector3(-8.0, 0.0, 14.0)      # bờ ruộng trước nhà
	var banyan: Vector3 = (scene.get_node("World/Banyan") as BanyanTree).tree_position + Vector3(1.5, 0, 1.5)
	rig.global_position = field
	fp.enter()
	await _frames(5)
	print("Chỗ thoáng bờ ruộng: '%s'" % k.refusal(kid, field))
	print("Dưới gốc đa: '%s'" % k.refusal(kid, banyan))
	print("Giữa làng (sân đình): '%s'" % k.refusal(kid, (scene.get_node("World/Village") as Village).dinh_door))
	w.set_weather("fog", true)
	print("Sương mù: '%s'" % k.refusal(kid, field))
	w.set_weather("clear", true)
	fp.global_position = field + Vector3(0, 0.1, 0)
	kid.global_position = field + Vector3(0, 0, 2.0)
	kid.visible = true
	await _frames(5)
	dlg.start(kid, fp)
	fp._suspend("talk")
	var idx := _game_option(dlg, "kite")
	print("Câu mượn diều trong hội thoại: %s" % ("có" if idx >= 0 else "KHÔNG"))
	dlg._choose(idx)
	dlg._choose(0)          # (Thả diều)
	await _frames(240)
	print("Đang thả: %s, camera diều %s, nhập vai tạm dừng '%s', diều cao %.1f m, dây %.0f m, đứa trẻ đứng xem %s" % [
			KiteFlying.Phase.keys()[k.phase], k._cam.current, fp._suspended, k.line * sin(k.el) + 1.25, k.line, kid.has_meta("talking")])
	var ev := InputEventAction.new()
	ev.action = "exit_interior"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(5)
	print("Esc: %s, bảng kết quả %s" % [KiteFlying.Phase.keys()[k.phase], k._result.visible])
	Input.parse_input_event(ev)
	await _frames(5)
	print("Esc lần nữa: %s, nhập vai tiếp %s, camera nhập vai %s, đứa trẻ thôi đứng xem %s" % [
			KiteFlying.Phase.keys()[k.phase], fp._suspended == "" and fp.active, fp.camera.current, not kid.has_meta("talking")])
	quit()


## Tìm câu rủ chơi `key`: ở danh sách đầu, hoặc trong "Chơi gì không em?" (chọn câu đó trước). Trả về chỉ số
## trong `dlg._options` hiện tại (−1 nếu không có).
func _game_option(dlg: Dialogue, key: String) -> int:
	var opts := dlg._build_options()
	dlg._options = opts
	for i in opts.size():
		if str(opts[i].get("key", "")) == key:
			return i
	for i in opts.size():
		if str(opts[i].get("key", "")) == "games":
			dlg._choose(i)
			for j in dlg._options.size():
				if str(dlg._options[j].get("key", "")) == key:
					return j
	return -1
