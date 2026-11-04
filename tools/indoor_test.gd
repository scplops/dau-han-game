extends SceneTree
## Thử dân làng trong nhà (mục 22) không giao diện: vào một toà, chạy thời gian thật một lúc,
## in ai đang ở trong, tư thế, ai mới vào / mới ra; thử nói chuyện với một người trong nhà.
## Dùng: godot --headless --path . -s tools/indoor_test.gd -- --enter=pagoda --hour=8.5 --seconds=40
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 60
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	(scene.get_node("DayNight") as DayNight).time_of_day = float(args.get("hour", "12"))
	var vs := scene.get_node("World/Villagers") as Villagers
	vs.replan()
	await process_frame
	var he := scene.get_node("HouseEntry") as HouseEntry
	var folk := scene.get_node("IndoorFolk") as IndoorFolk
	he.enter_house(true, he.find_entry(str(args.get("enter", "house_9"))))
	await process_frame
	var secs := int(args.get("seconds", "30"))
	for s in secs:
		await create_timer(1.0).timeout
		if s % 10 == 0 or s == secs - 1:
			var lines: Array[String] = []
			for f in folk._folk:
				var p: Villager = f.proxy
				lines.append("%s (%s%s)" % [p.display_name, p.work_anim, ", đi ra" if f.leaving else (", đang vào" if p.state == Villager.State.WALK else "")])
			print("%3ds — %d người: %s" % [s, folk._folk.size(), ", ".join(lines)])
	# Nói chuyện với người đầu tiên đang ngồi
	var dlg := scene.get_node("Dialogue") as Dialogue
	for f in folk._folk:
		var p: Villager = f.proxy
		if p.state == Villager.State.IDLE and p.work_anim != "sleep":
			print(dlg.transcript(p, scene.get_node("FirstPerson") as Node3D, 1))
			break
	quit()
