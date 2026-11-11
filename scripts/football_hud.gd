class_name FootballHud
extends Control
## Giao diện đá bóng góc nhìn thứ nhất (mục 50). Vẽ bằng `_draw()` mỗi khung khi người nhập vai đang ở trong trận:
## - Trên giữa: bảng tỉ số gọn (ô màu hai đội, tỉ số, hiệp, đồng hồ; đội của bạn có chữ "BẠN") + lời trọng tài.
## - Trong cảnh: vòng trắng quanh quả bóng kèm số mét (bóng ngoài tầm nhìn thì mũi tên ghim ở mép màn hình), nhãn
##   "SÚT VÀO ĐÂY" trên khung thành đối phương, "Khung thành nhà" trên khung thành mình, dấu ▼ màu đội trên đầu
##   từng cầu thủ (đồng đội đậm, đối thủ nhạt), chỗ đặt bóng khi bạn được đá lại.
## - Dưới giữa: việc cần làm lúc này (chữ to) + thanh lực sút khi đang giữ chuột.
## - Góc dưới phải: sa bàn sân nhìn từ trên, hướng tấn công của bạn quay lên trên.
## - Góc dưới trái: phím.
## Người đứng xem (chưa vào đội) chỉ thấy bảng tỉ số.

var fb: Football

const TEAM_COLORS: Array[Color] = [Color("#e8584a"), Color("#4a8fe0")]
const PANEL := Color(0.08, 0.1, 0.08, 0.62)
const WHITE := Color(1, 1, 1, 0.96)
const SOFT := Color(1, 1, 1, 0.7)
const DARK := Color(0, 0, 0, 0.75)

var _font: Font
var _bold: Font
var _t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Hud.font(false)
	_bold = Hud.font(true)


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		# Con của CanvasLayer không tự giãn theo cửa sổ: đặt kích thước theo khung nhìn mỗi khung
		position = Vector2.ZERO
		size = get_viewport_rect().size
		queue_redraw()


# --- Tiện ích vẽ ---------------------------------------------------------------------------------------

func _text(pos: Vector2, s: String, sz: int, col: Color, bold: bool = true, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var f := _bold if bold else _font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, maxi(sz / 5, 3), DARK)
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _box(r: Rect2, col: Color = PANEL, radius: int = 10) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, r)


## Chiếu điểm 3D lên màn hình: {pos, on (nằm trong khung nhìn), edge (điểm ghim ở mép nếu ở ngoài), dir}.
func _project(cam: Camera3D, p: Vector3, margin: float = 70.0) -> Dictionary:
	var c := size * 0.5
	var behind := cam.is_position_behind(p)
	var sp := cam.unproject_position(p)
	if behind:
		sp = c - (sp - c)               # điểm sau lưng: lật qua tâm để mũi tên chỉ đúng phía
		if sp.distance_to(c) < 1.0:
			sp = c + Vector2(0, 1)
		sp = c + (sp - c).normalized() * maxf(size.x, size.y)
	margin = minf(margin, minf(size.x, size.y) * 0.3)      # cửa sổ rất nhỏ: lề không được lớn hơn nửa màn hình
	var inner := Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	var on := not behind and inner.has_point(sp)
	var d := sp - c
	var edge := sp
	if not on and d.length() > 0.01:
		var k := minf((inner.size.x * 0.5) / maxf(absf(d.x), 0.01), (inner.size.y * 0.5) / maxf(absf(d.y), 0.01))
		edge = c + d * k
	return {"pos": sp, "on": on, "edge": edge, "dir": d.normalized() if d.length() > 0.01 else Vector2.UP}


func _arrow(at: Vector2, dir: Vector2, r: float, col: Color) -> void:
	var n := dir.orthogonal()
	var pts := PackedVector2Array([at + dir * r, at - dir * r * 0.6 + n * r * 0.75, at - dir * r * 0.6 - n * r * 0.75])
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, DARK, 2.0, true)


# --- Vẽ ------------------------------------------------------------------------------------------------

func _draw() -> void:
	if fb == null:
		return
	_draw_score()
	if fb.user_team < 0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_draw_world(cam)
	_draw_prompt()
	_draw_radar()
	_draw_keys()


func _draw_score() -> void:
	var c := size.x * 0.5
	var mins := int(maxf(fb._match_timer, 0.0)) / 60
	var secs := int(maxf(fb._match_timer, 0.0)) % 60
	var hname: String = {Football.Phase.HALFTIME: "Nghỉ giữa hiệp", Football.Phase.FULLTIME: "Hết giờ",
			Football.Phase.IDLE: "Chờ người"}.get(fb.phase, "Hiệp %d" % fb.half)
	_box(Rect2(c - 300, 12, 600, 62))
	# Hai ô màu đội + tên; tỉ số ở giữa
	for t in 2:
		var sgn := -1.0 if t == 0 else 1.0
		var x := c + sgn * 250.0
		draw_rect(Rect2(x - 9, 24, 18, 18), TEAM_COLORS[t])
		var nm := Football.TEAM_NAMES[t] + ("  · BẠN" if t == fb.user_team else "")
		_text(Vector2(c + sgn * 150.0, 42), nm, 18, WHITE if t == fb.user_team else SOFT)
	_text(Vector2(c, 46), "%d – %d" % [fb.score[0], fb.score[1]], 30, WHITE)
	_text(Vector2(c, 68), "%s  ·  %02d:%02d" % [hname, mins, secs], 14, SOFT, false)
	# Lời trọng tài
	if fb._call_t > 0.0 and fb._call_text != "":
		var a := clampf(fb._call_t / 0.5, 0.0, 1.0)
		_text(Vector2(c, 112), fb._call_text, 24, Color(Palette.FLOWER_YELLOW, a))


func _draw_world(cam: Camera3D) -> void:
	var me := fb._user_pos2()
	var team := fb.user_team
	var mid := fb.rect.get_center()
	# Khung thành: đối phương (sút vào) và nhà
	var gx_opp := fb.rect.end.x if fb._attack_dir(team) > 0.0 else fb.rect.position.x
	var gx_own := fb.rect.position.x if fb._attack_dir(team) > 0.0 else fb.rect.end.x
	var g_opp := Vector3(gx_opp, fb.goal_height + 0.7, mid.y)
	var pr := _project(cam, g_opp, 90.0)
	var gold := Palette.FLOWER_YELLOW
	var d_goal := me.distance_to(Vector2(gx_opp, mid.y))
	if pr.on:
		_text((pr.pos as Vector2) + Vector2(0, -8), "▼ SÚT VÀO ĐÂY  ·  %d m" % int(d_goal), 18, gold)
	else:
		_arrow(pr.edge, pr.dir, 13.0, gold)
		_text((pr.edge as Vector2) - (pr.dir as Vector2) * 34.0 + Vector2(0, 6), "Khung thành đối phương %d m" % int(d_goal), 14, gold)
	var po := _project(cam, Vector3(gx_own, fb.goal_height + 0.7, mid.y), 90.0)
	if po.on:
		_text((po.pos as Vector2) + Vector2(0, -8), "Khung thành nhà", 14, SOFT)
	# Cầu thủ: dấu ▼ màu đội trên đầu (đồng đội đậm, đối thủ nhạt)
	for p: Dictionary in fb.players:
		var v: Villager = p.v
		if not is_instance_valid(v):
			continue
		var head := v.global_position + Vector3(0, 1.95 if v.role != "kid" else 1.5, 0)
		if cam.is_position_behind(head):
			continue
		var sp := cam.unproject_position(head)
		var dist := cam.global_position.distance_to(head)
		var r := clampf(130.0 / maxf(dist, 1.0), 5.0, 13.0)
		var mate := int(p.team) == team
		var col := TEAM_COLORS[int(p.team)]
		col.a = 0.95 if mate else 0.6
		var tri := PackedVector2Array([sp + Vector2(-r, -r * 1.5), sp + Vector2(r, -r * 1.5), sp])
		draw_colored_polygon(tri, col)
		if mate:
			tri.append(tri[0])
			draw_polyline(tri, WHITE, 1.5, true)
	# Chỗ đặt bóng khi bạn được đá lại
	if fb.phase == Football.Phase.RESTART and fb._restart.get("taker") is String:
		var rp: Vector3 = fb._restart.get("pos", fb._ball_pos)
		var pk := _project(cam, rp + Vector3(0, 0.9, 0))
		if pk.on:
			_text((pk.pos as Vector2) + Vector2(0, -26), "BẠN ĐÁ Ở ĐÂY", 16, gold)
	# Quả bóng: vòng trắng + số mét; ngoài tầm nhìn thì mũi tên ở mép màn hình
	var ball := fb._ball_pos
	var d_ball := me.distance_to(Vector2(ball.x, ball.z))
	var reach := fb._ball_in_reach() and fb._user_can_touch()
	var bcol := gold if reach else WHITE
	var pb := _project(cam, ball, 150.0)      # lề rộng: mũi tên ở mép dưới không đè lên khung lời nhắc
	if pb.on:
		var rr := clampf(260.0 / maxf(cam.global_position.distance_to(ball), 1.0), 9.0, 46.0)
		var pulse := 1.0 + (0.12 * sin(_t * 8.0) if reach else 0.0)
		draw_arc(pb.pos, rr * pulse, 0.0, TAU, 32, DARK, 5.0, true)
		draw_arc(pb.pos, rr * pulse, 0.0, TAU, 32, bcol, 2.5, true)
		if d_ball > fb.user_reach:
			_text((pb.pos as Vector2) + Vector2(0, -rr - 8.0), "BÓNG  %d m" % int(d_ball), 15, bcol)
	else:
		_arrow(pb.edge, pb.dir, 18.0, bcol)
		var lbl := "BÓNG Ở CHÂN BẠN" if reach else ("BÓNG  %d m" % int(d_ball))
		_text((pb.edge as Vector2) - (pb.dir as Vector2) * 44.0 + Vector2(0, 6), lbl, 17, bcol)


func _draw_prompt() -> void:
	var c := Vector2(size.x * 0.5, size.y - 96.0)
	var msg := fb.user_prompt()
	var w := maxf(_bold.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 48.0, 360.0)
	_box(Rect2(c.x - w * 0.5, c.y - 30.0, w, 44.0))
	_text(c, msg, 20, WHITE)
	if fb._charging:
		# Thanh lực sút
		var bw := 360.0
		var r := Rect2(c.x - bw * 0.5, c.y - 62.0, bw, 16.0)
		_box(r.grow(4.0), PANEL, 8)
		var col := Palette.FLOWER_YELLOW.lerp(Palette.FLAG_RED, clampf((fb._charge - 0.6) / 0.4, 0.0, 1.0))
		draw_rect(Rect2(r.position, Vector2(bw * fb._charge, r.size.y)), col)
		_text(Vector2(c.x, r.position.y - 8.0), "LỰC SÚT — thả chuột để sút", 14, WHITE)


## Sa bàn sân: hướng tấn công của bạn quay lên trên.
func _draw_radar() -> void:
	var k := 8.0                                     # px / m
	var pw := fb.rect.size.y * k                     # bề ngang sân → ngang sa bàn
	var ph := fb.rect.size.x * k                     # chiều dài sân → dọc sa bàn
	var o := Vector2(size.x - pw - 34.0, size.y - ph - 44.0)
	var dir := fb._attack_dir(fb.user_team)
	var mid := fb.rect.get_center()
	var cen := o + Vector2(pw, ph) * 0.5
	_box(Rect2(o - Vector2(12, 30), Vector2(pw + 24, ph + 44)))
	_text(Vector2(cen.x, o.y - 10.0), "▲ hướng tấn công", 13, Palette.FLOWER_YELLOW)
	draw_rect(Rect2(o, Vector2(pw, ph)), Color(0.36, 0.6, 0.3, 0.9))
	draw_rect(Rect2(o, Vector2(pw, ph)), SOFT, false, 1.5)
	draw_line(Vector2(o.x, cen.y), Vector2(o.x + pw, cen.y), SOFT, 1.0)
	draw_arc(cen, 2.5 * k, 0.0, TAU, 24, SOFT, 1.0)
	var gw := fb.goal_width * k
	draw_rect(Rect2(cen.x - gw * 0.5, o.y - 5.0, gw, 5.0), Palette.FLOWER_YELLOW)                       # khung thành đối phương
	draw_rect(Rect2(cen.x - gw * 0.5, o.y + ph, gw, 5.0), TEAM_COLORS[fb.user_team])                    # khung thành nhà
	var to_map := func(x: float, z: float) -> Vector2:
		var q := cen + Vector2((z - mid.y) * dir, -(x - mid.x) * dir) * k
		return Vector2(clampf(q.x, o.x - 8.0, o.x + pw + 8.0), clampf(q.y, o.y - 8.0, o.y + ph + 8.0))
	for p: Dictionary in fb.players:
		var v: Villager = p.v
		if is_instance_valid(v):
			draw_circle(to_map.call(v.global_position.x, v.global_position.z), 4.5, TEAM_COLORS[int(p.team)])
	var bp: Vector2 = to_map.call(fb._ball_pos.x, fb._ball_pos.z)
	draw_circle(bp, 4.0, DARK)
	draw_circle(bp, 3.0, WHITE)
	# Bạn: mũi tên theo hướng nhìn
	if fb.first_person != null:
		var f := -fb.first_person.global_transform.basis.z
		var me := fb._user_pos2()
		var hd := Vector2(f.z * dir, -f.x * dir).normalized()
		_arrow(to_map.call(me.x, me.y), hd, 9.0, WHITE)


func _draw_keys() -> void:
	var lines: Array[String] = ["Chuột trái (giữ rồi thả): sút", "Chuột phải: chuyền", "Q: gọi chuyền",
			"Chạy vào bóng: dẫn bóng  ·  Shift: chạy", "V / Esc: rời sân"]
	var o := Vector2(24.0, size.y - 34.0 - lines.size() * 22.0)
	_box(Rect2(o - Vector2(10, 22), Vector2(330, lines.size() * 22.0 + 14.0)))
	for i in lines.size():
		_text(o + Vector2(0, i * 22.0), lines[i], 14, SOFT, false, HORIZONTAL_ALIGNMENT_LEFT)
