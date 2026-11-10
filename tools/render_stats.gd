extends SceneTree
## Đo phần vẽ (mục 46), chạy dưới xvfb: số vật thể / tam giác / draw call mỗi khung ở vài góc nhìn, số node theo loại.
## Dùng: timeout 170 xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 -s tools/render_stats.gd
func _initialize() -> void:
	_run.call_deferred()

func _count(n: Node, acc: Dictionary) -> void:
	var c := n.get_class()
	acc[c] = int(acc.get(c, 0)) + 1
	if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree():
		acc["(hiện) " + c] = int(acc.get("(hiện) " + c, 0)) + 1
		if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			acc["(đổ bóng)"] = int(acc.get("(đổ bóng)", 0)) + 1
	for ch in n.get_children():
		_count(ch, acc)

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	var cal := scene.get_node("Calendar") as LunarCalendar
	var dn := scene.get_node("DayNight") as DayNight
	var vs := scene.get_node("World/Villagers") as Villagers
	var rig := scene.get_node("CameraRig") as CameraRig
	cal.set_date_string("2027-06-20")
	dn.time_of_day = 15.0
	dn.auto_run = false
	for i in 20:
		await process_frame
	vs.replan()
	Engine.time_scale = 30.0
	for i in 40:
		await process_frame
	Engine.time_scale = 1.0
	var acc := {}
	_count(scene, acc)
	var keys := acc.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(acc[a]) > int(acc[b]))
	var line := ""
	for k: String in keys.slice(0, 14):
		line += "%s %d · " % [k, int(acc[k])]
	print("Node: ", line)
	for view: Array in [["nhà mình (mặc định)", Vector3(0, 0, 0), 28.0], ["cổng làng", Vector3(0, 0, -45), 40.0], ["giữa làng", Vector3(0, 0, -100), 60.0], ["cả làng từ xa", Vector3(0, 0, -100), 150.0]]:
		rig.set_focus(view[1])
		rig.global_position = view[1]
		rig.distance = float(view[2])
		rig.snap()
		for i in 4:
			await process_frame
		print("%-22s vật thể %5d · tam giác %8d · draw call %5d" % [view[0],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	if not OS.get_cmdline_user_args().has("--breakdown"):
		quit()
		return
	rig.set_focus(Vector3.ZERO)
	rig.global_position = Vector3.ZERO
	rig.distance = 28.0
	rig.snap()
	dn.auto_run = false
	scene.get_node("World/Villagers").process_mode = Node.PROCESS_MODE_DISABLED     # đứng yên cho số liệu khỏi nhiễu
	for i in 4:
		await process_frame
	# Tách phần đóng góp: ẩn từng nhóm rồi xem còn bao nhiêu (góc nhìn mặc định)
	var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
	var world := scene.get_node("World")
	var tests: Array = [["đủ cả", null], ["tắt bóng mặt trời", "sun"]]
	for n in world.get_children():
		tests.append(["ẩn " + str(n.name), n])
	for nm: String in ["Farming", "Festival", "Seasons"]:
		tests.append(["ẩn " + nm, scene.get_node(nm)])
	# Chi tiết hơn: --detail=Village liệt kê từng node con của nhóm đó
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--detail="):
			tests = [["đủ cả", null], ["tắt bóng mặt trời", "sun"]]
			for n in world.get_node(a.get_slice("=", 1)).get_children():
				if n is Node3D:
					tests.append(["ẩn " + str(n.name), n])
	for t: Array in tests:
		var target: Variant = t[1]
		if target is String and sun != null:
			sun.shadow_enabled = false
		elif target is Node3D:
			(target as Node3D).visible = false
		for i in 3:
			await process_frame
		print("%-22s vật thể %5d · tam giác %8d · draw call %5d" % [t[0],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		if target is String and sun != null:
			sun.shadow_enabled = true
		elif target is Node3D:
			(target as Node3D).visible = true
	quit()
