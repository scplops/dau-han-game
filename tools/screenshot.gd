extends SceneTree
## Chụp ảnh scene chính để tự kiểm tra hình ảnh.
## Dùng: godot --path . -s tools/screenshot.gd -- --out=screenshots/a.png [--hour=17]
##        [--yaw=0] [--pitch=-40] [--distance=38] [--focus=x,z] [--ortho] [--frames=30]
##        [--weather=storm] [--flash] (loé chớp)
##        [--npc=N|farmer|kid|buffalo…] (chọn NPC, đặt camera vào họ)
##        [--fish=N] [--fish-state=charge|wait|nibble|bite|reel|caught] (câu cá ở bến thứ N)
##        [--football=N] (N người ra sân đá ngay, camera nhìn vào sân bóng)
##        [--fp] [--fp-yaw=độ] [--fp-pitch=độ] (nhập vai góc nhìn thứ nhất ở --focus;
##        cùng --enter=khoá thì đi bộ bên trong toà nhà đó)
##        [--quest=water,lost,…] (nhận sẵn các việc nhờ từ người gần nhất có vai hợp)
##        [--talk] [--talk-pick=N] (cùng --fp: bắt chuyện người gần nhất, chọn câu hỏi thứ N)
##        [--map=small|large|hidden] (bản đồ nhỏ)
##        [--fp --fp-board=N --fp-at=x,z] (nhập vai đứng trên đò N, toạ độ cục bộ của đò; --fp-yaw
##        khi đó tính so với hướng mũi đò)
##        [--boat=N] [--boat-drive=giây] [--boat-cam=độ] (lên đò thứ N, chèo trước vài giây,
##        xoay camera đò quanh đò; trong lúc chờ khung hình vẫn chèo để thấy dáng chèo)
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

	# Giờ đổi sau khi dân làng đã lên lịch lúc 17:00 → lên lại lịch theo giờ chụp
	var vs0 := scene.get_node_or_null("World/Villagers") as Villagers
	if vs0 != null and args.has("hour"):
		vs0.replan()

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

	# Câu cá ở bến thứ N, dựng sẵn trạng thái
	var fishing := scene.get_node_or_null("Fishing") as Fishing
	if fishing != null and args.has("fish"):
		fishing.start(int(args["fish"]), true)
		if args.has("fish-state"):
			fishing.debug_state(str(args["fish-state"]))

	# Sân bóng: đưa N người ra đá ngay, camera nhìn vào sân
	var football := scene.get_node_or_null("World/Football") as Football
	var football_focus := Vector3.INF
	if football != null and args.has("football"):
		football.debug_match(int(args["football"]))
		football_focus = football.center3()

	# Góc camera (camera đang dùng)
	var rig := scene.get_node_or_null("InteriorCameraRig" if inside else "CameraRig") as CameraRig
	if rig != null:
		if args.has("yaw"): rig.yaw_deg = float(args["yaw"])
		if args.has("pitch"): rig.pitch_deg = float(args["pitch"])
		if args.has("distance"): rig.distance = float(args["distance"])
		if args.has("ortho"): rig.orthographic = true
		if football_focus != Vector3.INF and not args.has("focus"):
			rig.set_focus(football_focus)
		if npc != null and not args.has("focus"):
			rig.set_focus(npc.global_position)
		if args.has("focus"):
			var f := str(args["focus"]).split(",")
			rig.set_focus(Vector3(float(f[0]), 0.0, float(f[1])))
		rig.snap()

	# Nhập vai: đứng ở tâm camera, quay theo --fp-yaw / --fp-pitch
	var fp := scene.get_node_or_null("FirstPerson") as FirstPerson
	if fp != null and args.has("fp"):
		await process_frame
		await physics_frame
		if inside:
			fp._dollhouse_to_walk()      # --enter=… --fp: đi bộ bên trong toà nhà
		else:
			fp.enter()
		# --fp-board=N [--fp-at=x,z]: đứng trên đò thứ N (toạ độ cục bộ của đò, mũi +z)
		if args.has("fp-board"):
			var brd := scene.get_node("BoatRide") as BoatRide
			var bi := int(args["fp-board"])
			brd.step_aboard(bi)
			if args.has("fp-at"):
				var at := str(args["fp-at"]).split(",")
				fp.global_position = brd.river.boat_nodes[bi].to_global(Vector3(float(at[0]), River.BOAT_DECK + 0.05, float(at[1])))
			if args.has("fp-yaw"):
				fp.rotation.y = brd.river.boat_nodes[bi].rotation.y + PI + deg_to_rad(float(args["fp-yaw"]))
		elif args.has("fp-yaw"): fp.rotation.y = deg_to_rad(float(args["fp-yaw"]))
		if args.has("fp-pitch"):
			fp._pitch = deg_to_rad(float(args["fp-pitch"]))
			fp.camera.rotation.x = fp._pitch
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Nhận sẵn việc nhờ để xem dấu chỉ đường, khung "Việc được nhờ"
		var qs := scene.get_node_or_null("Quests") as Quests
		var vs3 := scene.get_node_or_null("World/Villagers") as Villagers
		if args.has("quest") and qs != null and vs3 != null:
			var taken := {}
			for kind in str(args["quest"]).split(","):
				var best_q: Villager = null
				for v in vs3.people:
					if not v.visible or taken.has(v) or not Quests.KINDS_BY_ROLE.get(v.role, []).has(kind):
						continue
					if best_q == null or v.global_position.distance_to(fp.global_position) < best_q.global_position.distance_to(fp.global_position):
						best_q = v
				if best_q != null:
					taken[best_q] = true
					qs.debug_accept(best_q, kind)
			qs._refresh_offers()
		# Bắt chuyện người đang đứng gần nhất: đứng trước mặt họ, mở khung thoại
		var dlg := scene.get_node_or_null("Dialogue") as Dialogue
		var vs2 := scene.get_node_or_null("World/Villagers") as Villagers
		if args.has("talk") and dlg != null and vs2 != null:
			var best: Villager = null
			for v in vs2.people:
				if v.visible and (best == null or v.global_position.distance_to(fp.global_position) < best.global_position.distance_to(fp.global_position)):
					best = v
			if best != null:
				var face := Basis(Vector3.UP, best.rotation.y) * Vector3.BACK
				fp.global_position = best.global_position + face * 1.8 + Vector3(0, 0.05, 0)
				fp._look_target = best
				fp._act()
				for k in 30:
					await process_frame
				dlg._finish_typing()
				if args.has("talk-pick"):
					dlg._choose(int(args["talk-pick"]) - 1)
					await process_frame
					dlg._finish_typing()

	# Đò: --boat=N lên đò, --boat-drive=giây chèo tới trước
	var br := scene.get_node_or_null("BoatRide") as BoatRide
	var rowing := false
	if br != null and args.has("boat"):
		br.board(int(args["boat"]))
		for k in int(float(args.get("boat-drive", "0")) * 60.0):
			br.step(1.0 / 60.0, 1.0, 0.0, false)
		if args.has("boat-cam"):
			br._cam_yaw = deg_to_rad(float(args["boat-cam"]))
		br._cam.global_position = br._cam_target()
		rowing = true

	# Bản đồ nhỏ: --map=large | hidden
	var mm := scene.get_node_or_null("HUD/MiniMap") as MiniMap
	if mm != null and args.has("map"):
		mm.mode = MiniMap.Mode.LARGE if str(args["map"]) == "large" else (MiniMap.Mode.HIDDEN if str(args["map"]) == "hidden" else MiniMap.Mode.SMALL)
		mm._apply_mode()

	# Chờ vài khung hình cho bóng đổ, shader ổn định
	for i in int(args.get("frames", "30")):
		await process_frame
		if rowing:
			br.step(1.0 / 60.0, 0.8, 0.0, false)
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
