extends SceneTree
## Chạy thử đò không giao diện: đi bộ từ đê qua ván lên đò, vào trong mui, nhìn mái chèo →
## "E: Cầm chèo", chèo tới / rẽ / lùi (đò không lên bờ), chèo ra đầu sông, thôi chèo giữa sông
## (đứng lại trên đò, cất ván), lội xuống nước rồi trèo lên lại bằng bậc mạn, nhìn đò từ bờ
## "E: Lên đò", lên đò từ camera ngắm cảnh. Dùng: godot --headless --path . -s tools/boat_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _face(fp: FirstPerson, target: Vector3) -> void:
	var d := target - fp.camera.global_position
	fp.rotation.y = atan2(-d.x, -d.z)
	fp._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	fp.camera.rotation.x = fp._pitch

## Khoảng cách từ một điểm tới mép nước (âm = đã ở trên bờ).
func _margin(r: River, n3: Node3D) -> float:
	var p := Vector2(n3.global_position.x, n3.global_position.z)
	var s := r.nearest_s(p)
	var smp := r.sample(s)
	var n: Vector2 = (smp[1] as Vector2).orthogonal()
	return r.half_width(s) - absf((p - (smp[0] as Vector2)).dot(n))

## Chèo `seconds` giây với tay chèo cố định, trả về [quãng đường, mép nước gần nhất].
func _drive(br: BoatRide, r: River, seconds: float, throttle: float, steer: float) -> Array:
	var start := br.boat.global_position
	var worst := INF
	var dt := 1.0 / 60.0
	for i in int(seconds / dt):
		br.step(dt, throttle, steer, false)
		worst = minf(worst, _margin(r, br.boat))
	return [start.distance_to(br.boat.global_position), worst]

## Đi thẳng theo hướng đang nhìn `seconds` giây.
func _walk(fp: FirstPerson, seconds: float) -> void:
	Input.action_press("cam_forward")
	await _frames(int(seconds * 60.0))
	Input.action_release("cam_forward")
	await _frames(5)

## Toạ độ của người chơi trong hệ của đò.
func _local(fp: FirstPerson, b: Node3D) -> Vector3:
	return b.to_local(fp.global_position)

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(3)
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var he := scene.get_node("HouseEntry") as HouseEntry
	var rig := scene.get_node("CameraRig") as CameraRig
	var br := scene.get_node("BoatRide") as BoatRide
	var r := scene.get_node("World/River") as River
	var hud := scene.get_node("HUD") as Hud
	var b := r.boat_nodes[1]
	var plank := b.get_node_or_null("Plank") as Node3D
	print("Số đò: %d, đò 1 có ván: %s" % [r.boat_nodes.size(), plank != null])
	# 1) Đứng trên đê ở đầu ván, đi thẳng qua ván lên đò
	var plank_end := plank.to_global(Vector3((plank.get_child(0) as MeshInstance3D).mesh.get_aabb().size.x * 0.5 + 0.6, 0, 0))
	var plank_start := plank.to_global(Vector3(-(plank.get_child(0) as MeshInstance3D).mesh.get_aabb().size.x * 0.5, 0, 0))
	rig.global_position = Vector3(plank_end.x, 0, plank_end.z)
	fp.enter()
	fp.global_position = plank_end + Vector3(0, 0.2, 0)
	await _frames(20)
	_face(fp, plank_start + Vector3(0, 1.6, 0))
	fp._pitch = 0.0
	fp.camera.rotation.x = 0.0
	await _walk(fp, 2.2)
	var lp := _local(fp, b)
	print("1) đi qua ván: chỗ đứng trong đò (%.2f, %.2f, %.2f), trên sàn: %s" % [lp.x, lp.y, lp.z, absf(lp.x) < 1.0 and absf(lp.y - River.BOAT_DECK) < 0.12])
	# 2) Vào trong mui: ra giữa sàn, quay về mũi, đi tới (đi tiếp qua mui ra mũi thì rơi xuống sông)
	fp.global_position = b.to_global(Vector3(0, River.BOAT_DECK + 0.05, River.BOAT_GAP_Z))
	await _frames(3)
	fp.rotation.y = b.rotation.y + PI
	await _walk(fp, 1.3)
	lp = _local(fp, b)
	print("2) đi vào mui: z=%.2f (mui %.1f…%.1f), x=%.2f, y=%.2f — trong mui: %s" % [lp.z, River.BOAT_CABIN.x, River.BOAT_CABIN.y, lp.x, lp.y,
			lp.z > River.BOAT_CABIN.x and lp.z < River.BOAT_CABIN.y and absf(lp.y - River.BOAT_DECK) < 0.12])
	# 3) Ra đuôi, nhìn mái chèo → E
	fp.global_position = b.to_global(Vector3(0, River.BOAT_DECK + 0.05, -2.2))
	await _frames(5)
	_face(fp, (b.get_node("OarTarget") as Node3D).global_position)
	await _frames(3)
	print("3) gợi ý khi nhìn cọc chèo: '%s'" % hud._hint_label.text)
	fp._act()
	await _frames(3)
	print("   đang chèo: %s, camera đò: %s, nhập vai tạm dừng: %s, ván đã cất: %s" % [br.active, br._cam.current, fp._suspended, b.get_node_or_null("Plank") == null])
	# 4) Chèo
	var res := _drive(br, r, 20.0, 1.0, 0.0)
	print("4) chèo tới 20 s: đi %.1f m, gần mép nước nhất %.2f m" % [res[0], res[1]])
	res = _drive(br, r, 25.0, 1.0, 1.0)
	print("   chèo + rẽ phải 25 s: đi %.1f m, gần mép nhất %.2f m" % [res[0], res[1]])
	res = _drive(br, r, 15.0, -1.0, -1.0)
	print("   lùi + rẽ trái 15 s: đi %.1f m, gần mép nhất %.2f m" % [res[0], res[1]])
	# 5) Thôi chèo ở giữa sông: đứng lại ở đuôi đò, không có ván
	var s := r.length * 0.5
	var smp := r.sample(s)
	var c: Vector2 = smp[0]
	var t: Vector2 = smp[1]
	br.boat.global_position = Vector3(c.x, br.boat.global_position.y, c.y)
	br._yaw = atan2(t.x, t.y)
	br.step(0.016, 0.0, 0.0, false)
	br.disembark()
	await _frames(20)
	lp = _local(fp, b)
	print("5) thôi chèo giữa sông: nhập vai tiếp %s, camera nhập vai %s, đứng trên đò (z=%.2f, y=%.2f), ván: %s" % [
			fp._suspended == "" and fp.active, fp.camera.current, lp.z, lp.y, b.get_node_or_null("Plank") != null])
	# 6) Lội xuống nước từ khe mạn, rồi trèo lên lại bằng bậc
	fp.global_position = b.to_global(Vector3(2.6, 0.0, River.BOAT_GAP_Z))
	await _frames(30)
	var in_water := fp.global_position.y
	_face(fp, b.to_global(Vector3(0, River.BOAT_DECK + 1.6, River.BOAT_GAP_Z)))
	fp._pitch = 0.0
	fp.camera.rotation.x = 0.0
	await _walk(fp, 0.9)
	lp = _local(fp, b)
	print("6) đứng dưới nước y=%.2f → trèo bậc mạn: (%.2f, %.2f, %.2f), lên sàn: %s" % [in_water, lp.x, lp.y, lp.z, absf(lp.y - River.BOAT_DECK) < 0.12 and absf(lp.x) < 1.1])
	# 7) Chèo vào sát bờ, thôi chèo → ván tự bắc
	_face(fp, (b.get_node("OarTarget") as Node3D).global_position)
	fp.global_position = b.to_global(Vector3(0, River.BOAT_DECK + 0.05, -2.2))
	await _frames(3)
	_face(fp, (b.get_node("OarTarget") as Node3D).global_position)
	await _frames(3)
	fp._act()
	await _frames(2)
	br._yaw = atan2(-t.y, t.x)
	_drive(br, r, 10.0, 1.0, 0.0)
	br._yaw = atan2(t.x, t.y)
	br.step(0.016, 0.0, 0.0, false)
	br.disembark()
	await _frames(10)
	print("7) thôi chèo sát bờ (mép %.2f m): có ván %s" % [_margin(r, b), b.get_node_or_null("Plank") != null])
	# 8) Từ bờ nhìn đò → "E: Lên đò" → bước lên
	fp.exit()
	await _frames(3)
	var b0 := r.boat_nodes[0]
	var p0 := Vector2(b0.global_position.x, b0.global_position.z)
	var sm0 := r.sample(r.nearest_s(p0))
	var n0: Vector2 = (sm0[1] as Vector2).orthogonal()
	var side := signf((p0 - (sm0[0] as Vector2)).dot(n0))
	var hw0 := r.half_width(r.nearest_s(p0))
	var stand := (sm0[0] as Vector2) + n0 * side * (hw0 + 2.5)
	rig.global_position = Vector3(stand.x, 0, stand.y)
	fp.enter()
	fp.global_position = Vector3(stand.x, r.bank_height(2.5) + 0.3, stand.y)
	await _frames(20)
	_face(fp, b0.global_position + Vector3(0, 1.0, 0))
	await _frames(3)
	print("8) gợi ý khi nhìn đò từ bờ: '%s'" % hud._hint_label.text)
	fp._act()
	await _frames(20)
	lp = _local(fp, b0)
	print("   bước lên đò: (%.2f, %.2f, %.2f), nhập vai vẫn đi lại: %s" % [lp.x, lp.y, lp.z, fp._suspended == "" and fp.active])
	# 9) Ngắm cảnh: bấm đò 2 → chèo luôn; thôi chèo → camera ngắm cảnh nhìn vào đò
	fp.exit()
	await _frames(3)
	var target := r.boat_nodes[2].get_node("ClickTarget") as StaticBody3D
	(target.get_meta("activate") as Callable).call()
	await _frames(3)
	print("9) bấm đò từ ngắm cảnh: chèo %s, khoá cửa %s, rig tắt %s" % [br.active, he.locked, not rig.active])
	_drive(br, r, 5.0, 1.0, 0.0)
	br.disembark()
	await _frames(3)
	var bp := r.boat_nodes[2].global_position
	print("   thôi chèo: rig bật %s, camera rig %s, khoá cửa %s, tâm rig cách đò %.1f m" % [
			rig.active, rig.camera.current, he.locked, Vector2(rig._target_focus.x - bp.x, rig._target_focus.z - bp.z).length()])
	quit()
