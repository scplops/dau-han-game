extends SceneTree
## Thử năm trò dân gian nhỏ (mục 44), headless — chạy với `timeout`:
## 1) Chủ nhật 15:00: số trẻ muốn ra chơi; mỗi trò đưa đủ người ra bãi, mô phỏng 90 s, in số liệu, tan sạch meta.
## 2) Người chơi rủ từng trò ở sân nhà mình, bot chơi: đá cầu (bấm đúng lúc / không bấm), bắn bi (ngắm thẳng),
##    chơi chuyền (bấm đủ số lần), bịt mắt bắt dê (đi về phía dê gần nhất), rồng rắn (chạy vòng bắt đuôi) → Esc dọn sạch.
## Dùng: timeout 120 godot --headless --path . -s tools/folk_test.gd
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
	var fg := scene.get_node("FolkGames") as FolkGames
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	var sg := scene.get_node("SaveGame") as SaveGame
	dn.auto_run = false
	cal.set_date_string("2027-06-20")
	dn.time_of_day = 15.0
	vs.replan()
	await _frames(20)
	var want := 0
	var kids: Array[Villager] = []
	for v in vs.people:
		if v.role == "kid":
			kids.append(v)
			if vs._choices(v, 15.0).has("folk"):
				want += 1
	print("1) Chủ nhật 15:00: %d / %d trẻ con có thể ra chơi" % [want, kids.size()])
	var ki := 0
	for kind: String in FolkGames.ORDER:
		fg.stats = {}
		var n: int = FolkGames.KINDS[kind].max
		for i in n:
			var v := kids[ki]
			ki += 1
			v.visible = true
			v.remove_meta("talking")
			v.set_meta("folk_kind", kind)
			v.global_position = (fg.sites[kind] as Vector3) + Vector3(1.0 + i * 0.5, 0, 1.0)
			fg.on_arrive(v)
		var g: Dictionary = fg.groups[fg.groups.size() - 1]
		var t := 0.0
		while t < 90.0:
			fg.step(g, 0.05)
			t += 0.05
		print("   %s (%d đứa): %s" % [FolkGames.KINDS[kind].name, (g.members as Array).size(), fg.stats])
		fg._end_group(g)
	var left := 0
	for v in kids:
		if v.has_meta("folk"):
			left += 1
	print("   tan: còn meta %d, còn nhóm %d" % [left, fg.groups.size()])
	# 2) Người chơi
	rig.global_position = Vector3(-10, 0, 3)
	fp.enter()
	await _frames(10)
	fp.global_position = Vector3(-6, 0.3, 9)
	fp.rotation.y = 0.0
	await _frames(10)
	var kid := kids[ki]
	kid.visible = true
	kid.state = Villager.State.IDLE
	kid.global_position = fp.global_position + Vector3(0, 0, -1.6)
	print("2) Rủ %s: từ chối \"%s\"" % [kid.display_name, fg.refusal(kid)])
	var dt := 1.0 / 60.0
	for kind: String in FolkGames.ORDER:
		for mode in 2:
			fg.stats = {}
			fg.start_with(kid, kind)
			var g := fg.pg
			var t := 0.0
			var limit := 60.0 if kind != "ban_bi" else 150.0
			while t < limit and not bool((g.st as Dictionary).get("over", false)):
				fg.step(g, dt)
				t += dt
				var st: Dictionary = g.st
				if mode == 1:
					continue                      # không làm gì
				match kind:
					"da_cau":
						if int(st.to) % (g.members as Array).size() == 0 and float(st.wait) <= 0.0 and float(st.ft) >= float(st.dur) - dt * 1.5 and float(st.press) < 0.0:
							fg.press()
					"ban_bi":
						if str(st.phase) == "aim" and int(st.turn) == 0:
							var line := fg._bi_dir(g) * fg.bi_line
							var tp := Vector2.ZERO
							for m: Dictionary in st.marbles:
								if bool(m.alive):
									tp = m.p
									break
							st.aim = (-fg._bi_dir(g)).angle_to(tp - line)
							fg.press()
							st.power = 0.55
							fg.release()
					"chuyen":
						if int(st.turn) == 0:
							if float(st.ft) < 0.0:
								fg.press()
							elif int(st.taps) < fg._chuyen_need(st) and float(st.ft) > 0.15 * (int(st.taps) + 1):
								fg.press()
					"bit_mat", "rong_ran":
						var pos: Array = st.pos
						var me: Vector3 = pos[0]
						var target := Vector3.INF
						if kind == "bit_mat":
							for i in range(1, pos.size()):
								if target == Vector3.INF or (pos[i] as Vector3).distance_to(me) < target.distance_to(me):
									target = pos[i]
						else:
							var line2 := fg._dragon_line(g)
							target = pos[line2[line2.size() - 1]]
							var head: Vector3 = pos[line2[0]]
							if me.distance_to(head) < 1.8:
								target = me + (target - me).normalized() + (me - head).normalized() * 1.3
						var wdir := (target - me).normalized()
						var fwd := -fg._cam_dir
						var right := fwd.cross(Vector3.UP)
						fg._player_move(g, Vector2(wdir.dot(right), -wdir.dot(fwd)), dt)
			var st2: Dictionary = g.st
			var info := ""
			match kind:
				"da_cau": info = "chạm liên tiếp cao nhất %d, rơi %d lần" % [int(st2.score), int(fg.stats.get("cau_drops", 0))]
				"ban_bi": info = "điểm %s, bắn %d phát, trúng %d lần, xong ván %s" % [st2.pts, int(fg.stats.get("bi_shots", 0)), int(fg.stats.get("bi_hits", 0)), st2.over]
				"chuyen": info = "tới bàn %d, hỏng %d lần, xong %s" % [int(st2.score), int(fg.stats.get("chuyen_fail", 0)), st2.over]
				"bit_mat": info = "bắt được %d sau %.0f s (điểm %d)" % [int(st2.caught), float(st2.time), int(st2.score)]
				"rong_ran": info = "bắt đuôi %d sau %.0f s (điểm %d)" % [int(st2.caught), float(st2.time), int(st2.score)]
			print("   %s — %s: %s  [%d người, %.0f s]" % [FolkGames.KINDS[kind].name, "bot chơi" if mode == 0 else "đứng yên", info, (g.members as Array).size(), t])
			fg.stop_player()
			await _frames(2)
	print("   kỷ lục: cầu %d · bi %d · chuyền %d · dê %d · rồng rắn %d · %d lần chơi; dọn sạch: %s nhóm, nhập vai tiếp %s" % [int(sg.records.cau_best), int(sg.records.bi_best),
			int(sg.records.chuyen_best), int(sg.records.goat_best), int(sg.records.dragon_best), int(sg.records.folk_games), fg.groups.size(), fp._suspended.is_empty()])
	quit()
