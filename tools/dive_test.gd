extends SceneTree
## Thử lặn mò ốc / trai (mục 57), headless: ốc trai nằm dưới đáy sông quanh các bến; trên bờ / đang bơi nổi thì không
## nhặt được; giữ phím lặn: mắt xuống sát đáy, bơi chậm, hơi cạn dần, hết hơi tự ngoi lên và phải thả phím; lặn tới
## gần thì nhặt được, vào túi đồ; nhặt rồi mọc lại sau; nấu ốc luộc.
## Dùng: timeout 110 godot --headless --path . -s tools/dive_test.gd

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(name_s: String, ok: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["OK" if ok else "SAI", name_s, ("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(name_s)


func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var river := scene.get_node("World/River") as River
	var dive := scene.get_node("RiverDive") as RiverDive
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	var inv := scene.get_node("Inventory") as Inventory
	inv.reset()
	await _frames(3)
	var in_water := 0
	var kinds := {"oc": 0, "trai": 0}
	for sh in dive.shells:
		var p: Vector3 = sh.pos
		if river.is_water(Vector2(p.x, p.z), 1.5) and absf(p.y - river.bed_level) < 0.05:
			in_water += 1
		kinds[str(sh.id)] = int(kinds[str(sh.id)]) + 1
	_check("ốc trai nằm dưới đáy sông quanh 3 bến", dive.shells.size() == 3 * dive.shells_per_landing and in_water == dive.shells.size()
			and int(kinds.oc) > 0 and int(kinds.trai) > 0, "%d con (%s)" % [dive.shells.size(), kinds])
	var target: Dictionary = dive.shells[0]
	var tp: Vector3 = target.pos
	rig.set_focus(Vector3(tp.x, 0, tp.z))
	rig.snap()
	fp.enter()
	fp.global_position = Vector3(tp.x + 0.6, river.water_level, tp.z)
	fp.velocity = Vector3.ZERO
	await _frames(60)
	_check("đang bơi nổi: mắt trên mặt nước, không nhặt được", fp.swimming and not fp.diving and fp.camera.global_position.y > river.water_level
			and not dive.pick(dive.nearest_shell(fp.global_position)) and inv.count(str(target.id)) == 0)
	Input.action_press("fp_dive")
	await _frames(50)
	await process_frame
	var eye := fp.camera.global_position.y
	_check("giữ C: lặn, mắt sát đáy dưới mặt nước, màn nước xanh, hơi cạn dần", fp.diving and eye < river.water_level - 0.08 and eye > river.bed_level
			and dive._tint.visible and fp.breath < 0.97, "mắt cao %.2f m (đáy %.2f, mặt nước %.2f) · hơi %.0f %%" % [eye, river.bed_level, river.water_level, fp.breath * 100.0])
	_check("gần con %s: có gợi ý nhặt" % str(target.id), dive._near >= 0 and dive._label.text.begins_with("E: Nhặt"), dive._label.text)
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check("E: nhặt vào túi đồ, con đó biến mất", inv.count(str(target.id)) == 1 and not (target.node as MeshInstance3D).visible and int(dive.stats.picked) == 1)
	# Bơi dưới nước
	Input.action_press("cam_forward")
	await _frames(40)
	var a := fp.global_position
	await _frames(120)
	var sp := a.distance_to(fp.global_position) / 2.0
	Input.action_release("cam_forward")
	_check("lặn bơi chậm hơn bơi nổi", sp > 0.6 and sp <= fp.dive_speed + 0.1 and fp.dive_speed < fp.swim_speed, "%.2f m/s" % sp)
	# Nín thở tới hết hơi
	var t := 0.0
	while fp.diving and t < 30.0:
		await _frames(30)
		t += 0.5
	await _frames(20)
	_check("hết hơi: tự ngoi lên dù vẫn giữ phím", not fp.diving and fp.camera.global_position.y > river.water_level and t > 6.0 and t < 16.0, "sau %.1f s nữa" % t)
	await _frames(240)
	_check("vẫn giữ phím thì chưa lặn lại được; hơi đầy dần", not fp.diving and fp.breath > 0.6, "hơi %.0f %%" % (fp.breath * 100.0))
	Input.action_release("fp_dive")
	await _frames(5)
	Input.action_press("fp_dive")
	await _frames(20)
	_check("thả ra bấm lại: lặn tiếp", fp.diving)
	Input.action_release("fp_dive")
	await _frames(20)
	# Mọc lại
	target.gone = 0.0001
	await process_frame
	await process_frame
	await process_frame
	_check("một lúc sau mọc lại chỗ khác", (target.node as MeshInstance3D).visible and int(dive.stats.respawned) == 1 and (target.pos as Vector3).distance_to(tp) > 0.01)
	# Lên bờ: không lặn
	fp.global_position = fp._ground_spawn(Vector3(0, 0, 0))
	Input.action_press("fp_dive")
	await _frames(30)
	_check("trên bờ giữ C: không lặn", not fp.diving and not fp.swimming)
	Input.action_release("fp_dive")
	inv.add("oc", 2)
	inv.items.erase("trai")
	_check("ốc: đủ 2 rổ thì luộc được (ở bếp nhà mình)", inv.can_cook("oc") and Inventory.ITEMS.has("oc_luoc") and Inventory.ITEMS.has("canh_trai"))
	fp.exit()
	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
