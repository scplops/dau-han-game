class_name SchoolDay
extends Node3D
## Ngày học ở trường tiểu học (mục 26): thời khoá biểu, học sinh làng bên, trẻ con trong làng vào lớp.
## - Thời khoá biểu (`phase`): đến trường → (thứ Hai: chào cờ) → học → ra chơi → học → tan học, sáng và
##   chiều; thứ Bảy chỉ học sáng; nghỉ Chủ nhật và dịp Tết (LunarCalendar.is_school_day).
## - Học sinh làng bên (`pupil_count`, mặc đồng phục) đi theo đường đất vào cổng trường; trẻ con trong
##   làng (Villagers, việc `school`) cũng do SchoolDay điều khiển khi đã tới trường (`on_arrive`).
## - Giờ học: đi tới cửa lớp (tầng 1) rồi vào lớp (ẩn, meta `in_class` — IndoorFolk cho ngồi bàn khi
##   người chơi vào lớp học). Ra chơi: ùa ra sân chạy nhảy. Thứ Hai đầu giờ: xếp hàng chào cờ.
##   Tan học: ra cổng — học sinh làng bên đi xuôi đường đất rồi khuất; trẻ con trong làng về nhà.

@export var school: School
@export var villagers: Villagers
@export var calendar: LunarCalendar
@export var day_night: DayNight
@export var weather: Weather
@export_range(0, 60) var pupil_count: int = 16
@export var random_seed: int = 2027
@export var walk_speed: Vector2 = Vector2(1.3, 1.8)
@export var animate_distance: float = 70.0

## [giờ bắt đầu, giờ kết thúc, giai đoạn] — sáng và chiều.
const TIMETABLE := [
	[6.4, 7.0, "arrive"], [7.0, 9.2, "class"], [9.2, 9.6, "recess"], [9.6, 11.0, "class"], [11.0, 11.4, "leave"],
	[13.0, 13.5, "arrive"], [13.5, 14.9, "class"], [14.9, 15.25, "recess"], [15.25, 16.5, "class"], [16.5, 16.9, "leave"],
]
## Thứ Hai: 7:00–7:30 chào cờ đầu tuần thay tiết đầu.
const FLAG_TIME := Vector2(7.0, 7.5)
const GIRL_NAMES := ["Lan", "Hoa", "Mai", "Thảo", "Hằng", "Nga", "Huệ", "Liên", "Trang", "Thu", "Yến", "Hiền", "Vân", "Ngọc"]
const BOY_NAMES := ["Nam", "Hùng", "Dũng", "Tuấn", "Long", "Quân", "Hải", "Sơn", "Bình", "Khánh", "Tùng", "Phong", "Đức", "Việt"]

var pupils: Array[Villager] = []
var _rng := RandomNumberGenerator.new()
var _phase: String = ""
var _timer: float = 0.0


func _ready() -> void:
	_rng.seed = random_seed
	if school == null:
		return
	_spawn_pupils.call_deferred()


# --- Thời khoá biểu ---------------------------------------------------------------------------

func _hour() -> float:
	return day_night.time_of_day if day_night != null else 9.0


## Giai đoạn của buổi học lúc giờ `h` hôm nay: off | arrive | flag | class | recess | leave.
func phase(h: float) -> String:
	if calendar != null and not calendar.is_school_day():
		return "off"
	var saturday := calendar != null and calendar.weekday() == 6
	var monday := calendar != null and calendar.weekday() == 1
	for p in TIMETABLE:
		if h >= float(p[0]) and h < float(p[1]):
			if saturday and h >= 12.0:
				return "off"
			if monday and h >= FLAG_TIME.x and h < FLAG_TIME.y:
				return "flag"
			return str(p[2])
	return "off"


## Trẻ con trong làng có nên đi học / còn ở trường lúc này không.
func wants_pupils(h: float) -> bool:
	return phase(h) in ["arrive", "flag", "class", "recess"]


func phase_text() -> String:
	match _phase:
		"arrive": return "học sinh đang đến trường"
		"flag": return "chào cờ đầu tuần"
		"class": return "đang trong giờ học"
		"recess": return "giờ ra chơi"
		"leave": return "tan học"
	return "trường nghỉ"


## Những học sinh đang ngồi trong lớp (IndoorFolk dùng khi vào lớp học).
func in_class() -> Array[Villager]:
	var out: Array[Villager] = []
	for v in pupils:
		if v.has_meta("in_class"):
			out.append(v)
	if villagers != null:
		for v in villagers.people:
			if v.has_meta("in_class"):
				out.append(v)
	return out


# --- Học sinh làng bên -------------------------------------------------------------------------

func _spawn_pupils() -> void:
	var shirts: Array[Color] = [Palette.SIGN_BLUE, Palette.LILY, Palette.FLOWER_PINK, Palette.FARMER_SHIRT, Palette.ALTAR_RED.lightened(0.2)]
	var used := {}
	for i in pupil_count:
		var female := i % 2 == 0
		var v := Villager.new()
		v.name = "Pupil%d" % i
		v.role = "kid"
		v.role_name = "Học sinh làng bên"
		var names: Array = GIRL_NAMES if female else BOY_NAMES
		var nm := str(names[_rng.randi_range(0, names.size() - 1)])
		for t in 5:
			if not used.has(nm):
				break
			nm = str(names[_rng.randi_range(0, names.size() - 1)])
		used[nm] = true
		v.display_name = ("Bé " if female else "Cu ") + nm
		v.speed = _rng.randf_range(walk_speed.x, walk_speed.y)
		v.side_offset = _rng.randf_range(-0.6, 0.6)
		v.set_meta("female", female)
		v.set_meta("pupil", true)
		v.set_meta("class", i % maxi(school.classroom_doors.size(), 1))
		var spawn := Vector3(school.road_x + _rng.randf_range(-0.8, 0.8), 0.06, school.gate_z + _rng.randf_range(14.0, 48.0))
		v.set_meta("spawn", spawn)
		v.home = {"name": "Làng bên", "key": "", "front": spawn, "door": spawn, "gate": spawn}
		add_child(v)
		var look := {"shirt": shirts[_rng.randi_range(0, shirts.size() - 1)], "pants": Palette.WINDOW_DARK,
				"skin": Palette.FARMER_SKIN.darkened(_rng.randf_range(-0.04, 0.08)), "hat": "none" if female else "tuft",
				"scale": _rng.randf_range(0.6, 0.74), "female": female, "prop": "none"}
		v.build_person(look)
		v.add_uniform(look)
		v.wear("uniform")
		pupils.append(v)
	_place_all()


## Đặt ngay mọi học sinh đúng chỗ theo giờ hiện tại (lúc mở game, đổi giờ / ngày đột ngột).
func _place_all() -> void:
	_phase = phase(_hour())
	for v in pupils:
		_place(v, _phase)
	if villagers != null:
		for v in villagers.people:
			if v.has_meta("at_school"):
				_place(v, _phase)


func replan() -> void:
	_place_all()


func _place(v: Villager, ph: String) -> void:
	v.remove_meta("in_class")
	v.state = Villager.State.IDLE
	v.path = PackedVector3Array()
	match ph:
		"class":
			v.global_position = _door(v)
			v.visible = false
			v.set_meta("in_class", true)
			v.activity_text = "đang ngồi học trong lớp"
		"recess", "arrive":
			v.global_position = _yard_spot()
			v.visible = true
			v.work_anim = "play"
			v.activity_text = "đang ra chơi ở sân trường" if ph == "recess" else "đang chơi ở sân trường chờ vào lớp"
			v.dwell = _rng.randf_range(2.0, 8.0)
		"flag":
			v.global_position = _flag_slot(v)
			v.visible = true
			v.rotation.y = PI
			v.work_anim = "idle"
			v.activity_text = "đang chào cờ đầu tuần"
		_:
			if v.has_meta("pupil"):
				v.global_position = v.get_meta("spawn")
				v.visible = false
				v.activity_text = "đang ở nhà bên làng bên"
			else:
				_release(v)


# --- Đường đi --------------------------------------------------------------------------------

func _door(v: Villager) -> Vector3:
	var i := int(v.get_meta("class", 0)) % school.classroom_doors.size()
	return school.classroom_doors[i] + Vector3(_rng.randf_range(-0.4, 0.4), 0, 0)


func _front(v: Villager) -> Vector3:
	var i := int(v.get_meta("class", 0)) % school.classroom_fronts.size()
	return school.classroom_fronts[i] + Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.3, 0.3))


func _yard_spot() -> Vector3:
	return school.yard_spots[_rng.randi_range(0, school.yard_spots.size() - 1)] + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2))


## Chỗ đứng chào cờ: mỗi lớp một hàng dọc trước cột cờ, quay mặt về cột cờ.
func _flag_slot(v: Villager) -> Vector3:
	var c := int(v.get_meta("class", 0))
	var idx := 0
	for p in pupils + (villagers.people if villagers != null else []):
		if p == v:
			break
		if int(p.get_meta("class", -1)) == c and (p.has_meta("pupil") or p.has_meta("at_school")):
			idx += 1
	var n := maxi(school.classroom_doors.size(), 1)
	return school.flag_pos + Vector3((c - (n - 1) * 0.5) * 1.6, 0.0, 3.0 + idx * 0.85)


func _walk(v: Villager, pts: Array[Vector3], goal: String) -> void:
	v.set_meta("goal", goal)
	v.visible = true
	v.walk_path(PackedVector3Array(pts))
	v.work_anim = "idle"


## Đi tới lớp rồi vào lớp.
func _go_class(v: Villager) -> void:
	if v.has_meta("in_class"):
		return
	_walk(v, [_front(v), _door(v)], "class")
	v.activity_text = "đang vào lớp"


func _go_yard(v: Villager) -> void:
	var pts: Array[Vector3] = []
	if v.has_meta("in_class"):
		v.remove_meta("in_class")
		v.global_position = _door(v)
		pts.append(_front(v))
	pts.append(_yard_spot())
	_walk(v, pts, "yard")
	v.activity_text = "đang ra chơi ở sân trường"


func _go_flag(v: Villager) -> void:
	var pts: Array[Vector3] = []
	if v.has_meta("in_class"):
		v.remove_meta("in_class")
		v.global_position = _door(v)
		pts.append(_front(v))
	pts.append(_flag_slot(v))
	_walk(v, pts, "flag")
	v.activity_text = "đang ra xếp hàng chào cờ"


## Tan học: học sinh làng bên ra cổng, đi xuôi đường đất; trẻ con trong làng trả về Villagers.
func _go_home(v: Villager) -> void:
	if not v.has_meta("pupil"):
		if v.has_meta("in_class"):
			v.remove_meta("in_class")
			v.global_position = _door(v)
			v.visible = true
		_release(v)
		return
	var pts: Array[Vector3] = []
	if v.has_meta("in_class"):
		v.remove_meta("in_class")
		v.global_position = _door(v)
		pts.append(_front(v))
	pts.append(school.gate_in)
	pts.append(school.gate_out)
	pts.append(v.get_meta("spawn"))
	_walk(v, pts, "home")
	v.activity_text = "tan học, đang về làng bên"


## Học sinh làng bên đi tới trường (đang ở nhà = ẩn ở đầu đường).
func _come(v: Villager) -> void:
	v.global_position = v.get_meta("spawn")
	_walk(v, [school.gate_out, school.gate_in, _yard_spot()], "arrive")
	v.activity_text = "đang đi học"


func _release(v: Villager) -> void:
	v.remove_meta("at_school")
	v.remove_meta("goal")
	v.remove_meta("in_class")
	v.visible = true
	v.dwell = 0.0          # Villagers chọn việc tiếp theo (về nhà, đi chơi…)


# --- Trẻ con trong làng ----------------------------------------------------------------------

## Villagers gọi khi một đứa trẻ trong làng (việc `school`) đi tới nơi ở trường.
func on_arrive(v: Villager) -> void:
	var goal := str(v.get_meta("goal", "arrive"))
	if not v.has_meta("pupil"):
		v.set_meta("at_school", true)
		if not v.has_meta("class"):
			v.set_meta("class", _rng.randi_range(0, maxi(school.classroom_doors.size(), 1) - 1))
		v.dwell = 1.0e6     # SchoolDay giữ cho tới khi tan học
	match goal:
		"class":
			v.visible = false
			v.set_meta("in_class", true)
			v.activity_text = "đang ngồi học trong lớp"
		"flag":
			v.rotation.y = PI
			v.work_anim = "idle"
			v.activity_text = "đang chào cờ đầu tuần"
		"home":
			v.visible = false
			v.activity_text = "đang ở nhà bên làng bên"
		_:
			v.work_anim = "play"
			v.dwell = 1.0e6 if not v.has_meta("pupil") else _rng.randf_range(2.0, 7.0)
			v.set_meta("play_timer", _rng.randf_range(2.0, 7.0))
			v.activity_text = "đang chơi ở sân trường"
	v.remove_meta("goal")
	# Tới nơi mà giai đoạn đã đổi (vd. vừa tới sân thì vào học): làm theo giai đoạn hiện tại
	_follow_phase(v, phase(_hour()))


## Đưa một học sinh về đúng việc của giai đoạn `ph` (nếu đang làm khác).
func _follow_phase(v: Villager, ph: String) -> void:
	if v.state == Villager.State.WALK:
		var goal := str(v.get_meta("goal", ""))
		var want: String = {"class": "class", "recess": "yard", "arrive": "yard", "flag": "flag", "leave": "home", "off": "home"}.get(ph, "")
		if goal == want or (goal == "arrive" and want == "yard"):
			return
	match ph:
		"class":
			if not v.has_meta("in_class") and v.visible:
				_go_class(v)
		"recess", "arrive":
			if v.has_meta("in_class") or str(v.get_meta("goal", "")) == "flag" or v.activity_text == "đang chào cờ đầu tuần":
				_go_yard(v)
		"flag":
			if v.activity_text != "đang chào cờ đầu tuần" and v.state != Villager.State.WALK:
				_go_flag(v)
		"leave", "off":
			if v.has_meta("pupil"):
				if v.visible or v.has_meta("in_class"):
					if str(v.get_meta("goal", "")) != "home":
						_go_home(v)
			else:
				_go_home(v)


# --- Mỗi khung hình ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if school == null:
		return
	var h := _hour()
	var ph := phase(h)
	var changed := ph != _phase
	_phase = ph
	_timer -= delta
	var check := changed or _timer <= 0.0
	if check:
		_timer = 0.5
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	var storm := weather != null and weather.kind == "storm" and weather.rain > 0.5
	for v in pupils:
		if v.has_meta("talking"):
			var st := v.state
			v.state = Villager.State.IDLE
			v.tick(delta, true)
			v.state = st
			continue
		var was_walking := v.state == Villager.State.WALK
		v.tick(delta, v.visible and v.global_position.distance_to(cam_pos) < animate_distance)
		if was_walking and v.state == Villager.State.IDLE:
			on_arrive(v)
			continue
		if check:
			# Đang ở nhà (ẩn ở đầu đường) và trường mở: đi học
			if not v.visible and not v.has_meta("in_class") and wants_pupils(h) and not storm and v.state != Villager.State.WALK:
				_come(v)
			elif v.visible or v.has_meta("in_class"):
				_follow_phase(v, ph)
		_wander(v, delta, ph)
	# Trẻ con trong làng đang ở trường
	if villagers != null and check:
		for v in villagers.people:
			if v.has_meta("at_school"):
				if v.activity != "school":
					_release(v)          # Villagers đã gọi đi việc khác (giông, tối…)
				else:
					_follow_phase(v, ph)
	if villagers != null:
		for v in villagers.people:
			if v.has_meta("at_school") and v.state == Villager.State.IDLE:
				_wander(v, delta, ph)


## Giờ ra chơi: chạy từ chỗ này sang chỗ khác trong sân.
func _wander(v: Villager, delta: float, ph: String) -> void:
	if not (ph in ["recess", "arrive"]) or not v.visible or v.state != Villager.State.IDLE or v.has_meta("talking"):
		return
	var t := float(v.get_meta("play_timer", 0.0)) - delta
	v.set_meta("play_timer", t)
	if t <= 0.0:
		v.set_meta("play_timer", _rng.randf_range(3.0, 8.0))
		_walk(v, [_yard_spot()], "yard")
		v.speed_mul = 1.4
