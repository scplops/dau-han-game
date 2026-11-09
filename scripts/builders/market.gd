class_name Market
extends Node3D
## Chợ phiên đầu làng (mục 40). Bãi cỏ ngoài cổng làng phía đông nam (giữa đường đất và cây đa nhà mình): hai dãy lều
## tre mái lá / mái bạt quay mặt vào lối giữa, `stall_count` sạp — rau, hoa quả, cá, gà vịt, gạo, đồ gốm, nón quạt,
## bánh kẹo. Lều dựng sẵn; hàng hoá chỉ bày ra trong phiên chợ.
## - Phiên chợ: ngày âm lịch chia 5 dư 1 (mùng 1, 6, 11, 16, 21, 26), buổi sáng `market_hours`.
## - Người bán: lúc chợ mở, Market gọi người gánh hàng (thiếu thì nông dân nữ) ra sạp (việc `market_sell`), ngồi ghế
##   đẩu sau sạp; tan chợ thì về. Người đi chợ: việc `market` của Villagers (phụ nữ, cụ già, trẻ con) — đứng trước sạp.
## - Người chơi (nhập vai, trò chuyện với người bán): xem hàng → mua (tiền `money`, đồ vào `bag`); hàng cá mua cá trong
##   giỏ theo cân × giá loài; đồ đã mua đem biếu dân làng (Dialogue: "Biếu … chút quà") — họ quý hơn.

signal traded(text: String)

@export var village: Village
@export var calendar: LunarCalendar
@export var day_night: DayNight
@export var weather: Weather
@export var villagers: Villagers
@export var fishing: Fishing
@export var random_seed: int = 1906
@export_group("Bố cục")
## Tâm lối đi giữa hai dãy lều.
@export var origin: Vector3 = Vector3(7.2, 0.0, -20.5)
@export var stall_spacing: float = 3.8
@export var row_offset: float = 3.6
@export_group("Phiên chợ")
## Giờ họp chợ (giờ trong game).
@export var market_hours: Vector2 = Vector2(5.5, 11.5)
## Gọi người bán ra chợ sớm hơn giờ họp bao nhiêu giờ (gánh hàng từ trong làng ra mất một lúc).
@export var prep_hours: float = 1.25
## Tiền người chơi có lúc bắt đầu (nghìn đồng).
@export var start_money: int = 20

## Các sạp: loại, tên, hàng bán (tên, giá nghìn đồng).
const STALLS: Array = [
	{"kind": "veg", "name": "Hàng rau", "items": [["bó rau muống", 2], ["mớ rau cải", 2], ["bó hành lá", 1]]},
	{"kind": "fruit", "name": "Hàng hoa quả", "items": [["nải chuối", 5], ["quả bưởi", 8], ["chùm nhãn", 6]]},
	{"kind": "fish", "name": "Hàng cá", "items": [["mớ tép", 5], ["xâu cá rô", 9]]},
	{"kind": "poultry", "name": "Hàng gà vịt", "items": [["chục trứng gà", 12], ["chục trứng vịt", 10]]},
	{"kind": "rice", "name": "Hàng gạo", "items": [["cân gạo nếp", 10], ["cân gạo tám", 9]]},
	{"kind": "pottery", "name": "Hàng đồ gốm", "items": [["cái nồi đất", 12], ["cái bát men", 4], ["cái chum nhỏ", 25]]},
	{"kind": "hats", "name": "Hàng nón quạt", "items": [["cái nón lá", 15], ["cái quạt nan", 3]]},
	{"kind": "sweets", "name": "Hàng bánh kẹo", "items": [["cái bánh đa", 2], ["gói kẹo lạc", 1], ["đôi bánh giầy", 3], ["cái kẹo kéo", 1]]},
]
## Giá cá hàng cá mua lại (nghìn đồng / kg).
const FISH_PRICE := {"Cá chép": 25, "Cá chép đỏ": 30, "Cá diếc": 20, "Cá trắm cỏ": 22, "Cá trê": 28, "Cá mè trắng": 15}

var stalls: Array[Dictionary] = []   # {kind, name, items, pos (giữa sạp), face (hướng nhìn ra lối), seat, seller}
var entry_path: PackedVector2Array    # từ đường đất vào lối giữa chợ (Villagers nối vào đồ thị đường)
var aisle: PackedVector2Array
var money: int = 20
var bag: Array[String] = []           # đồ đã mua, chưa biếu
var is_open: bool = false
var _goods: Node3D
var _rng := RandomNumberGenerator.new()
var _check: float = 0.0
var _called: bool = false


func build() -> void:
	_rng.seed = random_seed
	money = start_money
	var mb := MeshBuilder.new(random_seed, 0.05)
	mb.contact_shade_height = 0.5
	mb.contact_shade_strength = 0.2
	var goods := MeshBuilder.new(random_seed + 1, 0.06)
	var leaves := MeshBuilder.new(random_seed + 2, 0.06)
	var half := STALLS.size() / 2
	for i in STALLS.size():
		var north := i < half
		var k := i if north else i - half
		var x := origin.x + (k - (half - 1) * 0.5) * stall_spacing
		var z := origin.z + (-row_offset if north else row_offset)
		var face := Vector3(0, 0, 1) if north else Vector3(0, 0, -1)    # mặt sạp hướng ra lối giữa
		var pos := Vector3(x + _rng.randf_range(-0.2, 0.2), 0.0, z + _rng.randf_range(-0.15, 0.15))
		var st: Dictionary = (STALLS[i] as Dictionary).duplicate(true)
		st["pos"] = pos
		st["face"] = face
		st["seat"] = pos - face * 1.15                 # ghế đẩu sau sạp
		st["front"] = pos + face * 1.5                 # chỗ người mua đứng
		st["seller"] = null
		stalls.append(st)
		_stall(mb, leaves, st, i)
		_goods_for(goods, st)
	var x0 := origin.x - half * stall_spacing * 0.5 - 1.5
	var x1 := origin.x + half * stall_spacing * 0.5 + 1.5
	aisle = PackedVector2Array([Vector2(x0, origin.z), Vector2(x1, origin.z)])
	# Lối vào từ đường đất (khe giữa hai lều dãy bắc gần giữa)
	var gx := origin.x
	entry_path = PackedVector2Array([Vector2(gx, origin.z - row_offset - 4.5), Vector2(gx, origin.z)])
	# Nền đất nện lối giữa chợ
	var ground := MeshBuilder.new(random_seed + 3, 0.08)
	ground.add_quad(Vector3(x0, 0.02, origin.z - 1.4), Vector3(x1, 0.02, origin.z - 1.4), Vector3(x1, 0.02, origin.z + 1.4),
			Vector3(x0, 0.02, origin.z + 1.4), Palette.EARTH.lightened(0.05), Vector3(origin.x, -1, origin.z))
	ground.add_quad(Vector3(gx - 0.9, 0.025, origin.z - row_offset - 4.5), Vector3(gx + 0.9, 0.025, origin.z - row_offset - 4.5),
			Vector3(gx + 0.9, 0.025, origin.z), Vector3(gx - 0.9, 0.025, origin.z), Palette.EARTH.lightened(0.05), Vector3(gx, -1, origin.z))
	var g := ground.commit_instance("MarketGround")
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	add_child(mb.commit_instance("Stalls"))
	if leaves.triangle_count() > 0:
		add_child(leaves.commit_instance("StallRoofs", MeshBuilder.wind_material(0.03, 1.8, 1.0, 0.8)))
	_goods = goods.commit_instance("Goods")
	add_child(_goods)
	_goods.visible = false
	# Biển chợ
	var sign := Label3D.new()
	sign.text = "CHỢ PHIÊN"
	sign.font = Hud.font(true)
	sign.font_size = 96
	sign.pixel_size = 0.01
	sign.modulate = Palette.FLAG_RED
	sign.outline_size = 14
	sign.outline_modulate = Palette.HAT
	sign.position = Vector3(gx, 3.2, origin.z - row_offset - 3.6)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y     # đọc được từ cả hai phía
	add_child(sign)
	var post := MeshBuilder.new(9, 0.03)
	for s in [-1.0, 1.0]:
		post.add_limb(Vector3(gx + s * 1.3, 0, origin.z - row_offset - 3.6), Vector3(gx + s * 1.3, 3.4, origin.z - row_offset - 3.6), 0.06, 0.05, 5, Palette.BAMBOO_STEM)
	post.add_limb(Vector3(gx - 1.4, 3.3, origin.z - row_offset - 3.6), Vector3(gx + 1.4, 3.3, origin.z - row_offset - 3.6), 0.05, 0.05, 5, Palette.BAMBOO_STEM)
	add_child(post.commit_instance("Gate"))


static func _xf(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## Một lều: 4 cột tre, sạp tre, mái lá (hoặc bạt xanh) dốc ra lối đi, ghế đẩu sau sạp.
func _stall(mb: MeshBuilder, leaves: MeshBuilder, st: Dictionary, i: int) -> void:
	var p: Vector3 = st.pos
	var f: Vector3 = st.face
	var b := Basis(Vector3.UP, 0.0 if f.z > 0.0 else PI)
	var xf := Transform3D(b, p)
	var w := 2.7
	var d := 1.3
	var h := 0.72
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_prism(0.04, 0.035, h, 5, Palette.BAMBOO_STEM, xf * _xf(sx * (w * 0.5 - 0.1), 0, sz * (d * 0.5 - 0.1)))
	# Mặt sạp: nan tre
	mb.add_box(Vector3(w, 0.04, d), Palette.BAMBOO_STEM.darkened(0.1), xf * _xf(0, h, 0))
	var n := 9
	for k in n:
		mb.add_box(Vector3(w - 0.04, 0.02, d / n - 0.02), Palette.BAMBOO_STEM.lightened(0.08), xf * _xf(0, h + 0.04, -d * 0.5 + d * (k + 0.5) / n))
	# Cột mái: sau cao, trước thấp (mái dốc ra lối)
	var back_h := 2.5
	var front_h := 2.1
	for sx in [-1.0, 1.0]:
		mb.add_limb(xf * Vector3(sx * (w * 0.5 + 0.05), 0, -d * 0.5 - 0.5), xf * Vector3(sx * (w * 0.5 + 0.05), back_h, -d * 0.5 - 0.5), 0.05, 0.045, 5, Palette.BAMBOO_STEM)
		mb.add_limb(xf * Vector3(sx * (w * 0.5 + 0.05), 0, d * 0.5 + 0.35), xf * Vector3(sx * (w * 0.5 + 0.05), front_h, d * 0.5 + 0.35), 0.05, 0.045, 5, Palette.BAMBOO_STEM)
	# Mái: lá cọ (rung nhẹ trong gió) hoặc bạt xanh
	var a := xf * Vector3(-w * 0.5 - 0.3, back_h + 0.05, -d * 0.5 - 0.7)
	var bb := xf * Vector3(w * 0.5 + 0.3, back_h + 0.05, -d * 0.5 - 0.7)
	var c := xf * Vector3(w * 0.5 + 0.3, front_h - 0.05, d * 0.5 + 0.7)
	var dd := xf * Vector3(-w * 0.5 - 0.3, front_h - 0.05, d * 0.5 + 0.7)
	var tarp := i % 3 == 1
	var col := Palette.SIGN_BLUE.lightened(0.15) if tarp else Palette.THATCH
	var under := (a + c) * 0.5 - Vector3(0, 1, 0)
	if tarp:
		mb.add_quad(a, bb, c, dd, col, under)
		mb.add_quad(dd, c, bb, a, col.darkened(0.2), (a + c) * 0.5 + Vector3(0, 1, 0))
	else:
		leaves.add_quad(a, bb, c, dd, col, under)
		leaves.add_quad(dd, c, bb, a, Palette.THATCH_DARK, (a + c) * 0.5 + Vector3(0, 1, 0))
	# Ghế đẩu cho người bán
	var seat: Vector3 = st.seat
	mb.add_box(Vector3(0.36, 0.32, 0.3), Palette.WOOD, Transform3D(b, seat))


## Hàng bày trên sạp (chỉ hiện trong phiên chợ).
func _goods_for(mb: MeshBuilder, st: Dictionary) -> void:
	var p: Vector3 = st.pos
	var b := Basis(Vector3.UP, 0.0 if (st.face as Vector3).z > 0.0 else PI)
	var top := 0.78
	var at := func(x: float, z: float, y: float = 0.0) -> Transform3D:
		return Transform3D(b, p + b * Vector3(x, top + y, z))
	match str(st.kind):
		"veg":
			for k in 6:
				var t: Transform3D = at.call(-1.0 + k * 0.4, _rng.randf_range(-0.3, 0.3))
				mb.add_prism(0.12, 0.16, 0.14, 7, Palette.VEGETABLE.lightened(_rng.randf_range(-0.1, 0.15)), t)
				mb.add_box(Vector3(0.06, 0.02, 0.06), Palette.STRAW, t * _xf(0, 0.06, 0))
		"fruit":
			for k in 3:
				var t: Transform3D = at.call(-0.9 + k * 0.45, -0.2)
				for j in 5:
					mb.add_ellipsoid(Vector3(0.045, 0.14, 0.045), Palette.BANANA, t * Transform3D(Basis(Vector3.BACK, 0.9).rotated(Vector3.UP, j * 0.25), Vector3(j * 0.06 - 0.12, 0.08, 0)), 5, 3)
			for k in 4:
				mb.add_ellipsoid(Vector3(0.11, 0.1, 0.11), Palette.RICE_3.darkened(0.05), at.call(0.4 + (k % 2) * 0.25, 0.1 + (k / 2) * 0.24, 0.1), 7, 4)
		"fish":
			for k in 2:
				var t: Transform3D = at.call(-0.6 + k * 1.1, 0.0)
				mb.add_prism(0.32, 0.36, 0.14, 10, Palette.ROCK.lightened(0.2), t)
				mb.add_prism(0.3, 0.3, 0.02, 10, Palette.WATER, t * _xf(0, 0.12, 0))
				for j in 3:
					mb.add_ellipsoid(Vector3(0.08, 0.035, 0.03), Palette.FLOWER_WHITE.darkened(0.2) if j % 2 == 0 else Palette.ROCK_DARK,
							t * Transform3D(Basis(Vector3.UP, j * 1.4), Vector3(_rng.randf_range(-0.15, 0.15), 0.15, _rng.randf_range(-0.15, 0.15))), 6, 3)
		"poultry":
			for k in 2:
				var t: Transform3D = at.call(-0.7 + k * 1.2, 0.0)
				mb.add_prism(0.3, 0.26, 0.42, 8, Palette.BAMBOO_STEM.lightened(0.15), t)            # lồng tre
				mb.add_ellipsoid(Vector3(0.12, 0.12, 0.16), Palette.FLOWER_WHITE if k == 0 else Palette.STRAW.darkened(0.25), t * _xf(0, 0.2, 0), 6, 4)
			for j in 10:
				mb.add_ellipsoid(Vector3(0.025, 0.033, 0.025), Palette.FLOWER_WHITE.darkened(0.08), at.call(-0.1 + (j % 5) * 0.06, 0.25 + (j / 5) * 0.06), 5, 3)
		"rice":
			for k in 3:
				var t: Transform3D = at.call(-0.9 + k * 0.9, 0.0)
				mb.add_prism(0.26, 0.3, 0.3, 9, Palette.SACK, t)                              # thúng
				mb.add_ellipsoid(Vector3(0.26, 0.09, 0.26), Palette.FLOWER_WHITE if k != 1 else Palette.STRAW.lightened(0.3), t * _xf(0, 0.28, 0), 8, 3)
		"pottery":
			for k in 4:
				var t: Transform3D = at.call(-1.0 + k * 0.65, _rng.randf_range(-0.2, 0.2))
				mb.add_ellipsoid(Vector3(0.16, 0.14, 0.16), Palette.JAR if k % 2 == 0 else Palette.CERAMIC, t * _xf(0, 0.12, 0), 8, 4)
				mb.add_prism(0.08, 0.1, 0.06, 8, Palette.JAR.darkened(0.1), t * _xf(0, 0.22, 0))
		"hats":
			for k in 3:
				for j in 4:
					mb.add_pyramid(0.24, 0.16, 12, Palette.HAT if j % 2 == 0 else Palette.HAT_DARK, at.call(-0.8 + k * 0.6, 0.0, j * 0.035))
			for k in 4:
				mb.add_box(Vector3(0.26, 0.015, 0.3), Palette.BAMBOO_STEM.lightened(0.2), at.call(0.95, -0.35 + k * 0.2))
		"sweets":
			for k in 2:
				var t: Transform3D = at.call(-0.6 + k * 1.1, 0.0)
				mb.add_prism(0.42, 0.42, 0.03, 12, Palette.STRAW, t)                          # mẹt
				for j in 5:
					var a := j * TAU / 5
					if k == 0:
						mb.add_prism(0.14, 0.14, 0.012, 10, Palette.WOOD_LIGHT.lightened(0.2), t * _xf(cos(a) * 0.2, 0.04 + j * 0.01, sin(a) * 0.2))   # bánh đa
					else:
						mb.add_box(Vector3(0.12, 0.05, 0.08), Palette.FLOWER_YELLOW.darkened(0.3), t * _xf(cos(a) * 0.22, 0.04, sin(a) * 0.22))    # kẹo lạc


# --- Phiên chợ -----------------------------------------------------------------------------------------

## Hôm nay có phiên chợ không (ngày âm 1, 6, 11, 16, 21, 26).
func is_market_day() -> bool:
	if calendar == null:
		return false
	return int(calendar.lunar().day) % 5 == 1


func open_now() -> bool:
	var h := day_night.time_of_day if day_night != null else 8.0
	return is_market_day() and h >= market_hours.x and h < market_hours.y \
			and (weather == null or weather.kind != "storm")


## Câu mô tả cho sổ tay / hội thoại.
func status_text() -> String:
	if calendar == null:
		return ""
	var day := int(calendar.lunar().day)
	if is_market_day():
		return "hôm nay có phiên (%s–%s)%s" % [_hm(market_hours.x), _hm(market_hours.y), "  ·  đang họp" if is_open else ""]
	for k in range(1, 6):
		var l: Dictionary = calendar.lunar_at(calendar.jd + k)
		if int(l.day) % 5 == 1:
			return "phiên tới ngày %d âm lịch (còn %d ngày)" % [int(l.day), k]
	return ""


static func _hm(h: float) -> String:
	return "%d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	var h := day_night.time_of_day if day_night != null else 8.0
	var prep := is_market_day() and h >= market_hours.x - prep_hours and h < market_hours.y \
			and (weather == null or weather.kind != "storm")
	if prep and not _called:
		_called = true
		_call_sellers(h >= market_hours.x + 0.2)   # giờ nhảy thẳng vào lúc chợ đang họp: người bán ngồi sẵn
	var now := open_now()
	if now != is_open:
		is_open = now
		_goods.visible = now
	if not prep and _called:
		_called = false
		_release_sellers()


## Sắp họp chợ: gọi người bán ra từng sạp (người gánh hàng trước, thiếu thì phụ nữ làm ruộng).
## `instant`: đặt ngay vào sạp (giờ bị chỉnh nhảy vào giữa phiên chợ, hoặc mở game đã lưu).
func _call_sellers(instant: bool = false) -> void:
	if villagers == null:
		return
	var pool: Array[Villager] = []
	for v in villagers.people:
		if v.role == "carrier" and not v.has_meta("talking"):
			pool.append(v)
	for v in villagers.people:
		if v.role == "farmer" and v.get_meta("female", false) and not v.has_meta("talking"):
			pool.append(v)
	for st in stalls:
		if st.seller != null and is_instance_valid(st.seller):
			continue
		if pool.is_empty():
			break
		var v: Villager = pool.pop_front()
		st.seller = v
		v.set_meta("market_stall", stalls.find(st))
		villagers._next_activity(v, "market_sell")
		if instant:
			v.path = PackedVector3Array()
			v.state = Villager.State.IDLE
			v.visible = true
			v.set_meta("at_home", false)
			v.activity_text = "đang ngồi bán hàng ở chợ"
			on_seller_arrive(v)


func _release_sellers() -> void:
	for st in stalls:
		var v: Villager = st.seller
		st.seller = null
		if v != null and is_instance_valid(v):
			v.remove_meta("market_stall")
			v.remove_meta("market_seller")
			if v.activity == "market_sell":
				v.dwell = 0.0


## Đích của người bán (Villagers `_target`).
func seller_target(v: Villager) -> Vector3:
	var i := int(v.get_meta("market_stall", -1))
	if i < 0 or i >= stalls.size():
		return origin
	return stalls[i].seat


## Người bán tới sạp: ngồi ghế đẩu, mặt ra lối đi, ngồi tới khi tan chợ.
func on_seller_arrive(v: Villager) -> void:
	var i := int(v.get_meta("market_stall", -1))
	if i < 0 or not _called:
		v.dwell = 0.0
		return
	var st: Dictionary = stalls[i]
	v.set_meta("market_seller", i)
	v.global_position = st.seat
	var f: Vector3 = st.face
	v.rotation.y = atan2(f.x, f.z)
	v.work_anim = "sit"
	v.dwell = 1.0e6
	if v.prop_node != null:
		v.prop_node.visible = false
	v.activity_text = "đang bán " + str(st.name).to_lower().trim_prefix("hàng ")


## Đích của người đi chợ: trước một sạp ngẫu nhiên.
func shopper_target() -> Vector3:
	var st: Dictionary = stalls[_rng.randi_range(0, stalls.size() - 1)]
	return (st.front as Vector3) + Vector3(_rng.randf_range(-0.9, 0.9), 0.05, 0.0)


## Người đi chợ tới nơi: quay mặt vào sạp gần nhất, đứng xem hàng / mặc cả.
func on_shopper_arrive(v: Villager) -> void:
	var best: Dictionary = stalls[0]
	for st in stalls:
		if (st.front as Vector3).distance_to(v.global_position) < (best.front as Vector3).distance_to(v.global_position):
			best = st
	var d: Vector3 = (best.pos as Vector3) - v.global_position
	v.rotation.y = atan2(d.x, d.z)
	v.work_anim = "chat"


# --- Mua bán với người chơi (qua hội thoại) -----------------------------------------------------------------

func stall_of(v: Villager) -> Dictionary:
	var i := int(v.get_meta("market_seller", -1))
	return stalls[i] if i >= 0 and i < stalls.size() else {}


## Các câu thêm vào khung thoại (Dialogue gọi): xem hàng, bán cá (hàng cá), biếu quà (ai cũng được).
func dialog_options(v: Villager, dlg: Dialogue) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st := stall_of(v)
	if not st.is_empty() and is_open:
		out.append({"key": "mk_buy", "repeat": true, "text": "{Npc} bán gì thế{a}? Cho {me} xem hàng.",
				"answer": func() -> String: return "%s đây, {you} xem đi. Hôm nay hàng tươi lắm! (Bạn có %d nghìn)" % [st.name, money],
				"next": func() -> Array[Dictionary]: return _buy_options(st, dlg)})
		if str(st.kind) == "fish" and fishing != null and not fishing.basket.is_empty():
			out.append({"key": "mk_sell", "repeat": true, "text": "{Npc} mua cá {me} câu được không{a}?",
					"answer": func() -> String: return sell_fish()})
	if not bag.is_empty():
		out.append({"key": "mk_gift", "repeat": true, "text": "{Me} biếu {npc} chút quà{a}.",
				"answer": func() -> String: return "Ôi, {you} quà cáp gì thế này…",
				"next": func() -> Array[Dictionary]: return _gift_options(v, dlg)})
	return out


func _buy_options(st: Dictionary, dlg: Dialogue) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Array in st.items:
		var nm: String = it[0]
		var price: int = it[1]
		out.append({"text": "Mua %s — %d nghìn" % [nm, price], "answer": func() -> String: return buy(nm, price),
				"next": func() -> Array[Dictionary]: return _buy_options(st, dlg)})
		if out.size() >= 3:
			break
	out.append({"text": "Thôi, {me} xem thế thôi{a}.", "end": true})
	return out


func _gift_options(v: Villager, dlg: Dialogue) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for nm in bag:
		if seen.has(nm):
			continue
		seen[nm] = true
		out.append({"text": "Biếu %s" % nm, "answer": func() -> String: return give(v, nm, dlg)})
		if out.size() >= 3:
			break
	out.append({"text": "Thôi, để lúc khác.", "end": true})
	return out


func buy(nm: String, price: int) -> String:
	if money < price:
		return "Ơ, {you} không đủ tiền rồi (còn %d nghìn). Câu cá bán cho hàng cá lấy tiền mà mua nhé." % money
	money -= price
	bag.append(nm)
	traded.emit("Mua %s · còn %d nghìn" % [nm, money])
	return "Đây, %s của {you} đây. Cầm cẩn thận nhé! (Còn %d nghìn)" % [nm, money]


## Hàng cá mua hết cá trong giỏ: cân × giá loài.
func sell_fish() -> String:
	if fishing == null or fishing.basket.is_empty():
		return "Giỏ có con nào đâu mà bán hả {you}?"
	var total := 0.0
	var n := fishing.basket.size()
	for b: Dictionary in fishing.basket:
		total += float(b.kg) * float(FISH_PRICE.get(str(b.name), 18))
	var got := maxi(1, roundi(total))
	fishing.basket.clear()
	fishing._update_log()
	money += got
	traded.emit("Bán %d con cá · được %d nghìn" % [n, got])
	return "Cá tươi thế này {self} lấy hết! %d con, {self} trả {you} %d nghìn nhé. (Bạn có %d nghìn)" % [n, got, money]


## Biếu quà: bỏ khỏi giỏ đồ, người nhận vui, nhớ người chơi lâu hơn.
func give(v: Villager, nm: String, dlg: Dialogue) -> String:
	var i := bag.find(nm)
	if i < 0:
		return "…"
	bag.remove_at(i)
	if dlg != null:
		var real: Villager = v.get_meta("proxy_of", v)
		dlg._met[real] = int(dlg._met.get(real, 0)) + 2
	traded.emit("Biếu %s %s" % [v.display_name, nm])
	var kid := v.role in ["kid", "herder"]
	if kid:
		return ["A, %s! Em cảm ơn {you}! Thích quá!" % nm, "Cho em thật ạ? Em cảm ơn {you} nhiều!"][_rng.randi_range(0, 1)]
	return ["Quý hoá quá, {you} biếu {self} %s à. Cảm ơn {you} nhé!" % nm,
			"Ôi, {you} chu đáo quá. Lần sau sang {self} mời nước chè nhé!"][_rng.randi_range(0, 1)]
