extends SceneTree
## Kiểm tra đi bộ bên trong MỌI toà nhà (nhập vai): nhà mình, 60 nhà làng, đình, chùa, lớp học.
## Mỗi toà: đứng trước cửa nhìn cửa → E → vào; đứng vững trên nền, không kẹt trong tường; đi sâu
## vào trong, sang trái, sang phải (đo quãng đi được, có xuyên tường lọt ra ngoài / rơi khỏi nền
## không); quay ra cửa đi thẳng → về sân. In một dòng cho mỗi toà và tổng kết cuối.
## Dùng: godot --headless --path . -s tools/building_walk_test.gd [-- --only=house_3,dinh]
const SPEED := 2.5     # tua nhanh thời gian cho đỡ lâu (bước vật lý vẫn nhỏ, không xuyên tường)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## Chờ tới khi điều kiện đúng (tối đa `limit` khung). Trả về true nếu đúng.
func _until(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await physics_frame
	return bool(cond.call())

func _face(fp: FirstPerson, target: Vector3) -> void:
	var d := target - fp.camera.global_position
	fp.rotation.y = atan2(-d.x, -d.z)
	fp._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	fp.camera.rotation.x = fp._pitch

## Đi theo hướng yaw (thế giới) trong `frames` khung, theo dõi chỗ đứng (cục bộ của nội thất).
func _walk(fp: FirstPerson, it: Interior, he: HouseEntry, yaw: float, frames: int, track: Dictionary) -> void:
	fp.rotation.y = yaw
	fp._pitch = 0.0
	fp.camera.rotation.x = 0.0
	Input.action_press("cam_forward")
	var last := fp.global_position
	for i in frames:
		await physics_frame
		if not he.inside or not fp._inside_walk:
			track.left_early = true
			break
		var lp := it.to_local(fp.global_position)
		track.min_y = minf(track.min_y, lp.y)
		track.max_x = maxf(track.max_x, absf(lp.x))
		track.min_z = minf(track.min_z, lp.z)
		track.dist += Vector2(fp.global_position.x - last.x, fp.global_position.z - last.z).length()
		last = fp.global_position
	Input.action_release("cam_forward")
	await _frames(3)

func _run() -> void:
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	(scene.get_node("DayNight") as DayNight).time_of_day = 10.0
	await _frames(3)
	Engine.time_scale = SPEED
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var he := scene.get_node("HouseEntry") as HouseEntry
	var rig := scene.get_node("CameraRig") as CameraRig
	var hud := scene.get_node("HUD") as Hud
	var it := he.interior
	var keys: Array[String] = ["main", "dinh", "pagoda", "school"]
	for i in 41:
		keys.append("house_%d" % i)
	var problems: Array[String] = []
	var ok_count := 0
	for key in keys:
		if not only.is_empty() and not key in only:
			continue
		var door := he.find_entry(key)
		if door == null:
			problems.append("%s: không tìm thấy cửa" % key)
			print("%-9s  KHÔNG CÓ CỬA" % key)
			continue
		var out := door.global_basis.z
		out.y = 0.0
		out = out.normalized()
		# 1) Đứng ngoài sân trước cửa (dò mặt đất từ ngang tầm người — từ trên cao thì trúng mái hiên),
		#    rồi đi thẳng tới cửa cho tới khi nhìn trúng cửa (gợi ý "E: vào")
		var space := fp.get_world_3d().direct_space_state
		var approach := door.global_position + out * 4.0
		for dd: float in [3.0, 4.0, 5.0, 6.0, 2.0]:
			var q: Vector3 = door.global_position + out * dd
			var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, door.global_position.y + 0.6, q.z), Vector3(q.x, -1.0, q.z), 1 << (FirstPerson.SOLID_LAYER - 1))
			var hit := space.intersect_ray(ray)
			var gy := float(hit.position.y) if not hit.is_empty() else 0.0
			if not fp.test_move(Transform3D(Basis(), Vector3(q.x, gy + 0.05, q.z)), Vector3(0, 0.1, 0)):
				approach = Vector3(q.x, gy + 0.05, q.z)
				break
		rig.global_position = Vector3(approach.x, 0, approach.z)
		if not fp.active:
			fp.enter()
		fp.global_position = approach
		fp.velocity = Vector3.ZERO
		await _frames(8)
		Input.action_press("cam_forward")
		for k in 150:
			_face(fp, door.global_position)
			await physics_frame
			if fp._look_target == door:
				break
		Input.action_release("cam_forward")
		await _frames(3)
		_face(fp, door.global_position)
		await _frames(3)
		var hint := hud._hint_label.text if hud._hint_panel.visible else ""
		var looked := fp._look_target == door
		if looked:
			fp._act()
		else:
			# Không nhìn trúng cửa từ chỗ đứng (bị vật gì chắn) — vẫn vào để thử bên trong
			fp._outside_spot = fp.global_position
			fp._outside_yaw = fp.rotation.y
			he.walk_inside = true
			fp._suspend("house")
			he.locked = false
			he.enter_house(false, door)
		var entered := await _until(func() -> bool: return he.inside and fp._inside_walk and fp.camera.current, 240)
		if not entered:
			problems.append("%s: không vào được (inside=%s, walk=%s)" % [key, he.inside, fp._inside_walk])
			print("%-9s  KHÔNG VÀO ĐƯỢC" % key)
			he.exit_house(true)
			await _frames(30)
			continue
		await _frames(20)
		# 2) Đứng vững: trên nền, không kẹt
		var lp0 := it.to_local(fp.global_position)
		var floor_y := lp0.y
		var on_floor := fp.is_on_floor()
		var stuck := 0
		for d: Vector3 in [Vector3(0.15, 0, 0), Vector3(-0.15, 0, 0), Vector3(0, 0, 0.15), Vector3(0, 0, -0.15)]:
			if fp.test_move(fp.global_transform, fp.global_basis * d):
				stuck += 1
		# 3) Đi khắp: vào sâu, sang trái, sang phải (tính theo hướng nhà)
		var track := {"min_y": lp0.y, "max_x": absf(lp0.x), "min_z": lp0.z, "dist": 0.0, "left_early": false}
		var base := it.global_rotation.y
		await _walk(fp, it, he, base, 70, track)                 # vào trong (−z cục bộ)
		await _walk(fp, it, he, base + PI * 0.5, 70, track)      # sang trái
		await _walk(fp, it, he, base - PI * 0.5, 130, track)     # sang phải
		await _walk(fp, it, he, base, 50, track)                 # vào sâu thêm
		var leaked := bool(track.left_early)
		var fell := float(track.min_y) < floor_y - 0.3
		var depth := lp0.z - float(track.min_z)
		# 4) Ra: về chỗ ngay sau cửa, quay ra, đi thẳng
		var exited := false
		var back_dist := INF
		if not leaked:
			fp.global_position = it.to_global(it.entry_point)
			fp.velocity = Vector3.ZERO
			await _frames(2)
			fp.rotation.y = base + PI
			Input.action_press("cam_forward")
			exited = await _until(func() -> bool: return not he.inside, 200)
			Input.action_release("cam_forward")
			await _until(func() -> bool: return fp._suspended == "" and not fp._inside_walk, 200)
			await _frames(5)
			exited = exited and not he.inside and fp.camera.current
			back_dist = Vector2(fp.global_position.x - approach.x, fp.global_position.z - approach.z).length()
		else:
			await _until(func() -> bool: return not he.inside and fp._suspended == "", 200)
		var line := "%-9s  E:%s  vào:✓  nền:%s  kẹt:%d/4  đi được %.1f m (sâu %.1f/%.1f m, ngang ±%.1f/%.1f m)  xuyên tường:%s  rơi:%s  ra:%s (cách chỗ đứng %.1f m)" % [
				key, "✓" if looked else "✗ (%s)" % hint, "✓" if on_floor else "✗", stuck, track.dist, depth, it.size.y,
				track.max_x, it.size.x * 0.5, "CÓ" if leaked else "không", "CÓ" if fell else "không",
				"✓" if exited else "✗", back_dist]
		print(line)
		var bad: Array[String] = []
		if not looked: bad.append("không nhìn trúng cửa từ ngoài (gợi ý '%s')" % hint)
		if not on_floor: bad.append("không đứng trên nền")
		if stuck >= 3: bad.append("kẹt ở chỗ vào")
		if float(track.dist) < 2.0: bad.append("gần như không đi được (%.1f m)" % track.dist)
		if leaked: bad.append("xuyên tường lọt ra ngoài")
		if fell: bad.append("rơi xuống dưới nền")
		if not exited: bad.append("đi ra cửa không về sân")
		if bad.is_empty():
			ok_count += 1
		else:
			problems.append("%s: %s" % [key, ", ".join(bad)])
	Engine.time_scale = 1.0
	print("\nTỔNG: %d toà ổn, %d toà có vấn đề" % [ok_count, problems.size()])
	for p in problems:
		print("  - " + p)
	quit()
