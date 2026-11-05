extends SceneTree
## Thử luật bóng đá làng + người nhập vai vào đá (headless):
## 1) Luật trên tình huống dựng sẵn: ném biên, phạt góc, phát bóng lên (thủ môn đá), phạm lỗi ngoài / trong
##    vòng cấm (đá phạt / phạt đền), bàn thắng hiệp 2 tính đúng đội (đổi sân).
## 2) Một trận máy đấu máy (10 người, bước 1/60 s): đếm pha đá lại, phạm lỗi, phạt đền, nghỉ giữa hiệp, hết giờ.
## 3) Người nhập vai: 16:40, đứng giữa sân → "E: Xin vào đá" → vào đội, gọi người ra sân → trận bắt đầu;
##    tự chạy tới bóng sút về khung thành đối phương; gọi chuyền; ném biên + sút phạt đền; thôi nhập vai → rời đội.
## Dùng: godot --headless --path . -s tools/football_join_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _sim(fb: Football, seconds: float) -> void:
	for i in int(seconds * 60.0):
		fb._step(1.0 / 60.0)

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var fb := scene.get_node("World/Football") as Football
	fb.set_process(false)
	var c := fb.rect.get_center()
	var ok := 0
	var n := 0
	# --- 1) Luật
	fb.debug_match(8, 0.0)
	fb.phase = Football.Phase.PLAY
	# Đội 0 chạm cuối, bóng ra biên dọc phía bắc → đội 1 ném biên, bóng đặt trên vạch
	fb._last_team = 0
	fb._ball_pos = Vector3(c.x + 3.0, 0.13, fb.rect.position.y - 0.5)
	fb._step_ball(0.0)
	_sim(fb, 1.0)
	var r := fb._restart
	n += 1; ok += int(r.get("kind") == "throw" and int(r.get("team")) == 1 and bool(r.get("placed")) and absf((r.pos as Vector3).z - fb.rect.position.y) < 0.2)
	print("ra biên dọc (đội 0 chạm cuối): %s cho đội %s, bóng trên vạch %s" % [r.get("kind"), r.get("team"), r.get("placed")])
	_sim(fb, 6.0)
	n += 1; ok += int(fb.phase == Football.Phase.PLAY)
	print("   người ném tới nơi và ném: giai đoạn %s" % Football.Phase.keys()[fb.phase])
	# Đội 0 (khung thành nhà ở x nhỏ hiệp 1) đá ra vạch cuối sân nhà → phạt góc cho đội 1
	fb.phase = Football.Phase.PLAY
	fb._last_team = 0
	fb._ball_pos = Vector3(fb.rect.position.x - 0.5, 0.13, c.y + 5.0)
	fb._step_ball(0.0)
	n += 1; ok += int(fb._restart.get("kind") == "corner" and int(fb._restart.get("team")) == 1)
	print("đội 0 đá ra vạch cuối sân nhà: %s cho đội %s" % [fb._restart.get("kind"), fb._restart.get("team")])
	# Đội 1 đá ra vạch cuối sân đội 0 → phát bóng lên cho đội 0, thủ môn đá
	fb.phase = Football.Phase.PLAY
	fb._last_team = 1
	fb._ball_pos = Vector3(fb.rect.position.x - 0.5, 0.13, c.y + 5.0)
	fb._step_ball(0.0)
	var taker: Variant = fb._restart.get("taker")
	n += 1; ok += int(fb._restart.get("kind") == "goal_kick" and int(fb._restart.get("team")) == 0 and taker is Dictionary and bool(taker.keeper))
	print("đội 1 đá ra vạch cuối sân đội 0: %s cho đội %s, thủ môn đá %s" % [fb._restart.get("kind"), fb._restart.get("team"), taker is Dictionary and bool(taker.keeper)])
	# Phạm lỗi giữa sân / trong vòng cấm đội 0
	fb.phase = Football.Phase.PLAY
	fb._foul(0, c + Vector2(2, 1), "Thử")
	n += 1; ok += int(fb._restart.get("kind") == "free" and int(fb._restart.get("team")) == 1)
	print("đội 0 phạm lỗi giữa sân: %s cho đội %s" % [fb._restart.get("kind"), fb._restart.get("team")])
	fb.phase = Football.Phase.PLAY
	fb._foul(0, Vector2(fb.rect.position.x + 1.5, c.y + 1.0), "Thử")
	var spot := fb._restart.pos as Vector3
	n += 1; ok += int(fb._restart.get("kind") == "penalty" and int(fb._restart.get("team")) == 1 and absf(spot.x - (fb.rect.position.x + 5.0)) < 0.1)
	print("đội 0 phạm lỗi trong vòng cấm nhà: %s cho đội %s, chấm cách vạch %.1f m" % [fb._restart.get("kind"), fb._restart.get("team"), spot.x - fb.rect.position.x])
	_sim(fb, 6.0)
	print("   sút phạt đền xong: giai đoạn %s, tỉ số %d – %d, cản được %d" % [Football.Phase.keys()[fb.phase], fb.score[0], fb.score[1], fb.stats.pen_saved])
	# Hiệp 2: bóng vào khung thành phía x lớn → đội 1 ghi (hiệp 1 thì đội 0)
	fb.half = 2
	fb.phase = Football.Phase.PLAY
	var before := fb.score.duplicate()
	fb._ball_pos = Vector3(fb.rect.end.x - 0.2, 0.3, c.y)
	fb._ball_vel = Vector3(6, 0, 0)
	_sim(fb, 0.2)
	n += 1; ok += int(fb.score[1] == before[1] + 1 and fb.score[0] == before[0])
	print("hiệp 2, bóng vào khung thành phía đông: tỉ số %d – %d → %d – %d (đội 1 ghi)" % [before[0], before[1], fb.score[0], fb.score[1]])
	print("LUẬT: %d/%d đúng" % [ok, n])
	fb._end_match()
	# --- 2) Một trận máy đấu máy
	fb.debug_match(10, 0.0)
	var seen_half := false
	var seen_full := false
	var t := 0.0
	while t < fb.match_length + 150.0:
		fb._step(1.0 / 60.0)
		t += 1.0 / 60.0
		seen_half = seen_half or fb.phase == Football.Phase.HALFTIME
		seen_full = seen_full or fb.phase == Football.Phase.FULLTIME
		if fb.phase == Football.Phase.IDLE and seen_full:
			break
	print("Trận máy đấu máy %d s: tỉ số %d – %d · ném biên %d · phát bóng lên %d · phạt góc %d · phạm lỗi %d (đá phạt %d, phạt đền %d, cản %d) · nghỉ giữa hiệp %s · hết giờ %s · tản đi %s" % [
			int(t), fb.score[0], fb.score[1], fb.stats.throw, fb.stats.goal_kick, fb.stats.corner, fb.stats.fouls,
			fb.stats.free, fb.stats.penalty, fb.stats.pen_saved, seen_half, seen_full, fb.players.is_empty()])
	# --- 3) Người nhập vai
	fb.set_process(true)
	var dn := scene.get_node("DayNight") as DayNight
	dn.time_of_day = 16.7
	var vs := scene.get_node("World/Villagers") as Villagers
	vs.replan()
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	var mid := fb.center3()
	rig.global_position = mid
	fp.enter()
	fp.global_position = mid + Vector3(1.0, 0.2, 0.5)
	await _frames(10)
	print("Đứng giữa sân: gợi ý '%s'" % fp.hud._hint.text if fp.hud.get("_hint") != null else fb.join_hint(fp.global_position))
	print("   join_hint: '%s', đích nhìn là sân: %s" % [fb.join_hint(fp.global_position), fp._look_target == fb])
	fp._act()
	await _frames(2)
	print("   E: đội của bạn %s, người trên sân %d, đang được gọi ra %d, thông báo '%s'" % [
			Football.TEAM_NAMES[fb.user_team] if fb.user_team >= 0 else "-", fb.players.size(),
			vs.people.filter(func(v: Villager) -> bool: return v.activity == "football").size(), fb._call_text])
	Engine.time_scale = 6.0
	for k in 120:
		await _frames(30)
		if fb.phase in [Football.Phase.KICKOFF, Football.Phase.PLAY] and fb.players.size() >= 4:
			break
	print("   chờ mọi người tới: %d người máy trên sân, đội %d – %d người, giai đoạn %s" % [
			fb.players.size(), fb._team_counts()[0], fb._team_counts()[1], Football.Phase.keys()[fb.phase]])
	# Người chơi tự đá: chạy tới bóng (đặt sát sau bóng), nhìn về khung thành đối phương, sút
	var shots := 0
	var touches0 := int(fb.stats.user_touches)
	for k in 40:
		await _frames(20)
		if fb.phase != Football.Phase.PLAY or fb.user_team < 0:
			continue
		var goal := Vector3(fb.rect.end.x if fb._attack_dir(fb.user_team) > 0.0 else fb.rect.position.x, 0, c.y)
		var b := fb.ball_position()
		var to := (goal - b)
		to.y = 0.0
		fp.global_position = Vector3(b.x, fp.global_position.y, b.z) - to.normalized() * 0.9
		fp.velocity = Vector3.ZERO
		fp.rotation.y = atan2(-to.x, -to.z)
		fp._pitch = -0.1
		fp.camera.rotation.x = fp._pitch
		await _frames(1)
		fb.user_charge_start()
		fb._charge = 0.7
		fb.user_charge_release(-fp.camera.global_transform.basis.z)
		shots += 1
	print("   bạn sút %d lần, chạm bóng %d, bàn của bạn %d, tỉ số %d – %d, phạm lỗi của bạn %d" % [
			shots, int(fb.stats.user_touches) - touches0, fb.stats.user_goals, fb.score[0], fb.score[1], fb.stats.user_fouls])
	# Gọi chuyền: đứng trống trải phía trên, gọi Q, chờ đồng đội chuyền
	var calls := int(fb.stats.pass_to_user)
	for k in 6:
		if fb.phase != Football.Phase.PLAY:
			await _frames(60)
			continue
		var gx := fb.rect.end.x if fb._attack_dir(fb.user_team) > 0.0 else fb.rect.position.x
		fp.global_position = Vector3(lerpf(c.x, gx, 0.5), fp.global_position.y, c.y + 4.0)
		fb.user_call()
		await _frames(150)
	print("   gọi chuyền 6 lần: đồng đội chuyền cho bạn %d lần" % (int(fb.stats.pass_to_user) - calls))
	# Bạn ném biên + sút phạt đền
	Engine.time_scale = 1.0
	fb.phase = Football.Phase.PLAY
	fp.global_position = Vector3(c.x, fp.global_position.y, fb.rect.position.y + 0.8)
	fb._begin_restart("throw", fb.user_team, Vector3(c.x, 0, fb.rect.position.y + 0.1), 0.0)
	fb._step(1.0 / 60.0)
	var thrower: Variant = fb._restart.get("taker")
	fb.user_charge_start()
	await _frames(10)
	fp.rotation.y = 0.0
	fb.user_charge_release(Vector3(0.3, 0.2, 1.0).normalized())
	print("   ném biên gần bạn: người ném '%s', ném xong giai đoạn %s, bóng bay %.1f m/s" % [thrower, Football.Phase.keys()[fb.phase], fb._ball_vel.length()])
	var opp := 1 - fb.user_team
	var pen_goals := 0
	var pen_saves := 0
	for k in 6:
		var before_s: int = fb.score[fb.user_team]
		var saved0 := int(fb.stats.pen_saved)
		fb.phase = Football.Phase.PLAY
		var box_x := fb._own_goal_x(opp) + fb._attack_dir(opp) * 1.5
		fb._foul(opp, Vector2(box_x, c.y), "Thử")
		var sp := fb._restart.pos as Vector3
		fp.global_position = Vector3(sp.x, fp.global_position.y, sp.z) - Vector3(fb._attack_dir(fb.user_team), 0, 0) * 0.9
		for f in 60:
			fb._step(1.0 / 60.0)
		var gx2 := fb.rect.end.x if fb._attack_dir(fb.user_team) > 0.0 else fb.rect.position.x
		var aimz := c.y + (1.0 if k % 2 == 0 else -1.0) * (0.9 + 0.13 * k)
		var d := Vector3(gx2, 0.5, aimz) - Vector3(sp.x, 1.6, sp.z)
		fb.user_charge_start()
		fb._charge = 0.8
		var taker_ok: bool = fb._restart.get("taker") is String
		fb.user_charge_release(d.normalized())
		var v0 := fb._ball_vel
		for f in 120:
			fb._step(1.0 / 60.0)
		print("      quả %d: người sút là bạn %s, hướng z %.2f, vận tốc (%.1f, %.1f, %.1f), bóng dừng ở (%.1f, %.1f) cách vạch %.1f, giai đoạn %s" % [
				k, taker_ok, aimz - c.y, v0.x, v0.y, v0.z, fb._ball_pos.x - c.x, fb._ball_pos.z - c.y, absf(fb._ball_pos.x - gx2), Football.Phase.keys()[fb.phase]])
		pen_goals += int(fb.score[fb.user_team] > before_s)
		pen_saves += int(int(fb.stats.pen_saved) > saved0)
		if fb.phase == Football.Phase.GOAL:
			fb._begin_kickoff()
	print("   bạn sút 6 quả phạt đền: vào %d, thủ môn cản %d" % [pen_goals, pen_saves])
	fp.exit()
	await _frames(5)
	print("   thôi nhập vai: còn trong đội %s, bảng tỉ số ẩn %s" % [fb.user_team >= 0, not fb._ui.visible])
	quit()
