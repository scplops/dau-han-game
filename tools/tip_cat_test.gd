extends SceneTree
## Thử Đánh khăng (headless):
## 1) Trẻ con tự chơi: 4 đứa ở bãi sân đình 90 s — số lượt, chết vì bị bắt / khăng sát lỗ, điểm trung bình; tan sạch.
## 2) Người chơi rủ qua hội thoại ở sân gạch nhà mình, bot chơi lượt của người chơi theo 2 lối:
##    "chuẩn" (lực 0,8, vụt đỡ khi khăng còn ~1 m, vụt lệch đỉnh nảy ±0,03 s) và "vụng" (lệch ±0,25 s, đỡ sớm);
##    đếm điểm / lượt, số lần chết; hết `rounds` vòng có người thắng.
## 3) Esc dọn sạch; 4) từ chối: người lớn, mưa, chỗ hẹp.
## Dùng: godot --headless --path . -s tools/tip_cat_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## Chạy một lượt của người chơi bằng bot; trả về [điểm, chết, lý do].
func _player_turn(tc: TipCat, g: Dictionary, err: float, bat_dist: float, power: float) -> Array:
	var dt := 1.0 / 60.0
	var strike_at := -1.0
	for i in 60 * 60:
		var ph := String(g.phase)
		if not (g.striker is String):
			break
		match ph:
			"flick_ready":
				g.aim = randf_range(-0.25, 0.25)
				tc._flick(g, power)
			"throw_flight":
				var p := g.pos as Vector3
				var h := g.hole as Vector3
				if not bool(g.bat_tried) and Vector2(p.x - h.x, p.z - h.z).length() < bat_dist and float((g.vel as Vector3).y) < 0.0:
					tc.player_press()
			"strike_ready":
				tc.player_press()
				strike_at = tc.hop_speed / TipCat.G + randf_range(-err, err)
			"hop":
				if float(g.hop_t) >= 0.0 and strike_at >= 0.0 and float(g.hop_t) >= strike_at:
					tc.player_press()
					strike_at = -1.0
			"result":
				return [int(g.pts), String(g.msg).contains("chết"), String(g.msg)]
		tc.step(g, dt)
	print("      KẸT: phase=%s pos=%s hop_t=%.2f strikes=%d msg=%s thrower=%s" % [g.phase, g.pos, float(g.hop_t), int(g.strikes_left), g.msg, g.thrower])
	return [int(g.pts), true, "hết giờ thử"]

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var cal := scene.get_node("Calendar") as LunarCalendar
	while cal.weekday() != 0:
		cal.add_days(1)
	var dn := scene.get_node("DayNight") as DayNight
	dn.time_of_day = 15.0
	var vs := scene.get_node("World/Villagers") as Villagers
	vs.replan()
	var tc := scene.get_node("TipCat") as TipCat
	tc.set_process(false)
	seed(5)
	print("Bãi đánh khăng: %s · hướng %s · việc 'khang' lúc 15:00 CN: %s" % [tc.sites, tc.site_dirs, tc.ambient_ok(15.0)])
	# --- 1) Trẻ con tự chơi
	var kids: Array[Villager] = []
	for v in vs.people:
		if v.role == "kid" and kids.size() < 4:
			kids.append(v)
	for v in kids:
		v.global_position = tc.sites[0] + Vector3(randf_range(-2, 2), 0, -1.5)
		v.activity = "khang"
		tc.on_arrive(v)
	var g: Dictionary = tc.games[0]
	g.t_left = 90.0
	var res := {"turns": 0, "out": 0, "pts": 0}
	var on_turn := func(_w: String, p: int, out: bool) -> void:
		res.turns += 1
		res.out += int(out)
		res.pts += p
	tc.turn_done.connect(on_turn)
	for i in 60 * 89:
		tc.step(g, 1.0 / 60.0)
	print("1) 4 đứa ở bãi sân đình, 89 s: %d lượt, chết %d, điểm TB %.1f khăng / lượt không chết · bảng %s" % [
			res.turns, res.out, float(res.pts) / maxf(res.turns - res.out, 1), g.score])
	for i in 120:
		if not tc.games.has(g):
			break
		tc.step(g, 1.0 / 60.0)
	var stuck := 0
	for v in kids:
		stuck += int(v.has_meta("khang") or v.has_meta("talking") or v.elbows[1].get_node_or_null("KhangCai") != null)
	print("   hết giờ chơi: tan %s, còn dính meta / khăng cái %d" % [not tc.games.has(g), stuck])
	tc.turn_done.disconnect(on_turn)
	# --- 2) Người chơi
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var dlg := scene.get_node("Dialogue") as Dialogue
	var rig := scene.get_node("CameraRig") as CameraRig
	var yard := Vector3(-14.0, 0.0, -1.0)
	rig.global_position = yard
	fp.enter()
	fp.global_position = yard + Vector3(0, 0.1, 0)
	fp.rotation.y = deg_to_rad(-90.0)      # nhìn về phía đông, ra đường đất / ruộng
	await _frames(8)
	var kid := kids[0]
	kid.global_position = yard + Vector3(0, 0, 1.5)
	kid.visible = true
	await _frames(3)
	print("2) chỗ đứng: '%s' · hướng nhìn %s" % [tc.refusal(kid, fp.global_position, tc._look_dir()), tc._look_dir()])
	dlg.start(kid, fp)
	fp._suspend("talk")
	var idx := _game_option(dlg, "khang")
	print("   câu rủ đánh khăng: %s" % ("có" if idx >= 0 else "KHÔNG"))
	dlg._choose(idx)
	dlg._choose(0)
	await _frames(3)
	var pg := tc.player_game
	print("   vào chơi: %s, người chơi %d (%s), camera khăng %s, nhập vai tạm dừng '%s', trẻ tạm %d" % [
			not pg.is_empty(), (pg.members as Array).size(), ", ".join((pg.order as Array).map(func(x: Variant) -> String: return tc._name(x))),
			tc._cam.current, fp._suspended, tc._temps.size()])
	for style in [["chuẩn", 0.03, 1.0, 0.8], ["vụng", 0.25, 2.1, 0.5]]:
		var pts: Array[String] = []
		var outs := 0
		var why := {}
		for k in 6:
			for i in 60 * 120:
				if pg.striker is String and String(pg.phase) == "flick_ready":
					break
				if pg.done:          # đủ vòng giữa lượt bọn trẻ: đặt lại ván
					pg.done = false
					pg.round = 1
					pg.t = 0.1
				tc.step(pg, 1.0 / 60.0)
			var r := _player_turn(tc, pg, float(style[1]), float(style[2]), float(style[3]))
			pts.append(str(r[0]))
			outs += int(r[1])
			if r[1]:
				var key := "bị bắt" if String(r[2]).contains("bắt") else ("sát lỗ" if String(r[2]).contains("lỗ") else String(r[2]))
				why[key] = int(why.get(key, 0)) + 1
			if pg.done:          # đủ vòng: đặt lại ván để thử tiếp
				pg.done = false
				pg.round = 1
				pg.t = 0.1
		print("   %-6s → điểm mỗi lượt %s · chết %d/6 %s" % [style[0], "/".join(pts), outs, why])
	# Ván trọn 3 vòng
	for nm in (pg.score as Dictionary).keys():
		pg.score[nm] = 0
	pg.round = 1
	pg.turn_i = -1
	pg.turns = 0
	pg.done = false
	tc._next_turn(pg)
	for i in 60 * 600:
		if pg.done:
			break
		if pg.striker is String and String(pg.phase) == "flick_ready":
			_player_turn(tc, pg, 0.05, 1.0, 0.8)
		else:
			tc.step(pg, 1.0 / 60.0)
	print("   chơi trọn %d vòng: xong %s · %s · điểm %s" % [tc.rounds, pg.done, pg.msg, pg.score])
	# --- 3) Esc
	var ev := InputEventAction.new()
	ev.action = "exit_interior"
	ev.pressed = true
	tc._unhandled_input(ev)
	await _frames(3)
	print("3) Esc: còn chơi %s, cuộc chơi còn %d, trẻ tạm còn %d, nhập vai tiếp %s, camera nhập vai %s" % [
			not tc.player_game.is_empty(), tc.games.size(), tc._temps.size(), fp._suspended == "" and fp.active, fp.camera.current])
	# --- 4) Từ chối
	var adult: Villager = null
	for v in vs.people:
		if v.role == "farmer":
			adult = v
			break
	var tight := (scene.get_node("World/Banyan") as BanyanTree).tree_position + Vector3(2.0, 0, 0)
	print("4) người lớn: '%s' · sát gốc đa nhìn vào thân cây: '%s'" % [tc.refusal(adult), tc.refusal(kid, tight, Vector3(-1, 0, 0))])
	w.set_weather("drizzle", true)
	print("   mưa phùn: '%s' · việc 'khang' khi mưa: %s" % [tc.refusal(kid), tc.ambient_ok(15.0)])
	quit()


## Tìm câu rủ chơi `key`: ở danh sách đầu, hoặc trong "Chơi gì không em?".
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
