class_name Characters
extends Node3D
## Tượng tĩnh low-poly có chút "sự sống": trâu gặm cỏ (thở + vẫy đuôi),
## người đội nón lá cầm cuốc (thở), vài con vịt bơi chậm trên ao.
## Vị trí trâu/người phải khớp `RiceField.clear_zones` để không bị lúa mọc xuyên.

@export var terrain: Terrain
@export var random_seed: int = 9109

@export_group("Trâu")
@export var buffalo_position: Vector3 = Vector3(-4.6, 0.03, 9.6)
@export var buffalo_yaw_deg: float = 35.0
@export_group("Người")
@export var farmer_position: Vector3 = Vector3(-7.0, 0.03, 12.2)
@export var farmer_yaw_deg: float = 20.0
@export_group("Vịt")
@export_range(0, 8) var duck_count: int = 3
@export var duck_swim_radius: float = 2.2
@export var duck_speed: float = 0.12

@export_group("Hoạt ảnh")
@export_range(0.0, 0.05) var breath_amount: float = 0.015
@export var breath_speed: float = 1.6
@export var tail_swing_deg: float = 18.0

var _buffalo: Node3D
var _farmer: Node3D
var _tail: Node3D
var _ducks: Array[Node3D] = []
var _duck_phase: Array[float] = []
var _time: float = 0.0


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	_buffalo = _build_buffalo(rng)
	_farmer = _build_farmer(rng)
	if terrain != null:
		for i in duck_count:
			var duck := _build_duck(rng)
			_ducks.append(duck)
			_duck_phase.append(TAU * i / maxf(duck_count, 1) + rng.randf_range(-0.4, 0.4))
	_process(0.0)


func _process(delta: float) -> void:
	_time += delta
	# Thở: co giãn trục y quanh chân (gốc toạ độ ở mặt đất)
	if _buffalo != null:
		_buffalo.scale = Vector3(1.0, 1.0 + breath_amount * sin(_time * breath_speed), 1.0 + breath_amount * 0.5 * sin(_time * breath_speed))
	if _farmer != null:
		_farmer.scale = Vector3(1.0, 1.0 + breath_amount * 0.7 * sin(_time * breath_speed * 1.3 + 1.0), 1.0)
	if _tail != null:
		# Vẫy đuôi từng đợt
		var swing := sin(_time * 3.0) * maxf(0.0, sin(_time * 0.7))
		_tail.rotation.x = deg_to_rad(tail_swing_deg) * swing
	# Vịt bơi vòng chậm quanh tâm ao, dập dềnh nhẹ
	for i in _ducks.size():
		var a := _duck_phase[i] + _time * duck_speed * (1.0 + 0.15 * i)
		var r := duck_swim_radius * (0.75 + 0.25 * sin(a * 2.0 + i))
		var c := terrain.pond_center
		var duck := _ducks[i]
		duck.position = Vector3(c.x + cos(a) * r, terrain.water_level + 0.02 + 0.015 * sin(_time * 2.0 + i), c.y + sin(a) * r)
		duck.rotation.y = -a  # hướng theo chiều bơi


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## Basis quay trục +Y cục bộ trùng hướng `dir`.
static func _aim(dir: Vector3) -> Basis:
	dir = dir.normalized()
	var axis := Vector3.UP.cross(dir)
	if axis.length() < 0.001:
		return Basis() if dir.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), Vector3.UP.angle_to(dir))


## Khúc trụ nối điểm a tới điểm b.
static func _limb(mb: MeshBuilder, a: Vector3, b: Vector3, r0: float, r1: float, sides: int,
		color: Color, xf: Transform3D) -> void:
	mb.add_prism(r0, r1, a.distance_to(b), sides, color, xf * Transform3D(_aim(b - a), a))


func _place(node_name: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	var y := pos.y
	if terrain != null:
		y = maxf(pos.y, terrain.height_at(pos.x, pos.z))
	node.position = Vector3(pos.x, y, pos.z)
	node.rotation.y = deg_to_rad(yaw_deg)
	add_child(node)
	return node


# --- Trâu (hướng +x cục bộ) ----------------------------------------------------------

func _build_buffalo(rng: RandomNumberGenerator) -> Node3D:
	var root := _place("Buffalo", buffalo_position, buffalo_yaw_deg)
	var mb := MeshBuilder.new(random_seed, 0.04)
	mb.contact_shade_height = 0.5
	var id := Transform3D.IDENTITY
	var body := Palette.BUFFALO
	var dark := Palette.BUFFALO_DARK

	# Chân + móng
	for p in [Vector2(0.62, 0.28), Vector2(0.62, -0.28), Vector2(-0.62, 0.28), Vector2(-0.62, -0.28)]:
		var v: Vector2 = p
		mb.add_prism(0.13, 0.1, 0.62, 5, dark, _t(v.x, 0.06, v.y))
		mb.add_prism(0.1, 0.1, 0.08, 5, Palette.WINDOW_DARK, _t(v.x, 0.0, v.y))
	# Thân: lăng trụ 7 cạnh nằm ngang, hơi dẹt; bụng tối hơn; u vai, mông
	var torso := Transform3D(Basis(Vector3.BACK, -PI / 2.0).scaled(Vector3(1.0, 1.0, 0.95)), Vector3(-0.95, 0.98, 0.0))
	mb.add_prism(0.52, 0.48, 1.9, 7, body, torso)
	mb.add_box(Vector3(1.4, 0.2, 0.7), dark, _t(0.0, 0.48, 0.0))
	mb.add_blob(Vector3(0.45, 0.3, 0.45), body, rng, 0.12, _t(0.55, 1.02, 0.0))
	mb.add_blob(Vector3(0.5, 0.42, 0.5), body, rng, 0.1, _t(-0.75, 0.62, 0.0))
	# Cổ cúi xuống, đầu chúc xuống đất gặm cỏ
	var neck_a := Vector3(0.75, 1.0, 0.0)
	var neck_b := Vector3(1.3, 0.58, 0.0)
	_limb(mb, neck_a, neck_b, 0.32, 0.24, 6, body, id)
	# Trục +y của hộp đầu hướng xuống-ra trước; trục -x cục bộ là đỉnh sọ
	var head := Transform3D(Basis(Vector3.BACK, deg_to_rad(-150.0)), Vector3(1.3, 0.58, 0.0))
	mb.add_box(Vector3(0.38, 0.56, 0.36), body, head)
	mb.add_box(Vector3(0.32, 0.16, 0.3), dark, head * _t(0.0, 0.48, 0.0))      # mõm
	# Tai
	for s in [-1.0, 1.0]:
		var ear := head * Transform3D(Basis(Vector3.RIGHT, s * 1.2), Vector3(-0.05, 0.12, s * 0.17))
		mb.add_box(Vector3(0.1, 0.22, 0.05), dark, ear)
	# Sừng cong lưỡi liềm: hai khúc mỗi bên
	for s in [-1.0, 1.0]:
		var base := head * Vector3(-0.15, 0.08, s * 0.15)
		var mid := base + Vector3(-0.08, 0.16, s * 0.34)
		var tip := mid + Vector3(-0.32, 0.16, -s * 0.1)
		_limb(mb, base, mid, 0.06, 0.045, 5, Palette.BUFFALO_HORN, id)
		_limb(mb, mid, tip, 0.045, 0.0, 5, Palette.BUFFALO_HORN, id)
	var mesh := mb.commit_instance("Body")
	root.add_child(mesh)

	# Đuôi: node riêng, xoay quanh gốc đuôi
	_tail = Node3D.new()
	_tail.name = "TailPivot"
	_tail.position = Vector3(-1.1, 1.08, 0.0)
	root.add_child(_tail)
	var tb := MeshBuilder.new(random_seed + 5, 0.0)
	_limb(tb, Vector3.ZERO, Vector3(-0.12, -0.65, 0.0), 0.035, 0.025, 4, dark, id)
	tb.add_blob(Vector3(0.06, 0.1, 0.06), Palette.WINDOW_DARK, rng, 0.1, _t(-0.12, -0.82, 0.0))
	_tail.add_child(tb.commit_instance("Tail"))
	return root


# --- Người nông dân đội nón lá, cầm cuốc (hướng +x cục bộ) --------------------------

func _build_farmer(rng: RandomNumberGenerator) -> Node3D:
	var root := _place("Farmer", farmer_position, farmer_yaw_deg)
	var mb := MeshBuilder.new(random_seed + 1, 0.03)
	mb.contact_shade_height = 0.3
	var id := Transform3D.IDENTITY
	# Chân: ống quần xắn, bắp chân để trần
	for s in [-1.0, 1.0]:
		var z: float = s * 0.1
		mb.add_prism(0.065, 0.06, 0.32, 5, Palette.FARMER_SKIN, _t(0.0, 0.0, z))
		mb.add_prism(0.085, 0.09, 0.46, 5, Palette.FARMER_PANTS, _t(0.0, 0.32, z))
	# Thân áo
	mb.add_prism(0.2, 0.22, 0.56, 6, Palette.FARMER_SHIRT,
			Transform3D(Basis().scaled(Vector3(0.8, 1.0, 1.0)), Vector3(0.0, 0.76, 0.0)))
	# Cánh tay: tay phải đưa ra trước cầm cán cuốc, tay trái buông
	var sh_r := Vector3(0.0, 1.27, 0.24)
	var sh_l := Vector3(0.0, 1.27, -0.24)
	var hand_r := Vector3(0.32, 0.92, 0.2)
	var hand_l := Vector3(0.04, 0.8, -0.3)
	_limb(mb, sh_r, hand_r, 0.06, 0.05, 5, Palette.FARMER_SHIRT, id)
	_limb(mb, sh_l, hand_l, 0.06, 0.05, 5, Palette.FARMER_SHIRT, id)
	mb.add_blob(Vector3(0.05, 0.05, 0.05), Palette.FARMER_SKIN, rng, 0.1, _t(hand_r.x, hand_r.y - 0.05, hand_r.z))
	mb.add_blob(Vector3(0.05, 0.05, 0.05), Palette.FARMER_SKIN, rng, 0.1, _t(hand_l.x, hand_l.y - 0.05, hand_l.z))
	# Cổ + đầu
	mb.add_prism(0.05, 0.05, 0.08, 5, Palette.FARMER_SKIN, _t(0.0, 1.32, 0.0))
	mb.add_blob(Vector3(0.12, 0.13, 0.12), Palette.FARMER_SKIN, rng, 0.08, _t(0.0, 1.36, 0.0))
	# Nón lá: chóp 12 cạnh + vành tối phía dưới
	mb.add_prism(0.37, 0.35, 0.025, 12, Palette.HAT_DARK, _t(0.0, 1.52, 0.0))
	mb.add_pyramid(0.37, 0.3, 12, Palette.HAT, _t(0.0, 1.545, 0.0))
	# Cuốc: cán gỗ chéo xuống đất, lưỡi sắt
	var handle_top := hand_r + Vector3(0.05, 0.25, 0.0)
	var handle_bot := Vector3(0.95, 0.1, 0.22)
	_limb(mb, handle_bot, handle_top, 0.025, 0.025, 4, Palette.WOOD, id)
	mb.add_box(Vector3(0.08, 0.22, 0.2), Palette.ROCK_DARK, _t(handle_bot.x + 0.02, 0.0, handle_bot.z))
	root.add_child(mb.commit_instance("Body"))
	return root


# --- Vịt (hướng +z cục bộ để xoay theo chiều bơi) ------------------------------------

func _build_duck(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Duck"
	add_child(root)
	var mb := MeshBuilder.new(random_seed + 10 + _ducks.size(), 0.03)
	mb.add_blob(Vector3(0.14, 0.09, 0.2), Palette.DUCK, rng, 0.1, _t(0.0, -0.04, 0.0))
	mb.add_blob(Vector3(0.07, 0.07, 0.07), Palette.DUCK, rng, 0.08, _t(0.0, 0.08, 0.15))
	mb.add_box(Vector3(0.05, 0.03, 0.08), Palette.BEAK, _t(0.0, 0.14, 0.24))
	mb.add_pyramid(0.05, 0.1, 4, Palette.DUCK, Transform3D(Basis(Vector3.RIGHT, -1.2), Vector3(0.0, 0.06, -0.18)))
	root.add_child(mb.commit_instance("Body"))
	return root
