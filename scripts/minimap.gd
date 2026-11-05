class_name MiniMap
extends Control
## Bản đồ nhỏ (mục 23), vẽ bằng code từ dữ liệu thật của cảnh: ruộng, đường đất, sông, lũy tre,
## đường trục, ngõ, lô đất + nhà, đình, chùa, ao, giếng, cây đa, sân bóng, trường, nhà mình, bến sông.
## - Hướng bắc ở trên (−z). Mũi tên = người chơi khi nhập vai; hình quạt = vùng camera ngắm cảnh.
## - Chấm dân làng, "!" người có việc nhờ, hình thoi vàng = mục tiêu việc đang làm.
## - Phím M (action `toggle_minimap`): nhỏ ở góc → lớn giữa màn hình (cả làng, có tên chỗ) → ẩn.
## - Bấm vào bản đồ (chế độ ngắm cảnh): đưa camera tới chỗ đó.

enum Mode { SMALL, LARGE, HIDDEN }

@export var terrain: Terrain
@export var village: Village
@export var river: River
@export var school: School
@export var football: Football
@export var house: House
@export var villagers: Villagers
@export var quests: Quests
@export var first_person: FirstPerson
@export var outdoor_rig: CameraRig
@export var house_entry: HouseEntry
@export var boat_ride: BoatRide
@export var school_day: SchoolDay

@export_group("Hiển thị")
@export var small_size: float = 230.0
## Bán kính vùng nhìn của bản đồ nhỏ (m).
@export var small_radius: float = 75.0
@export var large_size: float = 680.0
@export var large_center: Vector2 = Vector2(-15.0, -92.0)
@export var large_radius: float = 165.0
@export var redraw_interval: float = 0.05

var mode: Mode = Mode.SMALL
var _center := Vector2.ZERO
var _scale: float = 1.0
var _timer: float = 0.0
var _font: Font
var _font_bold: Font


func _ready() -> void:
	_font = Hud.font(false)
	_font_bold = Hud.font(true)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_mode()
	get_viewport().size_changed.connect(_apply_mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_minimap"):
		mode = ((int(mode) + 1) % 3) as Mode
		_apply_mode()
		get_viewport().set_input_as_handled()


## Đặt kích thước / vị trí theo chế độ: nhỏ ở góc dưới phải (trên dải phím tắt), lớn ở giữa.
func _apply_mode() -> void:
	visible = mode != Mode.HIDDEN
	var vp := get_viewport_rect().size
	if mode == Mode.SMALL:
		size = Vector2(small_size, small_size)
		position = Vector2(vp.x - small_size - 20.0, vp.y - small_size - 92.0)
	elif mode == Mode.LARGE:
		var s := minf(large_size, minf(vp.x, vp.y) - 160.0)
		size = Vector2(s, s)
		position = (vp - size) * 0.5 + Vector2(0, -20)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Bấm vào bản đồ: camera ngắm cảnh bay tới đó (không áp dụng khi đang nhập vai / trong nhà)
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if outdoor_rig != null and not (first_person != null and first_person.active) \
				and not (house_entry != null and house_entry.inside):
			var w := _m2w((event as InputEventMouseButton).position)
			outdoor_rig.set_focus(Vector3(w.x, 0.0, w.y))
		accept_event()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = redraw_interval
		queue_redraw()


# --- Toạ độ --------------------------------------------------------------------------------

func _w2m(p: Vector2) -> Vector2:
	return (p - _center) * _scale + size * 0.5


func _m2w(m: Vector2) -> Vector2:
	return (m - size * 0.5) / _scale + _center


func _pts(arr: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(_w2m(p))
	return out


## Chỗ đứng (x, z) và hướng nhìn (rad, theo quy ước yaw của Godot) của người chơi / camera.
func _player() -> Array:
	if house_entry != null and house_entry.inside and house_entry._target != null:
		var t := house_entry._target.global_position
		return [Vector2(t.x, t.z), 0.0, true]
	if boat_ride != null and boat_ride.active:
		var b := boat_ride.boat.global_position
		return [Vector2(b.x, b.z), boat_ride.heading_for_map(), true]
	if first_person != null and first_person.active:
		var p := first_person.global_position
		return [Vector2(p.x, p.z), first_person.rotation.y, true]
	if outdoor_rig != null:
		var f := outdoor_rig.global_position
		return [Vector2(f.x, f.z), deg_to_rad(outdoor_rig.yaw_deg), false]
	return [Vector2.ZERO, 0.0, false]


# --- Vẽ --------------------------------------------------------------------------------------

func _draw() -> void:
	var pl: Array = _player()
	if mode == Mode.LARGE:
		_center = large_center
		_scale = size.x / (large_radius * 2.0)
	else:
		_center = pl[0]
		_scale = size.x / (small_radius * 2.0)
	var lw := func(m: float) -> float: return maxf(m * _scale, 1.5)

	# Nền + khung
	draw_rect(Rect2(Vector2.ZERO, size), Palette.GRASS.darkened(0.12))
	# Ruộng, sân, đường đất
	if terrain != null:
		for r: Rect2 in terrain.outer_fields:
			_rect(r, Palette.RICE_2.darkened(0.05))
		_rect(terrain.field_rect, Palette.RICE_1)
		_rect(terrain.yard_rect, Palette.YARD)
		for road: PackedVector2Array in terrain.roads:
			draw_polyline(_pts(road), Palette.EARTH, lw.call(terrain.road_width))
		draw_polyline(_pts(terrain.path_points), Palette.EARTH, lw.call(terrain.path_width))
		_ellipse(terrain.pond_center, Vector2.ONE * terrain.pond_radius, Palette.WATER)
	# Sông: đê sẫm rồi nước
	if river != null and not river._pts.is_empty():
		var rp := _pts(river._pts)
		draw_polyline(rp, Palette.DIKE, lw.call(26.0))
		draw_polyline(rp, Palette.WATER, lw.call(14.0))
	# Làng: nền, lũy tre
	if village != null:
		_ellipse(village.center, village.radii, Palette.GRASS.lightened(0.04))
		_ellipse_ring(village.center, village.radii, Palette.BAMBOO_LEAF_DARK, lw.call(5.0))
		for r: Rect2 in village._occupied:
			_rect(r.grow(-0.6), Palette.YARD.lerp(Palette.GRASS, 0.55))
		draw_polyline(_pts(village.lane_points()), Palette.LANE_BRICK, lw.call(village.main_lane_width))
		for a: PackedVector2Array in village.alley_lines():
			draw_polyline(_pts(a), Palette.LANE_BRICK, lw.call(village.alley_width))
		for ap: Dictionary in village.access_paths:
			draw_polyline(_pts(ap.points), Palette.LANE_BRICK, lw.call(village.access_width))
		# Nhà: khối mái sau cửa
		for h: Dictionary in village.homes:
			var door: Vector3 = h.door
			var fwd: Vector3 = h.forward
			_house(Vector2(door.x, door.z) - Vector2(fwd.x, fwd.z) * 2.6, Vector2(fwd.x, fwd.z), Vector2(7.5, 4.6), Palette.ROOF)
		# Đình, chùa, ao, giếng, cây đa, sân bóng
		var ds := Vector2(village.dinh_spot.x, village.dinh_spot.z)
		_rect(Rect2(ds.x - village.dinh_half_width + 1.5, ds.y - 5.0, (village.dinh_half_width - 1.5) * 2.0, 15.0), Palette.LANE_BRICK.darkened(0.1))
		_house(ds + Vector2(0, -9.0), Vector2(0, 1), Vector2(16.0, 9.0), Palette.ROOF_BROWN)
		_rect(village.pagoda_rect, Palette.YARD)
		_house(village.pagoda_rect.get_center() + Vector2(0, -4.5), Vector2(0, 1), Vector2(13.0, 9.0), Palette.ROOF_BROWN)
		_ellipse(village.pond_center, village.pond_radii, Palette.WATER)
		draw_circle(_w2m(Vector2(village.well_position.x, village.well_position.z)), maxf(1.6 * _scale, 2.5), Palette.ROCK)
		draw_circle(_w2m(Vector2(village.banyan_position.x, village.banyan_position.z)), maxf(5.0 * _scale, 3.0), Palette.BANYAN_LEAF_1)
		_rect(village.pitch_rect, Palette.GRASS.lerp(Palette.DIKE, 0.3))
		draw_rect(Rect2(_w2m(village.pitch_rect.position), village.pitch_rect.size * _scale), Palette.SCHOOL_TRIM, false, 1.0)
	# Trường
	if school != null:
		_rect(school.site, Palette.SCHOOL_YARD)
		_house(Vector2(school.site.get_center().x + 3.0, school.site.position.y + 6.0), Vector2(0, 1), Vector2(30.0, 8.0), Palette.ROOF)
	# Nhà mình
	if house != null:
		var hp := Vector2(house.house_position.x, house.house_position.z)
		var hf := Vector2(sin(deg_to_rad(house.house_yaw_deg)), cos(deg_to_rad(house.house_yaw_deg)))
		_house(hp, hf, Vector2(house.length, house.depth), Palette.ROOF)
	# Bến sông
	if river != null:
		for l: Dictionary in river.landings:
			var s: Vector3 = l.spot
			draw_circle(_w2m(Vector2(s.x, s.z)), 3.0, Palette.WOOD_LIGHT)
		# Đò: thoi gỗ dọc theo hướng mũi
		for b: Node3D in river.boat_nodes:
			var bp := Vector2(b.global_position.x, b.global_position.z)
			var f := Vector2(sin(b.rotation.y), cos(b.rotation.y))
			var half := maxf(4.8 * _scale, 4.0)
			var side := f.orthogonal() * maxf(1.1 * _scale, 1.6)
			var m := _w2m(bp)
			# _w2m: x giữ, z → y; hướng trên bản đồ cũng vậy
			draw_colored_polygon(PackedVector2Array([m + f * half, m + side, m - f * half, m - side]), Palette.WOOD)

	_draw_people()
	_draw_quests()
	if mode == Mode.LARGE:
		_draw_labels()
	_draw_player(pl)
	# La bàn "B" (Bắc) + thước tỉ lệ
	draw_string(_font_bold, Vector2(size.x - 22, 22), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.HUD_TEXT)
	draw_line(Vector2(size.x - 17, 26), Vector2(size.x - 17, 36), Palette.HUD_TEXT, 2.0)
	var bar_m := 20.0 if mode == Mode.SMALL else 50.0
	var bar := bar_m * _scale
	draw_line(Vector2(10, size.y - 12), Vector2(10 + bar, size.y - 12), Palette.HUD_TEXT, 2.0)
	draw_string(_font, Vector2(14 + bar, size.y - 7), "%d m" % int(bar_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.HUD_TEXT)
	if mode == Mode.LARGE:
		draw_string(_font, Vector2(10, 20), "M: ẩn bản đồ  ·  bấm để đưa camera tới", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.HUD_SUBTEXT)
	# Khung viền
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.WINDOW_DARK, 0.8), false, 3.0)


func _rect(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(_w2m(r.position), r.size * _scale), col)


func _ellipse_points(c: Vector2, r: Vector2, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(_w2m(c + Vector2(cos(a) * r.x, sin(a) * r.y)))
	return pts


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	draw_colored_polygon(_ellipse_points(c, r), col)


func _ellipse_ring(c: Vector2, r: Vector2, col: Color, width: float) -> void:
	var pts := _ellipse_points(c, r, 64)
	pts.append(pts[0])
	draw_polyline(pts, col, width)


## Khối nhà xoay theo hướng mặt tiền `fwd` (x, z), kích thước dài × sâu (m).
func _house(c: Vector2, fwd: Vector2, dims: Vector2, col: Color) -> void:
	var f := fwd.normalized()
	var side := Vector2(f.y, -f.x)
	var hx := dims.x * 0.5
	var hz := dims.y * 0.5
	var pts := PackedVector2Array([
		_w2m(c + side * hx + f * hz), _w2m(c - side * hx + f * hz),
		_w2m(c - side * hx - f * hz), _w2m(c + side * hx - f * hz)])
	draw_colored_polygon(pts, col)


func _draw_people() -> void:
	if villagers == null:
		return
	var r := 2.4 if mode == Mode.SMALL else 2.0
	for v in villagers.people:
		if not v.visible or v.has_meta("hiding"):
			continue                       # đang trốn (trốn tìm) thì không lộ trên bản đồ
		var col := Palette.FLOWER_YELLOW if v.role in ["kid", "herder"] else Palette.HUD_TEXT
		draw_circle(_w2m(Vector2(v.global_position.x, v.global_position.z)), r, col.darkened(0.1))
		if v.has_meta("quest_offer"):
			var m := _w2m(Vector2(v.global_position.x, v.global_position.z))
			draw_circle(m, 6.0, Palette.WINDOW_DARK)
			draw_string(_font_bold, m + Vector2(-2.5, 5.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.FLOWER_YELLOW)
	if school_day != null:
		for p in school_day.pupils:
			if p.visible:
				draw_circle(_w2m(Vector2(p.global_position.x, p.global_position.z)), r * 0.85, Palette.FLOWER_YELLOW.darkened(0.1))
	for a in villagers.animals:
		if a.visible and a.role == "buffalo":
			draw_circle(_w2m(Vector2(a.global_position.x, a.global_position.z)), r * 0.9, Palette.BUFFALO)


## Mục tiêu việc đang làm: hình thoi vàng (ra ngoài khung thì ghim ở mép, chỉ hướng).
func _draw_quests() -> void:
	if quests == null:
		return
	for q in quests.active:
		var p := quests._target_pos(q)
		var m := _w2m(Vector2(p.x, p.z))
		var inner := Rect2(Vector2(8, 8), size - Vector2(16, 16))
		if not inner.has_point(m):
			var c := size * 0.5
			var d := m - c
			var k := minf((inner.size.x * 0.5) / maxf(absf(d.x), 0.001), (inner.size.y * 0.5) / maxf(absf(d.y), 0.001))
			m = c + d * k
		var s := 6.0
		draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s), m + Vector2(s, 0), m + Vector2(0, s), m + Vector2(-s, 0)]), Palette.FLOWER_YELLOW)
		draw_polyline(PackedVector2Array([m + Vector2(0, -s), m + Vector2(s, 0), m + Vector2(0, s), m + Vector2(-s, 0), m + Vector2(0, -s)]), Palette.WINDOW_DARK, 1.0)


func _draw_player(pl: Array) -> void:
	var m := _w2m(pl[0])
	var yaw: float = pl[1]
	# Hướng nhìn: trong Godot yaw = 0 nhìn về −z (lên trên bản đồ)
	var dir := Vector2(-sin(yaw), -cos(yaw))
	if pl[2]:
		# Mũi tên người chơi
		var side := Vector2(dir.y, -dir.x)
		var tri := PackedVector2Array([m + dir * 10.0, m - dir * 6.0 + side * 6.0, m - dir * 3.0, m - dir * 6.0 - side * 6.0])
		draw_colored_polygon(tri, Palette.FLAG_RED)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Palette.HUD_TEXT, 1.5)
	else:
		# Vùng camera ngắm cảnh đang nhìn: hình quạt nhạt + tâm
		var fan := PackedVector2Array([m])
		for i in 9:
			var a := lerpf(-0.45, 0.45, i / 8.0)
			fan.append(m + dir.rotated(a) * 28.0)
		draw_colored_polygon(fan, Color(Palette.HUD_TEXT, 0.25))
		draw_circle(m, 4.0, Palette.FLAG_RED)
		draw_arc(m, 4.0, 0, TAU, 12, Palette.HUD_TEXT, 1.2)


## Tên chỗ trên bản đồ lớn.
func _draw_labels() -> void:
	var labels: Array = []
	if village != null:
		labels.append([Vector2(village.dinh_spot.x, village.dinh_spot.z - 10.0), "Đình làng"])
		labels.append([village.pagoda_rect.get_center(), "Chùa"])
		labels.append([village.pond_center, "Ao làng"])
		# Giếng và cây đa đứng sát nhau: chữ giếng lệch trái-trên, chữ cây đa lệch phải-dưới
		labels.append([Vector2(village.well_position.x - 7.0, village.well_position.z - 6.0), "Giếng"])
		labels.append([Vector2(village.banyan_position.x + 9.0, village.banyan_position.z + 4.0), "Cây đa"])
		labels.append([village.pitch_rect.get_center(), "Sân bóng"])
		labels.append([village.gate_point() + Vector2(0, 6.0), "Cổng làng"])
	if school != null:
		labels.append([school.site.get_center(), "Trường học"])
	if house != null:
		labels.append([Vector2(house.house_position.x, house.house_position.z + 6.0), "Nhà mình"])
	if terrain != null:
		labels.append([terrain.field_rect.get_center(), "Ruộng"])
	if river != null:
		for l: Dictionary in river.landings:
			var s: Vector3 = l.spot
			labels.append([Vector2(s.x, s.z), "Bến"])
	for lb: Array in labels:
		var m := _w2m(lb[0])
		var text: String = lb[1]
		var w := _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(_font_bold, m + Vector2(-w * 0.5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(Palette.WINDOW_DARK, 0.85))
		draw_string(_font_bold, m + Vector2(-w * 0.5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.HUD_TEXT)
