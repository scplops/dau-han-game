extends SceneTree
## Thử Trốn tìm (headless, tua nhanh thời gian thật):
## 1) Chủ nhật 15:00, nhập vai cạnh một đứa trẻ → hội thoại "Chơi trốn tìm" → bịt mắt đếm.
## 2) Hết đếm: đủ người trốn, ai cũng đang trốn, chỗ trốn khuất tầm nhìn từ cột.
## 3) Đi tới gần từng đứa, nhìn vào → bắt được; tìm hết → kết quả → trả bọn trẻ về việc cũ.
## 4) Ván hai: đứng xa cột quay lưng lại → có đứa lén về đập cột; Esc thôi chơi.
## Dùng: godot --headless --path . -s tools/hideseek_test.gd
const SPEED := 3.0

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _secs(s: float) -> void:
	await _frames(int(s * 60.0 / SPEED))

func _face(fp: FirstPerson, target: Vector3) -> void:
	var d := target - fp.camera.global_position
	fp.rotation.y = atan2(-d.x, -d.z)
	fp._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	fp.camera.rotation.x = fp._pitch

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var cal := scene.get_node("Calendar") as LunarCalendar
	while cal.weekday() != 0:
		cal.add_days(1)
	var dn := scene.get_node("DayNight") as DayNight
	dn.time_of_day = 15.0
	var vs := scene.get_node("World/Villagers") as Villagers
	vs.replan()
	await _frames(5)
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var dlg := scene.get_node("Dialogue") as Dialogue
	var hs := scene.get_node("HideSeek") as HideSeek
	var rig := scene.get_node("CameraRig") as CameraRig
	Engine.time_scale = SPEED
	var kid: Villager = null
	for v in vs.people:
		if v.role == "kid" and v.visible and v.state != Villager.State.WALK and hs.refusal(v) == "":
			kid = v
			break
	if kid == null:
		for v in vs.people:
			if v.role == "kid":
				kid = v
				break
		vs.call_out(kid)
	print("Rủ %s (%s) lúc %s, %s" % [kid.display_name, kid.activity, dn.time_text(), cal.date_text()])
	rig.global_position = kid.global_position + Vector3(0, 0, 2.0)
	fp.enter()
	fp.global_position = kid.global_position + Vector3(0, 0.1, 2.0)
	await _frames(10)
	dlg.start(kid, fp)
	fp._suspend("talk")
	var idx := _game_option(dlg, "hideseek")
	print("Câu rủ trốn tìm trong hội thoại: %s" % ("có" if idx >= 0 else "KHÔNG"))
	dlg._choose(idx)
	dlg._choose(0)          # (Bịt mắt đếm)
	await _frames(3)
	print("1) Đang đếm: %s, người trốn %d (trẻ nhà bên %d), màn hình tối %s, người chơi đứng yên '%s'" % [
			hs.phase == HideSeek.Phase.COUNT, hs.hiders.size(), hs._temps.size(), hs._blind.visible, fp._suspended])
	await _secs(hs.count_seconds + 1.0)
	var hiding := 0
	var hidden_from_base := 0
	var space := fp.get_world_3d().direct_space_state
	var dists: Array[String] = []
	for h in hs.hiders:
		if h.has_meta("hiding"):
			hiding += 1
		var ray := PhysicsRayQueryParameters3D.create(hs.base + Vector3(0, 1.6, 0), h.global_position + Vector3(0, 0.7, 0), 1 << (FirstPerson.SOLID_LAYER - 1))
		if not space.intersect_ray(ray).is_empty():
			hidden_from_base += 1
		dists.append("%.0f m" % h.global_position.distance_to(hs.base))
	print("2) Đi tìm: %s, đang trốn %d/%d, khuất tầm nhìn từ cột %d/%d, cách cột %s, nhập vai đi lại %s" % [
			hs.phase == HideSeek.Phase.SEEK, hiding, hs.hiders.size(), hidden_from_base, hs.hiders.size(), ", ".join(dists),
			fp._suspended == "" and fp.active])
	# 3) Đi tới từng đứa: đứng cách 3 m ở hướng không bị che, nhìn vào
	for h: Villager in hs.hiders.duplicate():
		if h.has_meta("hs_done"):
			continue
		var target := h.global_position + Vector3(0, 0.6, 0)
		for k in 16:
			var a := TAU * k / 16.0
			var p := h.global_position + Vector3(cos(a), 0, sin(a)) * 3.0
			var probe := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.6, 0), target, 1 << (FirstPerson.SOLID_LAYER - 1))
			if space.intersect_ray(probe).is_empty():
				fp.global_position = p + Vector3(0, 0.1, 0)
				break
		await _frames(3)
		_face(fp, target)
		await _frames(4)
	print("3) Tìm thấy %d/%d, về đập cột %d, giai đoạn %s" % [hs.found.size(), hs.hiders.size(), hs.escaped.size(), HideSeek.Phase.keys()[hs.phase]])
	await _secs(6.0)
	var left_meta := 0
	for v in vs.people:
		if v.has_meta("hiding") or v.has_meta("hs_spot") or v.activity == "hideseek" and v.dwell > 1000.0:
			left_meta += 1
	print("   Hết ván: tắt %s, trẻ nhà bên còn lại %d, người làng còn dính trò chơi %d, nhập vai %s" % [
			hs.phase == HideSeek.Phase.OFF, hs._temps.size(), left_meta, fp._suspended == "" and fp.active])
	# 4) Ván hai: đứng xa cột, quay lưng → có đứa về đập cột
	var kid2: Villager = null
	for v in vs.people:
		if v.role == "kid" and v.visible and hs.refusal(v) == "":
			kid2 = v
			break
	if kid2 == null:
		kid2 = kid
	fp.global_position = kid2.global_position + Vector3(0, 0.1, 2.0)
	await _frames(5)
	hs.start(kid2)
	await _secs(hs.count_seconds + 1.0)
	var far := hs.base + Vector3(0, 0, 30.0)
	for k in 12:
		var q := hs.base + Vector3(cos(k * 0.5), 0, sin(k * 0.5)) * 30.0
		var down := PhysicsRayQueryParameters3D.create(q + Vector3(0, 3, 0), q - Vector3(0, 3, 0), 1 << (FirstPerson.SOLID_LAYER - 1))
		var hit := space.intersect_ray(down)
		if not hit.is_empty() and float(hit.position.y) < hs.base.y + 0.6:
			far = hit.position
			break
	fp.global_position = far + Vector3(0, 0.1, 0)
	fp.velocity = Vector3.ZERO
	hs._escape_t = 0.0
	for s in 40:
		var away := fp.global_position + (fp.global_position - hs.base)
		_face(fp, Vector3(away.x, fp.camera.global_position.y, away.z))
		hs._escape_t = minf(hs._escape_t, 0.0)
		await _secs(1.0)
		if hs.escaped.size() > 0 or hs.phase != HideSeek.Phase.SEEK:
			break
	print("4) Đứng xa cột %.0f m quay lưng: %d đứa về đập cột, gợi ý '%s'" % [fp.global_position.distance_to(hs.base), hs.escaped.size(), hs._hint_text])
	var ev := InputEventAction.new()
	ev.action = "exit_interior"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(5)
	print("   Esc thôi chơi: tắt %s, nhập vai %s" % [hs.phase == HideSeek.Phase.OFF, fp._suspended == "" and fp.active])
	Engine.time_scale = 1.0
	quit()


## Tìm câu rủ chơi `key`: ở danh sách đầu, hoặc trong "Chơi gì không em?" (chọn câu đó trước). Trả về chỉ số
## trong `dlg._options` hiện tại (−1 nếu không có).
func _game_option(dlg: Dialogue, key: String) -> int:
	var opts := dlg._build_options()
	dlg._options = opts
	for i in opts.size():
		if str(opts[i].get("key", "")) == key:
			return i
	for i in opts.size():
		if str(opts[i].get("key", "")) == "games":
			dlg._choose(i)
			for j in dlg._options.size():
				if str(dlg._options[j].get("key", "")) == key:
					return j
	return -1
