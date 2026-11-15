class_name RiverDive
extends Node3D
## Lặn mò ốc, mò trai dưới sông (mục 57). Người chơi đang bơi giữ phím lặn (`fp_dive`: C / Ctrl) thì ngụp xuống sát
## đáy sông (FirstPerson.diving) — ở đây lo phần còn lại: màn nước xanh + thanh hơi thở, ốc và trai nằm dưới đáy quanh
## các bến (chỉ nhặt được khi đang lặn tới gần: "E: Nhặt"), nhặt rồi một lúc sau mọc lại chỗ khác.
## Sông chỉ sâu "giả" (mục 49): lặn là hạ mắt xuống sát lòng bùn, không đào lòng sông.

signal picked(id: String)

@export var river: River
@export var first_person: FirstPerson
@export var inventory: Inventory
@export var hud: Hud
@export var random_seed: int = 5757
## Số ốc / trai quanh mỗi bến và quãng dọc sông rải chúng (m, tính từ bến).
@export var shells_per_landing: int = 14
@export var spread_along: float = 45.0
## Tỉ lệ là trai (còn lại là ốc).
@export_range(0.0, 1.0) var clam_ratio: float = 0.35
## Với tay nhặt được trong ngần này mét.
@export var pick_reach: float = 1.4
## Nhặt rồi bao lâu thì mọc lại (giây thật).
@export var respawn_seconds: float = 240.0
@export var tint: Color = Color(0.08, 0.34, 0.38, 0.5)

var shells: Array[Dictionary] = []     # {node, id, pos, gone (giây còn lại tới lúc mọc lại), li}
var stats := {"picked": 0, "respawned": 0}
var _rng := RandomNumberGenerator.new()
var _ui: CanvasLayer
var _tint: ColorRect
var _bar_bg: ColorRect
var _bar: ColorRect
var _label: Label
var _near: int = -1
var _meshes := {}


func _ready() -> void:
	_rng.seed = random_seed
	_build_ui()
	_build.call_deferred()


func _build() -> void:
	if river == null:
		return
	_meshes = {"oc": _snail_mesh(), "trai": _clam_mesh()}
	for li in river.landings.size():
		for k in shells_per_landing:
			var id := "trai" if _rng.randf() < clam_ratio else "oc"
			var node := MeshInstance3D.new()
			node.mesh = _meshes[id]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = 30.0
			add_child(node)
			var sh := {"node": node, "id": id, "gone": 0.0, "li": li, "pos": Vector3.ZERO}
			_place(sh)
			shells.append(sh)


## Đặt một con ốc / trai xuống đáy sông ở chỗ ngẫu nhiên quanh bến của nó.
func _place(sh: Dictionary) -> void:
	var edge: Vector3 = river.landings[int(sh.li)].edge
	var s0 := river.nearest_s(Vector2(edge.x, edge.z))
	var s := clampf(s0 + _rng.randf_range(-spread_along, spread_along), 5.0, river.length - 5.0)
	var smp := river.sample(s)
	var n := (smp[1] as Vector2).orthogonal()
	var hw := river.half_width(s)
	var q := (smp[0] as Vector2) + n * _rng.randf_range(-(hw - 2.5), hw - 2.5)
	sh.pos = Vector3(q.x, river.bed_level + 0.01, q.y)
	var node: MeshInstance3D = sh.node
	node.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), sh.pos as Vector3)
	node.visible = true


func _snail_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new(571, 0.05)
	mb.add_blob(Vector3(0.07, 0.06, 0.07), Palette.SHELL_DARK, _rng, 0.15, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	mb.add_blob(Vector3(0.045, 0.045, 0.045), Palette.SHELL_DARK.lightened(0.15), _rng, 0.15, Transform3D(Basis.IDENTITY, Vector3(0.05, 0.03, 0.0)))
	mb.add_blob(Vector3(0.025, 0.03, 0.025), Palette.SHELL_DARK.lightened(0.3), _rng, 0.1, Transform3D(Basis.IDENTITY, Vector3(0.085, 0.055, 0.0)))
	return mb.commit()


func _clam_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new(572, 0.05)
	mb.add_blob(Vector3(0.11, 0.035, 0.075), Palette.SHELL_LIGHT, _rng, 0.12, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	mb.add_blob(Vector3(0.1, 0.03, 0.07), Palette.SHELL_LIGHT.darkened(0.2), _rng, 0.12, Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(0, 0.035, 0)))
	return mb.commit()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 3
	add_child(_ui)
	_tint = ColorRect.new()
	_tint.color = tint
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.visible = false
	_ui.add_child(_tint)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_top = -150.0
	box.offset_bottom = -110.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(box)
	_label = GameKit.label(true, 17, Palette.HUD_TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)
	_bar_bg = GameKit.bar(box, 260.0, 12.0)
	_bar = ColorRect.new()
	_bar.color = Palette.WATER_LIGHT
	_bar.size = Vector2(260, 12)
	_bar_bg.add_child(_bar)
	box.visible = false
	_tint.set_meta("box", box)


## Con ốc / trai gần người chơi nhất trong tầm với (−1 nếu không có).
func nearest_shell(p: Vector3) -> int:
	var best := -1
	var best_d := pick_reach
	for i in shells.size():
		var sh := shells[i]
		if float(sh.gone) > 0.0:
			continue
		var d := Vector2(p.x - (sh.pos as Vector3).x, p.z - (sh.pos as Vector3).z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


## Nhặt con thứ `i` (đang lặn mới nhặt được). Trả về true nếu nhặt được.
func pick(i: int) -> bool:
	if i < 0 or i >= shells.size() or first_person == null or not first_person.diving:
		return false
	var sh := shells[i]
	if float(sh.gone) > 0.0:
		return false
	sh.gone = respawn_seconds
	(sh.node as MeshInstance3D).visible = false
	if inventory != null:
		inventory.add(str(sh.id))
		inventory.toast("Mò được %s" % Inventory.item_name(str(sh.id)))
	stats.picked = int(stats.picked) + 1
	picked.emit(str(sh.id))
	return true


func _unhandled_input(event: InputEvent) -> void:
	if first_person == null or not first_person.active or not first_person.diving:
		return
	if event.is_action_pressed("interact") and _near >= 0:
		pick(_near)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	for sh in shells:
		if float(sh.gone) > 0.0:
			sh.gone = float(sh.gone) - delta
			if float(sh.gone) <= 0.0:
				sh.gone = 0.0
				_place(sh)
				stats.respawned = int(stats.respawned) + 1
	var fp := first_person
	var diving := fp != null and fp.active and fp.diving
	var show_bar := fp != null and fp.active and fp.swimming and fp._suspended == ""
	_tint.visible = diving and fp._suspended == ""
	var box := _tint.get_meta("box") as Control
	box.visible = show_bar
	_near = -1
	if not show_bar:
		return
	_bar_bg.visible = diving or fp.breath < 0.999
	_bar.size.x = 260.0 * fp.breath
	_bar.color = Palette.WATER_LIGHT if fp.breath > 0.25 else Palette.FLAG_RED
	if diving:
		_near = nearest_shell(fp.global_position)
		if _near >= 0:
			_label.text = "E: Nhặt %s" % Inventory.item_name(str(shells[_near].id))
		else:
			_label.text = "Đang lặn — tìm ốc, trai dưới đáy  ·  thả C để ngoi lên"
	else:
		_label.text = "Hết hơi — ngoi lên thở đã!" if fp.breath < 0.2 else ("Đang lấy hơi…" if fp.breath < 0.999 else "Giữ C để lặn mò ốc, mò trai")
