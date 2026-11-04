extends SceneTree
## Chạy thử đò không giao diện: nhập vai nhìn đò → E lên đò, chèo tới / rẽ (đò không lên bờ),
## lên bờ giữa sông (phải từ chối), lên bờ sát bờ (về nhập vai), lên đò từ camera ngắm cảnh
## rồi lên bờ ở bến. Dùng: godot --headless --path . -s tools/boat_test.gd
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

## Khoảng cách từ đò tới mép nước (âm = đã lên bờ).
func _margin(r: River, b: Node3D) -> float:
	var p := Vector2(b.global_position.x, b.global_position.z)
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
	print("Số đò: %d" % r.boat_nodes.size())
	# 1) Nhập vai, đứng trên đê cạnh đò 0, nhìn vào đò → E
	var b0 := r.boat_nodes[0]
	var p := Vector2(b0.global_position.x, b0.global_position.z)
	var smp := r.sample(r.nearest_s(p))
	var n: Vector2 = (smp[1] as Vector2).orthogonal()
	var side := signf((p - (smp[0] as Vector2)).dot(n))
	var stand := p + n * side * 2.6
	rig.global_position = Vector3(stand.x, 0, stand.y)
	fp.enter()
	fp.global_position = Vector3(stand.x, r.bank_height(_margin(r, b0) - 2.6 + 0.0) + 0.3, stand.y)
	await _frames(20)
	_face(fp, b0.global_position + Vector3(0, 0.5, 0))
	await _frames(3)
	print("1) gợi ý khi nhìn đò: '%s'" % hud._hint_label.text)
	fp._act()
	await _frames(3)
	print("   trên đò: %s, camera đò: %s, nhập vai tạm dừng: %s, chỗ HUD: %s" % [br.active, br._cam.current, fp._suspended, hud._boat])
	# 2) Chèo tới 20 s, rồi vừa chèo vừa rẽ hết cỡ 25 s
	var res := _drive(br, r, 20.0, 1.0, 0.0)
	print("2) chèo tới 20 s: đi %.1f m, gần mép nước nhất %.2f m" % [res[0], res[1]])
	res = _drive(br, r, 25.0, 1.0, 1.0)
	print("   chèo + rẽ phải 25 s: đi %.1f m, gần mép nhất %.2f m" % [res[0], res[1]])
	res = _drive(br, r, 15.0, -1.0, -1.0)
	print("   lùi + rẽ trái 15 s: đi %.1f m, gần mép nhất %.2f m, y đò %.2f" % [res[0], res[1], br.boat.global_position.y])
	# 2b) Chèo ra quá đầu sông: phải dừng ở điểm cuối
	var e: Array = r.sample(r.length - 5.0)
	var ep: Vector2 = e[0]
	br.boat.global_position = Vector3(ep.x, br.boat.global_position.y, ep.y)
	br._yaw = atan2((e[1] as Vector2).x, (e[1] as Vector2).y)
	_drive(br, r, 20.0, 1.0, 0.0)
	var bp := Vector2(br.boat.global_position.x, br.boat.global_position.z)
	var end: Array = r.sample(r.length)
	print("   chèo ra đầu sông: vượt điểm cuối %.1f m (≤ 0 là đúng), cách mép %.2f m" % [(bp - (end[0] as Vector2)).dot(end[1] as Vector2), _margin(r, br.boat)])
	# 3) Đặt đò giữa sông → lên bờ phải bị từ chối
	var s := r.length * 0.5
	var c: Vector2 = r.sample(s)[0]
	br.boat.global_position = Vector3(c.x, br.boat.global_position.y, c.y)
	var ok := br.disembark()
	print("3) lên bờ giữa sông: %s, gợi ý '%s'" % [ok, hud._hint_label.text])
	# 4) Chèo ngang vào bờ rồi lên
	smp = r.sample(s)
	var t: Vector2 = smp[1]
	br._yaw = atan2(-t.y, t.x)        # mũi vuông góc với dòng (về phía n)
	res = _drive(br, r, 12.0, 1.0, 0.0)
	print("4) chèo vào bờ: gần mép %.2f m" % _margin(r, br.boat))
	var parked := br.boat.global_position
	ok = br.disembark()
	await _frames(30)
	print("   lên bờ: %s, nhập vai tiếp: %s, camera nhập vai: %s, y người %.2f, trên bờ cách mép %.2f m" % [
			ok, fp._suspended == "" and fp.active, fp.camera.current, fp.global_position.y,
			-_margin(r, fp)])
	print("   đò neo lại: %s, sào hiện lại: %s" % [br.boat.global_position.distance_to(parked) < 0.3, (br.boat.get_node("Pole") as Node3D).visible])
	# 5) Thôi nhập vai, lên đò 1 bằng vùng bấm (camera ngắm cảnh), chèo về bến gần nhất rồi lên bờ
	fp.exit()
	await _frames(3)
	var target := r.boat_nodes[1].get_node("ClickTarget") as StaticBody3D
	(target.get_meta("activate") as Callable).call()
	await _frames(3)
	print("5) lên đò 1 từ ngắm cảnh: %s, khoá cửa: %s, rig tắt: %s" % [br.active, he.locked, not rig.active])
	var land: Dictionary = r.landings[0]
	var spot: Vector3 = land.spot
	br.boat.global_position = Vector3(spot.x, br.boat.global_position.y, spot.z) - Basis(Vector3.UP, float(land.face)) * Vector3(0, 0, -2.5)
	br.step(0.016, 0.0, 0.0, false)
	ok = br.disembark()
	await _frames(3)
	print("   lên bến: %s, rig bật: %s, camera rig: %s, khoá cửa: %s, tâm rig cách bến %.1f m" % [
			ok, rig.active, rig.camera.current, he.locked, Vector2(rig._target_focus.x - spot.x, rig._target_focus.z - spot.z).length()])
	quit()
