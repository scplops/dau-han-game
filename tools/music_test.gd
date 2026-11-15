extends SceneTree
## Thử nhạc nền (mục 58), headless: buổi theo giờ; soạn + dựng từng buổi (thời gian dựng, độ dài, đỉnh, RMS, số nốt,
## mọi nốt nằm trên thang ngũ cung); hai lần gieo khác nhau cho hai khúc khác nhau, cùng lần gieo thì giống hệt;
## phát trong game (dựng ở luồng phụ), hết khúc thì lặng rồi tới khúc mới; phím tắt nhạc; lưu file .wav để nghe thử.
## Dùng: timeout 110 godot --headless --path . -s tools/music_test.gd

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
	var music := scene.get_node("Music") as Music
	var dn := scene.get_node("DayNight") as DayNight
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	dn.auto_run = false
	_check("buổi theo giờ", Music.mood_at(6.0) == "dawn" and Music.mood_at(12.0) == "day" and Music.mood_at(17.5) == "dusk"
			and Music.mood_at(22.0) == "night" and Music.mood_at(3.0) == "night")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/sounds"))
	var ok_all := true
	var lines: Array[String] = []
	for m: String in Music.MOODS:
		var t0 := Time.get_ticks_msec()
		var x := Music.compose(m, 1234)
		var ms := Time.get_ticks_msec() - t0
		var peak := 0.0
		var sum := 0.0
		for v in x:
			peak = maxf(peak, absf(v))
			sum += v * v
		var rms := sqrt(sum / x.size())
		var notes := Music.score(m, 1234)
		# Mọi nốt đều thuộc thang ngũ cung của chủ âm
		var on_scale := true
		var root := float(Music.MOODS[m].root)
		for nt: Array in notes:
			var semis := fposmod(12.0 * log(float(nt[2]) / root) / log(2.0), 12.0)
			var best := 9.0
			for sc: int in Music.SCALE:
				best = minf(best, minf(absf(semis - sc), 12.0 - absf(semis - sc)))
			on_scale = on_scale and best < 0.05
		var secs := float(x.size()) / Music.SAMPLE_RATE
		lines.append("%s: %.0f s · %d nốt · dựng %d ms · đỉnh %.2f · rms %.3f" % [m, secs, notes.size(), ms, peak, rms])
		ok_all = ok_all and secs > 25.0 and secs < 60.0 and peak > 0.35 and peak <= 0.71 and rms > 0.03 and notes.size() > 20 and on_scale and ms < 4000
		Soundscape._wav(x, false).save_to_wav("res://screenshots/sounds/music_%s.wav" % m)
	_check("bốn buổi: dài 25–60 s, không câm, đúng thang ngũ cung, dựng nhanh", ok_all, "\n      " + "\n      ".join(lines))
	var a := Music.compose("day", 1)
	var b := Music.compose("day", 2)
	var a2 := Music.compose("day", 1)
	var diff := 0
	for i in mini(a.size(), b.size()):
		if absf(a[i] - b[i]) > 0.01:
			diff += 1
	_check("mỗi lần gieo một khúc khác; cùng lần gieo thì giống hệt", diff > a.size() / 4 and a == a2, "%d %% mẫu khác nhau" % (100 * diff / a.size()))
	# Phát trong game
	dn.time_of_day = 17.5
	music.first_delay = 0.0
	music._wait = 0.0
	var waited := 0
	while not music.playing and waited < 600:
		await process_frame
		waited += 1
	_check("17:30: nổi khúc chiều muộn (dựng ở luồng phụ)", music.playing and music.mood == "dusk" and int(music.stats.plays) == 1, "sau %d khung" % waited)
	music._on_finished()
	_check("hết khúc: lặng một lúc", not music.playing and music._wait >= music.pause_seconds.x)
	dn.time_of_day = 22.0
	music._wait = 0.0
	waited = 0
	while not music.playing and waited < 600:
		await process_frame
		waited += 1
	_check("22:00: khúc đêm", music.playing and music.mood == "night" and int(music.stats.plays) == 2)
	var ev := InputEventAction.new()
	ev.action = "toggle_music"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check("phím L: tắt nhạc", not music.enabled and not music.playing)
	music._wait = 0.0
	for i in 30:
		await process_frame
	_check("đang tắt thì không nổi nhạc", not music.playing and music._task < 0)
	music.set_enabled(true)
	print("\nKết quả: %s" % ("TẤT CẢ ĐÚNG" if _fails.is_empty() else "SAI %d mục: %s" % [_fails.size(), ", ".join(_fails)]))
	quit()
