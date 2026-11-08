class_name Farming
extends Node3D
## Mùa vụ lúa (mục 33). Mỗi vụ `cycle_days` ngày theo lịch trong game (mặc định 90 — khoảng 3 tháng), các
## thửa lệch nhau vài ngày cho đồng không đều tăm tắp. Ngày trong vụ = (ngày Julius + giờ / 24 − mốc
## `epoch_date`) mod `cycle_days` + độ lệch của thửa. Các giai đoạn (`STAGES`, ngày bắt đầu):
##   cày bừa 0 → cấy 5 → lúa non 11 → thì con gái 30 → trổ bông 55 → chín 65 → gặt 80 → ruộng nghỉ 87.
## - Ruộng nhà mình (3 thửa, `RiceField`): khóm lúa cấy dần theo luống, cao dần, xanh non → xanh đậm → vàng,
##   bông lúa mọc khi trổ, gặt dần thành gốc rạ (thấp, màu rơm), bó lúa nằm trên ruộng, nước ruộng (đục khi
##   cày bừa, trong khi cấy, rút dần trước khi trổ). Có cặp trâu kéo cày đi đi lại lại khi thửa đang cày.
## - Đồng ngoài làng (`Terrain.outer_fields`): mỗi ô ruộng một tấm phủ có luống (MultiMesh, màu theo giai
##   đoạn), nước ruộng, đống rơm sau gặt.
## - Trong làng: mùa gặt có sân phơi thóc vàng trước một số nhà, rơm chất đống.
## - Dân làng: nông dân ra đồng đông hơn mùa cấy / mùa gặt (`busy`), làm theo giai đoạn ở chỗ đứng
##   (`field_work`: cuốc đất / cấy / làm cỏ / gặt). HUD, hội thoại nói về vụ lúa (`stage_text`, `rice_talk`).

signal stage_changed(key: String)

@export var calendar: LunarCalendar
@export var day_night: DayNight
@export var weather: Weather
@export var terrain: Terrain
@export var rice_field: RiceField
@export var villagers: Villagers
@export var village: Village
## Số ngày một vụ (cày tới hết gặt + nghỉ).
@export var cycle_days: float = 90.0
## Ngày bắt đầu cày của một vụ làm mốc (dd/mm/yyyy).
@export var epoch_date: String = "24/08/2026"
## Độ lệch ngày của 3 thửa nhà mình.
@export var home_offsets: PackedFloat32Array = PackedFloat32Array([0.0, -1.5, -3.0])
## Ô ruộng ngoài đồng lệch ngẫu nhiên trong khoảng này (ngày).
@export var outer_offset_range: Vector2 = Vector2(-6.0, 2.0)
## Cập nhật hình mỗi bao nhiêu giây (chỉ vẽ lại khi trạng thái đổi đáng kể).
@export var update_interval: float = 0.5
@export var plow_speed: float = 0.7
@export var random_seed: int = 6262

const STAGES: Array = [
	["plow", 0.0, "cày bừa", "đang cày bừa, ngâm nước"],
	["transplant", 5.0, "cấy", "đang cấy"],
	["young", 11.0, "lúa non", "lúa đang lên xanh"],
	["maiden", 30.0, "thì con gái", "lúa đang thì con gái"],
	["heading", 55.0, "trổ bông", "lúa đang trổ bông"],
	["ripe", 65.0, "lúa chín", "lúa chín vàng"],
	["harvest", 80.0, "gặt", "đang gặt"],
	["fallow", 87.0, "ruộng nghỉ", "gặt xong, ruộng trơ gốc rạ"],
]
const C_YOUNG := Color("#b9dc78")
const C_MAIDEN := Color("#5f9a3a")
const C_GOLD := Color("#e0b850")
const C_STUBBLE := Color("#b59a5c")
const C_MUD := Color("#7a6044")

## Ngày mốc (số ngày Julius) — tính một lần.
var _epoch_jd: int = 0
var _day_shift: float = 0.0           # bài thử / công cụ chụp ảnh dời ngày trong vụ
var _outer: Array[Dictionary] = []    # {rect, offset}
var _outer_mm: MultiMesh
var _outer_water_mm: MultiMesh
var _stack_mm: MultiMesh
var _sheaf_mm: MultiMesh
var _yard_mm: MultiMesh
var _home_water: Array[MeshInstance3D] = []
var _yard_spots: Array[Transform3D] = []
var _sheaf_spots: Array[Dictionary] = []   # {xf, paddy, order}
var _home_sig: String = ""
var _outer_sig: String = ""
var _t: float = 0.0
var _plow: Node3D
var _plow_buffalo: Villager
var _plow_man: Villager
var _plow_t: float = 0.0
var _last_key: String = ""
var _rng := RandomNumberGenerator.new()
## Đếm lúc vẽ (renderer headless không giữ transform MultiMesh nên bài thử đọc ở đây).
var counts: Dictionary = {}


func _ready() -> void:
	_rng.seed = random_seed
	var d := epoch_date.split("/")
	_epoch_jd = LunarCalendar.jd_from_date(int(d[0]), int(d[1]), int(d[2]))
	_build_home()
	_build_outer()
	_build_yards()
	_build_plow_team()
	refresh(true)


# --- Thời gian vụ ---------------------------------------------------------------------------------

## Ngày trong vụ (0 … cycle_days) cho một thửa lệch `offset` ngày.
func day_in_cycle(offset: float = 0.0) -> float:
	if _epoch_jd == 0:          # Villagers hỏi khi dựng làng, trước _ready của Farming
		var dd := epoch_date.split("/")
		_epoch_jd = LunarCalendar.jd_from_date(int(dd[0]), int(dd[1]), int(dd[2]))
	var jd := calendar.jd if calendar != null else _epoch_jd
	var h := day_night.time_of_day if day_night != null else 12.0
	return fposmod(float(jd - _epoch_jd) + h / 24.0 + offset + _day_shift, cycle_days)


## Đặt ngày trong vụ của thửa nhà mình đầu tiên (bài thử, chụp ảnh).
func set_cycle_day(d: float) -> void:
	_day_shift = 0.0
	_day_shift = d - day_in_cycle(home_offsets[0] if home_offsets.size() > 0 else 0.0)
	refresh(true)


static func stage_of(d: float) -> Array:
	var cur: Array = STAGES[0]
	for st: Array in STAGES:
		if d >= float(st[1]):
			cur = st
	return cur


## Trạng thái hình của một thửa ở ngày `d`: nước, bùn, đã cấy, cao, chín, bông, đã gặt.
static func state_of(d: float) -> Dictionary:
	var s := {"water": 0.0, "mud": 0.0, "planted": 1.0, "height": 1.0, "ripe": 0.0, "ears": 0.0,
			"harvested": 0.0, "green": 1.0, "key": String(stage_of(d)[0])}
	if d < 5.0:                              # cày bừa: ruộng ngập nước đục, chưa có lúa
		s.water = 1.0
		s.mud = 1.0 - smoothstep(3.5, 5.0, d) * 0.6
		s.planted = 0.0
	elif d < 11.0:                           # cấy dần
		s.water = 1.0
		s.mud = 0.4 * (1.0 - smoothstep(5.0, 8.0, d))
		s.planted = clampf((d - 5.0) / 5.5, 0.0, 1.0)
		s.height = 0.3
		s.green = 0.0
	elif d < 30.0:                           # lúa non lên xanh
		s.water = 1.0
		s.height = lerpf(0.32, 0.7, (d - 11.0) / 19.0)
		s.green = (d - 11.0) / 19.0 * 0.5
	elif d < 55.0:                           # thì con gái, nước rút dần
		s.water = 1.0 - smoothstep(44.0, 54.0, d)
		s.height = lerpf(0.7, 0.95, (d - 30.0) / 25.0)
		s.green = lerpf(0.5, 1.0, (d - 30.0) / 25.0)
	elif d < 65.0:                           # trổ bông
		s.height = 1.0
		s.ears = smoothstep(55.0, 61.0, d)
		s.ripe = 0.1 * smoothstep(58.0, 65.0, d)
	elif d < 80.0:                           # chín dần
		s.height = 1.0
		s.ears = 1.0
		s.ripe = lerpf(0.1, 1.0, smoothstep(65.0, 77.0, d))
	elif d < 87.0:                           # gặt dần
		s.height = 1.0
		s.ears = 1.0
		s.ripe = 1.0
		s.harvested = clampf((d - 80.0) / 6.0, 0.0, 1.0)
	else:                                    # gặt xong, gốc rạ
		s.ripe = 1.0
		s.harvested = 1.0
	return s


## Màu thân lúa theo trạng thái.
static func crop_color(s: Dictionary) -> Color:
	var g := C_YOUNG.lerp(C_MAIDEN, float(s.green))
	return g.lerp(C_GOLD, float(s.ripe))


func _home_state(i: int) -> Dictionary:
	return state_of(day_in_cycle(home_offsets[i % home_offsets.size()] if home_offsets.size() > 0 else 0.0))


## Giai đoạn chung của cánh đồng (theo thửa nhà mình đầu tiên).
func stage_key() -> String:
	return String(stage_of(day_in_cycle(home_offsets[0] if home_offsets.size() > 0 else 0.0))[0])


func stage_text() -> String:
	var d := day_in_cycle(home_offsets[0] if home_offsets.size() > 0 else 0.0)
	var st := stage_of(d)
	return "Đồng: %s (ngày %d/%d của vụ)" % [String(st[3]), int(d) + 1, int(cycle_days)]


# --- Dựng ----------------------------------------------------------------------------------------

func _water_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.15
	m.metallic_specular = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _quad_mesh(stripes: int) -> ArrayMesh:
	# Tấm vuông 1 × 1 nằm ngang, chia dải luống: dải lúa (trắng) xen rãnh (xám) — màu instance nhân vào
	var mb := MeshBuilder.new(random_seed, 0.0)
	for k in stripes:
		var x0 := -0.5 + float(k) / stripes
		var x1 := -0.5 + float(k + 1) / stripes
		var xm := lerpf(x0, x1, 0.75)
		mb.add_quad(Vector3(x0, 0, -0.5), Vector3(xm, 0, -0.5), Vector3(xm, 0, 0.5), Vector3(x0, 0, 0.5), Color.WHITE, Vector3(0, -1, 0))
		if stripes > 1:
			mb.add_quad(Vector3(xm, 0, -0.5), Vector3(x1, 0, -0.5), Vector3(x1, 0, 0.5), Vector3(xm, 0, 0.5), Color(0.78, 0.78, 0.78), Vector3(0, -1, 0))
	return mb.commit()


func _build_home() -> void:
	if terrain == null:
		return
	var rects := terrain.paddy_rects()
	for i in rects.size():
		var r := rects[i].grow(-0.25)
		var mi := MeshInstance3D.new()
		mi.name = "PaddyWater%d" % i
		var pm := PlaneMesh.new()
		pm.size = r.size
		mi.mesh = pm
		var mat := _water_material()
		mat.vertex_color_use_as_albedo = false
		mi.material_override = mat
		mi.position = Vector3(r.get_center().x, 0.09, r.get_center().y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_home_water.append(mi)
		# Chỗ đặt bó lúa trên thửa (hiện dần theo gặt)
		for k in 14:
			var p := Vector3(_rng.randf_range(r.position.x + 0.6, r.end.x - 0.6), 0.05, _rng.randf_range(r.position.y + 0.6, r.end.y - 0.6))
			var fx := (p.x - rects[i].position.x) / rects[i].size.x
			var fz := (p.z - rects[i].position.y) / rects[i].size.y
			_sheaf_spots.append({"xf": Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p), "paddy": i,
					"order": clampf(floorf(fx * 12.0) / 12.0 + fz / 12.0, 0.0, 1.0)})
	_sheaf_mm = _multimesh(_sheaf_mesh(), _sheaf_spots.size(), "Sheaves", MeshBuilder.material())


func _build_outer() -> void:
	if terrain == null:
		return
	for fr in terrain.outer_fields:
		var nx := maxi(1, roundi(fr.size.x / terrain.outer_paddy_size.x))
		var nz := maxi(1, roundi(fr.size.y / terrain.outer_paddy_size.y))
		var pw := fr.size.x / nx
		var pd := fr.size.y / nz
		for ix in nx:
			for iz in nz:
				var r := Rect2(fr.position.x + ix * pw, fr.position.y + iz * pd, pw, pd).grow(-0.35)
				_outer.append({"rect": r, "offset": _rng.randf_range(outer_offset_range.x, outer_offset_range.y),
						"stack": Vector3(_rng.randf_range(r.position.x + 1.5, r.end.x - 1.5), 0.03, _rng.randf_range(r.position.y + 1.5, r.end.y - 1.5))})
	var mat := MeshBuilder.material()
	_outer_mm = _multimesh(_quad_mesh(13), _outer.size(), "OuterCrop", mat)
	_outer_water_mm = _multimesh(_quad_mesh(1), _outer.size(), "OuterWater", _water_material())
	_stack_mm = _multimesh(_stack_mesh(), _outer.size(), "StrawStacks", MeshBuilder.material())


func _build_yards() -> void:
	# Sân phơi thóc trước một nửa số nhà trong làng (và sân nhà mình)
	if village != null:
		for i in village.homes.size():
			if i % 2 == 0:
				var h: Dictionary = village.homes[i]
				var fwd: Vector3 = h.forward
				var p: Vector3 = (h.door as Vector3) + fwd * 3.2
				_yard_spots.append(Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), Vector3(p.x, 0.04, p.z)))
	_yard_spots.append(Transform3D(Basis.IDENTITY, Vector3(-9.0, 0.06, -3.5)))
	_yard_mm = _multimesh(_yard_mesh(), _yard_spots.size(), "DryingGrain", MeshBuilder.material())


func _multimesh(mesh: Mesh, n: int, name_: String, mat: Material) -> MultiMesh:
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	m.mesh = mesh
	m.instance_count = n
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in n:
		m.set_instance_transform(i, zero)
		m.set_instance_color(i, Color.WHITE)
	var mi := MultiMeshInstance3D.new()
	mi.name = name_
	mi.multimesh = m
	mi.material_override = mat
	add_child(mi)
	return m


func _stack_mesh() -> ArrayMesh:
	# Đống rơm: thân trụ phình + chóp, cọc tre giữa
	var mb := MeshBuilder.new(random_seed + 3, 0.05)
	mb.add_prism(0.9, 1.0, 0.9, 9, Palette.STRAW)
	mb.add_prism(1.0, 0.0, 1.3, 9, Palette.STRAW.darkened(0.08), _xf(0, 0.9, 0))
	mb.add_limb(Vector3(0, 2.0, 0), Vector3(0, 2.6, 0), 0.04, 0.03, 4, Palette.BAMBOO_STEM)
	return mb.commit()


func _sheaf_mesh() -> ArrayMesh:
	# Bó lúa nằm: bó rơm buộc giữa, đầu bông vàng
	var mb := MeshBuilder.new(random_seed + 4, 0.05)
	var lying := Basis(Vector3.BACK, PI * 0.5)
	mb.add_prism(0.09, 0.07, 0.55, 6, Palette.STRAW, Transform3D(lying, Vector3(0.28, 0.08, 0)))
	mb.add_prism(0.1, 0.1, 0.05, 6, Palette.WOOD, Transform3D(lying, Vector3(0.05, 0.08, 0)))
	mb.add_ellipsoid(Vector3(0.12, 0.08, 0.11), C_GOLD, _xf(-0.33, 0.02, 0), 7, 3, false)
	return mb.commit()


func _yard_mesh() -> ArrayMesh:
	# Sân phơi: lớp thóc vàng trải mỏng + vài đụn thóc, cào gỗ
	var mb := MeshBuilder.new(random_seed + 5, 0.04)
	mb.add_box(Vector3(2.6, 0.03, 1.8), C_GOLD)
	for k in 3:
		mb.add_prism(0.32, 0.0, 0.22, 7, C_GOLD.darkened(0.05), _xf(-0.8 + k * 0.8, 0.02, 0.35 * (k % 2)))
	mb.add_limb(Vector3(1.0, 0.04, -0.7), Vector3(1.7, 0.04, 0.2), 0.02, 0.02, 4, Palette.WOOD_LIGHT)
	return mb.commit()


static func _xf(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## Cặp trâu kéo cày + người cầm cày (hiện khi thửa nhà mình đang cày, ban ngày).
func _build_plow_team() -> void:
	_plow = Node3D.new()
	_plow.name = "PlowTeam"
	add_child(_plow)
	_plow_buffalo = Villager.new()
	_plow_buffalo.role = "buffalo"
	_plow_buffalo.display_name = "Trâu cày"
	_plow_buffalo.home = {"name": "", "key": ""}
	_plow.add_child(_plow_buffalo)
	_plow_buffalo.build_animal("buffalo")
	_plow_man = Villager.new()
	_plow_man.role = "farmer"
	_plow_man.display_name = "Bác Cày"
	_plow_man.home = {"name": "", "key": ""}
	_plow.add_child(_plow_man)
	var look: Dictionary = villagers._look("farmer", false) if villagers != null else {}
	look["prop"] = "none"
	look["hat"] = "non"
	_plow_man.build_person(look)
	_plow_man.work_anim = "plow"
	# Cái cày gỗ: bắp cày cong, lưỡi cày, ách trên vai trâu nối bằng dây thừng
	var mb := MeshBuilder.new(random_seed + 6, 0.03)
	mb.add_limb(Vector3(0, 0.75, -0.2), Vector3(0, 0.1, 0.5), 0.035, 0.03, 5, Palette.WOOD)
	mb.add_limb(Vector3(0, 0.1, 0.5), Vector3(0, 0.05, 1.0), 0.04, 0.03, 5, Palette.WOOD)
	mb.add_pyramid(0.08, 0.25, 4, Palette.ROCK_DARK, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.04, 1.0)))
	mb.add_limb(Vector3(-0.18, 0.75, -0.2), Vector3(0.18, 0.75, -0.2), 0.02, 0.02, 4, Palette.WOOD)
	mb.add_limb(Vector3(0, 0.1, 1.0), Vector3(0, 0.9, 2.3), 0.012, 0.012, 3, Palette.STRAW.darkened(0.3))
	var plow_mesh := mb.commit_instance("Plow")
	_plow.add_child(plow_mesh)
	_plow.visible = false


# --- Cập nhật -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = update_interval
		refresh(false)
	_step_plow(delta)


## Vẽ lại theo ngày hiện tại (chỉ khi đổi đáng kể, trừ khi `force`).
func refresh(force: bool) -> void:
	var key := stage_key()
	if key != _last_key:
		_last_key = key
		stage_changed.emit(key)
	_update_home(force)
	_update_outer(force)


func _sig(s: Dictionary) -> String:
	return "%d%d%d%d%d%d%d" % [int(float(s.water) * 20), int(float(s.mud) * 20), int(float(s.planted) * 60),
			int(float(s.height) * 30), int(float(s.ripe) * 30), int(float(s.ears) * 20), int(float(s.harvested) * 60)]


func _update_home(force: bool) -> void:
	if rice_field == null or rice_field.mm == null:
		return
	var states: Array[Dictionary] = []
	var sig := ""
	for i in rice_field.paddy_count:
		var st := _home_state(i)
		states.append(st)
		sig += _sig(st) + "|"
	if sig == _home_sig and not force:
		return
	_home_sig = sig
	var mm := rice_field.mm
	var ears := rice_field.ears_mm
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	var ch := rice_field.clump_height
	var n_shown := 0
	var n_stub := 0
	var n_ears := 0
	for i in rice_field.base_xforms.size():
		var st: Dictionary = states[rice_field.paddy_of[i]]
		var ord := rice_field.order01[i]
		var bx := rice_field.base_xforms[i]
		var k := rice_field.base_colors[i].v / maxf(Palette.RICE_2.v, 0.01)   # giữ lệch màu từng khóm
		if ord >= float(st.planted):
			mm.set_instance_transform(i, zero)
			ears.set_instance_transform(i, zero)
			continue
		n_shown += 1
		if ord < float(st.harvested):
			n_stub += 1
			# Gốc rạ: khóm cắt thấp, màu rơm
			mm.set_instance_transform(i, Transform3D(bx.basis.scaled(Vector3(1.0, 0.16, 1.0)), bx.origin))
			mm.set_instance_color(i, C_STUBBLE * clampf(k, 0.85, 1.15))
			ears.set_instance_transform(i, zero)
			continue
		var h := float(st.height)
		mm.set_instance_transform(i, Transform3D(bx.basis.scaled(Vector3(lerpf(0.7, 1.0, h), h, lerpf(0.7, 1.0, h))), bx.origin))
		var col := crop_color(st)
		mm.set_instance_color(i, Color(col.r * k, col.g * k, col.b * k).clamp())
		var e := float(st.ears)
		if e > 0.01:
			n_ears += 1
			var top := bx.origin + Vector3(0, ch * h * bx.basis.get_scale().y * 0.95, 0)
			mm_set_ear(ears, i, Transform3D(Basis(Vector3.UP, float(i) * 1.7).scaled(Vector3.ONE * e), top),
					C_YOUNG.lerp(C_GOLD, clampf(float(st.ripe) * 1.2, 0.0, 1.0)))
		else:
			ears.set_instance_transform(i, zero)
	counts.home_shown = n_shown
	counts.home_stubble = n_stub
	counts.home_ears = n_ears
	# Nước ruộng nhà mình
	for i in _home_water.size():
		var st: Dictionary = states[mini(i, states.size() - 1)]
		var w := float(st.water)
		var mat := _home_water[i].material_override as StandardMaterial3D
		_home_water[i].visible = w > 0.02
		mat.albedo_color = Color(Palette.WATER.lerp(C_MUD, float(st.mud) * 0.85), 0.55 * w + 0.2 * float(st.mud) * w)
	# Bó lúa nằm trên thửa đã gặt (trước khi gánh về): hiện sau khi gặt tới chỗ đó, gánh hết khi ruộng nghỉ
	counts.sheaves = 0
	for j in _sheaf_spots.size():
		var sp: Dictionary = _sheaf_spots[j]
		var st: Dictionary = states[mini(int(sp.paddy), states.size() - 1)]
		var d := day_in_cycle(home_offsets[int(sp.paddy) % home_offsets.size()])
		var show := float(sp.order) < float(st.harvested) and d < 88.5
		_sheaf_mm.set_instance_transform(j, sp.xf if show else zero)
		counts.sheaves = int(counts.sheaves) + int(show)


func mm_set_ear(m: MultiMesh, i: int, xf: Transform3D, col: Color) -> void:
	m.set_instance_transform(i, xf)
	m.set_instance_color(i, col)


func _update_outer(force: bool) -> void:
	if _outer_mm == null:
		return
	var sig := ""
	var states: Array[Dictionary] = []
	for o in _outer:
		var st := state_of(day_in_cycle(float(o.offset)))
		states.append(st)
		sig += _sig(st)
	if sig == _outer_sig and not force:
		return
	_outer_sig = sig
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	var yard_on := 0.0
	counts.outer_water = 0
	counts.stacks = 0
	for i in _outer.size():
		var o: Dictionary = _outer[i]
		var st: Dictionary = states[i]
		var r: Rect2 = o.rect
		var xf := Transform3D(Basis().scaled(Vector3(r.size.x, 1.0, r.size.y)), Vector3(r.get_center().x, 0.045, r.get_center().y))
		# Màu tấm phủ: bùn → mạ lấm tấm trên nước → xanh → vàng → gốc rạ
		var crop := crop_color(st)
		var planted := float(st.planted)
		var col := C_MUD.lerp(crop, planted * (0.35 + 0.65 * smoothstep(0.0, 1.0, float(st.height))))
		col = col.lerp(C_STUBBLE, float(st.harvested))
		_outer_mm.set_instance_transform(i, xf)
		_outer_mm.set_instance_color(i, col)
		var w := float(st.water)
		if w > 0.02:
			var wxf := Transform3D(Basis().scaled(Vector3(r.size.x, 1.0, r.size.y)), Vector3(r.get_center().x, 0.075, r.get_center().y))
			_outer_water_mm.set_instance_transform(i, wxf)
			counts.outer_water = int(counts.outer_water) + 1
			var cover := 1.0 - 0.7 * planted * float(st.height)   # lúa lên cao thì nước khuất dần
			_outer_water_mm.set_instance_color(i, Color(Palette.WATER.lerp(C_MUD, float(st.mud) * 0.8), (0.55 + 0.25 * float(st.mud)) * w * cover))
		else:
			_outer_water_mm.set_instance_transform(i, zero)
		# Đống rơm: chất dần khi gặt, còn tới hết ruộng nghỉ
		var hv := float(st.harvested)
		if hv > 0.3:
			var sc := lerpf(0.4, 1.0, (hv - 0.3) / 0.7)
			_stack_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), o.stack))
			counts.stacks = int(counts.stacks) + 1
		else:
			_stack_mm.set_instance_transform(i, zero)
		yard_on += hv * (1.0 if float(st.ripe) > 0.9 else 0.0)
	# Sân phơi thóc trong làng: từ khi gặt tới giữa kỳ ruộng nghỉ
	var dh := day_in_cycle(home_offsets[0] if home_offsets.size() > 0 else 0.0)
	var drying := dh >= 81.0 and dh < 89.5
	counts.yards = 0
	for j in _yard_spots.size():
		counts.yards = int(counts.yards) + int(drying and (j % 3 != 2 or dh > 83.0))
		_yard_mm.set_instance_transform(j, _yard_spots[j] if drying and (j % 3 != 2 or dh > 83.0) else zero)


# --- Trâu kéo cày ----------------------------------------------------------------------------------

func _step_plow(delta: float) -> void:
	if terrain == null or rice_field == null:
		return
	var h := day_night.time_of_day if day_night != null else 12.0
	var bad := weather != null and weather.kind in ["storm", "drizzle"]
	var idx := -1
	for i in rice_field.paddy_count:
		if String(_home_state(i).key) == "plow":
			idx = i
			break
	var on := idx >= 0 and h >= 6.0 and h < 17.5 and not bad
	_plow.visible = on
	if not on:
		return
	_plow_t += delta * plow_speed
	# Đi luống đi luống về theo chiều dọc thửa (dọc z), mỗi luống cách 1,2 m
	var r := terrain.paddy_rects()[idx].grow(-1.2)
	var len_ := r.size.y
	var lanes := maxi(1, int(r.size.x / 1.2))
	var total := len_ * lanes
	var s := fposmod(_plow_t, total)
	var lane := int(s / len_)
	var along := fmod(s, len_)
	var forward := lane % 2 == 0
	var z := r.position.y + (along if forward else len_ - along)
	var x := r.position.x + (lane + 0.5) * r.size.x / lanes
	var dir := Vector3(0, 0, 1.0 if forward else -1.0)
	var buf := Vector3(x, 0.02, z)
	_plow_buffalo.global_position = buf
	_plow_buffalo.rotation.y = atan2(dir.x, dir.z)
	_plow_man.global_position = buf - dir * 2.6
	_plow_man.rotation.y = _plow_buffalo.rotation.y
	var plow_mesh := _plow.get_node("Plow") as Node3D
	plow_mesh.global_position = buf - dir * 2.3
	plow_mesh.rotation.y = _plow_buffalo.rotation.y
	for v in [_plow_buffalo, _plow_man]:
		v._walk_amount = 0.55
		v.speed_mul = 0.6
		v._animate(delta)


# --- Cho dân làng / hội thoại -----------------------------------------------------------------------

## Mức bận việc đồng (nhân vào trọng số ra đồng): mùa cấy, mùa gặt đông người.
func busy() -> float:
	match stage_key():
		"transplant", "harvest": return 2.2
		"plow": return 1.4
		"ripe": return 0.8
		"fallow": return 0.6
	return 0.9


## Việc làm ở chỗ đứng `p` ngoài đồng: {anim, text, prop} theo giai đoạn của ô ruộng gần nhất.
func field_work(p: Vector3) -> Dictionary:
	var d := day_in_cycle(home_offsets[0] if home_offsets.size() > 0 else 0.0)
	var best := INF
	for o in _outer:
		var r: Rect2 = o.rect
		var dist := r.get_center().distance_to(Vector2(p.x, p.z))
		if dist < best:
			best = dist
			d = day_in_cycle(float(o.offset))
	match String(stage_of(d)[0]):
		"plow": return {"anim": "hoe", "text": "đang cuốc góc ruộng, đắp bờ giữ nước", "prop": true}
		"transplant": return {"anim": "plant", "text": "đang cấy lúa ngoài đồng", "prop": false}
		"young", "maiden": return {"anim": "plant", "text": "đang làm cỏ, bón phân cho lúa", "prop": false}
		"heading": return {"anim": "hoe", "text": "đang ra thăm lúa trổ bông", "prop": true}
		"ripe": return {"anim": "idle", "text": "đang ra đồng xem lúa chín", "prop": true}
		"harvest": return {"anim": "reap", "text": "đang gặt lúa", "prop": false}
	return {"anim": "hoe", "text": "đang cày vỡ gốc rạ, chuẩn bị vụ sau", "prop": true}


## Lời nông dân nói về vụ lúa (câu "Lúa năm nay thế nào?").
func rice_talk() -> String:
	var d := day_in_cycle(home_offsets[0] if home_offsets.size() > 0 else 0.0)
	var left := int(80.0 - d)
	match String(stage_of(d)[0]):
		"plow": return "Đang cày bừa ngâm ruộng đấy {you} ạ. Vài hôm nữa nước ngấu là xuống mạ cấy."
		"transplant": return "Đang mùa cấy, cả làng ra đồng. Cấy thẳng hàng thì lúa mới đều, {you} ạ."
		"young": return "Lúa mới bén rễ, đang lên xanh. Phải giữ nước cho đủ, làm cỏ cho sạch."
		"maiden": return "Lúa đang thì con gái, đẹp lắm. Độ %d hôm nữa là trổ bông." % maxi(int(55.0 - d), 1)
		"heading": return "Lúa trổ đều rồi, chỉ mong trời đừng mưa to lúc này kẻo lép hạt."
		"ripe": return "Lúa ngả vàng rồi, chừng %d hôm nữa là gặt. Năm nay chắc được mùa." % maxi(left, 1)
		"harvest": return "Đang gặt hái đây, bận tối mắt. Gặt về còn phơi thóc, đánh đống rơm nữa."
	return "Gặt xong rồi, thóc phơi khô cất bồ cả. Nghỉ ít hôm lại cày vụ mới."
