extends SceneTree
## Thử công cụ đo hiệu năng (mục 59), headless: tóm tắt số liệu (FPS trung bình / 1 % khung chậm nhất); đang nhập vai thì
## không đo; bài đo đi hết 3 mức × 4 góc nhìn, trả lại camera + mức đồ hoạ + HUD, chọn mức gợi ý, ghi file; huỷ giữa chừng.
## Dùng: timeout 110 godot --headless --path . -s tools/perf_meter_test.gd

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(name_s: String, ok: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["OK" if ok else "SAI", name_s, ("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(name_s)


func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var pm := scene.get_node("PerfMeter") as PerfMeter
	var rig := scene.get_node("CameraRig") as CameraRig
	var gfx := scene.get_node("Graphics") as Graphics
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var hud := scene.get_node("HUD") as Hud
	# 99 khung 10 ms + 1 khung 100 ms
	var smp := PackedFloat32Array()
	for i in 99:
		smp.append(0.01)
	smp.append(0.1)
	var r := PerfMeter.summarize(2, "x", smp)
	_check("tóm tắt: FPS trung bình và 1 % khung chậm nhất", absf(float(r.avg) - 100.0 / 1.09) < 0.5 and absf(float(r.low) - 10.0) < 0.1 and int(r.frames) == 100,
			"trung bình %.1f · chậm nhất %.1f" % [float(r.avg), float(r.low)])
	fp.enter()
	await process_frame
	_check("đang nhập vai: không đo, có lời nhắc", not pm.start_benchmark() and not pm.running and pm._status.visible, pm._status.text)
	fp.exit()
	await process_frame
	pm.bench_seconds = 0.25
	pm.settle_seconds = 0.05
	pm.out_path = "user://benchmark_test.txt"
	if FileAccess.file_exists(pm.out_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pm.out_path))
	rig.set_focus(Vector3(5, 0, -20))
	rig.yaw_deg = 33.0
	rig.distance = 31.0
	rig.snap()
	gfx.set_quality(1)
	var seen_levels := {}
	_check("bấm F4 ở chế độ ngắm cảnh: bắt đầu đo, HUD ẩn", pm.start_benchmark() and pm.running and not hud.visible and not rig.active)
	var guard := 0
	while pm.running and guard < 20000:
		seen_levels[gfx.quality] = true
		await process_frame
		guard += 1
	_check("đi hết 3 mức × 4 góc nhìn", not pm.running and pm.results.size() == 12 and seen_levels.size() == 3, "%d lượt · các mức đã bật %s" % [pm.results.size(), seen_levels.keys()])
	var ok_res := true
	for res: Dictionary in pm.results:
		ok_res = ok_res and float(res.avg) > 0.0 and float(res.low) > 0.0 and float(res.low) <= float(res.avg) + 0.01 and int(res.frames) > 0
	_check("mỗi lượt có FPS trung bình ≥ FPS khung chậm nhất > 0", ok_res)
	_check("trả lại camera, mức đồ hoạ, HUD", rig._target_focus.distance_to(Vector3(5, 0, -20)) < 0.01 and absf(rig.yaw_deg - 33.0) < 0.01
			and absf(rig.distance - 31.0) < 0.01 and gfx.quality == 1 and hud.visible and rig.active)
	_check("có mức gợi ý và bảng kết quả", pm.recommended >= 0 and pm.recommended <= 2 and pm._result_panel.visible
			and pm.report(false).contains("Mức Nhẹ") and pm.report(false).contains("Cả làng từ xa"), "gợi ý mức %s" % Graphics.NAMES[pm.recommended])
	var txt := FileAccess.get_file_as_string(pm.out_path)
	_check("ghi file kết quả", txt.contains("Kết quả đo hiệu năng") and txt.contains("Mức Cao"), "%d ký tự" % txt.length())
	print(pm.report(false).indent("      "))
	# Mức gợi ý theo số liệu giả
	pm.results = [{"quality": 0, "view": "a", "avg": 120.0, "low": 80.0, "frames": 1}, {"quality": 0, "view": "b", "avg": 70.0, "low": 50.0, "frames": 1},
			{"quality": 1, "view": "a", "avg": 90.0, "low": 60.0, "frames": 1}, {"quality": 1, "view": "b", "avg": 52.0, "low": 40.0, "frames": 1},
			{"quality": 2, "view": "a", "avg": 60.0, "low": 30.0, "frames": 1}, {"quality": 2, "view": "b", "avg": 31.0, "low": 20.0, "frames": 1}]
	_check("FPS của một mức = góc nặng nhất", absf(pm.level_fps(0) - 70.0) < 0.01 and absf(pm.level_fps(1) - 52.0) < 0.01 and absf(pm.level_fps(2) - 31.0) < 0.01)
	# Huỷ giữa chừng
	pm._result_panel.visible = false
	gfx.set_quality(2)
	pm.start_benchmark()
	for i in 5:
		await process_frame
	pm.cancel()
	_check("huỷ giữa chừng: trả lại như cũ", not pm.running and gfx.quality == 2 and hud.visible and rig.active)
	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
