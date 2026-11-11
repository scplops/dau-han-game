class_name Soundscape
extends Node
## Âm thanh làng quê (mục 38) — mọi tiếng đều TỔNG HỢP BẰNG CODE lúc khởi động (AudioStreamWAV mono 16 bit,
## `SAMPLE_RATE`), không dùng file âm thanh ngoài (giống mesh procedural). Mỗi khung chỉ tạo một tiếng để không
## giật lúc mở game.
## - Nền (lặp, không định vị): gió (theo `Weather.wind`), mưa (theo `Weather.rain`), dế kêu + ếch nhái ban đêm,
##   tiếng sông (định vị: một nguồn 3D chạy theo điểm sông gần người nghe nhất).
## - Tiếng lẻ (định vị 3D, lấy từ một bể `AudioStreamPlayer3D`): chim hót ban ngày, gà gáy sáng sớm, gà cục tác, chó sủa,
##   trống trường (đầu giờ, ra chơi, tan học), chuông chùa (5:00 và 18:00), trống đua thuyền theo nhịp, nước té
##   (`River.rippled`), sấm sau chớp (`Weather.lightning`), reo hò khi có bàn thắng / về đích, bước chân khi nhập vai.
## - Trong nhà: bus `Ambient` bật lọc thấp (nghe như cách tường), bớt to.
## - Phím N (action `toggle_sound`): tắt / bật tiếng.

const SAMPLE_RATE := 16000

@export var day_night: DayNight
@export var weather: Weather
@export var river: River
@export var village: Village
@export var school: School
@export var school_day: SchoolDay
@export var villagers: Villagers
@export var house_entry: HouseEntry
@export var first_person: FirstPerson
@export var football: Football
@export var boat_race: BoatRace
@export var calendar: LunarCalendar
@export var market: Market
@export_group("Âm lượng (dB)")
## Mức ve kêu (0…1, Seasons đặt: chỉ mùa hạ).
var cicada_level: float = 0.0
@export var cicada_db: float = -20.0
@export var master_db: float = 0.0
@export var wind_db: Vector2 = Vector2(-34.0, -14.0)      # gió nhẹ … gió mạnh
@export var rain_db: Vector2 = Vector2(-40.0, -8.0)
@export var night_db: float = -17.0
@export var river_db: float = -10.0
@export var effects_db: float = -6.0
@export_group("")
@export var random_seed: int = 0

var sounds: Dictionary = {}          # tên → AudioStreamWAV
var muted: bool = false
## Đếm số lần phát từng tiếng (bài thử đọc).
var played: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _queue: Array[String] = []       # tiếng còn chờ tạo
var _loops: Dictionary = {}          # tên → AudioStreamPlayer
var _river_player: AudioStreamPlayer3D
var _market_player: AudioStreamPlayer3D
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i: int = 0
var _timers: Dictionary = {}
var _school_phase: String = ""
var _last_hour: float = -1.0
var _bell_left: int = 0
var _bell_t: float = 0.0
var _drum_left: int = 0
var _drum_t: float = 0.0
var _drum_pos: Vector3
var _race_beat: float = 0.0
var _thunder: Array[float] = []
var _splash_cool: float = 0.0
var _step_t: float = 0.0
var _ambient_bus: int = -1
var _lowpass: AudioEffectLowPassFilter


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_setup_buses()
	_queue.assign(["wind", "rain", "river", "crickets", "frogs", "cicada", "bird0", "bird1", "bird2", "rooster", "drum", "bell",
			"thunder", "splash", "step", "bark", "cluck", "cheer", "murmur", "pop", "flute"])
	for i in 14:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Effects"
		p.unit_size = 12.0
		p.max_distance = 220.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)
	_river_player = AudioStreamPlayer3D.new()
	_river_player.bus = "Ambient"
	_river_player.unit_size = 14.0
	_river_player.max_distance = 140.0
	_river_player.volume_db = river_db
	add_child(_river_player)
	_market_player = AudioStreamPlayer3D.new()
	_market_player.bus = "Ambient"
	_market_player.unit_size = 10.0
	_market_player.max_distance = 90.0
	_market_player.volume_db = -80.0
	add_child(_market_player)
	if weather != null:
		weather.lightning.connect(func() -> void: _thunder.append(_rng.randf_range(0.6, 3.2)))
	if river != null:
		river.rippled.connect(_on_ripple)
	if football != null:
		football.goal_scored.connect(func(_t: int, _p: bool) -> void: play_at("cheer", football.center3(), 0.0, _rng.randf_range(0.95, 1.1)))
	if boat_race != null:
		boat_race.finished.connect(func(place: int, _time: float) -> void:
			if place == 1:
				play_flat("cheer", -4.0))
	_timers = {"bird": 2.0, "rooster": 5.0, "bark": 8.0, "cluck": 3.0}


func _setup_buses() -> void:
	for nm in ["Ambient", "Effects"]:
		if AudioServer.get_bus_index(nm) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, nm)
			AudioServer.set_bus_send(idx, "Master")
	_ambient_bus = AudioServer.get_bus_index("Ambient")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 900.0
	AudioServer.add_bus_effect(_ambient_bus, _lowpass)
	AudioServer.set_bus_effect_enabled(_ambient_bus, 0, false)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), effects_db)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_sound"):
		muted = not muted
		AudioServer.set_bus_mute(0, muted)
		get_viewport().set_input_as_handled()


# --- Mỗi khung --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _queue.is_empty():
		var nm: String = _queue.pop_front()
		sounds[nm] = _make(nm)
		if nm in ["wind", "rain", "crickets", "frogs", "cicada"]:
			var p := AudioStreamPlayer.new()
			p.stream = sounds[nm]
			p.bus = "Ambient"
			p.volume_db = -80.0
			add_child(p)
			p.play(_rng.randf() * 2.0)
			_loops[nm] = p
		elif nm == "river":
			_river_player.stream = sounds[nm]
			_river_player.play()
		elif nm == "murmur":
			_market_player.stream = sounds[nm]
			if market != null:
				_market_player.global_position = market.origin + Vector3(0, 1.5, 0)
			_market_player.play()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var listen := cam.global_position
	var h := day_night.time_of_day if day_night != null else 15.0
	var inside := house_entry != null and house_entry.inside
	var night := h >= 18.8 or h < 5.0
	var rain := weather.rain if weather != null else 0.0
	var wind := weather.wind if weather != null else 1.0
	# Trong nhà: nghe như cách tường
	AudioServer.set_bus_effect_enabled(_ambient_bus, 0, inside)
	var room := -8.0 if inside else 0.0
	_fade("wind", lerpf(wind_db.x, wind_db.y, clampf((wind - 0.5) / 1.5, 0.0, 1.0)) + room, delta)
	_fade("rain", (lerpf(rain_db.x, rain_db.y, clampf(rain, 0.0, 1.0)) if rain > 0.02 else -80.0) + room * 0.5, delta)
	var night_k := clampf((h - 18.6) / 0.6, 0.0, 1.0) if h >= 12.0 else clampf((5.2 - h) / 0.6, 0.0, 1.0)
	_fade("crickets", (night_db if night_k > 0.0 and rain < 0.5 else -80.0) + room + (1.0 - night_k) * -20.0, delta)
	_fade("frogs", (night_db - 3.0 + rain * 6.0 if night_k > 0.0 else -80.0) + room + (1.0 - night_k) * -20.0, delta)
	# Ve kêu ngày hè (8:00–18:00, tạnh ráo), râm ran nhất buổi trưa
	var day_k := clampf((h - 7.5) / 1.5, 0.0, 1.0) * clampf((18.2 - h) / 1.2, 0.0, 1.0)
	var cic := cicada_level * day_k * (1.0 if rain < 0.2 else 0.0)
	_fade("cicada", (cicada_db + (1.0 - cic) * -18.0 if cic > 0.02 else -80.0) + room, delta)
	# Tiếng sông: nguồn 3D ở điểm sông gần người nghe nhất
	if river != null and _river_player.stream != null:
		var s := river.nearest_s(Vector2(listen.x, listen.z))
		var c: Vector2 = river.sample(s)[0]
		_river_player.global_position = Vector3(c.x, river.water_level, c.y)
		_river_player.volume_db = river_db + (-12.0 if inside else 0.0)
	# Chợ phiên: tiếng người mua bán ồn ào khi chợ họp
	if market != null and _market_player.stream != null:
		var want := (-4.0 if market.is_open else -80.0) + (-12.0 if inside else 0.0)
		_market_player.volume_db = move_toward(_market_player.volume_db, want, delta * 30.0)
	if inside:
		_tick_timers(delta, listen, h, night, rain, true)
		return
	_tick_timers(delta, listen, h, night, rain, false)
	_tick_events(delta, h)
	_tick_steps(delta)


func _fade(nm: String, target_db: float, delta: float) -> void:
	if not _loops.has(nm):
		return
	var p: AudioStreamPlayer = _loops[nm]
	p.volume_db = move_toward(p.volume_db, target_db, delta * 30.0)


## Tiếng lẻ ngẫu nhiên: chim hót, gà gáy, chó sủa, gà cục tác.
func _tick_timers(delta: float, listen: Vector3, h: float, night: bool, rain: float, inside: bool) -> void:
	for k: String in _timers:
		_timers[k] = float(_timers[k]) - delta
	var room := -10.0 if inside else 0.0
	if float(_timers.bird) <= 0.0:
		_timers.bird = _rng.randf_range(2.5, 7.0)
		if not night and h >= 5.3 and rain < 0.3:
			var a := _rng.randf() * TAU
			play_at("bird%d" % _rng.randi_range(0, 2), listen + Vector3(cos(a) * 14.0, 5.0, sin(a) * 14.0), -6.0 + room, _rng.randf_range(0.85, 1.2))
	if float(_timers.rooster) <= 0.0:
		_timers.rooster = _rng.randf_range(12.0, 30.0)
		if h >= 4.3 and h < 7.2 and village != null and not village.homes.is_empty():
			var hm: Dictionary = village.homes[_rng.randi_range(0, village.homes.size() - 1)]
			play_at("rooster", hm.door, room, _rng.randf_range(0.9, 1.1))
	if float(_timers.bark) <= 0.0:
		_timers.bark = _rng.randf_range(9.0, 25.0)
		var dog := _nearest_animal("dog", listen, 60.0)
		if dog != null:
			play_at("bark", dog.global_position + Vector3(0, 0.6, 0), room, _rng.randf_range(0.9, 1.15))
	if float(_timers.cluck) <= 0.0:
		_timers.cluck = _rng.randf_range(3.0, 9.0)
		if not night:
			var hen := _nearest_animal("chicken", listen, 35.0)
			if hen != null:
				play_at("cluck", hen.global_position, -4.0 + room, _rng.randf_range(0.9, 1.3))


func _nearest_animal(role: String, p: Vector3, within: float) -> Villager:
	if villagers == null:
		return null
	var best: Villager = null
	var bd := within
	for a in villagers.animals:
		if a.role == role and a.visible:
			var d := a.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = a
	return best


## Tiếng theo lịch: trống trường, chuông chùa, sấm, trống đua thuyền.
func _tick_events(delta: float, h: float) -> void:
	# Trống trường mỗi khi đổi giai đoạn (vào học, ra chơi, vào lại, tan học)
	if school_day != null and school != null:
		var ph := school_day.phase(h)
		if _school_phase != "" and ph != _school_phase and ph in ["arrive", "class", "recess", "leave", "flag"]:
			_drum_left = 3 if ph != "leave" else 5
			_drum_t = 0.0
			_drum_pos = school.flag_pos + Vector3(0, 1.5, 0)
		_school_phase = ph
	if _drum_left > 0:
		_drum_t -= delta
		if _drum_t <= 0.0:
			play_at("drum", _drum_pos, 2.0, 1.0)
			_drum_left -= 1
			_drum_t = 0.55
	# Chuông chùa lúc 5:00 và 18:00
	if _last_hour >= 0.0 and village != null:
		for bell_h in [5.0, 18.0]:
			if _last_hour < bell_h and h >= bell_h and h - _last_hour < 1.0:
				_bell_left = 3
				_bell_t = 0.0
	_last_hour = h
	if _bell_left > 0:
		_bell_t -= delta
		if _bell_t <= 0.0:
			play_at("bell", village.pagoda_spot + Vector3(0, 4, 0), 4.0, 1.0)
			_bell_left -= 1
			_bell_t = 5.5
	# Sấm: sau chớp một lúc
	for i in range(_thunder.size() - 1, -1, -1):
		_thunder[i] -= delta
		if _thunder[i] <= 0.0:
			_thunder.remove_at(i)
			play_flat("thunder", _rng.randf_range(-6.0, 0.0), _rng.randf_range(0.8, 1.1))
	# Trống đua thuyền theo nhịp (cả khi dân làng tự đua)
	_splash_cool -= delta
	if boat_race != null and boat_race.phase == BoatRace.Phase.RACE and not boat_race.boats.is_empty():
		var prev := _race_beat
		_race_beat = fmod(boat_race._beat_t, boat_race.beat_period)
		if _race_beat < prev:
			play_at("drum", (boat_race.boats[0].node as Node3D).global_position + Vector3(0, 1, 0), -4.0, 1.25)


func _on_ripple(pos: Vector3) -> void:
	if _splash_cool > 0.0:
		return
	_splash_cool = 0.25
	play_at("splash", pos, -3.0, _rng.randf_range(0.85, 1.25))


## Bước chân khi nhập vai đi trên mặt đất.
func _tick_steps(delta: float) -> void:
	if first_person == null or not first_person.active or first_person._suspended != "" or not first_person.is_on_floor() or first_person.swimming:
		return
	var v := first_person.velocity
	var sp := Vector2(v.x, v.z).length()
	if sp < 0.6:
		_step_t = 0.0
		return
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = clampf(1.1 / sp, 0.26, 0.6)
		play_flat("step", -14.0, _rng.randf_range(0.85, 1.15))


# --- Phát ---------------------------------------------------------------------------------------------

func play_at(nm: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(nm) or muted:
		return
	played[nm] = int(played.get(nm, 0)) + 1
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = sounds[nm]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func play_flat(nm: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(nm) or muted:
		return
	played[nm] = int(played.get(nm, 0)) + 1
	var p := AudioStreamPlayer.new()
	p.stream = sounds[nm]
	p.bus = "Effects"
	p.volume_db = vol_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# --- Tổng hợp tiếng ----------------------------------------------------------------------------------

func _make(nm: String) -> AudioStreamWAV:
	match nm:
		"wind": return _wav(_wind(6.0), true)
		"rain": return _wav(_rain(4.0), true)
		"river": return _wav(_river(5.0), true)
		"crickets": return _wav(_crickets(4.0), true)
		"frogs": return _wav(_frogs(6.0), true)
		"cicada": return _wav(_cicada(6.0), true)
		"bird0": return _wav(_bird(0.9, 0), false)
		"bird1": return _wav(_bird(1.2, 1), false)
		"bird2": return _wav(_bird(0.7, 2), false)
		"rooster": return _wav(_rooster(), false)
		"drum": return _wav(_drum(), false)
		"bell": return _wav(_bell(), false)
		"thunder": return _wav(_thunder_s(), false)
		"splash": return _wav(_splash(), false)
		"step": return _wav(_step(), false)
		"bark": return _wav(_bark(), false)
		"cluck": return _wav(_cluck(), false)
		"cheer": return _wav(_cheer(), false)
		"murmur": return _wav(_murmur(5.0), true)
		"pop": return _wav(_pop(), false)
		"flute": return _wav(_flute(), false)
	return _wav(PackedFloat32Array([0.0]), false)


## Mảng mẫu −1…1 → AudioStreamWAV 16 bit. `loop`: lặp cả đoạn (đuôi đã trộn vào đầu cho liền).
static func _wav(x: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(x.size() * 2)
	for i in x.size():
		bytes.encode_s16(i * 2, int(clampf(x[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SAMPLE_RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = x.size()
	return w


## Trộn đoạn cuối vào đoạn đầu rồi cắt, để vòng lặp không có chỗ nối.
static func _seamless(x: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := x.size() - fade
	for i in fade:
		var t := float(i) / fade
		x[i] = x[i] * t + x[n + i] * (1.0 - t)
	x.resize(n)
	return x


static func _norm(x: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in x:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in x.size():
		x[i] *= k
	return x


func _wind(sec: float) -> PackedFloat32Array:
	var n := int(sec * SAMPLE_RATE) + 4000
	var x := PackedFloat32Array()
	x.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var gust := 0.55 + 0.3 * sin(t * TAU / sec * 2.0) + 0.15 * sin(t * TAU / sec * 5.0 + 1.3)
		var a := 0.02 + 0.05 * gust          # lọc thấp, độ mở theo cơn gió
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * a
		lp2 += (lp - lp2) * a
		x[i] = lp2 * gust
	return _norm(_seamless(x, 4000), 0.8)


func _rain(sec: float) -> PackedFloat32Array:
	var n := int(sec * SAMPLE_RATE) + 3000
	var x := PackedFloat32Array()
	x.resize(n)
	var lp := 0.0
	var drop := 0.0
	for i in n:
		var w := _rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.35
		var hiss := w - lp                    # lọc cao: tiếng rào rào
		if _rng.randf() < 0.004:
			drop = _rng.randf_range(0.4, 1.0)  # giọt to lộp độp
		drop *= 0.985
		x[i] = hiss * 0.5 + drop * _rng.randf_range(-1.0, 1.0) * 0.6
	return _norm(_seamless(x, 3000), 0.75)


func _river(sec: float) -> PackedFloat32Array:
	var n := int(sec * SAMPLE_RATE) + 4000
	var x := PackedFloat32Array()
	x.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var bub := 0.0
	var bf := 400.0
	var ph := 0.0
	for i in n:
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.08
		lp2 += (lp - lp2) * 0.08
		if _rng.randf() < 0.0012:
			bub = 1.0
			bf = _rng.randf_range(260.0, 700.0)
		bub *= 0.9993
		bf *= 1.00004                        # bọt nước: tiếng "lóc" cao dần
		ph += TAU * bf / SAMPLE_RATE
		x[i] = lp2 * 1.4 + sin(ph) * bub * bub * 0.25
	return _norm(_seamless(x, 4000), 0.7)


func _crickets(sec: float) -> PackedFloat32Array:
	var n := int(sec * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	for c in 4:
		var f := _rng.randf_range(4000.0, 5200.0)
		var period := _rng.randf_range(0.45, 0.8)
		var off := _rng.randf() * period
		var amp := _rng.randf_range(0.4, 1.0)
		# Chu kỳ chia hết đoạn lặp để vòng lặp liền
		period = sec / round(sec / period)
		for i in n:
			var t := float(i) / SAMPLE_RATE
			var u := fmod(t + off, period)
			if u < 0.12:
				var pulse := sin(PI * fmod(u, 0.04) / 0.04)    # 3 tiếng "ri" liền
				x[i] += sin(TAU * f * t) * pulse * amp
	return _norm(x, 0.6)


## Ve sầu: vài con, mỗi con một tiếng rít cao rung nhanh, to dần rồi lịm đi theo từng đợt.
func _cicada(sec: float) -> PackedFloat32Array:
	var n := int(sec * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	for c in 5:
		var f := _rng.randf_range(3400.0, 4600.0)
		var buzz := _rng.randf_range(70.0, 115.0)
		var swell := sec / float(_rng.randi_range(1, 3))      # chu kỳ đợt chia hết đoạn lặp
		var off := _rng.randf() * swell
		var amp := _rng.randf_range(0.5, 1.0)
		for i in n:
			var t := float(i) / SAMPLE_RATE
			var env := 0.5 - 0.5 * cos(TAU * (t + off) / swell)
			var am := 0.55 + 0.45 * signf(sin(TAU * buzz * t))
			x[i] += (sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.51 * t)) * am * env * env * amp
	return _norm(x, 0.5)


func _frogs(sec: float) -> PackedFloat32Array:
	var n := int(sec * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	for k in 9:
		var t0 := _rng.randf_range(0.0, sec - 0.5)
		var f := _rng.randf_range(160.0, 280.0)
		var croaks := _rng.randi_range(1, 2)
		for c in croaks:
			var s0 := int((t0 + c * 0.32) * SAMPLE_RATE)
			var ln := int(0.18 * SAMPLE_RATE)
			for j in ln:
				var i := (s0 + j) % n
				var t := float(j) / SAMPLE_RATE
				var env := sin(PI * float(j) / ln)
				var am := 0.5 + 0.5 * sin(TAU * 38.0 * t)          # "ộp" rung
				x[i] += tanh(3.0 * sin(TAU * f * (1.0 - 0.15 * t / 0.18) * t)) * env * am * 0.5
	return _norm(x, 0.6)


func _bird(sec: float, kind: int) -> PackedFloat32Array:
	var n := int(sec * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var notes := _rng.randi_range(3, 6)
	var ph := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var k := int(t / sec * notes)
		var u := fmod(t / sec * notes, 1.0)
		var base: float = [3200.0, 2600.0, 4200.0][kind] * (1.0 + 0.12 * ((k * 7 + kind) % 3))
		var f: float = base * (1.0 + (0.35 * u if kind == 0 else (-0.3 * u if kind == 1 else 0.5 * sin(u * PI * 3.0))))
		ph += TAU * f / SAMPLE_RATE
		var env := sin(PI * minf(u / 0.75, 1.0)) if u < 0.75 else 0.0
		x[i] = sin(ph) * env
	return _norm(x, 0.7)


## Gà gáy "ò ó o o": giọng giàu hoạ âm, bốn nốt trượt, rung nhẹ.
func _rooster() -> PackedFloat32Array:
	var notes := [[0.0, 0.28, 520.0, 560.0], [0.3, 0.32, 760.0, 820.0], [0.64, 0.42, 800.0, 700.0], [1.08, 0.7, 640.0, 470.0]]
	var n := int(1.85 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		for nt: Array in notes:
			var t0: float = nt[0]
			var d: float = nt[1]
			if t >= t0 and t < t0 + d:
				var u := (t - t0) / d
				var f := lerpf(nt[2], nt[3], u) * (1.0 + 0.02 * sin(TAU * 7.0 * t))
				ph += TAU * f / SAMPLE_RATE
				var env := minf(u / 0.08, 1.0) * minf((1.0 - u) / 0.15, 1.0)
				var v := 0.0
				for hm in range(1, 7):
					v += sin(ph * hm) * [1.0, 0.7, 0.9, 0.5, 0.35, 0.2][hm - 1]   # hoạ âm thứ 3 mạnh: giọng khàn
				x[i] = v * env
	return _norm(x, 0.8)


## Trống trường "tùng": âm trầm tụt giọng + tiếng gõ.
func _drum() -> PackedFloat32Array:
	var n := int(1.0 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var f := 70.0 + 70.0 * exp(-t * 18.0)
		ph += TAU * f / SAMPLE_RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.2
		x[i] = sin(ph) * exp(-t * 4.5) + lp * exp(-t * 40.0) * 0.8
	return _norm(x, 0.95)


## Chuông chùa: các hoạ âm lệch (chuông đồng), ngân dài, có tiếng "đổ hồi".
func _bell() -> PackedFloat32Array:
	var n := int(6.0 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var parts := [[1.0, 1.0, 0.35], [2.0, 0.6, 0.5], [2.76, 0.45, 0.8], [5.4, 0.25, 1.6], [0.5, 0.5, 0.25]]
	var f0 := 196.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var v := 0.0
		for p: Array in parts:
			var fr: float = f0 * float(p[0])
			v += sin(TAU * fr * t + 0.3 * sin(TAU * 1.3 * t)) * float(p[1]) * exp(-t * float(p[2]))
		x[i] = v * minf(t / 0.004, 1.0)
	return _norm(x, 0.85)


func _thunder_s() -> PackedFloat32Array:
	var n := int(5.0 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var brown := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		brown = clampf(brown + _rng.randf_range(-0.05, 0.05), -1.0, 1.0) * 0.999
		lp += (brown - lp) * 0.05
		var crack := _rng.randf_range(-1.0, 1.0) * exp(-t * 9.0) * 0.6
		var roll := (0.6 + 0.4 * sin(t * 5.3) * sin(t * 2.1)) * exp(-t * 0.7)
		x[i] = lp * 3.0 * roll * minf(t / 0.05, 1.0) + crack
	return _norm(x, 0.95)


func _splash() -> PackedFloat32Array:
	var n := int(0.45 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var w := _rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.5
		ph += TAU * (500.0 + 900.0 * t) / SAMPLE_RATE
		x[i] = (w - lp) * exp(-t * 12.0) + sin(ph) * exp(-t * 20.0) * 0.4
	return _norm(x, 0.8)


func _step() -> PackedFloat32Array:
	var n := int(0.14 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.12
		x[i] = lp * exp(-t * 35.0) * minf(t / 0.004, 1.0)
	return _norm(x, 0.8)


## Chó sủa "gâu": hai tiếng ngắn, giọng khàn.
func _bark() -> PackedFloat32Array:
	var n := int(0.62 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var u := fmod(t, 0.31)
		if u < 0.16:
			var f := 520.0 - 900.0 * u
			ph += TAU * f / SAMPLE_RATE
			var env := minf(u / 0.01, 1.0) * exp(-u * 18.0)
			x[i] = (tanh(4.0 * sin(ph)) * 0.7 + _rng.randf_range(-1.0, 1.0) * 0.3) * env
	return _norm(x, 0.8)


func _cluck() -> PackedFloat32Array:
	var n := int(0.5 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var u := fmod(t, 0.12)
		if u < 0.06 and t < 0.38:
			ph += TAU * (650.0 + 300.0 * u / 0.06) / SAMPLE_RATE
			x[i] = tanh(3.0 * sin(ph)) * sin(PI * u / 0.06)
	return _norm(x, 0.7)


## Reo hò: nhiều giọng "ê" trượt lên xuống + tiếng ồn đám đông.
func _cheer() -> PackedFloat32Array:
	var n := int(1.6 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	for v in 6:
		var f0 := _rng.randf_range(260.0, 480.0)
		var t0 := _rng.randf_range(0.0, 0.25)
		var ph := 0.0
		var bp := 0.0
		var bp2 := 0.0
		for i in n:
			var t := float(i) / SAMPLE_RATE - t0
			if t < 0.0:
				continue
			var f := f0 * (1.0 + 0.25 * sin(minf(t, 1.0) * PI) + 0.03 * sin(TAU * 6.0 * t))
			ph += TAU * f / SAMPLE_RATE
			var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
			bp += (saw - bp) * 0.35                    # lọc nhẹ cho bớt chói
			bp2 += (bp - bp2) * 0.35
			var env := minf(t / 0.08, 1.0) * clampf((1.4 - t) / 0.4, 0.0, 1.0)
			x[i] += (bp - bp2 * 0.6) * env * 0.4
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.3
		x[i] += lp * 0.25 * clampf((1.5 - t) / 0.5, 0.0, 1.0)
	return _norm(x, 0.8)


## Chợ ồn ào: nhiều giọng nói chuyện (răng cưa lọc, cao độ lên xuống theo câu, ngắt quãng theo âm tiết) chồng lên nhau.
func _murmur(sec: float) -> PackedFloat32Array:
	var n := int(sec * SAMPLE_RATE) + 4000
	var x := PackedFloat32Array()
	x.resize(n)
	for v in 7:
		var f0 := _rng.randf_range(150.0, 320.0)
		var syl := _rng.randf_range(4.0, 6.5)        # âm tiết / giây
		var ph := 0.0
		var lp := 0.0
		var lp2 := 0.0
		var talk := _rng.randf() < 0.5
		var next_switch := _rng.randf_range(0.4, 1.6)
		for i in n:
			var t := float(i) / SAMPLE_RATE
			if t > next_switch:
				talk = not talk                       # nói một câu rồi nghỉ
				next_switch = t + (_rng.randf_range(0.8, 2.0) if talk else _rng.randf_range(0.3, 1.0))
			if not talk:
				continue
			var f := f0 * (1.0 + 0.18 * sin(TAU * 0.7 * t + v) + 0.08 * sin(TAU * syl * 0.5 * t))
			ph += TAU * f / SAMPLE_RATE
			var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
			lp += (saw - lp) * 0.22
			lp2 += (lp - lp2) * 0.22
			var env := maxf(0.0, sin(PI * fmod(t * syl, 1.0)))
			x[i] += (lp - lp2 * 0.7) * env * 0.35
	return _norm(_seamless(x, 4000), 0.6)


## Tiếng pháo nổ "đùng": ồn trắng tắt rất nhanh + một nhịp trầm.
func _pop() -> PackedFloat32Array:
	var n := int(0.22 * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		x[i] = _rng.randf_range(-1.0, 1.0) * exp(-t * 38.0) + sin(TAU * 110.0 * t) * exp(-t * 25.0) * 0.6
	return _norm(x, 0.95)


## Sáo trúc (túi đồ, mục 48): một câu nhạc ngũ cung, mỗi nốt có rung, hơi thổi (ồn lọc) và luyến lên ở đầu nốt.
func _flute() -> PackedFloat32Array:
	# [nốt (bán cung so với Sol 392 Hz), số phách]
	var tune: Array = [[0, 1.0], [3, 0.5], [5, 0.5], [7, 1.5], [5, 0.5], [3, 1.0], [0, 0.5], [-2, 0.5], [0, 2.0],
			[5, 1.0], [7, 0.5], [10, 0.5], [7, 1.0], [5, 0.5], [3, 0.5], [0, 2.5]]
	var beat := 0.34
	var total := 0.0
	for nt: Array in tune:
		total += float(nt[1]) * beat
	var n := int((total + 0.4) * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var pos := 0
	var phase := 0.0
	var breath := 0.0
	for nt: Array in tune:
		var f0 := 392.0 * pow(2.0, float(nt[0]) / 12.0)
		var len_s := float(nt[1]) * beat
		var m := int(len_s * SAMPLE_RATE)
		for i in m:
			if pos + i >= n:
				break
			var t := float(i) / SAMPLE_RATE
			var bend := 1.0 - 0.03 * exp(-t * 30.0)              # luyến lên đầu nốt
			var vib := 1.0 + 0.006 * sin(TAU * 5.5 * t) * clampf(t * 3.0, 0.0, 1.0)
			phase += TAU * f0 * bend * vib / SAMPLE_RATE
			var env := clampf(t / 0.04, 0.0, 1.0) * clampf((len_s - t) / 0.05, 0.0, 1.0)
			breath = breath * 0.85 + _rng.randf_range(-1.0, 1.0) * 0.15
			x[pos + i] = (sin(phase) + 0.22 * sin(2.0 * phase) + 0.06 * sin(3.0 * phase) + 0.18 * breath) * env * (0.75 + 0.25 * sin(PI * t / len_s))
		pos += m
	return _norm(x, 0.8)
