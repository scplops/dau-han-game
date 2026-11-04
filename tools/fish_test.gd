extends SceneTree
## Chạy thử mini-game câu cá không giao diện (người chơi giả): quăng, chờ, giật, kéo theo nhịp.
## Dùng: godot --headless --path . -s tools/fish_test.gd [-- --spot=N]   (chạy theo thời gian thật, ~3 phút)
## --spot: chỗ câu (0–2 bến sông, 3 trở đi là chỗ câu trên đò).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 60
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	var f := scene.get_node("Fishing") as Fishing
	await process_frame
	var spot := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spot="):
			spot = int(a.substr(7))
	f.start(spot, true)
	print("Chỗ câu %d: %s" % [spot, f._spots[spot].name])
	var results := {}
	var last := -1
	var t := 0.0
	var holding := false
	for frame in 60 * 240:
		await process_frame
		t += 1.0 / 60.0
		var st := f.state
		if st != last:
			print("%.1fs  %s  %s" % [t, Fishing.State.keys()[st], f._toast if f._toast_timer > 0 else ""])
			last = st
		match st:
			Fishing.State.READY:
				Input.action_press("fish_reel"); f._on_press(); holding = true
			Fishing.State.CHARGE:
				if f._power > 0.8:
					Input.action_release("fish_reel"); f._cast(f._power); holding = false
			Fishing.State.BITE:
				f._on_press()
			Fishing.State.REEL:
				# Giữ khi căng < 0.75, thả khi căng hơn
				if f._tension < 0.6 and not holding:
					Input.action_press("fish_reel"); holding = true
				elif f._tension > 0.8 and holding:
					Input.action_release("fish_reel"); holding = false
			Fishing.State.CAUGHT, Fishing.State.LOST:
				if holding:
					Input.action_release("fish_reel"); holding = false
		if f._total >= 4:
			break
	print("caught: ", f._total, "  log: ", f._log)
	f.stop()
	print("after stop state=", f.state, " locked=", (scene.get_node("HouseEntry") as HouseEntry).locked)
	quit()
