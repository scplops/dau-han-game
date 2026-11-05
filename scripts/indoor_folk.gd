class_name IndoorFolk
extends Node3D
## Dân làng ở trong nhà (mục 22). Khi đang xem / đi bộ trong một toà nhà, những người mà theo
## lịch đang ở đó sẽ hiện ra bên trong và làm việc của họ ở các chỗ `Interior.seats`:
## - Nhà ở: người nhà đang "ở trong nhà" (Villager.State.INSIDE) — uống nước chè, ngồi nghỉ,
##   dệt vải, xay thóc, học bài, thắp hương; tối thì nằm ngủ trên giường / phản.
## - Chùa: người đang lễ chùa quỳ trên bồ đoàn. Đình: người lớn ra đình ngồi chiếu hội, vái hương án.
## - Lớp học: trẻ con đang ở trường ngồi bàn học.
## Mỗi người trong nhà là một "bản sao" (Villager mới, cùng hình dáng, meta `proxy_of` = người thật)
## — người thật vẫn ở ngoài làng theo lịch; bản sao đi ra cửa khi người thật ra khỏi nhà, và bước
## vào cửa khi người thật về tới nhà. Nói chuyện được với bản sao (Dialogue dùng người thật để nhớ).

@export var house_entry: HouseEntry
@export var interior: Interior
@export var villagers: Villagers
@export var day_night: DayNight
@export var school_day: SchoolDay
@export var random_seed: int = 909
## Bao lâu (giây) xem lại ai ra ai vào.
@export var sync_interval: float = 1.0
@export var walk_speed: float = 1.1

var _key: String = ""
var _folk: Array[Dictionary] = []     # {real, proxy, seat (chỉ số), leaving}
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _keeper: Villager                  # sư cụ ở chùa / ông thủ từ ở đình (có mặt 5h–21h)


func _ready() -> void:
	_rng.seed = random_seed
	if house_entry != null:
		house_entry.inside_changed.connect(_on_inside_changed)


func _on_inside_changed(inside: bool) -> void:
	_clear()
	if inside and house_entry._target != null:
		_key = str(house_entry._target.get_meta("key", ""))
		_timer = 0.0
		_sync(true)


func _clear() -> void:
	for f in _folk:
		if is_instance_valid(f.proxy):
			(f.proxy as Node).queue_free()
	_folk.clear()
	if _keeper != null and is_instance_valid(_keeper):
		_keeper.queue_free()
	_keeper = null
	_key = ""


# --- Ai đang ở trong toà nhà này ------------------------------------------------------------

func _hour() -> float:
	return day_night.time_of_day if day_night != null else 17.0


func _night() -> bool:
	var h := _hour()
	return h >= 21.0 or h < 5.5


## Người thật này có đang ở trong toà nhà đang xem không.
func _belongs(v: Villager) -> bool:
	match _key:
		"pagoda":
			return v.activity == "pagoda" and v.state == Villager.State.IDLE
		"dinh":
			if v.has_meta("at_dinh"):
				return true                 # đi lễ mùng 1 / rằm (mục 25)
			return v.activity == "dinh" and v.state == Villager.State.IDLE and not v.role in ["kid", "herder"]
		"school":
			return v.has_meta("in_class")   # đang ngồi học (SchoolDay, mục 26)
	return str(v.home.get("key", "")) == _key and v.state == Villager.State.INSIDE


func _sync(first: bool) -> void:
	if _key == "" or villagers == null or interior == null:
		return
	if _keeper == null and _key in ["pagoda", "dinh"] and _hour() >= 5.0 and _hour() < 21.0:
		_add_keeper()
	if _keeper == null and _key == "school" and school_day != null and school_day.phase(_hour()) in ["class", "arrive", "recess"]:
		_add_keeper()
	# Ai đã ra khỏi nhà (theo lịch) thì đứng dậy đi ra cửa
	for f in _folk:
		if f.get("keeper", false):
			continue
		if not f.leaving and not _belongs(f.real) and not (f.proxy as Villager).has_meta("talking"):
			_leave(f)
	# Ai mới về / mới tới thì bước vào (lần đầu: đã ngồi sẵn ở chỗ)
	var everyone: Array[Villager] = villagers.people.duplicate()
	if school_day != null:
		everyone.append_array(school_day.pupils)
	for v in everyone:
		if not _belongs(v) or _has(v):
			continue
		var seat := _pick_seat(v)
		if seat < 0:
			continue
		var p := _make_proxy(v)
		var f := {"real": v, "proxy": p, "seat": seat, "leaving": false}
		_folk.append(f)
		if first:
			_sit(f)
		else:
			_walk_to_seat(f)


## Người trông giữ thường trực: sư cụ (áo nâu sồng, đầu cạo) tụng kinh trước Phật điện;
## ông thủ từ đứng vái trước hương án đình. Không có người thật tương ứng ngoài làng.
func _add_keeper() -> void:
	var pagoda := _key == "pagoda"
	var school := _key == "school"
	var want := "pagoda_pray" if pagoda else ("teach" if school else "dinh_pray")
	var seat := -1
	for i in interior.seats.size():
		if interior.seats[i].act == want and not _seat_taken(i):
			# Chỗ chính giữa, gần bàn thờ nhất
			if seat < 0 or absf((interior.seats[i].pos as Vector3).x) < absf((interior.seats[seat].pos as Vector3).x) - 0.01 \
					or (absf((interior.seats[i].pos as Vector3).x - (interior.seats[seat].pos as Vector3).x) < 0.01 and (interior.seats[i].pos as Vector3).z < (interior.seats[seat].pos as Vector3).z):
				seat = i
	if seat < 0:
		return
	var p := Villager.new()
	p.name = "Keeper"
	p.role = "elder"
	if school:
		# Cô giáo đứng giảng ở bục
		p.role = "carrier"
		p.display_name = "Cô giáo Hạnh"
		p.role_name = "Cô giáo chủ nhiệm"
		p.home = {"name": "Trường tiểu học", "key": "school"}
		p.set_meta("female", true)
		add_child(p)
		p.build_person({"shirt": Palette.FLOWER_WHITE, "pants": Palette.WINDOW_DARK, "skin": Palette.FARMER_SKIN,
				"hat": "none", "scale": 1.0, "female": true, "prop": "none"})
		_keeper = p
		var ft := {"real": p, "proxy": p, "seat": seat, "leaving": false, "keeper": true}
		_folk.append(ft)
		_sit(ft)
		p.activity = "teach"
		p.activity_text = "teach"
		return
	if pagoda:
		p.display_name = "Sư cụ"
		p.role_name = "Sư trụ trì chùa làng"
	else:
		p.display_name = "Ông thủ từ"
		p.role_name = "Người trông đình"
	p.home = {"name": "Chùa làng" if pagoda else "Đình làng", "key": _key}
	add_child(p)
	var robe := Palette.MUD.darkened(0.25)
	var look := {"shirt": robe if pagoda else Palette.WINDOW_DARK, "pants": robe if pagoda else Palette.WINDOW_DARK,
			"skin": Palette.FARMER_SKIN.darkened(0.04), "hat": "none" if pagoda else "khan", "scale": 0.95,
			"female": false, "prop": "none", "bald": pagoda}
	p.build_person(look)
	_keeper = p
	var f := {"real": p, "proxy": p, "seat": seat, "leaving": false, "keeper": true}
	_folk.append(f)
	_sit(f)
	p.activity = "monk_chant" if pagoda else "dinh_keep"
	p.activity_text = p.activity


func _has(v: Villager) -> bool:
	for f in _folk:
		if f.real == v:
			return true
	return false


func _seat_taken(i: int) -> bool:
	for f in _folk:
		if int(f.seat) == i and not f.leaving:
			return true
	return false


## Chọn chỗ hợp với người và giờ: tối ngủ; trẻ con học; phụ nữ dệt; cụ già thắp hương / uống trà.
func _pick_seat(v: Villager) -> int:
	var night := _night() and not _key in ["pagoda", "dinh", "school"]
	var best := -1
	var best_score := -INF
	for i in interior.seats.size():
		if _seat_taken(i):
			continue
		var st: Dictionary = interior.seats[i]
		var tags: Array = st.tags
		var score := _rng.randf()
		if night != tags.has("night"):
			score -= 10.0
		if tags.has("kid"):
			score += 3.0 if v.role in ["kid", "herder"] else -4.0
		if tags.has("female"):
			score += 2.0 if v.get_meta("female", false) else -1.5
		if tags.has("elder"):
			score += 2.0 if v.role == "elder" else -0.5
		if tags.has("teacher"):
			score -= 20.0                 # bục giảng để cô giáo đứng
		if tags.has("worship"):
			score += 4.0 if v.has_meta("at_dinh") else -3.0
		if score > best_score:
			best_score = score
			best = i
	return best if best_score > -5.0 else -1


# --- Bản sao trong nhà -----------------------------------------------------------------------

func _make_proxy(v: Villager) -> Villager:
	var p := Villager.new()
	p.name = "Indoor_" + v.name
	p.role = v.role
	p.role_name = v.role_name
	p.display_name = v.display_name
	p.home = v.home
	p.speed = walk_speed
	p.set_meta("proxy_of", v)
	p.set_meta("female", v.get_meta("female", false))
	add_child(p)
	var look: Dictionary = v._look.duplicate()
	look.prop = "none"                   # đồ cầm tay để ngoài cửa
	if look.get("hat", "none") == "non":
		look.hat = "none"                 # vào nhà thì bỏ nón (khăn vẫn đội)
	p.build_person(look)
	if v.in_uniform and v.has_outfit("uniform"):
		p.add_uniform(look)
		p.wear("uniform")
	return p


## Đặt ngay vào chỗ, đúng tư thế.
func _sit(f: Dictionary) -> void:
	var p: Villager = f.proxy
	var st: Dictionary = interior.seats[int(f.seat)]
	p.state = Villager.State.IDLE
	p.global_position = interior.to_global(st.pos)
	p.basis = Basis(Vector3.UP, float(st.yaw) + interior.global_rotation.y)
	if st.pose == "sleep":
		p.basis = p.basis * Basis(Vector3.RIGHT, -PI * 0.5)   # nằm ngửa, đầu về phía gối
	p.work_anim = str(st.pose)
	p.activity = str(st.act)
	p.activity_text = str(st.act)
	p._walk_amount = 0.0


func _walk_to_seat(f: Dictionary) -> void:
	var p: Villager = f.proxy
	var st: Dictionary = interior.seats[int(f.seat)]
	var door := interior.to_global(interior.entry_point + Vector3(0, 0, 1.2))
	p.global_position = door
	var target: Vector3 = st.pos
	if st.pose == "sleep":
		target = Vector3(target.x, interior.entry_point.y, target.z + 0.5)   # tới cạnh giường rồi nằm
	p.walk_path(PackedVector3Array([interior.to_global(interior.entry_point), interior.to_global(target)]))
	p.work_anim = "idle"
	f.arriving = true


func _leave(f: Dictionary) -> void:
	var p: Villager = f.proxy
	f.leaving = true
	p.basis = Basis(Vector3.UP, p.rotation.y)    # đứng dậy (nếu đang nằm)
	p.work_anim = "idle"
	p.walk_path(PackedVector3Array([interior.to_global(interior.entry_point),
			interior.to_global(interior.entry_point + Vector3(0, 0, 1.6))]))


func _process(delta: float) -> void:
	if _key == "" or interior == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = sync_interval
		_sync(false)
	for i in range(_folk.size() - 1, -1, -1):
		var f: Dictionary = _folk[i]
		var p: Villager = f.proxy
		if not is_instance_valid(p):
			_folk.remove_at(i)
			continue
		var was_walking := p.state == Villager.State.WALK
		if not p.has_meta("talking"):
			p.tick(delta, true)
		else:
			var st := p.state
			p.state = Villager.State.IDLE
			p.tick(delta, true)
			p.state = st
		if was_walking and p.state == Villager.State.IDLE:
			if f.leaving:
				p.queue_free()
				_folk.remove_at(i)
			elif f.get("arriving", false):
				f.arriving = false
				_sit(f)
