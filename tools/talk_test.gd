extends SceneTree
## In thử hội thoại với mỗi loại dân làng (không giao diện) để đọc lại lời lẽ, xưng hô.
## Dùng: godot --headless --path . -s tools/talk_test.gd -- [--hour=17]
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather(str(args.get("weather", "cloudy")), true)
	(scene.get_node("DayNight") as DayNight).time_of_day = float(args.get("hour", "17"))
	var vs := scene.get_node("World/Villagers") as Villagers
	vs.replan()
	await process_frame
	var fishing := scene.get_node("Fishing") as Fishing
	fishing._log = {"Cá chép": {"count": 2, "best": 2.35}, "Cá diếc": {"count": 1, "best": 0.3}}
	fishing._total = 3
	var dlg := scene.get_node("Dialogue") as Dialogue
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var seen := {}
	for v in vs.people + vs.animals:
		var key := v.role + ("_f" if v.get_meta("female", false) else "")
		if seen.has(key) or not v.visible:
			continue
		seen[key] = true
		fp.global_position = v.global_position + Vector3(1.5, 0, 0)
		print("\n=== %s (%s, %s) ===" % [v.display_name, v.role_name, v.activity])
		print(dlg.transcript(v, fp, 4))
	# Gặp lại lần hai
	for v in vs.people:
		if v.visible and v.role == "elder":
			print("\n=== Gặp lại %s ===" % v.display_name)
			print(dlg.transcript(v, fp, 1))
			break
	quit()
