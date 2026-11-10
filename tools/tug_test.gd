extends SceneTree
## Thử kéo co (mục 43), headless:
## 1) Chủ nhật 16:00 để làng tự ra bãi (tua ×4): đủ người thì kéo, đủ hiệp thì tan sạch meta.
## 2) Người chơi rủ qua hội thoại ở sân nhà mình → bot bấm theo nhịp với tỉ lệ trúng khác nhau → thắng / thua.
## 3) Xin vào cuộc đang kéo ở bãi (chơi lại từ đầu 0–0), Esc dọn sạch; từ chối cụ già / trời mưa.
## Dùng: godot --headless --path . -s tools/tug_test.gd
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
	var cal := scene.get_node("Calendar") as LunarCalendar
	var dn := scene.get_node("DayNight") as DayNight
	var vs := scene.get_node("World/Villagers") as Villagers
	var tg := scene.get_node("TugOfWar") as TugOfWar
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var dlg := scene.get_node("Dialogue") as Dialogue
	var rig := scene.get_node("CameraRig") as CameraRig
	var sg := scene.get_node("SaveGame") as SaveGame
	dn.auto_run = false
	cal.set_date_string("2027-06-20")
	dn.time_of_day = 16.0
	vs.replan()
	await _frames(30)
	var want := 0
	for v in vs.people:
		if vs._choices(v, 16.0).has("tug"):
			want += 1
	print("1) Chủ nhật 16:00: %d người có thể ra kéo co" % want)
	# Đưa 8 người ra bãi cho nhanh
	var n := 0
	for v in vs.people:
		if n < 8 and v.visible and (v.role == "kid" or (v.role == "farmer" and not v.get_meta("female", false))):
			vs._next_activity(v, "tug")
			v.global_position = tg.site + Vector3(3.0, 0, -3.0 + n * 0.8)
			v.path = PackedVector3Array()
			tg.on_arrive(v)
			n += 1
	print("   tới bãi: đội A %d, đội B %d, giai đoạn %s" % [tg._count(0), tg._count(1), tg.g.phase])
	var t := 0.0
	var max_x := 0.0
	while not tg.g.is_empty() and t < 200.0:
		tg.step(0.05)
		tg._pose(0.05)
		if not tg.g.is_empty():
			max_x = maxf(max_x, absf(float(tg.g.x)))
		t += 0.05
	var left := 0
	for v in vs.people:
		if v.has_meta("tug") or (v.has_meta("talking") and v.dwell > 1.0e5):
			left += 1
	print("   tự kéo: %d hiệp, %d cuộc, lệch xa nhất %.1f m, %.0f s; tan: còn meta %d" % [int(tg.stats.rounds), int(tg.stats.matches), max_x, t, left])
	# 2) Người chơi rủ ở sân nhà mình
	rig.global_position = Vector3(-10, 0, 3)
	fp.enter()
	await _frames(10)
	fp.global_position = Vector3(-6, 0.3, 8)
	fp.rotation.y = 0.0
	await _frames(20)
	var kid: Villager = null
	for v in vs.people:
		if v.role == "farmer" and v.visible and not v.get_meta("female", false) and not v.has_meta("talking"):
			kid = v
			break
	kid.global_position = fp.global_position + Vector3(0, 0, -1.6)
	kid.state = Villager.State.IDLE
	print("2) Rủ %s: từ chối \"%s\"" % [kid.display_name, tg.refusal(kid, fp.global_position, Vector3(0, 0, -1))])
	for rate: float in [1.0, 0.8, 0.6, 0.0, -1.0]:
		tg.start_with(kid)
		var res := {"won": false, "a": 0, "b": 0}
		var cb := func(won: bool, a: int, b: int) -> void:
			res.won = won
			res.a = a
			res.b = b
		tg.finished.connect(cb)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var beat_i := -1
		var tt := 0.0
		while str(tg.g.phase) != "done" and tt < 300.0:
			tg.step(1.0 / 60.0)
			tt += 1.0 / 60.0
			if str(tg.g.phase) == "pull":
				var bi := int(tg._beat_t / tg.beat_period + 0.5)
				var off := absf(tg._beat_t - bi * tg.beat_period)
				if rate < 0.0:
					if rng.randf() < 0.08:
						tg.player_pull()          # bấm bừa
				elif bi != beat_i and off < 0.03 and bi > 0:
					beat_i = bi
					if rng.randf() < rate:
						tg.player_pull()
					elif rate > 0.0:
						tg._beat_t += 0.0         # bỏ nhịp này
		tg.finished.disconnect(cb)
		print("   %s: %s %d–%d sau %.0f s (đội %d người đấu %d)" % ["bấm bừa" if rate < 0.0 else "trúng %d%% nhịp" % int(rate * 100), "THẮNG" if res.won else "thua",
				res.a, res.b, tt, tg._count(0), tg._count(1)])
		tg.stop_player()
		await _frames(3)
	print("   kỷ lục: thắng %d / %d cuộc; dọn sạch: g rỗng %s, nhập vai tiếp %s" % [int(sg.records.tug_wins), int(sg.records.tug_games), tg.g.is_empty(), fp._suspended.is_empty()])
	# 3) Xin vào cuộc ở bãi
	n = 0
	var first: Villager = null
	for v in vs.people:
		if n < 6 and v.visible and v.role == "kid" and not v.has_meta("talking"):
			v.global_position = tg.site + Vector3(3.0, 0, n * 0.8)
			tg.on_arrive(v)
			if first == null:
				first = v
			n += 1
	for i in 400:
		tg.step(0.05)
	print("3) Bãi: giai đoạn %s tỉ số %s → xin vào" % [tg.g.phase, tg.g.score])
	tg.join_at(first)
	print("   sau khi vào: đang chơi %s, tỉ số %s, hiệp %d, đội %d (có bạn) đấu %d" % [tg.playing, tg.g.score, int(tg.g.round), tg._count(0), tg._count(1)])
	tg.stop_player()
	print("   Esc: đang chơi %s, bãi còn cuộc %s (dân làng kéo tiếp)" % [tg.playing, not tg.g.is_empty()])
	var elder: Villager = null
	for v in vs.people:
		if v.role == "elder":
			elder = v
			break
	print("   cụ già: \"%s\"" % tg.refusal(elder))
	w.set_weather("storm", true)
	print("   trời giông: \"%s\" · ambient_ok %s" % [tg.refusal(kid), tg.ambient_ok(16.0)])
	quit()
