extends SceneTree
## Thử Ô ăn quan (headless):
## 1) Luật trên vài thế cờ dựng sẵn: rải, bốc rải tiếp, ăn, ăn liên tiếp, gặp ô quan mất lượt, ăn quan.
## 2) 200 ván máy đấu máy (dễ / khó): tổng điểm luôn bảo toàn, ván nào cũng kết thúc, bên khó thắng nhiều hơn.
## 3) Trong game: nhập vai, bắt chuyện một đứa trẻ → rủ chơi → bàn hiện, đi vài nước → Esc → nhập vai tiếp.
## Dùng: godot --headless --path . -s tools/oaq_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _state(cnt: Array, big := [true, true]) -> Dictionary:
	return {"cnt": cnt.duplicate(), "big": big.duplicate(), "score": [0, 0], "stock": [0, 0]}

func _total(s: Dictionary, qv: int) -> int:
	var t := 0
	for v in (s.cnt as Array):
		t += int(v)
	t += qv * (int(bool(s.big[0])) + int(bool(s.big[1])))
	return t + int(s.score[0]) + int(s.score[1])

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var g := scene.get_node("OAnQuan") as OAnQuan
	var qv := g.quan_value
	var ok := 0
	var n := 0
	# --- 1) Luật
	# Ô 1 có 2 viên, rải sang phải: rơi vào 2, 3; ô 4 trống, ô 5 có 3 → ăn 3
	var s := _state([0, 2, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0])
	OAnQuan.play(s, 1, 1, 0, qv)
	n += 1; ok += int(int(s.score[0]) == 3)
	print("rải 2 viên, cách ô trống ăn ô sau: điểm %d (mong đợi 3)" % int(s.score[0]))
	# Ăn liên tiếp: ô 1 có 1 viên → rơi vào 2; ô 3 trống, ô 4 có 2 → ăn; ô 5 trống, ô 6 (quan) có quan → ăn quan
	s = _state([0, 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0])
	OAnQuan.play(s, 1, 1, 0, qv, 0)
	n += 1; ok += int(int(s.score[0]) == 2 + qv and not bool(s.big[1]))
	print("ăn liên tiếp tới quan (bỏ luật quan non): điểm %d (mong đợi %d), quan phải còn: %s" % [int(s.score[0]), 2 + qv, s.big[1]])
	# Quan non: ô quan mới có 2 sỏi dân → chưa được ăn
	s = _state([0, 1, 0, 0, 2, 0, 2, 0, 0, 0, 0, 0])
	OAnQuan.play(s, 1, 1, 0, qv, 5)
	n += 1; ok += int(int(s.score[0]) == 2 and bool(s.big[1]))
	print("quan non (2 sỏi < 5): điểm %d (mong đợi 2), quan phải còn: %s" % [int(s.score[0]), s.big[1]])
	# Rải xong ô kế là ô quan → mất lượt, không ăn gì
	s = _state([0, 0, 0, 0, 1, 0, 0, 5, 0, 0, 0, 0])
	OAnQuan.play(s, 4, 1, 0, qv)
	n += 1; ok += int(int(s.score[0]) == 0 and (s.cnt as Array)[5] == 1)
	print("rải tới sát ô quan: điểm %d (mong đợi 0), ô 5 = %d" % [int(s.score[0]), (s.cnt as Array)[5]])
	# Ô kế có sỏi → bốc lên rải tiếp: ô 2 (1 viên) rơi vào ô 3; ô 4 có 2 viên → bốc rải vào 5, 6
	s = _state([0, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0])
	var ev := OAnQuan.play(s, 2, 1, 0, qv)
	var picks := ev.filter(func(e: Array) -> bool: return e[0] == "pick").size()
	n += 1; ok += int(picks == 2)
	print("bốc rải tiếp: %d lần bốc (mong đợi 2), ô 6 = %d" % [picks, (s.cnt as Array)[6]])
	# Rải qua ô quan theo chiều trái từ ô 1: rơi vào ô 0 (quan) rồi ô 11 của đối thủ
	s = _state([0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	OAnQuan.play(s, 1, -1, 0, qv)
	n += 1; ok += int((s.cnt as Array)[0] == 1 and (s.cnt as Array)[11] == 1)
	print("rải qua ô quan trái: ô 0 = %d, ô 11 = %d (mong đợi 1, 1)" % [(s.cnt as Array)[0], (s.cnt as Array)[11]])
	# Hàng trống → rải lại 5 viên đã ăn
	s = _state([0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0])
	s.stock[0] = 7
	s.score[0] = 7
	var r := OAnQuan.refill(s, 0)
	n += 1; ok += int(bool(r[0]) and int(s.score[0]) == 2 and (s.cnt as Array)[1] == 1)
	print("hàng trống rải lại: được đi %s, điểm còn %d (mong đợi 2)" % [r[0], int(s.score[0])])
	print("LUẬT: %d/%d đúng" % [ok, n])

	# --- 2) Máy đấu máy
	var wins := [0, 0, 0]
	var moves_total := 0
	var bad := 0
	var stuck := 0
	for game in 200:
		var st := {"cnt": [0, 5, 5, 5, 5, 5, 0, 5, 5, 5, 5, 5], "big": [true, true], "score": [0, 0], "stock": [0, 0]}
		var total0 := _total(st, qv)
		var who := game % 2
		var moves := 0
		while not OAnQuan.is_over(st) and moves < 400:
			var rr := OAnQuan.refill(st, who)
			if not bool(rr[0]):
				OAnQuan.collect(st)
				break
			g.hard = who == 1
			var m := g.ai_move(st, who)
			OAnQuan.play(st, m.x, m.y, who, qv, g.quan_non)
			if _total(st, qv) != total0:
				bad += 1
			who = 1 - who
			moves += 1
		if OAnQuan.is_over(st):
			OAnQuan.collect(st)
		if moves >= 400:
			stuck += 1
		moves_total += moves
		var a := int(st.score[0])
		var b := int(st.score[1])
		wins[0 if a > b else (1 if b > a else 2)] += 1
	print("200 ván máy dễ (bên 0) đấu máy khó (bên 1): dễ thắng %d, khó thắng %d, hoà %d · trung bình %.1f nước · lệch tổng điểm %d lần · ván không dứt %d" % [
			wins[0], wins[1], wins[2], moves_total / 200.0, bad, stuck])

	# --- 3) Trong game
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var dlg := scene.get_node("Dialogue") as Dialogue
	var vs := scene.get_node("World/Villagers") as Villagers
	var kid: Villager = null
	for v in vs.people:
		if v.role == "kid" and v.visible and v.state != Villager.State.WALK:
			kid = v
			break
	if kid == null:
		kid = vs.people.filter(func(v: Villager) -> bool: return v.role == "kid")[0]
		vs.call_out(kid)
		await _frames(5)
		kid.state = Villager.State.IDLE
		kid.visible = true
	var rig := scene.get_node("CameraRig") as CameraRig
	rig.global_position = kid.global_position + Vector3(0, 0, 2.0)
	fp.enter()
	fp.global_position = kid.global_position + Vector3(0, 0.1, 2.0)
	await _frames(10)
	dlg.start(kid, fp)
	fp._suspend("talk")
	var opts := dlg._build_options()
	var idx := -1
	for i in opts.size():
		if str(opts[i].get("key", "")) == "oaq":
			idx = i
	print("Câu rủ chơi trong hội thoại: %s" % ("có" if idx >= 0 else "KHÔNG"))
	dlg._options = opts
	dlg._choose(idx)
	dlg._choose(0)          # (Ngồi xuống chơi)
	await _frames(5)
	print("Đang chơi: %s, camera bàn: %s, nhập vai tạm dừng: '%s', đối thủ ngồi: %s" % [g.active, g._cam.current, fp._suspended, kid.work_anim])
	# Người chơi đi 3 nước (lấy nước tốt nhất như máy dễ), chờ máy đáp
	for k in 3:
		await _until_turn(g)
		if g.over:
			break
		var m := g.ai_move(g.st, OAnQuan.PLAYER)
		g._do_move(m.x, m.y)
		await _frames(10)
	await _until_turn(g)
	print("Sau vài lượt: điểm bạn %d – %d %s, lượt: %s" % [int(g.st.score[0]), int(g.st.score[1]), kid.display_name, "bạn" if g.turn == 0 else "máy"])
	g.stop()
	await _frames(5)
	print("Thôi chơi: bàn ẩn %s, nhập vai tiếp %s, camera nhập vai %s, đối thủ đứng dậy (%s)" % [
			not g._board.visible, fp._suspended == "" and fp.active, fp.camera.current, kid.work_anim])
	quit()

func _until_turn(g: OAnQuan) -> void:
	for i in 2000:
		if g.over or (g.turn == OAnQuan.PLAYER and not g._busy and g._queue.is_empty()):
			return
		await process_frame
