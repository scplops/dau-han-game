class_name Football
extends Node3D
## Sân bóng làng (mục 17): bãi cỏ loang lổ đất, vạch vôi, khung thành tre, cờ góc, ghế băng,
## bảng tỉ số gỗ, cây bàng che nắng. Quả bóng có vật lý đơn giản (nảy, lăn, chạm cột, vào lưới).
## Dân làng (trẻ con, thanh niên) chiều chiều ra đá: chia hai đội Xóm Đông (mặc áo, vòng đỏ) –
## Xóm Đoài (cởi trần, vòng xanh) như đá bóng làng ngày xưa; con gái luôn vào đội mặc áo; người thừa, cụ già đứng xem. Người xem bấm vào bóng để sút.
## Dựng sau `Village` (lấy `pitch_rect`), đứng sau `Villagers` trong cây scene để điều khiển
## cầu thủ SAU khi Villagers đã tick xong mỗi khung.

enum Phase { IDLE, KICKOFF, PLAY, GOAL }

const TEAM_NAMES: Array[String] = ["Xóm Đông", "Xóm Đoài"]
## Đội cởi trần (cởi áo khi vào sân, mặc lại khi ra).
const SHIRTLESS_TEAM := 1
## Vị trí đội hình (tỉ lệ dọc sân tính từ khung thành nhà, tỉ lệ ngang sân).
const FORMATION: Array[Vector2] = [Vector2(0.3, 0.5), Vector2(0.38, 0.22), Vector2(0.38, 0.78),
		Vector2(0.58, 0.36), Vector2(0.58, 0.64), Vector2(0.72, 0.5)]

@export var village: Village
@export var villagers: Villagers
@export var random_seed: int = 1717

@export_group("Sân")
@export var goal_width: float = 3.6
@export var goal_height: float = 1.8
@export var goal_depth: float = 1.0
@export var line_width: float = 0.12

@export_group("Trận đấu")
@export_range(2, 16) var max_players: int = 12
## Một trận kéo dài bao lâu (giây thật), xong thì mọi người tản đi.
@export var match_length: float = 240.0
@export var ball_radius: float = 0.13
@export var rolling_friction: float = 3.2
@export var user_kick_speed: float = 12.0

var rect: Rect2
var score: Array[int] = [0, 0]
var phase: Phase = Phase.IDLE
var players: Array[Dictionary] = []   # {v, team, keeper, slot, cool, kick_t, run}

var _rng := RandomNumberGenerator.new()
var _ball: Node3D
var _ball_spin: Node3D
var _ball_pos := Vector3.ZERO
var _ball_vel := Vector3.ZERO
var _phase_timer: float = 0.0
var _match_timer: float = 0.0
var _restart_timer: float = -1.0
var _restart_pos := Vector3.ZERO
var _kickoff_team: int = 0
var _score_labels: Array[Label3D] = []
var _goal_label: Label3D
var _discs: Array[CylinderMesh] = []
var _touch_gap: float = 0.0      # nhịp ngắn sau mỗi cú chạm: bóng phải rời chân rồi người khác mới chạm


func build() -> void:
	_rng.seed = random_seed
	rect = village.pitch_rect if village != null else Rect2(-62, -154, 30, 18)
	var ground := MeshBuilder.new(random_seed, 0.025)
	var stat := MeshBuilder.new(random_seed + 1, 0.04)
	stat.contact_shade_height = 0.4
	var leaves := MeshBuilder.new(random_seed + 2, 0.06)
	_build_ground(ground)
	_build_lines(ground)
	for s: float in [-1.0, 1.0]:
		_build_goal(stat, s)
	_build_furniture(stat, leaves)
	var g := ground.commit_instance("PitchGround")
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	add_child(stat.commit_instance("PitchProps"))
	add_child(leaves.commit_instance("PitchTrees", MeshBuilder.wind_material(0.1, 2.0, 6.0, 0.9)))
	_build_scoreboard()
	_build_ball()
	for col: Color in [Palette.FLAG_RED, Palette.SIGN_BLUE]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.36
		cm.bottom_radius = 0.36
		cm.height = 0.02
		cm.radial_segments = 12
		cm.rings = 1
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(col.lightened(0.15), 0.85)
		cm.material = mat
		_discs.append(cm)
	_place_ball(center3())
	print("Football: sân %dx%d m tại (%d, %d)" % [int(rect.size.x), int(rect.size.y), int(rect.get_center().x), int(rect.get_center().y)])


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


func center3() -> Vector3:
	var c := rect.get_center()
	return Vector3(c.x, 0.0, c.y)


## Chỗ đứng xem bên đường biên dọc phía nam (giáp ngõ).
func gather_spot(rng: RandomNumberGenerator) -> Vector3:
	var rect := village.pitch_rect   # Villagers có thể hỏi trước khi Football.build() chạy
	return Vector3(rng.randf_range(rect.position.x + 2.0, rect.end.x - 2.0), 0.05, rect.end.y + rng.randf_range(1.2, 2.2))


# --- Dựng sân ---------------------------------------------------------------------------

## Nền: lưới ô 2 m, cỏ mòn thành đất ở khung thành và giữa sân.
func _build_ground(mb: MeshBuilder) -> void:
	var r := rect.grow(1.6)
	var cell := 2.0
	var c := rect.get_center()
	var y := 0.025
	var nx := int(ceil(r.size.x / cell))
	var nz := int(ceil(r.size.y / cell))
	for i in nx:
		for j in nz:
			var x0 := r.position.x + i * r.size.x / nx
			var x1 := r.position.x + (i + 1) * r.size.x / nx
			var z0 := r.position.y + j * r.size.y / nz
			var z1 := r.position.y + (j + 1) * r.size.y / nz
			var m := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var goal_d := minf(m.distance_to(Vector2(rect.position.x + 1.5, c.y)), m.distance_to(Vector2(rect.end.x - 1.5, c.y)))
			var wear := maxf(1.0 - goal_d / 5.0, 0.0) + maxf(1.0 - m.distance_to(c) / 4.0, 0.0) * 0.6
			wear = clampf(wear + _rng.randf_range(-0.05, 0.12), 0.0, 1.0)
			var col := Palette.GRASS.lerp(Palette.DIKE, 0.2).lerp(Palette.EARTH, wear * 0.8)
			mb.add_quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), col, Vector3(m.x, -1, m.y))


## Vạch vôi: biên, giữa sân, vòng tròn giữa, vùng cấm nhỏ, chấm phạt đền (hơi xiêu vẹo).
func _build_lines(mb: MeshBuilder) -> void:
	var r := rect
	var c := r.get_center()
	var segs: Array = [
		[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
		[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position],
		[Vector2(c.x, r.position.y), Vector2(c.x, r.end.y)],
	]
	for s: float in [-1.0, 1.0]:
		var gx := c.x + s * r.size.x * 0.5
		var bx := gx - s * 3.0
		segs.append([Vector2(gx, c.y - 3.5), Vector2(bx, c.y - 3.5)])
		segs.append([Vector2(bx, c.y - 3.5), Vector2(bx, c.y + 3.5)])
		segs.append([Vector2(bx, c.y + 3.5), Vector2(gx, c.y + 3.5)])
		_line_dot(mb, Vector2(gx - s * 5.0, c.y), 0.14)
	for k in 24:
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		segs.append([c + Vector2(cos(a0), sin(a0)) * 3.0, c + Vector2(cos(a1), sin(a1)) * 3.0])
	_line_dot(mb, c, 0.16)
	for sg: Array in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var wob := Vector2(_rng.randf_range(-0.04, 0.04), _rng.randf_range(-0.04, 0.04))
		var d := (b - a).normalized().orthogonal() * line_width * 0.5
		var y := 0.04
		var a2 := a + wob
		var b2 := b + wob * 0.5
		mb.add_quad(Vector3(a2.x - d.x, y, a2.y - d.y), Vector3(b2.x - d.x, y, b2.y - d.y),
				Vector3(b2.x + d.x, y, b2.y + d.y), Vector3(a2.x + d.x, y, a2.y + d.y), Palette.SCHOOL_TRIM,
				Vector3(a.x, -1, a.y))


func _line_dot(mb: MeshBuilder, p: Vector2, r: float) -> void:
	mb.add_prism(r, r, 0.016, 8, Palette.SCHOOL_TRIM, _t(p.x, 0.03, p.y))


## Khung thành tre: hai cột, xà ngang, khung sau, lưới cước thưa.
func _build_goal(mb: MeshBuilder, s: float) -> void:
	var c := rect.get_center()
	var gx := c.x + s * rect.size.x * 0.5
	var hw := goal_width * 0.5
	var h := goal_height
	var d := goal_depth
	var pole := Palette.BAMBOO_STEM.lightened(0.15)
	var net := Palette.FLOWER_WHITE.darkened(0.12)
	for e: float in [-1.0, 1.0]:
		var z := c.y + e * hw
		mb.add_prism(0.06, 0.055, h + 0.04, 6, pole, _t(gx, 0.0, z))
		mb.add_limb(Vector3(gx, h, z), Vector3(gx + s * d, h * 0.7, z), 0.03, 0.03, 5, pole)
		mb.add_limb(Vector3(gx + s * d, 0.0, z), Vector3(gx + s * d, h * 0.7, z), 0.03, 0.03, 5, pole)
		mb.add_limb(Vector3(gx, 0.02, z), Vector3(gx + s * d, 0.02, z), 0.025, 0.025, 4, pole)
	mb.add_limb(Vector3(gx, h, c.y - hw), Vector3(gx, h, c.y + hw), 0.055, 0.055, 6, pole)
	mb.add_limb(Vector3(gx + s * d, h * 0.7, c.y - hw), Vector3(gx + s * d, h * 0.7, c.y + hw), 0.03, 0.03, 5, pole)
	mb.add_limb(Vector3(gx + s * d, 0.02, c.y - hw), Vector3(gx + s * d, 0.02, c.y + hw), 0.025, 0.025, 4, pole)
	# Lưới: dây dọc mặt sau + mặt trên, dây ngang mặt sau
	var n := 9
	for k in n + 1:
		var z := c.y - hw + goal_width * k / n
		mb.add_limb(Vector3(gx + s * d, 0.02, z), Vector3(gx + s * d, h * 0.7, z), 0.007, 0.007, 3, net)
		mb.add_limb(Vector3(gx, h, z), Vector3(gx + s * d, h * 0.7, z), 0.007, 0.007, 3, net)
	for k in range(1, 5):
		var y := h * 0.7 * k / 5.0
		mb.add_limb(Vector3(gx + s * d, y, c.y - hw), Vector3(gx + s * d, y, c.y + hw), 0.007, 0.007, 3, net)
	for e: float in [-1.0, 1.0]:
		var z := c.y + e * hw
		for k in range(1, 4):
			var t := k / 4.0
			mb.add_limb(Vector3(gx + s * d * t, 0.02, z), Vector3(gx + s * d * t, lerpf(h, h * 0.7, t), z), 0.007, 0.007, 3, net)


## Cờ góc, ghế băng tre, cây bàng, xe đạp dựng, đống rơm.
func _build_furniture(mb: MeshBuilder, leaves: MeshBuilder) -> void:
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		mb.add_prism(0.025, 0.02, 1.3, 5, Palette.BAMBOO_STEM, _t(corner.x, 0.0, corner.y))
		mb.add_triangle(Vector3(corner.x, 1.3, corner.y), Vector3(corner.x, 1.0, corner.y),
				Vector3(corner.x + 0.38, 1.18, corner.y + 0.05), Palette.FLAG_RED, Vector3(corner.x, 1.15, corner.y - 1.0))
		mb.add_triangle(Vector3(corner.x, 1.3, corner.y), Vector3(corner.x, 1.0, corner.y),
				Vector3(corner.x + 0.38, 1.18, corner.y + 0.05), Palette.FLAG_RED, Vector3(corner.x, 1.15, corner.y + 1.0))
	# Ghế băng tre phía bắc (hai bên bảng tỉ số)
	var c := rect.get_center()
	for s: float in [-1.0, 1.0]:
		var bx := c.x + s * 6.5
		var bz := rect.position.y - 1.6
		mb.add_box(Vector3(2.6, 0.06, 0.38), Palette.BAMBOO_STEM.lightened(0.1), _t(bx, 0.42, bz))
		for lx: float in [-1.1, 1.1]:
			for lz: float in [-0.14, 0.14]:
				mb.add_box(Vector3(0.05, 0.42, 0.05), Palette.BAMBOO_NODE, _t(bx + lx, 0.0, bz + lz))
	# Cây bàng hai đầu sân phía bắc
	for p: Vector2 in [Vector2(rect.position.x - 3.0, rect.position.y - 2.5), Vector2(rect.end.x - 1.0, rect.position.y - 3.5)]:
		_bang(mb, leaves, Vector3(p.x, 0.0, p.y))
	# Đống rơm góc tây nam
	var hay := _t(rect.position.x - 3.2, 0.0, rect.end.y + 1.5)
	mb.add_prism(1.3, 1.1, 0.9, 9, Palette.STRAW, hay)
	mb.add_prism(1.1, 0.12, 1.1, 9, Palette.STRAW.darkened(0.08), hay * _t(0, 0.9, 0))
	mb.add_limb(Vector3(0, 1.8, 0), Vector3(0, 2.4, 0), 0.03, 0.02, 4, Palette.WOOD, hay)
	# Hai xe đạp dựng cạnh ghế
	for k in 2:
		_bicycle(mb, _t(c.x + 9.8 + k * 0.7, 0.0, rect.position.y - 1.2) * Transform3D(Basis(Vector3.UP, 0.15 + k * 0.1), Vector3.ZERO))


func _bang(mb: MeshBuilder, leaves: MeshBuilder, p: Vector3) -> void:
	var xf := Transform3D(Basis(), p)
	mb.add_prism(0.28, 0.18, 5.4, 7, Palette.BANYAN_TRUNK, xf)
	for t in 3:
		var y := 2.3 + t * 1.3
		var r := 3.0 - t * 0.8
		for i in 5:
			var a := TAU * i / 5.0 + t * 0.6
			mb.add_limb(Vector3(0, y, 0), Vector3(cos(a) * r * 0.8, y + 0.15, sin(a) * r * 0.8), 0.08, 0.04, 4, Palette.BANYAN_TRUNK, xf)
		leaves.add_prism(r, r * 0.8, 0.45, 9, Palette.BANYAN_LEAF_1 if t % 2 == 0 else Palette.BAMBOO_LEAF, xf * _t(0, y + 0.1, 0), _rng.randf())


func _bicycle(mb: MeshBuilder, xf: Transform3D) -> void:
	var dark := Palette.WINDOW_DARK
	for z: float in [-0.5, 0.5]:
		mb.add_prism(0.33, 0.33, 0.04, 10, dark, xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.02, 0.33, z)))
	mb.add_limb(Vector3(0, 0.33, -0.5), Vector3(0, 0.62, 0.0), 0.02, 0.02, 4, Palette.SIGN_BLUE, xf)
	mb.add_limb(Vector3(0, 0.62, 0.0), Vector3(0, 0.66, 0.42), 0.02, 0.02, 4, Palette.SIGN_BLUE, xf)
	mb.add_limb(Vector3(0, 0.66, 0.42), Vector3(0, 0.33, 0.5), 0.02, 0.02, 4, Palette.SIGN_BLUE, xf)
	mb.add_limb(Vector3(0, 0.33, -0.5), Vector3(0, 0.33, 0.0), 0.02, 0.02, 4, Palette.SIGN_BLUE, xf)
	mb.add_box(Vector3(0.1, 0.04, 0.22), dark, xf * _t(0, 0.66, -0.05))
	mb.add_limb(Vector3(-0.22, 0.86, 0.42), Vector3(0.22, 0.86, 0.42), 0.015, 0.015, 4, dark, xf)
	mb.add_limb(Vector3(0, 0.66, 0.42), Vector3(0, 0.86, 0.42), 0.015, 0.015, 4, dark, xf)


## Bảng tỉ số gỗ giữa phía bắc: tên hai xóm + tỉ số viết phấn.
func _build_scoreboard() -> void:
	var c := rect.get_center()
	var bz := rect.position.y - 2.4
	var mb := MeshBuilder.new(random_seed + 5, 0.04)
	for s: float in [-1.0, 1.0]:
		mb.add_prism(0.05, 0.045, 2.3, 5, Palette.BAMBOO_STEM, _t(c.x + s * 1.3, 0.0, bz))
	mb.add_box(Vector3(2.9, 1.0, 0.07), Palette.BLACKBOARD, _t(c.x, 1.15, bz + 0.05))
	mb.add_box(Vector3(3.0, 0.08, 0.1), Palette.WOOD, _t(c.x, 2.15, bz + 0.05))
	mb.add_box(Vector3(3.0, 0.08, 0.1), Palette.WOOD, _t(c.x, 1.11, bz + 0.05))
	add_child(mb.commit_instance("Scoreboard"))
	var font := load("res://assets/fonts/BeVietnamPro-SemiBold.ttf") as Font
	# Hàng trên: tên hai xóm; hàng dưới: tỉ số to giữa bảng
	var specs: Array = [[-0.7, 1.88, Palette.FLAG_RED.lightened(0.35), 30, TEAM_NAMES[0]],
			[0.0, 1.42, Palette.SCHOOL_TRIM, 64, "0 - 0"],
			[0.7, 1.88, Palette.SIGN_BLUE.lightened(0.5), 30, TEAM_NAMES[1]]]
	for sp: Array in specs:
		var l := Label3D.new()
		l.font = font
		l.font_size = sp[3]
		l.pixel_size = 0.006
		l.modulate = sp[2]
		l.text = sp[4]
		l.outline_size = 0
		l.position = Vector3(c.x + float(sp[0]), float(sp[1]), bz + 0.1)
		add_child(l)
		_score_labels.append(l)
	_goal_label = Label3D.new()
	_goal_label.font = font
	_goal_label.font_size = 96
	_goal_label.pixel_size = 0.01
	_goal_label.modulate = Palette.FLOWER_YELLOW
	_goal_label.outline_modulate = Palette.WINDOW_DARK
	_goal_label.outline_size = 18
	_goal_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_goal_label.no_depth_test = true
	_goal_label.text = "VÀO!"
	_goal_label.visible = false
	add_child(_goal_label)


func _build_ball() -> void:
	_ball = Node3D.new()
	_ball.name = "Ball"
	add_child(_ball)
	_ball_spin = Node3D.new()
	_ball.add_child(_ball_spin)
	var mb := MeshBuilder.new(random_seed + 9, 0.02)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var r := ball_radius
	mb.add_blob(Vector3(r, r, r), Palette.FLOWER_WHITE, rng, 0.05, _t(0, -r, 0))
	# Các mảng đen ngũ giác trên bề mặt
	for d: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var axis := Vector3.UP.cross(d)
		var b := Basis() if axis.length() < 0.01 else Basis(axis.normalized(), Vector3.UP.angle_to(d))
		mb.add_prism(r * 0.42, r * 0.42, 0.012, 5, Palette.WINDOW_DARK, Transform3D(b, d * r * 0.96))
	var mi := mb.commit_instance("BallMesh")
	_ball_spin.add_child(mi)
	var target := HouseEntry.make_click_target(_ball, Transform3D.IDENTITY, Vector3(0.7, 0.7, 0.7), "Sút bóng  ·  bấm chuột")
	target.set_meta("activate", user_kick)
	target.add_to_group(HouseEntry.ACTIVATE_GROUP)


func _place_ball(p: Vector3) -> void:
	_ball_pos = Vector3(p.x, ball_radius, p.z)
	_ball_vel = Vector3.ZERO
	_ball.global_position = _ball_pos


func _update_score() -> void:
	_score_labels[1].text = "%d - %d" % [score[0], score[1]]


# --- Người xem sút bóng -----------------------------------------------------------------

## Bấm vào bóng: sút bay ra xa phía camera đang nhìn.
func user_kick() -> void:
	var cam := get_viewport().get_camera_3d()
	var dir := Vector3(0, 0, -1)
	if cam != null:
		dir = _ball_pos - cam.global_position
		dir.y = 0.0
		dir = dir.normalized()
	_kick(dir, user_kick_speed * _rng.randf_range(0.9, 1.1), _rng.randf_range(2.5, 4.5))


func _kick(dir: Vector3, speed: float, lift: float) -> void:
	_ball_vel = dir.normalized() * speed + Vector3(0, lift, 0)
	_ball_pos.y = maxf(_ball_pos.y, ball_radius + 0.02)


# --- Cầu thủ ----------------------------------------------------------------------------

## Villagers gọi khi một người tới sân. Trả về true nếu vào đá, false nếu đứng xem.
func arrive(v: Villager) -> bool:
	var can_play: bool = v.role == "kid" or (v.role == "farmer" and not v.get_meta("female", false))
	if not can_play or players.size() >= max_players or _find(v) >= 0:
		v.work_anim = "play" if v.role == "kid" else "chat"
		v.activity_text = "đang xem đá bóng"
		var d := center3() - v.global_position
		v.rotation.y = atan2(d.x, d.z)
		return false
	var counts := [0, 0]
	for p in players:
		counts[int(p.team)] += 1
	var team := 0 if counts[0] <= counts[1] else 1
	if v.get_meta("female", false):
		team = 1 - SHIRTLESS_TEAM     # con gái luôn vào đội mặc áo
	var disc := MeshInstance3D.new()
	disc.name = "TeamDisc"
	disc.mesh = _discs[team]
	disc.position.y = 0.03
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(disc)
	if v.prop_node != null:
		v.prop_node.visible = false      # dựng cuốc bên lề rồi mới vào sân
	if team == SHIRTLESS_TEAM:
		v.set_meta("outfit_before", v.outfit)
		v.add_shirtless()
		v.wear("shirtless")
	var run := clampf(v.speed * (2.0 if v.role == "kid" else 2.5), 2.6, 4.2)
	players.append({"v": v, "team": team, "keeper": false, "slot": 0, "cool": 0.0, "kick_t": 0.0,
			"run": run, "disc": disc, "wander": _rng.randf() * TAU})
	v.dwell = 1.0e6     # Football quyết định khi nào xong
	v.work_anim = "idle"
	v.activity_text = "đang đá bóng cho %s%s" % [TEAM_NAMES[team], " (cởi trần)" if team == SHIRTLESS_TEAM else ""]
	_assign_roles()
	if phase == Phase.IDLE and players.size() >= 2:
		_start_match()
	return true


func _find(v: Villager) -> int:
	for i in players.size():
		if players[i].v == v:
			return i
	return -1


func _remove(i: int, release: bool) -> void:
	var p: Dictionary = players[i]
	var v: Villager = p.v
	if is_instance_valid(p.disc):
		(p.disc as Node).queue_free()
	if is_instance_valid(v) and v.prop_node != null:
		v.prop_node.visible = true
	if is_instance_valid(v) and v.outfit == "shirtless":
		v.wear(str(v.get_meta("outfit_before", "casual")))   # mặc áo lại
	if release and is_instance_valid(v):
		v.dwell = _rng.randf_range(0.5, 3.0)
		v.speed_mul = 1.0
		v.work_anim = "chat"
		v.activity_text = "đá bóng xong, đang nghỉ"
	players.remove_at(i)
	_assign_roles()


## Thủ môn: người vào sân sớm nhất của đội khi đội có từ 4 người; còn lại xếp theo đội hình.
func _assign_roles() -> void:
	for team in 2:
		var mine: Array[Dictionary] = []
		for p in players:
			if int(p.team) == team:
				mine.append(p)
		var slot := 0
		for k in mine.size():
			mine[k].keeper = k == 0 and mine.size() >= 4
			if not mine[k].keeper:
				mine[k].slot = slot
				slot += 1


func _start_match() -> void:
	score = [0, 0]
	_update_score()
	_match_timer = match_length
	_kickoff_team = _rng.randi_range(0, 1)
	_begin_kickoff()


func _begin_kickoff() -> void:
	phase = Phase.KICKOFF
	_phase_timer = 2.0
	_restart_timer = -1.0
	_place_ball(center3())


func _end_match() -> void:
	phase = Phase.IDLE
	while not players.is_empty():
		_remove(players.size() - 1, true)


# --- Mỗi khung hình ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ball == null or not is_visible_in_tree():
		return
	# Đồng bộ danh sách: ai đã bỏ đi (trời tối, giông, Villagers đổi việc) thì bỏ khỏi đội
	for i in range(players.size() - 1, -1, -1):
		var v: Villager = players[i].v
		if not is_instance_valid(v) or v.activity != "football" or v.state != Villager.State.IDLE or not v.visible:
			_remove(i, false)
	if phase != Phase.IDLE and players.size() < 2:
		phase = Phase.IDLE
	var dt := minf(delta, 0.05)
	_step(dt)
	_apply_visuals(dt)


## Một bước mô phỏng (dùng chung cho chạy thật và chạy trước khi chụp ảnh).
func _step(dt: float) -> void:
	_step_ball(dt)
	match phase:
		Phase.KICKOFF:
			_phase_timer -= dt
			_move_players(dt, true)
			if _phase_timer <= 0.0:
				phase = Phase.PLAY
				var dir := Vector3(1.0 if _kickoff_team == 0 else -1.0, 0, _rng.randf_range(-0.6, 0.6))
				_kick(dir, 4.0, 0.0)
		Phase.PLAY:
			_match_timer -= dt
			_move_players(dt, false)
			_try_kicks()
			if _match_timer <= 0.0:
				_end_match()
		Phase.GOAL:
			_phase_timer -= dt
			_move_players(dt, true)
			if _phase_timer <= 0.0:
				_begin_kickoff()
	_touch_gap = maxf(_touch_gap - dt, 0.0)
	for p in players:
		p.cool = maxf(float(p.cool) - dt, 0.0)
		p.kick_t = maxf(float(p.kick_t) - dt, 0.0)


func _attack_dir(team: int) -> float:
	return 1.0 if team == 0 else -1.0


func _own_goal_x(team: int) -> float:
	return rect.position.x if team == 0 else rect.end.x


func _home_point(p: Dictionary) -> Vector2:
	var team := int(p.team)
	var dir := _attack_dir(team)
	var c := rect.get_center()
	if p.keeper:
		return Vector2(_own_goal_x(team) + dir * 0.8, clampf(_ball_pos.z, c.y - 1.5, c.y + 1.5))
	var f: Vector2 = FORMATION[int(p.slot) % FORMATION.size()]
	var x := _own_goal_x(team) + dir * f.x * rect.size.x + (_ball_pos.x - c.x) * 0.45
	var z := rect.position.y + f.y * rect.size.y + (_ball_pos.z - c.y) * 0.2
	# Đội hình lặp lại thì lệch ra cho khỏi đứng chồng
	if int(p.slot) >= FORMATION.size():
		z += 2.5
	return Vector2(clampf(x, rect.position.x + 0.5, rect.end.x - 0.5), clampf(z, rect.position.y + 0.5, rect.end.y - 0.5))


func _move_players(dt: float, formation_only: bool) -> void:
	var ball2 := Vector2(_ball_pos.x, _ball_pos.z) + Vector2(_ball_vel.x, _ball_vel.z) * 0.25
	# Người gần bóng nhất mỗi đội lao vào bóng, người thứ hai chạy đỡ
	var chasers: Array = [null, null]
	var support: Array = [null, null]
	if not formation_only:
		var best := [INF, INF]
		var second := [INF, INF]
		for p in players:
			if p.keeper:
				continue
			var t := int(p.team)
			var d := Vector2(p.v.global_position.x, p.v.global_position.z).distance_to(ball2)
			if d < best[t]:
				second[t] = best[t]
				support[t] = chasers[t]
				best[t] = d
				chasers[t] = p
			elif d < second[t]:
				second[t] = d
				support[t] = p
	for p in players:
		var v: Villager = p.v
		var pos := Vector2(v.global_position.x, v.global_position.z)
		var team := int(p.team)
		var goal := Vector2(rect.end.x if team == 0 else rect.position.x, rect.get_center().y)
		var target := _home_point(p)
		var urgent := false
		if not formation_only:
			if p == chasers[team]:
				var to_goal := (goal - ball2).normalized()
				target = ball2 - to_goal * 0.35
				urgent = true
			elif p == support[team]:
				target = ball2 + Vector2(_attack_dir(team) * 5.0, (1.0 if pos.y > ball2.y else -1.0) * 3.0)
			elif p.keeper and ball2.distance_to(pos) < 4.0 and absf(ball2.x - _own_goal_x(team)) < 6.0:
				target = ball2
				urgent = true
		if phase == Phase.KICKOFF and not p.keeper:
			# Giao bóng: hai đội về phần sân nhà
			target.x = minf(target.x, rect.get_center().x - 1.0) if team == 0 else maxf(target.x, rect.get_center().x + 1.0)
		# Lững thững khi đứng chờ
		p.wander = float(p.wander) + dt * 0.7
		if not urgent:
			target += Vector2(sin(float(p.wander)), cos(float(p.wander) * 0.8)) * 0.6
		var to := target - pos
		var dist := to.length()
		var speed: float = p.run if urgent or dist > 4.0 else minf(1.3, float(p.run))
		if p.keeper:
			speed *= 0.75          # thủ môn làng phản xạ chậm
		if phase == Phase.GOAL:
			speed = 0.0
		var step := minf(speed * dt, dist)
		var move := to / dist * step if dist > 0.05 else Vector2.ZERO
		# Đẩy nhau ra khi đứng sát
		for q in players:
			if q == p:
				continue
			var qp := Vector2(q.v.global_position.x, q.v.global_position.z)
			var sep := pos - qp
			if sep.length() < 0.7 and sep.length() > 0.001:
				move += sep.normalized() * (0.7 - sep.length()) * dt * 4.0
		pos += move
		v.global_position = Vector3(pos.x, v.global_position.y, pos.y)
		var face := move if move.length() > 0.002 else (ball2 - pos)
		if face.length() > 0.01:
			v._face(Vector3(face.x, 0, face.y).normalized(), dt)
		var amount := clampf(move.length() / maxf(dt, 0.001) / float(p.run), 0.0, 1.0)
		p.amount = amount
		v.speed_mul = 1.0 + amount
		v._walk_amount = move_toward(v._walk_amount, amount, dt * 6.0)


func _try_kicks() -> void:
	if _ball_pos.y > 0.55 or _restart_timer >= 0.0 or _touch_gap > 0.0:
		return
	var order := range(players.size())
	order.shuffle()
	for i: int in order:
		var p: Dictionary = players[i]
		if float(p.cool) > 0.0:
			continue
		var v: Villager = p.v
		var pos := Vector2(v.global_position.x, v.global_position.z)
		var ball2 := Vector2(_ball_pos.x, _ball_pos.z)
		if pos.distance_to(ball2) > 0.6:
			continue
		var team := int(p.team)
		var dir := _attack_dir(team)
		# Nhắm khung thành, đôi khi chệch cột
		var goal := Vector2(rect.end.x if team == 0 else rect.position.x, rect.get_center().y + _rng.randf_range(-2.6, 2.6))
		var to_goal := goal - ball2
		var aim: Vector2
		var speed: float
		var lift: float
		if p.keeper:
			# Thủ môn phát bóng dài ra một cánh
			aim = Vector2(dir, (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.4, 0.9))
			speed = _rng.randf_range(9.0, 11.0)
			lift = _rng.randf_range(3.0, 4.5)
		elif to_goal.length() < 14.0 and _rng.randf() < 0.8:
			aim = to_goal                      # sút
			speed = _rng.randf_range(9.0, 13.0)
			lift = _rng.randf_range(0.3, 1.8)
		else:
			var mate := _pass_target(p, ball2)
			if mate != Vector2.INF and _rng.randf() < 0.4:
				aim = mate - ball2             # chuyền
				speed = clampf(aim.length() * 1.1 + 2.0, 5.0, 10.0)
				lift = 0.4 if aim.length() < 9.0 else 2.0
			else:
				# Dẫn bóng: lách sang phía không có đối phương
				var away := _rng.randf_range(0.15, 0.6) * _dodge_side(p, ball2)
				aim = to_goal.normalized().rotated(away * dir)
				speed = _rng.randf_range(4.0, 5.5)
				lift = 0.0
		_kick(Vector3(aim.x, 0, aim.y), speed, lift)
		p.cool = 0.5
		p.kick_t = 0.35
		_touch_gap = 0.3
		return


## Phía (−1 / +1) để lách: ngược với đối phương gần nhất.
func _dodge_side(p: Dictionary, ball2: Vector2) -> float:
	var best := INF
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var dir := _attack_dir(int(p.team))
	for q in players:
		if int(q.team) == int(p.team):
			continue
		var qp := Vector2(q.v.global_position.x, q.v.global_position.z)
		var d := qp.distance_to(ball2)
		if d < best and d < 4.0:
			best = d
			side = -signf((qp.y - ball2.y) * dir) if absf(qp.y - ball2.y) > 0.05 else side
	return side


## Đồng đội ở phía trên (gần khung thành đối phương hơn) trong tầm chuyền.
func _pass_target(p: Dictionary, ball2: Vector2) -> Vector2:
	var team := int(p.team)
	var dir := _attack_dir(team)
	var best := Vector2.INF
	var best_gain := 2.0
	for q in players:
		if q == p or int(q.team) != team or q.keeper:
			continue
		var qp := Vector2(q.v.global_position.x, q.v.global_position.z)
		var gain := (qp.x - ball2.x) * dir
		if gain > best_gain and qp.distance_to(ball2) < 15.0:
			best_gain = gain
			best = qp + Vector2(dir * 1.0, 0)
	return best


# --- Bóng -------------------------------------------------------------------------------

func _step_ball(dt: float) -> void:
	var prev := _ball_pos
	_ball_vel.y -= 9.8 * dt
	_ball_pos += _ball_vel * dt
	var r := ball_radius
	if _ball_pos.y <= r:
		_ball_pos.y = r
		if _ball_vel.y < 0.0:
			_ball_vel.y = -_ball_vel.y * 0.45
			_ball_vel.x *= 0.8      # nảy trên đất gồ ghề mất đà
			_ball_vel.z *= 0.8
			if _ball_vel.y < 0.6:
				_ball_vel.y = 0.0
		# Lăn trên cỏ: chậm dần
		var h := Vector2(_ball_vel.x, _ball_vel.z)
		var sp := h.length()
		if sp > 0.0:
			h = h / sp * maxf(sp - rolling_friction * dt, 0.0)
			_ball_vel.x = h.x
			_ball_vel.z = h.y
	else:
		_ball_vel.x *= 1.0 - 0.15 * dt
		_ball_vel.z *= 1.0 - 0.15 * dt
	_check_goal(prev)
	# Bóng ra ngoài biên: đặt lại ở vạch sau một nhịp (ném biên / phát bóng)
	if phase == Phase.PLAY:
		if _restart_timer < 0.0 and not rect.grow(0.15).has_point(Vector2(_ball_pos.x, _ball_pos.z)):
			_restart_timer = 1.0
			var c := rect.get_center()
			if _ball_pos.x < rect.position.x or _ball_pos.x > rect.end.x:
				var s := -1.0 if _ball_pos.x < rect.position.x else 1.0
				_restart_pos = Vector3(c.x + s * (rect.size.x * 0.5 - 2.5), 0, c.y + _rng.randf_range(-2.5, 2.5))
			else:
				_restart_pos = Vector3(clampf(_ball_pos.x, rect.position.x + 0.5, rect.end.x - 0.5), 0,
						clampf(_ball_pos.z, rect.position.y + 0.3, rect.end.y - 0.3))
		elif _restart_timer >= 0.0:
			_restart_timer -= dt
			if _restart_timer < 0.0:
				_place_ball(_restart_pos)
	# Không cho bóng bay vào nhà dân: tường ảo quanh sân
	var wall := rect.grow(4.0)
	if _ball_pos.x < wall.position.x or _ball_pos.x > wall.end.x:
		_ball_pos.x = clampf(_ball_pos.x, wall.position.x, wall.end.x)
		_ball_vel.x *= -0.35
	if _ball_pos.z < wall.position.y or _ball_pos.z > wall.end.y:
		_ball_pos.z = clampf(_ball_pos.z, wall.position.y, wall.end.y)
		_ball_vel.z *= -0.35


## Bóng qua vạch cuối sân: vào lưới, chạm cột / xà bật ra, hay chỉ ra ngoài.
func _check_goal(prev: Vector3) -> void:
	var c := rect.get_center()
	for s: float in [-1.0, 1.0]:
		var gx := c.x + s * rect.size.x * 0.5
		var crossed := (prev.x - gx) * s < 0.0 and (_ball_pos.x - gx) * s >= 0.0
		if not crossed:
			continue
		var dz := absf(_ball_pos.z - c.y)
		var hw := goal_width * 0.5
		var post_hit := absf(dz - hw) < 0.12 + ball_radius and _ball_pos.y < goal_height
		var bar_hit := dz < hw and absf(_ball_pos.y - goal_height) < 0.08 + ball_radius
		if post_hit or bar_hit:
			_ball_pos.x = gx - s * (ball_radius + 0.02)
			_ball_vel.x = -_ball_vel.x * 0.5
			_ball_vel.z += _rng.randf_range(-1.5, 1.5)
			return
		if dz < hw and _ball_pos.y < goal_height:
			_ball_vel *= 0.25
			_ball_pos.x = minf(_ball_pos.x * s, (gx + s * goal_depth * 0.6) * s) * s
			if phase == Phase.PLAY:
				var team := 0 if s > 0.0 else 1
				score[team] += 1
				_update_score()
				phase = Phase.GOAL
				_phase_timer = 2.6
				_kickoff_team = 1 - team
				_goal_label.global_position = Vector3(gx, 3.2, c.y)
				_goal_label.visible = true
				_goal_label.set_meta("t", 0.0)
				for p in players:
					if int(p.team) == team:
						(p.v as Villager).work_anim = "play"
			else:
				# Ngoài trận (người xem sút vào): vẫn cho "VÀO!" vui
				_goal_label.global_position = Vector3(gx, 3.2, c.y)
				_goal_label.visible = true
				_goal_label.set_meta("t", 0.0)
			return
	# Bóng nằm trong lưới thì không lăn ra
	for s: float in [-1.0, 1.0]:
		var gx := c.x + s * rect.size.x * 0.5
		if (_ball_pos.x - gx) * s > 0.0 and absf(_ball_pos.z - c.y) < goal_width * 0.5:
			if (_ball_pos.x - gx) * s > goal_depth - ball_radius:
				_ball_pos.x = gx + s * (goal_depth - ball_radius)
				_ball_vel.x = -_ball_vel.x * 0.2


func _apply_visuals(dt: float) -> void:
	_ball.global_position = _ball_pos
	var hv := Vector3(_ball_vel.x, 0, _ball_vel.z)
	if hv.length() > 0.05:
		var axis := Vector3.UP.cross(hv.normalized())
		_ball_spin.rotate(axis, hv.length() / ball_radius * dt)
	if _goal_label.visible:
		var t := float(_goal_label.get_meta("t", 0.0)) + dt
		_goal_label.set_meta("t", t)
		var k := minf(t / 0.25, 1.0)
		_goal_label.scale = Vector3.ONE * (0.4 + 0.6 * ease(k, 0.4))
		_goal_label.position.y = 3.2 + t * 0.3
		if t > 2.2:
			_goal_label.visible = false
	# Dáng sút: đá chân phải ra trước; đội vừa ghi bàn nhảy mừng
	for p in players:
		var v: Villager = p.v
		if float(p.kick_t) > 0.0 and v.legs.size() == 2:
			v.legs[1].rotation.x = -1.3 * sin(float(p.kick_t) / 0.35 * PI)
		if phase != Phase.GOAL and v.work_anim == "play":
			v.work_anim = "idle"


# --- Công cụ chụp ảnh -------------------------------------------------------------------

## Đưa ngay `n` người ra sân và cho đá trước `seconds` giây (chụp ảnh không phải chờ).
func debug_match(n: int, seconds: float = 6.0) -> void:
	if villagers == null:
		return
	var picked := 0
	for v in villagers.people:
		if picked >= n:
			break
		if not (v.role == "kid" or (v.role == "farmer" and not v.get_meta("female", false))):
			continue
		v.activity = "football"
		v.state = Villager.State.IDLE
		v.visible = true
		v.path = PackedVector3Array()
		v.global_position = Vector3(_rng.randf_range(rect.position.x + 2, rect.end.x - 2), 0.05, _rng.randf_range(rect.position.y + 2, rect.end.y - 2))
		v.set_meta("at_home", false)
		if arrive(v):
			picked += 1
	for i in int(seconds * 60.0):
		_step(1.0 / 60.0)
	_apply_visuals(0.0)
