extends SceneTree
## Thử Nhảy dây (headless):
## 1) Trẻ con tự chơi: 4 đứa tới bãi sân đình → 2 quay, 2 xếp hàng; chạy 60 s: số lượt, người vướng ra
##    thay người quay, kỷ lục; hết giờ chơi thì tản (meta gỡ hết).
## 2) Người chơi: bờ ruộng trước nhà, rủ một đứa qua hội thoại → vào nhảy (camera nhảy dây, hình nhân).
##    Nhảy đúng nhịp / lệch ±0,08 s / nhảy sớm / không nhảy: đếm được bao nhiêu lần, dây nhanh tới đâu.
## 3) Vướng → lượt bọn trẻ → lại tới bạn; Esc → nhập vai tiếp, trẻ tạm xoá, cuộc chơi tan.
## 4) Lời từ chối: dưới gốc đa (chật), trời mưa phùn, người lớn.
## Dùng: godot --headless --path . -s tools/jump_rope_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## Bot người chơi nhảy theo pha dây, mỗi vòng dây nhảy đúng một lần: `lead` = nhảy trước lúc dây chạm đất bao
## nhiêu giây; `noise` lệch ngẫu nhiên (như tay người).
func _play(jr: JumpRope, lead: float, noise: float, max_s: float) -> Dictionary:
	var g := jr.player_game
	var dt := 1.0 / 60.0
	var t := 0.0
	var planned := lead + randf_range(-noise, noise)
	var pressed_cycle := -1
	while t < max_s:
		var cyc := int(floorf(float(g.phi) / TAU))
		if g.jumper is String and float(g.wait) <= 0.0 and float(g.air) < 0.0 and lead >= 0.0 and cyc != pressed_cycle:
			var t_bottom := (TAU - fmod(float(g.phi), TAU)) / (TAU * float(g.rev))
			if t_bottom <= planned:
				jr.player_jump()
				pressed_cycle = cyc
				planned = lead + randf_range(-noise, noise)
		var was_player: bool = g.jumper is String
		var c := int(g.count)
		jr.step(g, dt)
		t += dt
		if was_player and g.jumper == null:
			return {"count": c, "t": t, "rev": float(g.rev), "tripped": true}
	return {"count": int(g.count), "t": t, "rev": float(g.rev), "tripped": false}


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
	var jr := scene.get_node("JumpRope") as JumpRope
	jr.set_process(false)
	seed(11)
	print("Bãi chơi: %s · trẻ con chọn việc 'jumprope' lúc 15:00 CN: %s" % [jr.sites, jr.ambient_ok(15.0)])
	# --- 1) Trẻ con tự chơi
	var kids: Array[Villager] = []
	for v in vs.people:
		if v.role == "kid" and kids.size() < 4:
			kids.append(v)
	for v in kids:
		v.global_position = jr.sites[0] + Vector3(randf_range(-1, 1), 0, 2.5)
		v.activity = "jumprope"
		jr.on_arrive(v)
	var g: Dictionary = jr.games[0]
	g.t_left = 60.0
	var turner_changes := 0
	var turns := [0]
	var last_turners: Array = (g.turners as Array).duplicate()
	jr.turn_over.connect(func(_w: String, _c: int) -> void: turns[0] += 1)
	for i in 60 * 59:
		jr.step(g, 1.0 / 60.0)
		if g.turners != last_turners:
			turner_changes += 1
			last_turners = (g.turners as Array).duplicate()
	print("1) 4 đứa ở bãi sân đình, 59 s: %d lượt nhảy xong, đổi người quay %d lần, kỷ lục %s" % [turns[0], turner_changes, g.best])
	for i in 120:
		if not jr.games.has(g):
			break
		jr.step(g, 1.0 / 60.0)
	var stuck := 0
	for v in kids:
		stuck += int(v.has_meta("jumprope") or v.has_meta("talking"))
	print("   hết giờ chơi: cuộc chơi tan %s, còn dính meta %d, dwell về 0 %s" % [not jr.games.has(g), stuck, kids.all(func(v: Villager) -> bool: return v.dwell <= 0.0)])
	# --- 2) Người chơi
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var dlg := scene.get_node("Dialogue") as Dialogue
	var rig := scene.get_node("CameraRig") as CameraRig
	var field := Vector3(-8.0, 0.0, 14.0)
	rig.global_position = field
	fp.enter()
	fp.global_position = field + Vector3(0, 0.1, 0)
	fp.rotation.y = 0.0
	await _frames(8)
	var kid := kids[0]
	kid.global_position = field + Vector3(1.5, 0, 0)
	kid.visible = true
	await _frames(3)
	print("2) Bờ ruộng thoáng: '%s' · dưới gốc đa: '%s'" % [jr.refusal(kid, fp.global_position),
			jr.refusal(kid, (scene.get_node("World/Banyan") as BanyanTree).tree_position + Vector3(1.5, 0, 1.5))])
	dlg.start(kid, fp)
	fp._suspend("talk")
	var idx := _game_option(dlg, "jumprope")
	print("   câu rủ nhảy dây: %s" % ("có" if idx >= 0 else "KHÔNG"))
	dlg._choose(idx)
	dlg._choose(0)
	await _frames(3)
	var pg := jr.player_game
	print("   vào nhảy: %s, người quay %d (%s), hàng chờ %d, camera nhảy dây %s, nhập vai tạm dừng '%s', trẻ tạm %d" % [
			not pg.is_empty(), (pg.turners as Array).size(), ", ".join((pg.turners as Array).map(func(v: Villager) -> String: return v.display_name)),
			(pg.queue as Array).size(), jr._cam.current, fp._suspended, jr._temps.size()])
	# Đợi tới lượt người chơi
	for i in 600:
		if pg.jumper is String and float(pg.wait) <= 0.0:
			break
		jr.step(pg, 1.0 / 60.0)
	var res := [["đúng nhịp", 0.16, 0.0], ["lệch ±0,06 s", 0.16, 0.06], ["lệch ±0,1 s", 0.16, 0.1], ["lệch ±0,14 s", 0.16, 0.14], ["lệch ±0,08 s", 0.16, 0.08], ["nhảy sớm 0,3 s", 0.3, 0.0], ["không nhảy", -1.0, 0.0]]
	for r in res:
		var counts: Array[String] = []
		var trips := 0
		var top_rev := 0.0
		for trial in 5:
			# Chờ lại tới lượt mình (bọn trẻ nhảy xen giữa)
			for i in 60 * 120:
				if pg.jumper is String and float(pg.wait) <= 0.0:
					break
				jr.step(pg, 1.0 / 60.0)
			var out := _play(jr, float(r[1]), float(r[2]), 45.0)
			if not out.tripped:
				jr._trip(pg)          # hết giờ thử: cho xuống lượt
			counts.append(str(out.count))
			trips += int(out.tripped)
			top_rev = maxf(top_rev, float(out.rev))
		print("   %-12s → số lần nhảy %s · vướng %d/5 · dây nhanh nhất %.2f vòng/s" % [r[0], "/".join(counts), trips, top_rev])
	print("   kỷ lục: %s" % pg.best)
	# --- 3) Esc
	var ev := InputEventAction.new()
	ev.action = "exit_interior"
	ev.pressed = true
	jr._unhandled_input(ev)
	await _frames(3)
	print("3) Esc: còn chơi %s, cuộc chơi còn %d, trẻ tạm còn %d, nhập vai tiếp %s, camera nhập vai %s" % [
			not jr.player_game.is_empty(), jr.games.size(), jr._temps.size(), fp._suspended == "" and fp.active, fp.camera.current])
	# --- 4) Từ chối
	w.set_weather("drizzle", true)
	var adult: Villager = null
	for v in vs.people:
		if v.role == "farmer":
			adult = v
			break
	print("4) mưa phùn: '%s' · người lớn: '%s' · việc 'jumprope' khi mưa: %s" % [jr.refusal(kid), jr.refusal(adult), jr.ambient_ok(15.0)])
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
