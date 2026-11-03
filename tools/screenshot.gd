extends SceneTree
## Chụp ảnh scene chính để tự kiểm tra hình ảnh.
## Dùng: godot --path . -s tools/screenshot.gd -- --out=screenshots/a.png [--hour=17]
##        [--yaw=0] [--pitch=-40] [--distance=38] [--focus=x,z] [--ortho] [--frames=30]

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

	# Góc camera
	var rig := scene.get_node_or_null("CameraRig") as CameraRig
	if rig != null:
		if args.has("yaw"): rig.yaw_deg = float(args["yaw"])
		if args.has("pitch"): rig.pitch_deg = float(args["pitch"])
		if args.has("distance"): rig.distance = float(args["distance"])
		if args.has("ortho"): rig.orthographic = true
		if args.has("focus"):
			var f := str(args["focus"]).split(",")
			rig.set_focus(Vector3(float(f[0]), 0.0, float(f[1])))
		rig.snap()

	# Chờ vài khung hình cho bóng đổ, shader ổn định
	for i in int(args.get("frames", "30")):
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
