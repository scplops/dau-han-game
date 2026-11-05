extends SceneTree
## Chạy thử một trận bóng không giao diện: đưa N người ra sân, mô phỏng theo bước cố định,
## in tỉ số, số lần bóng ra biên, thời gian bóng nằm yên.
## Dùng: godot --headless --path . -s tools/football_test.gd -- [--players=12] [--seconds=240]
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var f := scene.get_node("World/Football") as Football
	f.set_process(false)
	f.debug_match(int(args.get("players", "12")), 0.0)
	print("cầu thủ: ", f.players.size(), "  pha: ", Football.Phase.keys()[f.phase])
	var dt := 1.0 / 60.0
	var outs := 0
	var still := 0.0
	var last_score := [0, 0]
	var kicks := 0
	var secs := float(args.get("seconds", "240"))
	for i in int(secs * 60.0):
		var v0 := f._ball_vel
		f._step(dt)
		if f._ball_vel.length() > v0.length() + 2.0:
			kicks += 1
		if f._ball_vel.length() < 0.05 and f.phase == Football.Phase.PLAY:
			still += dt
			if args.has("debug") and i % 30 == 0:
				var nd := INF
				for p in f.players:
					nd = minf(nd, Vector2(p.v.global_position.x - f._ball_pos.x, p.v.global_position.z - f._ball_pos.z).length())
				print("  yên t=%.1f ball=%s gần nhất=%.2f restart=%.2f" % [i * dt, f._ball_pos, nd, f._restart_timer])
		if args.has("debug") and i % 600 == 0: print("  t=%d ball=%s vel=%.1f restart=%.2f" % [i / 60, f._ball_pos, f._ball_vel.length(), f._restart_timer])
		if f.score != last_score:
			print("%5.1fs  BÀN THẮNG  %s %d - %d %s" % [i * dt, Football.TEAM_NAMES[0], f.score[0], f.score[1], Football.TEAM_NAMES[1]])
			last_score = f.score.duplicate()
		if f.phase == Football.Phase.IDLE:
			print("%5.1fs  hết trận" % (i * dt))
			break
	outs = int(f.stats.throw) + int(f.stats.goal_kick) + int(f.stats.corner)
	print("cú chạm bóng: %d, bóng ra ngoài: %d (ném biên %d, phát bóng lên %d, phạt góc %d), phạm lỗi %d, phạt đền %d, nghỉ giữa hiệp %s, bóng nằm yên khi đang đá: %.1fs" % [
			kicks, outs, f.stats.throw, f.stats.goal_kick, f.stats.corner, f.stats.fouls, f.stats.penalty, f.half == 2, still])
	quit()
