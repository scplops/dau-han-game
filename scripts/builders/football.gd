class_name Football
extends Node3D
## Sân bóng làng (mục 17): bãi cỏ loang lổ đất, vạch vôi, khung thành tre, cờ góc, ghế băng,
## bảng tỉ số gỗ, cây bàng che nắng. Quả bóng có vật lý đơn giản (nảy, lăn, chạm cột, vào lưới).
## Dân làng (trẻ con, thanh niên) chiều chiều ra đá: chia hai đội Xóm Đông (mặc áo, vòng đỏ) –
## Xóm Đoài (cởi trần, vòng xanh) như đá bóng làng ngày xưa; con gái luôn vào đội mặc áo; người thừa, cụ già đứng xem. Người xem bấm vào bóng để sút.
## Dựng sau `Village` (lấy `pitch_rect`), đứng sau `Villagers` trong cây scene để điều khiển
## cầu thủ SAU khi Villagers đã tick xong mỗi khung.
## Người nhập vai vào đá được (mục 17b): đứng trên sân nhấn E "Xin vào đá" → vào đội ít người hơn (sân
## vắng thì gọi trẻ con / thanh niên quanh làng ra). Giữ chuột trái lấy lực rồi thả để sút, chuột phải
## chuyền cho đồng đội theo hướng nhìn, Q gọi đồng đội chuyền cho mình, chạy vào bóng để dẫn.
## Luật: 2 hiệp đổi sân, giao bóng giữa sân, ném biên, phát bóng lên, phạt góc, phạm lỗi → đá phạt
## (trong vòng cấm → phạt đền), hết giờ. Đá làng không có việt vị.

## Có bàn thắng (`by_player`: người nhập vai chạm bóng cuối cùng).
signal goal_scored(team: int, by_player: bool)

enum Phase { IDLE, KICKOFF, PLAY, GOAL, RESTART, HALFTIME, FULLTIME }

const TEAM_NAMES: Array[String] = ["Xóm Đông", "Xóm Đoài"]
## Đội cởi trần (cởi áo khi vào sân, mặc lại khi ra).
const SHIRTLESS_TEAM := 1
## Vị trí đội hình (tỉ lệ dọc sân tính từ khung thành nhà, tỉ lệ ngang sân).
const FORMATION: Array[Vector2] = [Vector2(0.3, 0.5), Vector2(0.38, 0.22), Vector2(0.38, 0.78),
		Vector2(0.58, 0.36), Vector2(0.58, 0.64), Vector2(0.72, 0.5)]

@export var village: Village
@export var villagers: Villagers
@export var first_person: FirstPerson
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

@export_group("Luật")
@export var halftime_seconds: float = 6.0
## Bóng ra ngoài bao lâu thì đặt lại (ném biên, phát bóng, phạt góc).
@export var restart_delay: float = 0.9
## Xác suất một pha tranh bóng của máy thành phạm lỗi.
@export var foul_chance: float = 0.04
## Xác suất thủ môn cản được quả phạt đền sút vào giữa (sút sát cột thì khó cản hơn).
@export var penalty_save: float = 0.45

@export_group("Người chơi vào đá")
## Lực sút (m/s) khi nhấp nhẹ … giữ đủ lâu.
@export var user_shot_speed: Vector2 = Vector2(6.0, 17.0)
@export var user_charge_time: float = 0.9
@export var user_reach: float = 1.7

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
var _touch_gap: float = 0.0
var _player_touch: bool = false   # người nhập vai là người chạm bóng cuối
## Đội của người nhập vai (−1 = không đá).
var user_team: int = -1
var half: int = 1
## Thống kê cho bài thử / bảng kết quả.
var stats: Dictionary = {}
var _last_team: int = -1          # đội chạm bóng cuối (tính ném biên / phạt góc)
var _first_kickoff: int = 0
var _restart: Dictionary = {}     # {kind, team, pos, taker, placed, t}
var _call_label: Label3D
var _call_text: String = ""
var _call_t: float = 0.0
var _pass_call_t: float = 0.0     # người chơi vừa gọi "Chuyền đây!"
var _charging: bool = false
var _charge: float = 0.0
var _user_foul_cd: float = 0.0
var _pen_save: bool = false
var _ui: CanvasLayer
var _ui_panel: PanelContainer
var _ui_score: Label
var _ui_info: Label
var _ui_call: Label


func build() -> void:
	_rng.seed = random_seed
	rect = village.pitch_rect if village != null else Rect2(-64, -176, 30, 18)
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
	_call_label = Label3D.new()
	_call_label.font = Hud.font(true)
	_call_label.font_size = 64
	_call_label.pixel_size = 0.006
	_call_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_call_label.no_depth_test = true
	_call_label.modulate = Palette.FLOWER_YELLOW
	_call_label.outline_size = 10
	_call_label.outline_modulate = Palette.WINDOW_DARK
	_call_label.visible = false
	add_child(_call_label)
	_build_overlay()
	_reset_stats()
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
	_player_touch = false
	_ball_pos = Vector3(p.x, ball_radius, p.z)
	_ball_vel = Vector3.ZERO
	_ball.global_position = _ball_pos


func _update_score() -> void:
	_score_labels[1].text = "%d - %d" % [score[0], score[1]]


# --- Người xem / người nhập vai -------------------------------------------------------------

func ball_node() -> Node3D:
	return _ball


func ball_position() -> Vector3:
	return _ball_pos


## Người nhập vai sút (nhìn vào bóng + E): theo hướng nhìn, `up` là độ bổng (0..1).
func kick_from_player(dir: Vector3, up: float) -> void:
	if user_team >= 0:
		if _user_can_touch():
			_user_kick(dir, user_kick_speed * _rng.randf_range(0.85, 1.05), lerpf(0.5, 7.0, up))
		return
	_kick(dir, user_kick_speed * _rng.randf_range(0.85, 1.05), lerpf(0.5, 7.0, up))
	_touch_gap = 0.3
	_player_touch = true


## Người nhập vai đi vào bóng: đẩy nhẹ theo hướng chân (dẫn bóng).
func nudge(dir: Vector3, speed: float) -> void:
	if _ball_pos.y > ball_radius + 0.15:
		return
	if user_team >= 0:
		if phase != Phase.PLAY or _touch_gap > 0.0:
			return       # đang chờ đá lại / giao bóng: không dẫn bóng
		_last_team = user_team
	var h := Vector3(_ball_vel.x, 0, _ball_vel.z)
	if h.dot(dir) >= speed * 0.9:
		return
	_kick(dir, speed, 0.0)
	_player_touch = true


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
	var counts := _team_counts()
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
	if phase == Phase.IDLE and _total() >= 2:
		_start_match()
	return true


func _team_counts() -> Array[int]:
	var counts: Array[int] = [0, 0]
	for p in players:
		counts[int(p.team)] += 1
	if user_team >= 0:
		counts[user_team] += 1
	return counts


## Số người trên sân (kể cả người nhập vai).
func _total() -> int:
	return players.size() + (1 if user_team >= 0 else 0)


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
	_reset_stats()
	_match_timer = match_length
	half = 1
	_kickoff_team = _rng.randi_range(0, 1)
	_first_kickoff = _kickoff_team
	_call("Tuýt! Bắt đầu trận — %s giao bóng" % TEAM_NAMES[_kickoff_team])
	_begin_kickoff()


func _reset_stats() -> void:
	stats = {"throw": 0, "goal_kick": 0, "corner": 0, "free": 0, "penalty": 0, "fouls": 0, "user_fouls": 0,
			"pen_saved": 0, "user_touches": 0, "user_goals": 0, "user_passes": 0, "pass_to_user": 0, "halftime": 0}


func _begin_kickoff() -> void:
	phase = Phase.KICKOFF
	_phase_timer = 2.0
	_restart_timer = -1.0
	_restart = {}
	_pen_save = false
	_place_ball(center3())


func _end_match() -> void:
	phase = Phase.IDLE
	_restart = {}
	while not players.is_empty():
		_remove(players.size() - 1, true)
	if user_team >= 0:
		leave_user()
	_place_ball(center3())


# --- Mỗi khung hình ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ball == null or not is_visible_in_tree():
		return
	# Đồng bộ danh sách: ai đã bỏ đi (trời tối, giông, Villagers đổi việc) thì bỏ khỏi đội
	for i in range(players.size() - 1, -1, -1):
		var v: Villager = players[i].v
		if not is_instance_valid(v) or v.activity != "football" or v.state != Villager.State.IDLE or not v.visible:
			_remove(i, false)
	# Người nhập vai thôi nhập vai / đi ra xa sân / làm việc khác thì rời đội
	if user_team >= 0:
		var fp := first_person
		var gone := fp == null or not fp.active or not (fp._suspended in ["", "talk"])
		if not gone:
			gone = not rect.grow(8.0).has_point(Vector2(fp.global_position.x, fp.global_position.z))
		if gone:
			leave_user()
			_call("Bạn đã rời sân", false)
	if phase != Phase.IDLE and _total() < 2:
		phase = Phase.IDLE
		_restart = {}
	var dt := minf(delta, 0.05)
	if _charging:
		_charge = minf(_charge + dt / user_charge_time, 1.0)
	_step(dt)
	_apply_visuals(dt)
	_update_overlay()


## Một bước mô phỏng (dùng chung cho chạy thật và chạy trước khi chụp ảnh).
func _step(dt: float) -> void:
	_step_ball(dt)
	match phase:
		Phase.KICKOFF:
			_phase_timer -= dt
			_move_players(dt, true)
			# Đội người chơi giao bóng và người chơi đứng ở giữa sân: chờ người chơi đá (tối đa 6 s)
			var wait_user := user_team == _kickoff_team and _user_near(center3(), 3.5) and _phase_timer > -6.0
			if _phase_timer <= 0.0 and not wait_user:
				phase = Phase.PLAY
				var dir := Vector3(_attack_dir(_kickoff_team), 0, _rng.randf_range(-0.6, 0.6))
				_kick(dir, 4.0, 0.0)
				_last_team = _kickoff_team
		Phase.PLAY:
			_match_timer -= dt
			_move_players(dt, false)
			_try_kicks()
			_check_user_foul(dt)
			if half == 1 and _match_timer <= match_length * 0.5:
				_begin_halftime()
			elif _match_timer <= 0.0:
				_begin_fulltime()
		Phase.GOAL:
			_phase_timer -= dt
			_move_players(dt, true)
			if _phase_timer <= 0.0:
				_begin_kickoff()
		Phase.RESTART:
			_match_timer -= dt
			_step_restart(dt)
		Phase.HALFTIME:
			_phase_timer -= dt
			_move_players(dt, true)
			if _phase_timer <= 0.0:
				_kickoff_team = 1 - _first_kickoff
				_call("Hiệp 2 — %s giao bóng" % TEAM_NAMES[_kickoff_team])
				_begin_kickoff()
		Phase.FULLTIME:
			_phase_timer -= dt
			_move_players(dt, true)
			if _phase_timer <= 0.0:
				_end_match()
	_touch_gap = maxf(_touch_gap - dt, 0.0)
	_call_t = maxf(_call_t - dt, 0.0)
	_pass_call_t = maxf(_pass_call_t - dt, 0.0)
	_user_foul_cd = maxf(_user_foul_cd - dt, 0.0)
	for p in players:
		p.cool = maxf(float(p.cool) - dt, 0.0)
		p.kick_t = maxf(float(p.kick_t) - dt, 0.0)


## Hướng tấn công theo trục x: hiệp 2 hai đội đổi sân.
func _attack_dir(team: int) -> float:
	var d := 1.0 if team == 0 else -1.0
	return d if half == 1 else -d


func _own_goal_x(team: int) -> float:
	return rect.position.x if _attack_dir(team) > 0.0 else rect.end.x


## Trong vòng cấm của đội `team` (3 m trước khung thành nhà, rộng 7 m)?
func _in_own_box(team: int, p: Vector2) -> bool:
	var gx := _own_goal_x(team)
	return absf(p.x - gx) <= 3.0 and absf(p.y - rect.get_center().y) <= 3.5


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
		# Người nhập vai gần bóng hơn thì đồng đội máy không lao vào nữa, chỉ chạy đỡ
		if user_team >= 0:
			var du := _user_pos2().distance_to(ball2)
			if du < best[user_team]:
				support[user_team] = chasers[user_team]
				chasers[user_team] = null
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
		if phase in [Phase.KICKOFF, Phase.HALFTIME] and not p.keeper:
			# Giao bóng: hai đội về phần sân nhà
			var cx := rect.get_center().x
			target.x = minf(target.x, cx - 1.0) if _attack_dir(team) > 0.0 else maxf(target.x, cx + 1.0)
			if phase == Phase.KICKOFF and team != _kickoff_team:
				var off := target - rect.get_center()
				if off.length() < 3.3:
					target = rect.get_center() + off.normalized() * 3.3   # ngoài vòng tròn giữa sân
		if phase == Phase.RESTART and bool(_restart.get("placed", false)):
			var r := _restart_target(p, target)
			target = r[0]
			urgent = r[1]
		# Lững thững khi đứng chờ
		p.wander = float(p.wander) + dt * 0.7
		if not urgent:
			target += Vector2(sin(float(p.wander)), cos(float(p.wander) * 0.8)) * 0.6
		var to := target - pos
		var dist := to.length()
		var hurry := dist > (1.0 if phase == Phase.RESTART else 4.0)   # chờ đá lại: dạt ra chỗ đứng cho nhanh
		var speed: float = p.run if urgent or hurry else minf(1.3, float(p.run))
		if p.keeper:
			speed *= 0.75          # thủ môn làng phản xạ chậm
		if phase == Phase.GOAL or phase == Phase.FULLTIME:
			speed = 0.0
		var step := minf(speed * dt, dist)
		var move := to / dist * step if dist > 0.05 else Vector2.ZERO
		# Đẩy nhau ra khi đứng sát (cả người nhập vai)
		var others: Array[Vector2] = []
		for q in players:
			if q != p:
				others.append(Vector2(q.v.global_position.x, q.v.global_position.z))
		if user_team >= 0:
			others.append(_user_pos2())
		for qp in others:
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
		# Tranh bóng với đối phương đang giữ bóng: đôi khi thành phạm lỗi
		if _opponent_on_ball(team, ball2) and _rng.randf() < foul_chance:
			p.cool = 1.0
			_foul(team, ball2, (p.v as Villager).display_name)
			return
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
		elif user_team == team and _pass_call_t > 0.0 and _user_free() and _user_pos2().distance_to(ball2) < 22.0 and _rng.randf() < 0.85:
			# Người chơi gọi "Chuyền đây!": chuyền tới trước chân người chơi
			var fpv := first_person.velocity
			var lead := _user_pos2() + Vector2(fpv.x, fpv.z) * 0.4
			aim = lead - ball2
			speed = clampf(aim.length() * 1.05 + 2.0, 5.0, 11.0)
			lift = 0.3 if aim.length() < 10.0 else 2.0
			_pass_call_t = 0.0
			stats.pass_to_user = int(stats.pass_to_user) + 1
		else:
			var mate := _pass_target(p, ball2)
			if mate != Vector2.INF and _rng.randf() < 0.4:
				if user_team == team and mate.distance_to(_user_pos2()) < 1.5:
					stats.pass_to_user = int(stats.pass_to_user) + 1
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
		_player_touch = false
		_last_team = team
		return


## Đối phương của `team` đang giữ bóng (đứng sát bóng) — máy hoặc người nhập vai.
func _opponent_on_ball(team: int, ball2: Vector2) -> bool:
	for q in players:
		if int(q.team) != team and Vector2(q.v.global_position.x, q.v.global_position.z).distance_to(ball2) < 1.0:
			return true
	return user_team >= 0 and user_team != team and _user_pos2().distance_to(ball2) < 1.0


## Người chơi không bị kèm (không đối phương nào trong 2,5 m).
func _user_free() -> bool:
	for q in players:
		if int(q.team) != user_team and Vector2(q.v.global_position.x, q.v.global_position.z).distance_to(_user_pos2()) < 2.5:
			return false
	return true


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
	if user_team >= 0 and user_team != int(p.team):
		var up := _user_pos2()
		if up.distance_to(ball2) < minf(best, 4.0) and absf(up.y - ball2.y) > 0.05:
			side = -signf((up.y - ball2.y) * dir)
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
	# Người nhập vai cùng đội cũng là chỗ chuyền (ưu tiên nếu đang trống)
	if user_team == team:
		var up := _user_pos2()
		var gain := (up.x - ball2.x) * dir + (2.0 if _user_free() else -3.0)
		if gain > best_gain and up.distance_to(ball2) < 15.0:
			best = up + Vector2(dir * 1.0, 0)
	return best


# --- Người nhập vai vào đá -----------------------------------------------------------------

func _user_pos2() -> Vector2:
	if first_person == null:
		return Vector2.INF
	return Vector2(first_person.global_position.x, first_person.global_position.z)


func _user_near(p: Vector3, r: float) -> bool:
	return user_team >= 0 and _user_pos2().distance_to(Vector2(p.x, p.z)) < r


## Gợi ý "E: Xin vào đá" khi người nhập vai đứng trên sân / mép sân (rỗng = không).
func join_hint(pos: Vector3) -> String:
	if user_team >= 0 or phase == Phase.FULLTIME or rect.size == Vector2.ZERO:
		return ""
	if not rect.grow(2.0).has_point(Vector2(pos.x, pos.z)):
		return ""
	return "E: Xin vào đá bóng" + ("" if phase != Phase.IDLE else " (gọi mọi người ra sân)")


## Vào đội ít người hơn; sân vắng thì gọi trẻ con / thanh niên quanh làng ra đá.
func join_user() -> void:
	if user_team >= 0:
		return
	var counts := _team_counts()
	user_team = 0 if counts[0] <= counts[1] else 1
	_charging = false
	var called := 0
	if players.size() < 5:
		called = _gather(6 - players.size())
	if phase == Phase.IDLE and _total() >= 2:
		_start_match()
	var side := "mặc áo, vòng đỏ" if user_team != SHIRTLESS_TEAM else "cởi trần, vòng xanh"
	if players.is_empty() and called == 0:
		_call("Chưa ai ra sân được — bạn tập sút một mình", false)
	elif phase == Phase.IDLE:
		_call("Bạn vào %s (%s) — chờ mọi người ra sân…" % [TEAM_NAMES[user_team], side], false)
	else:
		_call("Bạn vào đá cho %s (%s)" % [TEAM_NAMES[user_team], side], false)
	_ui.visible = true


func leave_user() -> void:
	user_team = -1
	_charging = false
	_charge = 0.0
	if _restart.get("taker") is String:
		_restart.taker = _pick_taker(int(_restart.team), String(_restart.kind))
	if phase != Phase.IDLE and _total() < 2:
		phase = Phase.IDLE
		_restart = {}


## Gọi tối đa `n` người (trẻ con, đàn ông) đang rảnh ra sân. Trả về số người được gọi.
func _gather(n: int) -> int:
	if villagers == null or n <= 0:
		return 0
	var h := villagers._hour()
	if villagers._is_night(h) or villagers._storm():
		return 0
	var c := center3()
	var cand: Array[Villager] = []
	for v in villagers.people:
		if not (v.role == "kid" or (v.role == "farmer" and not v.get_meta("female", false))):
			continue
		if not v.visible or v.activity in ["football", "school", "worship", "hideseek"]:
			continue
		var busy := false
		for m in ["at_school", "in_class", "talking", "hiding", "playing_oaq", "pupil"]:
			if v.has_meta(m):
				busy = true
		if not busy and v.global_position.distance_to(c) < 170.0:
			cand.append(v)
	cand.sort_custom(func(a: Villager, b: Villager) -> bool: return a.global_position.distance_to(c) < b.global_position.distance_to(c))
	var k := 0
	for v in cand.slice(0, n):
		villagers._next_activity(v, "football")
		v.speed_mul = 1.6
		v.activity_text = "được gọi ra sân đá bóng"
		k += 1
	return k


## Được chạm bóng không (đang chờ đá lại thì chỉ người được giao đá).
func _user_can_touch() -> bool:
	match phase:
		Phase.PLAY, Phase.IDLE:
			return true
		Phase.RESTART:
			return _restart.get("taker") is String and bool(_restart.get("placed", false))
		Phase.KICKOFF:
			return user_team == _kickoff_team and _user_near(center3(), 3.5)
	return false


func _ball_in_reach() -> bool:
	var b := Vector2(_ball_pos.x, _ball_pos.z)
	return _user_pos2().distance_to(b) <= user_reach and _ball_pos.y < 1.2


## Chuột trái nhấn: bắt đầu lấy lực.
func user_charge_start() -> void:
	if user_team < 0:
		return
	_charging = true
	_charge = 0.0


## Chuột trái thả: sút theo hướng nhìn `look` với lực đã lấy (ném biên thì ném bằng tay).
func user_charge_release(look: Vector3) -> void:
	if user_team < 0 or not _charging:
		return
	_charging = false
	var power := _charge
	_charge = 0.0
	if not _ball_in_reach():
		_call("Bóng xa quá — chạy lại gần bóng (dưới %.1f m)" % user_reach, false)
		return
	if not _user_can_touch():
		return
	var dir := Vector3(look.x, 0, look.z).normalized()
	var speed := lerpf(user_shot_speed.x, user_shot_speed.y, power)
	var lift := clampf(look.y + 0.12, 0.0, 0.8) * 9.0 + power * 0.8
	if String(_restart.get("kind", "")) == "throw":
		speed = lerpf(4.5, 10.0, power)
		lift = 2.5 + clampf(look.y, 0.0, 0.6) * 4.0
	_user_kick(dir, speed, lift)


## Chuột phải: chuyền cho đồng đội gần hướng nhìn nhất (không có thì chuyền thẳng).
func user_pass(look: Vector3) -> void:
	if user_team < 0 or not _ball_in_reach() or not _user_can_touch():
		return
	var ball2 := Vector2(_ball_pos.x, _ball_pos.z)
	var dir2 := Vector2(look.x, look.z).normalized()
	var best := Vector2.INF
	var best_cos := 0.55
	for q in players:
		if int(q.team) != user_team:
			continue
		var qp := Vector2(q.v.global_position.x, q.v.global_position.z)
		var to := qp - ball2
		if to.length() < 1.5 or to.length() > 25.0:
			continue
		var cs := to.normalized().dot(dir2)
		if cs > best_cos:
			best_cos = cs
			best = qp
	var aim := dir2 * 9.0 if best == Vector2.INF else best - ball2
	var speed := clampf(aim.length() * 1.05 + 2.5, 5.0, 12.0)
	var lift := 0.3 if aim.length() < 11.0 else 2.2
	if String(_restart.get("kind", "")) == "throw":
		lift = 2.5
	stats.user_passes = int(stats.user_passes) + 1
	_user_kick(Vector3(aim.x, 0, aim.y), speed, lift)


## Q: "Chuyền đây!" — đồng đội đang có bóng sẽ chuyền cho mình (nếu không bị kèm).
func user_call() -> void:
	if user_team < 0:
		return
	_pass_call_t = 3.0
	_call("Bạn gọi: \"Chuyền đây!\"", false)


func _user_kick(dir: Vector3, speed: float, lift: float) -> void:
	var restart_kind := String(_restart.get("kind", "")) if phase == Phase.RESTART else ""
	if restart_kind == "penalty":
		_decide_penalty_save(dir)
	_kick(dir, speed, lift)
	# Phạt đền: không ai chạm bóng cho tới khi bóng qua vạch (cản hay không do _pen_save quyết định)
	_touch_gap = 0.7 if restart_kind == "penalty" else 0.3
	_player_touch = true
	_last_team = user_team
	stats.user_touches = int(stats.user_touches) + 1
	if phase in [Phase.RESTART, Phase.KICKOFF]:
		phase = Phase.PLAY
		_restart = {}


## Người nhập vai chạy xô vào đối phương đang giữ bóng: phạm lỗi.
func _check_user_foul(_dt: float) -> void:
	if user_team < 0 or _user_foul_cd > 0.0 or first_person == null:
		return
	var v := Vector2(first_person.velocity.x, first_person.velocity.z)
	if v.length() < 4.2:
		return
	var up := _user_pos2()
	var ball2 := Vector2(_ball_pos.x, _ball_pos.z)
	for q in players:
		if int(q.team) == user_team:
			continue
		var qp := Vector2(q.v.global_position.x, q.v.global_position.z)
		var to := qp - up
		if to.length() < 0.6 and qp.distance_to(ball2) < 1.2 and to.normalized().dot(v.normalized()) > 0.6:
			_user_foul_cd = 3.0
			stats.user_fouls = int(stats.user_fouls) + 1
			_foul(user_team, ball2, "Bạn")
			return


# --- Luật: đá lại, phạm lỗi, hiệp -----------------------------------------------------------

## Phạm lỗi của đội `team` tại `at`: đội kia được đá phạt, trong vòng cấm của `team` thì phạt đền.
func _foul(team: int, at: Vector2, who: String) -> void:
	stats.fouls = int(stats.fouls) + 1
	var victim := 1 - team
	if _in_own_box(team, at):
		var spot := Vector2(_own_goal_x(team) + _attack_dir(team) * 5.0, rect.get_center().y)
		_begin_restart("penalty", victim, Vector3(spot.x, 0, spot.y), 0.6)
		_call("Tuýt! %s phạm lỗi trong vòng cấm — PHẠT ĐỀN cho %s" % [who, TEAM_NAMES[victim]])
	else:
		var p := Vector2(clampf(at.x, rect.position.x + 0.6, rect.end.x - 0.6), clampf(at.y, rect.position.y + 0.6, rect.end.y - 0.6))
		_begin_restart("free", victim, Vector3(p.x, 0, p.y), 0.6)
		_call("Tuýt! %s phạm lỗi — đá phạt cho %s" % [who, TEAM_NAMES[victim]])


## Bóng ra ngoài: ném biên (biên dọc), phát bóng lên / phạt góc (vạch cuối sân).
func _ball_out() -> void:
	var c := rect.get_center()
	var b := Vector2(_ball_pos.x, _ball_pos.z)
	var last := _last_team if _last_team >= 0 else _rng.randi_range(0, 1)
	if b.x < rect.position.x or b.x > rect.end.x:
		var s := -1.0 if b.x < rect.position.x else 1.0
		var gx := c.x + s * rect.size.x * 0.5
		# Đội phòng ngự ở đầu sân này = đội có khung thành nhà ở đây
		var defender := 0 if is_equal_approx(_own_goal_x(0), gx) else 1
		if last == defender:
			var cz := rect.position.y + 0.3 if b.y < c.y else rect.end.y - 0.3
			_begin_restart("corner", 1 - defender, Vector3(gx - s * 0.3, 0, cz), restart_delay)
			_call("Phạt góc — %s" % TEAM_NAMES[1 - defender])
		else:
			_begin_restart("goal_kick", defender, Vector3(gx - s * 2.0, 0, c.y + (1.2 if b.y > c.y else -1.2)), restart_delay)
			_call("Phát bóng lên — %s" % TEAM_NAMES[defender])
	else:
		var z := rect.position.y + 0.1 if b.y < c.y else rect.end.y - 0.1
		var x := clampf(b.x, rect.position.x + 0.6, rect.end.x - 0.6)
		_begin_restart("throw", 1 - last, Vector3(x, 0, z), restart_delay)
		_call("Ném biên — %s" % TEAM_NAMES[1 - last])


func _begin_restart(kind: String, team: int, pos: Vector3, delay: float) -> void:
	phase = Phase.RESTART
	stats[kind] = int(stats.get(kind, 0)) + 1
	_restart = {"kind": kind, "team": team, "pos": pos, "placed": false, "t": delay, "wait": 1.2}
	_restart.taker = _pick_taker(team, kind)   # sau khi đã có "pos" (chọn theo chỗ đặt bóng mới)
	_pen_save = false


## Người đá lại: thủ môn phát bóng lên; còn lại người gần bóng nhất (người nhập vai được ưu tiên
## nếu gần ngang người máy; phạt đền thì người nhập vai luôn được đá).
func _pick_taker(team: int, kind: String) -> Variant:
	var pos := _restart.get("pos", _ball_pos) as Vector3 if not _restart.is_empty() else _ball_pos
	var p2 := Vector2(pos.x, pos.z)
	var best: Variant = null
	var best_d := INF
	for q in players:
		if int(q.team) != team:
			continue
		if kind == "goal_kick" and q.keeper:
			return q
		if q.keeper and kind != "goal_kick":
			continue
		var d := Vector2(q.v.global_position.x, q.v.global_position.z).distance_to(p2)
		if d < best_d:
			best_d = d
			best = q
	if user_team == team:
		var du := _user_pos2().distance_to(p2)
		if kind == "penalty" or best == null or du < best_d + 2.0:
			return "user"
	if best == null:
		for q in players:
			if int(q.team) == team:
				return q
	return best


## Đang chờ đá lại: đặt bóng sau một nhịp, người đá chạy tới, máy đá khi đã tới nơi.
func _step_restart(dt: float) -> void:
	_restart.t = float(_restart.t) - dt
	if not bool(_restart.placed):
		_move_players(dt, true)
		if float(_restart.t) <= 0.0:
			_restart.placed = true
			_place_ball(_restart.pos as Vector3)
			if String(_restart.kind) == "penalty":
				_call("Phạt đền! %s sút" % ("Bạn" if _restart.taker is String else TEAM_NAMES[int(_restart.team)]))
				_line_up_penalty()
		return
	_move_players(dt, true)
	_restart.wait = float(_restart.wait) - dt
	var taker: Variant = _restart.taker
	if taker is Dictionary and float(_restart.wait) <= 0.0:
		var v: Villager = (taker as Dictionary).v
		var bp := _restart.pos as Vector3
		if Vector2(v.global_position.x, v.global_position.z).distance_to(Vector2(bp.x, bp.z)) < 0.7:
			_take_restart(taker as Dictionary)
	elif taker == null:
		_take_restart({})


## Máy thực hiện quả đá lại.
func _take_restart(p: Dictionary) -> void:
	var kind := String(_restart.kind)
	var team := int(_restart.team)
	var dir := _attack_dir(team)
	var c := rect.get_center()
	var ball2 := Vector2(_ball_pos.x, _ball_pos.z)
	var goal := Vector2(rect.end.x if dir > 0.0 else rect.position.x, c.y)
	var aim := Vector2(dir, 0)
	var speed := 8.0
	var lift := 0.5
	match kind:
		"throw":
			var mate := _pass_target(p, ball2) if not p.is_empty() else Vector2.INF
			aim = (mate - ball2) if mate != Vector2.INF else Vector2(dir * 6.0, (c.y - ball2.y) * 0.5)
			speed = clampf(aim.length() * 0.95 + 2.0, 4.5, 9.0)
			lift = 2.6
		"goal_kick":
			aim = Vector2(dir, _rng.randf_range(-0.6, 0.6))
			speed = _rng.randf_range(10.0, 12.0)
			lift = _rng.randf_range(3.5, 5.0)
		"corner":
			var tgt := Vector2(goal.x - dir * _rng.randf_range(2.0, 5.0), c.y + _rng.randf_range(-2.5, 2.5))
			aim = tgt - ball2
			speed = clampf(aim.length() * 0.95 + 3.0, 7.0, 12.0)
			lift = 3.6
		"free":
			if goal.distance_to(ball2) < 16.0:
				aim = Vector2(goal.x, c.y + _rng.randf_range(-1.6, 1.6)) - ball2
				speed = _rng.randf_range(10.0, 13.0)
				lift = _rng.randf_range(1.0, 2.2)
			else:
				var mate := _pass_target(p, ball2) if not p.is_empty() else Vector2.INF
				aim = (mate - ball2) if mate != Vector2.INF else Vector2(dir, _rng.randf_range(-0.4, 0.4))
				speed = clampf(aim.length() + 3.0, 7.0, 11.0)
				lift = 1.5
		"penalty":
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			aim = Vector2(goal.x, c.y + side * _rng.randf_range(0.4, goal_width * 0.5 - 0.3)) - ball2
			speed = _rng.randf_range(11.0, 13.5)
			lift = _rng.randf_range(0.2, 1.0)
			_decide_penalty_save(Vector3(aim.x, 0, aim.y))
	_kick(Vector3(aim.x, 0, aim.y), speed, lift)
	if not p.is_empty():
		p.kick_t = 0.35
		p.cool = 0.8
	_last_team = team
	_player_touch = false
	_touch_gap = 0.7 if kind == "penalty" else 0.35
	phase = Phase.PLAY
	_restart = {}


## x của vạch đứng chờ khi phạt đền: sau chấm phạt đền 4 m (chấm cách vạch cuối 5 m).
func _penalty_line(defender: int) -> float:
	return _own_goal_x(defender) + _attack_dir(defender) * 9.0


## Đặt bóng phạt đền: thủ môn về giữa khung thành, mọi người (trừ người sút) ra sau vạch chờ ngay.
func _line_up_penalty() -> void:
	var defender := 1 - int(_restart.team)
	var c := rect.get_center()
	var behind := _penalty_line(defender)
	var dir := _attack_dir(defender)
	for p in players:
		if is_same(p, _restart.taker):
			continue
		var v: Villager = p.v
		if p.keeper and int(p.team) == defender:
			v.global_position = Vector3(_own_goal_x(defender) + dir * 0.3, v.global_position.y, c.y)
		elif (v.global_position.x - behind) * dir < 0.0:
			v.global_position.x = behind + dir * _rng.randf_range(0.2, 1.5)


## Phạt đền: quyết định thủ môn có cản được không (sút càng sát cột càng khó cản).
func _decide_penalty_save(dir: Vector3) -> void:
	var team := int(_restart.get("team", 0))
	var c := rect.get_center()
	var gx := rect.end.x if _attack_dir(team) > 0.0 else rect.position.x
	var d := Vector2(dir.x, dir.z).normalized()
	if absf(d.x) < 0.05 or signf(d.x) != signf(gx - _ball_pos.x):
		_pen_save = false
		return
	var z_at := _ball_pos.z + d.y / d.x * (gx - _ball_pos.x)
	var off := absf(z_at - c.y) / (goal_width * 0.5)
	var has_keeper := false
	for q in players:
		if int(q.team) != team and q.keeper:
			has_keeper = true
	var chance := penalty_save * (1.25 - off) if has_keeper else penalty_save * 0.4 * (1.0 - off)
	_pen_save = off < 1.0 and _rng.randf() < chance


## Vị trí đứng khi chờ đá lại: [target, urgent].
func _restart_target(p: Dictionary, target: Vector2) -> Array:
	var bp3 := _restart.pos as Vector3
	var bp := Vector2(bp3.x, bp3.z)
	var team := int(p.team)
	var kind := String(_restart.kind)
	if is_same(p, _restart.taker):
		var dir := _attack_dir(int(_restart.team))
		var back := Vector2(dir, 0) if kind != "throw" else Vector2(0, signf(bp.y - rect.get_center().y))
		return [bp - back * 0.45, true]
	if kind == "penalty":
		var defender := 1 - int(_restart.team)
		if p.keeper and team == defender:
			var gx := _own_goal_x(defender)
			return [Vector2(gx + _attack_dir(defender) * 0.3, rect.get_center().y), true]
		# Mọi người đứng sau chấm phạt đền (xa khung thành hơn chấm), cách chấm ≥ 4 m
		var behind := _penalty_line(defender)
		if (target.x - behind) * _attack_dir(defender) < 0.0:
			target.x = behind
		return [target, false]
	var keep := 4.0 if kind in ["free", "penalty"] else 3.0
	if team != int(_restart.team) or kind == "penalty":
		var off := target - bp
		if off.length() < keep:
			target = bp + (off.normalized() if off.length() > 0.01 else Vector2(0, 1)) * keep
	return [target, false]


func _begin_halftime() -> void:
	phase = Phase.HALFTIME
	_phase_timer = halftime_seconds
	stats.halftime = 1
	half = 2
	_restart = {}
	_place_ball(center3())
	_call("Hết hiệp 1 (%d – %d) — nghỉ giữa hiệp, đổi sân" % [score[0], score[1]])


func _begin_fulltime() -> void:
	phase = Phase.FULLTIME
	_phase_timer = 6.0
	_restart = {}
	var res := "Hoà!" if score[0] == score[1] else "%s thắng!" % TEAM_NAMES[0 if score[0] > score[1] else 1]
	if user_team >= 0 and score[0] != score[1]:
		res += "  Đội bạn %s." % ("thắng" if score[user_team] > score[1 - user_team] else "thua")
	_call("Hết giờ! %s %d – %d %s · %s" % [TEAM_NAMES[0], score[0], score[1], TEAM_NAMES[1], res])


## Trọng tài hô (chữ to trên sân + dòng trên giao diện người chơi). `on_field = false`: lời riêng cho
## người chơi (vào / rời đội, gọi chuyền) — chỉ hiện trên bảng tỉ số.
func _call(text: String, on_field: bool = true) -> void:
	_call_text = text
	_call_t = 4.0
	if _call_label != null and on_field:
		_call_label.text = text
		_call_label.global_position = Vector3(_ball_pos.x, 2.6, _ball_pos.z)
		_call_label.visible = true
		_call_label.set_meta("t", 0.0)


# --- Bảng tỉ số cho người chơi ---------------------------------------------------------------

func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 4
	_ui.visible = false
	add_child(_ui)
	_ui_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_ui_panel.add_theme_stylebox_override("panel", sb)
	_ui_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_ui_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui_panel.offset_top = 14
	_ui.add_child(_ui_panel)
	var box := VBoxContainer.new()
	_ui_panel.add_child(box)
	_ui_score = _ui_label(true, 24, Palette.HUD_TEXT)
	_ui_info = _ui_label(false, 15, Palette.HUD_SUBTEXT)
	_ui_call = _ui_label(true, 17, Palette.FLOWER_YELLOW)
	for l in [_ui_score, _ui_info, _ui_call]:
		box.add_child(l)


func _ui_label(bold: bool, size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", Hud.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Hướng (so với chỗ người chơi đang nhìn) tới điểm `p`.
func _rel_dir(p: Vector2) -> String:
	if first_person == null:
		return ""
	var to := p - _user_pos2()
	var fwd3 := -first_person.global_transform.basis.z
	var a := wrapf(atan2(to.x, -to.y) - atan2(fwd3.x, -fwd3.z), -PI, PI)
	if absf(a) < PI * 0.25:
		return "phía trước"
	if absf(a) > PI * 0.75:
		return "phía sau"
	return "bên phải" if a > 0.0 else "bên trái"


func _update_overlay() -> void:
	if _ui == null:
		return
	var show := user_team >= 0
	if not show and first_person != null and first_person.active and phase != Phase.IDLE:
		show = rect.grow(10.0).has_point(_user_pos2())
	_ui.visible = show
	if not show:
		return
	var mins := int(maxf(_match_timer, 0.0)) / 60
	var secs := int(maxf(_match_timer, 0.0)) % 60
	var hname: String = {Phase.HALFTIME: "Nghỉ giữa hiệp", Phase.FULLTIME: "Hết giờ", Phase.IDLE: "Chờ người"}.get(phase, "Hiệp %d" % half)
	_ui_score.text = "%s  %d – %d  %s   ·   %s   ·   %02d:%02d" % [TEAM_NAMES[0], score[0], score[1], TEAM_NAMES[1], hname, mins, secs]
	var info := ""
	if user_team >= 0:
		var goal := Vector2(rect.end.x if _attack_dir(user_team) > 0.0 else rect.position.x, rect.get_center().y)
		info = "Bạn đá cho %s · khung thành đối phương ở %s" % [TEAM_NAMES[user_team], _rel_dir(goal)]
		var act := ""
		if phase == Phase.RESTART and _restart.get("taker") is String:
			act = {"throw": "Bạn ném biên: chuột trái (giữ để ném xa) / chuột phải ném cho đồng đội",
					"corner": "Bạn đá phạt góc: giữ chuột trái lấy lực, nhìn lên để bóng bổng",
					"goal_kick": "Bạn phát bóng lên: giữ chuột trái lấy lực",
					"free": "Bạn đá phạt: chuột trái sút / chuột phải chuyền",
					"penalty": "Bạn sút phạt đền: nhìn vào góc khung thành, giữ chuột trái lấy lực"}.get(String(_restart.kind), "")
		elif phase == Phase.KICKOFF and user_team == _kickoff_team and _user_near(center3(), 3.5):
			act = "Bạn giao bóng: chuột phải chuyền cho đồng đội hoặc chuột trái sút"
		else:
			act = "Giữ chuột trái: sút  ·  chuột phải: chuyền  ·  Q: gọi chuyền  ·  chạy vào bóng: dẫn"
		if _charging:
			var n := int(round(_charge * 10.0))
			act = "Lực sút  " + "■".repeat(n) + "□".repeat(10 - n)
		info += "\n" + act
	_ui_info.text = info
	_ui_call.text = _call_text if _call_t > 0.0 else ""


# --- Bóng -------------------------------------------------------------------------------

func _step_ball(dt: float) -> void:
	var prev := _ball_pos
	_ball_vel.y -= 9.8 * dt
	_ball_pos += _ball_vel * dt
	var r := ball_radius
	if _ball_pos.y <= r:
		_ball_pos.y = r
		if _ball_vel.y < 0.0:
			# Chỉ những cú rơi thật (không phải trọng lực kéo nhẹ khi đang lăn) mới nảy và mất đà
			if _ball_vel.y < -1.5:
				_ball_vel.x *= 0.85      # nảy trên đất gồ ghề mất đà
				_ball_vel.z *= 0.85
			_ball_vel.y = -_ball_vel.y * 0.45
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
	# Bóng ra ngoài: ném biên / phát bóng lên / phạt góc (đội chạm cuối mất bóng)
	if phase == Phase.PLAY and not rect.grow(0.15).has_point(Vector2(_ball_pos.x, _ball_pos.z)):
		_ball_out()
	elif phase == Phase.IDLE:
		if _restart_timer < 0.0 and not rect.grow(0.15).has_point(Vector2(_ball_pos.x, _ball_pos.z)):
			_restart_timer = 1.0
			_restart_pos = Vector3(clampf(_ball_pos.x, rect.position.x + 0.5, rect.end.x - 0.5), 0,
					clampf(_ball_pos.z, rect.position.y + 0.3, rect.end.y - 0.3))
		elif _restart_timer >= 0.0:
			_restart_timer -= dt
			if _restart_timer < 0.0:
				_place_ball(_restart_pos)
	# Chờ đá lại: bóng nằm yên ở chỗ đặt
	if phase == Phase.RESTART and bool(_restart.get("placed", false)):
		_ball_pos = _restart.pos as Vector3
		_ball_pos.y = ball_radius
		_ball_vel = Vector3.ZERO
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
		# Quả phạt đền bị thủ môn cản
		if _pen_save and dz < hw + 0.3:
			_pen_save = false
			_ball_pos.x = gx - s * (ball_radius + 0.4)
			_ball_vel = Vector3(-s * _rng.randf_range(2.0, 4.0), 1.5, _rng.randf_range(-3.0, 3.0))
			stats.pen_saved = int(stats.pen_saved) + 1
			_call("Thủ môn cản được!")
			_last_team = 0 if _attack_dir(0) * s < 0.0 else 1
			return
		var post_hit := absf(dz - hw) < 0.12 + ball_radius and _ball_pos.y < goal_height
		var bar_hit := dz < hw and absf(_ball_pos.y - goal_height) < 0.08 + ball_radius
		if post_hit or bar_hit:
			_ball_pos.x = gx - s * (ball_radius + 0.02)
			_ball_vel.x = -_ball_vel.x * 0.5
			_ball_vel.z += _rng.randf_range(-1.5, 1.5)
			return
		if dz < hw and _ball_pos.y < goal_height:
			_ball_vel *= 0.25
			var scorer := 0 if _attack_dir(0) == s else 1
			goal_scored.emit(scorer, _player_touch)
			_ball_pos.x = minf(_ball_pos.x * s, (gx + s * goal_depth * 0.6) * s) * s
			if phase == Phase.PLAY:
				var team := scorer
				score[team] += 1
				if _player_touch and user_team == team:
					stats.user_goals = int(stats.user_goals) + 1
				_call("VÀO! %s ghi bàn%s" % [TEAM_NAMES[team], " — bạn ghi!" if _player_touch and user_team == team else ""])
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
	if _call_label.visible:
		var ct := float(_call_label.get_meta("t", 0.0)) + dt
		_call_label.set_meta("t", ct)
		if ct > 3.0:
			_call_label.visible = false
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
