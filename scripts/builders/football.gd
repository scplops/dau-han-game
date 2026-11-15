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
## Trọng tài thổi còi `count` tiếng ở chỗ `pos` (Soundscape phát tiếng).
signal whistle(pos: Vector3, count: int)

enum Phase { IDLE, KICKOFF, PLAY, GOAL, RESTART, HALFTIME, FULLTIME }

const TEAM_NAMES: Array[String] = ["Xóm Đông", "Xóm Đoài"]
## Đội cởi trần (cởi áo khi vào sân, mặc lại khi ra).
const SHIRTLESS_TEAM := 1
## Vị trí đội hình (tỉ lệ dọc sân tính từ khung thành nhà, tỉ lệ ngang sân).
## 10 cầu thủ ngoài (4-4-2); thủ môn xếp riêng. Thứ tự để đội ít người vẫn dàn đều.
const FORMATION: Array[Vector2] = [Vector2(0.24, 0.38), Vector2(0.24, 0.62), Vector2(0.46, 0.3), Vector2(0.46, 0.7),
		Vector2(0.68, 0.62), Vector2(0.22, 0.14), Vector2(0.22, 0.86), Vector2(0.48, 0.08), Vector2(0.48, 0.92),
		Vector2(0.7, 0.34)]

@export var village: Village
@export var villagers: Villagers
@export var first_person: FirstPerson
@export var random_seed: int = 1717

@export_group("Sân")
@export var goal_width: float = 5.0
@export var goal_height: float = 2.0
## Vòng cấm: sâu (từ vạch cuối sân) × rộng; chấm phạt đền cách vạch; bán kính vòng tròn giữa sân.
@export var box_depth: float = 9.0
@export var box_width: float = 20.0
@export var penalty_spot: float = 7.0
@export var circle_radius: float = 5.0
@export var goal_depth: float = 1.0
@export var line_width: float = 0.12

@export_group("Trận đấu")
## Số cầu thủ tối đa trên sân (11 đấu 11; kể cả người nhập vai).
@export_range(2, 22) var max_players: int = 22
## Trong tầm này (m) trước khung thành thì máy sút.
@export var shot_range: float = 20.0
## Người nhập vai xin vào mà thiếu quân: gọi dân làng rảnh trong tầm này, còn thiếu thì người làng bên vào đá.
@export var gather_distance: float = 45.0
## Một trận kéo dài bao lâu (giây thật), xong thì mọi người tản đi.
@export var match_length: float = 360.0
@export var ball_radius: float = 0.13
@export var rolling_friction: float = 3.2
@export var user_kick_speed: float = 12.0

@export_group("Lối chơi")
## Lực sút của máy (m/s, thấp nhất – cao nhất).
@export var shot_speed: Vector2 = Vector2(14.0, 19.0)
## Tầm chuyền ngắn (m).
@export var pass_range: float = 20.0
## Xác suất chọn chuyền dài bổng khi có đồng đội trống ở xa phía trên.
@export_range(0.0, 1.0) var long_pass_chance: float = 0.22
@export var long_pass_range: float = 36.0
## Xác suất tạt bóng vào vòng cấm khi đang dẫn bóng ở cánh, gần cuối sân.
@export_range(0.0, 1.0) var cross_chance: float = 0.75
## Tầm với (ngang) và độ cao bóng đánh đầu được (thấp nhất – cao nhất, m).
@export var header_reach: float = 1.0
@export var header_heights: Vector2 = Vector2(1.15, 2.25)
## Thủ môn cản được cú sút bay trong tầm với (m) với xác suất này.
@export var keeper_reach: float = 1.5
@export_range(0.0, 1.0) var keeper_save: float = 0.6
## Tốc độ chạy của trọng tài (m/s).
@export var referee_speed: float = 3.8

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
## Góc nhìn (độ) khi người nhập vai đang đá — rộng hơn bình thường để thấy bóng, đồng đội.
@export var user_fov: float = 86.0

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
var _pen_flight: bool = false      # quả phạt đền đang bay (thủ môn cản hay không đã quyết từ lúc sút)
var _ui: CanvasLayer
var _hud: FootballHud
var _guest_root: Node3D
var _guest_n: int = 0
var _ref: Villager                 # trọng tài (người làng bên, áo đen)
var _ref_arm_t: float = 0.0       # đang giơ tay thổi còi
var _ref_moving: bool = false


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
			var goal_d := minf(m.distance_to(Vector2(rect.position.x + 2.0, c.y)), m.distance_to(Vector2(rect.end.x - 2.0, c.y)))
			var wear := maxf(1.0 - goal_d / (box_depth * 0.9), 0.0) + maxf(1.0 - m.distance_to(c) / (circle_radius * 1.2), 0.0) * 0.6
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
		var bx := gx - s * box_depth
		var bh := box_width * 0.5
		segs.append([Vector2(gx, c.y - bh), Vector2(bx, c.y - bh)])
		segs.append([Vector2(bx, c.y - bh), Vector2(bx, c.y + bh)])
		segs.append([Vector2(bx, c.y + bh), Vector2(gx, c.y + bh)])
		_line_dot(mb, Vector2(gx - s * penalty_spot, c.y), 0.16)
	for k in 32:
		var a0 := TAU * k / 32.0
		var a1 := TAU * (k + 1) / 32.0
		segs.append([c + Vector2(cos(a0), sin(a0)) * circle_radius, c + Vector2(cos(a1), sin(a1)) * circle_radius])
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
	_pen_flight = false
	_ball_vel = dir.normalized() * speed + Vector3(0, lift, 0)
	_ball_pos.y = maxf(_ball_pos.y, ball_radius + 0.02)


# --- Cầu thủ ----------------------------------------------------------------------------

## Villagers gọi khi một người tới sân. Trả về true nếu vào đá, false nếu đứng xem.
func arrive(v: Villager) -> bool:
	var can_play: bool = v.role == "kid" or (v.role == "farmer" and not v.get_meta("female", false))
	if not can_play or _total() >= max_players or _find(v) >= 0:
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
			"run": run, "disc": disc, "wander": _rng.randf() * TAU, "jump_t": 0.0})
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
	if is_instance_valid(v) and v.has_meta("fb_guest"):
		v.queue_free()                 # người làng bên: hết trận thì về
	elif release and is_instance_valid(v):
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
			mine[k].keeper = k == 0 and mine.size() + (1 if team == user_team else 0) >= 4
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
	_spawn_referee()
	_whistle(1)
	_begin_kickoff()


func _reset_stats() -> void:
	stats = {"throw": 0, "goal_kick": 0, "corner": 0, "free": 0, "penalty": 0, "fouls": 0, "user_fouls": 0,
			"pen_saved": 0, "user_touches": 0, "user_goals": 0, "user_passes": 0, "pass_to_user": 0, "halftime": 0,
			"shots": 0, "passes": 0, "long_passes": 0, "crosses": 0, "headers": 0, "header_shots": 0, "user_headers": 0,
			"whistles": 0, "saves": 0}


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
	_dismiss_referee()
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
		_dismiss_referee()
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
			var wait_user := user_team == _kickoff_team and _user_near(center3(), circle_radius + 0.5) and _phase_timer > -6.0
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
				_whistle(1)
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
		p.jump_t = maxf(float(p.jump_t) - dt, 0.0)
	_step_referee(dt)


## Hướng tấn công theo trục x: hiệp 2 hai đội đổi sân.
func _attack_dir(team: int) -> float:
	var d := 1.0 if team == 0 else -1.0
	return d if half == 1 else -d


func _own_goal_x(team: int) -> float:
	return rect.position.x if _attack_dir(team) > 0.0 else rect.end.x


## Tâm khung thành đối phương của `team` (theo hiệp).
func _opp_goal(team: int) -> Vector2:
	return Vector2(rect.end.x if _attack_dir(team) > 0.0 else rect.position.x, rect.get_center().y)


## Lực (x) và độ bổng (y) để bóng bay `dist` mét trong `t` giây (bù sức cản không khí).
func _loft(dist: float, t: float) -> Vector2:
	return Vector2(dist / t * 1.08, 4.9 * t)


## Chỗ bóng bổng sẽ rơi xuống ngang tầm đầu (bóng thấp / đang lăn thì chỗ bóng sắp tới).
func _ball_target() -> Vector2:
	var b := Vector2(_ball_pos.x, _ball_pos.z)
	var hv := Vector2(_ball_vel.x, _ball_vel.z)
	if _ball_pos.y < 0.6 and _ball_vel.y < 2.0:
		return b + hv * 0.25
	var h := 1.6 if _ball_pos.y > 1.6 or _ball_vel.y > 5.6 else 0.0     # có lên tới tầm đầu không
	var disc := _ball_vel.y * _ball_vel.y + 19.6 * (_ball_pos.y - h)
	var t := (_ball_vel.y + sqrt(maxf(disc, 0.0))) / 9.8
	return b + hv * t * 0.93


## Trong vòng cấm của đội `team` (3 m trước khung thành nhà, rộng 7 m)?
func _in_own_box(team: int, p: Vector2) -> bool:
	var gx := _own_goal_x(team)
	return absf(p.x - gx) <= box_depth and absf(p.y - rect.get_center().y) <= box_width * 0.5


func _home_point(p: Dictionary) -> Vector2:
	var team := int(p.team)
	var dir := _attack_dir(team)
	var c := rect.get_center()
	if p.keeper:
		return Vector2(_own_goal_x(team) + dir * 1.0, clampf(_ball_pos.z, c.y - goal_width * 0.4, c.y + goal_width * 0.4))
	var f: Vector2 = FORMATION[int(p.slot) % FORMATION.size()]
	var x := _own_goal_x(team) + dir * f.x * rect.size.x + (_ball_pos.x - c.x) * 0.45
	var z := rect.position.y + f.y * rect.size.y + (_ball_pos.z - c.y) * 0.2
	# Bóng đã lên gần cuối sân đối phương: tiền đạo băng vào vòng cấm chờ tạt
	var og := _opp_goal(team)
	if f.x > 0.6 and (og.x - _ball_pos.x) * dir < 26.0:
		x = og.x - dir * (5.5 + float(int(p.slot) % 3) * 1.5)
		z = c.y + (-2.6 if f.y < 0.5 else 2.6)
	# Đội hình lặp lại thì lệch ra cho khỏi đứng chồng
	if int(p.slot) >= FORMATION.size():
		z += 2.5
	return Vector2(clampf(x, rect.position.x + 0.5, rect.end.x - 0.5), clampf(z, rect.position.y + 0.5, rect.end.y - 0.5))


func _move_players(dt: float, formation_only: bool) -> void:
	var ball2 := _ball_target()
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
		var goal := _opp_goal(team)
		var target := _home_point(p)
		var urgent := false
		if not formation_only:
			if p == chasers[team]:
				var to_goal := (goal - ball2).normalized()
				target = ball2 - to_goal * 0.35
				urgent = true
			elif p == support[team]:
				target = ball2 + Vector2(_attack_dir(team) * 5.0, (1.0 if pos.y > ball2.y else -1.0) * 3.0)
			elif p.keeper and ball2.distance_to(pos) < 6.0 and absf(ball2.x - _own_goal_x(team)) < box_depth:
				target = ball2
				urgent = true
		if phase in [Phase.KICKOFF, Phase.HALFTIME] and not p.keeper:
			# Giao bóng: hai đội về phần sân nhà
			var cx := rect.get_center().x
			target.x = minf(target.x, cx - 1.0) if _attack_dir(team) > 0.0 else maxf(target.x, cx + 1.0)
			if phase == Phase.KICKOFF and team != _kickoff_team:
				var off := target - rect.get_center()
				if off.length() < circle_radius + 0.3:
					target = rect.get_center() + off.normalized() * (circle_radius + 0.3)   # ngoài vòng tròn giữa sân
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
		if v.has_meta("fb_guest"):
			v._animate(dt)            # người làng bên: Villagers không diễn hoạt hộ


func _try_kicks() -> void:
	if _restart_timer >= 0.0 or _touch_gap > 0.0:
		return
	if _ball_pos.y > 0.55:
		_try_headers()
		return
	# Duyệt từ một người bất kỳ: hai người cùng tới bóng thì không đội nào luôn được đá trước
	var first := _rng.randi_range(0, maxi(players.size() - 1, 0))
	for k in players.size():
		var p: Dictionary = players[(first + k) % players.size()]
		if float(p.cool) > 0.0:
			continue
		var v: Villager = p.v
		var pos := Vector2(v.global_position.x, v.global_position.z)
		var ball2 := Vector2(_ball_pos.x, _ball_pos.z)
		if pos.distance_to(ball2) > 0.6:
			continue
		var team := int(p.team)
		var dir := _attack_dir(team)
		var c := rect.get_center()
		# Tranh bóng với đối phương đang giữ bóng: đôi khi thành phạm lỗi
		if _opponent_on_ball(team, ball2) and _rng.randf() < foul_chance:
			p.cool = 1.0
			_foul(team, ball2, (p.v as Villager).display_name)
			return
		# Nhắm khung thành, đôi khi chệch cột
		var og := _opp_goal(team)
		var goal := Vector2(og.x, og.y + _rng.randf_range(-goal_width * 0.5 - 1.6, goal_width * 0.5 + 1.6))
		var to_goal := goal - ball2
		var depth := (og.x - ball2.x) * dir          # còn cách vạch cuối sân đối phương
		var wide := absf(ball2.y - c.y) > rect.size.y * 0.22
		var aim: Vector2
		var speed: float
		var lift: float
		if p.keeper:
			# Thủ môn phát bóng dài ra một cánh
			aim = Vector2(dir, (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.4, 0.9))
			speed = _rng.randf_range(13.0, 16.0)
			lift = _rng.randf_range(5.0, 6.5)
		elif wide and depth < 26.0 and depth > 1.5 and _rng.randf() < cross_chance:
			# Tạt cánh: bóng bổng vào trước khung thành
			var tgt := _cross_target(p)
			aim = tgt - ball2
			var kick := _loft(aim.length(), clampf(aim.length() / 13.0, 0.9, 1.5))
			speed = kick.x
			lift = kick.y
			stats.crosses = int(stats.crosses) + 1
		elif to_goal.length() < shot_range and not (wide and depth < 6.0) and _rng.randf() < 0.8:
			aim = to_goal                      # sút
			speed = _rng.randf_range(shot_speed.x, shot_speed.y)
			lift = _rng.randf_range(0.3, 2.0)
			stats.shots = int(stats.shots) + 1
		elif user_team == team and _pass_call_t > 0.0 and _user_free() and _user_pos2().distance_to(ball2) < 26.0 and _rng.randf() < 0.85:
			# Người chơi gọi "Chuyền đây!": chuyền tới trước chân người chơi
			var fpv := first_person.velocity
			var lead := _user_pos2() + Vector2(fpv.x, fpv.z) * 0.4
			aim = lead - ball2
			speed = clampf(aim.length() * 1.1 + 3.0, 6.0, 14.0)
			lift = 0.3 if aim.length() < 12.0 else 2.2
			_pass_call_t = 0.0
			stats.pass_to_user = int(stats.pass_to_user) + 1
		else:
			var far := _long_target(p, ball2)
			var mate := _pass_target(p, ball2)
			if far != Vector2.INF and _rng.randf() < long_pass_chance:
				# Chuyền dài bổng vượt tuyến
				aim = far - ball2
				var kick := _loft(aim.length(), clampf(aim.length() / 15.0, 1.0, 1.7))
				speed = kick.x
				lift = kick.y
				stats.long_passes = int(stats.long_passes) + 1
			elif mate != Vector2.INF and _rng.randf() < 0.5:
				if user_team == team and mate.distance_to(_user_pos2()) < 1.5:
					stats.pass_to_user = int(stats.pass_to_user) + 1
				aim = mate - ball2             # chuyền sệt
				speed = clampf(aim.length() * 1.15 + 3.0, 6.0, 14.0)
				lift = 0.3 if aim.length() < 12.0 else 2.2
				stats.passes = int(stats.passes) + 1
			else:
				# Dẫn bóng: lách sang phía không có đối phương
				var away := _rng.randf_range(0.15, 0.6) * _dodge_side(p, ball2)
				aim = (og - ball2).normalized().rotated(away * dir)
				if wide and depth > 14.0:
					aim = Vector2(dir, away * 0.3)      # ở cánh: dốc bóng dọc biên xuống cuối sân rồi tạt
				speed = _rng.randf_range(4.2, 5.8)
				lift = 0.0
		_kick(Vector3(aim.x, 0, aim.y), speed, lift)
		p.cool = 0.5
		p.kick_t = 0.35
		_touch_gap = 0.3
		_player_touch = false
		_last_team = team
		return


## Bóng bổng ngang tầm đầu: người đứng sát điểm rơi bật lên đánh đầu — trước khung thành đối phương thì
## đánh đầu vào khung, ở sân nhà thì phá ra, còn lại thì đánh đầu nối cho đồng đội phía trên.
func _try_headers() -> void:
	# Chỉ đánh đầu bóng đang rơi xuống (bóng sút căng đi ngang qua thì không kịp)
	if _ball_pos.y < header_heights.x or _ball_pos.y > header_heights.y or _ball_vel.y > -0.5:
		return
	var ball2 := Vector2(_ball_pos.x, _ball_pos.z)
	var who: Dictionary = {}
	var best := header_reach
	for p in players:
		if float(p.cool) > 0.0:
			continue
		var v: Villager = p.v
		if v.role == "kid" and _ball_pos.y > header_heights.y - 0.5:
			continue                   # trẻ con không với tới bóng cao
		var d := Vector2(v.global_position.x, v.global_position.z).distance_to(ball2)
		if d < best:
			best = d
			who = p
	if who.is_empty():
		return
	var team := int(who.team)
	var dir := _attack_dir(team)
	var og := _opp_goal(team)
	var aim: Vector2
	var speed: float
	var lift: float
	if who.keeper:
		# Thủ môn đấm bóng ra
		aim = Vector2(dir, _rng.randf_range(-0.8, 0.8))
		speed = _rng.randf_range(9.0, 12.0)
		lift = _rng.randf_range(3.0, 4.5)
	elif og.distance_to(ball2) < 13.0:
		aim = Vector2(og.x, og.y + _rng.randf_range(-goal_width * 0.5 - 0.8, goal_width * 0.5 + 0.8)) - ball2
		speed = _rng.randf_range(9.5, 13.0)
		lift = _rng.randf_range(-2.0, 0.6)
		stats.header_shots = int(stats.header_shots) + 1
	elif (ball2.x - _own_goal_x(team)) * dir < rect.size.x * 0.3:
		aim = Vector2(dir, _rng.randf_range(-0.7, 0.7))          # phá bóng
		speed = _rng.randf_range(9.0, 12.0)
		lift = _rng.randf_range(3.0, 4.5)
	else:
		var mate := _pass_target(who, ball2)
		aim = (mate - ball2) if mate != Vector2.INF else Vector2(dir, _rng.randf_range(-0.5, 0.5))
		speed = clampf(aim.length() * 0.9 + 2.0, 5.0, 9.0)
		lift = 1.6
	_ball_vel = Vector3(aim.x, 0, aim.y).normalized() * speed + Vector3(0, lift, 0)
	if float(who.jump_t) <= 0.0:
		who.y0 = (who.v as Villager).global_position.y
	who.jump_t = 0.45
	who.cool = 0.7
	_touch_gap = 0.3
	_player_touch = false
	_last_team = team
	stats.headers = int(stats.headers) + 1


## Chỗ tạt bóng tới: đồng đội đang ở trước khung thành đối phương, không có thì khoảng trống trước khung.
func _cross_target(p: Dictionary) -> Vector2:
	var team := int(p.team)
	var dir := _attack_dir(team)
	var og := _opp_goal(team)
	var best := Vector2.INF
	var best_d := 15.0
	for q in players:
		if q == p or int(q.team) != team or q.keeper:
			continue
		var qp := Vector2(q.v.global_position.x, q.v.global_position.z)
		var d := qp.distance_to(og)
		if d < best_d and absf(qp.y - og.y) < 9.0:
			best_d = d
			best = qp
	if user_team == team and _user_pos2().distance_to(og) < best_d and _user_free():
		best = _user_pos2()
	if best == Vector2.INF:
		best = Vector2(og.x - dir * _rng.randf_range(6.0, 9.0), og.y + _rng.randf_range(-3.0, 3.0))
	return best + Vector2(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.8, 0.8))


## Đồng đội ở xa phía trên, không bị kèm, để chuyền dài (Vector2.INF nếu không có).
func _long_target(p: Dictionary, ball2: Vector2) -> Vector2:
	var team := int(p.team)
	var dir := _attack_dir(team)
	var best := Vector2.INF
	var best_gain := 10.0
	for q in players:
		if q == p or int(q.team) != team or q.keeper:
			continue
		var qp := Vector2(q.v.global_position.x, q.v.global_position.z)
		var d := qp.distance_to(ball2)
		var gain := (qp.x - ball2.x) * dir
		if gain <= best_gain or d < 16.0 or d > long_pass_range:
			continue
		var marked := false
		for o in players:
			if int(o.team) != team and Vector2(o.v.global_position.x, o.v.global_position.z).distance_to(qp) < 3.0:
				marked = true
				break
		if not marked:
			best_gain = gain
			best = qp + Vector2(dir * 2.0, 0)
	return best


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
		if gain > best_gain and qp.distance_to(ball2) < pass_range:
			best_gain = gain
			best = qp + Vector2(dir * 1.0, 0)
	# Người nhập vai cùng đội cũng là chỗ chuyền (ưu tiên nếu đang trống)
	if user_team == team:
		var up := _user_pos2()
		var gain := (up.x - ball2.x) * dir + (2.0 if _user_free() else -3.0)
		if gain > best_gain and up.distance_to(ball2) < pass_range:
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
	if _total() < max_players:
		called = _gather(max_players - _total())
		_fill_guests(max_players - _total() - called)
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
	_set_play_view(true)
	if _call_label != null:
		_call_label.visible = false


func leave_user() -> void:
	user_team = -1
	_set_play_view(false)
	_charging = false
	_charge = 0.0
	if _restart.get("taker") is String:
		_restart.taker = _pick_taker(int(_restart.team), String(_restart.kind))
	if phase != Phase.IDLE and _total() < 2:
		phase = Phase.IDLE
		_restart = {}


## Thiếu quân thì `n` người làng bên (hình tạm, ngoài Villagers) chạy từ biên vào đá cho đủ 11 đấu 11.
func _fill_guests(n: int) -> void:
	if n <= 0:
		return
	_ensure_guest_root()
	for i in n:
		_guest_n += 1
		var kid := i % 3 == 2
		var v := GameKit.make_person(_guest_root, villagers, "Guest%d" % _guest_n, "kid" if kid else "farmer",
				("Thằng làng bên %d" if kid else "Anh làng bên %d") % _guest_n, false,
				{"role_name": "khách làng bên", "home_name": "làng bên"})
		v.set_meta("fb_guest", true)
		v.activity = "football"
		v.state = Villager.State.IDLE
		var side := -1.0 if i % 2 == 0 else 1.0
		v.global_position = Vector3(_rng.randf_range(rect.position.x + 4.0, rect.end.x - 4.0), 0.05,
				rect.get_center().y + side * (rect.size.y * 0.5 + _rng.randf_range(0.6, 1.6)))
		arrive(v)


func _ensure_guest_root() -> void:
	if _guest_root == null:
		_guest_root = Node3D.new()
		_guest_root.name = "FootballGuests"
		# Đặt NGOÀI `World`: nhập vai dựng va chạm từ mesh dưới World
		get_parent().get_parent().add_child(_guest_root)


# --- Trọng tài ---------------------------------------------------------------------------------

## Trọng tài (áo quần đen) vào sân khi trận bắt đầu, chạy theo bóng, giơ tay thổi còi.
func _spawn_referee() -> void:
	if is_instance_valid(_ref) or villagers == null:
		return
	_ensure_guest_root()
	_ref = GameKit.make_person(_guest_root, villagers, "Referee", "farmer", "Ông trọng tài", false,
			{"role_name": "trọng tài", "home_name": "làng bên", "shirt": Palette.REFEREE, "pants": Palette.REFEREE})
	_ref.set_meta("fb_guest", true)
	_ref.set_meta("fb_referee", true)
	_ref.activity = "football"
	_ref.activity_text = "đang cầm còi bắt trận bóng"
	_ref.state = Villager.State.IDLE
	var c := rect.get_center()
	_ref.global_position = Vector3(c.x + 3.0, 0.05, c.y - 4.0)


func _dismiss_referee() -> void:
	if is_instance_valid(_ref):
		_ref.queue_free()
	_ref = null


func is_referee(v: Villager) -> bool:
	return v != null and v == _ref


func _whistle(count: int) -> void:
	stats.whistles = int(stats.get("whistles", 0)) + 1
	_ref_arm_t = 0.5 + 0.38 * count
	var at := _ref.global_position + Vector3(0, 1.5, 0) if is_instance_valid(_ref) else _ball_pos
	whistle.emit(at, count)


func _step_referee(dt: float) -> void:
	if not is_instance_valid(_ref):
		return
	_ref_arm_t = maxf(_ref_arm_t - dt, 0.0)
	var c := rect.get_center()
	var ball2 := Vector2(_ball_pos.x, _ball_pos.z)
	var pos := Vector2(_ref.global_position.x, _ref.global_position.z)
	# Đứng chếch về phía giữa sân so với bóng, không chắn đường bóng
	var inward := c - ball2
	inward = inward.normalized() if inward.length() > 1.0 else Vector2(0, 1)
	var target := ball2 + inward.rotated(0.7) * 6.5
	if phase in [Phase.HALFTIME, Phase.FULLTIME, Phase.KICKOFF, Phase.GOAL]:
		target = c + Vector2(2.5, -3.5)
	target = Vector2(clampf(target.x, rect.position.x + 2.0, rect.end.x - 2.0), clampf(target.y, rect.position.y + 2.0, rect.end.y - 2.0))
	var to := target - pos
	var dist := to.length()
	# Chỉ chạy khi đã xa chỗ cần đứng (đỡ giật qua giật lại theo từng cú chạm)
	if dist > 3.0:
		_ref_moving = true
	elif dist < 0.6:
		_ref_moving = false
	var move := Vector2.ZERO
	if _ref_moving and _ref_arm_t <= 0.0:
		move = to / dist * minf((referee_speed if dist > 5.0 else referee_speed * 0.5) * dt, dist)
	# Né cầu thủ đứng sát
	for q in players:
		var sep := pos - Vector2(q.v.global_position.x, q.v.global_position.z)
		if sep.length() < 0.8 and sep.length() > 0.001:
			move += sep.normalized() * (0.8 - sep.length()) * dt * 4.0
	pos += move
	_ref.global_position = Vector3(pos.x, _ref.global_position.y, pos.y)
	var face := move if move.length() > 0.002 else (ball2 - pos)
	if face.length() > 0.01:
		_ref._face(Vector3(face.x, 0, face.y).normalized(), dt)
	var amount := clampf(move.length() / maxf(dt, 0.001) / referee_speed, 0.0, 1.0)
	_ref.speed_mul = 1.0 + amount
	_ref._walk_amount = move_toward(_ref._walk_amount, amount, dt * 6.0)
	_ref._animate(dt)
	if _ref_arm_t > 0.0 and _ref.arms.size() == 2:
		_ref.arms[1].rotation.x = -2.7          # giơ tay phải lên khi thổi còi
		if _ref.elbows.size() == 2:
			_ref.elbows[1].rotation.x = 0.0


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
		if not busy and v.global_position.distance_to(c) < gather_distance:
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
			return user_team == _kickoff_team and _user_near(center3(), circle_radius + 0.5)
	return false


func _ball_in_reach() -> bool:
	var b := Vector2(_ball_pos.x, _ball_pos.z)
	return _user_pos2().distance_to(b) <= user_reach and _ball_pos.y < header_heights.y


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
	elif _ball_pos.y > 1.0:
		# Bóng bổng ngang đầu: đánh đầu theo hướng nhìn
		speed = lerpf(8.0, 13.0, power)
		lift = clampf(look.y, -0.3, 0.5) * 8.0
		stats.user_headers = int(stats.user_headers) + 1
		_call("Bạn đánh đầu!", false)
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
	_pen_flight = restart_kind == "penalty"
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
	_whistle(1)
	var victim := 1 - team
	if _in_own_box(team, at):
		var spot := Vector2(_own_goal_x(team) + _attack_dir(team) * penalty_spot, rect.get_center().y)
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
	_pen_flight = kind == "penalty"
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
	_whistle(2)


func _begin_fulltime() -> void:
	phase = Phase.FULLTIME
	_phase_timer = 6.0
	_restart = {}
	var res := "Hoà!" if score[0] == score[1] else "%s thắng!" % TEAM_NAMES[0 if score[0] > score[1] else 1]
	if user_team >= 0 and score[0] != score[1]:
		res += "  Đội bạn %s." % ("thắng" if score[user_team] > score[1 - user_team] else "thua")
	_call("Hết giờ! %s %d – %d %s · %s" % [TEAM_NAMES[0], score[0], score[1], TEAM_NAMES[1], res])
	_whistle(3)


## Trọng tài hô (chữ to trên sân + dòng trên giao diện người chơi). `on_field = false`: lời riêng cho
## người chơi (vào / rời đội, gọi chuyền) — chỉ hiện trên bảng tỉ số.
func _call(text: String, on_field: bool = true) -> void:
	_call_text = text
	_call_t = 4.0
	# Người chơi đang trong trận: lời trọng tài hiện trên giao diện (chữ 3D to trên sân che mất tầm nhìn)
	if _call_label != null and on_field and user_team < 0:
		_call_label.text = text
		_call_label.global_position = Vector3(_ball_pos.x, 2.6, _ball_pos.z)
		_call_label.visible = true
		_call_label.set_meta("t", 0.0)


# --- Giao diện cho người chơi (mục 50: `FootballHud` vẽ, ở đây chỉ bật / tắt và soạn lời nhắc) ----------------

func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 4
	_ui.visible = false
	add_child(_ui)
	_hud = FootballHud.new()
	_hud.fb = self
	_ui.add_child(_hud)


## Vào / rời trận: ẩn HUD chung + bản đồ nhỏ (đã có sa bàn sân), mở rộng góc nhìn cho dễ thấy bóng và đồng đội.
func _set_play_view(on: bool) -> void:
	if first_person == null:
		return
	if first_person.hud != null:
		first_person.hud.visible = not on
	if first_person.camera != null:
		first_person.camera.fov = user_fov if on else first_person.fov


## Đội đang giữ bóng (có cầu thủ máy trong 1,3 m quanh bóng); −1 nếu bóng tự do.
func _holder_team() -> int:
	var b := Vector2(_ball_pos.x, _ball_pos.z)
	var best := -1
	var bd := 1.3
	for q in players:
		var d := Vector2(q.v.global_position.x, q.v.global_position.z).distance_to(b)
		if d < bd:
			bd = d
			best = int(q.team)
	return best


## Việc người chơi nên làm lúc này (một dòng, FootballHud hiện chữ to dưới màn hình).
func user_prompt() -> String:
	if user_team < 0:
		return ""
	match phase:
		Phase.IDLE:
			return "Chờ mọi người ra sân… (tập sút: chạy tới bóng, giữ chuột trái)" if players.is_empty() else "Chờ đủ người…"
		Phase.HALFTIME:
			return "Nghỉ giữa hiệp — hiệp 2 đổi sân"
		Phase.FULLTIME:
			return "Hết giờ!"
		Phase.GOAL:
			return "VÀO!  Về sân nhà chờ giao bóng"
		Phase.RESTART:
			if _restart.get("taker") is String:
				if not bool(_restart.get("placed", false)) or not _ball_in_reach():
					return "Bạn được đá — chạy tới chỗ đặt bóng"
				return {"throw": "NÉM BIÊN: chuột trái ném (giữ để ném xa) · chuột phải ném cho đồng đội",
						"corner": "PHẠT GÓC: giữ chuột trái lấy lực, nhìn lên cho bóng bổng",
						"goal_kick": "PHÁT BÓNG: giữ chuột trái lấy lực",
						"free": "ĐÁ PHẠT: chuột trái sút · chuột phải chuyền",
						"penalty": "PHẠT ĐỀN: nhìn vào góc khung thành, giữ chuột trái rồi thả"}.get(String(_restart.kind), "Bạn đá")
			return "Chờ %s đá lại" % ("đồng đội" if int(_restart.get("team", -1)) == user_team else "đối phương")
		Phase.KICKOFF:
			if user_team == _kickoff_team and _user_near(center3(), circle_radius + 0.5):
				return "GIAO BÓNG: chuột phải chuyền cho đồng đội · chuột trái sút"
			return "Chờ giao bóng — %s" % ("đội bạn giao" if user_team == _kickoff_team else "đối phương giao")
	if _ball_in_reach() and _user_can_touch():
		return "BÓNG Ở CHÂN BẠN — giữ chuột trái: sút · chuột phải: chuyền"
	var holder := _holder_team()
	if holder == user_team:
		return "Đồng đội giữ bóng — chạy lên phía trước, Q: gọi chuyền"
	if holder >= 0:
		return "Đối phương giữ bóng — chạy tới tranh bóng (đừng chạy xô vào người)"
	return "Chạy tới bóng (theo vòng / mũi tên trắng)"


func _update_overlay() -> void:
	if _ui == null:
		return
	var show := user_team >= 0
	if not show and first_person != null and first_person.active and phase != Phase.IDLE:
		show = rect.grow(10.0).has_point(_user_pos2())
	_ui.visible = show


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
		if dz < hw and _ball_pos.y < goal_height and phase == Phase.PLAY and not _pen_flight and _keeper_saves(gx, s):
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
				_whistle(1)
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


## Cú sút sắp vào lưới: thủ môn đứng trong tầm với thì có thể cản — đẩy bóng ra sân hoặc ra ngoài vạch cuối
## (phạt góc). Trả về true nếu cản được.
func _keeper_saves(gx: float, s: float) -> bool:
	var defender := 0 if is_equal_approx(_own_goal_x(0), gx) else 1
	for p in players:
		if int(p.team) != defender or not p.keeper:
			continue
		var v: Villager = p.v
		if absf(v.global_position.x - gx) > 3.0 or absf(v.global_position.z - _ball_pos.z) > keeper_reach:
			return false
		if _rng.randf() > keeper_save:
			return false
		stats.saves = int(stats.saves) + 1
		_last_team = defender
		_player_touch = false
		_touch_gap = 0.3
		if float(p.jump_t) <= 0.0:
			p.y0 = v.global_position.y
		p.jump_t = 0.45
		var c := rect.get_center()
		var side := 1.0 if _ball_pos.z > c.y else -1.0
		if _rng.randf() < 0.45:
			# Đẩy bóng ra ngoài vạch cuối sân cạnh cột → phạt góc
			_ball_pos = Vector3(gx + s * 0.4, _ball_pos.y, c.y + side * (goal_width * 0.5 + 1.2))
			_ball_vel = Vector3(s * 2.0, 1.0, side * 3.0)
			_call("Thủ môn đẩy bóng ra ngoài!")
		else:
			_ball_pos.x = gx - s * (ball_radius + 0.5)
			_ball_vel = Vector3(-s * _rng.randf_range(4.0, 7.0), _rng.randf_range(2.0, 4.0), _rng.randf_range(-5.0, 5.0))
			_call("Thủ môn cản được!")
		return true
	return false


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
		# Bật nhảy đánh đầu
		if p.has("y0"):
			var jt := float(p.jump_t)
			v.global_position.y = float(p.y0) + (0.42 * sin((1.0 - jt / 0.45) * PI) if jt > 0.0 else 0.0)
			if jt <= 0.0:
				p.erase("y0")


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
