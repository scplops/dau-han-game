extends SceneTree
## Chạy thử nhập vai không giao diện: đi vào tường nhà (phải bị chặn), nhìn cửa → vào nhà → ra,
## dẫn bóng ở sân bóng, ngồi câu ở bến sông → thôi câu. In kết quả từng bước.
## Dùng: godot --headless --path . -s tools/fp_test.gd
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
	var door := he.find_entry("main")
	# 1) Đi thẳng vào nhà từ trước sân: phải dừng trước thềm / tường
	var start := door.global_position + Vector3(0, 0, 0)
	var house := scene.get_node("World/House") as House
	var fwd := Basis(Vector3.UP, deg_to_rad(house.house_yaw_deg)) * Vector3.BACK
	rig.global_position = door.global_position + fwd * 6.0
	fp.enter()
	_face(fp, door.global_position)
	fp._pitch = 0.0
	fp.camera.rotation.x = 0.0
	Input.action_press("cam_forward")
	await _frames(240)
	Input.action_release("cam_forward")
	var d_door := Vector2(fp.global_position.x - door.global_position.x, fp.global_position.z - door.global_position.z).length()
	var behind := (fp.global_position - house.house_position).dot(fwd)
	print("1) đi vào nhà: cách cửa %.2f m, y=%.2f, phía trước tường: %s" % [d_door, fp.global_position.y, str(behind > house.depth * 0.5 - house.veranda_depth - 0.1)])
	# 2) Nhìn cửa → E vào nhà → ra lại
	_face(fp, door.global_position)
	await _frames(2)
	print("2) gợi ý khi nhìn cửa: '%s'" % (scene.get_node("HUD") as Hud)._hint_label.text)
	fp._act()
	await create_timer(1.2).timeout
	print("   trong nhà: %s, camera nhập vai đang dùng: %s" % [he.inside, fp.camera.current])
	he.exit_house()
	await create_timer(1.2).timeout
	await _frames(2)
	print("   ra sân: trong nhà=%s, nhập vai tiếp=%s, camera nhập vai=%s, khoá cửa=%s" % [he.inside, fp._suspended == "", fp.camera.current, he.locked])
	# 3) Dẫn bóng: đứng sau bóng, đi tới
	var fb := scene.get_node("World/Football") as Football
	var b0 := fb.ball_position()
	fp.global_position = b0 + Vector3(-3.0, 0.1, 0)
	await _frames(5)
	_face(fp, b0)
	fp._pitch = 0.0
	Input.action_press("cam_forward")
	await _frames(150)
	Input.action_release("cam_forward")
	print("3) bóng lăn được %.2f m theo chân" % Vector2(fb.ball_position().x - b0.x, fb.ball_position().z - b0.z).length())
	# Sút bóng bằng E khi nhìn vào bóng
	var b1 := fb.ball_position()
	fp.global_position = b1 + Vector3(-1.5, 0.1, 0)
	await _frames(10)
	_face(fp, fb.ball_position())
	await _frames(2)
	fp._act()
	await _frames(30)
	print("   sút: bóng bay %.2f m" % Vector2(fb.ball_position().x - b1.x, fb.ball_position().z - b1.z).length())
	# 4) Ngồi câu ở bến tây
	var fishing := scene.get_node("Fishing") as Fishing
	var spot: Node3D = fishing._spots[0].node
	fp.global_position = spot.global_position + spot.global_transform.basis.z * -2.0 + Vector3(0, 0.5, 0)
	await _frames(20)
	_face(fp, spot.global_position + Vector3(0, 0.55, 0.1))
	await _frames(2)
	print("4) gợi ý khi nhìn chỗ câu: '%s'" % (scene.get_node("HUD") as Hud)._hint_label.text)
	fp._act()
	await _frames(5)
	print("   đang câu: %s, camera ngắm cảnh: %s" % [Fishing.State.keys()[fishing.state], rig.camera.current])
	fishing.stop()
	await _frames(3)
	print("   thôi câu: nhập vai tiếp=%s, camera nhập vai=%s" % [fp._suspended == "", fp.camera.current])
	fp.exit()
	print("5) thoát nhập vai: camera ngắm cảnh=%s, tâm=%s" % [rig.camera.current, rig.global_position])
	quit()
