extends SceneTree
## Thử trò chơi dân gian khi KHÔNG có người chơi và khi người chơi vào (mục 36):
## 1) Chủ nhật 15:00, trời nắng: để làng tự chạy (tua nhanh) — đếm ván ô ăn quan dân làng tự chơi (nước đi,
##    điểm), trốn tìm của bọn trẻ (vòng, bắt được, đập cột), diều đang bay, đua thuyền của dân làng (về đích),
##    nhảy dây, đánh khăng.
## 2) Người chơi vào từng trò đang diễn ra → trò chơi bắt đầu lại từ đầu (điểm 0, đếm lại, vạch xuất phát…).
## Dùng: godot --headless --path . -s tools/folk_ambient_test.gd
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
	while cal.weekday() != 0:
		cal.add_days(1)
	var dn := scene.get_node("DayNight") as DayNight
	dn.time_of_day = 14.5
	dn.auto_run = false
	var vs := scene.get_node("World/Villagers") as Villagers
	vs.replan()
	var oaq := scene.get_node("OAnQuan") as OAnQuan
	var hs := scene.get_node("HideSeek") as HideSeek
	var kite := scene.get_node("KiteFlying") as KiteFlying
	var race := scene.get_node("BoatRace") as BoatRace
	var jr := scene.get_node("JumpRope") as JumpRope
	var tc := scene.get_node("TipCat") as TipCat
	race._amb_wait = 5.0
	print("Chỗ chơi: ô ăn quan %s · trốn tìm (cột) %s · thả diều %s" % [oaq.sites, hs.ambient_bases if not hs.ambient_bases.is_empty() else "chưa tính", kite.sites])
	# --- 1) Làng tự chạy
	Engine.time_scale = 4.0
	var stats := {"oaq_moves": 0, "oaq_games": 0, "hs_rounds": 0, "hs_found": 0, "hs_escaped": 0, "kites": 0, "race_done": 0}
	var last_scores := {}
	var hs_phase := {}
	var seen_race := false
	for sec in 160:
		await _frames(60)
		for g in oaq.ambient:
			var sc: Dictionary = g.st
			if sc.is_empty():
				continue
			var key := str(g.site)
			var tot := int(sc.score[0]) + int(sc.score[1])
			var cnt_sum := 0
			for c in sc.cnt:
				cnt_sum += int(c)
			var sig := "%d|%d|%s" % [tot, int(g.games), str(sc.cnt)]
			if last_scores.get(key, "") != sig:
				stats.oaq_moves += 1
				last_scores[key] = sig
			stats.oaq_games = maxi(stats.oaq_games, int(g.games))
		for g in hs.ambient:
			var k := str(g.base)
			if str(g.phase) == "count" and hs_phase.get(k, "") != "count":
				stats.hs_rounds += 1
			if str(g.phase) == "seek" or str(g.phase) == "back":
				stats.hs_found = maxi(stats.hs_found, (g.found as Array).size())
				stats.hs_escaped = maxi(stats.hs_escaped, (g.escaped as Array).size())
			hs_phase[k] = str(g.phase)
		stats.kites = maxi(stats.kites, kite.ambient.size())
		if race.ambient and race.phase == BoatRace.Phase.RACE:
			seen_race = true
		if race.ambient and race.phase == BoatRace.Phase.RESULT:
			stats.race_done = maxi(stats.race_done, race.order.size())
		if sec % 40 == 39:
			print("  %3d s: ô ăn quan %d bàn (%s) · trốn tìm %d nhóm (%s) · diều %d · đua %s · nhảy dây %d · đánh khăng %d" % [
					sec + 1, oaq.ambient.size(), ", ".join(oaq.ambient.map(func(g: Dictionary) -> String: return "%d người, ván %d" % [(g.players as Array).size(), int(g.games)])),
					hs.ambient.size(), ", ".join(hs.ambient.map(func(g: Dictionary) -> String: return "%d đứa, %s" % [(g.members as Array).size(), g.phase])),
					kite.ambient.size(), ("đang đua (%s)" % BoatRace.Phase.keys()[race.phase]) if race.ambient else "nghỉ",
					jr.games.size(), tc.games.size()])
	Engine.time_scale = 1.0
	print("1) Không có người chơi (160 s): ô ăn quan %d lần bàn đổi, %d ván · trốn tìm %d vòng, bắt nhiều nhất %d, đập cột %d · diều bay cùng lúc %d · đua thuyền: có đua %s, về đích %d thuyền" % [
			stats.oaq_moves, stats.oaq_games, stats.hs_rounds, stats.hs_found, stats.hs_escaped, stats.kites, seen_race, stats.race_done])
	# --- 2) Người chơi vào
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	rig.global_position = Vector3(0, 0, -60)
	fp.enter()
	await _frames(5)
	# Ô ăn quan: chờ có bàn đủ hai người đang chơi
	Engine.time_scale = 4.0
	var og: Dictionary = {}
	for i in 60 * 120:
		for g0 in oaq.ambient:
			if (g0.players as Array).size() >= 2 and not (g0.st as Dictionary).is_empty():
				og = g0
		if not og.is_empty():
			break
		await physics_frame
	Engine.time_scale = 1.0
	if not og.is_empty():
		var g: Dictionary = og
		if (g.players as Array).size() >= 2:
			var v: Villager = g.players[0]
			var other: Villager = g.players[1]
			fp.global_position = v.global_position + Vector3(1.5, 0.1, 0)
			await _frames(3)
			oaq.join_ambient(v)
			await _frames(3)
			var fresh: bool = int(oaq.st.score[0]) == 0 and int(oaq.st.score[1]) == 0 and (oaq.st.cnt as Array)[1] == oaq.stones_per_square
			print("2) Ô ăn quan: vào chơi %s với %s · bàn mới (0–0, mỗi ô %d) %s · bàn dân làng đó tan %s · người kia thôi chơi %s" % [
					oaq.active, oaq.npc.display_name if oaq.npc else "?", oaq.stones_per_square, fresh, not oaq.ambient.has(g), not other.has_meta("oaq_ambient")])
			oaq.stop()
			await _frames(3)
	else:
		print("2) Ô ăn quan: KHÔNG có bàn nào đang chơi")
	# Trốn tìm
	var hg: Dictionary = {}
	Engine.time_scale = 4.0
	for i in 60 * 120:
		for g in hs.ambient:
			if (g.members as Array).size() >= 3 and str(g.phase) == "seek":
				hg = g
		if not hg.is_empty():
			break
		await physics_frame
	Engine.time_scale = 1.0
	if not hg.is_empty():
		var k: Villager = hg.members[0]
		var n_before := (hg.members as Array).size()
		fp.global_position = k.global_position + Vector3(1.0, 0.1, 0)
		await _frames(3)
		hs.join_ambient(k)
		await _frames(3)
		var former := 0
		for m: Villager in hg.members:
			if hs.hiders.has(m):
				former += 1
		print("   Trốn tìm: chơi lại từ đầu %s (đang %s, người chơi đi tìm), nhóm cũ tan %s, %d/%d đứa của nhóm cũ đi trốn" % [
				hs.phase == HideSeek.Phase.COUNT, HideSeek.Phase.keys()[hs.phase], not hs.ambient.has(hg), former, n_before])
		hs.stop()
		await _frames(3)
	else:
		print("   Trốn tìm: KHÔNG có nhóm nào đang chơi")
	# Thả diều
	if not kite.ambient.is_empty():
		var f: Dictionary = kite.ambient[0]
		var kk: Villager = f.kid
		fp.global_position = kk.global_position + Vector3(1.2, 0.1, 0)
		await _frames(3)
		var no := kite.refusal(kk, fp.global_position)
		kite.start(kk)
		await _frames(3)
		print("   Thả diều: mượn diều của %s (%s) → thả lại từ đầu %s (dây %.0f m), diều của đứa trẻ thu về %s" % [
				kk.display_name, "chịu" if no == "" else no, kite.phase == KiteFlying.Phase.FLY, kite.line, not kite.ambient.has(f)])
		kite.stop()
		await _frames(3)
	else:
		print("   Thả diều: KHÔNG có đứa nào đang thả")
	# Đua thuyền: chờ dân làng đua, đi được nửa đường thì người chơi vào
	race._amb_wait = 0.1
	for i in 600:
		if race.ambient and race.phase == BoatRace.Phase.RACE and absf(float(race.boats[1].s) - race.start_s) > 60.0:
			break
		await physics_frame
	var mid := absf(float(race.boats[1].s) - race.start_s)
	race.start()
	await _frames(3)
	var at_start := race.boats.all(func(b: Dictionary) -> bool: return absf(float(b.s) - race.start_s) < 4.0 and not b.done)
	print("   Đua thuyền: dân làng đang đua (thuyền 2 đã đi %.0f m) → người chơi vào: bảng chọn %s, hết đua của dân làng %s, các thuyền về vạch xuất phát %s" % [
			mid, race.phase == BoatRace.Phase.SETUP, not race.ambient, at_start])
	race.begin("team", 4, false)
	await _frames(3)
	print("      bắt đầu đua: %s" % BoatRace.Phase.keys()[race.phase])
	race.stop()
	await _frames(3)
	# Nhảy dây: chờ có cuộc chơi đang đếm
	var rg: Dictionary = {}
	for i in 1200:
		for g in jr.games:
			if int(g.count) > 0 and (g.turners as Array).size() >= 2:
				rg = g
		if not rg.is_empty():
			break
		await physics_frame
	if not rg.is_empty():
		var c0 := int(rg.count)
		var m: Villager = rg.turners[0]
		jr.join_at(m)
		await _frames(2)
		print("   Nhảy dây: đang đếm %d → người chơi vào: đếm lại %d, người chơi nhảy đầu tiên %s" % [c0, int(rg.count), (rg.queue as Array).size() > 0 and rg.queue[0] is String])
		jr.stop_player()
	else:
		print("   Nhảy dây: không có cuộc chơi đang đếm")
	# Đánh khăng
	var kg: Dictionary = {}
	for i in 1200:
		for g in tc.games:
			if int(g.turns) > 1:
				kg = g
		if not kg.is_empty():
			break
		await physics_frame
	if not kg.is_empty():
		var t0 := int(kg.turns)
		var sc0: Dictionary = (kg.score as Dictionary).duplicate()
		var m2: Villager = null
		for x in kg.members:
			if x is Villager:
				m2 = x
		tc.join_at(m2)
		await _frames(2)
		var zero := (kg.score as Dictionary).values().all(func(x: Variant) -> bool: return int(x) == 0)
		print("   Đánh khăng: đang lượt %d, điểm %s → người chơi vào: điểm về 0 %s, vòng %d, người chơi đánh trước %s" % [
				t0, sc0, zero, int(kg.round), kg.striker is String])
		tc.stop_player()
	else:
		print("   Đánh khăng: không có cuộc chơi")
	quit()
