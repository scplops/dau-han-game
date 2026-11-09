extends SceneTree
## Chụp ảnh scene chính để tự kiểm tra hình ảnh.
## Dùng: godot --path . -s tools/screenshot.gd -- --out=screenshots/a.png [--hour=17]
##        [--yaw=0] [--pitch=-40] [--distance=38] [--focus=x,z] [--ortho] [--frames=30]
##        [--weather=storm] [--flash] (loé chớp)
##        [--npc=N|farmer|kid|buffalo…] (chọn NPC, đặt camera vào họ)
##        [--fish=N] [--fish-state=charge|wait|nibble|bite|reel|caught] (câu cá ở bến thứ N)
##        [--football=N] (N người ra sân đá ngay, camera nhìn vào sân bóng)
##        [--enter=house_0 --fp --fp-in=stair|up|x,y,z] (đứng ở chân cầu thang / trên gác nhà 2 tầng)
##        [--fp] [--fp-yaw=độ] [--fp-pitch=độ] (nhập vai góc nhìn thứ nhất ở --focus;
##        cùng --enter=khoá thì đi bộ bên trong toà nhà đó)
##        [--quest=water,lost,…] (nhận sẵn các việc nhờ từ người gần nhất có vai hợp)
##        [--talk] [--talk-pick=N] (cùng --fp: bắt chuyện người gần nhất, chọn câu hỏi thứ N)
##        [--map=small|large|hidden] (bản đồ nhỏ)
##        [--fp --fp-board=N --fp-at=x,z] (nhập vai đứng trên đò N, toạ độ cục bộ của đò; --fp-yaw
##        khi đó tính so với hướng mũi đò)
##        [--date=YYYY-MM-DD] [--lunar-day=N] (ngày dương / nhảy tới ngày âm N, vd. 15 = rằm)
##        [--settle=giây] (chạy trước, tua nhanh, cho dân làng kịp đi tới nơi)
##        [--race=giây | --race-result] (đua thuyền: chèo đúng nhịp tới giây đó / tới đích)
##        [--race-mode=team|solo] [--race-boats=N] [--race-obstacles=0|1] [--race-seed=N] [--race-setup]
##        [--kite=giây] (cùng --fp: thả diều mượn của đứa trẻ gần nhất)
##        [--fb-join=N] [--fb-restart=throw|corner|free|penalty] (cùng --fp: vào đá bóng)
##        [--rope=N] (bãi nhảy dây thứ N) [--rope-play[=số lần]] (cùng --fp: bạn đang nhảy dây)
##        [--khang=N] (bãi đánh khăng thứ N) [--khang-play[=giai đoạn]] (cùng --fp: bạn đang đánh khăng)
##        [--crop-day=N] (ngày N trong vụ lúa: 2 cày, 8 cấy, 40 xanh, 60 trổ, 76 chín, 84 gặt, 89 rạ)
##        [--oaq=N] (cùng --fp: chơi ô ăn quan với người gần nhất, đi trước N lượt)
##        [--hs [--hs-count] [--hs-look=N]] (cùng --fp: trốn tìm với đứa trẻ gần nhất)
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

	# Ngày: --date=YYYY-MM-DD, --lunar-day=N (nhảy tới ngày gần nhất có ngày âm N, vd. 15 = rằm)
	var cal := scene.get_node_or_null("Calendar") as LunarCalendar
	if cal != null:
		if args.has("date"):
			cal.set_date_string(str(args["date"]))
		if args.has("lunar-day"):
			cal.goto_lunar_day(int(args["lunar-day"]))

	# Giờ đổi sau khi dân làng đã lên lịch lúc 17:00 → lên lại lịch theo giờ chụp
	var vs0 := scene.get_node_or_null("World/Villagers") as Villagers
	if vs0 != null and (args.has("hour") or args.has("date") or args.has("lunar-day")):
		vs0.replan()
	var sd0 := scene.get_node_or_null("SchoolDay") as SchoolDay
	if sd0 != null and (args.has("hour") or args.has("date") or args.has("lunar-day")):
		await process_frame
		sd0.replan()
	# --settle=giây: chạy trước cho dân làng kịp đi tới nơi (tua nhanh)
	if args.has("settle"):
		Engine.time_scale = 4.0
		for i in int(float(args["settle"]) * 15.0):
			await physics_frame
		Engine.time_scale = 1.0

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
		# --fp-in=x,y,z: chỗ đứng trong toà nhà (toạ độ cục bộ nội thất; "stair" = chân cầu thang, "up" = trên gác)
		if inside and args.has("fp-in"):
			var itr := entry.interior
			var where := str(args["fp-in"])
			var lp: Vector3
			if where == "stair":
				lp = itr.stair.bottom + Vector3(0, 0.05, 0.6)
			elif where == "up":
				lp = itr.stair.top + Vector3(1.2, 0.05, 0.1)
			else:
				var c := where.split(",")
				lp = Vector3(float(c[0]), float(c[1]), float(c[2]))
			fp.global_position = itr.to_global(lp)
			fp.velocity = Vector3.ZERO
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

	# Ô ăn quan: --oaq=N (cùng --fp): rủ người gần nhất chơi, đi trước N lượt (tự chọn nước)
	var oaq := scene.get_node_or_null("OAnQuan") as OAnQuan
	if oaq != null and args.has("oaq") and fp != null and fp.active:
		var vsq := scene.get_node("World/Villagers") as Villagers
		var best: Villager = null
		for v in vsq.people:
			if v.visible and v.role in ["kid", "elder"] and (best == null or v.global_position.distance_to(fp.global_position) < best.global_position.distance_to(fp.global_position)):
				best = v
		if best != null:
			best.state = Villager.State.IDLE
			oaq.start(best)
			print("Ô ăn quan với ", best.display_name, " · việc ", best.activity, " · ở trường ", best.has_meta("at_school"))
			for k in int(args["oaq"]):
				for f in 3000:
					if oaq.over or (oaq.turn == OAnQuan.PLAYER and not oaq._busy and oaq._queue.is_empty()):
						break
					await process_frame
				if oaq.over:
					break
				var m := oaq.ai_move(oaq.st, OAnQuan.PLAYER)
				oaq._do_move(m.x, m.y)
			# --oaq-side: camera nhìn ngang từ bên hông bàn (kiểm tra dáng ngồi)
			if args.has("oaq-side"):
				var bx := oaq._board.global_transform
				oaq._cam.global_position = bx.origin + bx.basis.x * 2.6 + Vector3(0, 0.9, 0)
				oaq._cam.look_at(bx.origin + Vector3(0, 0.3, 0), Vector3.UP)
			# Chụp giữa lúc đang rải (còn sỏi trên tay)
			for f in (3000 if int(args["oaq"]) > 0 else 0):
				if not oaq._hand.is_empty() or oaq.over:
					break
				await process_frame

	# Trốn tìm: --hs (cùng --fp) rủ đứa trẻ gần nhất; --hs-count chụp lúc đang đếm; không có thì chờ
	# hết đếm rồi đứng cách đứa thứ --hs-look=N khoảng 6 m (chỗ nhìn thấy được), quay về phía nó
	var hsk := scene.get_node_or_null("HideSeek") as HideSeek
	if hsk != null and args.has("hs") and fp != null and fp.active:
		var vsh := scene.get_node("World/Villagers") as Villagers
		var kid: Villager = null
		for v in vsh.people:
			if v.visible and v.role == "kid" and (kid == null or v.global_position.distance_to(fp.global_position) < kid.global_position.distance_to(fp.global_position)):
				kid = v
		if kid != null:
			hsk.start(kid)
			if not args.has("hs-count"):
				Engine.time_scale = 4.0
				for f in int((hsk.count_seconds + 0.5) * 15.0):
					await physics_frame
				Engine.time_scale = 1.0
				hsk._hint_t = 9999.0
				var hi := clampi(int(args.get("hs-look", "0")), 0, hsk.hiders.size() - 1)
				var h := hsk.hiders[hi]
				var sp := fp.get_world_3d().direct_space_state
				var tgt := h.global_position + Vector3(0, 0.6, 0)
				for k in 24:
					var a := TAU * k / 24.0
					var pp := h.global_position + Vector3(cos(a), 0, sin(a)) * 7.8
					var pr := PhysicsRayQueryParameters3D.create(pp + Vector3(0, 1.6, 0), tgt, 1 << (FirstPerson.SOLID_LAYER - 1))
					var pr2 := PhysicsRayQueryParameters3D.create(pp + Vector3(0, 1.6, 0), h.global_position + Vector3(0, 0.15, 0), 1 << (FirstPerson.SOLID_LAYER - 1))
					if sp.intersect_ray(pr).is_empty() and sp.intersect_ray(pr2).is_empty():
						fp.global_position = pp + Vector3(0, 0.1, 0)
						break
				var dd := tgt - (fp.global_position + Vector3(0, 1.6, 0))
				fp.rotation.y = atan2(-dd.x, -dd.z) + 0.12
				fp._pitch = atan2(dd.y, Vector2(dd.x, dd.z).length())
				fp.camera.rotation.x = fp._pitch

	# Đua thuyền: --race=giây (vào đua, chèo đúng nhịp tới giây đó; 0 = lúc đếm ngược),
	# --race-result (chèo tới đích, chụp bảng kết quả)
	var race := scene.get_node_or_null("BoatRace") as BoatRace
	var racing := false
	if race != null and args.has("race-setup"):
		race.start()
		if str(args.get("race-mode", "team")) == "solo":
			race._use_mode("solo", int(args.get("race-boats", "6")))
		race._update_setup()
		race._update_camera(1.0)
	if race != null and (args.has("race") or args.has("race-result")):
		race._rng.seed = int(args.get("race-seed", "500"))
		race.begin(str(args.get("race-mode", "team")), int(args.get("race-boats", "4")), str(args.get("race-obstacles", "1")) != "0")
		race.set_process(false)
		var secs := 999.0 if args.has("race-result") else float(args.get("race", "0"))
		if secs > 0.0:
			race.phase = BoatRace.Phase.RACE
			var tt := 0.0
			while tt < secs and race.phase == BoatRace.Phase.RACE:
				var b0: Dictionary = race.boats[0]
				race.step(1.0 / 60.0, true, clampf((0.3 * (float(b0.lat) - race.ai_target_lat(b0, 0)) - float(b0.head)) * 3.0, -1.0, 1.0))
				if fmod(race._beat_t, race.beat_period) < 1.0 / 60.0:
					race.press_beat()
				tt += 1.0 / 60.0
		else:
			race._big.text = "3"
		for b in race.boats:
			race._place(b, race._clock)
		for o in race.obstacles:
			race._place_obstacle(o)
		race._update_camera(1.0)
		race._update_ui()
		racing = true

	# Thả diều: --kite=giây (cùng --fp): mượn diều đứa trẻ gần nhất, chơi khéo tới giây đó
	var kf := scene.get_node_or_null("KiteFlying") as KiteFlying
	if kf != null and args.has("kite") and fp != null and fp.active:
		var vsk := scene.get_node("World/Villagers") as Villagers
		var kk: Villager = null
		for v in vsk.people:
			if v.role in ["kid", "herder"] and not v.has_meta("in_class") and (kk == null or v.global_position.distance_to(fp.global_position) < kk.global_position.distance_to(fp.global_position)):
				kk = v
		if kk != null:
			kk.visible = true
			kf.start(kk)
			kf.set_process(false)
			var kt := 0.0
			while kt < float(args["kite"]) and kf.phase == KiteFlying.Phase.FLY:
				var pull := false
				var reel := 0.0
				if kf.tension > 0.85 or kf.strain > 0.2:
					reel = 1.0
				elif kf.el < 0.5:
					pull = true
				elif kf.tension < 0.55 and kf.el > 0.7:
					reel = 1.0
				kf.step(1.0 / 60.0, pull, reel, 0.0)
				kt += 1.0 / 60.0
			kf._kite_pos = kf._kite_target()
			for i in 30:
				kf._place_kite(1.0 / 30.0)
			kf._update_camera(1.0)
			kf._update_ui()
			kk.look_at(Vector3(kf._kite_pos.x, kk.global_position.y, kf._kite_pos.z), Vector3.UP, true)
			kf.set_process(true)

	# Đá bóng cùng dân làng: --fb-join=N (cùng --fp): N người ra sân, người chơi vào đội, đứng sau bóng
	# nhìn về khung thành đối phương; --fb-restart=throw|corner|free|penalty: chờ người chơi đá lại
	var fbj := scene.get_node_or_null("World/Football") as Football
	if fbj != null and args.has("fb-join") and fp != null and fp.active:
		fbj.debug_match(int(args["fb-join"]), 5.0)
		fbj.join_user()
		var fc := fbj.rect.get_center()
		var team := fbj.user_team
		var gx := fbj.rect.end.x if fbj._attack_dir(team) > 0.0 else fbj.rect.position.x
		if args.has("fb-restart"):
			var kind := str(args["fb-restart"])
			var rp := Vector3(fc.x + 3.0, 0, fbj.rect.position.y + 0.1)
			if kind == "corner":
				rp = Vector3(gx - signf(gx - fc.x) * 0.3, 0, fbj.rect.position.y + 0.3)
			elif kind == "free":
				rp = Vector3(lerpf(fc.x, gx, 0.45), 0, fc.y - 2.0)
			elif kind == "penalty":
				rp = Vector3(gx - signf(gx - fc.x) * 5.0, 0, fc.y)
			fbj.phase = Football.Phase.PLAY
			fbj._begin_restart(kind, team, rp, 0.0)
			if kind == "penalty":
				fbj._call("Phạt đền! Bạn sút")
			for i in 150:
				fbj._step(1.0 / 60.0)
		var bp := fbj.ball_position()
		var to := Vector3(gx, 0, fc.y) - bp
		if args.has("fb-restart") and str(args["fb-restart"]) == "throw":
			to = Vector3(fc.x, 0, fc.y) - bp
		to.y = 0.0
		fp.global_position = Vector3(bp.x, fp.global_position.y, bp.z) - to.normalized() * 1.1
		fp.rotation.y = atan2(-to.x, -to.z)
		fp._pitch = float(args.get("fp-pitch", "-12")) * PI / 180.0
		fp.camera.rotation.x = fp._pitch
		fbj._apply_visuals(0.0)
		fbj._update_overlay()

	# Nhảy dây: --rope=N bãi thứ N có 4 đứa đang chơi (camera nhìn vào bãi); --rope-play (cùng --fp): rủ đứa
	# trẻ gần nhất, tới lượt bạn, chụp lúc đang lơ lửng trên dây
	var jrs := scene.get_node_or_null("JumpRope") as JumpRope
	if jrs != null and args.has("rope") and not jrs.sites.is_empty():
		var site := jrs.sites[clampi(int(args["rope"]), 0, jrs.sites.size() - 1)]
		var vsr := scene.get_node("World/Villagers") as Villagers
		var n := 0
		for v in vsr.people:
			if v.role == "kid" and n < 4:
				v.visible = true
				v.state = Villager.State.IDLE
				v.global_position = site + Vector3(-1.0 + n * 0.7, 0, 2.4)
				v.activity = "jumprope"
				jrs.on_arrive(v)
				n += 1
		var gg: Dictionary = jrs.games[0]
		for i in 60 * 6:
			jrs.step(gg, 1.0 / 60.0)
		if rig != null:
			rig.set_focus(site)
			rig.global_position = site
	if jrs != null and args.has("rope-play") and fp != null and fp.active:
		var vsp := scene.get_node("World/Villagers") as Villagers
		var kid: Villager = null
		for v in vsp.people:
			if v.role == "kid" and (kid == null or v.global_position.distance_to(fp.global_position) < kid.global_position.distance_to(fp.global_position)):
				kid = v
		kid.visible = true
		kid.state = Villager.State.IDLE
		jrs.start_with(kid)
		jrs.set_process(false)
		var pg := jrs.player_game
		for i in 60 * 30:
			if pg.jumper is String and float(pg.wait) <= 0.0:
				break
			jrs.step(pg, 1.0 / 60.0)
		# nhảy đúng nhịp vài lần, dừng khi đang lơ lửng ngay lúc dây quét dưới chân
		var jumps := 0
		for i in 60 * 20:
			var tb := (TAU - fmod(float(pg.phi), TAU)) / (TAU * float(pg.rev))
			if float(pg.air) < 0.0 and tb <= 0.16 and tb > 0.14:
				jrs.player_jump()
				jumps += 1
			jrs.step(pg, 1.0 / 60.0)
			if jumps >= int(args.get("rope-play", "8")) and float(pg.air) > 0.14:
				break
		jrs._update_camera(pg, 1.0)
		jrs._update_ui(pg)
		jrs.set_process(true)
		jrs.process_mode = Node.PROCESS_MODE_DISABLED   # giữ nguyên khoảnh khắc cho khung chụp

	# Đánh khăng: --khang=N bãi thứ N có 4 đứa đang chơi (chụp lúc khăng đang bay); --khang-play[=phase] (cùng --fp):
	# rủ đứa trẻ gần nhất, tới lượt bạn, dừng ở giai đoạn `phase` (flick_ready | hop | throw_flight)
	var tcs := scene.get_node_or_null("TipCat") as TipCat
	if tcs != null and args.has("khang") and not tcs.sites.is_empty():
		var si := clampi(int(args["khang"]), 0, tcs.sites.size() - 1)
		var vsk2 := scene.get_node("World/Villagers") as Villagers
		var nk := 0
		for v in vsk2.people:
			if v.role == "kid" and nk < 4:
				v.visible = true
				v.state = Villager.State.IDLE
				v.global_position = tcs.sites[si] + Vector3(-1.5 + nk, 0, -1.5)
				v.activity = "khang"
				tcs.on_arrive(v)
				nk += 1
		var kg: Dictionary = tcs.games[0]
		for i in 60 * 30:
			tcs.step(kg, 1.0 / 60.0)
			if i > 60 * 4 and String(kg.phase) in ["flick_flight", "strike_flight"] and float((kg.pos as Vector3).y) > 1.5:
				break
		tcs.process_mode = Node.PROCESS_MODE_DISABLED
		if rig != null:
			var mid := tcs.sites[si] + tcs.site_dirs[si] * 6.0
			rig.set_focus(mid)
			rig.global_position = mid
	if tcs != null and args.has("khang-play") and fp != null and fp.active:
		var vsk3 := scene.get_node("World/Villagers") as Villagers
		var kd: Villager = null
		for v in vsk3.people:
			if v.role == "kid" and (kd == null or v.global_position.distance_to(fp.global_position) < kd.global_position.distance_to(fp.global_position)):
				kd = v
		kd.visible = true
		kd.state = Villager.State.IDLE
		tcs.start_with(kd)
		tcs.set_process(false)
		var pgk := tcs.player_game
		var want := str(args["khang-play"]) if str(args["khang-play"]) != "true" else "hop"
		for i in 60 * 40:
			var ph := String(pgk.phase)
			if pgk.striker is String:
				if ph == want and (want != "hop" or float(pgk.hop_t) > 0.38):
					break
				if ph == "flick_ready" and want != "flick_ready":
					pgk.aim = 0.15
					tcs._flick(pgk, 0.75)
				elif ph == "strike_ready":
					tcs.player_press()
				elif ph == "throw_flight" and want != "throw_flight":
					pass
				elif ph == "flick_ready":
					tcs._charge = 0.6
					tcs._charging = true
					if i > 30:
						break
			tcs.step(pgk, 1.0 / 60.0)
		tcs._update_camera(pgk, 1.0)
		tcs._update_ui(pgk, 0.0)
		tcs.process_mode = Node.PROCESS_MODE_DISABLED

	# Mùa vụ: --crop-day=N đặt ngày N (0…90) trong vụ lúa (mục 33)
	var fmc := scene.get_node_or_null("Farming") as Farming
	if fmc != null and args.has("crop-day"):
		fmc.set_cycle_day(float(args["crop-day"]))
		var vsc := scene.get_node_or_null("World/Villagers") as Villagers
		if vsc != null and args.has("hour"):
			vsc.replan()

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
		if racing and race.phase == BoatRace.Phase.RACE:
			race.step(1.0 / 60.0, true, 0.0)
			for b in race.boats:
				race._place(b, race._clock)
			for o in race.obstacles:
				race._place_obstacle(o)
			race._update_camera(1.0 / 60.0)
			race._update_ui()
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
