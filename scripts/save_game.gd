class_name SaveGame
extends Node
## Lưu game (mục 37): ngày giờ trong game, thời tiết, chỗ camera đang ngắm, sổ câu + giỏ cá, quà được tặng,
## người đã quen (số lần trò chuyện), kỷ lục các trò dân gian và bóng đá.
## - Tự lưu mỗi `autosave_seconds` giây thật, khi tắt cửa sổ, và khi nhấn F5 (action `save_game`).
## - Mở game: có file lưu thì nạp lại (tiếp tục ngày giờ cũ, không lấy ngày hôm nay của máy).
## - Chạy bằng `-s tools/...` (bài thử, công cụ chụp ảnh) thì KHÔNG đọc / ghi file lưu.
## - Ván mới: Ctrl+F5 (action `new_game`) xoá file lưu, lần mở sau bắt đầu lại từ đầu.

signal saved(path: String)
signal loaded(path: String)

@export var enabled: bool = true
@export var save_path: String = "user://lang_que_save.json"
@export var autosave_seconds: float = 60.0
@export var calendar: LunarCalendar
@export var day_night: DayNight
@export var weather: Weather
@export var outdoor_rig: CameraRig
@export var fishing: Fishing
@export var quests: Quests
@export var dialogue: Dialogue
@export var villagers: Villagers
@export var football: Football
@export var jump_rope: JumpRope
@export var tip_cat: TipCat
@export var boat_race: BoatRace
@export var kite: KiteFlying
@export var o_an_quan: OAnQuan
@export var hide_seek: HideSeek
@export var market: Market

const VERSION := 1

## Kỷ lục của người chơi (sổ tay mục 38 đọc từ đây).
var records: Dictionary = {
	"rope_best": 0, "rope_games": 0,
	"khang_best": 0, "khang_turns": 0,
	"race_best_team": 0.0, "race_best_solo": 0.0, "race_wins": 0, "races": 0,
	"kite_best": 0.0, "kites": 0,
	"oaq_wins": 0, "oaq_losses": 0, "oaq_draws": 0,
	"hs_games": 0, "hs_found": 0, "hs_all_found": 0,
	"goals": 0,
	"play_seconds": 0.0,
}
var last_saved: String = ""
var _timer: float = 0.0
var _disabled: bool = false
var _toast: Label
var _toast_t: float = 0.0


func _ready() -> void:
	var args := OS.get_cmdline_args()
	_disabled = not enabled or args.has("-s") or args.has("--script")
	_build_toast()
	_connect_games()
	_timer = autosave_seconds
	if not _disabled:
		_load.call_deferred()


func _connect_games() -> void:
	if jump_rope != null:
		jump_rope.turn_over.connect(func(who: String, count: int) -> void:
			if who == "Bạn":
				records.rope_games = int(records.rope_games) + 1
				records.rope_best = maxi(int(records.rope_best), count))
	if tip_cat != null:
		tip_cat.turn_done.connect(func(who: String, points: int, out: bool) -> void:
			if who == "Bạn":
				records.khang_turns = int(records.khang_turns) + 1
				if not out:
					records.khang_best = maxi(int(records.khang_best), points))
	if boat_race != null:
		boat_race.finished.connect(func(place: int, time: float) -> void:
			records.races = int(records.races) + 1
			if place == 1:
				records.race_wins = int(records.race_wins) + 1
			if time > 0.0:
				var key := "race_best_solo" if boat_race.mode == "solo" else "race_best_team"
				var best := float(records[key])
				records[key] = time if best <= 0.0 else minf(best, time))
	if kite != null:
		kite.finished.connect(func(h: float, _s: float, _r: String) -> void:
			records.kites = int(records.kites) + 1
			records.kite_best = maxf(float(records.kite_best), h))
	if o_an_quan != null:
		o_an_quan.finished.connect(func(ps: int, ns: int) -> void:
			if not o_an_quan.over:
				return            # bỏ dở giữa ván thì không tính
			if ps > ns:
				records.oaq_wins = int(records.oaq_wins) + 1
			elif ps < ns:
				records.oaq_losses = int(records.oaq_losses) + 1
			else:
				records.oaq_draws = int(records.oaq_draws) + 1)
	if hide_seek != null:
		hide_seek.finished.connect(func(found: int, _escaped: int, total: int) -> void:
			records.hs_games = int(records.hs_games) + 1
			records.hs_found = int(records.hs_found) + found
			if total > 0 and found >= total:
				records.hs_all_found = int(records.hs_all_found) + 1)
	if football != null:
		football.goal_scored.connect(func(_team: int, by_player: bool) -> void:
			if by_player:
				records.goals = int(records.goals) + 1)


func _process(delta: float) -> void:
	records.play_seconds = float(records.play_seconds) + delta
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		_toast.visible = _toast_t > 0.0
	if _disabled or autosave_seconds <= 0.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = autosave_seconds
		save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _disabled:
		save()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("new_game"):
		reset()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("save_game"):
		if _disabled:
			_show_toast("Đang chạy thử: không lưu")
		else:
			save()
			_show_toast("Đã lưu game")
		get_viewport().set_input_as_handled()


# --- Gói / mở dữ liệu ------------------------------------------------------------------------------

## Toàn bộ dữ liệu cần lưu thành một từ điển (JSON được).
func snapshot() -> Dictionary:
	var d := {"version": VERSION, "saved_at": Time.get_datetime_string_from_system(false, true)}
	if calendar != null:
		d["jd"] = calendar.jd
	if day_night != null:
		d["hour"] = day_night.time_of_day
		d["auto_run"] = day_night.auto_run
	if weather != null:
		d["weather"] = weather.kind
	if outdoor_rig != null:
		var f := outdoor_rig.global_position
		d["camera"] = {"focus": [f.x, f.z], "yaw": outdoor_rig.yaw_deg, "distance": outdoor_rig.distance}
	if fishing != null:
		d["fish_log"] = fishing._log.duplicate(true)
		d["fish_total"] = fishing._total
		d["basket"] = fishing.basket.duplicate(true)
	if quests != null:
		d["gifts"] = quests.gifts.duplicate()
		d["quests_done"] = quests.done_count
	if dialogue != null:
		var met := {}
		for v: Variant in dialogue._met:
			if is_instance_valid(v) and v is Villager:
				met[(v as Villager).display_name] = int(dialogue._met[v])
		d["met"] = met
	if market != null:
		d["money"] = market.money
		d["bag"] = market.bag.duplicate()
	d["records"] = records.duplicate()
	return d


## Nạp từ điển đã lưu vào các phần của game.
func apply(d: Dictionary) -> void:
	if calendar != null and d.has("jd"):
		calendar.set_jd(int(d.jd))
	if day_night != null and d.has("hour"):
		day_night.time_of_day = float(d.hour)
		day_night.auto_run = bool(d.get("auto_run", day_night.auto_run))
	if weather != null and d.has("weather"):
		weather.set_weather(str(d.weather), true)
	if outdoor_rig != null and d.has("camera"):
		var c: Dictionary = d.camera
		var f: Array = c.get("focus", [0.0, 0.0])
		outdoor_rig.set_focus(Vector3(float(f[0]), 0.0, float(f[1])))
		outdoor_rig.yaw_deg = float(c.get("yaw", outdoor_rig.yaw_deg))
		outdoor_rig.distance = float(c.get("distance", outdoor_rig.distance))
		outdoor_rig.snap()
	if fishing != null:
		var lg: Dictionary = d.get("fish_log", {})
		fishing._log.clear()
		for k: String in lg:
			var r: Dictionary = lg[k]
			fishing._log[k] = {"count": int(r.get("count", 0)), "best": float(r.get("best", 0.0))}
		fishing._total = int(d.get("fish_total", 0))
		fishing.basket.clear()
		for b: Dictionary in d.get("basket", []):
			fishing.basket.append({"name": str(b.get("name", "")), "kg": float(b.get("kg", 0.0))})
		fishing._update_log()
	if quests != null:
		quests.gifts.clear()
		for g: Variant in d.get("gifts", []):
			quests.gifts.append(str(g))
		quests.done_count = int(d.get("quests_done", quests.gifts.size()))
	if dialogue != null and villagers != null:
		var met: Dictionary = d.get("met", {})
		dialogue._met.clear()
		for v in villagers.people:
			if met.has(v.display_name):
				dialogue._met[v] = int(met[v.display_name])
	if market != null:
		market.money = int(d.get("money", market.money))
		market.bag.clear()
		for it: Variant in d.get("bag", []):
			market.bag.append(str(it))
	var rec: Dictionary = d.get("records", {})
	for k: String in rec:
		if records.has(k):
			records[k] = rec[k]
	if villagers != null:
		villagers.replan()          # dân làng làm việc đúng với giờ vừa nạp


func save() -> bool:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: không ghi được %s" % save_path)
		return false
	f.store_string(JSON.stringify(snapshot(), "\t"))
	f.close()
	last_saved = Time.get_time_string_from_system()
	saved.emit(save_path)
	return true


func _load() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var txt := FileAccess.get_file_as_string(save_path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_warning("SaveGame: file lưu hỏng, bỏ qua")
		return
	apply(parsed as Dictionary)
	loaded.emit(save_path)
	_show_toast("Đã mở lại game đã lưu")


## Ván mới: xoá file lưu (lần mở sau bắt đầu từ đầu) và không tự lưu nữa trong lần chạy này.
func reset() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	_disabled = true
	_show_toast("Đã xoá file lưu — mở lại game để chơi ván mới")


# --- Thông báo nhỏ ---------------------------------------------------------------------------------

func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_toast = Label.new()
	_toast.add_theme_font_override("font", Hud.font(true))
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Palette.FLOWER_YELLOW)
	_toast.add_theme_color_override("font_outline_color", Palette.WINDOW_DARK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 70.0
	_toast.offset_left = -300.0
	_toast.offset_right = 300.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	layer.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.6
	_toast.visible = true
	_toast.modulate.a = 1.0
