class_name Inventory
extends CanvasLayer
## Túi đồ + túi tiền của người chơi (mục 48). Gộp những thứ trước đây nằm rải rác: tiền (Market.money), đồ mua ở chợ
## (Market.bag), quà nhận khi giúp việc (Quests.gifts — giờ là vật phẩm thật), cá trong giỏ (vẫn ở Fishing.basket, hiện
## ở ngăn "Giỏ cá").
## - Danh mục `ITEMS`: mã → tên, loại (food / tool / goods), giá chợ (nghìn đồng), sạp mua lại, biểu tượng, công dụng.
## - Công dụng: ăn / uống → no bụng (`energy` giây thật): chạy nhanh hơn khi nhập vai, chèo đua thuyền và kéo co đỡ mệt;
##   hộp mồi giun → cá cắn nhanh hơn `bait_per_box` lượt câu; diều giấy → tự thả diều ở chỗ thoáng (đứt dây thì mất diều);
##   sáo trúc → thổi một khúc sáo (trẻ con quanh đó khen).
## - Kiếm tiền: bán cá / bán lại đồ ở chợ phiên (Market), việc nhờ (Quests: người lớn trả tiền công + quà), giải nhất đua
##   thuyền, thắng kéo co / ô ăn quan có quà, mừng tuổi ngày Tết (Festival).
## - Biếu quà cho bất kỳ ai (Dialogue gọi `dialog_options`): ai được đúng món mình thích (`likes`) thì quý hơn.
## - Phím I (`toggle_inventory`): mở / gấp màn hình túi đồ — lưới ô có biểu tượng vẽ bằng code, bên phải là chi tiết món
##   đang chọn, nút Dùng / Bỏ đi. A / D đổi ngăn, W / S chọn món, E dùng, I / Esc gấp.

signal changed
signal used(id: String)

@export var market: Market
@export var fishing: Fishing
@export var quests: Quests
@export var dialogue: Dialogue
@export var first_person: FirstPerson
@export var kite: KiteFlying
@export var boat_race: BoatRace
@export var tug_war: TugOfWar
@export var o_an_quan: OAnQuan
@export var soundscape: Soundscape
@export var villagers: Villagers
@export var notebook: Notebook
@export var hud: Hud
@export var outdoor_rig: CameraRig
@export_group("Tiền")
## Tiền lúc bắt đầu chơi (nghìn đồng).
@export var start_money: int = 20
## Bán lại đồ cho người bán ở chợ được bao nhiêu phần giá.
@export_range(0.1, 1.0) var resell_ratio: float = 0.5
## Giải nhất đua thuyền rồng (nghìn đồng); thuyền đơn thì 2 nghìn mỗi thuyền thua, tối đa bằng giải này.
@export var race_prize: int = 10
@export_group("Công dụng")
## No bụng tối đa (giây thật).
@export var energy_cap: float = 360.0
## Khi no bụng: tốc độ chạy × hệ số này.
@export var run_boost: float = 1.25
## Khi no bụng: sức chèo đua thuyền tụt chậm lại (× hệ số).
@export var stamina_save: float = 0.6
## Khi no bụng: sức kéo co tụt chậm lại (× hệ số).
@export var tug_decay: float = 0.7
## Một hộp mồi giun dùng được bao nhiêu lượt câu.
@export var bait_per_box: int = 5

## Loại vật phẩm (ngăn trong túi).
const CATS := {"food": "Đồ ăn", "tool": "Đồ dùng", "goods": "Đồ đạc"}
const TABS: Array[String] = ["all", "food", "tool", "goods", "fish"]
const TAB_NAMES := {"all": "Tất cả", "food": "Đồ ăn", "tool": "Đồ dùng", "goods": "Đồ đạc", "fish": "Giỏ cá"}

## Danh mục vật phẩm. stall: sạp ở chợ mua lại món này ("" = không ai mua). energy: giây no bụng.
## use: eat | drink | bait | kite | flute | "" (không dùng được, chỉ để biếu / bán). likes: vai thích được biếu món này.
## alias: tên cũ (file lưu bản trước, quà của việc nhờ).
const ITEMS := {
	# --- Đồ ăn ---
	"chuoi": {"name": "nải chuối", "cat": "food", "price": 5, "stall": "fruit", "icon": "banana", "use": "eat", "energy": 90,
			"desc": "Nải chuối tiêu chín vàng, thơm lừng.", "likes": ["kid", "elder"], "alias": ["nải chuối tiêu"]},
	"buoi": {"name": "quả bưởi", "cat": "food", "price": 8, "stall": "fruit", "icon": "pomelo", "use": "eat", "energy": 120,
			"desc": "Bưởi Diễn ngọt mát, bóc ra cả nhà ăn.", "likes": ["elder", "carrier"]},
	"nhan": {"name": "chùm nhãn", "cat": "food", "price": 6, "stall": "fruit", "icon": "longan", "use": "eat", "energy": 90,
			"desc": "Nhãn lồng cùi dày, hạt nhỏ.", "likes": ["kid", "carrier"]},
	"oi": {"name": "túi ổi chín", "cat": "food", "price": 4, "stall": "fruit", "icon": "guava", "use": "eat", "energy": 75,
			"desc": "Ổi vườn chín thơm, chấm muối ớt.", "likes": ["kid", "herder"]},
	"sim": {"name": "chùm sim chín", "cat": "food", "price": 3, "stall": "fruit", "icon": "sim", "use": "eat", "energy": 60,
			"desc": "Sim chín tím hái trên đồi, ăn tím cả lưỡi.", "likes": ["kid", "herder"]},
	"khoai": {"name": "rổ khoai lang", "cat": "food", "price": 4, "stall": "veg", "icon": "potato", "use": "eat", "energy": 150,
			"desc": "Khoai lang luộc bở tơi, ăn chắc bụng.", "likes": ["farmer", "herder"]},
	"banh_da": {"name": "cái bánh đa", "cat": "food", "price": 2, "stall": "sweets", "icon": "cracker", "use": "eat", "energy": 60,
			"desc": "Bánh đa vừng nướng giòn.", "likes": ["kid", "herder"], "alias": ["mấy cái bánh đa"]},
	"keo_lac": {"name": "gói kẹo lạc", "cat": "food", "price": 1, "stall": "sweets", "icon": "candy", "use": "eat", "energy": 45,
			"desc": "Kẹo lạc mật mía, ngọt bùi.", "likes": ["kid", "elder"], "alias": ["đĩa kẹo lạc"]},
	"banh_giay": {"name": "đôi bánh giầy", "cat": "food", "price": 3, "stall": "sweets", "icon": "ricecake", "use": "eat", "energy": 90,
			"desc": "Bánh giầy dẻo kẹp giò.", "likes": ["elder", "farmer"]},
	"keo_keo": {"name": "cái kẹo kéo", "cat": "food", "price": 1, "stall": "sweets", "icon": "taffy", "use": "eat", "energy": 40,
			"desc": "Kẹo kéo trắng ngà, dẻo quánh.", "likes": ["kid"]},
	"xoi_lac": {"name": "gói xôi lạc", "cat": "food", "price": 4, "stall": "rice", "icon": "packet", "use": "eat", "energy": 150,
			"desc": "Xôi lạc gói lá chuối, ăn sáng no tới trưa.", "likes": ["farmer", "carrier"]},
	"che": {"name": "gói chè Thái", "cat": "food", "price": 6, "stall": "", "icon": "tea", "use": "drink", "energy": 120,
			"desc": "Chè búp Thái Nguyên. Pha một ấm uống cho tỉnh người.", "likes": ["elder", "farmer"]},
	# --- Đồ dùng ---
	"moi": {"name": "hộp mồi giun", "cat": "tool", "price": 3, "stall": "fish", "icon": "bait", "use": "bait",
			"desc": "Giun đất đào ở bờ ruộng. Móc mồi vào thì cá cắn câu nhanh hơn (5 lượt câu).", "likes": []},
	"dieu": {"name": "con diều giấy", "cat": "tool", "price": 6, "stall": "hats", "icon": "kite", "use": "kite",
			"desc": "Diều sáo khung tre. Ra chỗ thoáng mà thả — dây đứt thì diều bay mất đấy!", "likes": ["kid", "herder"]},
	"sao": {"name": "cây sáo trúc", "cat": "tool", "price": 5, "stall": "hats", "icon": "flute", "use": "flute",
			"desc": "Sáo trúc sáu lỗ, thổi nghe trong vắt giữa đồng.", "likes": ["herder", "kid"], "alias": ["cái sáo trúc"]},
	"quay": {"name": "con quay gỗ", "cat": "tool", "price": 2, "stall": "sweets", "icon": "top", "use": "",
			"desc": "Con quay gỗ đẽo tay, quấn dây quất cho quay tít.", "likes": ["kid"]},
	"bi": {"name": "túi bi ve", "cat": "tool", "price": 1, "stall": "sweets", "icon": "marbles", "use": "",
			"desc": "Mấy viên bi ve xanh đỏ, để bắn bi với bọn trẻ.", "likes": ["kid", "herder"], "alias": ["mấy viên bi"]},
	"quat": {"name": "cái quạt nan", "cat": "tool", "price": 3, "stall": "hats", "icon": "fan", "use": "",
			"desc": "Quạt nan tre, trưa hè phe phẩy.", "likes": ["elder", "carrier"]},
	"non_la": {"name": "cái nón lá", "cat": "tool", "price": 15, "stall": "hats", "icon": "hat", "use": "",
			"desc": "Nón lá trắng, che nắng che mưa.", "likes": ["carrier", "farmer", "elder"]},
	# --- Đồ đạc, thức ăn sống ---
	"rau_muong": {"name": "bó rau muống", "cat": "goods", "price": 2, "stall": "veg", "icon": "greens", "use": "",
			"desc": "Rau muống ruộng, luộc chấm tương.", "likes": ["farmer", "carrier"]},
	"rau_cai": {"name": "mớ rau cải", "cat": "goods", "price": 2, "stall": "veg", "icon": "greens", "use": "",
			"desc": "Cải ngồng nấu canh.", "likes": ["carrier"]},
	"hanh": {"name": "bó hành lá", "cat": "goods", "price": 1, "stall": "veg", "icon": "greens", "use": "",
			"desc": "Hành lá thơm.", "likes": []},
	"tep": {"name": "mớ tép", "cat": "goods", "price": 5, "stall": "fish", "icon": "shrimp", "use": "",
			"desc": "Tép đồng rang khế.", "likes": ["carrier"]},
	"ca_ro": {"name": "xâu cá rô", "cat": "goods", "price": 9, "stall": "fish", "icon": "fish", "use": "",
			"desc": "Cá rô đồng xâu lạt, về kho tộ.", "likes": ["farmer", "elder"]},
	"trung_ga": {"name": "chục trứng gà", "cat": "goods", "price": 12, "stall": "poultry", "icon": "eggs", "use": "",
			"desc": "Trứng gà ta.", "likes": ["elder", "carrier"]},
	"trung_vit": {"name": "chục trứng vịt", "cat": "goods", "price": 10, "stall": "poultry", "icon": "duck_eggs", "use": "",
			"desc": "Trứng vịt đồng.", "likes": ["farmer"]},
	"gao_nep": {"name": "cân gạo nếp", "cat": "goods", "price": 10, "stall": "rice", "icon": "sack", "use": "",
			"desc": "Nếp cái hoa vàng, đồ xôi thơm cả ngõ.", "likes": ["elder", "carrier"]},
	"gao_tam": {"name": "cân gạo tám", "cat": "goods", "price": 9, "stall": "rice", "icon": "sack", "use": "",
			"desc": "Gạo tám xoan dẻo thơm.", "likes": ["farmer"]},
	"noi_dat": {"name": "cái nồi đất", "cat": "goods", "price": 12, "stall": "pottery", "icon": "pot", "use": "",
			"desc": "Nồi đất kho cá.", "likes": ["carrier"]},
	"bat_men": {"name": "cái bát men", "cat": "goods", "price": 4, "stall": "pottery", "icon": "bowl", "use": "",
			"desc": "Bát men Bát Tràng.", "likes": ["elder"]},
	"chum": {"name": "cái chum nhỏ", "cat": "goods", "price": 25, "stall": "pottery", "icon": "jar", "use": "",
			"desc": "Chum sành đựng nước mưa.", "likes": ["farmer", "elder"]},
}

var money: int = 20
## Số lượng từng món: mã → số.
var items: Dictionary = {}
## Thứ tự món được thêm vào (để lưới ô không nhảy lung tung).
var order: Array[String] = []
## Còn no bụng bao nhiêu giây thật.
var energy: float = 0.0
## Tổng tiền đã kiếm / đã tiêu (sổ tay).
var earned: int = 0
var spent: int = 0
var open: bool = false
## Đang tự thả diều của mình (mất diều nếu đứt dây).
var flying_own_kite: bool = false

var _tab: int = 0
var _sel: int = 0
var _entries: Array[Dictionary] = []    # ô đang hiện: {kind: item|fish, id, n | fish}
var _root: Control
var _money_label: Label
var _tab_buttons: Array[Button] = []
var _grid: GridContainer
var _detail_icon: ItemIcon
var _detail_name: Label
var _detail_sub: Label
var _detail_desc: Label
var _use_button: Button
var _drop_button: Button
var _status: Label
var _toast: Label
var _toast_t: float = 0.0
var _from_fp: bool = false
var _rig_was_active: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 19
	_rng.randomize()
	money = start_money
	_build_ui()
	_root.visible = false
	_connect_prizes()
	if kite != null:
		kite.finished.connect(_on_kite_finished)
	_push_effects()
	_update_hud()


# --- Danh mục ----------------------------------------------------------------------------------------------

static func item_name(id: String) -> String:
	return str((ITEMS[id] as Dictionary).name) if ITEMS.has(id) else id


static func price_of(id: String) -> int:
	return int((ITEMS[id] as Dictionary).price) if ITEMS.has(id) else 0


## Mã vật phẩm từ tên (kể cả tên cũ). Rỗng nếu không có.
static func id_of(name_s: String) -> String:
	var low := name_s.strip_edges().to_lower()
	for id: String in ITEMS:
		var it: Dictionary = ITEMS[id]
		if str(it.name).to_lower() == low:
			return id
		for a: String in it.get("alias", []):
			if a.to_lower() == low:
				return id
	return ""


static func usable(id: String) -> bool:
	return ITEMS.has(id) and str((ITEMS[id] as Dictionary).use) != ""


# --- Tiền và đồ ----------------------------------------------------------------------------------------------

func count(id: String) -> int:
	return int(items.get(id, 0))


func total_items() -> int:
	var n := 0
	for id: String in items:
		n += int(items[id])
	return n


func add(id: String, n: int = 1) -> void:
	if not ITEMS.has(id) or n <= 0:
		push_warning("Inventory: không có vật phẩm '%s'" % id)
		return
	if not items.has(id):
		order.append(id)
	items[id] = count(id) + n
	_changed()


## Bớt n món; false nếu không đủ.
func remove(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	items[id] = count(id) - n
	if int(items[id]) <= 0:
		items.erase(id)
		order.erase(id)
	_changed()
	return true


func earn(n: int, why: String = "") -> void:
	if n <= 0:
		return
	money += n
	earned += n
	if why != "":
		toast("%s · +%d nghìn" % [why, n])
	_changed()


## Trả tiền; false (không trừ) nếu không đủ.
func spend(n: int) -> bool:
	if n > money:
		return false
	money -= n
	spent += n
	_changed()
	return true


func money_text() -> String:
	return "%d nghìn đồng" % money


func _changed() -> void:
	_update_hud()
	if open:
		_refresh()
	changed.emit()


func _update_hud() -> void:
	if hud != null:
		hud.money_text = "%d nghìn đ" % money


# --- Dùng đồ ------------------------------------------------------------------------------------------------

## Dùng một món. Trả về lời báo (rỗng = không dùng được lúc này, lời giải thích đã hiện bằng toast).
func use(id: String) -> String:
	if count(id) <= 0 or not usable(id):
		return ""
	var it: Dictionary = ITEMS[id]
	var nm := str(it.name)
	var msg := ""
	match str(it.use):
		"eat", "drink":
			energy = minf(energy + float(it.energy), energy_cap)
			remove(id)
			msg = "%s %s · no bụng %s — chạy nhanh hơn, chèo thuyền / kéo co đỡ mệt" % [
					"Uống chè từ" if str(it.use) == "drink" else "Ăn", nm, _clock(energy)]
		"bait":
			if fishing == null:
				return ""
			remove(id)
			fishing.bait += bait_per_box
			msg = "Móc sẵn mồi giun · %d lượt câu cá cắn nhanh hơn" % fishing.bait
		"kite":
			var why := _kite_refusal()
			if why != "":
				toast(why)
				return ""
			close()
			flying_own_kite = true
			kite.start(null)
			msg = "Thả con diều giấy của bạn"
		"flute":
			if soundscape != null:
				soundscape.play_flat("flute", -2.0)
			_flute_listeners()
			msg = "Bạn thổi một khúc sáo…"
	if msg != "":
		toast(msg)
		used.emit(id)
	return msg


func _kite_refusal() -> String:
	if kite == null or first_person == null:
		return "Không thả diều được lúc này."
	if not first_person.active or not (first_person._suspended in ["", "inventory"]):
		return "Nhập vai (V) rồi ra chỗ thoáng mới thả diều được."
	if kite.phase != KiteFlying.Phase.OFF:
		return "Đang thả diều rồi."
	return kite.self_refusal(first_person.global_position)


func _on_kite_finished(_h: float, _s: float, why: String) -> void:
	if not flying_own_kite:
		return
	if why == "snap":
		remove("dieu")
		toast("Đứt dây — con diều giấy của bạn bay mất rồi!")


## Trẻ con quanh đó nghe sáo thì khen.
func _flute_listeners() -> void:
	if villagers == null or dialogue == null or first_person == null:
		return
	var at := first_person.global_position if first_person.active else (outdoor_rig.global_position if outdoor_rig != null else Vector3.ZERO)
	var lines := ["Hay quá! {You} thổi bài nữa đi!", "Sáo {you} thổi nghe như sáo diều ấy!", "Ơ, {you} thổi sáo hay thế!"]
	var n := 0
	for v in villagers.people:
		if n >= 2:
			break
		if v.visible and v.role in ["kid", "herder", "elder"] and v.global_position.distance_to(at) < 14.0:
			dialogue.bark(v, dialogue.fill_for(v, lines[_rng.randi_range(0, lines.size() - 1)]))
			n += 1


func _process(delta: float) -> void:
	if energy > 0.0:
		energy = maxf(energy - delta, 0.0)
		if energy == 0.0:
			toast("Hết no bụng rồi — đói thì ăn gì đó đi.")
		_push_effects()
	elif first_person != null and first_person.run_boost != 1.0:
		_push_effects()
	if flying_own_kite and kite != null and kite.phase == KiteFlying.Phase.OFF:
		flying_own_kite = false
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		_toast.visible = _toast_t > 0.0
	if open and Engine.get_process_frames() % 15 == 0:
		_status.text = _status_text()


## Đẩy hiệu ứng no bụng sang các phần khác (chúng không cần biết Inventory).
func _push_effects() -> void:
	var full := energy > 0.0
	if first_person != null:
		first_person.run_boost = run_boost if full else 1.0
	if boat_race != null:
		boat_race.stamina_scale = stamina_save if full else 1.0
	if tug_war != null:
		tug_war.decay_scale = tug_decay if full else 1.0


static func _clock(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


# --- Thưởng từ trò chơi -------------------------------------------------------------------------------------

func _connect_prizes() -> void:
	if boat_race != null:
		boat_race.finished.connect(func(place: int, _time: float) -> void:
			if place != 1:
				return
			var n := race_prize
			if boat_race.mode == "solo":
				n = mini(race_prize, 2 * (boat_race.boats.size() - 1))
			earn(n, "Giải nhất đua thuyền"))
	if tug_war != null:
		tug_war.finished.connect(func(won: bool, _a: int, _b: int) -> void:
			if won:
				add("keo_lac")
				toast("Thắng kéo co · được gói kẹo lạc"))
	if o_an_quan != null:
		o_an_quan.finished.connect(func(ps: int, ns: int) -> void:
			if o_an_quan.over and ps > ns:
				add("banh_da")
				toast("Thắng ván ô ăn quan · được cái bánh đa"))


# --- Biếu quà (Dialogue gọi) ------------------------------------------------------------------------------

func dialog_options(v: Villager, dlg: Dialogue) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if order.is_empty():
		return out
	out.append({"key": "inv_gift", "repeat": true, "text": "{Me} biếu {npc} chút quà{a}.",
			"answer": func() -> String: return "Ôi, {you} quà cáp gì thế này…",
			"next": func() -> Array[Dictionary]: return _gift_options(v, dlg, 0)})
	return out


func _gift_options(v: Villager, dlg: Dialogue, page: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var per := 3 if order.size() <= 3 else 2
	var start := page * per
	for k in range(start, mini(start + per, order.size())):
		var id: String = order[k]
		out.append({"text": "Biếu %s" % item_name(id), "answer": func() -> String: return give(v, id, dlg)})
	if order.size() > start + per:
		var nxt := page + 1
		out.append({"text": "Món khác…", "answer": func() -> String: return "…",
				"next": func() -> Array[Dictionary]: return _gift_options(v, dlg, nxt)})
	out.append({"text": "Thôi, để lúc khác.", "end": true})
	return out


## Biếu một món: bớt khỏi túi, người nhận quý hơn (đúng món thích thì quý hơn nữa).
func give(v: Villager, id: String, dlg: Dialogue) -> String:
	if not remove(id):
		return "…"
	var nm := item_name(id)
	var liked: bool = v.role in ((ITEMS[id] as Dictionary).likes as Array)
	if dlg != null:
		var real: Villager = v.get_meta("proxy_of", v)
		dlg._met[real] = int(dlg._met.get(real, 0)) + (3 if liked else 2)
	toast("Biếu %s %s" % [v.display_name, nm])
	var kid := v.role in ["kid", "herder"]
	if liked:
		if kid:
			return "A, %s! Em thích cái này nhất! Em cảm ơn {you} nhiều lắm!" % nm
		return "Ôi, đúng %s {self} đang cần! {You} chu đáo quá, {self} cảm ơn {you} nhé!" % nm
	if kid:
		return ["Cho em %s thật ạ? Em cảm ơn {you}!" % nm, "Em cảm ơn {you} ạ!"][_rng.randi_range(0, 1)]
	return ["Quý hoá quá, {you} biếu {self} %s à. Cảm ơn {you} nhé!" % nm,
			"Ôi, {you} chu đáo quá. Lần sau sang {self} mời nước chè nhé!"][_rng.randi_range(0, 1)]


# --- Lưu / nạp ------------------------------------------------------------------------------------------------

func snapshot() -> Dictionary:
	var its := {}
	for id in order:
		its[id] = count(id)
	return {"money": money, "items": its, "order": order.duplicate(), "energy": energy, "earned": earned, "spent": spent,
			"bait": fishing.bait if fishing != null else 0}


func load_data(d: Dictionary) -> void:
	items.clear()
	order.clear()
	money = int(d.get("money", start_money))
	var its: Dictionary = d.get("items", {})
	for id: Variant in d.get("order", its.keys()):
		var k := str(id)
		if ITEMS.has(k) and int(its.get(k, 0)) > 0:
			order.append(k)
			items[k] = int(its[k])
	energy = float(d.get("energy", 0.0))
	earned = int(d.get("earned", 0))
	spent = int(d.get("spent", 0))
	if fishing != null:
		fishing.bait = int(d.get("bait", 0))
	_push_effects()
	_changed()


## File lưu bản trước (mục 37–40): tiền + túi đồ ở Market (tên), quà ở Quests (tên) → vật phẩm.
func load_legacy(d: Dictionary) -> void:
	items.clear()
	order.clear()
	money = int(d.get("money", start_money))
	for key in ["bag", "gifts"]:
		for nm: Variant in d.get(key, []):
			var id := id_of(str(nm))
			if id != "":
				if not items.has(id):
					order.append(id)
				items[id] = count(id) + 1
	_changed()


func reset() -> void:
	items.clear()
	order.clear()
	money = start_money
	energy = 0.0
	earned = 0
	spent = 0
	_push_effects()
	_changed()


# --- Màn hình túi đồ -------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		if open:
			close()
		else:
			show_inventory()
		get_viewport().set_input_as_handled()
		return
	if not open:
		return
	if event.is_action_pressed("exit_interior"):
		close()
	elif event.is_action_pressed("cam_left"):
		set_tab((_tab + TABS.size() - 1) % TABS.size())
	elif event.is_action_pressed("cam_right"):
		set_tab((_tab + 1) % TABS.size())
	elif event.is_action_pressed("cam_forward"):
		_select(_sel - 1)
	elif event.is_action_pressed("cam_back"):
		_select(_sel + 1)
	elif event.is_action_pressed("interact"):
		_use_selected()
	elif not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()       # túi đang mở: không cho phím lọt xuống


## Mở túi (không mở khi đang trò chuyện, đang chơi trò gì, hay sổ tay đang mở).
func show_inventory() -> bool:
	if open or (dialogue != null and dialogue.talking) or (notebook != null and notebook.open):
		return false
	_from_fp = first_person != null and first_person.active
	if _from_fp:
		if first_person._suspended != "":
			return false
		first_person._suspend("inventory")
	open = true
	_root.visible = true
	if outdoor_rig != null and not _from_fp:
		_rig_was_active = outdoor_rig.active
		outdoor_rig.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	return true


func close() -> void:
	if not open:
		return
	open = false
	_root.visible = false
	if outdoor_rig != null and not _from_fp:
		outdoor_rig.active = _rig_was_active
	if _from_fp and first_person != null and first_person._suspended == "inventory":
		first_person._resume()


func set_tab(i: int) -> void:
	_tab = i
	_sel = 0
	_refresh()


func _select(i: int) -> void:
	if _entries.is_empty():
		return
	_sel = clampi(i, 0, _entries.size() - 1)
	_refresh_selection()


func _use_selected() -> void:
	if _sel < _entries.size() and str(_entries[_sel].kind) == "item":
		use(str(_entries[_sel].id))


func _drop_selected() -> void:
	if _sel < _entries.size() and str(_entries[_sel].kind) == "item":
		var id := str(_entries[_sel].id)
		if remove(id):
			toast("Bỏ đi %s" % item_name(id))


func _collect_entries() -> void:
	_entries.clear()
	var tab := TABS[_tab]
	if tab != "fish":
		for id in order:
			if tab == "all" or str((ITEMS[id] as Dictionary).cat) == tab:
				_entries.append({"kind": "item", "id": id, "n": count(id)})
	if (tab == "fish" or tab == "all") and fishing != null:
		for b: Dictionary in fishing.basket:
			_entries.append({"kind": "fish", "id": str(b.name), "fish": b})


func _refresh() -> void:
	_money_label.text = "Túi tiền: " + money_text()
	for k in _tab_buttons.size():
		_tab_buttons[k].button_pressed = k == _tab
	_collect_entries()
	_sel = clampi(_sel, 0, maxi(_entries.size() - 1, 0))
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for i in _entries.size():
		_grid.add_child(_slot(i))
	_refresh_selection()
	_status.text = _status_text()


func _slot(i: int) -> Control:
	var e: Dictionary = _entries[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(104, 112)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.ICON_SLOT_ON if state.contains("pressed") else Palette.ICON_SLOT
		sb.border_color = Color(Notebook.INK_SOFT, 0.6 if state == "hover" else 0.35)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func() -> void: _select(i))
	var ic := ItemIcon.new()
	ic.position = Vector2(20, 6)
	ic.size = Vector2(64, 64)
	ic.custom_minimum_size = Vector2(64, 64)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var nm := Label.new()
	nm.add_theme_font_override("font", Hud.font(false))
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Notebook.INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(4, 72)
	nm.size = Vector2(96, 36)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(nm)
	if str(e.kind) == "item":
		var id := str(e.id)
		ic.set_icon(str((ITEMS[id] as Dictionary).icon))
		nm.text = item_name(id)
		if int(e.n) > 1:
			var cnt := Label.new()
			cnt.text = "×%d" % int(e.n)
			cnt.add_theme_font_override("font", Hud.font(true))
			cnt.add_theme_font_size_override("font_size", 15)
			cnt.add_theme_color_override("font_color", Notebook.ACCENT)
			cnt.position = Vector2(66, 4)
			cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(cnt)
	else:
		var f: Dictionary = e.fish
		ic.set_icon("fish", fish_color(str(f.name)))
		nm.text = "%s\n%s" % [str(f.name).trim_prefix("Cá "), Fishing._kg(float(f.kg))]
	return b


static func fish_color(name_s: String) -> Color:
	match name_s:
		"Cá chép đỏ": return Palette.ICON_FISH_RED
		"Cá chép": return Palette.ICON_FISH_GOLD
		"Cá trê": return Palette.ICON_FISH_DARK
		"Cá diếc": return Palette.ICON_LONGAN
	return Palette.ICON_FISH


func _refresh_selection() -> void:
	var slots := _grid.get_children()
	for k in slots.size():
		(slots[k] as Button).set_pressed_no_signal(k == _sel)
	if _entries.is_empty():
		_detail_icon.set_icon("")
		_detail_name.text = "Túi trống" if TABS[_tab] != "fish" else "Giỏ cá trống"
		_detail_sub.text = ""
		_detail_desc.text = ("Ngồi câu ở bến sông, cá câu được nằm ở đây — đem bán cho hàng cá ở chợ phiên." if TABS[_tab] == "fish"
				else "Mua đồ ở chợ phiên (sáng mùng 1, 6, 11, 16, 21, 26 âm lịch), giúp việc dân làng để nhận quà, thắng trò dân gian có thưởng.")
		_use_button.visible = false
		_drop_button.visible = false
		return
	var e: Dictionary = _entries[_sel]
	if str(e.kind) == "fish":
		var f: Dictionary = e.fish
		var price := maxi(1, roundi(float(f.kg) * float(Market.FISH_PRICE.get(str(f.name), 18))))
		_detail_icon.set_icon("fish", fish_color(str(f.name)))
		_detail_name.text = str(f.name)
		_detail_sub.text = "Cá trong giỏ  ·  %s" % Fishing._kg(float(f.kg))
		_detail_desc.text = "Hàng cá ở chợ phiên mua khoảng %d nghìn. Ai nhờ câu đúng loài này thì đem tới đưa." % price
		_use_button.visible = false
		_drop_button.visible = false
		return
	var id := str(e.id)
	var it: Dictionary = ITEMS[id]
	_detail_icon.set_icon(str(it.icon))
	_detail_name.text = item_name(id).substr(0, 1).to_upper() + item_name(id).substr(1)
	var sub := "%s  ·  có %d  ·  giá chợ %d nghìn" % [CATS[str(it.cat)], int(e.n), int(it.price)]
	_detail_sub.text = sub
	var desc := str(it.desc)
	match str(it.use):
		"eat", "drink":
			desc += "\n\n%s: no bụng thêm %s (chạy nhanh hơn, chèo thuyền và kéo co đỡ mệt)." % [
					"Uống" if str(it.use) == "drink" else "Ăn", _clock(float(it.energy))]
		"kite":
			desc += "\n\nDùng khi nhập vai ở chỗ thoáng (bờ ruộng, sân trước nhà)."
	if str(it.stall) != "":
		desc += "\nBán lại ở chợ: %d nghìn." % maxi(1, int(int(it.price) * resell_ratio))
	if not (it.likes as Array).is_empty():
		desc += "\nBiếu %s thì họ thích lắm." % ", ".join((it.likes as Array).map(func(r: String) -> String: return _role_word(r)))
	_detail_desc.text = desc
	_use_button.visible = usable(id)
	_use_button.text = {"eat": "Ăn (E)", "drink": "Pha chè uống (E)", "bait": "Móc mồi (E)", "kite": "Thả diều (E)",
			"flute": "Thổi sáo (E)"}.get(str(it.use), "Dùng (E)")
	_drop_button.visible = true


static func _role_word(r: String) -> String:
	return {"kid": "trẻ con", "herder": "trẻ chăn trâu", "elder": "các cụ", "farmer": "nhà nông",
			"carrier": "người gánh hàng"}.get(r, r)


func _status_text() -> String:
	var parts: Array[String] = []
	parts.append(("No bụng: còn %s" % _clock(energy)) if energy > 0.0 else "Bụng đói (ăn gì đó để chạy nhanh hơn)")
	if fishing != null and fishing.bait > 0:
		parts.append("Mồi giun: %d lượt" % fishing.bait)
	if quests != null and not quests.items.is_empty():
		parts.append("Đang cầm: " + ", ".join(quests.items))
	parts.append("Đã kiếm %d · đã tiêu %d nghìn" % [earned, spent])
	return "   ·   ".join(parts)


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 3.0
	_toast.visible = true
	_toast.modulate.a = 1.0


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -520
	panel.offset_top = -330
	panel.offset_right = 520
	panel.offset_bottom = 330
	var sb := StyleBoxFlat.new()
	sb.bg_color = Notebook.PAPER
	sb.border_color = Palette.WOOD
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 18
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	# Tiêu đề + túi tiền
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label(true, 26, Notebook.ACCENT, "Túi đồ")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_money_label = _label(true, 20, Notebook.INK, "")
	head.add_child(_money_label)
	# Ngăn
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	for k in TABS.size():
		var b := Button.new()
		b.text = TAB_NAMES[TABS[k]]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", Hud.font(true))
		b.add_theme_font_size_override("font_size", 15)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var t := StyleBoxFlat.new()
			t.bg_color = Notebook.ACCENT if state.contains("pressed") else Color(Notebook.INK_SOFT, 0.18 if state == "hover" else 0.1)
			t.set_corner_radius_all(6)
			t.content_margin_left = 14
			t.content_margin_right = 14
			t.content_margin_top = 4
			t.content_margin_bottom = 4
			b.add_theme_stylebox_override(state, t)
		b.add_theme_color_override("font_color", Notebook.INK)
		b.add_theme_color_override("font_pressed_color", Notebook.PAPER)
		b.add_theme_color_override("font_hover_pressed_color", Notebook.PAPER)
		b.add_theme_color_override("font_hover_color", Notebook.INK)
		b.pressed.connect(set_tab.bind(k))
		tabs.add_child(b)
		_tab_buttons.append(b)
	# Lưới ô + chi tiết
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(612, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	var det := VBoxContainer.new()
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	det.add_theme_constant_override("separation", 8)
	body.add_child(det)
	_detail_icon = ItemIcon.new()
	_detail_icon.custom_minimum_size = Vector2(110, 110)
	_detail_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	det.add_child(_detail_icon)
	_detail_name = _label(true, 22, Notebook.INK, "")
	det.add_child(_detail_name)
	_detail_sub = _label(false, 14, Notebook.INK_SOFT, "")
	det.add_child(_detail_sub)
	_detail_desc = _label(false, 15, Notebook.INK, "")
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(320, 0)
	det.add_child(_detail_desc)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	det.add_child(spacer)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	det.add_child(btns)
	_use_button = _button("Dùng (E)", true)
	_use_button.pressed.connect(_use_selected)
	btns.add_child(_use_button)
	_drop_button = _button("Bỏ đi 1", false)
	_drop_button.pressed.connect(_drop_selected)
	btns.add_child(_drop_button)
	# Dòng trạng thái + phím
	_status = _label(false, 14, Notebook.INK, "")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	col.add_child(_label(false, 13, Notebook.INK_SOFT, "I / Esc: gấp túi    A / D: đổi ngăn    W / S hoặc bấm ô: chọn món    E: dùng"))
	# Chữ báo (hiện cả khi túi gấp)
	_toast = Label.new()
	_toast.add_theme_font_override("font", Hud.font(true))
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", Palette.HUD_TEXT)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.offset_top = 150
	_toast.visible = false
	add_child(_toast)


func _label(bold: bool, sz: int, c: Color, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Hud.font(bold))
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	return l


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Hud.font(true))
	b.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed"]:
		var t := StyleBoxFlat.new()
		var base := Notebook.ACCENT if primary else Notebook.INK_SOFT
		t.bg_color = base.lightened(0.12) if state == "hover" else base
		t.set_corner_radius_all(8)
		t.content_margin_left = 18
		t.content_margin_right = 18
		t.content_margin_top = 8
		t.content_margin_bottom = 8
		b.add_theme_stylebox_override(state, t)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Notebook.PAPER)
	return b


# --- Biểu tượng vẽ bằng code --------------------------------------------------------------------------------

## Một biểu tượng vật phẩm vẽ bằng hình phẳng (khung 64 × 64, tự co giãn theo kích thước).
class ItemIcon extends Control:
	var icon: String = ""
	var tint: Color = Color.WHITE

	func set_icon(key: String, c: Color = Color.WHITE) -> void:
		icon = key
		tint = c
		queue_redraw()

	func _draw() -> void:
		if icon == "":
			return
		var k := minf(size.x, size.y) / 64.0
		draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5), 0.0, Vector2(k, k))
		var ink := Notebook.INK
		match icon:
			"banana":
				for i in 3:
					var pts := PackedVector2Array()
					for a in 9:
						var t := float(a) / 8.0
						pts.append(Vector2(14 + 36 * t, 22 + i * 7 + 18 * sin(t * PI)))
					draw_polyline(pts, Palette.FLOWER_YELLOW, 8.0, true)
				draw_line(Vector2(10, 20), Vector2(16, 26), Palette.BANANA_TRUNK, 5.0)
			"pomelo":
				draw_circle(Vector2(32, 36), 20, Palette.ICON_POMELO)
				draw_circle(Vector2(27, 31), 6, Palette.ICON_POMELO.lightened(0.25))
				draw_colored_polygon(PackedVector2Array([Vector2(32, 16), Vector2(44, 6), Vector2(40, 18)]), Palette.LILY)
			"longan", "sim":
				var c := Palette.ICON_LONGAN if icon == "longan" else Palette.ICON_SIM
				draw_line(Vector2(32, 6), Vector2(32, 20), Palette.WOOD, 3.0)
				for p: Vector2 in [Vector2(24, 26), Vector2(40, 26), Vector2(32, 30), Vector2(20, 38), Vector2(32, 42),
						Vector2(44, 38), Vector2(26, 50), Vector2(38, 50)]:
					draw_circle(p, 7, c)
					draw_circle(p + Vector2(-2, -2), 2, c.lightened(0.35))
			"guava":
				draw_circle(Vector2(30, 38), 16, Palette.ICON_GUAVA)
				draw_circle(Vector2(42, 30), 12, Palette.ICON_GUAVA.darkened(0.08))
				draw_colored_polygon(PackedVector2Array([Vector2(40, 18), Vector2(52, 10), Vector2(48, 22)]), Palette.LILY)
			"potato":
				for p: Vector2 in [Vector2(22, 40), Vector2(40, 42), Vector2(32, 28)]:
					draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5) + p * k, 0.4, Vector2(k * 1.6, k))
					draw_circle(Vector2.ZERO, 8, Palette.ICON_POTATO)
				draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5), 0.0, Vector2(k, k))
			"cracker":
				draw_circle(Vector2(32, 32), 24, Palette.ICON_CANDY.lightened(0.3))
				draw_arc(Vector2(32, 32), 24, 0, TAU, 32, Palette.ICON_CANDY, 2.0)
				for i in 12:
					var a := i * 2.4
					draw_circle(Vector2(32, 32) + Vector2(cos(a), sin(a)) * (6 + i * 1.4), 1.6, ink)
			"candy":
				draw_rect(Rect2(12, 22, 40, 22), Palette.ICON_CANDY)
				for i in 8:
					draw_circle(Vector2(18 + (i % 4) * 9, 28 + (i / 4) * 9), 2.5, Palette.ICON_EGG)
			"ricecake":
				draw_circle(Vector2(32, 26), 16, Palette.ICON_RICE_CAKE)
				draw_arc(Vector2(32, 26), 16, 0, TAU, 28, Palette.SACK.darkened(0.15), 2.0)
				draw_circle(Vector2(32, 42), 16, Palette.ICON_RICE_CAKE)
				draw_arc(Vector2(32, 42), 16, 0, TAU, 28, Palette.SACK.darkened(0.15), 2.0)
			"taffy":
				draw_line(Vector2(14, 50), Vector2(50, 14), Palette.ICON_RICE_CAKE, 10.0)
				for i in 5:
					var p := Vector2(18 + i * 7, 46 - i * 7)
					draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), Palette.SACK.darkened(0.2), 2.0)
			"packet", "tea":
				var c := Palette.BANANA if icon == "packet" else Palette.LILY.darkened(0.1)
				draw_colored_polygon(PackedVector2Array([Vector2(32, 10), Vector2(54, 32), Vector2(32, 54), Vector2(10, 32)]), c)
				draw_line(Vector2(21, 21), Vector2(43, 43), Palette.STRAW, 3.0)
				draw_line(Vector2(43, 21), Vector2(21, 43), Palette.STRAW, 3.0)
				if icon == "tea":
					draw_rect(Rect2(22, 26, 20, 12), Palette.FLAG_RED)
			"bait":
				draw_rect(Rect2(12, 26, 40, 26), Palette.JAR)
				draw_rect(Rect2(10, 22, 44, 6), Palette.JAR.darkened(0.2))
				var pts := PackedVector2Array()
				for a in 10:
					pts.append(Vector2(18 + a * 3, 18 - 4 * sin(a * 1.1)))
				draw_polyline(pts, Palette.FLOWER_PINK, 4.0, true)
			"kite":
				draw_colored_polygon(PackedVector2Array([Vector2(32, 6), Vector2(52, 26), Vector2(32, 46)]), Palette.FLAG_RED)
				draw_colored_polygon(PackedVector2Array([Vector2(32, 6), Vector2(12, 26), Vector2(32, 46)]), Palette.FLOWER_YELLOW)
				draw_line(Vector2(32, 6), Vector2(32, 46), Palette.WOOD, 2.0)
				draw_line(Vector2(12, 26), Vector2(52, 26), Palette.WOOD, 2.0)
				var tail := PackedVector2Array()
				for a in 8:
					tail.append(Vector2(32 + 5 * sin(a * 1.2), 46 + a * 2.4))
				draw_polyline(tail, Palette.FLAG_RED, 2.5, true)
			"flute":
				draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5) + Vector2(32, 32) * k, -0.6, Vector2(k, k))
				draw_rect(Rect2(-28, -4, 56, 8), Palette.BAMBOO_STEM.lightened(0.15))
				draw_rect(Rect2(-12, -4, 2, 8), Palette.BAMBOO_NODE)
				for i in 6:
					draw_circle(Vector2(-4 + i * 5, 0), 1.6, ink)
				draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5), 0.0, Vector2(k, k))
			"top":
				draw_colored_polygon(PackedVector2Array([Vector2(12, 26), Vector2(52, 26), Vector2(32, 54)]), Palette.WOOD_LIGHT)
				draw_rect(Rect2(12, 22, 40, 6), Palette.FLAG_RED)
				draw_line(Vector2(32, 22), Vector2(32, 10), Palette.WOOD, 4.0)
			"marbles":
				for p: Array in [[Vector2(22, 38), Palette.FLAG_RED], [Vector2(40, 40), Palette.SIGN_BLUE], [Vector2(31, 24), Palette.LILY]]:
					draw_circle(p[0], 10, p[1])
					draw_circle((p[0] as Vector2) + Vector2(-3, -3), 3, Color(1, 1, 1, 0.7))
			"fan":
				draw_colored_polygon(PackedVector2Array([Vector2(32, 50), Vector2(8, 22), Vector2(20, 12), Vector2(32, 9),
						Vector2(44, 12), Vector2(56, 22)]), Palette.STRAW)
				for i in 7:
					var a := lerpf(-2.3, -0.84, float(i) / 6.0)
					draw_line(Vector2(32, 50), Vector2(32, 50) + Vector2(cos(a), sin(a)) * 40, Palette.WOOD_LIGHT, 1.5)
				draw_line(Vector2(32, 50), Vector2(32, 60), Palette.WOOD, 4.0)
			"hat":
				draw_colored_polygon(PackedVector2Array([Vector2(32, 10), Vector2(58, 46), Vector2(6, 46)]), Palette.HAT)
				draw_colored_polygon(PackedVector2Array([Vector2(32, 10), Vector2(58, 46), Vector2(32, 46)]), Palette.HAT_DARK)
				for i in 3:
					var y := 22 + i * 8
					draw_line(Vector2(32 - (y - 10) * 0.72, y), Vector2(32 + (y - 10) * 0.72, y), Palette.HAT_DARK.darkened(0.1), 1.0)
			"greens":
				for i in 7:
					var x := 18 + i * 4.5
					draw_line(Vector2(32, 54), Vector2(x, 10 + (i % 2) * 6), Palette.VEGETABLE.lightened(0.05 * (i % 3)), 4.0)
				draw_rect(Rect2(24, 40, 16, 5), Palette.STRAW)
			"shrimp":
				for i in 3:
					var c := Vector2(20 + i * 12, 30 + (i % 2) * 10)
					draw_arc(c, 7, 0.4, 4.5, 10, Palette.ICON_FISH_RED.lightened(0.2), 4.0)
			"fish":
				var c := tint if tint != Color.WHITE else Palette.ICON_FISH
				draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5) + Vector2(28, 32) * k, 0.0, Vector2(k * 1.9, k))
				draw_circle(Vector2.ZERO, 11, c)
				draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5), 0.0, Vector2(k, k))
				draw_colored_polygon(PackedVector2Array([Vector2(46, 32), Vector2(60, 20), Vector2(60, 44)]), c.darkened(0.15))
				draw_circle(Vector2(14, 29), 2.2, ink)
			"eggs", "duck_eggs":
				var c := Palette.ICON_EGG if icon == "eggs" else Palette.ICON_DUCK_EGG
				draw_rect(Rect2(8, 40, 48, 14), Palette.STRAW)
				for p: Vector2 in [Vector2(18, 36), Vector2(32, 34), Vector2(46, 36), Vector2(25, 26), Vector2(39, 26)]:
					draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5) + p * k, 0.0, Vector2(k * 0.8, k))
					draw_circle(Vector2.ZERO, 8, c)
				draw_set_transform(Vector2((size.x - 64.0 * k) * 0.5, (size.y - 64.0 * k) * 0.5), 0.0, Vector2(k, k))
			"sack":
				var bag := PackedVector2Array([Vector2(16, 18), Vector2(48, 18), Vector2(54, 54), Vector2(10, 54)])
				draw_colored_polygon(bag, Palette.SACK.darkened(0.08))
				bag.append(bag[0])
				draw_polyline(bag, Palette.WOOD_LIGHT, 2.0)
				draw_rect(Rect2(20, 12, 24, 8), Palette.SACK.darkened(0.1))
				draw_line(Vector2(18, 20), Vector2(46, 20), Palette.WOOD, 3.0)
				for i in 6:
					draw_circle(Vector2(26 + (i % 3) * 6, 12 + (i / 3) * 4), 1.6, Palette.ICON_RICE_CAKE)
			"pot":
				draw_colored_polygon(PackedVector2Array([Vector2(10, 24), Vector2(54, 24), Vector2(48, 50), Vector2(16, 50)]), Palette.JAR)
				draw_rect(Rect2(8, 20, 48, 6), Palette.JAR.darkened(0.2))
				draw_rect(Rect2(24, 12, 16, 6), Palette.JAR.darkened(0.25))
			"bowl":
				draw_colored_polygon(PackedVector2Array([Vector2(8, 26), Vector2(56, 26), Vector2(44, 48), Vector2(20, 48)]), Palette.CERAMIC)
				draw_line(Vector2(9, 30), Vector2(55, 30), Palette.SIGN_BLUE, 3.0)
				draw_rect(Rect2(26, 48, 12, 4), Palette.CERAMIC.darkened(0.1))
			"jar":
				draw_circle(Vector2(32, 38), 20, Palette.JAR)
				draw_rect(Rect2(20, 12, 24, 10), Palette.JAR.darkened(0.15))
				draw_circle(Vector2(25, 32), 5, Palette.JAR.lightened(0.15))
			_:
				draw_rect(Rect2(14, 14, 36, 36), Palette.WOOD_LIGHT)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
