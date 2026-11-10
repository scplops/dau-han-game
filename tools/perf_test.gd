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
	var nodes: Array[Node] = []
	for n in scene.get_children():
		nodes.append(n)
	for n in scene.get_node("World").get_children():
		nodes.append(n)
	var rows: Array = []
	for n in nodes:
		if n.name == "World" or n.get_script() == null:
			continue
		var old := n.process_mode
		n.process_mode = Node.PROCESS_MODE_DISABLED
		var t: float = await _measure(60)
		n.process_mode = old
		rows.append([base - t, str(n.name)])
		for i in 5:
			await process_frame
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for r: Array in rows.slice(0, 12):
		print("   %-14s %.2f ms" % [r[1], float(r[0])])
	quit()
