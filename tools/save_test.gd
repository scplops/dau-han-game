extends SceneTree
## Thử lưu game (mục 37), headless: đặt trạng thái (ngày, giờ, thời tiết, camera, sổ câu + giỏ cá, quà, người đã
## quen, kỷ lục các trò qua tín hiệu thật) → lưu ra file tạm → xáo trộn hết → nạp lại → so từng mục.
## Dùng: godot --headless --path . -s tools/save_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(5)
	var sg := scene.get_node("SaveGame") as SaveGame
	sg.save_path = "user://save_test.json"
	print("SaveGame chạy bằng -s: tự lưu / tự mở bị tắt %s" % sg._disabled)
	var cal := scene.get_node("Calendar") as LunarCalendar
	var dn := scene.get_node("DayNight") as DayNight
	var w := scene.get_node("Weather") as Weather
	var rig := scene.get_node("CameraRig") as CameraRig
	var fish := scene.get_node("Fishing") as Fishing
	var qs := scene.get_node("Quests") as Quests
	var dlg := scene.get_node("Dialogue") as Dialogue
	var vs := scene.get_node("World/Villagers") as Villagers
	var jr := scene.get_node("JumpRope") as JumpRope
	var kite := scene.get_node("KiteFlying") as KiteFlying
	var race := scene.get_node("BoatRace") as BoatRace
	var fb := scene.get_node("World/Football") as Football
	# --- Đặt trạng thái
	cal.add_days(17)
	var jd0 := cal.jd
	dn.time_of_day = 9.25
	w.auto_change = false
	w.set_weather("cloudy", true)
	rig.set_focus(Vector3(12.0, 0.0, -80.0))
	rig.yaw_deg = 33.0
	rig.distance = 25.0
	rig.snap()
	await _frames(2)
	fish._log = {"Cá chép": {"count": 3, "best": 1.42}, "Cá diếc": {"count": 1, "best": 0.21}}
	fish._total = 4
	fish.basket.clear()
	fish.basket.append({"name": "Cá chép", "kg": 1.42})
	qs.gifts.clear()
	qs.gifts.append("gói chè Thái")
	qs.gifts.append("con quay gỗ")
	var v1: Villager = vs.people[3]
	var v2: Villager = vs.people[40]
	dlg._met.clear()
	dlg._met[v1] = 2
	dlg._met[v2] = 5
	jr.turn_over.emit("Bạn", 37)
	jr.turn_over.emit("Thằng Tí", 80)       # không phải người chơi: không tính
	kite.finished.emit(64.5, 80.0, "reel")
	race.mode = "team"
	race.finished.emit(1, 49.3)
	fb.goal_scored.emit(0, true)
	fb.goal_scored.emit(1, false)
	var rec0: Dictionary = sg.records.duplicate()
	var ok := sg.save()
	var txt := FileAccess.get_file_as_string(sg.save_path)
	print("1) Lưu: %s · %d byte · kỷ lục %s" % [ok, txt.length(), {"rope_best": rec0.rope_best, "kite_best": rec0.kite_best, "race_best_team": rec0.race_best_team, "race_wins": rec0.race_wins, "goals": rec0.goals}])
	# --- Xáo trộn
	cal.add_days(-40)
	dn.time_of_day = 22.0
	w.set_weather("storm", true)
	rig.set_focus(Vector3.ZERO)
	fish._log = {}
	fish._total = 0
	fish.basket.clear()
	qs.gifts.clear()
	dlg._met.clear()
	for k in sg.records:
		sg.records[k] = 0
	# --- Nạp lại
	sg._load()
	await _frames(3)
	var checks := {
		"ngày": cal.jd == jd0,
		"giờ": absf(dn.time_of_day - 9.25) < 0.01,
		"thời tiết": w.kind == "cloudy",
		"camera": rig._target_focus.distance_to(Vector3(12, 0, -80)) < 0.5 and absf(rig.yaw_deg - 33.0) < 0.1,
		"sổ câu": fish._total == 4 and int(fish._log.get("Cá chép", {}).get("count", 0)) == 3,
		"giỏ cá": fish.basket.size() == 1,
		"quà": qs.gifts.size() == 2 and qs.gifts[1] == "con quay gỗ",
		"người đã quen": int(dlg._met.get(v1, 0)) == 2 and int(dlg._met.get(v2, 0)) == 5,
		"kỷ lục nhảy dây": int(sg.records.rope_best) == 37,
		"kỷ lục diều": absf(float(sg.records.kite_best) - 64.5) < 0.01,
		"đua thuyền": absf(float(sg.records.race_best_team) - 49.3) < 0.01 and int(sg.records.race_wins) == 1,
		"bàn thắng": int(sg.records.goals) == 1,
	}
	var bad: Array[String] = []
	for k: String in checks:
		if not checks[k]:
			bad.append(k)
	print("2) Nạp lại: %d/%d mục đúng %s" % [checks.size() - bad.size(), checks.size(), ("· SAI: " + ", ".join(bad)) if not bad.is_empty() else ""])
	# --- File hỏng
	var f := FileAccess.open(sg.save_path, FileAccess.WRITE)
	f.store_string("{ hỏng")
	f.close()
	sg._load()
	print("3) File hỏng: bỏ qua, game vẫn chạy (ngày giữ %s)" % (cal.jd == jd0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sg.save_path))
	quit()
