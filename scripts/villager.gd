class_name Villager
extends Node3D
## Một NPC: người (nông dân, người gánh hàng, cụ già, trẻ con, người chăn trâu) hoặc con vật
## (trâu, chó, gà, vịt). Tự dựng hình low-poly có khớp tay/chân để làm dáng đi, dáng làm việc.
## Việc đi đâu do `Villagers` quyết định; Villager chỉ đi theo `path` và diễn hoạt.
## Mặt trước hướng +z cục bộ.

enum State { IDLE, WALK, INSIDE }

const CLICK_LAYER := 3            # lớp va chạm để bấm chọn NPC

# --- Thông tin (hiện khi bấm chọn) ---
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
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var lantern: Node3D
var ring: MeshInstance3D
var _phase: float = 0.0
var _walk_amount: float = 0.0
var _work_time: float = 0.0
var _trail: Array[Vector3] = []   # vệt đường đã đi (cho con vật đi theo)
var _holds_pole: bool = false
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
	mi.visibility_range_end = 70.0 if role in ["chicken", "duck"] else 150.0
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# --- Dựng người ------------------------------------------------------------------------

## look: {shirt, pants, skin, hat ("non"|"khan"|"none"), scale, female, prop ("hoe"|"pole"|"stick"|"none")}
func build_person(look: Dictionary) -> void:
	var s: float = look.get("scale", 1.0)
	var shirt: Color = look.shirt
	var pants: Color = look.pants
	var skin: Color = look.get("skin", Palette.FARMER_SKIN)
	var hip := 0.78 * s
	body = _pivot(self, Vector3.ZERO)
	var hk := "%s_%s_%.2f" % [shirt.to_html(), pants.to_html(), s]
	# Chân: ống quần + bắp chân
	for side in [-1.0, 1.0]:
		var leg := _pivot(body, Vector3(side * 0.1 * s, hip, 0.0))
		_part(leg, _cached("leg_" + hk, func(mb: MeshBuilder) -> void:
			mb.add_limb(Vector3.ZERO, Vector3(0, -hip * 0.55, 0), 0.085 * s, 0.075 * s, 5, pants)
			mb.add_limb(Vector3(0, -hip * 0.55, 0), Vector3(0, -hip, 0), 0.06 * s, 0.055 * s, 5, skin)
		), Vector3.ZERO)
		legs.append(leg)
	# Thân + đầu (+ lưng còng cho cụ già)
	var bend := 0.25 if role == "elder" else 0.0
	_part(body, _cached("torso_%s_%.2f_%.2f" % [shirt.to_html(), s, bend], func(mb: MeshBuilder) -> void:
		var tilt := Transform3D(Basis(Vector3.RIGHT, bend), Vector3(0, hip, 0))
		mb.add_prism(0.2 * s, 0.22 * s, 0.56 * s, 6, shirt, tilt * Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.8)), Vector3.ZERO))
		mb.add_prism(0.05 * s, 0.05 * s, 0.08 * s, 5, skin, tilt * _t(0, 0.56 * s, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		mb.add_blob(Vector3(0.12, 0.13, 0.12) * s, skin, rng, 0.06, tilt * _t(0, 0.6 * s, 0))
	), Vector3.ZERO)
	var head_top := Vector3(0, hip + 0.86 * s * cos(bend), 0.86 * s * sin(bend))
	match str(look.get("hat", "none")):
		"non":
			_part(body, _cached("non_%.2f" % s, func(mb: MeshBuilder) -> void:
				mb.add_prism(0.36 * s, 0.34 * s, 0.025, 12, Palette.HAT_DARK)
				mb.add_pyramid(0.36 * s, 0.28 * s, 12, Palette.HAT, _t(0, 0.025, 0))
			), head_top - Vector3(0, 0.05 * s, 0))
		"khan":
			_part(body, _cached("khan_%.2f" % s, func(mb: MeshBuilder) -> void:
				mb.add_box(Vector3(0.27, 0.07, 0.27) * s, Palette.WINDOW_DARK)
				mb.add_pyramid(0.08 * s, 0.1 * s, 4, Palette.WINDOW_DARK, _t(0, 0.05 * s, 0.1 * s))
			), head_top - Vector3(0, 0.07 * s, 0))
		"tuft":
			_part(body, _cached("tuft", func(mb: MeshBuilder) -> void:
				mb.add_blob(Vector3(0.05, 0.05, 0.05), Palette.WINDOW_DARK, RandomNumberGenerator.new(), 0.1)
			), head_top)
	# Tay
	var sh := hip + 0.52 * s
	for side in [-1.0, 1.0]:
		var arm := _pivot(body, Vector3(side * 0.24 * s, sh, 0.52 * s * sin(bend) * 0.6))
		_part(arm, _cached("arm_" + hk, func(mb: MeshBuilder) -> void:
			mb.add_limb(Vector3.ZERO, Vector3(0, -0.5 * s, 0), 0.055 * s, 0.045 * s, 5, shirt)
			mb.add_blob(Vector3(0.045, 0.05, 0.045) * s, skin, RandomNumberGenerator.new(), 0.05, _t(0, -0.56 * s, 0))
		), Vector3.ZERO)
		arms.append(arm)
	# Đồ cầm theo
	match str(look.get("prop", "none")):
		"hoe":
			_part(arms[1], _cached("hoe", func(mb: MeshBuilder) -> void:
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
	_add_click_body(Vector3(0.7, 1.75 * s, 0.7))


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
	if dist <= step + 0.05:
		global_position = Vector3(target.x, global_position.y, target.z)
		path_index += 1
		if path_index >= path.size():
			state = State.IDLE
	else:
		var dir := to / dist
		global_position += dir * step
		_face(dir, delta)
	_walk_amount = move_toward(_walk_amount, 1.0, delta * 4.0)
	_ground()
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
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))


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
	body.position.y = absf(sin(_phase)) * 0.04 * w * (1.6 if role == "kid" else 1.0)

	# Dáng làm việc khi đứng yên
	_work_time += delta
	var idle := 1.0 - w
	match work_anim:
		"hoe":
			if arms.size() == 2:
				var t := fmod(_work_time * 1.1, 1.0)
				var lift := -2.2 * smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(0.75, 0.9, t))
				arms[1].rotation.x = lerpf(-swing * 0.8, lift, idle)
				arms[0].rotation.x = lerpf(swing * 0.8, lift * 0.8, idle)
				body.rotation.x = 0.25 * idle * smoothstep(0.7, 0.9, t)
		"play":
			body.position.y += absf(sin(_work_time * 7.0)) * 0.18 * idle
			if arms.size() == 2:
				arms[0].rotation.z = -1.2 * idle * absf(sin(_work_time * 7.0))
				arms[1].rotation.z = 1.2 * idle * absf(sin(_work_time * 7.0))
		"chat":
			if arms.size() == 2:
				arms[0].rotation.x = lerpf(swing * 0.8, -0.5 - 0.3 * sin(_work_time * 2.3), idle)
				arms[1].rotation.x = lerpf(-swing * 0.8, 0.0, idle)
			body.rotation.y = 0.15 * sin(_work_time * 0.7) * idle
		"peck", "graze":
			var dip := 0.5 if work_anim == "peck" else 0.18
			body.rotation.x = dip * maxf(0.0, sin(_work_time * (6.0 if work_anim == "peck" else 0.8))) * idle
		"sit":
			if legs.size() == 2:
				legs[0].rotation.x = lerpf(swing, -1.4, idle)
				legs[1].rotation.x = lerpf(-swing, -1.4, idle)
			body.position.y -= 0.35 * idle
		_:
			if arms.size() == 2:
				arms[0].rotation.x = -swing * 0.8
				arms[1].rotation.x = -1.6 if _holds_pole else swing * 0.8
			body.rotation.x = 0.0
	if work_anim != "hoe" and work_anim != "peck" and work_anim != "graze":
		body.rotation.x = move_toward(body.rotation.x, 0.0, delta * 3.0)
