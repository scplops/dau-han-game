extends SceneTree
## Chụp ảnh scene chính để tự kiểm tra hình ảnh.
## Dùng: godot --path . -s tools/screenshot.gd -- --out=screenshots/a.png [--hour=17]
##        [--yaw=0] [--pitch=-40] [--distance=38] [--focus=x,z] [--ortho] [--frames=30]
##        [--weather=storm] [--flash] (loé chớp)
##        [--npc=N|farmer|kid|buffalo…] (chọn NPC, đặt camera vào họ)
##        [--inside] (chụp trong nhà mình) [--enter=dinh|pagoda|house_N] [--hover] (rê chuột lên cửa)

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := _parse_args()
	var size_parts := str(args.get("size", "1920x1080")).split("x")
	DisplayServer.window_set_size(Vector2i(int(size_parts[0]), int(size_parts[1])))

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)

	# Giờ trong ngày (khi đã có node DayNight)
	var day_night := scene.get_node_or_null("DayNight")
	if day_night != null and args.has("hour"):
		day_night.set("time_of_day", float(args["hour"]))

	# Thời tiết: --weather=clear|cloudy|drizzle|storm|fog (nhảy ngay, tắt tự đổi)
	var weather := scene.get_node_or_null("Weather") as Weather
	if weather != null:
		weather.auto_change = false
		weather.set_weather(str(args.get("weather", "clear")), true)

	# Vào trong nhà
	var entry := scene.get_node_or_null("HouseEntry") as HouseEntry
	var inside := (args.has("inside") or args.has("enter")) and entry != null
	if inside:
		entry.enter_house(true, entry.find_entry(str(args.get("enter", "main"))))

	# Chọn NPC thứ N, đặt camera vào họ (--npc=N), hoặc NPC đầu tiên có vai trò --npc=farmer
	var vs := scene.get_node_or_null("World/Villagers") as Villagers
	var npc: Villager = null
	if vs != null and args.has("npc"):
		var key := str(args["npc"])
		for v in vs.people + vs.animals:
			if (key.is_valid_int() and v == (vs.people + vs.animals)[int(key)]) or (v.role == key and v.visible):
				npc = v
				break
		if npc != null:
			vs.select_villager(npc)
			vs._following = true   # camera đi theo để NPC luôn ở giữa khung

	# Góc camera (camera đang dùng)
	var rig := scene.get_node_or_null("InteriorCameraRig" if inside else "CameraRig") as CameraRig
	if rig != null:
		if args.has("yaw"): rig.yaw_deg = float(args["yaw"])
		if args.has("pitch"): rig.pitch_deg = float(args["pitch"])
		if args.has("distance"): rig.distance = float(args["distance"])
		if args.has("ortho"): rig.orthographic = true
		if npc != null and not args.has("focus"):
			rig.set_focus(npc.global_position)
		if args.has("focus"):
			var f := str(args["focus"]).split(",")
			rig.set_focus(Vector3(float(f[0]), 0.0, float(f[1])))
		rig.snap()

	# Chờ vài khung hình cho bóng đổ, shader ổn định
	for i in int(args.get("frames", "30")):
		await process_frame
		# Đưa chuột lên cửa để kiểm tra viền sáng + gợi ý
		if args.has("hover") and i == 3 and rig != null:
			var house := scene.get_node_or_null("World/House") as Node3D
			var door := Vector3(0.0, 0.9, 1000.0 + 1.2) if inside else Vector3.ZERO
			if not inside and house != null:
				var target := house.find_child("ClickTarget", true, false) as Node3D
				door = target.global_position
			root.warp_mouse(rig.camera.unproject_position(door))
	if args.has("flash") and weather != null:
		weather.flash_now()
		weather.process_mode = Node.PROCESS_MODE_DISABLED   # giữ nguyên tia chớp cho khung chụp
		await process_frame
	await RenderingServer.frame_post_draw

	var out := str(args.get("out", "screenshots/shot.png"))
	var abs_path := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := root.get_texture().get_image().save_png(abs_path)
	print("Saved screenshot: ", abs_path, " (err=", err, ")")
	quit()


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		result[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return result
