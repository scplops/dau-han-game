class_name Villagers
extends Node3D
## Dân làng và con vật đi lại theo lịch sinh hoạt (không hội thoại, không điều khiển).
## - Đường đi: đồ thị AStar3D dựng từ đường trục, các ngõ, đường đất ra đồng, lối vào sân nhà mình.
##   Đi từ nhà ra: cửa → trước hiên → cổng → ngõ…; về nhà thì ngược lại rồi "vào nhà" (ẩn đi).
## - Lịch: theo giờ của DayNight (sáng ra đồng, trưa về nghỉ, chiều đi chơi, tối về nhà);
##   mỗi việc kéo dài một lúc (giây thật) nên làng vẫn sống động cả khi giờ đứng yên.
## - Thời tiết: mưa phùn đi nhanh hơn; mưa giông thì ai cũng chạy về nhà trú, tạnh mới ra.
## - Con vật: trâu theo trẻ chăn trâu, chó theo chủ, gà mổ thóc trong sân, vịt bơi ở ao làng.
## - Bấm chuột trái vào người/vật: hiện tên, nhà, việc đang làm; F: camera đi theo.

const NIGHT_START := 20.5
const NIGHT_END := 5.2

@export var village: Village
@export var river: River
@export var school: School
@export var football: Football
@export var terrain: Terrain
@export var house: House
@export var day_night: DayNight
@export var calendar: LunarCalendar
@export var weather: Weather
@export var hud: Hud
@export var outdoor_rig: CameraRig
@export var random_seed: int = 4242

@export var school_day: SchoolDay
@export var hide_seek: HideSeek
@export var jump_rope: JumpRope
@export var tip_cat: TipCat
@export var farming: Farming
@export var o_an_quan: OAnQuan
@export var kite: KiteFlying

@export_group("Đi lễ đình (mùng 1, rằm)")
## Giờ đi lễ buổi sáng / buổi chiều (giờ trong game).
@export var worship_morning: Vector2 = Vector2(5.5, 9.5)
@export var worship_evening: Vector2 = Vector2(16.5, 19.0)
## Ở trong đình bao lâu (giây thật).
@export var worship_minutes: Vector2 = Vector2(30.0, 60.0)

@export_group("Số lượng")
## Mỗi nhà trong làng là một hộ: số người mỗi hộ (ngẫu nhiên trong khoảng, theo seed).
@export var household_size: Vector2i = Vector2i(3, 4)
## Tỉ lệ hộ có ông / bà sống cùng (ba thế hệ).
@export_range(0.0, 1.0) var elder_chance: float = 0.45
## Tỉ lệ con trong nhà đi chăn trâu (mỗi đứa chăn trâu có một con trâu).
@export_range(0.0, 1.0) var herder_chance: float = 0.16
## Tỉ lệ vợ đi gánh hàng (còn lại làm ruộng cùng chồng).
@export_range(0.0, 1.0) var carrier_chance: float = 0.35
## Giới hạn số hộ có người (0 = mọi nhà trong làng).
@export_range(0, 200) var max_households: int = 0
@export_range(0, 40) var dogs: int = 10
@export_range(0, 40) var chicken_yards: int = 12
@export_range(1, 8) var chickens_per_yard: int = 4
@export_range(0, 12) var ducks: int = 6
@export_range(0, 20) var lantern_walkers: int = 6

@export_group("Hiệu năng")
@export var animate_distance: float = 90.0

var people: Array[Villager] = []
var animals: Array[Villager] = []
var selected: Villager

var _astar := AStar3D.new()
var _next_id: int = 0
var _rng := RandomNumberGenerator.new()
var _homes: Array[Dictionary] = []
var _field_spots: Array[Vector3] = []
var _chickens: Array[Dictionary] = []     # {node, center}
var _duck_leader: Villager
var _weather_check: float = 0.0
var _info_timer: float = 0.0
var _following: bool = false
var _used_names: Dictionary = {}
## Số hộ có người ở (có sau build()).
var households: int = 0

const MALE := ["Tư", "Năm", "Sáu", "Bảy", "Tám", "Chín", "Hùng", "Dũng", "Lực", "Sửu", "Dần", "Mão", "Tỵ", "Thìn", "Khoai", "Bình", "Toàn", "Thắng",
		"Hai", "Ba", "Mười", "Cường", "Hải", "Long", "Quý", "Tý", "Ngọ", "Mùi", "Thân", "Tuất", "Hợi", "Sơn", "Thành", "Đức", "Phúc", "Lộc",
		"Thọ", "Khánh", "Chiến", "Tiến", "Vượng", "Hưng", "Nghĩa", "Trung", "Kiên", "Tùng"]
const FEMALE := ["Hoa", "Lan", "Mận", "Đào", "Thắm", "Liên", "Hà", "Nụ", "Huệ", "Cúc", "Xoan", "Gấm", "Nhài", "Sen", "Mơ", "Tươi",
		"Hồng", "Mai", "Thu", "Hương", "Nga", "Yến", "Loan", "Phượng", "Duyên", "Hạnh", "Thơm", "Mến", "Ngát", "Lụa", "Vân", "Bưởi",
		"Hằng", "Nhung", "Thoa", "Tuyết", "Quế", "Lý", "Thìn", "Hiền", "Lành", "Na"]
const KID := ["Tí", "Tèo", "Bống", "Mít", "Na", "Cốm", "Thóc", "Gạo", "Bin", "Bông", "Su", "Nhím", "Cò", "Bơ",
		"Cún", "Bi", "Bé", "Út", "Còi", "Đậu", "Lạc", "Vừng", "Ngô", "Khoai", "Sóc", "Chuột", "Tũn", "Bờm", "Hến", "Ốc",
		"Tôm", "Tép", "Mướp", "Bầu", "Bí", "Sắn", "Mỡ", "Cua", "Kẹo", "Mía", "Chanh", "Quýt", "Hạt", "Nhót", "Sấu", "Thị"]

const ROLE_NAMES := {
	"farmer": "Nông dân", "carrier": "Người gánh hàng", "elder": "Cụ già", "kid": "Trẻ con",
	"herder": "Trẻ chăn trâu", "buffalo": "Con trâu", "dog": "Con chó", "chicken": "Đàn gà", "duck": "Đàn vịt",
}
## [đang đi tới, đang ở đó]
const ACTIVITY_TEXT := {
	"field": ["đang ra đồng", "đang làm đồng"],
	"graze": ["đang dắt trâu ra đồng", "đang chăn trâu ngoài đồng"],
	"well": ["đang đi lấy nước", "đang gánh nước ở giếng làng"],
	"banyan": ["đang ra gốc đa", "đang ngồi nghỉ dưới gốc đa"],
	"pagoda": ["đang lên chùa", "đang đi lễ chùa"],
	"dinh": ["đang ra đình", "đang chơi ở sân đình"],
	"pond": ["đang ra ao làng", "đang chơi bên ao làng"],
	"visit": ["đang sang nhà hàng xóm", "đang ngồi chơi với hàng xóm"],
	"yard": ["đang về sân nhà", "đang làm việc ngoài sân"],
	"inside": ["đang về nhà", "đang ở trong nhà"],
	"shelter": ["đang chạy về nhà trú mưa", "đang trú mưa trong nhà"],
	"lantern": ["đang cầm đèn đi chơi tối", "đang ngồi chơi tối với hàng xóm"],
	"river": ["đang ra bến sông", "đang giặt giũ ở bến sông"],
	"school": ["đang đi học", "đang ra chơi ở sân trường"],
	"swim": ["đang ra sông tắm", "đang tắm sông"],
	"fishing": ["đang vác cần ra sông", "đang ngồi câu cá ở bến sông"],
	"football": ["đang ra sân bóng", "đang xem đá bóng"],
	"worship": ["đang ra đình lễ", "đang thắp hương ở đình"],
	"hideseek": ["đang chạy đi trốn", "đang chơi trốn tìm"],
	"jumprope": ["đang ra chỗ chơi nhảy dây", "đang chơi nhảy dây"],
	"khang": ["đang ra bãi đánh khăng", "đang chơi đánh khăng"],
	"oaq": ["đang ra chỗ chơi ô ăn quan", "đang ngồi chơi ô ăn quan"],
	"hs_play": ["đang ra chỗ chơi trốn tìm", "đang chơi trốn tìm"],
	"kite": ["đang mang diều ra đồng", "đang thả diều"],
}


func build() -> void:
	if village == null:
		push_warning("Villagers: chưa gán village")
		return
	_rng.seed = random_seed
	_build_graph()
	_collect_homes()
	_collect_field_spots()
	_spawn_people()
	_spawn_animals()
	print("Villagers: %d hộ, %d người, %d con vật, %d điểm đường" % [households, people.size(), animals.size(), _astar.get_point_count()])


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


# --- Đồ thị đường đi -----------------------------------------------------------------

func _add_line(points: PackedVector2Array, step: float, y: float = 0.05) -> Array[int]:
	var ids: Array[int] = []
	for p in Terrain._densify(points, step):
		var id := _next_id
		_next_id += 1
		_astar.add_point(id, Vector3(p.x, y, p.y))
		if not ids.is_empty():
			_astar.connect_points(ids[ids.size() - 1], id)
		ids.append(id)
	return ids


func _join_to_graph(points: PackedVector2Array, step: float) -> void:
	var first := Vector3(points[0].x, 0.05, points[0].y)
	var near := _astar.get_closest_point(first) if _astar.get_point_count() > 0 else -1
	var ids := _add_line(points, step)
	if near >= 0:
		_astar.connect_points(ids[0], near)


func _build_graph() -> void:
	_add_line(village.lane_points(), 5.0)
	for a in village.alley_lines():
		_join_to_graph(a, 5.0)
	if terrain != null:
		for r in terrain.roads:
			_join_to_graph(r, 6.0)
		_join_to_graph(terrain.path_points, 2.0)
	# Đường vào trường
	if school != null and not school.entry_path.is_empty():
		_join_to_graph(school.entry_path, 3.0)
	# Lối ra sông: đoạn gạch trong làng + đường đất qua đê + cầu ván (có độ cao)
	if river != null:
		for i in mini(village.access_paths.size(), river.landings.size()):
			var line := PackedVector3Array()
			for p in Terrain._densify(village.access_paths[i].points, 4.0):
				line.append(Vector3(p.x, 0.05, p.y))
			line.append_array(river.landings[i].path)
			var near := _astar.get_closest_point(line[0])
			var prev := -1
			for p3 in line:
				var id := _next_id
				_next_id += 1
				_astar.add_point(id, p3)
				if prev >= 0:
					_astar.connect_points(prev, id)
				prev = id
			_astar.connect_points(_next_id - line.size(), near)


func _nearest(p: Vector3) -> int:
	return _astar.get_closest_point(Vector3(p.x, 0.05, p.z))


## Đường đi từ `from` tới `to` theo đồ thị (gồm cả hai đầu).
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := _nearest(from)
	var b := _nearest(to)
	var out := PackedVector3Array()
	if a != b:
		out = _astar.get_point_path(a, b)
	else:
		out.append(_astar.get_point_position(a))
	# Bỏ điểm đầu nếu nó nằm "sau lưng" (đỡ đi lùi một đoạn)
	if out.size() >= 2 and from.distance_to(out[1]) < out[0].distance_to(out[1]):
		out.remove_at(0)
	out.append(to)
	return out


# --- Nhà, ruộng ------------------------------------------------------------------------

func _collect_homes() -> void:
	for h in village.homes:
		var d: Dictionary = h.duplicate()
		d["front"] = (d.door as Vector3) + (d.forward as Vector3) * 1.8
		_homes.append(d)
	# Nhà mình (cạnh ruộng)
	if house != null and terrain != null:
		var fwd := Basis(Vector3.UP, deg_to_rad(house.house_yaw_deg)) * Vector3.BACK
		var door := house.house_position + fwd * (house.depth * 0.5 - house.veranda_depth + 0.2) + Vector3(0, house.plinth_height, 0)
		var gate := Vector3(terrain.path_points[0].x, 0.05, terrain.path_points[0].y)
		_homes.append({"door": door, "forward": fwd, "gate": gate, "front": door + fwd * 2.4,
				"name": "Nhà mình (cạnh ruộng)", "key": "main"})


func _collect_field_spots() -> void:
	if terrain == null:
		return
	for fr in terrain.outer_fields:
		var n := 0
		for attempt in 40:
			var p := Vector3(_rng.randf_range(fr.position.x + 2.0, fr.end.x - 2.0), 0.05,
					_rng.randf_range(fr.position.y + 2.0, fr.end.y - 2.0))
			if p.distance_to(_astar.get_point_position(_nearest(p))) < 16.0:
				_field_spots.append(p)
				n += 1
				if n >= 8:
					break


# --- Sinh người ------------------------------------------------------------------------

func _unique_name(prefixes: Array, names: Array) -> String:
	for i in 60:
		var n := "%s %s" % [prefixes[_rng.randi_range(0, prefixes.size() - 1)], names[_rng.randi_range(0, names.size() - 1)]]
		if not _used_names.has(n):
			_used_names[n] = true
			return n
	# Hết chỗ ngẫu nhiên: duyệt lần lượt mọi tổ hợp
	for pre in prefixes:
		for nm in names:
			var n := "%s %s" % [pre, nm]
			if not _used_names.has(n):
				_used_names[n] = true
				return n
	return "%s %s" % [prefixes[0], names[_rng.randi_range(0, names.size() - 1)]]


## Thành phần một hộ `size` người: [[vai, nữ?, quan hệ], ...]. Bố mẹ trước, ông / bà, rồi các con.
func _household(size: int) -> Array:
	var out: Array = []
	var grand := _rng.randf() < elder_chance
	var kids_n := size - 2 - (1 if grand else 0)
	if kids_n < 1 and grand:
		# Ba người mà có ông / bà: một bố hoặc mẹ + ông / bà + một con
		kids_n = 1
		var mum_only := _rng.randf() < 0.4
		if mum_only:
			out.append(["carrier" if _rng.randf() < carrier_chance else "farmer", true, "mẹ"])
		else:
			out.append(["farmer", false, "bố"])
	else:
		out.append(["farmer", false, "bố"])
		out.append(["carrier" if _rng.randf() < carrier_chance else "farmer", true, "mẹ"])
	if grand:
		var gf := _rng.randf() < 0.55
		out.append(["elder", gf, "bà" if gf else "ông"])
	for k in kids_n:
		var role := "herder" if _rng.randf() < herder_chance else "kid"
		var f := _rng.randf() < (0.15 if role == "herder" else 0.5)
		out.append([role, f, "con"])
	return out


func _spawn_people() -> void:
	var lanterns := 0
	var n_homes := 0
	for hi in _homes.size():
		var home: Dictionary = _homes[hi]
		if str(home.key) == "main":
			continue          # nhà mình không có người máy ở
		if max_households > 0 and n_homes >= max_households:
			break
		n_homes += 1
		var size := _rng.randi_range(household_size.x, maxi(household_size.x, household_size.y))
		var family: Array[Villager] = []
		for m in _household(size):
			var role: String = m[0]
			var female: bool = m[1]
			var v := Villager.new()
			v.name = "Villager%d" % people.size()
			v.role = role
			v.role_name = ROLE_NAMES[role]
			v.terrain = terrain
			v.home = home
			v.side_offset = _rng.randf_range(-0.7, 0.7)
			v.set_meta("female", female)
			v.set_meta("household", hi)
			v.set_meta("relation", m[2])
			var look := _look(role, female)
			match role:
				"elder":
					v.display_name = _unique_name(["Bà", "Cụ bà"] if female else ["Ông", "Cụ ông"], FEMALE if female else MALE)
					v.speed = _rng.randf_range(0.6, 0.85)
				"kid", "herder":
					v.display_name = _unique_name(["Cái", "Bé"] if female else ["Cu", "Thằng"], KID)
					v.speed = _rng.randf_range(1.6, 2.2) if role == "kid" else 1.1
				_:
					v.display_name = _unique_name(["Chị", "Cô", "Thím"] if female else ["Anh", "Chú", "Bác"], FEMALE if female else MALE)
					v.speed = _rng.randf_range(1.2, 1.5) if role != "carrier" else 1.15
			add_child(v)
			v.build_person(look)
			if role == "kid" and school != null:
				v.add_uniform(look)
			if role in ["farmer", "carrier", "elder"] and lanterns < lantern_walkers and _rng.randf() < 0.12:
				v.add_lantern(true)
				v.set_meta("lantern", true)
				lanterns += 1
			people.append(v)
			family.append(v)
		home["family"] = family
		for v in family:
			_start(v)
	households = n_homes


## Người cùng hộ với `v` (kể cả `v`).
func family_of(v: Villager) -> Array:
	return v.home.get("family", [v])


func _look(role: String, female: bool) -> Dictionary:
	var male_shirts: Array[Color] = [Palette.FARMER_SHIRT, Palette.PILLOW, Palette.BLANKET.darkened(0.2), Palette.WOOD_LIGHT, Palette.MUD]
	var female_shirts: Array[Color] = [Palette.WINDOW_DARK, Palette.BANYAN_TRUNK, Palette.FLOWER_WHITE, Palette.ALTAR_RED.darkened(0.25), Palette.LILY.darkened(0.3)]
	var kid_shirts: Array[Color] = [Palette.BLANKET, Palette.HIBISCUS, Palette.LILY, Palette.FLOWER_YELLOW.darkened(0.2)]
	var shirts := female_shirts if female else male_shirts
	var look := {
		"shirt": shirts[_rng.randi_range(0, shirts.size() - 1)],
		"pants": Palette.WINDOW_DARK if female or _rng.randf() < 0.4 else Palette.FARMER_PANTS,
		"skin": Palette.FARMER_SKIN.darkened(_rng.randf_range(0.0, 0.15)),
		"scale": _rng.randf_range(0.95, 1.05),
		"hat": "khan" if female else "non",
		"prop": "none",
	}
	match role:
		"farmer":
			look.prop = "hoe"
			look.hat = "non"
		"carrier":
			look.prop = "pole"
			look.hat = "non" if _rng.randf() < 0.6 else "khan"
		"elder":
			look.prop = "stick"
			look.shirt = Palette.PILLOW if not female else Palette.WINDOW_DARK
			look.scale = _rng.randf_range(0.88, 0.95)
			look.hat = "khan" if female else "none"
		"kid", "herder":
			look.shirt = kid_shirts[_rng.randi_range(0, kid_shirts.size() - 1)]
			look.pants = Palette.WINDOW_DARK
			look.scale = _rng.randf_range(0.6, 0.72)
			look.hat = "non" if role == "herder" else ("tuft" if not female else "none")
	return look


# --- Sinh con vật ----------------------------------------------------------------------

func _spawn_animals() -> void:
	# Trâu theo trẻ chăn trâu
	for v in people:
		if v.role == "herder":
			var b := _animal("buffalo", "Con trâu của " + v.display_name)
			b.follow_target = v
			b.follow_distance = 3.0
			b.home = v.home
			b.global_position = v.global_position - v.global_transform.basis.z * 3.0
			b.visible = v.visible
	# Chó theo chủ (người lớn)
	var adults := people.filter(func(p: Villager) -> bool: return p.role in ["farmer", "carrier"])
	for i in mini(dogs, adults.size()):
		var owner: Villager = adults[_rng.randi_range(0, adults.size() - 1)]
		var d := _animal("dog", "Con chó nhà " + owner.display_name)
		d.follow_target = owner
		d.follow_distance = 1.6
		d.home = owner.home
		d.global_position = owner.global_position + Vector3(1, 0, 1)
		d.visible = owner.visible
	# Gà trong sân vài nhà
	for i in chicken_yards:
		var h: Dictionary = _homes[_rng.randi_range(0, _homes.size() - 1)]
		var center: Vector3 = (h.front as Vector3) + (h.forward as Vector3) * 1.6
		center.y = 0.05
		for k in chickens_per_yard:
			var c := _animal("chicken", "Đàn gà nhà " + str(h.name))
			c.home = h
			c.speed = 0.7
			c.global_position = center + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
			_chickens.append({"node": c, "center": center})
	# Vịt bơi nối đuôi ở ao làng
	var prev: Villager = null
	for i in ducks:
		var dk := _animal("duck", "Đàn vịt ở ao làng")
		dk.speed = 0.45
		var pc := village.pond_center
		dk.global_position = Vector3(pc.x + i * 0.5, 0.06, pc.y)
		dk.activity_text = "đang bơi trên ao làng"
		if prev == null:
			_duck_leader = dk
		else:
			dk.follow_target = prev
			dk.follow_distance = 0.6
		prev = dk


func _animal(kind: String, title: String) -> Villager:
	var a := Villager.new()
	a.role = kind
	a.role_name = ROLE_NAMES[kind]
	a.display_name = title
	a.terrain = terrain
	a.name = "%s%d" % [kind.capitalize(), animals.size()]
	add_child(a)
	a.build_animal(kind)
	animals.append(a)
	return a


# --- Lịch sinh hoạt ------------------------------------------------------------------

func _hour() -> float:
	return day_night.time_of_day if day_night != null else 15.0


func _is_night(h: float) -> bool:
	return h >= NIGHT_START or h < NIGHT_END


func _storm() -> bool:
	return weather != null and weather.kind == "storm" and weather.rain > 0.5


## Trọng số các việc có thể làm theo vai trò và giờ.
func _choices(v: Villager, h: float) -> Dictionary:
	var drizzle := weather != null and weather.kind == "drizzle"
	if _is_night(h):
		if v.has_meta("lantern") and h >= 18.5 and h < 22.0:
			return {"lantern": 3.0, "inside": 1.0}
		return {"inside": 1.0}
	if h >= 19.0:
		return {"inside": 5.0, "visit": 1.0} if not v.has_meta("lantern") else {"lantern": 3.0, "inside": 1.0}
	var c := {}
	var noon := h >= 11.0 and h < 13.0
	match v.role:
		"farmer":
			c = {"inside": 3.0, "banyan": 2.0, "yard": 1.0} if noon else {"field": 6.0, "well": 1.0, "visit": 1.0, "yard": 1.0}
		"herder":
			c = {"inside": 2.0, "banyan": 1.0} if noon else {"graze": 6.0, "pond": 1.0}
		"carrier":
			c = {"inside": 2.0, "yard": 1.0} if noon else {"well": 3.0, "field": 2.0, "visit": 2.0, "yard": 1.0}
		"elder":
			c = {"banyan": 3.0, "pagoda": 2.0, "visit": 2.0, "dinh": 1.0, "yard": 2.0, "inside": 1.0}
		"kid":
			c = {"inside": 2.0, "yard": 1.0} if noon else {"dinh": 4.0, "pond": 2.0, "banyan": 1.0, "visit": 1.0, "yard": 1.0}
	# Mùa vụ (mục 33): mùa cấy, mùa gặt ra đồng đông hơn
	if farming != null and c.has("field"):
		c["field"] = float(c["field"]) * farming.busy()
	# Nhảy dây (mục 31): trẻ con rủ nhau ra sân đình / gốc đa đầu làng
	if jump_rope != null and v.role == "kid" and jump_rope.ambient_ok(h):
		c["jumprope"] = 3.0 if v.get_meta("female", false) else 1.5
	# Đánh khăng (mục 32): con trai chơi nhiều hơn
	if tip_cat != null and v.role in ["kid", "herder"] and tip_cat.ambient_ok(h):
		c["khang"] = 1.0 if v.get_meta("female", false) else (3.0 if v.role == "kid" else 1.0)
	# Ô ăn quan (mục 27, 36): cụ già, trẻ con ngồi chơi dưới gốc đa / sân chùa
	if o_an_quan != null and o_an_quan.ambient_ok(h) and v.role in ["elder", "kid", "herder"]:
		c["oaq"] = 1.6 if v.role == "elder" else (0.0 if noon and v.role != "elder" else 1.0)
	# Trốn tìm (mục 28, 36): trẻ con rủ nhau chơi trong ngõ
	if hide_seek != null and v.role == "kid" and hide_seek.ambient_ok(h):
		c["hs_play"] = 1.8
	# Thả diều (mục 30, 36): trẻ con mang diều ra bờ ruộng khi trời có gió
	if kite != null and v.role in ["kid", "herder"] and kite.ambient_ok(h):
		c["kite"] = 1.5
	# Trẻ con đi học theo thời khoá biểu (nghỉ Chủ nhật, nghỉ Tết — mục 25)
	if school_day != null and v.role == "kid" and school_day.wants_pupils(h):
		c = {"school": 8.0, "inside": 0.5}
		return c
	# Mùng 1, rằm: người lớn ra đình thắp hương, sáng sớm và chiều tối (mỗi buổi một lần)
	var worship := worship_weight(v, h)
	if worship > 0.0:
		c["worship"] = worship
	# Ra sông (ban ngày, trời không mưa)
	if river != null and not river.landings.is_empty() and h >= 7.0 and h < 18.0 and not noon:
		match v.role:
			"carrier": c["river"] = 2.5
			"farmer": c["river"] = 0.8
			"kid": c["swim"] = 2.0
			"elder": c["fishing"] = 2.0
	# Chiều tan học, tan đồng: trẻ con và thanh niên ra sân bóng, người già ra xem
	if football != null and h >= 16.3 and h < 18.6:
		match v.role:
			"kid": c["football"] = 7.0
			"farmer": c["football"] = 0.8 if v.get_meta("female", false) else 3.5
			"elder": c["football"] = 1.5
	if h < 7.0:
		c.erase("dinh")
		c.erase("pond")
		c.erase("pagoda")
	if drizzle:
		c.erase("swim")
		c.erase("fishing")
		c.erase("pond")
		c.erase("dinh")
		c["inside"] = float(c.get("inside", 0.0)) + 2.0
	if h >= 17.0:
		c["inside"] = float(c.get("inside", 0.0)) + 3.0
	return c


## Trọng số đi lễ đình hôm nay (0 nếu không phải ngày lễ / ngoài giờ / buổi này đã lễ rồi).
func worship_weight(v: Villager, h: float) -> float:
	if calendar == null or not calendar.is_worship_day():
		return 0.0
	var morning := h >= worship_morning.x and h < worship_morning.y
	var evening := h >= worship_evening.x and h < worship_evening.y
	if not (morning or evening):
		return 0.0
	if str(v.get_meta("worship_done", "")) == _worship_session(h):
		return 0.0
	match v.role:
		"elder": return 14.0
		"carrier": return 9.0
		"farmer": return 7.0
		"kid", "herder": return 1.5
	return 0.0


func _worship_session(h: float) -> String:
	return "%d_%s" % [calendar.jd if calendar != null else 0, "am" if h < 12.0 else "pm"]


func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := _rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return str(k)
	return str(weights.keys()[0])


## Toạ độ đích của một việc.
func _target(v: Villager, act: String) -> Vector3:
	var h: Dictionary = v.home
	match act:
		"field", "graze":
			if not _field_spots.is_empty():
				return _field_spots[_rng.randi_range(0, _field_spots.size() - 1)]
		"well":
			if str(h.key) == "main":
				return Vector3(-16.4, 0.05, -4.8)
			var a := _rng.randf() * TAU
			return village.well_position + Vector3(cos(a) * 2.6, 0.05, sin(a) * 2.6)
		"banyan":
			var a2 := _rng.randf_range(0.2, PI - 0.2)
			return village.banyan_position + Vector3(cos(a2) * 3.5, 0.05, sin(a2) * 3.5)
		"pagoda":
			return village.pagoda_spot + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-1.5, 1.5))
		"dinh":
			return village.dinh_spot + Vector3(_rng.randf_range(-7, 7), 0, _rng.randf_range(-2, 2))
		"worship":
			return village.dinh_door + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-0.3, 0.3))
		"pond":
			var a3 := _rng.randf_range(0.3, PI - 0.3)
			return Vector3(village.pond_center.x + cos(a3) * village.pond_radii.x * 1.35, 0.05,
					village.pond_center.y + sin(a3) * village.pond_radii.y * 1.35)
		"visit", "lantern":
			var other: Dictionary = _homes[_rng.randi_range(0, _homes.size() - 1)]
			return (other.gate as Vector3) + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(0.2, 1.0))
		"football":
			return football.gather_spot(_rng)
		"jumprope":
			return jump_rope.site_target(v)
		"khang":
			return tip_cat.site_target(v)
		"oaq":
			return o_an_quan.site_target(v)
		"hs_play":
			return hide_seek.site_target(v)
		"kite":
			return kite.site_target(v)
		"school":
			return school.yard_spots[_rng.randi_range(0, school.yard_spots.size() - 1)] + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		"river", "swim", "fishing":
			var l: Dictionary = river.landings[_rng.randi_range(0, river.landings.size() - 1)]
			v.set_meta("landing", l)
			match act:
				"fishing": return l.spot
				"swim": return (l.edge as Vector3) + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-1.0, 1.0))
				_: return (l.wash as Vector3) + Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4))
		"yard":
			var side := (h.forward as Vector3).cross(Vector3.UP)
			return (h.front as Vector3) + (h.forward as Vector3) * _rng.randf_range(0.8, 2.2) + side * _rng.randf_range(-2.0, 2.0)
	return h.front


## Lên lại lịch cho mọi người theo giờ hiện tại (khi giờ bị đổi đột ngột, vd. công cụ chụp ảnh).
func replan() -> void:
	for v in people:
		v.state = Villager.State.IDLE
		v.visible = true
		_start(v)


## Bắt đầu: chọn việc theo giờ, đặt NPC ở giữa đường đi tới đó cho làng không "đổ ra cùng lúc".
func _start(v: Villager) -> void:
	v.global_position = v.home.front
	v.set_meta("at_home", true)
	_next_activity(v)
	if v.activity in ["inside", "shelter"]:
		# Đang ở trong nhà ngay từ đầu
		v.global_position = v.home.door
		v.state = Villager.State.INSIDE
		v.visible = false
		v.activity_text = ACTIVITY_TEXT[v.activity][1]
		v.dwell = _rng.randf_range(2.0, 30.0)
	elif v.state == Villager.State.WALK and v.path.size() > 2:
		var i := _rng.randi_range(0, v.path.size() - 2)
		v.global_position = v.path[i]
		v.path_index = i + 1
		v.set_meta("at_home", false)


func _next_activity(v: Villager, forced: String = "") -> void:
	# Lễ xong trong đình: bước ra ở chân thềm
	if v.has_meta("at_dinh"):
		v.remove_meta("at_dinh")
		v.global_position = village.dinh_door
		v.visible = true
	var act := forced if forced != "" else _pick(_choices(v, _hour()))
	v.activity = act
	var h: Dictionary = v.home
	var at_home: bool = v.get_meta("at_home", false)
	var from := v.global_position
	var p := PackedVector3Array()
	if act in ["inside", "shelter"]:
		if at_home and v.state == Villager.State.INSIDE:
			v.dwell = _rng.randf_range(15.0, 45.0)
			v.activity_text = ACTIVITY_TEXT[act][1]
			return
		if not at_home:
			p = find_path(from, h.gate as Vector3)
		p.append(h.front)
		p.append(h.door)
	elif act == "yard":
		if not at_home:
			p = find_path(from, h.gate as Vector3)
		p.append(_target(v, act))
	else:
		p = _route(v, from, _target(v, act), at_home)
	if act in ["dinh", "worship"]:
		p = _around_dinh_pond(p)
	v.set_meta("at_home", act in ["inside", "shelter", "yard"])
	# Học sinh: mặc đồng phục khi đi học (thay ở nhà — lúc ra khỏi cửa), về nhà thì thay ra
	if v.has_outfit("uniform"):
		# Mặc vào khi bắt đầu đi học; cởi ra khi đã về trong nhà (không thay giữa đường)
		if act == "school":
			v.set_outfit(true)
		elif v.state == Villager.State.INSIDE or at_home:
			v.set_outfit(false)
	v.walk_path(p)
	v.speed_mul = 1.7 if act == "shelter" else (1.3 if weather != null and weather.kind == "drizzle" else 1.0)
	v.work_anim = "idle"
	v.activity_text = ACTIVITY_TEXT[act][0]
	if v.lantern != null:
		v.lantern.visible = act == "lantern"


## Đoạn đường nào cắt ngang hồ bán nguyệt ở sân đình thì đi vòng qua mép hồ (bên gần hơn).
func _around_dinh_pond(p: PackedVector3Array) -> PackedVector3Array:
	var c := village.dinh_pond_center
	var r := village.dinh_pond_radii + Vector2(1.2, 1.2)
	if r.x <= 1.3:
		return p
	var out := PackedVector3Array()
	for i in p.size():
		if i > 0:
			var a := p[i - 1]
			var b := p[i]
			var hits := false
			for k in range(1, 12):
				var q := a.lerp(b, k / 12.0)
				if Vector2((q.x - c.x) / r.x, (q.z - c.z) / r.y).length() < 1.0:
					hits = true
					break
			if hits:
				var side := signf((a.x + b.x) * 0.5 - c.x)
				if side == 0.0:
					side = 1.0
				var first := c.z + r.y if a.z > b.z else c.z - r.y
				var second := c.z - r.y if a.z > b.z else c.z + r.y
				out.append(Vector3(c.x + side * r.x * 0.75, a.y, first))
				out.append(Vector3(c.x + side * r.x, a.y, c.z))
				out.append(Vector3(c.x + side * r.x * 0.75, a.y, second))
		out.append(p[i])
	return out


## Nếu đang ở trong nhà/sân thì đi ra qua trước hiên và cổng trước rồi mới vào đồ thị.
func _route(v: Villager, from: Vector3, to: Vector3, at_home: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var start := from
	if at_home:
		var h: Dictionary = v.home
		if v.state == Villager.State.INSIDE:
			out.append(h.front)
		out.append(h.gate)
		start = h.gate
	out.append_array(find_path(start, to))
	return out


func _arrive(v: Villager) -> void:
	var act := v.activity
	v.activity_text = ACTIVITY_TEXT[act][1]
	if act in ["inside", "shelter"]:
		v.state = Villager.State.INSIDE
		v.visible = false
		v.dwell = _rng.randf_range(20.0, 50.0)
		return
	if act == "worship":
		# Vào trong đình thắp hương, khấn vái (IndoorFolk cho hiện ở hương án nếu đang xem đình)
		v.set_meta("at_dinh", true)
		v.set_meta("worship_done", _worship_session(_hour()))
		v.visible = false
		v.dwell = _rng.randf_range(worship_minutes.x, worship_minutes.y)
		return
	v.dwell = _rng.randf_range(45.0, 100.0) if act in ["field", "graze", "fishing", "river"] else _rng.randf_range(20.0, 50.0)
	if act == "khang" and tip_cat != null:
		tip_cat.on_arrive(v)          # đánh khăng (mục 32): TipCat giữ tới khi tan cuộc
		return
	if act == "oaq" and o_an_quan != null:
		o_an_quan.on_arrive(v)        # ô ăn quan (mục 36): ngồi xổm chơi tới khi tan ván
		return
	if act == "hs_play" and hide_seek != null:
		hide_seek.ambient_arrive(v)   # trốn tìm của bọn trẻ (mục 36)
		return
	if act == "kite" and kite != null:
		kite.ambient_arrive(v)        # thả diều (mục 36)
		return
	if act == "jumprope" and jump_rope != null:
		jump_rope.on_arrive(v)        # nhảy dây (mục 31): JumpRope giữ tới khi tan cuộc
		return
	if act == "hideseek":
		if hide_seek != null:
			hide_seek.on_arrive(v)    # trốn tìm (mục 28): tới chỗ trốn / về cột
		return
	if act == "school" and school_day != null:
		school_day.on_arrive(v)       # tới trường: SchoolDay cho vào lớp / ra chơi theo thời khoá biểu
		return
	match act:
		"field":
			v.work_anim = "hoe" if v.role == "farmer" else "idle"
			if farming != null and v.role in ["farmer", "carrier"]:
				var fw := farming.field_work(v.global_position)
				v.work_anim = String(fw.anim)
				v.activity_text = String(fw.text)
				if v.prop_node != null:
					v.prop_node.visible = bool(fw.prop)
		"graze": v.work_anim = "idle"
		"dinh", "pond": v.work_anim = "play" if v.role in ["kid", "herder"] else "chat"
		"banyan": v.work_anim = "sit" if v.role == "elder" else "chat"
		"visit", "pagoda", "lantern": v.work_anim = "chat"
		"swim", "school": v.work_anim = "play"
		"fishing": v.work_anim = "sit"
		"river": v.work_anim = "hoe"   # cúi lên cúi xuống giặt giũ
		_: v.work_anim = "idle"
	# Quay mặt về phía giếng / gốc đa / bạn chơi cho tự nhiên
	var look_at_pt := Vector3.ZERO
	if act in ["river", "swim", "fishing"] and v.has_meta("landing"):
		v.rotation.y = float(v.get_meta("landing").face)
	match act:
		"well": look_at_pt = village.well_position
		"banyan": look_at_pt = village.banyan_position
		"pagoda": look_at_pt = village.pagoda_spot + Vector3(0, 0, -6)
	if look_at_pt != Vector3.ZERO:
		var d := look_at_pt - v.global_position
		v.rotation.y = atan2(d.x, d.z)
	# Ra tới sân bóng: vào đá nếu còn chỗ, không thì đứng xem
	if act == "football" and football != null:
		football.arrive(v)


# --- Mỗi khung hình --------------------------------------------------------------------

func _process(delta: float) -> void:
	if people.is_empty() and animals.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	var storm := _storm()
	var night := _is_night(_hour())
	_weather_check -= delta
	var check_weather := _weather_check <= 0.0
	if check_weather:
		_weather_check = 1.0

	for v in people:
		if v.has_meta("talking"):
			# Đang nói chuyện với người chơi: đứng lại, giữ nguyên việc đang làm
			var st := v.state
			var dw := v.dwell
			v.state = Villager.State.IDLE
			v.tick(delta, true)
			v.state = st
			v.dwell = dw
			continue
		var was_walking := v.state == Villager.State.WALK
		v.tick(delta, v.global_position.distance_to(cam_pos) < animate_distance)
		if was_walking and v.state == Villager.State.IDLE:
			_arrive(v)
		elif v.state != Villager.State.WALK and v.dwell <= 0.0:
			if not (storm and v.state == Villager.State.INSIDE):
				_next_activity(v)
		if check_weather and storm and v.state != Villager.State.INSIDE and v.activity != "shelter":
			_next_activity(v, "shelter")
		elif check_weather and night and v.state != Villager.State.INSIDE \
				and not v.activity in ["inside", "shelter", "lantern"]:
			_next_activity(v)   # trời tối: bỏ dở việc, về nhà (hoặc cầm đèn đi chơi)

	_tick_animals(delta, cam_pos)

	if selected != null:
		if _following and outdoor_rig != null:
			outdoor_rig.set_focus(selected.global_position)
		_info_timer -= delta
		if _info_timer <= 0.0:
			_info_timer = 0.25
			_show_info()


func _tick_animals(delta: float, cam_pos: Vector3) -> void:
	var h := _hour()
	var night := _is_night(h) or h >= 19.5 or h < 5.5
	for a in animals:
		var near := a.global_position.distance_to(cam_pos) < animate_distance * 0.7
		match a.role:
			"buffalo", "dog":
				var owner := a.follow_target
				a.work_anim = "graze" if a.role == "buffalo" and owner.state == Villager.State.IDLE else "idle"
				a.activity_text = ("đang gặm cỏ" if a.work_anim == "graze" else "đang đi theo " + owner.display_name) if owner.visible else "đang nằm trong chuồng"
				a.tick(delta, near)
			"duck":
				if a == _duck_leader and a.state != Villager.State.WALK:
					_duck_loop(a)
				a.tick(delta, near)
				a.visible = not night
			"chicken":
				_tick_chicken(a, delta, night, near)


func _duck_loop(d: Villager) -> void:
	var p := PackedVector3Array()
	var pc := village.pond_center
	var r := village.pond_radii * 0.62
	var start := _rng.randf() * TAU
	for i in 12:
		var a := start + TAU * i / 12.0
		p.append(Vector3(pc.x + cos(a) * r.x, 0.06, pc.y + sin(a) * r.y))
	d.walk_path(p)


func _tick_chicken(c: Villager, delta: float, night: bool, near: bool) -> void:
	if night or _storm():
		c.visible = false
		c.activity_text = "đang ngủ trong chuồng"
		return
	c.visible = true
	var center: Vector3 = Vector3.ZERO
	for item in _chickens:
		if item.node == c:
			center = item.center
			break
	var was_walking := c.state == Villager.State.WALK
	c.tick(delta, near)
	if was_walking and c.state == Villager.State.IDLE:
		c.work_anim = "peck"
		c.dwell = _rng.randf_range(2.0, 6.0)
		c.activity_text = "đang mổ thóc ngoài sân"
	elif c.state == Villager.State.IDLE and c.dwell <= 0.0:
		var p := PackedVector3Array()
		p.append(center + Vector3(_rng.randf_range(-2.0, 2.0), 0, _rng.randf_range(-1.6, 1.6)))
		c.walk_path(p)
		c.work_anim = "idle"
		c.activity_text = "đang lon ton trong sân"


# --- Bấm chọn, thông tin ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_select(_pick_at(mb.position))
	elif event.is_action_pressed("follow_npc") and selected != null:
		_following = not _following
		_info_timer = 0.0


func _pick_at(screen: Vector2) -> Villager:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 300.0,
			1 << (Villager.CLICK_LAYER - 1))
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var col := hit.get("collider") as Node
	return col.get_meta("villager") as Villager if col != null and col.has_meta("villager") else null


## Chọn một NPC (null = bỏ chọn).
func _select(v: Villager) -> void:
	if selected != null and is_instance_valid(selected):
		selected.set_selected(false)
	selected = v
	_following = false
	if v == null:
		if hud != null:
			hud.hide_info()
		return
	v.set_selected(true)
	_info_timer = 0.0


## Gọi một người đang ở trong nhà ra cổng (người chơi tới gõ cửa vì có việc).
func call_out(v: Villager) -> void:
	var h: Dictionary = v.home
	v.global_position = h.front
	v.visible = true
	v.state = Villager.State.IDLE
	v.path = PackedVector3Array()
	v.activity = "yard"
	v.activity_text = "ra cổng tiếp khách"
	v.work_anim = "chat"
	v.dwell = 45.0
	v.set_meta("at_home", true)
	if v.lantern != null:
		v.lantern.visible = false


func select_villager(v: Villager) -> void:
	_select(v)
	_show_info()


func _show_info() -> void:
	if hud == null or selected == null:
		return
	var v := selected
	var lines: Array[String] = []
	if v.role in ["buffalo", "dog", "chicken", "duck"]:
		lines.append(v.role_name)
	else:
		lines.append(v.role_name)
		lines.append("Nhà: " + str(v.home.get("name", "")))
	var txt := v.activity_text if v.visible or v.state == Villager.State.INSIDE else "đang ở trong nhà"
	lines.append(txt.substr(0, 1).to_upper() + txt.substr(1))
	lines.append("F: thôi đi theo" if _following else "F: camera đi theo  ·  bấm chỗ khác để bỏ chọn")
	hud.show_info(v.display_name, lines)
