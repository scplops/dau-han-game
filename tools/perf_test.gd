extends SceneTree
## Đo hiệu năng phần script (mục 45), headless: thời gian xử lý trung bình mỗi khung của cả game, rồi lần lượt tắt
## từng node (process_mode = DISABLED) để xem node đó tốn bao nhiêu. Chạy với `timeout`.
## Dùng: timeout 170 godot --headless --path . -s tools/perf_test.gd [-- --hour=15 --frames=240]
func _initialize() -> void:
	_run.call_deferred()

func _measure(frames: int) -> float:
	var total := 0.0
	for i in frames:
		await process_frame
		total += Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return total / frames * 1000.0

func _run() -> void:
	var hour := 15.0
	var frames := 240
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			hour = float(a.get_slice("=", 1))
		elif a.begins_with("--frames="):
			frames = int(a.get_slice("=", 1))
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	var cal := scene.get_node("Calendar") as LunarCalendar
	var dn := scene.get_node("DayNight") as DayNight
	var vs := scene.get_node("World/Villagers") as Villagers
	cal.set_date_string("2027-06-20")
	dn.time_of_day = hour
	dn.auto_run = false
	for i in 30:
		await process_frame
	vs.replan()
	Engine.time_scale = 4.0
	for i in 600:
		await process_frame                # cho dân làng ra đường, các trò bắt đầu
	Engine.time_scale = 1.0
	var out := 0
	for v in vs.people:
		if v.visible:
			out += 1
	var base: float = await _measure(frames)
	print("Giờ %.1f · %d / %d người ngoài đường · %d node · mỗi khung %.2f ms (script + vật lý)" % [hour, out, vs.people.size(),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), base])
	vs.stat_next = 0
	vs.stat_people_us = 0
	vs.stat_animals_us = 0
	vs.stat_acts = {}
	var t1 := Time.get_ticks_usec()
	for k in 120:
		vs._process(1.0 / 60.0)
	var per := (Time.get_ticks_usec() - t1) / 120000.0
	var acts := {}
	for v in vs.people:
		acts[v.activity] = int(acts.get(v.activity, 0)) + 1
	print("   người %.2f ms · con vật %.2f ms" % [vs.stat_people_us / 120000.0, vs.stat_animals_us / 120000.0])
	print("   Villagers: %.2f ms / khung · lên lịch lại %.1f lần / khung %s · việc: %s" % [per, vs.stat_next / 120.0, vs.stat_acts, acts])
	# Gọi thẳng _process / _physics_process của từng node 60 lần, bấm giờ (ít nhiễu hơn so với tắt / bật node)
	var nodes: Array[Node] = []
	for n in scene.get_children():
		nodes.append(n)
	for n in scene.get_node("World").get_children():
		nodes.append(n)
	var rows: Array = []
	var sum := 0.0
	for n in nodes:
		if n.get_script() == null:
			continue
		var us := 0
		for m: String in ["_process", "_physics_process"]:
			if n.has_method(m) and ((m == "_process" and n.is_processing()) or (m == "_physics_process" and n.is_physics_processing())):
				var t0 := Time.get_ticks_usec()
				for k in 60:
					n.call(m, 1.0 / 60.0)
				us += Time.get_ticks_usec() - t0
		if us > 0:
			rows.append([us / 60000.0, str(n.name)])
			sum += us / 60000.0
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	print("   tổng các _process đo trực tiếp: %.2f ms" % sum)
	for r: Array in rows.slice(0, 14):
		print("   %-14s %.3f ms" % [r[1], float(r[0])])
	quit()
