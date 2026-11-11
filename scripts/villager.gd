class_name Villager
extends Node3D
## Một NPC: người (nông dân, người gánh hàng, cụ già, trẻ con, người chăn trâu) hoặc con vật
## (trâu, chó, gà, vịt). Tự dựng hình low-poly có khớp tay/chân để làm dáng đi, dáng làm việc.
## Việc đi đâu do `Villagers` quyết định; Villager chỉ đi theo `path` và diễn hoạt.
## Mặt trước hướng +z cục bộ.

enum State { IDLE, WALK, INSIDE }

const CLICK_LAYER := 3            # lớp va chạm để bấm chọn NPC

# --- Thông tin (hiện khi bấm chọn) ---
## Mục 46: người xa camera hơn LOD_DISTANCE vẽ bằng hình đơn giản, xa hơn FAR_DISTANCE thì không vẽ.
const LOD_DISTANCE := 75.0
const LOD_MARGIN := 4.0
const FAR_DISTANCE := 170.0
var _lod: MeshInstance3D
var _shadow_parts: Array[MeshInstance3D] = []
var _shadows_on: bool = true
var display_name: String = ""
var role: String = "farmer"       # farmer, carrier, elder, kid, herder, buffalo, dog, chicken, duck
var role_name: String = ""
var home: Dictionary = {}         # {door, forward, gate, name, key}
var activity: String = ""         # khoá hoạt động hiện tại
var activity_text: String = ""

# --- Di chuyển ---
var state: State = State.IDLE
var path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
var speed: float = 1.4
var speed_mul: float = 1.0
var side_offset: float = 0.0      # lệch sang một bên đường để không giẫm lên nhau
var dwell: float = 0.0            # thời gian (giây thật) còn ở lại chỗ hiện tại
var work_anim: String = "idle"    # idle, hoe, chat, play, peck, graze, sit
var follow_target: Villager       # trâu/chó đi theo chủ
var follow_distance: float = 2.5
var terrain: Terrain

# --- Hình ---
var body: Node3D                  # nhấp nhô khi đi
var legs: Array[Node3D] = []       # khớp hông (người) / chân (con vật)
var _click_body: StaticBody3D
var arms: Array[Node3D] = []       # khớp vai
var knees: Array[Node3D] = []      # khớp gối (người) — co khi bước, gập khi ngồi
var elbows: Array[Node3D] = []     # khớp khuỷu tay
var lantern: Node3D
var ring: MeshInstance3D
var _phase: float = 0.0
var _walk_amount: float = 0.0
var _work_time: float = 0.0
var _trail: Array[Vector3] = []   # vệt đường đã đi (cho con vật đi theo)
var _holds_pole: bool = false
var prop_node: Node3D             # đồ cầm tay (cuốc…) — ẩn đi khi ra sân đá bóng
var _outfits: Dictionary = {}     # tên bộ đồ → {body, legs, arms}: casual, uniform, shirtless
var outfit: String = "casual"
var in_uniform: bool = false
var _look: Dictionary = {}
var _walk_start: Vector3 = Vector3.ZERO   # điểm bắt đầu đoạn đường đầu tiên (lấy độ cao)
var _path_y: float = 0.05                 # độ cao nội suy theo đường (leo đê, lên cầu ván)

static var _mesh_cache: Dictionary = {}


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## Lấy mesh từ bộ nhớ đệm theo khoá, dựng mới nếu chưa có (nhiều NPC dùng chung mesh).
static func _cached(key: String, builder: Callable) -> ArrayMesh:
	if not _mesh_cache.has(key):
		var mb := MeshBuilder.new(key.hash(), 0.03)
		builder.call(mb)
		_mesh_cache[key] = mb.commit()
	return _mesh_cache[key]


func _part(parent: Node3D, mesh: ArrayMesh, pos: Vector3, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	# Người: các mảnh có khớp chỉ vẽ tới LOD_DISTANCE, xa hơn thay bằng MỘT hình đơn giản (`_build_lod`, mục 46)
	if role in ["chicken", "duck"]:
		mi.visibility_range_end = 70.0
	elif role in ["buffalo", "dog"]:
		mi.visibility_range_end = FAR_DISTANCE
	else:
		mi.visibility_range_end = LOD_DISTANCE
		mi.visibility_range_end_margin = LOD_MARGIN
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_shadow_parts.append(mi)
	parent.add_child(mi)
	return mi


## Bật / tắt đổ bóng của cả người (Villagers tắt bóng người ở xa — mỗi mảnh đổ bóng là thêm draw call cho từng tầng bóng).
func set_shadows(on: bool) -> void:
	if on == _shadows_on:
		return
	_shadows_on = on
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in _shadow_parts:
		mi.cast_shadow = mode


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# --- Dựng người ------------------------------------------------------------------------

## look: {shirt, pants, skin, hat ("non"|"khan"|"none"), scale, female, prop ("hoe"|"pole"|"stick"|"none")}
func build_person(look: Dictionary) -> void:
	_look = look
	_build_person_rig(look)
	_outfits["casual"] = _snapshot()
	_outfits["casual"]["look"] = look
	_build_lod(look)
	_add_click_body(Vector3(0.7, 1.75 * float(look.get("scale", 1.0)), 0.7))


## Bộ đồ thứ hai (đồng phục học sinh): dựng thêm một bộ khung hình riêng, ẩn đi; `set_outfit`
## đổi qua lại. Áo sơ mi trắng, quần xanh sẫm, khăn quàng đỏ thắt ở cổ.
func add_uniform(look: Dictionary) -> void:
	var u := look.duplicate()
	u.shirt = Palette.SCHOOL_TRIM
	u.pants = Palette.SIGN_BLUE.darkened(0.45)
	u.hat = "none" if look.get("hat", "none") == "non" else look.get("hat", "none")
	u.scarf = true
	_add_outfit("uniform", u)


## Bộ cởi trần (đội cởi trần khi đá bóng, mục 17): thân và tay màu da, giữ quần và mũ nón.
## Chỉ dựng lần đầu cần đến để không tốn node cho người không bao giờ ra sân.
func add_shirtless() -> void:
	if _outfits.has("shirtless") or _look.is_empty():
		return
	var u := _look.duplicate()
	u.shirt = (u.get("skin", Palette.FARMER_SKIN) as Color).darkened(0.06)   # da rám nắng
	u.scarf = false
	u.prop = "none"     # cuốc đã dựng bên lề sân
	_add_outfit("shirtless", u)


func has_outfit(name_s: String) -> bool:
	return _outfits.has(name_s)


## Mặc bộ đồ `name_s` (casual | uniform | shirtless), các bộ khác ẩn đi.
func wear(name_s: String) -> void:
	if not _outfits.has(name_s):
		return
	for k: String in _outfits:
		(_outfits[k].body as Node3D).visible = k == name_s
	var o: Dictionary = _outfits[name_s]
	body = o.body
	legs.assign(o.legs)
	arms.assign(o.arms)
	knees.assign(o.get("knees", []))
	elbows.assign(o.get("elbows", []))
	outfit = name_s
	in_uniform = name_s == "uniform"
	if _lod != null and o.has("look"):
		_lod.mesh = _lod_mesh(o.look)


## true = mặc đồng phục, false = áo thường.
func set_outfit(uniform: bool) -> void:
	wear("uniform" if uniform else "casual")


## Dựng thêm một bộ khung hình (ẩn đi), giữ nguyên bộ đang mặc.
func _add_outfit(name_s: String, look: Dictionary) -> void:
	legs = []
	arms = []
	knees = []
	elbows = []
	_build_person_rig(look)
	_outfits[name_s] = _snapshot()
	_outfits[name_s]["look"] = look
	wear(outfit)


## Hình đơn giản khi ở xa (mục 46): một mesh ~60 tam giác (quần, áo, đầu, nón / tóc) thay cho ~12 mảnh có khớp
## (~2.100 tam giác). Chuyển đổi tự động theo khoảng cách tới camera bằng visibility range, không đổ bóng.
func _build_lod(look: Dictionary) -> void:
	_lod = MeshInstance3D.new()
	_lod.name = "Lod"
	_lod.mesh = _lod_mesh(look)
	_lod.visibility_range_begin = LOD_DISTANCE
	_lod.visibility_range_begin_margin = LOD_MARGIN
	_lod.visibility_range_end = FAR_DISTANCE
	_lod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lod)


static func _lod_mesh(look: Dictionary) -> ArrayMesh:
	var s: float = look.get("scale", 1.0)
	var shirt: Color = look.get("shirt", Palette.FARMER_SHIRT)
	var pants: Color = look.get("pants", Palette.FARMER_PANTS)
	var skin: Color = look.get("skin", Palette.FARMER_SKIN)
	var hat := str(look.get("hat", "none"))
	var key := "lod_%s_%s_%s_%s_%.2f" % [shirt.to_html(), pants.to_html(), skin.to_html(), hat, s]
	return _cached(key, func(mb: MeshBuilder) -> void:
		mb.add_prism(0.13 * s, 0.15 * s, 0.8 * s, 5, pants)
		mb.add_prism(0.17 * s, 0.19 * s, 0.6 * s, 5, shirt, _t(0, 0.8 * s, 0))
		mb.add_prism(0.11 * s, 0.1 * s, 0.24 * s, 5, skin, _t(0, 1.4 * s, 0))
		match hat:
			"non":
				mb.add_pyramid(0.32 * s, 0.2 * s, 6, Palette.HAT, _t(0, 1.58 * s, 0))
			"khan":
				mb.add_prism(0.12 * s, 0.11 * s, 0.1 * s, 5, Palette.WINDOW_DARK.lightened(0.25), _t(0, 1.58 * s, 0))
			_:
				mb.add_prism(0.115 * s, 0.09 * s, 0.07 * s, 5, Palette.WINDOW_DARK.lightened(0.05), _t(0, 1.62 * s, 0))
	)


func _snapshot() -> Dictionary:
	return {"body": body, "legs": legs.duplicate(), "arms": arms.duplicate(),
			"knees": knees.duplicate(), "elbows": elbows.duplicate()}


## Đầu người kiểu "low-poly mềm" (dùng chung cho dân làng, người câu cá, tượng nông dân):
## đầu bo tròn, tai, chỏm tóc (phụ nữ có búi), mắt, lông mày, má hồng. `xf`: đáy đầu, mặt hướng +z.
static func soft_head(mb: MeshBuilder, xf: Transform3D, s: float, skin: Color, female: bool, bald: bool = false) -> void:
	mb.add_ellipsoid(Vector3(0.112, 0.128, 0.118) * s, skin, xf, 12, 7)
	for ex: float in [-1.0, 1.0]:
		mb.add_ellipsoid(Vector3(0.018, 0.032, 0.026) * s, skin.darkened(0.06), xf * _t(ex * 0.11 * s, 0.1 * s, -0.005 * s), 6, 3)
	var hair := Palette.WINDOW_DARK.lightened(0.05)
	if not bald:
		mb.add_ellipsoid(Vector3(0.118, 0.095, 0.124) * s, hair, xf * _t(0, 0.135 * s, -0.012 * s), 12, 6)
	if female and not bald:
		mb.add_ellipsoid(Vector3(0.05, 0.045, 0.045) * s, hair, xf * _t(0, 0.1 * s, -0.12 * s), 8, 4)
	for ex: float in [-0.042, 0.042]:
		mb.add_ellipsoid(Vector3(0.014, 0.017, 0.008) * s, Palette.WINDOW_DARK, xf * _t(ex * s, 0.125 * s, 0.108 * s), 6, 3)
		mb.add_capsule(Vector3((ex - 0.018) * s, 0.168 * s, 0.103 * s), Vector3((ex + 0.018) * s, 0.168 * s, 0.103 * s),
				0.006 * s, 0.006 * s, 4, hair, xf)
		mb.add_ellipsoid(Vector3(0.022, 0.012, 0.006) * s, skin.lerp(Palette.LOTUS, 0.35), xf * _t(ex * 1.45 * s, 0.085 * s, 0.1 * s), 6, 3)


func _build_person_rig(look: Dictionary) -> void:
	# "Low-poly mềm": tay chân là ống bo tròn hai đầu, thân và đầu bo tròn, bóng mượt;
	# có khớp gối, khớp khuỷu để dáng đi co duỗi tự nhiên.
	var s: float = look.get("scale", 1.0)
	var shirt: Color = look.shirt
	var pants: Color = look.pants
	var skin: Color = look.get("skin", Palette.FARMER_SKIN)
	var female: bool = look.get("female", false)
	var hip := 0.78 * s
	var thigh := hip * 0.5
	var shin := hip * 0.5
	body = _pivot(self, Vector3.ZERO)
	var hk := "%s_%s_%.2f" % [shirt.to_html(), pants.to_html(), s]
	# Chân: đùi (quần) → gối → ống chân (quần xắn, bắp chân trần) → bàn chân
	for side in [-1.0, 1.0]:
		var leg := _pivot(body, Vector3(side * 0.095 * s, hip, 0.0))
		_part(leg, _cached("thigh_" + hk, func(mb: MeshBuilder) -> void:
			mb.add_capsule(Vector3.ZERO, Vector3(0, -thigh, 0), 0.085 * s, 0.072 * s, 8, pants)
		), Vector3.ZERO)
		var knee := _pivot(leg, Vector3(0, -thigh, 0))
		_part(knee, _cached("shin_" + hk, func(mb: MeshBuilder) -> void:
			mb.add_capsule(Vector3.ZERO, Vector3(0, -shin * 0.3, 0), 0.072 * s, 0.068 * s, 8, pants)
			mb.add_capsule(Vector3(0, -shin * 0.25, 0), Vector3(0, -shin + 0.05 * s, 0), 0.055 * s, 0.042 * s, 8, skin)
			mb.add_ellipsoid(Vector3(0.048, 0.03, 0.085) * s, skin.darkened(0.12), _t(0, -shin, 0.035 * s), 8, 4)
		), Vector3.ZERO)
		legs.append(leg)
		knees.append(knee)
	# Thân + hông + cổ + đầu (+ lưng còng cho cụ già)
	var bend := 0.25 if role == "elder" else 0.0
	var bald: bool = look.get("bald", false)
	var hair_key := ("b" if bald else "") + ("f" if female else "m")
	_part(body, _cached("torso_soft_%s_%s_%.2f_%.2f_%s" % [shirt.to_html(), pants.to_html(), s, bend, hair_key], func(mb: MeshBuilder) -> void:
		var tilt := Transform3D(Basis(Vector3.RIGHT, bend), Vector3(0, hip, 0))
		# Hông (quần) và thân áo: ống dẹt, vai rộng hơn eo một chút
		mb.add_ellipsoid(Vector3(0.17, 0.11, 0.13) * s, pants, _t(0, hip - 0.1 * s, 0), 10, 5)
		mb.add_capsule(Vector3(0, 0.11 * s, 0), Vector3(0, 0.36 * s, 0), 0.175 * s, 0.19 * s, 10, shirt, tilt, true, Vector2(1.0, 0.78))
		# Vạt áo bà ba hơi xoè dưới eo
		mb.add_prism(0.18 * s, 0.185 * s, 0.1 * s, 10, shirt.darkened(0.05), tilt * Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.8)), Vector3(0, -0.02 * s, 0)))
		mb.add_capsule(Vector3(0, 0.5 * s, 0), Vector3(0, 0.6 * s, 0), 0.045 * s, 0.043 * s, 8, skin, tilt)
		soft_head(mb, tilt * _t(0, 0.58 * s, 0.005 * s), s, skin, female, bald)
	), Vector3.ZERO)
	var head_top := Vector3(0, hip + 0.86 * s * cos(bend), 0.86 * s * sin(bend))
	match str(look.get("hat", "none")):
		"non":
			_part(body, _cached("non_soft_%.2f" % s, func(mb: MeshBuilder) -> void:
				mb.add_prism(0.36 * s, 0.34 * s, 0.025, 16, Palette.HAT_DARK)
				mb.add_pyramid(0.36 * s, 0.28 * s, 16, Palette.HAT, _t(0, 0.025, 0))
			), head_top - Vector3(0, 0.07 * s, 0))
		"khan":
			_part(body, _cached("khan_soft_%.2f" % s, func(mb: MeshBuilder) -> void:
				# Khăn mỏ quạ: vành khăn ôm đầu + mỏ nhọn trước trán
				mb.add_ellipsoid(Vector3(0.13, 0.06, 0.135) * s, Palette.WINDOW_DARK, Transform3D.IDENTITY, 12, 4)
				mb.add_pyramid(0.07 * s, 0.09 * s, 4, Palette.WINDOW_DARK, Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.06 * s, 0.1 * s)))
			), head_top - Vector3(0, 0.09 * s, 0))
		"tuft":
			_part(body, _cached("tuft", func(mb: MeshBuilder) -> void:
				mb.add_ellipsoid(Vector3(0.04, 0.035, 0.04), Palette.WINDOW_DARK, Transform3D.IDENTITY, 8, 4)
			), head_top - Vector3(0, 0.02, 0))
	# Tay: bắp tay → khuỷu → cẳng tay (tay áo dài) → bàn tay
	var sh := hip + 0.5 * s
	var upper := 0.27 * s
	for side in [-1.0, 1.0]:
		var arm := _pivot(body, Vector3(side * 0.205 * s, sh - 0.02 * s, 0.5 * s * sin(bend) * 0.6))
		_part(arm, _cached("uarm_" + hk, func(mb: MeshBuilder) -> void:
			mb.add_capsule(Vector3.ZERO, Vector3(0, -upper, 0), 0.052 * s, 0.046 * s, 8, shirt)
		), Vector3.ZERO)
		var elbow := _pivot(arm, Vector3(0, -upper, 0))
		_part(elbow, _cached("farm_" + hk, func(mb: MeshBuilder) -> void:
			mb.add_capsule(Vector3.ZERO, Vector3(0, -0.21 * s, 0), 0.045 * s, 0.038 * s, 8, shirt)
			mb.add_ellipsoid(Vector3(0.036, 0.048, 0.03) * s, skin, _t(0, -0.3 * s, 0.005 * s), 8, 4)
		), Vector3.ZERO)
		arms.append(arm)
		elbows.append(elbow)
	# Đồ cầm theo
	match str(look.get("prop", "none")):
		"hoe":
			prop_node = _part(arms[1], _cached("hoe", func(mb: MeshBuilder) -> void:
				mb.add_limb(Vector3(0, -0.5, -0.5), Vector3(0, -0.55, 0.75), 0.022, 0.022, 4, Palette.WOOD)
				mb.add_box(Vector3(0.06, 0.2, 0.16), Palette.ROCK_DARK, _t(0, -0.7, -0.5))
			), Vector3.ZERO)
		"stick":
			_part(arms[1], _cached("stick", func(mb: MeshBuilder) -> void:
				mb.add_limb(Vector3(0, -0.5, 0.05), Vector3(0, -1.15, 0.2), 0.02, 0.018, 4, Palette.WOOD_LIGHT)
			), Vector3.ZERO)
		"pole":
			# Đòn gánh trên vai phải, hai thúng trước sau
			_part(body, _cached("pole", func(mb: MeshBuilder) -> void:
				mb.add_limb(Vector3(0.22, 0, -0.75), Vector3(0.22, 0, 0.75), 0.025, 0.025, 5, Palette.BAMBOO_STEM)
				for z in [-0.72, 0.72]:
					mb.add_box(Vector3(0.01, 0.5, 0.01), Palette.WOOD, _t(0.22, -0.5, z))
					mb.add_prism(0.2, 0.24, 0.24, 9, Palette.STRAW, _t(0.22, -0.78, z))
					mb.add_blob(Vector3(0.16, 0.08, 0.16), Palette.VEGETABLE, RandomNumberGenerator.new(), 0.2, _t(0.22, -0.56, z))
			), Vector3(0, sh + 0.02, 0))
			arms[1].rotation.x = -1.6
			_holds_pole = true
	# Khăn quàng đỏ: tam giác vắt quanh cổ, hai vạt thắt nút trước ngực
	if look.get("scarf", false):
		_part(body, _cached("scarf_%.2f" % s, func(mb: MeshBuilder) -> void:
			var y := hip + 0.53 * s
			mb.add_prism(0.17 * s, 0.13 * s, 0.07 * s, 8, Palette.FLAG_RED, _t(0, y - 0.01, 0))
			mb.add_blob(Vector3(0.035, 0.035, 0.03) * s, Palette.FLAG_RED.darkened(0.15), RandomNumberGenerator.new(), 0.05, _t(0, y - 0.03 * s, 0.15 * s))
			for side in [-1.0, 1.0]:
				var top := Vector3(side * 0.01, y - 0.02 * s, 0.16 * s)
				var tip := Vector3(side * 0.08 * s, y - 0.3 * s, 0.19 * s)
				mb.add_limb(top, tip, 0.045 * s, 0.01 * s, 3, Palette.FLAG_RED, Transform3D.IDENTITY)
			# Vạt sau lưng
			mb.add_pyramid(0.12 * s, 0.2 * s, 3, Palette.FLAG_RED, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, y + 0.02, -0.12 * s)))
		), Vector3.ZERO)


# --- Dựng con vật ----------------------------------------------------------------------

func build_animal(kind: String) -> void:
	body = _pivot(self, Vector3.ZERO)
	match kind:
		"buffalo":
			var leg_h := 0.62
			for p in [Vector2(0.28, 0.62), Vector2(-0.28, 0.62), Vector2(0.28, -0.62), Vector2(-0.28, -0.62)]:
				var v: Vector2 = p
				var leg := _pivot(body, Vector3(v.x, leg_h, v.y))
				_part(leg, _cached("buf_leg", func(mb: MeshBuilder) -> void:
					mb.add_limb(Vector3.ZERO, Vector3(0, -leg_h, 0), 0.12, 0.09, 5, Palette.BUFFALO_DARK)
				), Vector3.ZERO)
				legs.append(leg)
			_part(body, _cached("buf_body", func(mb: MeshBuilder) -> void:
				var rng := RandomNumberGenerator.new()
				rng.seed = 3
				mb.add_prism(0.5, 0.46, 1.8, 7, Palette.BUFFALO, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.98, -0.9)))
				mb.add_blob(Vector3(0.42, 0.28, 0.42), Palette.BUFFALO, rng, 0.1, _t(0, 0.98, 0.55))
				mb.add_limb(Vector3(0, 1.0, 0.75), Vector3(0, 0.75, 1.2), 0.28, 0.22, 6, Palette.BUFFALO)
				mb.add_box(Vector3(0.34, 0.36, 0.52), Palette.BUFFALO, _t(0, 0.5, 1.35))
				mb.add_box(Vector3(0.28, 0.16, 0.18), Palette.BUFFALO_DARK, _t(0, 0.52, 1.62))
				for side in [-1.0, 1.0]:
					var base := Vector3(side * 0.15, 0.88, 1.3)
					var mid := base + Vector3(side * 0.32, 0.12, -0.1)
					mb.add_limb(base, mid, 0.06, 0.045, 5, Palette.BUFFALO_HORN)
					mb.add_limb(mid, mid + Vector3(-side * 0.1, 0.18, -0.3), 0.045, 0.0, 5, Palette.BUFFALO_HORN)
				mb.add_limb(Vector3(0, 1.1, -1.05), Vector3(0, 0.45, -1.2), 0.035, 0.025, 4, Palette.BUFFALO_DARK)
			), Vector3.ZERO)
			_add_click_body(Vector3(0.9, 1.4, 2.6))
		"dog":
			var leg_h := 0.28
			for p in [Vector2(0.1, 0.22), Vector2(-0.1, 0.22), Vector2(0.1, -0.22), Vector2(-0.1, -0.22)]:
				var v: Vector2 = p
				var leg := _pivot(body, Vector3(v.x, leg_h, v.y))
				_part(leg, _cached("dog_leg", func(mb: MeshBuilder) -> void:
					mb.add_limb(Vector3.ZERO, Vector3(0, -leg_h, 0), 0.04, 0.035, 4, Palette.EARTH.darkened(0.2))
				), Vector3.ZERO)
				legs.append(leg)
			_part(body, _cached("dog_body", func(mb: MeshBuilder) -> void:
				var rng := RandomNumberGenerator.new()
				rng.seed = 5
				var c := Palette.EARTH.darkened(0.1)
				mb.add_blob(Vector3(0.14, 0.13, 0.3), c, rng, 0.08, _t(0, 0.25, 0))
				mb.add_blob(Vector3(0.1, 0.1, 0.12), c, rng, 0.06, _t(0, 0.4, 0.32))
				mb.add_box(Vector3(0.08, 0.07, 0.12), c.darkened(0.2), _t(0, 0.45, 0.44))
				for side in [-1.0, 1.0]:
					mb.add_pyramid(0.04, 0.1, 3, c.darkened(0.25), _t(side * 0.06, 0.56, 0.3))
				mb.add_limb(Vector3(0, 0.42, -0.28), Vector3(0, 0.62, -0.42), 0.03, 0.01, 4, c)
			), Vector3.ZERO)
			_add_click_body(Vector3(0.4, 0.7, 0.8))
		"chicken":
			_part(body, _cached("chicken", func(mb: MeshBuilder) -> void:
				var rng := RandomNumberGenerator.new()
				rng.seed = 9
				mb.add_limb(Vector3(0.04, 0, 0), Vector3(0.04, 0.12, 0), 0.01, 0.01, 3, Palette.BEAK)
				mb.add_limb(Vector3(-0.04, 0, 0), Vector3(-0.04, 0.12, 0), 0.01, 0.01, 3, Palette.BEAK)
				mb.add_blob(Vector3(0.1, 0.09, 0.13), Palette.BANYAN_TRUNK.lightened(0.15), rng, 0.08, _t(0, 0.1, 0))
				mb.add_blob(Vector3(0.05, 0.06, 0.05), Palette.BANYAN_TRUNK.lightened(0.25), rng, 0.05, _t(0, 0.24, 0.1))
				mb.add_box(Vector3(0.015, 0.04, 0.05), Palette.HIBISCUS, _t(0, 0.35, 0.1))
				mb.add_pyramid(0.02, 0.05, 3, Palette.BEAK, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.29, 0.15)))
				mb.add_pyramid(0.06, 0.12, 4, Palette.WINDOW_DARK, Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0, 0.18, -0.1)))
			), Vector3.ZERO, false)
			_add_click_body(Vector3(0.3, 0.4, 0.35))
		"duck":
			_part(body, _cached("duck", func(mb: MeshBuilder) -> void:
				var rng := RandomNumberGenerator.new()
				rng.seed = 11
				mb.add_blob(Vector3(0.14, 0.09, 0.2), Palette.DUCK, rng, 0.08, _t(0, 0.0, 0))
				mb.add_blob(Vector3(0.07, 0.07, 0.07), Palette.DUCK, rng, 0.06, _t(0, 0.12, 0.15))
				mb.add_box(Vector3(0.05, 0.03, 0.08), Palette.BEAK, _t(0, 0.18, 0.24))
			), Vector3.ZERO, false)
			_add_click_body(Vector3(0.35, 0.35, 0.45))


func _sync_click_body() -> void:
	if _click_body != null and is_instance_valid(_click_body):
		_click_body.collision_layer = (1 << (CLICK_LAYER - 1)) if visible else 0


func _add_click_body(size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1 << (CLICK_LAYER - 1)
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	sb.add_child(cs)
	sb.set_meta("villager", self)
	add_child(sb)
	_click_body = sb
	# Người đã "vào nhà" (ẩn đi) thì tắt vùng bấm: không thì một người vô hình đứng ở cửa nhà
	# chặn tia nhìn / chuột, không bấm được cửa để vào
	if not visibility_changed.is_connected(_sync_click_body):
		visibility_changed.connect(_sync_click_body)
	_sync_click_body()
	# Vòng sáng dưới chân khi được chọn
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	var r := maxf(size.x, size.z) * 0.6
	torus.inner_radius = r
	torus.outer_radius = r + 0.08
	torus.rings = 24
	torus.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Palette.WINDOW_GLOW
	torus.material = mat
	ring.mesh = torus
	ring.scale = Vector3(1, 0.2, 1)
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)


## Đèn lồng cầm tay (người đi tối). `light` = có OmniLight thật hay chỉ phát sáng.
func add_lantern(light: bool) -> void:
	if arms.is_empty():
		return
	lantern = Node3D.new()
	lantern.position = Vector3(0, -0.6, 0.05)
	arms[0].add_child(lantern)
	_part(lantern, _cached("lantern", func(mb: MeshBuilder) -> void:
		mb.add_box(Vector3(0.01, 0.15, 0.01), Palette.WINDOW_DARK, _t(0, 0, 0))
		mb.add_blob(Vector3(0.09, 0.12, 0.09), Palette.ALTAR_RED, RandomNumberGenerator.new(), 0.05, _t(0, -0.24, 0))
	), Vector3.ZERO, false)
	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Palette.WINDOW_GLOW
	sm.material = mat
	glow.mesh = sm
	glow.position = Vector3(0, -0.14, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern.add_child(glow)
	if light:
		var l := OmniLight3D.new()
		l.light_color = Palette.WINDOW_GLOW
		l.omni_range = 4.5
		l.light_energy = 1.4
		l.position = Vector3(0, -0.14, 0)
		lantern.add_child(l)
	lantern.visible = false


# --- Cập nhật mỗi khung hình --------------------------------------------------------

func set_selected(on: bool) -> void:
	if ring != null:
		ring.visible = on


## Đặt đường đi mới (đã gồm điểm đích).
func walk_path(p: PackedVector3Array) -> void:
	path = p
	path_index = 0
	_walk_start = global_position
	state = State.WALK if p.size() > 0 else State.IDLE
	visible = true


func tick(delta: float, animate: bool) -> void:
	match state:
		State.WALK:
			_step_walk(delta)
		State.IDLE:
			dwell -= delta
			_walk_amount = move_toward(_walk_amount, 0.0, delta * 4.0)
		State.INSIDE:
			dwell -= delta
	if follow_target != null:
		_step_follow(delta)
	if animate and visible:
		_animate(delta)


func _step_walk(delta: float) -> void:
	if path_index >= path.size():
		state = State.IDLE
		return
	var target := path[path_index]
	# Lệch sang một bên theo hướng CỐ ĐỊNH của đoạn đường (trừ điểm cuối), để không giẫm lên nhau
	if path_index > 0 and path_index < path.size() - 1:
		var seg := path[path_index] - path[path_index - 1]
		seg.y = 0.0
		if seg.length() > 0.01:
			target += Vector3(seg.z, 0, -seg.x).normalized() * side_offset
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	var step := speed * speed_mul * delta
	# Độ cao: nội suy giữa điểm đầu và điểm cuối đoạn đường (đường lên đê, cầu ván có độ cao riêng)
	var from := path[path_index - 1] if path_index > 0 else _walk_start
	var seg_len := Vector2(target.x - from.x, target.z - from.z).length()
	var t := 1.0 - clampf((dist - step) / maxf(seg_len, 0.001), 0.0, 1.0)
	_path_y = lerpf(from.y, target.y, t)
	# Đặt vị trí MỘT lần mỗi bước (mỗi lần đặt là cập nhật transform của ~30 node con)
	var np := global_position
	if dist <= step + 0.05:
		np = Vector3(target.x, np.y, target.z)
		path_index += 1
		if path_index >= path.size():
			state = State.IDLE
	else:
		var dir := to / dist
		np += dir * step
		_face(dir, delta)
	_walk_amount = move_toward(_walk_amount, 1.0, delta * 4.0)
	np.y = _ground_y(np)
	global_position = np
	_record_trail()


## Trâu/chó đi theo vệt chân của chủ, giữ khoảng cách.
func _step_follow(delta: float) -> void:
	var leader := follow_target
	visible = leader.visible
	if not visible:
		return
	var goal := leader.global_position
	for i in range(leader._trail.size() - 1, -1, -1):
		if leader._trail[i].distance_to(leader.global_position) >= follow_distance:
			goal = leader._trail[i]
			break
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.4:
		var sp := clampf(dist * 1.5, 0.5, 4.0)
		var dir := to / dist
		global_position += dir * minf(sp * delta, dist)
		_face(dir, delta)
		_walk_amount = move_toward(_walk_amount, 1.0, delta * 4.0)
	else:
		_walk_amount = move_toward(_walk_amount, 0.0, delta * 3.0)
		# Đứng yên: quay theo hướng chủ
		var look := leader.global_position - global_position
		look.y = 0.0
		if look.length() > 0.3:
			_face(look.normalized(), delta * 0.5)
	if dist > 25.0:
		global_position = goal   # bị bỏ xa quá (vd. chủ vào nhà rồi ra) thì nhảy tới
	_path_y = lerpf(_path_y, goal.y, clampf(delta * 6.0, 0.0, 1.0))
	_ground()
	_record_trail()


func _face(dir: Vector3, delta: float) -> void:
	var yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))   # quay người từ tốn


## Độ cao mặt đất tại p (như _ground nhưng không đặt vị trí).
func _ground_y(p: Vector3) -> float:
	if role == "duck":
		return p.y
	if terrain != null and absf(p.x) < terrain.grid_extent and absf(p.z) < terrain.grid_extent:
		return maxf(terrain.height_at(p.x, p.z), -0.1) + 0.02
	return maxf(_path_y, 0.05)


func _ground() -> void:
	var p := global_position
	var y := maxf(_path_y, 0.05)
	if terrain != null and absf(p.x) < terrain.grid_extent and absf(p.z) < terrain.grid_extent:
		y = maxf(terrain.height_at(p.x, p.z), -0.1) + 0.02
	if role == "duck":
		y = global_position.y
	global_position.y = y


func _record_trail() -> void:
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(global_position) > 0.4:
		_trail.append(global_position)
		if _trail.size() > 40:
			_trail.remove_at(0)


func _animate(delta: float) -> void:
	var fast := 1.6 if role in ["kid", "dog"] else (0.7 if role in ["elder", "buffalo"] else 1.0)
	_phase += delta * (5.0 + 4.0 * speed_mul) * fast * maxf(_walk_amount, 0.2)
	var w := _walk_amount
	var swing := sin(_phase) * 0.55 * w
	if legs.size() == 2:
		legs[0].rotation.x = swing
		legs[1].rotation.x = -swing
	elif legs.size() == 4:
		legs[0].rotation.x = swing
		legs[3].rotation.x = swing
		legs[1].rotation.x = -swing
		legs[2].rotation.x = -swing
	# Người: gối co khi chân đưa lên trước, hơi chùng khi chạm đất; thân lắc nhẹ theo bước
	if knees.size() == 2:
		var c := cos(_phase)
		knees[0].rotation.x = w * (0.1 + 0.85 * maxf(0.0, -c))
		knees[1].rotation.x = w * (0.1 + 0.85 * maxf(0.0, c))
	var person := knees.size() == 2
	if person:
		body.position.y = (absf(sin(_phase)) * 0.035 - 0.02) * w * (1.5 if role == "kid" else 1.0)
		body.rotation.z = sin(_phase) * 0.035 * w
		body.rotation.y = sin(_phase) * 0.07 * w
	else:
		body.position.y = absf(sin(_phase)) * 0.04 * w
	# Thở nhẹ khi đứng yên
	_work_time += delta
	var idle := 1.0 - w
	if person:
		body.scale = Vector3(1.0, 1.0 + 0.012 * sin(_work_time * 1.8) * idle, 1.0)
	# Khuỷu tay hơi gập, gập thêm khi đi (tay cầm đồ thì giữ thẳng cho khớp đồ cầm)
	if elbows.size() == 2:
		var e := -(0.22 + 0.3 * w)
		elbows[0].rotation.x = 0.0 if (lantern != null and lantern.visible) else e
		elbows[1].rotation.x = 0.0 if (_holds_pole or prop_node != null and prop_node.visible) else e

	# Dáng làm việc khi đứng yên
	match work_anim:
		"hoe":
			if arms.size() == 2:
				var t := fmod(_work_time * 1.1, 1.0)
				var lift := -2.2 * smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(0.75, 0.9, t))
				arms[1].rotation.x = lerpf(-swing * 0.8, lift, idle)
				arms[0].rotation.x = lerpf(swing * 0.8, lift * 0.8, idle)
				body.rotation.x = 0.25 * idle * smoothstep(0.7, 0.9, t)
				if knees.size() == 2:
					var dip := 0.25 * idle * smoothstep(0.7, 0.9, t)
					knees[0].rotation.x = maxf(knees[0].rotation.x, dip)
					knees[1].rotation.x = maxf(knees[1].rotation.x, dip)
		"play":
			var hop := absf(sin(_work_time * 7.0))
			body.position.y += hop * 0.18 * idle
			if arms.size() == 2:
				arms[0].rotation.z = -1.2 * idle * hop
				arms[1].rotation.z = 1.2 * idle * hop
			if knees.size() == 2:
				knees[0].rotation.x = maxf(knees[0].rotation.x, 0.5 * idle * (1.0 - hop))
				knees[1].rotation.x = maxf(knees[1].rotation.x, 0.5 * idle * (1.0 - hop))
		"chat":
			if arms.size() == 2:
				arms[0].rotation.x = lerpf(swing * 0.8, -0.35 - 0.25 * sin(_work_time * 2.3), idle)
				arms[1].rotation.x = lerpf(-swing * 0.8, 0.0, idle)
			if elbows.size() == 2:
				elbows[0].rotation.x = lerpf(elbows[0].rotation.x, -0.9 - 0.3 * sin(_work_time * 2.3), idle)
			body.rotation.y += 0.15 * sin(_work_time * 0.7) * idle
		"peck", "graze":
			var dip2 := 0.5 if work_anim == "peck" else 0.18
			body.rotation.x = dip2 * maxf(0.0, sin(_work_time * (6.0 if work_anim == "peck" else 0.8))) * idle
		"sit", "tea", "weave", "study", "kneel":
			var kneel := work_anim == "kneel"
			if legs.size() == 2:
				legs[0].rotation.x = lerpf(swing, -0.08 if kneel else -1.45, idle)
				legs[1].rotation.x = lerpf(-swing, -0.08 if kneel else -1.45, idle)
			if knees.size() == 2:
				# Quỳ: đùi thẳng đứng, ống chân nằm sát nền phía sau
				knees[0].rotation.x = lerpf(knees[0].rotation.x, 1.62 if kneel else 1.45, idle)
				knees[1].rotation.x = lerpf(knees[1].rotation.x, 1.62 if kneel else 1.45, idle)
			# Gập gối thì hông hạ xuống đúng một đoạn đùi (như ngồi ghế đẩu, ngồi bậc, quỳ)
			body.position.y -= idle * (0.35 if knees.is_empty() else legs[0].position.y * 0.47)
			if arms.size() == 2 and elbows.size() == 2:
				var t2 := _work_time
				match work_anim:
					"tea":
						# Thỉnh thoảng nâng chén nước chè lên uống
						var sip := smoothstep(0.75, 0.85, fmod(t2 * 0.18, 1.0)) * (1.0 - smoothstep(0.92, 1.0, fmod(t2 * 0.18, 1.0)))
						arms[1].rotation.x = -0.45 - 0.5 * sip
						elbows[1].rotation.x = -1.2 - 0.9 * sip
						arms[0].rotation.x = -0.35
						elbows[0].rotation.x = -0.9
					"weave":
						# Hai tay đưa thoi qua lại
						arms[0].rotation.x = -0.9 + 0.25 * sin(t2 * 3.0)
						arms[1].rotation.x = -0.9 - 0.25 * sin(t2 * 3.0)
						elbows[0].rotation.x = -0.6
						elbows[1].rotation.x = -0.6
					"study":
						arms[0].rotation.x = -0.75
						arms[1].rotation.x = -0.8 + 0.06 * sin(t2 * 9.0)   # tay viết
						elbows[0].rotation.x = -1.0
						elbows[1].rotation.x = -1.0
						body.rotation.x = 0.18
					"kneel":
						# Chắp tay trước ngực, cúi lạy chậm
						arms[0].rotation.x = -0.9
						arms[1].rotation.x = -0.9
						arms[0].rotation.z = 0.35
						arms[1].rotation.z = -0.35
						elbows[0].rotation.x = -1.6
						elbows[1].rotation.x = -1.6
						body.rotation.x = 0.35 * maxf(0.0, sin(t2 * 0.6))
		"squat":
			# Ngồi xổm sát đất chơi ô ăn quan: gối gập sâu, hông hạ thấp, tay đưa ra trước bốc sỏi
			if legs.size() == 2:
				legs[0].rotation.x = lerpf(swing, -1.75, idle)
				legs[1].rotation.x = lerpf(-swing, -1.75, idle)
			if knees.size() == 2:
				knees[0].rotation.x = lerpf(knees[0].rotation.x, 2.35, idle)
				knees[1].rotation.x = lerpf(knees[1].rotation.x, 2.35, idle)
			if not legs.is_empty():
				body.position.y -= idle * legs[0].position.y * 0.78
			body.rotation.x = 0.28 * idle
			var reach := 0.5 + 0.5 * sin(_work_time * 1.1)
			if arms.size() == 2:
				arms[0].rotation.x = -0.75 - 0.15 * reach
				arms[1].rotation.x = -0.6 - 0.45 * reach
				arms[0].rotation.z = 0.15
				arms[1].rotation.z = -0.15
			for e in elbows:
				e.rotation.x = -0.35
		"teach":
			# Cô giáo đứng giảng: tay phải giơ chỉ lên bảng theo nhịp, thân xoay nhẹ
			var k := 0.5 + 0.5 * sin(_work_time * 0.7)
			if arms.size() == 2:
				arms[1].rotation.x = lerpf(-0.3, -1.9, k)
				arms[1].rotation.z = -0.25
				arms[0].rotation.x = -0.2
				arms[0].rotation.z = 0.0
			for e in elbows:
				e.rotation.x = -0.3
			body.rotation.y = 0.35 * sin(_work_time * 0.35)
			body.rotation.x = 0.0
		"pray":
			# Đứng chắp tay vái
			if arms.size() == 2 and elbows.size() == 2:
				arms[0].rotation.x = -0.9
				arms[1].rotation.x = -0.9
				arms[0].rotation.z = 0.35
				arms[1].rotation.z = -0.35
				elbows[0].rotation.x = -1.6
				elbows[1].rotation.x = -1.6
			body.rotation.x = 0.3 * maxf(0.0, sin(_work_time * 0.9))
		"plant", "reap":
			# Cấy / làm cỏ (cúi sâu, tay phải cắm mạ xuống bùn, lùi dần) và gặt (cúi, tay trái nắm bó lúa,
			# tay phải đưa liềm quẹt ngang). Thân cúi về trước, hông xoay ngược để chân vẫn đứng thẳng.
			var reap := work_anim == "reap"
			var bend := (0.95 if not reap else 0.75) * idle
			body.rotation.x = bend
			for l in legs:
				l.rotation.x = lerpf(l.rotation.x, -bend + 0.08, idle)
			if knees.size() == 2:
				knees[0].rotation.x = maxf(knees[0].rotation.x, 0.25 * idle)
				knees[1].rotation.x = maxf(knees[1].rotation.x, 0.25 * idle)
			body.position.y -= 0.06 * idle
			var cyc := _work_time * (1.6 if not reap else 2.0)
			var u := fmod(cyc, 1.0)
			if arms.size() == 2:
				if reap:
					arms[0].rotation.x = lerpf(arms[0].rotation.x, -1.0, idle)
					arms[1].rotation.x = lerpf(arms[1].rotation.x, -0.9, idle)
					arms[1].rotation.z = lerpf(0.0, -0.9 + 1.4 * smoothstep(0.0, 0.5, u) * (1.0 - smoothstep(0.6, 1.0, u)), idle)
				else:
					var dip := sin(u * PI)
					arms[1].rotation.x = lerpf(arms[1].rotation.x, -0.7 - 0.6 * dip, idle)
					arms[0].rotation.x = lerpf(arms[0].rotation.x, -0.9, idle)
					arms[0].rotation.z = 0.25 * idle
			for e in elbows:
				e.rotation.x = lerpf(e.rotation.x, -0.5, idle)
		"plow":
			# Hai tay cầm bắp cày phía trước, người hơi đổ về trước khi đi
			if arms.size() == 2:
				arms[0].rotation.x = -0.75
				arms[1].rotation.x = -0.75
				arms[0].rotation.z = 0.12
				arms[1].rotation.z = -0.12
			for e in elbows:
				e.rotation.x = -0.35
			body.rotation.x = 0.18
		"work":
			# Đẩy tay cối xay: hai tay ra trước, người đưa tới đưa lui
			var push := sin(_work_time * 2.2)
			if arms.size() == 2 and elbows.size() == 2:
				arms[0].rotation.x = -1.1 + 0.3 * push
				arms[1].rotation.x = -1.1 + 0.3 * push
				elbows[0].rotation.x = -0.5 - 0.3 * push
				elbows[1].rotation.x = -0.5 - 0.3 * push
			body.rotation.x = 0.12 + 0.08 * push
		"swim":
			# Bơi sải (RiverSwim xoay cả người nằm sấp sát mặt nước): hai tay quạt vòng so le, chân đập, thân lắc
			var st := _work_time * 4.2
			if arms.size() == 2:
				arms[0].rotation.x = -fposmod(st, TAU)
				arms[1].rotation.x = -fposmod(st + PI, TAU)
			for e in elbows:
				e.rotation.x = -0.15
			if legs.size() == 2:
				legs[0].rotation.x = 0.32 * sin(st * 2.3)
				legs[1].rotation.x = -0.32 * sin(st * 2.3)
			for k in knees:
				k.rotation.x = 0.2
			body.position.y = 0.0
			body.rotation = Vector3(0.0, 0.0, 0.16 * sin(st))
		"sleep":
			# Nằm ngửa (thân được IndoorFolk xoay nằm), tay xuôi, thở chậm
			for l in legs:
				l.rotation.x = 0.0
			for k in knees:
				k.rotation.x = 0.0
			if arms.size() == 2:
				arms[0].rotation.x = 0.0
				arms[1].rotation.x = 0.0
			for e in elbows:
				e.rotation.x = -0.2
			body.position.y = 0.0
			body.rotation = Vector3.ZERO
			body.scale = Vector3(1.0, 1.0, 1.0 + 0.02 * sin(_work_time * 1.1))
		_:
			if arms.size() == 2:
				arms[0].rotation.x = -swing * 0.8
				arms[1].rotation.x = -1.6 if _holds_pole else swing * 0.8
			body.rotation.x = 0.0
	if not work_anim in ["hoe", "peck", "graze", "pray", "work", "study", "kneel", "sleep"]:
		body.rotation.x = move_toward(body.rotation.x, 0.0, delta * 3.0)
	if not work_anim in ["kneel", "pray", "play"] and arms.size() == 2:
		arms[0].rotation.z = move_toward(arms[0].rotation.z, 0.0, delta * 4.0)
		arms[1].rotation.z = move_toward(arms[1].rotation.z, 0.0, delta * 4.0)
