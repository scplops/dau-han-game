class_name Music
extends Node
## Nhạc nền (mục 58) — TỔNG HỢP BẰNG CODE như mọi tiếng khác (không file nhạc ngoài). Bốn "buổi": sáng sớm, ban ngày,
## chiều muộn, đêm; mỗi buổi một kiểu (nhịp, giọng, nhạc cụ) trên thang ngũ cung (hò – xự – xang – xê – cống).
## Mỗi lần phát là một khúc MỚI do máy tự soạn (giai điệu đi bước ngắn trên thang âm, cuối câu về chủ âm), dài ~30–45 s,
## xong thì lặng một lúc (`pause_seconds`) rồi mới tới khúc sau — không lặp một bản mãi.
## Nhạc cụ: đàn tranh (dây gảy kiểu Karplus–Strong), sáo trúc (sin + hoạ âm + hơi thổi), đàn bầu ngân nền (sin luyến).
## Khúc nhạc được dựng trong luồng phụ (WorkerThreadPool) để không giật hình. Phím L (`toggle_music`): tắt / bật nhạc.

const SAMPLE_RATE := 16000
## Thang ngũ cung (bán cung so với chủ âm).
const SCALE: Array[int] = [0, 2, 5, 7, 9]
## Kiểu nhạc từng buổi: chủ âm (Hz), độ dài một phách (s), số ô nhịp (4 phách), nhạc cụ giai điệu, tỉ lệ lặng,
## có đàn bầu ngân nền không, âm lượng tương đối.
const MOODS := {
	"dawn": {"name": "sáng sớm", "root": 293.66, "beat": 0.6, "bars": 12, "lead": "flute", "rest": 0.18, "drone": true, "gain": 0.6},
	"day": {"name": "ban ngày", "root": 392.0, "beat": 0.4, "bars": 20, "lead": "pluck", "rest": 0.1, "drone": false, "gain": 1.0},
	"dusk": {"name": "chiều muộn", "root": 261.63, "beat": 0.68, "bars": 12, "lead": "flute", "rest": 0.22, "drone": true, "gain": 0.62},
	"night": {"name": "đêm", "root": 220.0, "beat": 0.85, "bars": 10, "lead": "pluck", "rest": 0.4, "drone": true, "gain": 0.7},
}
## Các kiểu chia phách trong một ô nhịp.
const RHYTHMS: Array = [[1.0, 1.0, 2.0], [2.0, 2.0], [1.0, 1.0, 1.0, 1.0], [3.0, 1.0], [0.5, 0.5, 1.0, 2.0], [1.5, 0.5, 2.0],
		[2.0, 1.0, 1.0], [4.0]]

@export var day_night: DayNight
@export var weather: Weather
## Âm lượng nhạc (dB) và âm lượng khi đang mưa to (nhạc lùi xuống dưới tiếng mưa).
@export var music_db: float = -15.0
@export var rain_db: float = -26.0
## Lặng giữa hai khúc (giây thật, ngẫu nhiên trong khoảng).
@export var pause_seconds: Vector2 = Vector2(18.0, 40.0)
## Lần đầu sau khi mở game chờ bao lâu mới có nhạc.
@export var first_delay: float = 6.0
@export var random_seed: int = 0

var enabled: bool = true
var mood: String = ""              # buổi của khúc đang phát / vừa phát
var playing: bool = false
var stats := {"rendered": 0, "plays": 0}
var _rng := RandomNumberGenerator.new()
var _player: AudioStreamPlayer
var _wait: float = 0.0
var _task: int = -1
var _pending: PackedFloat32Array
var _pending_mood: String = ""
var _mutex := Mutex.new()
var _ready_flag: bool = false
var _toast: Label
var _toast_t: float = 0.0


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), music_db)
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)
	_player.finished.connect(_on_finished)
	_wait = first_delay
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	_toast = GameKit.label(true, 20, Palette.FLOWER_YELLOW)
	_toast.add_theme_color_override("font_outline_color", Palette.WINDOW_DARK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 136.0
	_toast.visible = false
	layer.add_child(_toast)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Buổi theo giờ.
static func mood_at(h: float) -> String:
	if h >= 5.0 and h < 8.0:
		return "dawn"
	if h >= 8.0 and h < 16.5:
		return "day"
	if h >= 16.5 and h < 19.5:
		return "dusk"
	return "night"


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_player.stop()
		playing = false
		_wait = 2.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		set_enabled(not enabled)
		_toast.text = "Nhạc nền: %s" % ("bật" if enabled else "tắt")
		_toast.visible = true
		_toast_t = 2.5
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false
	# Mưa to thì nhạc lùi xuống
	var rain := weather.rain if weather != null else 0.0
	var bus := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(bus, move_toward(AudioServer.get_bus_volume_db(bus), lerpf(music_db, rain_db, clampf(rain * 1.5, 0.0, 1.0)), delta * 6.0))
	if not enabled or playing:
		return
	# Khúc đã dựng xong trong luồng phụ: phát
	if _task >= 0:
		_mutex.lock()
		var done := _ready_flag
		_mutex.unlock()
		if done:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_ready_flag = false
			_play(_pending_mood, _pending)
		return
	_wait -= delta
	if _wait <= 0.0:
		# Giông bão thì thôi không nổi nhạc
		if weather != null and weather.rain > 0.8:
			_wait = 10.0
			return
		_pending_mood = mood_at(day_night.time_of_day if day_night != null else 17.0)
		var seed_v := _rng.randi()
		_task = WorkerThreadPool.add_task(_render_task.bind(_pending_mood, seed_v))


func _render_task(m: String, seed_v: int) -> void:
	var x := compose(m, seed_v)
	_mutex.lock()
	_pending = x
	_ready_flag = true
	_mutex.unlock()


func _play(m: String, x: PackedFloat32Array) -> void:
	mood = m
	_player.stream = Soundscape._wav(x, false)
	_player.play()
	playing = true
	stats.rendered = int(stats.rendered) + 1
	stats.plays = int(stats.plays) + 1


func _on_finished() -> void:
	playing = false
	_wait = _rng.randf_range(pause_seconds.x, pause_seconds.y)


# --- Soạn + dựng một khúc (chạy được trong luồng phụ: chỉ tính toán trên mảng) ---------------------------------

## Tần số của bậc `d` trên thang ngũ cung (d có thể âm / quá 5: sang quãng tám khác).
static func degree_hz(root: float, d: int) -> float:
	var oct := floori(float(d) / 5.0)
	var k := posmod(d, 5)
	return root * pow(2.0, float(oct) + float(SCALE[k]) / 12.0)


## Soạn một khúc cho buổi `m`: danh sách nốt [bắt đầu (s), dài (s), tần số, nhạc cụ, độ to].
static func score(m: String, seed_v: int) -> Array:
	var cfg: Dictionary = MOODS[m]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var beat := float(cfg.beat)
	var root := float(cfg.root)
	var notes: Array = []
	var d := 5 if str(cfg.lead) == "pluck" else 2          # bậc đang đứng (5 = chủ âm quãng trên)
	var t := 0.0
	var bars := int(cfg.bars)
	# Một câu 4 ô nhịp; câu thứ hai nhắc lại nhịp của câu đầu cho dễ nghe
	var phrase_rhythm: Array = []
	for bar in bars:
		var in_phrase := bar % 4
		var rh: Array
		if in_phrase == 3:
			rh = [2.0, 2.0] if rng.randf() < 0.5 else [1.0, 1.0, 2.0]
		elif bar >= 4 and bar < 8 and in_phrase < phrase_rhythm.size():
			rh = phrase_rhythm[in_phrase]
		else:
			rh = RHYTHMS[rng.randi_range(0, RHYTHMS.size() - 1)]
			if bar < 4:
				phrase_rhythm.append(rh)
		var bt := t
		for k in rh.size():
			var dur := float(rh[k]) * beat
			var last := in_phrase == 3 and k == rh.size() - 1
			if last:
				d = 5 if d >= 3 else 0                         # cuối câu về chủ âm
			else:
				d = clampi(d + [-2, -1, -1, 1, 1, 2, 0][rng.randi_range(0, 6)], -1, 9)
			if last or rng.randf() >= float(cfg.rest):
				notes.append([bt, dur * (1.6 if last else 1.0), degree_hz(root, d), str(cfg.lead), 0.8 if k == 0 else 0.62])
				# Đàn tranh: thỉnh thoảng láy thêm nốt quãng trên
				if str(cfg.lead) == "pluck" and dur >= beat * 1.5 and rng.randf() < 0.35:
					notes.append([bt + dur * 0.5, dur * 0.5, degree_hz(root, d + 2), "pluck", 0.4])
			bt += dur
		# Đệm: đầu mỗi ô nhịp gảy chủ âm / bậc năm ở quãng dưới
		notes.append([t, beat * 3.5, degree_hz(root, -5 if in_phrase % 2 == 0 else -2), "pluck", 0.38])
		if str(cfg.lead) == "flute" and rng.randf() < 0.5:
			notes.append([t + beat * 2.0, beat * 2.0, degree_hz(root, [0, 2, 3][rng.randi_range(0, 2)]), "pluck", 0.3])
		t += beat * 4.0
	if bool(cfg.drone):
		notes.append([0.0, t, root * 0.5, "drone", 0.22])
	return notes


## Dựng khúc nhạc thành mảng mẫu −1…1.
static func compose(m: String, seed_v: int) -> PackedFloat32Array:
	var cfg: Dictionary = MOODS[m]
	var notes := score(m, seed_v)
	var total := float(cfg.beat) * 4.0 * int(cfg.bars) + 3.0
	var n := int(total * SAMPLE_RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 17
	for nt: Array in notes:
		var start := int(float(nt[0]) * SAMPLE_RATE)
		match str(nt[3]):
			"pluck": _pluck(x, start, float(nt[1]), float(nt[2]), float(nt[4]), rng)
			"flute": _flute(x, start, float(nt[1]), float(nt[2]), float(nt[4]), rng)
			"drone": _drone(x, start, float(nt[1]), float(nt[2]), float(nt[4]))
	# Chuẩn hoá + mờ dần hai đầu
	var peak := 0.0001
	for v in x:
		peak = maxf(peak, absf(v))
	var k := 0.7 * float(cfg.gain) / peak
	var fade := int(1.5 * SAMPLE_RATE)
	for i in n:
		var f := minf(1.0, minf(float(i) / 800.0, float(n - i) / float(fade)))
		x[i] *= k * f
	return x


## Đàn tranh: dây gảy Karplus–Strong (vòng trễ dài một chu kỳ, mỗi vòng lọc mềm đi) — ngân dài hơn độ dài nốt một chút.
static func _pluck(x: PackedFloat32Array, start: int, dur: float, hz: float, amp: float, rng: RandomNumberGenerator) -> void:
	var period := maxi(2, int(round(SAMPLE_RATE / hz)))
	var buf := PackedFloat32Array()
	buf.resize(period)
	var prev := 0.0
	for i in period:
		prev = prev * 0.45 + rng.randf_range(-1.0, 1.0) * 0.55         # gảy mềm: ồn đã lọc bớt
		buf[i] = prev
	var m := mini(int((dur + 0.9) * SAMPLE_RATE), x.size() - start)
	var damp := 0.4985 if hz > 300.0 else 0.4992
	var j := 0
	for i in m:
		var nx := j + 1
		if nx == period:
			nx = 0
		var y := buf[j]
		buf[j] = (y + buf[nx]) * damp
		x[start + i] += y * amp
		j = nx


## Sáo trúc: sin + hoạ âm, luyến đầu nốt, rung nhẹ, có hơi thổi.
static func _flute(x: PackedFloat32Array, start: int, dur: float, hz: float, amp: float, rng: RandomNumberGenerator) -> void:
	var m := mini(int(dur * SAMPLE_RATE), x.size() - start)
	var ph := 0.0
	var breath := 0.0
	var w := TAU * hz / SAMPLE_RATE
	for i in m:
		var t := float(i) / SAMPLE_RATE
		ph += w * (1.0 - 0.03 * exp(-t * 28.0)) * (1.0 + 0.006 * sin(TAU * 5.2 * t) * minf(t * 3.0, 1.0))
		breath = breath * 0.85 + rng.randf_range(-1.0, 1.0) * 0.15
		var env := minf(t / 0.05, 1.0) * minf((dur - t) / 0.08, 1.0)
		x[start + i] += (sin(ph) + 0.2 * sin(2.0 * ph) + 0.05 * sin(3.0 * ph) + 0.14 * breath) * env * amp * 0.55


## Đàn bầu ngân nền: sin trầm + quãng năm rất khẽ, to nhỏ chậm rãi.
static func _drone(x: PackedFloat32Array, start: int, dur: float, hz: float, amp: float) -> void:
	var m := mini(int(dur * SAMPLE_RATE), x.size() - start)
	var w := TAU * hz / SAMPLE_RATE
	for i in m:
		var t := float(i) / SAMPLE_RATE
		var swell := 0.6 + 0.4 * sin(TAU * t / 9.0)
		x[start + i] += (sin(w * i) + 0.3 * sin(w * 1.5 * i) + 0.15 * sin(w * 2.0 * i)) * amp * swell * 0.5
