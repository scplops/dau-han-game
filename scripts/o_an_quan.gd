class_name OAnQuan
extends Node3D
## Trò chơi dân gian Ô ăn quan (mục 27). Đang nhập vai, rủ một người trong làng chơi qua hội thoại →
## bàn kẻ phấn hiện trên mặt đất giữa hai người, người đó ngồi xổm xuống, camera nhìn xuống bàn.
## Luật (kiểu Bắc Bộ): 10 ô dân × `stones_per_square` sỏi + 2 ô quan (mỗi ô 1 viên quan to = `quan_value`
## điểm). Đến lượt: chọn một ô bên mình, rải từng viên theo một chiều (qua cả ô quan). Rải hết mà ô kế
## có sỏi → bốc lên rải tiếp; ô kế trống mà ô sau có sỏi → ăn ô đó (cách một ô trống lại ăn tiếp);
## ô kế là ô quan hoặc hai ô trống liền → mất lượt. Đến lượt mà 5 ô bên mình hết sỏi → lấy 5 viên
## đã ăn rải lại (không đủ thì thua cuộc). Hết hai quan: "hết quan tàn dân, thu quân kéo về" — sỏi
## còn bên nào về bên ấy; nhiều điểm hơn thì thắng.
## Chỉ số vòng 12 ô: 0 = quan trái, 1…5 = ô của người chơi (trái → phải), 6 = quan phải,
## 7…11 = ô của đối thủ (phải → trái). Chiều +1 = sang phải theo hàng của người chơi.

signal finished(player_score: int, npc_score: int)

@export var first_person: FirstPerson
@export var dialogue: Dialogue
@export var hud: Hud
@export var quan_value: int = 10
@export var stones_per_square: int = 5
## Luật "quan non": ô quan còn viên quan mà có ít hơn chừng này sỏi dân thì chưa được ăn (0 = bỏ luật).
@export var quan_non: int = 5
## Cạnh một ô dân (m).
@export var square_size: float = 0.34
## Thời gian rải mỗi viên / ăn một ô (giây).
@export var sow_step: float = 0.2
@export var ai_think: float = 1.0
@export var random_seed: int = 1975

const PLAYER := 0
const NPC := 1

var active: bool = false
var npc: Villager
var hard: bool = false
## Trạng thái ván: cnt = sỏi dân trong 12 ô, big = [quan trái còn, quan phải còn],
## score = điểm đã ăn, stock = số sỏi dân đã ăn (để rải lại khi hết ô).
var st: Dictionary = {}
var turn: int = PLAYER
var over: bool = false

var _rng := RandomNumberGenerator.new()
var _board: Node3D
var _cam: Camera3D
var _stones: Array = []          # 12 mảng node sỏi, mỗi ô một mảng
var _hand: Array[Node3D] = []
var _pile: Array = [[], []]      # sỏi đã ăn của mỗi bên (để hiện thành đống)
var _labels: Array[Label3D] = []
var _marks: Array[MeshInstance3D] = []
var _queue: Array = []
var _anim_t: float = 0.0
var _busy: bool = false
var _selected: int = -1
var _hover: int = -1
var _ai_timer: float = -1.0
var _saved: Dictionary = {}
var _mesh_dan: ArrayMesh
var _mesh_quan: ArrayMesh
var _mat: StandardMaterial3D
# Giao diện
var _ui: CanvasLayer
var _title: Label
var _score_label: Label
var _turn_label: Label
var _hint: Label
var _btn_left: Button
var _btn_right: Button
var _result: PanelContainer
var _result_label: Label


func _ready() -> void:
	_rng.seed = random_seed
	_build_meshes()
	_build_ui()


# --- Bắt đầu / kết thúc -----------------------------------------------------------------------

## Người này có chịu chơi không (trả về lời từ chối, rỗng = chịu).
static func refusal(v: Villager) -> String:
	if v.has_meta("in_class"):
		return "Đang giờ học, cô giáo nhắc mất!"
	if v.state == Villager.State.WALK and v.activity in ["field", "graze", "well", "river", "school", "worship", "shelter"]:
		return "Để lúc khác nhé, {self} đang dở việc."
	if v.activity in ["field", "fishing", "river", "football", "worship"] and not v.role in ["kid", "herder"]:
		return "Đang bận tay, lúc khác {self} chơi với {you} nhé."
	return ""


## Bày bàn giữa người chơi và `v`, bắt đầu ván (người chơi đi trước).
func start(v: Villager) -> void:
	if active or v == null:
		return
	npc = v
	hard = v.role == "elder" or (v.role in ["farmer", "carrier"] and _rng.randf() < 0.5)
	active = true
	over = false
	var p := first_person.global_position if first_person != null else v.global_position + Vector3(0, 0, 2)
	var d := Vector3(v.global_position.x - p.x, 0, v.global_position.z - p.z)
	if d.length() < 0.3:
		d = Vector3(0, 0, -1)
	d = d.normalized()
	var center := p + d * 1.0
	center.y = _ground_y(center, p.y)
	var z := -d
	var x := Vector3.UP.cross(z).normalized()
	_board.global_transform = Transform3D(Basis(x, Vector3.UP, z), center)
	_board.visible = true
	# Đối thủ ngồi xổm phía bên kia bàn, quay mặt vào bàn
	_saved = {"anim": v.work_anim, "pos": v.global_position, "rot": v.rotation.y}
	v.set_meta("talking", true)
	v.set_meta("playing_oaq", true)
	v.global_position = center - z * 0.72
	v.rotation.y = atan2(z.x, z.z)
	v.work_anim = "squat"
	# Người chơi nhường camera
	if first_person != null:
		first_person._suspend("game")
	# Nhìn chéo từ sau lưng người chơi: thấy cả bàn lẫn người ngồi đối diện
	_cam.global_position = center + z * 1.55 + Vector3(0, 1.75, 0)
	_cam.look_at(center - z * 0.45 + Vector3(0, 0.28, 0), Vector3.UP)
	_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud != null:
		hud.visible = false
	_ui.visible = true
	_new_game()
	_say(_rng_pick(["{You} đi trước đi, {self} nhường đấy.", "Chơi thì chơi! {You} đi trước."]))


func _new_game() -> void:
	# Array (kiểu tham chiếu) — KHÔNG dùng PackedInt32Array: gán sang biến khác rồi sửa sẽ sửa bản sao
	var cnt: Array = []
	for i in 12:
		cnt.append(0 if _is_quan(i) else stones_per_square)
	st = {"cnt": cnt, "big": [true, true], "score": [0, 0], "stock": [0, 0]}
	turn = PLAYER
	over = false
	_queue.clear()
	_busy = false
	_ai_timer = -1.0
	_result.visible = false
	_rebuild_stones()
	_begin_turn()


## Thôi chơi (Esc) hoặc chơi xong: trả người, trả camera.
func stop() -> void:
	if not active:
		return
	active = false
	_board.visible = false
	_ui.visible = false
	if hud != null:
		hud.visible = true
	if is_instance_valid(npc):
		npc.remove_meta("talking")
		npc.remove_meta("playing_oaq")
		npc.work_anim = str(_saved.get("anim", "idle"))
	var ps: int = st.score[PLAYER]
	var ns: int = st.score[NPC]
	npc = null
	if first_person != null:
		first_person._resume()
	finished.emit(ps, ns)


func _ground_y(p: Vector3, fallback: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p + Vector3(0, -2.0, 0), 1 << (FirstPerson.SOLID_LAYER - 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) + 0.005 if not hit.is_empty() else fallback


# --- Luật (thuần dữ liệu — AI và bài thử dùng chung) -------------------------------------------

static func _is_quan(i: int) -> bool:
	return i == 0 or i == 6


static func _wrap(i: int) -> int:
	return (i % 12 + 12) % 12


static func row_of(who: int) -> Array[int]:
	var out: Array[int] = []
	var first := 1 if who == PLAYER else 7
	for k in 5:
		out.append(first + k)
	return out


## Số "thứ" trong ô (ô quan còn viên quan to cũng tính là có).
static func amount(s: Dictionary, i: int) -> int:
	var a: int = int((s.cnt as Array)[i])
	if i == 0 and bool(s.big[0]):
		a += 1
	if i == 6 and bool(s.big[1]):
		a += 1
	return a


static func copy_state(s: Dictionary) -> Dictionary:
	return {"cnt": (s.cnt as Array).duplicate(), "big": (s.big as Array).duplicate(),
			"score": (s.score as Array).duplicate(), "stock": (s.stock as Array).duplicate()}


static func legal_moves(s: Dictionary, who: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in row_of(who):
		if (s.cnt as Array)[i] > 0:
			out.append(Vector2i(i, -1))
			out.append(Vector2i(i, 1))
	return out


## Đi một nước (sửa `s`), trả về chuỗi sự kiện để diễn hoạt:
## ["pick", ô] bốc · ["drop", ô] rải một viên · ["take", ô, bên] ăn cả ô.
static func play(s: Dictionary, sq: int, dir: int, who: int, qv: int, qn: int = 5) -> Array:
	var cnt: Array = s.cnt
	var ev: Array = []
	var hand: int = cnt[sq]
	cnt[sq] = 0
	ev.append(["pick", sq])
	var pos := sq
	while true:
		while hand > 0:
			pos = _wrap(pos + dir)
			cnt[pos] += 1
			hand -= 1
			ev.append(["drop", pos])
		var nxt := _wrap(pos + dir)
		if _is_quan(nxt):
			break                         # gặp ô quan: mất lượt
		if cnt[nxt] > 0:
			hand = int(cnt[nxt])          # ô kế có sỏi: bốc lên rải tiếp
			cnt[nxt] = 0
			pos = nxt
			ev.append(["pick", nxt])
			continue
		# Ô kế trống: ăn ô sau nó (nếu có), cách một ô trống lại ăn tiếp
		var target := _wrap(nxt + dir)
		while amount(s, target) > 0:
			if _quan_young(s, target, qn):
				break                     # quan non: chưa được ăn
			var gain: int = cnt[target]
			s.stock[who] = int(s.stock[who]) + int(cnt[target])
			if target == 0 and bool(s.big[0]):
				gain += qv
				s.big[0] = false
			elif target == 6 and bool(s.big[1]):
				gain += qv
				s.big[1] = false
			cnt[target] = 0
			s.score[who] = int(s.score[who]) + gain
			ev.append(["take", target, who])
			var gap := _wrap(target + dir)
			var after := _wrap(gap + dir)
			if amount(s, gap) == 0 and amount(s, after) > 0:
				target = after
			else:
				break
		break
	return ev


## Ô quan còn viên quan nhưng chưa đủ `qn` sỏi dân ("quan non").
static func _quan_young(s: Dictionary, i: int, qn: int) -> bool:
	if not _is_quan(i) or qn <= 0:
		return false
	var has_big := bool(s.big[0]) if i == 0 else bool(s.big[1])
	return has_big and int((s.cnt as Array)[i]) < qn


## Hết hai quan (cả viên quan lẫn sỏi trong ô quan) thì hết ván.
static func is_over(s: Dictionary) -> bool:
	return amount(s, 0) == 0 and amount(s, 6) == 0


## Thu quân: sỏi còn lại hàng bên nào về bên ấy.
static func collect(s: Dictionary) -> Array:
	var ev: Array = []
	for who in [PLAYER, NPC]:
		for i in row_of(who):
			var c: int = int((s.cnt as Array)[i])
			if c > 0:
				s.score[who] = int(s.score[who]) + c
				(s.cnt as Array)[i] = 0
				ev.append(["take", i, who])
	return ev


## Đầu lượt: hàng của `who` hết sỏi thì rải lại 5 viên đã ăn. Trả về [được đi tiếp?, sự kiện].
static func refill(s: Dictionary, who: int) -> Array:
	for i in row_of(who):
		if (s.cnt as Array)[i] > 0:
			return [true, []]
	if int(s.stock[who]) < 5:
		return [false, []]
	var ev: Array = []
	s.stock[who] = int(s.stock[who]) - 5
	s.score[who] = int(s.score[who]) - 5
	for i in row_of(who):
		(s.cnt as Array)[i] = 1
		ev.append(["give", i, who])
	return [true, ev]


## Máy chọn nước: tham ăn nhiều nhất; chơi khó thì trừ nước đáp trả tốt nhất của người chơi.
func ai_move(s: Dictionary, who: int) -> Vector2i:
	var best := Vector2i(-1, 1)
	var best_v := -INF
	for m in legal_moves(s, who):
		var s2 := copy_state(s)
		play(s2, m.x, m.y, who, quan_value, quan_non)
		var v := float(int(s2.score[who]) - int(s.score[who]))
		if hard and not is_over(s2):
			var other := 1 - who
			var reply := 0.0
			var s3 := copy_state(s2)
			refill(s3, other)
			for r in legal_moves(s3, other):
				var s4 := copy_state(s3)
				play(s4, r.x, r.y, other, quan_value, quan_non)
				reply = maxf(reply, float(int(s4.score[other]) - int(s3.score[other])))
			v -= reply * 0.9
			v += _rng.randf() * 0.5
		else:
			v += _rng.randf() * 4.0      # chơi dễ: hay đi bừa
		if v > best_v:
			best_v = v
			best = m
	return best


# --- Diễn biến ván ------------------------------------------------------------------------------

func _begin_turn() -> void:
	if is_over(st):
		_finish()
		return
	var r := refill(st, turn)
	if not bool(r[0]):
		# Hết sỏi mà không đủ 5 viên để rải lại: thua cuộc, bên kia thu hết
		_queue.append_array(collect(st))
		_queue.append(["over"])
		over = true
		_busy = true
		return
	if not (r[1] as Array).is_empty():
		_queue.append_array(r[1])
		_busy = true
		if turn == NPC:
			_say("Hết quân rồi, {self} phải rải lại vậy.")
	_selected = -1
	if turn == PLAYER:
		var moves := legal_moves(st, PLAYER)
		_selected = moves[0].x if not moves.is_empty() else -1
	else:
		_ai_timer = ai_think
	_update_ui()


func _do_move(sq: int, dir: int) -> void:
	if over or _busy:
		return
	var before_big: Array = (st.big as Array).duplicate()
	var ev := play(st, sq, dir, turn, quan_value, quan_non)
	_queue.append_array(ev)
	_queue.append(["end_turn", turn, before_big])
	_busy = true
	_selected = -1
	_update_ui()


func _finish() -> void:
	_queue.append_array(collect(st))
	_queue.append(["over"])
	over = true
	_busy = true


func _show_result() -> void:
	var ps: int = st.score[PLAYER]
	var ns: int = st.score[NPC]
	var line := ""
	if ps > ns:
		line = "Bạn thắng!  %d – %d" % [ps, ns]
		_say(_rng_pick(["Giỏi quá! {Self} chịu thua {you} rồi.", "Ván này {you} thắng, ván sau {self} gỡ!"]))
	elif ps < ns:
		line = "%s thắng  %d – %d" % [npc.display_name, ns, ps]
		_say(_rng_pick(["Hì hì, {self} thắng nhé!", "Phải tập thêm đi {you} ạ!"]))
	else:
		line = "Hoà  %d – %d" % [ps, ns]
		_say("Hoà rồi! Chơi ván nữa không?")
	_result_label.text = line + "\n\nE: chơi ván nữa   ·   Esc: thôi"
	_result.visible = true
	_update_ui()


func _process(delta: float) -> void:
	if not active:
		return
	if is_instance_valid(npc):
		npc.tick(delta, true)
	if not _queue.is_empty():
		_anim_t -= delta
		if _anim_t <= 0.0:
			_run_event(_queue.pop_front())
		return
	if _busy:
		_busy = false
		_update_ui()
	if over:
		return
	if turn == NPC and _ai_timer > 0.0:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			var m := ai_move(st, NPC)
			if m.x >= 0:
				_do_move(m.x, m.y)


## Diễn một sự kiện (hiển thị) — trạng thái `st` đã tính xong từ trước.
func _run_event(e: Array) -> void:
	_anim_t = sow_step
	match str(e[0]):
		"pick":
			var i: int = e[1]
			var keep: Array = []
			for n: Node3D in _stones[i]:
				if n.has_meta("quan"):
					keep.append(n)
				else:
					_hand.append(n)
			_stones[i] = keep
			_layout_hand(_square_center(i))
			_anim_t = sow_step * 1.4
		"drop":
			var i: int = e[1]
			if not _hand.is_empty():
				var n: Node3D = _hand.pop_back()
				_stones[i].append(n)
				_tween_to(n, _slot(i, (_stones[i] as Array).size() - 1))
			_layout_hand(_square_center(i))
		"take", "give":
			var i: int = e[1]
			var who: int = e[2]
			if e[0] == "take":
				for n: Node3D in _stones[i]:
					_pile[who].append(n)
					_tween_to(n, _pile_slot(who, (_pile[who] as Array).size() - 1, n.has_meta("quan")))
				_stones[i] = []
				_anim_t = sow_step * 2.5
			else:
				# Rải lại: lấy một viên dân từ đống của mình
				for k in range((_pile[who] as Array).size() - 1, -1, -1):
					var n: Node3D = _pile[who][k]
					if not n.has_meta("quan"):
						_pile[who].remove_at(k)
						_stones[i].append(n)
						_tween_to(n, _slot(i, 0))
						break
		"end_turn":
			var who: int = e[1]
			var before: Array = e[2]
			for q in 2:
				if bool(before[q]) and not bool(st.big[q]):
					_say("Ăn quan rồi nhé!" if who == NPC else _rng_pick(["Ối, mất quan của {self} rồi!", "Chà, {you} ăn được quan!"]))
			turn = 1 - who
			_hand.clear()
			_begin_turn()
		"over":
			_show_result()
	_update_counts()


# --- Điều khiển ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("exit_interior"):
		stop()
		get_viewport().set_input_as_handled()
		return
	if over and not _busy and event.is_action_pressed("interact"):
		_new_game()
		get_viewport().set_input_as_handled()
		return
	var mine := turn == PLAYER and not _busy and not over
	if event is InputEventMouseMotion:
		_hover = _square_at((event as InputEventMouseMotion).position)
		_update_marks()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and mine:
		var sq := _square_at((event as InputEventMouseButton).position)
		if sq > 0 and (st.cnt as Array)[sq] > 0:
			_selected = sq
			_update_ui()
		get_viewport().set_input_as_handled()
	elif mine and _selected > 0:
		if event.is_action_pressed("cam_left"):
			_do_move(_selected, -1)
		elif event.is_action_pressed("cam_right"):
			_do_move(_selected, 1)
		elif event.is_action_pressed("cam_forward") or event.is_action_pressed("cam_back"):
			_step_selection(1 if event.is_action_pressed("cam_back") else -1)
		else:
			return
		get_viewport().set_input_as_handled()


func _step_selection(step: int) -> void:
	var row := row_of(PLAYER)
	var k := row.find(_selected)
	for t in 5:
		k = (k + step + 5) % 5
		if (st.cnt as Array)[row[k]] > 0:
			_selected = row[k]
			break
	_update_ui()


## Ô của người chơi dưới con trỏ chuột (1…5), -1 nếu không trúng.
func _square_at(screen: Vector2) -> int:
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	var plane := Plane(Vector3.UP, _board.global_position.y)
	var hit: Variant = plane.intersects_ray(from, dir)
	if hit == null:
		return -1
	var lp := _board.to_local(hit as Vector3)
	var s := square_size
	if lp.z < 0.0 or lp.z > s or absf(lp.x) > 2.5 * s:
		return -1
	return clampi(int(floor(lp.x / s + 2.5)) + 1, 1, 5)


# --- Hình: bàn, sỏi ----------------------------------------------------------------------------

func _square_center(i: int) -> Vector3:
	var s := square_size
	if i == 0:
		return Vector3(-2.5 * s - s * 0.45, 0, 0)
	if i == 6:
		return Vector3(2.5 * s + s * 0.45, 0, 0)
	if i <= 5:
		return Vector3((i - 3) * s, 0, s * 0.5)
	return Vector3((9 - i) * s, 0, -s * 0.5)


## Chỗ của viên thứ k trong ô (xoắn ốc nhỏ quanh tâm ô, cao dần khi đông).
func _slot(i: int, k: int) -> Vector3:
	var c := _square_center(i)
	if k == 0:
		return c + Vector3(0, 0.012, 0)
	var a := k * 2.39996
	var r := minf(0.028 * sqrt(float(k)) + 0.014, square_size * 0.38)
	return c + Vector3(cos(a) * r, 0.012 + floor(k / 14.0) * 0.016, sin(a) * r)


func _pile_slot(who: int, k: int, quan: bool) -> Vector3:
	var base := Vector3(1.55 * square_size * 2.0, 0, square_size * 1.55) if who == PLAYER else Vector3(-1.55 * square_size * 2.0, 0, -square_size * 1.55)
	if quan:
		return base + Vector3(0.0 if who == PLAYER else 0.0, 0.03, 0.12 if who == PLAYER else -0.12)
	var a := k * 2.39996
	var r := 0.02 * sqrt(float(k))
	return base + Vector3(cos(a) * r, 0.012 + floor(k / 25.0) * 0.015, sin(a) * r)


func _layout_hand(at: Vector3) -> void:
	for k in _hand.size():
		var a := k * 2.39996
		_tween_to(_hand[k], at + Vector3(cos(a) * 0.03, 0.22 + k * 0.006, sin(a) * 0.03))


func _tween_to(n: Node3D, p: Vector3) -> void:
	var t := create_tween()
	t.tween_property(n, "position", p, sow_step * 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_meshes() -> void:
	_mat = MeshBuilder.material()
	var a := MeshBuilder.new(31, 0.0)
	a.add_ellipsoid(Vector3(0.024, 0.015, 0.02), Color.WHITE, Transform3D.IDENTITY, 6, 3, false)
	_mesh_dan = a.commit()
	var b := MeshBuilder.new(32, 0.0)
	b.add_ellipsoid(Vector3(0.05, 0.03, 0.042), Palette.ROCK_DARK.darkened(0.25), Transform3D.IDENTITY, 8, 4, false)
	_mesh_quan = b.commit()
	_board = Node3D.new()
	_board.name = "Board"
	_board.top_level = true
	_board.visible = false
	add_child(_board)
	# Mặt đất nện + đường phấn kẻ ô, hai ô quan bán nguyệt
	var mb := MeshBuilder.new(33, 0.03)
	var s := square_size
	var L := 5.0 * s
	mb.add_box(Vector3(L + 2.0 * s + 0.24, 0.006, 2.0 * s + 0.24), Palette.EARTH.darkened(0.08), Transform3D(Basis(), Vector3(0, 0.0, 0)))
	var chalk := Palette.FLOWER_WHITE
	var w := 0.012
	for z in [-s, 0.0, s]:
		mb.add_box(Vector3(L, 0.004, w), chalk, Transform3D(Basis(), Vector3(0, 0.006, z)))
	for k in 6:
		mb.add_box(Vector3(w, 0.004, 2.0 * s), chalk, Transform3D(Basis(), Vector3(-L * 0.5 + k * s, 0.006, 0)))
	for side: float in [-1.0, 1.0]:
		var cx := side * L * 0.5
		for k in 12:
			var a0 := -PI * 0.5 + PI * k / 12.0
			var a1 := -PI * 0.5 + PI * (k + 1) / 12.0
			var p0 := Vector3(cx + side * cos(a0) * s, 0.006, sin(a0) * s)
			var p1 := Vector3(cx + side * cos(a1) * s, 0.006, sin(a1) * s)
			var mid := (p0 + p1) * 0.5
			var seg := p1 - p0
			mb.add_box(Vector3(seg.length() + 0.004, 0.004, w), chalk, Transform3D(Basis(Vector3.UP, -atan2(seg.z, seg.x)), mid))
	_board.add_child(mb.commit_instance("Chalk"))
	# Số sỏi mỗi ô + đánh dấu ô đang chọn
	for i in 12:
		var l := Label3D.new()
		l.font = Hud.font(true)
		l.font_size = 40
		l.pixel_size = 0.0011
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Palette.HUD_TEXT
		l.outline_size = 8
		l.outline_modulate = Palette.WINDOW_DARK
		l.no_depth_test = true
		var c := _square_center(i)
		var off := Vector3(0, 0.1, 0)
		if i >= 1 and i <= 5:
			off.z = s * 0.38
		elif i >= 7:
			off.z = -s * 0.38
		l.position = c + off
		_board.add_child(l)
		_labels.append(l)
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s - 0.03, 0.003, s - 0.03)
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.albedo_color = Color(Palette.FLOWER_YELLOW, 0.4)
		bm.material = mm
		m.mesh = bm
		m.position = c + Vector3(0, 0.008, 0)
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_board.add_child(m)
		_marks.append(m)
	_cam = Camera3D.new()
	_cam.name = "BoardCam"
	_cam.top_level = true
	_cam.fov = 50.0
	_cam.near = 0.05
	add_child(_cam)


func _new_stone(quan: bool) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = _mesh_quan if quan else _mesh_dan
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if quan:
		n.set_meta("quan", true)
	else:
		# Sỏi màu lệch nhau: trắng ngà, xám, nâu đất
		var mat := StandardMaterial3D.new()
		mat.albedo_color = [Palette.FLOWER_WHITE, Palette.ROCK, Palette.ROCK_DARK, Palette.EARTH.lightened(0.2)][_rng.randi_range(0, 3)]
		mat.roughness = 1.0
		n.material_override = mat
	n.rotation.y = _rng.randf() * TAU
	_board.add_child(n)
	return n


func _rebuild_stones() -> void:
	for arr in _stones:
		for n: Node in arr:
			n.queue_free()
	for arr in _pile:
		for n: Node in arr:
			n.queue_free()
	for n in _hand:
		n.queue_free()
	_hand.clear()
	_pile = [[], []]
	_stones = []
	for i in 12:
		var arr: Array = []
		if _is_quan(i):
			var q := _new_stone(true)
			q.position = _slot(i, 0)
			arr.append(q)
		else:
			for k in stones_per_square:
				var n := _new_stone(false)
				n.position = _slot(i, k + 1)
				arr.append(n)
		_stones.append(arr)
	_update_counts()


func _update_counts() -> void:
	for i in 12:
		var dan := 0
		var big := false
		for n: Node3D in _stones[i]:
			if n.has_meta("quan"):
				big = true
			else:
				dan += 1
		_labels[i].text = ("Q+%d" % dan if big else str(dan)) if _is_quan(i) else str(dan)
	_update_ui()


func _update_marks() -> void:
	for i in 12:
		var on := i == _selected or (i == _hover and turn == PLAYER and i >= 1 and i <= 5 and not _busy and not over)
		_marks[i].visible = on
		((_marks[i].mesh as BoxMesh).material as StandardMaterial3D).albedo_color = Color(Palette.FLOWER_YELLOW, 0.5 if i == _selected else 0.22)


# --- Giao diện ----------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var top := _panel()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 16
	root.add_child(top)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(box)
	_title = _label(true, 22, Palette.FLOWER_YELLOW)
	_score_label = _label(true, 28, Palette.HUD_TEXT)
	_turn_label = _label(false, 16, Palette.HUD_SUBTEXT)
	for l in [_title, _score_label, _turn_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	var bottom := _panel()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -18
	root.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bottom.add_child(row)
	_btn_left = _button("◀  Rải sang trái (A)")
	_btn_left.pressed.connect(func() -> void:
		if _selected > 0 and turn == PLAYER: _do_move(_selected, -1))
	_hint = _label(false, 16, Palette.HUD_SUBTEXT)
	_btn_right = _button("Rải sang phải (D)  ▶")
	_btn_right.pressed.connect(func() -> void:
		if _selected > 0 and turn == PLAYER: _do_move(_selected, 1))
	row.add_child(_btn_left)
	row.add_child(_hint)
	row.add_child(_btn_right)
	_result = _panel()
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result.visible = false
	root.add_child(_result)
	_result_label = _label(true, 30, Palette.HUD_TEXT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_child(_result_label)


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.HUD_BG
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(bold: bool, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Hud.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Hud.font(true))
	b.add_theme_font_size_override("font_size", 16)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _update_ui() -> void:
	if npc == null or st.is_empty():
		return
	_title.text = "Ô ăn quan  ·  " + npc.display_name + ("  (chơi khó)" if hard else "")
	_score_label.text = "Bạn  %d   –   %d  %s" % [int(st.score[PLAYER]), int(st.score[NPC]), npc.display_name]
	if over:
		_turn_label.text = "Hết quan tàn dân, thu quân kéo về!"
	elif turn == PLAYER:
		_turn_label.text = "Lượt của bạn" + ("" if _busy else "  —  chọn ô rồi chọn chiều rải")
	else:
		_turn_label.text = npc.display_name + " đang tính nước…"
	var mine := turn == PLAYER and not _busy and not over and _selected > 0
	_btn_left.disabled = not mine
	_btn_right.disabled = not mine
	_hint.text = "Bấm ô / W S: chọn ô   ·   Esc: thôi chơi" if not over else "E: ván nữa   ·   Esc: thôi"
	_update_marks()


# --- Lời nói --------------------------------------------------------------------------------------

func _say(text: String) -> void:
	if dialogue != null and is_instance_valid(npc):
		dialogue.bark(npc, dialogue.fill_for(npc, text))


func _rng_pick(arr: Array) -> String:
	return str(arr[_rng.randi_range(0, arr.size() - 1)])
