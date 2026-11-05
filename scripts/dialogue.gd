class_name Dialogue
extends Node
## Trò chuyện với dân làng (mục 19). Người nhập vai nhìn vào một người và nhấn E:
## người đó dừng việc, quay sang chào; khung thoại hiện ở dưới màn hình, chữ chạy từng chữ;
## chọn câu hỏi bằng phím 1–4 hoặc bấm chuột. Esc để thôi.
## - Xưng hô theo vai vế: cụ / ông / bà / bác / chú / cô / thím gọi người chơi là "cháu",
##   anh / chị gọi là "em", trẻ con xưng "em" (hoặc "cháu") và gọi người chơi là anh / chị.
## - Lời thoại thay đổi theo vai trò, việc đang làm, giờ, thời tiết, trận bóng, giỏ cá
##   người chơi câu được, và nhớ đã gặp nhau chưa.
## - Con vật, người đang đá bóng: chỉ nói một câu ngắn hiện trên đầu (bark).

signal finished

@export var villagers: Villagers
@export var day_night: DayNight
@export var weather: Weather
@export var football: Football
@export var fishing: Fishing
@export var quests: Quests
@export var calendar: LunarCalendar
@export var school_day: SchoolDay
## Người chơi là nữ thì trẻ con gọi "chị", không thì gọi "anh".
@export var player_female: bool = false
@export var chars_per_second: float = 48.0
@export var bark_time: float = 2.6

## Chuyện làng các cụ hay kể (mỗi lần hỏi kể một chuyện khác).
const LORE: Array[String] = [
	"Đình làng mình thờ Thành hoàng, ngày xưa có công đánh giặc giữ làng. Tháng giêng mở hội, rước kiệu quanh làng vui lắm.",
	"Lũy tre này các cụ trồng từ bao đời rồi. Ngày xưa giặc cướp không vào được làng là nhờ nó đấy.",
	"Cây đa đầu làng ấy, hồi {self} còn bé đã to thế rồi. Trẻ con trèo lên hái quả, bị các cụ mắng suốt.",
	"Con sông ôm quanh làng mình như cái móng ngựa. Các cụ bảo thế đất ấy giữ được của, làng mới yên ổn.",
	"Ngày trước làng chưa có trường, trẻ con phải lội bộ sang làng bên mà học. Bây giờ sướng hơn nhiều.",
	"Chùa làng có quả chuông đúc từ đời xưa lắm. Đêm thanh vắng nghe tiếng chuông vọng ra tận bến sông.",
	"Hồi ấy cả làng chỉ có vài cái xe đạp, nhà nào có xe Phượng Hoàng là oai nhất xóm.",
	"Làng mình có lệ: con cháu đi xa về thì ra đình thắp nén hương, báo với Thành hoàng một tiếng.",
]
const ANIMAL_BARKS := {
	"dog": ["Gâu! Gâu!", "Gâu gâu… gừ…", "Ư ử…"],
	"buffalo": ["Ò… ọ…", "Nghé… ọ…"],
	"chicken": ["Cục ta cục tác!", "Ò ó o!", "Chiếp chiếp…"],
	"duck": ["Cạp cạp!", "Cạp… cạp cạp!"],
}

var talking: bool = false
var npc: Villager
var _rng := RandomNumberGenerator.new()
var _met: Dictionary = {}          # Villager → số lần đã nói chuyện
var _lore_index: Dictionary = {}   # Villager → chuyện kể tiếp theo
var _asked: Dictionary = {}        # khoá câu hỏi đã hỏi trong cuộc này
var _options: Array[Dictionary] = []
var _saved_anim: String = ""
var _saved_rot: float = 0.0
var _player: Node3D

# Giao diện
var _panel: PanelContainer
var _name_label: Label
var _text_label: Label
var _opts_box: VBoxContainer
var _typing: float = -1.0
var _barks: Array[Dictionary] = []   # {label, node, t}


func _ready() -> void:
	_rng.randomize()
	_build_ui()


# --- Bắt đầu / kết thúc ---------------------------------------------------------------

## Bắt chuyện với `v`. `player` là nơi người chơi đứng (để NPC quay mặt về).
## Trả về false nếu chỉ nói một câu ngắn (con vật, người đang bận đá bóng).
func start(v: Villager, player: Node3D) -> bool:
	if talking or v == null or not v.visible:
		return false
	if ANIMAL_BARKS.has(v.role):
		var arr: Array = ANIMAL_BARKS[v.role]
		bark(v, arr[_rng.randi_range(0, arr.size() - 1)])
		return false
	if v.work_anim == "sleep":
		bark(v, ["Khò… khò…", "Ư… để mai nói…", "Zzz…"][_rng.randi_range(0, 2)])
		return false
	if football != null and football._find(v) >= 0:
		bark(v, ["Đang đá, nói sau nhé!", "Chuyền đây! Chuyền đây!", "Ra cổ vũ đi!"][_rng.randi_range(0, 2)])
		return false
	talking = true
	npc = v
	_player = player
	_asked.clear()
	_saved_anim = v.work_anim
	_saved_rot = v.rotation.y
	v.set_meta("talking", true)
	v.work_anim = "chat"
	_face_player()
	_name_label.text = v.display_name
	_panel.visible = true
	_say(_greeting(), true)
	_met[_real(v)] = int(_met.get(_real(v), 0)) + 1
	return true


## Người trong nhà là bản sao (IndoorFolk) — nhớ, việc nhờ… tính theo người thật.
static func _real(v: Villager) -> Villager:
	return v.get_meta("proxy_of", v) as Villager


func end() -> void:
	if not talking:
		return
	talking = false
	_panel.visible = false
	if is_instance_valid(npc):
		npc.remove_meta("talking")
		npc.work_anim = _saved_anim
		if npc.state != Villager.State.WALK:
			npc.rotation.y = _saved_rot
	npc = null
	finished.emit()


# --- Điều khiển ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not talking:
		return
	if event.is_action_pressed("exit_interior"):
		end()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("fp_jump"):
		if _typing >= 0.0:
			_finish_typing()
		elif _options.size() == 1:
			_choose(0)
		get_viewport().set_input_as_handled()
		return
	for k in 4:
		if event.is_action_pressed("dialog_%d" % (k + 1)):
			if _typing >= 0.0:
				_finish_typing()
			if k < _options.size():
				_choose(k)
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	if talking:
		if not is_instance_valid(npc) or not npc.visible:
			end()
		else:
			_face_player()
			if _typing >= 0.0:
				_typing += delta * chars_per_second
				_text_label.visible_characters = int(_typing)
				if _typing >= _text_label.get_total_character_count():
					_finish_typing()
	for i in range(_barks.size() - 1, -1, -1):
		var b: Dictionary = _barks[i]
		b.t = float(b.t) - delta
		var l: Label3D = b.label
		if float(b.t) <= 0.0 or not is_instance_valid(b.node):
			l.queue_free()
			_barks.remove_at(i)
		else:
			l.global_position = (b.node as Node3D).global_position + Vector3(0, 2.15, 0)
			l.modulate.a = clampf(float(b.t) / 0.4, 0.0, 1.0)


func _face_player() -> void:
	if _player == null:
		return
	var d := _player.global_position - npc.global_position
	if Vector2(d.x, d.z).length() > 0.1:
		npc.rotation.y = lerp_angle(npc.rotation.y, atan2(d.x, d.z), 0.2)


## Câu ngắn hiện trên đầu một người / con vật.
func bark(v: Node3D, text: String) -> void:
	for b in _barks:
		if b.node == v:
			(b.label as Label3D).text = text
			b.t = bark_time
			return
	var l := Label3D.new()
	l.text = text
	l.font = Hud.font(true)
	l.font_size = 40
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Palette.HUD_TEXT
	l.outline_modulate = Palette.WINDOW_DARK
	l.outline_size = 10
	l.no_depth_test = true
	add_child(l)
	l.global_position = v.global_position + Vector3(0, 2.15, 0)
	_barks.append({"label": l, "node": v, "t": bark_time})


# --- Nói, hỏi, đáp ------------------------------------------------------------------------

func _say(text: String, then_options: bool) -> void:
	_text_label.text = _fill(text)
	_text_label.visible_characters = 0
	_typing = 0.0
	for c in _opts_box.get_children():
		c.queue_free()
	_options.clear()
	if then_options:
		_options = _build_options()


func _finish_typing() -> void:
	_typing = -1.0
	_text_label.visible_characters = -1
	_show_options()


func _show_options() -> void:
	for c in _opts_box.get_children():
		c.queue_free()
	for i in _options.size():
		var b := Button.new()
		b.text = "%d.  %s" % [i + 1, _fill(str(_options[i].text))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.add_theme_font_override("font", Hud.font(false))
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", Palette.HUD_SUBTEXT)
		b.add_theme_color_override("font_hover_color", Palette.FLOWER_YELLOW)
		b.add_theme_color_override("font_pressed_color", Palette.FLOWER_YELLOW)
		b.pressed.connect(_choose.bind(i))
		_opts_box.add_child(b)


func _choose(i: int) -> void:
	if i < 0 or i >= _options.size():
		return
	var o: Dictionary = _options[i]
	if o.has("key"):
		_asked[o.key] = true
	if o.get("bye", false):
		_say(_farewell(), false)
		_options = [{"text": "(Đi tiếp)", "end": true}]
		return
	if o.get("end", false):
		end()
		return
	var text: String = (o.answer as Callable).call()
	if o.has("next"):
		# Câu trả lời kèm lựa chọn riêng (vd. nhận / từ chối việc nhờ)
		_say(text, false)
		_options.assign((o.next as Callable).call())
		return
	_say(text, true)


## Các câu người chơi có thể hỏi lúc này (bỏ câu đã hỏi), luôn có câu chào ra về ở cuối.
func _build_options() -> Array[Dictionary]:
	var v := npc
	var out: Array[Dictionary] = []
	# Việc nhờ / báo việc xong / nhắn tin luôn đứng đầu
	if quests != null:
		out.assign(quests.dialog_options(_real(v)))
	var all: Array[Dictionary] = []
	all.append({"key": "doing", "text": "{Npc} đang làm gì đấy{a}?", "answer": _ans_doing})
	match v.role:
		"farmer":
			all.append({"key": "rice", "text": "Lúa năm nay thế nào{a}?", "answer": _ans_rice})
		"carrier":
			all.append({"key": "market", "text": "Chợ phiên có gì vui không{a}?", "answer": _ans_market})
		"elder":
			all.append({"key": "lore", "text": "{Npc} kể chuyện làng ngày xưa đi{a}.", "answer": _ans_lore})
		"kid":
			all.append({"key": "ball", "text": "Chiều nay có đi đá bóng không?", "answer": _ans_ball})
			all.append({"key": "school", "text": "Đi học có vui không em?", "answer": _ans_school})
		"herder":
			all.append({"key": "buffalo", "text": "Con trâu nhà em mấy tuổi rồi?", "answer": _ans_buffalo})
	if fishing != null and fishing._total > 0:
		all.append({"key": "catch", "text": "{Npc} xem giỏ cá {me} câu được này!", "answer": _ans_catch})
	if football != null and football.phase != Football.Phase.IDLE and v.role != "kid":
		all.append({"key": "match", "text": "Trận bóng thế nào rồi{a}?", "answer": _ans_match})
	if calendar != null:
		all.append({"key": "date", "text": "Hôm nay là ngày bao nhiêu âm lịch{a}?", "answer": _ans_date})
	all.append({"key": "weather", "text": "Trời thế này có mưa không{a}?", "answer": _ans_weather})
	all.append({"key": "home", "text": "Nhà {npc} ở đâu{a}?", "answer": _ans_home})
	for o in all:
		if not _asked.has(o.key) and out.size() < 3:
			out.append(o)
	out.append({"text": "Thôi, {me} chào {npc}{a}.", "bye": true})
	return out


# --- Lời thoại -----------------------------------------------------------------------------

func _hour() -> float:
	return day_night.time_of_day if day_night != null else 17.0


func _pick(arr: Array) -> String:
	return str(arr[_rng.randi_range(0, arr.size() - 1)])


func _greeting() -> String:
	var v := npc
	var h := _hour()
	var times: int = _met.get(_real(v), 0)
	var at_home := str(v.activity).begins_with("home_")
	var kid := v.role in ["kid", "herder"]
	if times > 0:
		if kid:
			return _pick(["Lại là {you} ạ? Hì hì.", "{You} lại tìm {self} ạ?"])
		return _pick(["Lại là {you} đấy à? Còn chuyện gì nữa thế?", "Ơ, {you} vẫn loanh quanh ở đây à?",
				"{You} lại sang chơi đấy à?"])
	if at_home and not kid:
		return _pick(["Ơ, {you} sang chơi đấy à? Vào đây ngồi uống nước chè.", "{You} đấy à? Vào nhà đi, ngồi chơi đã.",
				"Ai như {you}! Vào đây, {self} vừa pha ấm chè mới."])
	if kid:
		var g := "{Self} chào {you} ạ!"
		if v.in_uniform and v.activity == "school" and v.state == Villager.State.WALK:
			g += " {Self} đang đi học, sắp muộn rồi ạ!"
		elif v.in_uniform:
			g += " " + _pick(["{Self} vừa đi học về.", "Hôm nay {self} được điểm mười đấy!"])
		return g
	if v.activity in ["worship", "dinh_worship"] and calendar != null:
		var lw := LunarCalendar.lunar_day_words(int(calendar.lunar().day))
		return _pick(["Hôm nay %s, {self} ra đình thắp hương đây. {You} có ra không?" % lw,
				"Ơ {you}! %s rồi, đi lễ đình với {self} không?" % lw.capitalize()])
	if h >= 19.0 or h < 5.0:
		return _pick(["Tối rồi mà {you} còn đi đâu đấy?", "Ai đấy? À, {you} à. Tối thế này đi đâu?"])
	if v.role == "elder":
		return _pick(["À, {you} đấy à. Lại đây {self} hỏi chuyện tí nào.", "{You} về quê chơi đấy à? Lớn quá, {self} suýt không nhận ra."])
	if h < 10.0:
		return _pick(["Sáng sớm đã đi đâu đấy {you}?", "Chào {you}! Sáng nay trời {wx} nhỉ."])
	if h < 13.5:
		return _pick(["Trưa nắng thế này {you} đi đâu thế?", "Ăn cơm chưa {you}?"])
	return _pick(["Chiều rồi đấy {you} ạ. Đi chơi đâu đấy?", "Ơ, {you}! Đi đâu đấy?"])


func _farewell() -> String:
	var h := _hour()
	if npc.role in ["kid", "herder"]:
		return _pick(["{Self} chào {you} ạ! Mai {you} lại ra chơi nhé!", "Vâng ạ, {self} chào {you}!"])
	if h >= 19.0 or h < 5.0:
		return "Ừ, tối rồi, về sớm kẻo nhà mong {you} ạ."
	if weather != null and weather.kind == "drizzle":
		return "Ừ, đi đâu thì nhớ đội nón kẻo ướt nhé."
	return _pick(["Ừ, đi chơi vui nhé {you}.", "Ừ, lúc nào rảnh sang nhà {self} uống nước chè.", "Ừ, chào {you}."])


func _ans_doing() -> String:
	var v := npc
	match v.activity:
		"field":
			if v.role != "farmer":
				return "{Self} mang cơm ra đồng cho người nhà đấy."
			return _pick(["{Self} đang làm cỏ lúa. Lúa đang thì con gái, phải chăm cho kỹ.",
					"Ra thăm ruộng xem nước nôi thế nào. Ruộng mà khô là phải tát nước vào ngay."])
		"graze":
			return "{Self} chăn trâu ngoài bãi. Con trâu này hiền lắm, nhưng thấy cỏ non là nó chạy mất."
		"well":
			return "Gánh nước giếng làng về nấu cơm. Nước giếng làng trong lắm, mát nhất vùng đấy."
		"banyan":
			return _pick(["Ngồi gốc đa hóng mát thôi. Ở đây gió từ đồng thổi vào, mát hơn trong nhà.",
					"Chờ mấy ông bạn già ra đánh cờ tướng."])
		"pagoda":
			return "{Self} lên chùa thắp hương. Mồng một, ngày rằm chùa đông lắm."
		"dinh":
			if v.role in ["kid", "herder"]:
				return "Chơi ở sân đình ạ! Bọn {self} đang chơi đánh khăng, {you} chơi không?"
			return "Ra đình xem có việc gì của làng không."
		"pond":
			if v.role in ["kid", "herder"]:
				return "Ra ao xem vịt bơi! Hôm qua {self} thấy một con cá to tướng nhảy lên."
			return "Ra ao rửa mấy cái rổ rá."
		"visit":
			return "Sang nhà hàng xóm uống bát nước chè, nói chuyện mùa màng."
		"yard":
			return _pick(["Làm mấy việc vặt ngoài sân: phơi thóc, quét lá.", "Đan lại cái rổ bị thủng."])
		"lantern":
			return "Đi chơi tối, cầm cái đèn cho khỏi vấp. Ngõ làng tối om."
		"river":
			return "Ra bến giặt quần áo. Nước sông mát, giặt một lúc là xong."
		"swim":
			return "Tắm sông ạ! Mà {you} đừng mách mẹ {self} nhé."
		"fishing":
			return "Ngồi câu cho vui. Khúc sông này nhiều cá chép, có hôm {self} câu được con hơn hai cân."
		"school":
			if school_day != null:
				match school_day.phase(_hour()):
					"recess": return "Ra chơi ạ! {Self} đang chơi đuổi bắt, trống vào lớp là phải chạy vào ngay."
					"flag": return "Đang chào cờ ạ, {you} đứng nghiêm đi!"
					"leave": return "Tan học rồi ạ! {Self} về nhà ăn cơm."
					"off": return "Hôm nay {self} được nghỉ học ạ!" if calendar != null and not calendar.is_school_day() else "{Self} vừa tan học ạ."
			return "{Self} đi học ạ! Hôm nay học tập đọc với làm tính."
		"football":
			if v.role in ["kid", "herder"]:
				return "{Self} xem các anh đá bóng ạ. " + _score_text()
			return "Ra xem bọn trẻ đá bóng. " + _score_text()
		"inside", "shelter":
			return "Đang định về nhà đây."
		"home_tea":
			return _pick(["Ngồi uống bát nước chè cho ấm bụng. {You} ngồi xuống đây uống với {self} một chén.",
					"Uống chén chè xanh, nhâm nhi tí cho đỡ mỏi."])
		"home_rest":
			return "Nghỉ lưng một tí, cả ngày ngoài đồng mỏi quá." if not v.role in ["kid", "herder"] else "{Self} nằm chơi tí ạ, lát nữa {self} đi tắm."
		"home_weave":
			return "Dệt nốt tấm vải này để phiên chợ tới mang ra bán."
		"home_mill":
			return "Xay mẻ thóc để mai còn giã gạo nấu cơm."
		"home_study":
			return "{Self} đang làm bài tập về nhà ạ, mai cô giáo kiểm tra."
		"home_pray":
			return "Thắp nén hương cho các cụ. Nhà nào cũng thế, sáng tối thắp hương ông bà."
		"pagoda_pray":
			return "{Self} đang lễ Phật, cầu cho cả nhà mạnh khoẻ, mùa màng tốt tươi."
		"dinh_pray":
			return "Thắp hương Thành hoàng làng, xin cho làng mình yên ổn."
		"dinh_meet":
			return "Ngồi bàn chuyện làng với các cụ: sắp tới hội làng phải lo nhiều việc lắm."
		"class":
			return "Đang học ạ! Suỵt, {you} nói khẽ thôi kẻo cô giáo nhắc."
		"monk_chant":
			return _pick(["{Self} đang tụng kinh, cầu cho dân làng bình an, mưa thuận gió hoà.",
					"Sáng nào {self} cũng tụng một thời kinh. {You} có muốn thắp nén hương thì cứ tự nhiên."])
		"worship", "dinh_worship":
			var lw := LunarCalendar.lunar_day_words(int(calendar.lunar().day)) if calendar != null else "rằm"
			return _pick(["Hôm nay %s, {self} ra đình thắp nén hương cầu cho cả nhà mạnh khoẻ." % lw,
					"%s thì phải ra đình lễ Thành hoàng chứ {you}. Làng mình xưa nay vẫn thế." % lw.capitalize()])
		"teach":
			return "Cô đang dạy các em bài tập đọc. Cháu ngồi xuống cuối lớp nghe cùng cũng được."
		"dinh_keep":
			return "Ông trông đình, sáng tối thắp hương Thành hoàng, quét dọn sân đình. Hội làng sắp tới bận lắm."
	return "Cũng chẳng làm gì, đi loanh quanh thôi."


func _ans_rice() -> String:
	var h := _hour()
	var s := _pick(["Năm nay mưa thuận gió hoà, chắc được mùa đấy {you} ạ.",
			"Lúa đang thì con gái, tháng sau là trổ bông. Chỉ sợ cuối vụ có bão."])
	if h >= 16.0:
		s += " Chiều mát thế này ra đồng là sướng nhất."
	return s


func _ans_market() -> String:
	return _pick(["Chợ làng họp phiên sáng mồng năm, có bánh đúc, kẹo kéo, có cả hàng xén. Trẻ con mê lắm.",
			"Phiên chợ vừa rồi rau muống rẻ như cho. {Self} gánh ra mà bán chẳng được bao nhiêu."])


func _ans_lore() -> String:
	var i: int = _lore_index.get(npc, _rng.randi_range(0, LORE.size() - 1))
	_lore_index[npc] = (i + 1) % LORE.size()
	_asked.erase("lore")    # còn hỏi tiếp được
	return LORE[i]


func _ans_ball() -> String:
	var h := _hour()
	if football != null and football.phase != Football.Phase.IDLE:
		return "Đang đá đấy ạ! " + _score_text() + " {You} ra cổ vũ đi!"
	if h >= 16.0 and h < 18.6:
		return "Có ạ! Chiều nào xóm Đông cũng đá với xóm Đoài ở sân bóng góc làng. Bọn xóm Đoài cởi trần đá hăng lắm!"
	if h < 16.0:
		return "Chiều tan học mới đá cơ ạ, giờ này nắng lắm."
	return "Tối rồi, mẹ {self} không cho ra sân đâu ạ."


func _ans_school() -> String:
	return _pick(["Vui ạ! Cô giáo {self} hiền lắm. Nhưng {self} sợ nhất là bị gọi lên bảng.",
			"Vui ạ. Giờ ra chơi bọn {self} chơi nhảy dây với đá cầu ở sân trường."])


func _ans_buffalo() -> String:
	return "Con này lên năm rồi ạ. Nó khoẻ nhất xóm, cày một buổi không biết mệt!"


func _ans_catch() -> String:
	var best := ""
	var best_kg := 0.0
	for name_s: String in fishing._log:
		var rec: Dictionary = fishing._log[name_s]
		if float(rec.best) > best_kg:
			best_kg = float(rec.best)
			best = name_s
	var kg := ("%.1f" % best_kg).replace(".", ",")
	if npc.role in ["kid", "herder"]:
		return "Oa! Con %s %s cân cơ ạ? {You} giỏi thế!" % [best.to_lower(), kg]
	if best_kg >= 2.0:
		if npc.role == "elder" or npc.activity == "fishing":
			return "Chà, con %s những %s cân! {Self} câu cả đời mới được vài con to như thế." % [best.to_lower(), kg]
		return "Chà, con %s những %s cân! Mang về nấu canh chua thì ngon phải biết." % [best.to_lower(), kg]
	return "Được %d con cơ à? Con to nhất là %s, %s cân. Thế là khá rồi đấy." % [fishing._total, best.to_lower(), kg]


func _ans_match() -> String:
	return _score_text() + " " + _pick(["Bọn xóm Đoài cởi trần đá hăng lắm.", "Thằng thủ môn xóm Đông bắt bóng như mèo vồ chuột."])


func _ans_weather() -> String:
	var k := weather.kind if weather != null else "clear"
	match k:
		"cloudy": return "Mây kéo đen kịt thế kia, chắc chiều nay mưa đấy."
		"drizzle": return "Mưa phùn lất phất thế này thì đi đâu cũng phải đội nón."
		"fog": return "Sương dày quá, đi đường cẩn thận kẻo lạc sang làng bên đấy."
		"storm": return "Giông to thế này, về nhà mau lên!"
	return "Nắng ráo thế này thì còn lâu mới mưa. Phơi thóc được đấy."


func _ans_date() -> String:
	var l := calendar.lunar()
	var words := calendar.lunar_words()
	var hn := calendar.holiday_name()
	var t := "Hôm nay %s, tức là %s %s đấy." % [words, calendar.weekday_name().to_lower(), calendar.solar_text()]
	if npc.role in ["kid", "herder"]:
		t = "Hôm nay là %s ạ, %s." % [words, calendar.weekday_name().to_lower()]
	if hn == "Rằm" or hn == "Mùng một":
		t += " " + _pick(["Ngày lễ đấy, sáng nay cả làng ra đình thắp hương.", "Chiều nay {self} cũng ra đình thắp nén hương."])
	elif hn != "":
		t += " Hôm nay là %s, vui lắm!" % hn
	else:
		var d := int(l.day)
		var to_next := (15 - d) if d < 15 else (30 - d + 1)
		if to_next <= 3:
			t += " " + ("Sắp rằm rồi, " if d < 15 else "Sắp mùng một rồi, ") + "lại chuẩn bị ra đình thắp hương."
	return t


func _ans_home() -> String:
	if npc.has_meta("pupil"):
		return "Nhà {self} ở làng bên ạ, đi bộ theo đường đất qua mấy cánh đồng là tới."
	var home_name := str(npc.home.get("name", "")).to_lower()
	if str(npc.home.get("key", "")) == "main":
		return "Nhà {self} ngay cạnh ruộng đầu làng đấy, cái nhà ngói có cây đa ấy."
	return "Nhà {self} là cái %s ở trong làng. Lúc nào rảnh sang chơi uống nước chè." % home_name


func _score_text() -> String:
	if football == null or football.phase == Football.Phase.IDLE:
		return "Chờ mọi người ra đủ thì đá."
	return "Xóm Đông %d, xóm Đoài %d." % [football.score[0], football.score[1]]


# --- Xưng hô ---------------------------------------------------------------------------------

## {self}: NPC tự xưng; {you}: NPC gọi người chơi; {npc}: người chơi gọi NPC;
## {me}: người chơi tự xưng; {a}: " ạ" khi nói với người lớn hơn. Viết hoa: {Self}, {You}, {Npc}.
func _kin() -> Dictionary:
	var v := npc
	if v == null:
		return {"self": "tôi", "you": "bạn", "npc": "bạn", "me": "tôi", "a": ""}
	var words := v.display_name.split(" ")
	var title := words[0].to_lower()
	var big := "chị" if player_female else "anh"
	match title:
		"sư":
			# Sư cụ xưng "thầy", gọi người chơi là "con"
			return {"self": "thầy", "you": "con", "npc": "sư cụ", "me": "con", "a": " ạ"}
		"cụ":
			# Cụ ông / cụ bà: người chơi gọi "cụ", cụ tự xưng "ông" / "bà"
			var me_word := words[1].to_lower() if words.size() > 2 else "ông"
			return {"self": me_word, "you": "cháu", "npc": "cụ", "me": "cháu", "a": " ạ"}
		"ông", "bà", "bác", "chú", "cô", "thím":
			return {"self": title, "you": "cháu", "npc": title, "me": "cháu", "a": " ạ"}
		"anh", "chị":
			return {"self": title, "you": "em", "npc": title, "me": "em", "a": " ạ"}
	# Trẻ con
	return {"self": "em", "you": big, "npc": "em", "me": big, "a": ""}


func _fill(text: String) -> String:
	var k := _kin()
	var wx := "đẹp"
	if weather != null:
		wx = {"clear": "đẹp", "cloudy": "âm u", "drizzle": "lất phất mưa", "fog": "nhiều sương", "storm": "giông"}.get(weather.kind, "đẹp")
	var out := text
	for key: String in ["self", "you", "npc", "me"]:
		var val: String = k[key]
		out = out.replace("{" + key + "}", val)
		out = out.replace("{" + key.capitalize() + "}", val.substr(0, 1).to_upper() + val.substr(1))
	out = out.replace("{a}", k.a).replace("{wx}", wx)
	return out


# --- Giao diện ------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -100
	_panel.offset_left = -470
	_panel.offset_right = 470
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.HUD_BG, 0.82)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.border_color = Color(Palette.FLOWER_YELLOW, 0.5)
	sb.border_width_top = 2
	_panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_name_label = Label.new()
	_name_label.add_theme_font_override("font", Hud.font(true))
	_name_label.add_theme_font_size_override("font_size", 21)
	_name_label.add_theme_color_override("font_color", Palette.FLOWER_YELLOW)
	box.add_child(_name_label)
	_text_label = Label.new()
	_text_label.add_theme_font_override("font", Hud.font(false))
	_text_label.add_theme_font_size_override("font_size", 19)
	_text_label.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(880, 52)
	box.add_child(_text_label)
	_opts_box = VBoxContainer.new()
	_opts_box.add_theme_constant_override("separation", 0)
	box.add_child(_opts_box)
	var hint := Label.new()
	hint.text = "1–4 / bấm chuột: chọn    E: nói nhanh    Esc: thôi"
	hint.add_theme_font_override("font", Hud.font(false))
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(Palette.HUD_SUBTEXT, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)
	_panel.visible = false


# --- Công cụ kiểm tra ------------------------------------------------------------------------

## In một cuộc trò chuyện (chọn lần lượt các câu hỏi) — dùng cho tools/talk_test.gd.
func transcript(v: Villager, player: Node3D, picks: int = 3) -> String:
	if not start(v, player):
		return "(%s) %s" % [v.display_name, _barks[_barks.size() - 1].label.text if not _barks.is_empty() else ""]
	var lines: Array[String] = ["%s: %s" % [v.display_name, _text_label.text]]
	for i in picks + 1:
		if not talking:
			break
		if _options.is_empty():
			break
		var idx := 0 if i < picks else _options.size() - 1
		lines.append("  > " + _fill(str(_options[idx].text)))
		_choose(idx)
		if talking and not _text_label.text.is_empty():
			lines.append("%s: %s" % [v.display_name, _text_label.text])
		if talking and _options.size() == 1 and _options[0].get("end", false):
			_choose(0)
	end()
	return "\n".join(lines)
