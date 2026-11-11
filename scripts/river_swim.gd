class_name RiverSwim
extends Node3D
## Tắm sông (mục 49). Chiều mùa hè, tan học là trẻ con chạy ùa ra các bến sông tắm: nhảy ùm xuống, bơi sải quanh
## bến, đứng té nước nhau, tới chập tối thì lên bờ về nhà. Con trai cởi trần, con gái mặc nguyên quần áo.
## - Lịch: `weight(v, h)` cho Villagers — mùa hạ sau giờ học (ngày nghỉ thì từ đầu giờ chiều) trọng số rất cao; mùa
##   xuân / thu thỉnh thoảng; mùa đông, trời mưa thì không. Đi tắm thì chạy (`run_mul`) vì bến ở xa.
## - Sông chỉ sâu ~0,26 m nên "giả" độ sâu: lúc bơi người nằm sấp sát mặt nước (xoay cả node quanh trục X, dáng `swim`
##   của Villager: tay quạt sải, chân đập); lúc đứng té nước thì hạ node xuống dưới lòng sông cho nước ngang ngực.
## - Villagers chỉ diễn hoạt (meta `talking` + `swimming`); node này dắt từng đứa (đứng SAU `World` trong cây scene).
## - Người chơi bơi (FirstPerson.swimming) tới gần thì bọn trẻ reo gọi.

@export var river: River
@export var villagers: Villagers
@export var day_night: DayNight
@export var weather: Weather
@export var calendar: LunarCalendar
@export var first_person: FirstPerson
@export var dialogue: Dialogue
@export var random_seed: int = 0

@export_group("Lịch")
## Giờ tắm sông ngày đi học (sau giờ tan học) và ngày nghỉ.
@export var hours_school_day: Vector2 = Vector2(16.5, 18.9)
@export var hours_day_off: Vector2 = Vector2(14.5, 18.9)
## Sau giờ này không rủ nhau ra sông nữa (đường ra bến xa, tới nơi thì tối).
@export var go_by: float = 18.0
## Trọng số việc tắm sông: chiều mùa hạ trong giờ tắm / mùa hạ ngoài giờ / xuân, thu.
@export var summer_weight: float = 9.0
@export var summer_off_weight: float = 1.2
@export var mild_weight: float = 1.0
## Chạy ra sông nhanh gấp mấy lần đi thường.
@export var run_mul: float = 2.0
## Mỗi đứa tắm bao lâu (giây thật) rồi lên bờ.
@export var swim_seconds: Vector2 = Vector2(50.0, 90.0)
@export var max_per_landing: int = 12

@export_group("Bơi")
## Vùng bơi quanh bến: dọc sông ± chừng này, cách mép nước từ … tới … mét.
@export var zone_along: float = 9.0
@export var zone_out: Vector2 = Vector2(2.4, 8.0)
## Tránh tâm các đầm sen chừng này mét.
@export var lotus_clear: float = 7.0
@export var swim_speed: float = 1.15
## Góc nằm sấp khi bơi (độ) và độ cao gót chân so với mặt nước.
@export var tilt_deg: float = 72.0
@export var swim_feet: float = -0.2
## Đứng té nước: bàn chân thấp hơn mặt nước chừng này (nước ngang ngực).
@export var stand_depth: float = 0.62
@export var bark_every: Vector2 = Vector2(6.0, 13.0)

const BARKS: Array[String] = ["Nước mát quá!", "Té nước này!", "Đua ra giữa sông đi!", "Ai lặn lâu hơn nào!",
		"Ùm! Ha ha ha!", "Bơi sải này, xem tao này!", "Mai lại ra tắm nhé!"]
const GREET: Array[String] = ["A, {you} cũng xuống tắm à!", "{You} bơi đua với em không?", "Nước mát lắm {you} ơi!"]

## Người đang tắm: {v, li (chỉ số bến), phase (enter | swim | splash | exit), t, target, left}
var swimmers: Array[Dictionary] = []
## Đếm sự kiện (bài thử đọc).
var stats := {"joined": 0, "left": 0, "splashes": 0, "barks": 0, "greets": 0}
var _zones: Array[Dictionary] = []     # theo bến: {s0, side, edge, spot}
var _rng := RandomNumberGenerator.new()
var _bark_t: float = 5.0
var _greet_t: float = 0.0


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()


func _build_zones() -> void:
	_zones.clear()
	if river == null:
		return
	for l: Dictionary in river.landings:
		var e: Vector3 = l.edge
		var e2 := Vector2(e.x, e.z)
		var s0 := river.nearest_s(e2)
		var smp := river.sample(s0)
		var n := (smp[1] as Vector2).orthogonal()
		var side := 1.0 if (e2 - (smp[0] as Vector2)).dot(n) >= 0.0 else -1.0
		var sp: Vector3 = l.spot
		_zones.append({"s0": s0, "side": side, "edge": e, "spot": Vector2(sp.x, sp.z)})


# --- Lịch ------------------------------------------------------------------------------------------------

func _day_off() -> bool:
	if calendar == null:
		return false
	return not calendar.is_school_day() or calendar.weekday() == 6     # thứ Bảy chỉ học sáng


## Khung giờ tắm sông hôm nay.
func hours() -> Vector2:
	return hours_day_off if _day_off() else hours_school_day


func _wet() -> bool:
	return weather != null and (weather.kind in ["drizzle", "storm"] or weather.rain > 0.25)


## Đang trong giờ tắm sông chiều hè.
func swim_time(h: float) -> bool:
	var hr := hours()
	return villagers != null and villagers.season == "summer" and h >= hr.x and h < hr.y and not _wet()


## Trọng số việc `swim` của một đứa trẻ lúc `h` giờ (Villagers gọi).
func weight(v: Villager, h: float) -> float:
	if villagers == null or villagers.season == "winter" or _wet() or v.role != "kid":
		return 0.0
	if villagers.season == "summer":
		return summer_weight if (swim_time(h) and h < go_by) else summer_off_weight
	return mild_weight if h >= 13.0 else 0.0


## Bến gần nhất còn chỗ (Villagers lấy đích).
func landing_for(v: Villager) -> Dictionary:
	var best := -1
	var bd := INF
	for i in river.landings.size():
		if _count_at(i) >= max_per_landing:
			continue
		var d := (river.landings[i].edge as Vector3).distance_squared_to(v.global_position)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		best = _rng.randi_range(0, river.landings.size() - 1)
	return river.landings[best]


func _count_at(li: int) -> int:
	var n := 0
	for s in swimmers:
		if int(s.li) == li:
			n += 1
	return n


func is_member(v: Villager) -> bool:
	return v != null and v.has_meta("swimming")


# --- Vào / ra ---------------------------------------------------------------------------------------------

## Villagers gọi khi một đứa trẻ (việc `swim`) chạy tới mép nước ở bến.
func on_arrive(v: Villager) -> void:
	if river == null or is_member(v):
		return
	if _zones.size() != river.landings.size():
		_build_zones()
	var li := 0
	for i in _zones.size():
		if (_zones[i].edge as Vector3).distance_squared_to(v.global_position) < (_zones[li].edge as Vector3).distance_squared_to(v.global_position):
			li = i
	v.set_meta("swimming", true)
	v.set_meta("talking", true)       # Villagers chỉ diễn hoạt, không dắt đi, không đổi việc
	v.dwell = 1.0e6
	v.speed_mul = 1.0
	if not v.get_meta("female", false):
		v.set_meta("outfit_before", v.outfit)
		v.add_shirtless()
		v.wear("shirtless")           # con trai cởi trần nhảy xuống
	v.activity_text = "đang tắm sông"
	swimmers.append({"v": v, "li": li, "phase": "enter", "t": 0.0, "target": _zone_point(li),
			"left": _rng.randf_range(swim_seconds.x, swim_seconds.y), "rip": 0.0})
	stats.joined = int(stats.joined) + 1


## Một điểm trong vùng bơi của bến (tránh cầu ván, đầm sen và đò neo).
func _zone_point(li: int) -> Vector3:
	var z: Dictionary = _zones[li]
	var q := Vector2.ZERO
	for i in 16:
		var s := float(z.s0) + _rng.randf_range(-zone_along, zone_along)
		var smp := river.sample(s)
		var n := (smp[1] as Vector2).orthogonal()
		var out := minf(_rng.randf_range(zone_out.x, zone_out.y), river.half_width(s) * 1.4)
		q = (smp[0] as Vector2) + n * float(z.side) * (river.half_width(s) - out)
		if q.distance_to(z.spot as Vector2) < 2.6:
			continue
		var clear := true
		for lp: Vector3 in river.lotus_spots:          # không bơi vào đầm sen
			if Vector2(lp.x, lp.z).distance_to(q) < lotus_clear:
				clear = false
		for b: Node3D in river.boat_nodes:
			if Vector2(b.global_position.x, b.global_position.z).distance_to(q) < 6.5:
				clear = false
		if clear:
			break
	return Vector3(q.x, river.water_level, q.y)


func _release(s: Dictionary, done: bool) -> void:
	swimmers.erase(s)
	stats.left = int(stats.left) + 1
	var v: Villager = s.v
	if not is_instance_valid(v):
		return
	v.remove_meta("swimming")
	v.remove_meta("talking")
	v.rotation.x = 0.0
	v.work_anim = "idle"
	if v.outfit == "shirtless":
		v.wear(str(v.get_meta("outfit_before", "casual")))     # lên bờ mặc áo lại
	if done:
		var e: Vector3 = _zones[int(s.li)].edge
		v.global_position = Vector3(v.global_position.x, e.y, v.global_position.z)
		v.dwell = 0.0                 # Villagers chọn việc tiếp theo (thường là về nhà)


# --- Mỗi khung --------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if swimmers.is_empty():
		return
	step(delta)


## Một bước mô phỏng (bài thử gọi thẳng).
func step(delta: float) -> void:
	var h := day_night.time_of_day if day_night != null else 17.0
	var must_leave := _wet() or h >= hours().y or h < 5.0
	for s: Dictionary in swimmers.duplicate():
		var v: Villager = s.v
		# Bị Villagers gọi đi việc khác (lên lại lịch, giông…): thôi tắm
		if not is_instance_valid(v) or v.activity != "swim" or v.state == Villager.State.WALK:
			_release(s, false)
			continue
		s.t = float(s.t) + delta
		s.left = float(s.left) - delta
		if (must_leave or float(s.left) <= 0.0) and str(s.phase) != "exit":
			s.phase = "exit"
			s.t = 0.0
			var e: Vector3 = _zones[int(s.li)].edge
			s.target = Vector3(e.x, river.water_level, e.z)
		match str(s.phase):
			"enter":
				# Chạy mấy bước từ mép bờ rồi nhảy ùm xuống
				v.work_anim = "idle"
				v._walk_amount = 1.0
				if _move(v, s.target as Vector3, swim_speed * 1.6, delta) or float(s.t) > 4.0 \
						or (float(s.t) > 0.9 and river.is_water(Vector2(v.global_position.x, v.global_position.z), 1.6)):
					river.splash(v.global_position)
					stats.splashes = int(stats.splashes) + 1
					s.phase = "swim"
					s.target = _zone_point(int(s.li))
					s.t = 0.0
			"swim":
				_prone(v, delta)
				if _move(v, s.target as Vector3, swim_speed, delta):
					if _rng.randf() < 0.4:
						s.phase = "splash"
						s.t = 0.0
						s.hold = _rng.randf_range(3.0, 6.5)
					else:
						s.target = _zone_point(int(s.li))
				_ripple(s, v, delta, 0.9)
			"splash":
				_stand(v, delta, stand_depth)
				v.work_anim = "play"
				_face_buddy(v, delta)
				_ripple(s, v, delta, 0.6)
				if float(s.t) > float(s.get("hold", 4.0)):
					s.phase = "swim"
					s.target = _zone_point(int(s.li))
			"exit":
				_prone(v, delta)
				if _move(v, s.target as Vector3, swim_speed * 1.2, delta) or float(s.t) > 25.0:
					_release(s, true)
	_barks(delta)


## Đi / bơi về phía `to` (chỉ theo mặt phẳng ngang); true khi tới nơi.
func _move(v: Villager, to: Vector3, speed: float, dt: float) -> bool:
	var p := v.global_position
	var d := Vector3(to.x - p.x, 0.0, to.z - p.z)
	var dist := d.length()
	if dist < 0.35:
		return true
	v.global_position = p + d / dist * minf(dist, speed * dt)
	v.rotation.y = lerp_angle(v.rotation.y, atan2(d.x, d.z), minf(dt * 4.0, 1.0))
	return false


## Nằm sấp bơi sải sát mặt nước.
func _prone(v: Villager, dt: float) -> void:
	v.work_anim = "swim"
	v._walk_amount = 0.0
	var k := minf(dt * 5.0, 1.0)
	v.rotation.x = lerpf(v.rotation.x, deg_to_rad(tilt_deg), k)
	v.global_position.y = lerpf(v.global_position.y, river.water_level + swim_feet, k)


## Đứng trong nước, chân thấp hơn mặt nước `depth`.
func _stand(v: Villager, dt: float, depth: float) -> void:
	v._walk_amount = 0.0
	var k := minf(dt * 5.0, 1.0)
	v.rotation.x = lerpf(v.rotation.x, 0.0, k)
	v.global_position.y = lerpf(v.global_position.y, river.water_level - depth, k)


## Quay mặt về đứa đang tắm gần nhất (hoặc người chơi đang bơi gần) để té nước.
func _face_buddy(v: Villager, dt: float) -> void:
	var best := Vector3.INF
	var bd := 64.0
	for s in swimmers:
		var o: Villager = s.v
		if o != v and is_instance_valid(o):
			var d := o.global_position.distance_squared_to(v.global_position)
			if d < bd:
				bd = d
				best = o.global_position
	if first_person != null and first_person.active and first_person.swimming:
		var d2 := first_person.global_position.distance_squared_to(v.global_position)
		if d2 < bd:
			best = first_person.global_position
	if best != Vector3.INF:
		var f := best - v.global_position
		v.rotation.y = lerp_angle(v.rotation.y, atan2(f.x, f.z), minf(dt * 4.0, 1.0))


func _ripple(s: Dictionary, v: Villager, dt: float, every: float) -> void:
	s.rip = float(s.rip) - dt
	if float(s.rip) > 0.0:
		return
	s.rip = every * _rng.randf_range(0.8, 1.3)
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(v.global_position) > 90.0:
		return
	var fwd := Vector3(sin(v.rotation.y), 0.0, cos(v.rotation.y))
	river.splash(v.global_position + fwd * 0.7)
	stats.splashes = int(stats.splashes) + 1


## Thỉnh thoảng một đứa reo; người chơi bơi tới gần thì gọi.
func _barks(delta: float) -> void:
	if dialogue == null or swimmers.is_empty():
		return
	_bark_t -= delta
	if _bark_t <= 0.0:
		_bark_t = _rng.randf_range(bark_every.x, bark_every.y)
		var v: Villager = swimmers[_rng.randi_range(0, swimmers.size() - 1)].v
		if is_instance_valid(v):
			dialogue.bark(v, BARKS[_rng.randi_range(0, BARKS.size() - 1)])
			stats.barks = int(stats.barks) + 1
	_greet_t -= delta
	if _greet_t <= 0.0 and first_person != null and first_person.active and first_person.swimming:
		for s in swimmers:
			var v: Villager = s.v
			if is_instance_valid(v) and v.global_position.distance_to(first_person.global_position) < 7.0:
				dialogue.bark(v, dialogue.fill_for(v, GREET[_rng.randi_range(0, GREET.size() - 1)]))
				stats.greets = int(stats.greets) + 1
				_greet_t = 14.0
				break
