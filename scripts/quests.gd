class_name Quests
extends Node3D
## Dân làng nhờ việc (mục 20). Một vài người có dấu "!" trên đầu: nói chuyện và hỏi
## "có cần giúp gì không" thì họ nhờ một việc vặt; nhận lời thì việc hiện ở khung "Việc được nhờ",
## mỗi bước có dấu chỉ đường (hình thoi vàng + khoảng cách). Xong việc quay lại báo → được quà.
## Các loại việc (dùng lại những gì trong game đã có):
## - water:   múc nước ở giếng làng → gánh về nhà người nhờ (đi chậm lại) → báo.
## - message: chạy sang nhắn một người khác → báo lại.
## - fish:    câu một con cá đúng loài ở bến sông (Fishing.basket) → mang tới.
## - lost:    tìm đồ đánh rơi quanh một chỗ (gốc đa, bờ ao, sân đình…) → mang trả.
## - goal:    (trẻ con thách) sút một quả vào lưới ở sân bóng → báo.
## Người cần gặp đang ở trong nhà thì tới trước cổng nhà họ sẽ ra (`Villagers.call_out`).

signal changed

@export var village: Village
@export var river: River
@export var football: Football
@export var fishing: Fishing
@export var villagers: Villagers
@export var first_person: FirstPerson
@export var outdoor_rig: CameraRig
@export var dialogue: Dialogue
@export var hud: Hud
@export var random_seed: int = 0          # 0 = mỗi lần chơi một khác

@export_group("Nhịp")
@export_range(1, 5) var max_active: int = 3
## Số người đang có việc muốn nhờ (dấu "!").
@export_range(0, 12) var max_offers: int = 5
@export var offer_refresh: float = 30.0
## Tới gần chỗ cần đến trong bán kính này là xong bước "đi tới".
@export var arrive_radius: float = 2.4
## Gánh nước thì đi chậm lại.
@export_range(0.3, 1.0) var carry_speed: float = 0.7

const GIFTS := {
	"farmer": ["rổ khoai lang", "bó rau muống", "chục trứng gà"],
	"carrier": ["nải chuối tiêu", "gói xôi lạc", "mấy cái bánh đa"],
	"elder": ["gói chè Thái", "đĩa kẹo lạc", "túi ổi chín"],
	"kid": ["con quay gỗ", "con diều giấy", "mấy viên bi"],
	"herder": ["chùm sim chín", "cây sáo trúc"],
}
## [lời người nhờ dặn, lời người chơi nhắn lại (sau "X nhắn {npc}")].
const MESSAGES: Array = [
	["tối nay sang nhà {self} ăn giỗ", "tối nay sang ăn giỗ"],
	["mai cho {self} mượn cái bừa", "mai cho mượn cái bừa"],
	["chiều mai họp xóm ở đình, nhớ ra sớm", "chiều mai họp xóm ở đình, nhớ ra sớm"],
	["{self} có gói chè ngon, rảnh thì sang uống nước", "có gói chè ngon, rảnh thì sang uống nước"],
	["sáng mai đi chợ phiên thì rủ {self} đi cùng", "sáng mai đi chợ phiên thì rủ đi cùng"],
]
const FISH_KINDS: Array[String] = ["Cá chép", "Cá chép đỏ", "Cá diếc", "Cá trắm cỏ", "Cá trê", "Cá mè trắng"]
## Đồ đánh rơi theo vai người nhờ: [tên, kiểu hình]
const LOST_ITEMS := {
	"elder": [["cái nón lá", "hat"], ["cái điếu cày", "pipe"]],
	"farmer": [["con dao quắm", "knife"], ["cái nón lá", "hat"]],
	"carrier": [["cái quạt nan", "fan"], ["cái nón lá", "hat"]],
	"kid": [["con quay gỗ", "top"], ["quả cầu đá", "shuttle"]],
	"herder": [["cái sáo trúc", "pipe"], ["con quay gỗ", "top"]],
}
const KINDS_BY_ROLE := {
	"farmer": ["water", "message", "fish", "lost"],
	"carrier": ["water", "message", "fish", "lost"],
	"elder": ["water", "message", "fish", "lost"],
	"kid": ["lost", "goal"],
	"herder": ["lost", "goal"],
}

var active: Array[Dictionary] = []
var items: Array[String] = []       # đồ đang cầm (đôi thùng nước, đồ nhặt được)
var gifts: Array[String] = []       # quà đã nhận
var done_count: int = 0

var _rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _offer_timer: float = 2.0
var _ui_timer: float = 0.0
var _toast_timer: float = 0.0

# Giao diện
var _panel: PanelContainer
var _list: Label
var _toast_panel: PanelContainer
var _toast: Label
var _diamond_mesh: ArrayMesh
var _marker_mat: StandardMaterial3D


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.vertex_color_use_as_albedo = true
	_marker_mat.vertex_color_is_srgb = true
	_marker_mat.no_depth_test = true
	_marker_mat.render_priority = 10
	var mb := MeshBuilder.new(5, 0.0)
	mb.add_pyramid(0.22, 0.3, 4, Palette.FLOWER_YELLOW)
	mb.add_pyramid(0.22, 0.3, 4, Palette.FLOWER_YELLOW.darkened(0.2), Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO))
	_diamond_mesh = mb.commit(_marker_mat)
	_build_ui()
	if football != null:
		football.goal_scored.connect(_on_goal)


# --- Người có việc muốn nhờ -----------------------------------------------------------

func _refresh_offers() -> void:
	if villagers == null:
		return
	var count := 0
	for v in villagers.people:
		if v.has_meta("quest_offer"):
			count += 1
	var tries := 0
	while count < max_offers and tries < 40:
		tries += 1
		var v: Villager = villagers.people[_rng.randi_range(0, villagers.people.size() - 1)]
		if not v.visible or v.has_meta("quest_offer") or _quest_of_giver(v) != null:
			continue
		if not KINDS_BY_ROLE.has(v.role) or (football != null and football._find(v) >= 0):
			continue
		var kinds: Array = KINDS_BY_ROLE[v.role]
		var q := make_quest(v, str(kinds[_rng.randi_range(0, kinds.size() - 1)]))
		if q.is_empty():
			continue
		v.set_meta("quest_offer", q)
		_add_offer_mark(v)
		count += 1


func _add_offer_mark(v: Villager) -> void:
	var l := Label3D.new()
	l.name = "QuestMark"
	l.text = "!"
	l.font = Hud.font(true)
	l.font_size = 96
	l.pixel_size = 0.007
	l.modulate = Palette.FLOWER_YELLOW
	l.outline_modulate = Palette.WINDOW_DARK
	l.outline_size = 16
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 1.55 if v.role in ["kid", "herder"] else 2.25
	l.visibility_range_end = 55.0
	v.add_child(l)


func _clear_offer(v: Villager) -> void:
	if v.has_meta("quest_offer"):
		v.remove_meta("quest_offer")
	var m := v.get_node_or_null("QuestMark")
	if m != null:
		m.queue_free()


func _quest_of_giver(v: Villager) -> Variant:
	for q in active:
		if q.giver == v:
			return q
	return null


# --- Tạo việc ---------------------------------------------------------------------------

static func _lower_first(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1)


## Một việc nhờ của `giver` (kind: water | message | fish | lost | goal). Rỗng nếu không tạo được.
func make_quest(giver: Villager, kind: String) -> Dictionary:
	var g := _lower_first(giver.display_name)
	var kid := giver.role in ["kid", "herder"]
	var q := {"id": _next_id, "kind": kind, "giver": giver, "i": 0, "nodes": [], "marker": null}
	var gift_list: Array = GIFTS.get(giver.role, ["gói kẹo"])
	q.gift = str(gift_list[_rng.randi_range(0, gift_list.size() - 1)])
	var report := {"type": "talk", "npc": giver, "desc": "Về báo cho %s" % g}
	match kind:
		"water":
			if village == null:
				return {}
			var home_front: Vector3 = giver.home.get("front", giver.global_position)
			q.title = "Gánh nước cho %s" % g
			q.ask = _pick(["{You} gánh giúp {self} đôi nước ở giếng làng về đổ vào chum nhà {self} được không? Dạo này {self} đau lưng quá.",
					"Chum nhà {self} cạn rồi. {You} ra giếng làng gánh giúp {self} đôi nước nhé?"])
			q.steps = [
				{"type": "pickup", "item": "Đôi thùng nước", "hint": "Múc nước", "desc": "Múc nước ở giếng làng",
						"pos": village.well_position + Vector3(1.1, 0.0, 0.0), "model": "well"},
				{"type": "goto", "pos": home_front, "consume": "Đôi thùng nước", "desc": "Gánh nước về nhà %s" % g,
						"toast": "Đổ nước đầy chum nhà %s rồi!" % g},
				report.merged({"text": "{Me} gánh nước đầy chum cho {npc} rồi{a}!"}),
			]
		"message":
			var target := _pick_person(giver)
			if target == null:
				return {}
			var t := _lower_first(target.display_name)
			var msg: Array = MESSAGES[_rng.randi_range(0, MESSAGES.size() - 1)]
			q.title = "Nhắn tin cho %s" % g
			q.ask = "{You} chạy sang nhắn %s giúp {self}: %s nhé." % [t, msg[0]]
			q.steps = [
				{"type": "talk", "npc": target, "desc": "Nhắn %s" % t,
						"text": "%s nhắn {npc} %s{a}." % [giver.display_name, str(msg[1])],
						"reply": "Thế à? Ừ, {self} nhớ rồi. Cảm ơn {you} nhé!"},
				report.merged({"text": "{Me} nhắn %s rồi{a}." % t}),
			]
		"fish":
			if fishing == null or river == null or river.landings.is_empty():
				return {}
			var sp: String = FISH_KINDS[_rng.randi_range(0, FISH_KINDS.size() - 1)]
			q.title = "Câu %s cho %s" % [sp.to_lower(), g]
			q.ask = _pick(["Cháu nội {self} ốm, thèm bát cháo cá. {You} câu giúp {self} một con %s ở sông được không?" % sp.to_lower(),
					"Nhà {self} sắp có khách. {You} ra bến sông câu giúp {self} một con %s về làm món nhé?" % sp.to_lower()])
			q.species = sp
			q.steps = [
				{"type": "catch", "species": sp, "desc": "Câu một con %s ở bến sông" % sp.to_lower()},
				report.merged({"text": "%s đây{a}! {Me} vừa câu được." % sp, "consume_fish": sp}),
			]
		"lost":
			var poi := _pick_place()
			if poi.is_empty():
				return {}
			var it: Array = LOST_ITEMS[giver.role][_rng.randi_range(0, LOST_ITEMS[giver.role].size() - 1)]
			var name_s: String = it[0]
			var center: Vector3 = poi.pos
			var a := _rng.randf() * TAU
			var spot := center + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(1.8, 4.5)
			spot.y = center.y
			q.title = "Tìm %s cho %s" % [name_s, g]
			if kid:
				q.ask = "{Self} làm rơi %s ở chỗ %s mà tìm mãi không thấy. {You} tìm giúp {self} với!" % [name_s, poi.name]
			else:
				q.ask = "{Self} đánh rơi %s đâu đó quanh %s rồi, mắt kém tìm mãi chẳng thấy. {You} tìm giúp {self} với." % [name_s, poi.name]
			q.steps = [
				{"type": "pickup", "item": name_s, "hint": "Nhặt %s" % name_s, "desc": "Tìm %s quanh %s" % [name_s, poi.name],
						"pos": spot, "area": center, "model": str(it[1])},
				report.merged({"text": "Có phải %s này không{a}?" % name_s, "consume": name_s}),
			]
		"goal":
			if football == null:
				return {}
			q.title = "Sút bóng cho %s xem" % g
			q.ask = "{You} có sút vào lưới được không? Bọn {self} cá là {you} không sút nổi đâu! Ra sân bóng góc làng mà sút."
			q.steps = [
				{"type": "goal", "desc": "Sút một quả vào lưới ở sân bóng"},
				report.merged({"text": "Thấy chưa, {me} sút vào lưới rồi nhé!"}),
			]
		_:
			return {}
	_next_id += 1
	return q


func _pick(arr: Array) -> String:
	return str(arr[_rng.randi_range(0, arr.size() - 1)])


## Người lớn khác để nhắn tin.
func _pick_person(not_v: Villager) -> Villager:
	var pool: Array[Villager] = []
	for v in villagers.people:
		if v != not_v and v.role in ["farmer", "carrier", "elder"]:
			pool.append(v)
	return pool[_rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null


## Chỗ quen thuộc trong làng để đánh rơi đồ: {name, pos}.
func _pick_place() -> Dictionary:
	var places: Array[Dictionary] = []
	if village != null:
		places.append({"name": "gốc đa đầu làng", "pos": village.banyan_position})
		places.append({"name": "bờ ao làng", "pos": Vector3(village.pond_center.x, 0.0, village.pond_center.y + village.pond_radii.y * 1.5)})
		places.append({"name": "sân đình", "pos": village.dinh_spot})
		places.append({"name": "giếng làng", "pos": village.well_position})
	if football != null:
		var c := football.center3()
		places.append({"name": "sân bóng", "pos": Vector3(c.x, 0.0, football.rect.end.y + 1.5)})
	if river != null:
		var names := ["bến sông phía tây", "bến sông phía đông", "bến sông phía bắc"]
		for i in river.landings.size():
			var path: PackedVector3Array = river.landings[i].path
			if path.size() > 6:
				places.append({"name": names[i] if i < names.size() else "bến sông", "pos": path[path.size() - 6]})
	return places[_rng.randi_range(0, places.size() - 1)] if not places.is_empty() else {}


# --- Hội thoại --------------------------------------------------------------------------

## Các câu liên quan việc nhờ khi nói chuyện với `v` (Dialogue gọi).
func dialog_options(v: Villager) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in active:
		var st := _step(q)
		if st.get("type", "") == "talk" and st.npc == v:
			out.append({"text": st.text, "answer": _talk_done.bind(q)})
	if not out.is_empty():
		return out
	var mine: Variant = _quest_of_giver(v)
	if mine != null:
		out.append({"text": "Việc {npc} nhờ, {me} đang làm{a}.", "answer": _reminder.bind(mine)})
		return out
	if v.has_meta("quest_offer") and active.size() < max_active:
		var q: Dictionary = v.get_meta("quest_offer")
		out.append({"text": "{Npc} có cần {me} giúp gì không{a}?", "answer": _offer_text.bind(q), "next": _offer_choices.bind(q)})
	return out


func _reminder(q: Dictionary) -> String:
	return "Ừ, {you} cứ từ từ. " + str(_step(q).get("desc", "")) + " nhé."


func _offer_text(q: Dictionary) -> String:
	return str(q.ask)


func _offer_choices(q: Dictionary) -> Array[Dictionary]:
	var kid: bool = (q.giver as Villager).role in ["kid", "herder"]
	var o: Array[Dictionary] = [
		{"text": "Được, để {me} giúp {npc}!" if kid else "Vâng, để {me} giúp {npc}{a}!", "answer": _accept.bind(q)},
		{"text": "Để lúc khác {me} giúp{a}.", "answer": _decline},
	]
	return o


func _decline() -> String:
	return "Ừ, không sao. Lúc nào rảnh thì giúp {self} nhé."


func _accept(q: Dictionary) -> String:
	var giver: Villager = q.giver
	_clear_offer(giver)
	active.append(q)
	_begin_step(q)
	_show_toast("Nhận việc: " + str(q.title))
	changed.emit()
	if giver.role in ["kid", "herder"]:
		return "Hay quá! {You} nhanh lên nhé!"
	return "Ừ, ngoan quá. {Self} cảm ơn {you} trước nhé."


## Nói câu của bước "talk" với đúng người: xong bước đó.
func _talk_done(q: Dictionary) -> String:
	var st := _step(q)
	if st.has("consume"):
		items.erase(str(st.consume))
	if st.has("consume_fish") and fishing != null:
		for i in fishing.basket.size():
			if str(fishing.basket[i].name) == str(st.consume_fish):
				fishing.basket.remove_at(i)
				break
	var giver: Villager = q.giver
	if st.npc == giver and int(q.i) == (q.steps as Array).size() - 1:
		return _finish(q)
	_advance(q)
	return str(st.get("reply", "Ừ, cảm ơn {you} nhé."))


func _finish(q: Dictionary) -> String:
	var giver: Villager = q.giver
	_end_step(q)
	active.erase(q)
	gifts.append(str(q.gift))
	done_count += 1
	_update_carry()
	_show_toast("Xong việc! Nhận được: " + str(q.gift))
	changed.emit()
	match giver.role:
		"kid", "herder":
			return "Ghê thật! {Self} cho {you} %s này, {you} cầm lấy!" % q.gift
		"elder":
			return "Ngoan quá, may mà có {you}. {Self} có %s, cầm về mà dùng nhé." % q.gift
	return "Cảm ơn {you} nhiều nhé! Có %s đây, {you} cầm về mà dùng." % q.gift


# --- Các bước ------------------------------------------------------------------------------

func _step(q: Dictionary) -> Dictionary:
	var steps: Array = q.steps
	return steps[int(q.i)] if int(q.i) < steps.size() else {}


func _advance(q: Dictionary) -> void:
	_end_step(q)
	q.i = int(q.i) + 1
	_begin_step(q)
	changed.emit()


## Dựng những thứ một bước cần: vùng bấm để nhặt, đồ đánh rơi, dấu chỉ đường.
func _begin_step(q: Dictionary) -> void:
	var st := _step(q)
	if st.is_empty():
		return
	var marker := MeshInstance3D.new()
	marker.mesh = _diamond_mesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	var label := Label3D.new()
	label.font = Hud.font(true)
	label.font_size = 20
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 11
	label.modulate = Palette.FLOWER_YELLOW
	label.outline_modulate = Palette.WINDOW_DARK
	label.outline_size = 8
	label.position.y = -0.55
	marker.add_child(label)
	q.marker = marker
	q.marker_label = label
	if st.type == "pickup":
		var node := Node3D.new()
		node.position = st.pos
		add_child(node)
		(q.nodes as Array).append(node)
		if str(st.model) != "well":
			node.add_child(_item_mesh(str(st.model)))
		var target := HouseEntry.make_click_target(node, Transform3D(Basis(), Vector3(0, 0.4, 0)),
				Vector3(1.6, 1.2, 1.6) if st.model == "well" else Vector3(0.9, 0.8, 0.9), str(st.hint))
		target.set_meta("activate", _pickup.bind(q))
		target.add_to_group(HouseEntry.ACTIVATE_GROUP)
	_update_carry()


func _end_step(q: Dictionary) -> void:
	for n in q.nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	q.nodes = []
	if q.marker != null and is_instance_valid(q.marker):
		(q.marker as Node).queue_free()
	q.marker = null


func _pickup(q: Dictionary) -> void:
	var st := _step(q)
	if st.get("type", "") != "pickup":
		return
	items.append(str(st.item))
	_show_toast(("Đã múc đầy đôi thùng nước" if st.model == "well" else "Nhặt được " + str(st.item)) + ".")
	_advance(q)


func _on_goal(_team: int, by_player: bool) -> void:
	if not by_player:
		return
	for q in active.duplicate():
		if _step(q).get("type", "") == "goal":
			_show_toast("VÀO! Về khoe với " + _lower_first((q.giver as Villager).display_name) + " thôi.")
			_advance(q)


## Chỗ đứng hiện tại của người chơi (nhập vai) hoặc tâm camera ngắm cảnh.
func _player_pos() -> Vector3:
	if first_person != null and first_person.active:
		return first_person.global_position
	return outdoor_rig.global_position if outdoor_rig != null else Vector3.ZERO


## Vị trí dấu chỉ đường của bước hiện tại.
func _target_pos(q: Dictionary) -> Vector3:
	var st := _step(q)
	match str(st.get("type", "")):
		"pickup":
			return st.get("area", st.pos)
		"goto":
			return st.pos
		"talk":
			var v: Villager = st.npc
			if is_instance_valid(v) and v.visible:
				return v.global_position + Vector3(0, 1.0, 0)
			return v.home.get("front", v.global_position) if is_instance_valid(v) else Vector3.ZERO
		"catch":
			if fishing != null and not fishing._spots.is_empty():
				var best := Vector3.ZERO
				var bd := INF
				for s in fishing._spots:
					var p: Vector3 = (s.node as Node3D).global_position
					var d := p.distance_to(_player_pos())
					if d < bd:
						bd = d
						best = p
				return best
		"goal":
			return football.center3() if football != null else Vector3.ZERO
	return Vector3.ZERO


func _process(delta: float) -> void:
	_offer_timer -= delta
	if _offer_timer <= 0.0:
		_offer_timer = offer_refresh
		_refresh_offers()
	var me := _player_pos()
	var walking := first_person != null and first_person.active
	for q in active.duplicate():
		var st := _step(q)
		match str(st.get("type", "")):
			"goto":
				if walking and Vector2(me.x - st.pos.x, me.z - st.pos.z).length() < arrive_radius:
					if st.has("consume"):
						items.erase(str(st.consume))
					_show_toast(str(st.get("toast", "Tới nơi rồi.")))
					_advance(q)
			"catch":
				if fishing != null:
					for f in fishing.basket:
						if str(f.name) == str(st.species):
							_show_toast("Câu được %s rồi! Mang tới cho %s thôi." % [str(st.species).to_lower(), _lower_first((q.giver as Villager).display_name)])
							_advance(q)
							break
			"talk":
				# Người cần gặp đang trong nhà: tới trước cổng thì họ ra
				var v: Villager = st.npc
				if walking and is_instance_valid(v) and not v.visible:
					var front: Vector3 = v.home.get("front", v.global_position)
					if Vector2(me.x - front.x, me.z - front.z).length() < 3.0:
						villagers.call_out(v)
						if dialogue != null:
							dialogue.bark(v, "Ai gọi đấy? Ra đây!")
	_update_markers(delta)
	_ui_timer -= delta
	if _ui_timer <= 0.0:
		_ui_timer = 0.25
		_update_ui()
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast_panel.visible = _toast_timer > 0.0


func _update_markers(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var t := Time.get_ticks_msec() / 1000.0
	for q in active:
		var m: MeshInstance3D = q.marker
		if m == null or not is_instance_valid(m):
			continue
		var p := _target_pos(q)
		var lifted := p + Vector3(0, 2.4 + 0.15 * sin(t * 2.5), 0)
		m.global_position = lifted
		m.rotation.y = t * 1.5
		var d := cam.global_position.distance_to(lifted) if cam != null else 10.0
		m.scale = Vector3.ONE * clampf(d * 0.045, 0.6, 6.0)
		m.visible = d > 2.5 or _step(q).get("type", "") == "goto"
		var st := _step(q)
		var dist := Vector2(_player_pos().x - p.x, _player_pos().z - p.z).length()
		(q.marker_label as Label3D).text = ("quanh đây · " if st.has("area") else "") + "%d m" % int(dist)


func _update_carry() -> void:
	if first_person != null:
		first_person.speed_scale = carry_speed if items.has("Đôi thùng nước") else 1.0


# --- Giao diện -----------------------------------------------------------------------------

func _direction_word(q: Dictionary) -> String:
	var p := _target_pos(q)
	var me := _player_pos()
	var to := Vector2(p.x - me.x, p.z - me.z)
	if to.length() < 4.0:
		return "ngay đây"
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return "%d m" % int(to.length())
	var f := -cam.global_transform.basis.z
	var fwd := Vector2(f.x, f.z).normalized()
	var ang := rad_to_deg(fwd.angle_to(to.normalized()))
	var word := "phía trước"
	if absf(ang) > 145.0:
		word = "phía sau"
	elif ang > 35.0:
		word = "bên phải"
	elif ang < -35.0:
		word = "bên trái"
	return "%s, %d m" % [word, int(to.length())]


func _update_ui() -> void:
	var lines: Array[String] = []
	for q in active:
		lines.append("• " + str(q.title))
		lines.append("    " + str(_step(q).get("desc", "")) + "  ·  " + _direction_word(q))
	if not items.is_empty():
		lines.append("Đang cầm: " + ", ".join(items))
	if not gifts.is_empty():
		lines.append("Quà đã nhận (%d): %s" % [gifts.size(), ", ".join(gifts.slice(maxi(gifts.size() - 3, 0)))])
	_list.text = "\n".join(lines)
	_panel.visible = not lines.is_empty() and (hud == null or hud.visible)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_timer = 3.2
	_toast_panel.visible = true
	_toast_panel.reset_size()
	_toast_panel.offset_left = -_toast_panel.size.x * 0.5
	_toast_panel.offset_right = _toast_panel.size.x * 0.5


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_panel = _make_panel()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -20
	_panel.offset_top = 200
	_panel.custom_minimum_size.x = 340
	layer.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Việc được nhờ"
	title.add_theme_font_override("font", Hud.font(true))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Palette.FLOWER_YELLOW)
	box.add_child(title)
	_list = Label.new()
	_list.add_theme_font_override("font", Hud.font(false))
	_list.add_theme_font_size_override("font_size", 15)
	_list.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.custom_minimum_size.x = 320
	box.add_child(_list)
	_panel.visible = false
	_toast_panel = _make_panel()
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.offset_top = 120
	layer.add_child(_toast_panel)
	_toast = Label.new()
	_toast.add_theme_font_override("font", Hud.font(true))
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_toast_panel.add_child(_toast)
	_toast_panel.visible = false


func _make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	return p


# --- Đồ vật nhỏ (đồ đánh rơi) ----------------------------------------------------------------

func _item_mesh(model: String) -> MeshInstance3D:
	var mb := MeshBuilder.new(77, 0.03)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	match model:
		"hat":
			mb.add_pyramid(0.32, 0.2, 12, Palette.HAT, Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.05, 0)))
		"pipe":
			mb.add_limb(Vector3(-0.3, 0.05, 0), Vector3(0.3, 0.07, 0.05), 0.035, 0.03, 6, Palette.BAMBOO_STEM)
			mb.add_limb(Vector3(-0.05, 0.05, 0), Vector3(0.0, 0.05, 0.18), 0.015, 0.015, 4, Palette.WOOD)
		"knife":
			mb.add_box(Vector3(0.05, 0.03, 0.22), Palette.WOOD, Transform3D(Basis(), Vector3(0, 0.0, -0.12)))
			mb.add_box(Vector3(0.09, 0.015, 0.28), Palette.ROCK_DARK, Transform3D(Basis(Vector3.UP, 0.1), Vector3(0.02, 0.0, 0.14)))
		"fan":
			mb.add_prism(0.22, 0.22, 0.015, 10, Palette.STRAW, Transform3D(Basis(), Vector3(0, 0.0, 0.08)))
			mb.add_box(Vector3(0.03, 0.02, 0.18), Palette.BAMBOO_STEM, Transform3D(Basis(), Vector3(0, 0.0, -0.18)))
		"top":
			mb.add_prism(0.09, 0.02, 0.1, 8, Palette.WOOD_LIGHT, Transform3D(Basis(Vector3.FORWARD, 1.2), Vector3(0, 0.07, 0)))
			mb.add_prism(0.1, 0.09, 0.04, 8, Palette.HIBISCUS, Transform3D(Basis(Vector3.FORWARD, 1.2), Vector3(0, 0.07, 0)))
		"shuttle":
			mb.add_prism(0.05, 0.05, 0.05, 8, Palette.ROCK_DARK)
			mb.add_pyramid(0.09, 0.16, 6, Palette.FLOWER_WHITE, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.2, 0)))
		_:
			mb.add_blob(Vector3(0.1, 0.1, 0.1), Palette.HIBISCUS, rng, 0.1)
	var mi := mb.commit_instance("LostItem")
	mi.rotation.y = randf() * TAU
	return mi


# --- Công cụ kiểm tra ----------------------------------------------------------------------

## Nhận ngay một việc (dùng cho chụp ảnh / bài thử).
func debug_accept(giver: Villager, kind: String) -> Dictionary:
	var q := make_quest(giver, kind)
	if q.is_empty():
		return q
	_clear_offer(giver)
	active.append(q)
	_begin_step(q)
	changed.emit()
	return q
