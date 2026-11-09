extends SceneTree
## Thử cầu thang nhà 2 tầng (headless, nhập vai đi bộ bên trong):
## mỗi nhà 2 tầng: đứng chân cầu thang → đi lên (tới sàn gác?) → đi tiếp vào chiếu nghỉ → sang gian bên
## (vẫn trên gác?) → đi về phía lỗ cầu thang từ bên hông (lan can chặn, không rơi?) → ra ban công →
## quay lại đi xuống (về tới nền nhà?). Cuối: ban đêm người nhà lên gác ngủ (IndoorFolk).
## Dùng: godot --headless --path . -s tools/stairs_test.gd [-- --only=house_0]
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## Đi theo hướng `dir` (cục bộ nội thất, mặt phẳng) trong `frames` khung; trả về [y thấp nhất, y cao nhất, chỗ cuối].
func _walk(fp: FirstPerson, it: Interior, dir: Vector3, frames: int) -> Array:
	var g := it.global_transform.basis * dir
	fp.rotation.y = atan2(-g.x, -g.z)
	fp._pitch = 0.0
	fp.camera.rotation.x = 0.0
	Input.action_press("cam_forward")
	var lo := INF
	var hi := -INF
	for i in frames:
		await physics_frame
		var y := it.to_local(fp.global_position).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	Input.action_release("cam_forward")
	await _frames(4)
	return [lo, hi, it.to_local(fp.global_position)]

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
	await _frames(5)
	var vg := scene.get_node("World/Village") as Village
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var he := scene.get_node("HouseEntry") as HouseEntry
	var it := he.interior
	var keys: Array[String] = []
	for h in vg.homes:
		if str(h.name).contains("2 tầng") and (only.is_empty() or str(h.key) in only):
			keys.append(str(h.key))
	print("Nhà 2 tầng: %d (%s)" % [keys.size(), ", ".join(keys)])
	var ok := 0
	for key in keys:
		var door := he.find_entry(key)
		if not fp.active:
			fp.enter()
		fp._outside_spot = door.global_position + Vector3(0, 0, 2)
		fp._outside_yaw = 0.0
		he.walk_inside = true
		fp._suspend("house")
		he.locked = false
		he.enter_house(false, door)
		for i in 240:
			if he.inside and fp._inside_walk:
				break
			await physics_frame
		await _frames(10)
		var up_y := it.upper_y()
		var p0 := it._p
		var st: Dictionary = it.stair
		fp.global_position = it.to_global(Vector3(float(st.x), p0 + 0.05, float(st.z_bottom) + 0.5))
		fp.velocity = Vector3.ZERO
		await _frames(5)
		var climb := await _walk(fp, it, Vector3(0, 0, -1), 150)
		var top_ok: bool = absf((climb[2] as Vector3).y - up_y) < 0.15
		var side := await _walk(fp, it, Vector3(1, 0, 0), 80)
		var stay_up: bool = (side[0] as float) > up_y - 0.15
		# Từ gian bên đi về phía lỗ cầu thang (giữa thân thang) — lan can phải chặn
		var mid_z := (float(st.z_top) + float(st.z_bottom)) * 0.5
		fp.global_position = it.to_global(Vector3(float(st.hole_x1) + 1.0, up_y + 0.05, mid_z))
		fp.velocity = Vector3.ZERO
		await _frames(4)
		var push := await _walk(fp, it, Vector3(-1, 0, 0), 80)
		var railed: bool = (push[0] as float) > up_y - 0.15
		# Ra ban công (gian giữa, đi ra phía trước)
		var bal := "—"
		if it._ver > 0.0:
			fp.global_position = it.to_global(Vector3(it._gx(it._bays >> 1), up_y + 0.05, it._front_z - 1.0))
			fp.velocity = Vector3.ZERO
			await _frames(4)
			var out := await _walk(fp, it, Vector3(0, 0, 1), 120)
			var lp: Vector3 = out[2]
			bal = "ra được %s, không rơi %s" % [lp.z > it._front_z + 0.2, (out[0] as float) > up_y - 0.15]
		# Đi xuống: từ chiếu nghỉ quay ra phía trước đi thẳng xuống thang
		fp.global_position = it.to_global(Vector3(float(st.x), up_y + 0.05, float(st.z_top) - 0.4))
		fp.velocity = Vector3.ZERO
		await _frames(4)
		var down := await _walk(fp, it, Vector3(0, 0, 1), 150)
		var bottom_ok: bool = absf((down[2] as Vector3).y - p0) < 0.15
		var good := top_ok and stay_up and railed and bottom_ok and not bal.contains("false")
		ok += int(good)
		print("%-9s lên gác %s (y %.2f / sàn gác %.2f) · đi sang gian bên vẫn trên gác %s · lan can lỗ thang chặn %s · ban công %s · xuống tới nền %s" % [
				key, top_ok, (climb[2] as Vector3).y, up_y, stay_up, railed, bal, bottom_ok])
		he.exit_house(true)
		await _frames(20)
	print("TỔNG: %d / %d nhà 2 tầng ổn" % [ok, keys.size()])
	# Ban đêm: người nhà lên gác ngủ
	if not keys.is_empty():
		var dn := scene.get_node("DayNight") as DayNight
		dn.time_of_day = 22.5
		var vs := scene.get_node("World/Villagers") as Villagers
		vs.replan()
		await _frames(30)
		var folk := scene.get_node("IndoorFolk") as IndoorFolk
		fp.enter() if not fp.active else null
		he.walk_inside = true
		fp._suspend("house")
		he.enter_house(false, he.find_entry(keys[0]))
		for i in 240:
			if he.inside:
				break
			await physics_frame
		await _frames(60)
		var lines: Array[String] = []
		for f in folk._folk:
			var p: Villager = f.proxy
			var seat: Dictionary = it.seats[int(f.seat)]
			lines.append("%s (%s%s)" % [p.display_name, seat.pose, ", trên gác" if (seat.tags as Array).has("upstairs") else ""])
		print("Đêm 22:30 ở %s: %s" % [keys[0], "; ".join(lines)])
	quit()
