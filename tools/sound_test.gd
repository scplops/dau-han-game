extends SceneTree
## Thử âm thanh (mục 38), headless: thời gian tổng hợp từng tiếng (mỗi khung một tiếng), độ dài / to nhất / RMS
## (tiếng nào câm là lỗi); âm lượng nền theo thời tiết, ngày / đêm, trong nhà; các tiếng theo sự kiện: trống trường khi
## đổi tiết, chuông chùa 5:00, sấm sau chớp, nước té (giới hạn nhịp), bước chân khi nhập vai, reo khi có bàn thắng.
## Lưu các tiếng ra screenshots/sounds/*.wav để nghe thử.
## Dùng: godot --headless --path . -s tools/sound_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _stats(w: AudioStreamWAV) -> Array:
	var d := w.data
	var n := d.size() / 2
	var peak := 0.0
	var sum := 0.0
	for i in range(0, n, 4):
		var v := absf(d.decode_s16(i * 2) / 32000.0)
		peak = maxf(peak, v)
		sum += v * v
	return [float(n) / Soundscape.SAMPLE_RATE, peak, sqrt(sum / maxf(n / 4.0, 1.0))]

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var snd := scene.get_node("Soundscape") as Soundscape
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	var longest := 0
	var frames := 0
	while not snd._queue.is_empty() and frames < 200:
		var a := Time.get_ticks_usec()
		await process_frame
		longest = maxi(longest, Time.get_ticks_usec() - a)
		frames += 1
	print("1) Tổng hợp %d tiếng trong %d khung, khung lâu nhất %.0f ms" % [snd.sounds.size(), frames, longest / 1000.0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/sounds"))
	var silent: Array[String] = []
	var rows: Array[String] = []
	for nm: String in snd.sounds:
		var st := _stats(snd.sounds[nm])
		rows.append("%s %.1fs đỉnh %.2f rms %.2f" % [nm, st[0], st[1], st[2]])
		if float(st[2]) < 0.02:
			silent.append(nm)
		(snd.sounds[nm] as AudioStreamWAV).save_to_wav("res://screenshots/sounds/%s.wav" % nm)
	print("   " + " · ".join(rows))
	print("   câm: %s" % (silent if not silent.is_empty() else "không"))
	# 2) Âm nền
	var dn := scene.get_node("DayNight") as DayNight
	dn.auto_run = false
	var vols := func() -> String:
		var out: Array[String] = []
		for k in ["wind", "rain", "crickets", "frogs"]:
			out.append("%s %.0f" % [k, (snd._loops[k] as AudioStreamPlayer).volume_db])
		return ", ".join(out)
	dn.time_of_day = 14.0
	await _wait(3.0)
	print("2) 14:00 nắng: %s" % vols.call())
	dn.time_of_day = 21.0
	await _wait(3.0)
	print("   21:00 nắng: %s" % vols.call())
	w.set_weather("storm", true)
	await _wait(3.0)
	print("   21:00 giông: %s" % vols.call())
	var he := scene.get_node("HouseEntry") as HouseEntry
	he.enter_house(true, he.find_entry("main"))
	await _wait(3.0)
	print("   trong nhà (giông): %s · lọc trầm %s" % [vols.call(), AudioServer.is_bus_effect_enabled(snd._ambient_bus, 0)])
	he.exit_house(true)
	await _frames(10)
	# 3) Sự kiện
	snd.played.clear()
	w.lightning.emit()
	await _wait(3.5)
	var cal := scene.get_node("Calendar") as LunarCalendar
	while cal.weekday() != 1:
		cal.add_days(1)
	w.set_weather("clear", true)
	dn.time_of_day = 4.95
	await _frames(5)
	dn.time_of_day = 5.02            # qua 5:00: chuông chùa
	await _wait(12.0)
	dn.time_of_day = 6.3
	await _frames(5)
	dn.time_of_day = 6.5             # qua 6:24: trống vào học
	await _wait(2.0)
	var river := scene.get_node("World/River") as River
	for i in 20:
		river.splash(Vector3(150, 0, -115))
		await _wait(0.05)
	(scene.get_node("World/Football") as Football).goal_scored.emit(0, true)
	var fp := scene.get_node("FirstPerson") as FirstPerson
	var rig := scene.get_node("CameraRig") as CameraRig
	rig.global_position = Vector3(-8, 0, 14)
	fp.enter()
	await _frames(10)
	fp.rotation.y = 0.0
	Input.action_press("cam_forward")
	await _wait(3.0)
	Input.action_release("cam_forward")
	await _frames(10)
	print("3) Đã phát: %s" % snd.played)
	print("   (sấm sau chớp, chuông chùa 3 tiếng lúc 5:00, trống trường khi vào học, nước té giới hạn ~4/s, bước chân, reo khi có bàn)")
	print("Tổng thời gian chạy: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()
