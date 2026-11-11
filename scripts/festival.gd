class_name Festival
extends Node3D
## Lễ hội theo lịch âm (mục 41). Đồ trang trí dựng sẵn một lần, bật / tắt theo ngày:
## - **Tết** (25 tháng Chạp → mùng 7 tháng Giêng): cây nêu ở sân đình và ngoài cổng làng, câu đối đỏ + băng rôn "CHÚC MỪNG
##   NĂM MỚI" ở cổng làng, cành đào trước cổng mỗi nhà, dây cờ đuôi nheo dọc đường trục. Giao thừa (0:00 mùng 1) và sáng
##   mùng 1 (6:00) đốt pháo ở sân đình. Mùng 1–7: chúc Tết dân làng → người lớn mừng tuổi (lì xì), trẻ con xin mừng tuổi.
## - **Rằm tháng Giêng** (13–15 tháng Giêng): dây cờ hội dọc đường trục (đình đã có cờ ngũ sắc ngày rằm).
## - **Trung thu** (13–15 tháng Tám): dây cờ + đèn ông sao to ở cổng, mâm cỗ trông trăng ở sân đình; tối rằm
##   `parade_hours` trẻ con cầm đèn ông sao rước đèn dọc đường trục (cổng ↔ đình), trống ếch đi theo.

@export var calendar: LunarCalendar
@export var day_night: DayNight
@export var weather: Weather
@export var village: Village
@export var villagers: Villagers
@export var market: Market
@export var inventory: Inventory
@export var soundscape: Soundscape
@export var random_seed: int = 815
## Giờ rước đèn tối rằm tháng Tám.
@export var parade_hours: Vector2 = Vector2(18.4, 20.8)
## Tiền mừng tuổi người lớn cho người chơi (nghìn đồng).
@export var lixi_range: Vector2i = Vector2i(2, 5)

var mode: String = ""                 # "", "tet", "gieng", "trungthu"
## Tên những người đã chúc Tết năm nay (lưu cùng game).
var lixi: Array[String] = []
var lixi_year: int = 0
var firecrackers: int = 0             # số đợt pháo đã đốt (bài thử đọc)
var _tet: Node3D
var _bunting: Node3D
var _moon: Node3D
var _rng := RandomNumberGenerator.new()
var _check: float = 0.0
var _last_hour: float = -1.0
var _crack_t: float = 0.0
var _pop_t: float = 0.0
var _crack_pos: Vector3
var _sparks: CPUParticles3D
var _star_mesh: ArrayMesh
var _star_mat: StandardMaterial3D
var _drum_t: float = 0.0
var _drum_i: int = 0


func _ready() -> void:
	_rng.seed = random_seed
	if village == null:
		return
	_build.call_deferred()


static func _xf(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


func _build() -> void:
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.vertex_color_use_as_albedo = true
	_star_mat.vertex_color_is_srgb = true
	_star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_star_mesh = _make_star()
	_build_bunting()
	_build_tet()
	_build_moon()
	_apply()


## Ngôi sao năm cánh (đèn ông sao): cánh đỏ, viền trong vàng.
func _make_star() -> ArrayMesh:
	var mb := MeshBuilder.new(5, 0.0)
	var pts: Array[Vector3] = []
	for i in 10:
		var a := PI * 0.5 + i * TAU / 10.0
		var r := 0.24 if i % 2 == 0 else 0.1
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0))
	for i in 10:
		var col := Palette.FLAG_RED if i % 2 == 0 else Palette.FLAG_STAR
		mb.add_triangle(Vector3.ZERO, pts[i], pts[(i + 1) % 10], col, Vector3(0, 0, -1))
	return mb.commit()


## Dây cờ đuôi nheo căng ngang đường trục, mỗi ~9 m một dây giữa hai cột tre.
func _build_bunting() -> void:
	_bunting = Node3D.new()
	_bunting.name = "Bunting"
	add_child(_bunting)
	var poles := MeshBuilder.new(random_seed, 0.04)
	var flags := MeshBuilder.new(random_seed + 1, 0.02)
	var cols: Array[Color] = [Palette.FLAG_RED, Palette.FLAG_STAR, Palette.SIGN_BLUE, Palette.FLOWER_PINK, Palette.VEGETABLE]
	var z0 := village.gate_point().y - 6.0
	var z1: float = village.alley_z[village.alley_z.size() - 1] + 4.0
	var z := z0
	var k := 0
	while z > z1:
		var cx := village.lane_x(z)
		var h := 3.6
		var a := Vector3(cx - 2.6, h, z)
		var b := Vector3(cx + 2.6, h, z)
		for p in [a, b]:
			poles.add_limb(Vector3(p.x, 0, p.z), p + Vector3(0, 0.3, 0), 0.05, 0.035, 5, Palette.BAMBOO_STEM)
		poles.add_limb(a, b, 0.012, 0.012, 3, Palette.STRAW)
		for j in 9:
			var t := (j + 0.5) / 9.0
			var top := a.lerp(b, t) - Vector3(0, 0.25 * sin(t * PI), 0)
			var col := cols[(j + k) % cols.size()]
			for side in [1.0, -1.0]:
				flags.add_triangle(top + Vector3(-0.2, 0, 0), top + Vector3(0.2, 0, 0), top + Vector3(0, -0.5, 0), col, top + Vector3(0, -0.2, -side))
		z -= 9.0
		k += 1
	_bunting.add_child(poles.commit_instance("Poles"))
	_bunting.add_child(flags.commit_instance("Flags", MeshBuilder.wind_material(0.12, 3.0, 0.6, 1.4)))


## Tết: cây nêu, câu đối + băng rôn ở cổng làng, cành đào trước cổng các nhà.
func _build_tet() -> void:
	_tet = Node3D.new()
	_tet.name = "Tet"
	add_child(_tet)
	var mb := MeshBuilder.new(random_seed + 2, 0.04)
	var g := village.gate_point()
	_crack_pos = village.dinh_spot + Vector3(6.0, 0.0, 3.0)
	for p: Vector3 in [_crack_pos, Vector3(g.x + 5.5, 0.0, g.y + 4.0)]:
		# Cây nêu: cây tre cao, ngọn còn túm lá, treo dải vải đỏ, khánh đất, đèn lồng
		mb.add_limb(p, p + Vector3(0.5, 9.0, 0), 0.08, 0.03, 6, Palette.BAMBOO_STEM)
		var top := p + Vector3(0.5, 9.0, 0)
		mb.add_blob(Vector3(0.6, 0.5, 0.6), Palette.BAMBOO_LEAF, _rng, 0.3, _xf(top.x, top.y - 0.3, top.z))
		mb.add_box(Vector3(0.5, 2.4, 0.03), Palette.FLAG_RED, _xf(top.x - 0.45, top.y - 3.4, top.z))
		mb.add_box(Vector3(0.36, 0.1, 0.04), Palette.FLAG_STAR, _xf(top.x - 0.45, top.y - 1.3, top.z))
		mb.add_ellipsoid(Vector3(0.16, 0.2, 0.16), Palette.ALTAR_RED, _xf(top.x + 0.35, top.y - 2.0, top.z), 7, 4)
		mb.add_limb(top + Vector3(0, -0.6, 0), top + Vector3(0.35, -1.6, 0), 0.008, 0.008, 3, Palette.STRAW)
	# Câu đối đỏ chữ vàng trên hai trụ cổng (mặt ngoài, hướng nam)
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.6, 2.6, 0.04), Palette.FLAG_RED, _xf(g.x + s * 2.95, 1.0, g.y + 0.58))
		for k in 4:
			mb.add_box(Vector3(0.3, 0.3, 0.02), Palette.FLAG_STAR, _xf(g.x + s * 2.95, 1.25 + k * 0.6, g.y + 0.61))
	_tet.add_child(mb.commit_instance("Neu"))
	var banner := Label3D.new()
	banner.text = "CHÚC MỪNG NĂM MỚI"
	banner.font = Hud.font(true)
	banner.font_size = 72
	banner.pixel_size = 0.01
	banner.modulate = Palette.FLAG_STAR
	banner.outline_size = 16
	banner.outline_modulate = Palette.FLAG_RED
	banner.position = Vector3(g.x, 5.6, g.y + 0.7)
	banner.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y      # đọc được từ trong làng lẫn ngoài cổng
	_tet.add_child(banner)
	# Cành đào trước cổng mỗi nhà (một MultiMesh)
	var pm := MeshBuilder.new(random_seed + 3, 0.05)
	pm.add_prism(0.16, 0.2, 0.3, 8, Palette.JAR, Transform3D.IDENTITY)
	pm.add_limb(Vector3(0, 0.3, 0), Vector3(0.05, 1.1, 0), 0.03, 0.02, 4, Palette.BANYAN_TRUNK)
	for k in 5:
		var a := k * TAU / 5.0
		var tip := Vector3(cos(a) * 0.45, 1.2 + (k % 2) * 0.35, sin(a) * 0.45)
		pm.add_limb(Vector3(0.03, 0.8, 0), tip, 0.018, 0.01, 3, Palette.BANYAN_TRUNK)
		pm.add_blob(Vector3(0.2, 0.16, 0.2), Palette.FLOWER_PINK, _rng, 0.3, _xf(tip.x, tip.y - 0.05, tip.z))
	pm.add_blob(Vector3(0.24, 0.2, 0.24), Palette.FLOWER_PINK.lightened(0.15), _rng, 0.3, _xf(0.05, 1.35, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pm.commit()
	mm.instance_count = village.homes.size()
	for i in village.homes.size():
		var hm: Dictionary = village.homes[i]
		var fwd: Vector3 = hm.forward
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		var gate: Vector3 = hm.gate
		var pos := Vector3(gate.x, 0.03, gate.z) - fwd * 2.2 + side * (1.4 if i % 2 == 0 else -1.4)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.25)), pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PeachTrees"
	mmi.multimesh = mm
	mmi.material_override = MeshBuilder.material()
	_tet.add_child(mmi)
	# Xác pháo bay khi đốt pháo
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 60
	_sparks.lifetime = 0.9
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 2.0
	_sparks.initial_velocity_max = 5.0
	_sparks.gravity = Vector3(0, -9.0, 0)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.06, 0.06)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Palette.FLAG_RED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = sm
	_sparks.mesh = qm
	_sparks.position = _crack_pos + Vector3(0, 0.6, 0)
	add_child(_sparks)


## Trung thu: đèn ông sao to treo ở cổng làng, mâm cỗ trông trăng ở sân đình.
func _build_moon() -> void:
	_moon = Node3D.new()
	_moon.name = "MidAutumn"
	add_child(_moon)
	var g := village.gate_point()
	var big := MeshInstance3D.new()
	big.mesh = _star_mesh
	big.material_override = _star_mat
	big.scale = Vector3.ONE * 4.0
	big.position = Vector3(g.x, 6.0, g.y + 0.3)
	_moon.add_child(big)
	var mb := MeshBuilder.new(random_seed + 4, 0.05)
	var t := village.dinh_spot + Vector3(-5.0, 0.0, 1.0)
	# Mâm cỗ: bàn gỗ, mâm ngũ quả, bánh nướng bánh dẻo, đèn kéo quân
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add_box(Vector3(0.08, 0.7, 0.08), Palette.WOOD, _xf(t.x + sx * 0.8, 0.05, t.z + sz * 0.45))
	mb.add_box(Vector3(1.9, 0.06, 1.1), Palette.WOOD_LIGHT, _xf(t.x, 0.75, t.z))
	mb.add_prism(0.42, 0.42, 0.04, 12, Palette.GOLD, _xf(t.x - 0.35, 0.81, t.z))
	mb.add_ellipsoid(Vector3(0.2, 0.18, 0.2), Palette.RICE_3, _xf(t.x - 0.35, 0.85, t.z), 8, 4)                # bưởi
	for k in 5:
		var a := k * TAU / 5.0
		var col: Color = [Palette.BANANA, Palette.FLOWER_YELLOW, Palette.ALTAR_RED, Palette.VEGETABLE, Palette.HIBISCUS][k]
		mb.add_ellipsoid(Vector3(0.09, 0.09, 0.09), col, _xf(t.x - 0.35 + cos(a) * 0.28, 0.85, t.z + sin(a) * 0.28), 6, 3)
	for k in 4:
		mb.add_prism(0.11, 0.11, 0.06, 8, Palette.WOOD_LIGHT.darkened(0.15) if k % 2 == 0 else Palette.FLOWER_WHITE,
				_xf(t.x + 0.3 + (k % 2) * 0.28, 0.81, t.z - 0.2 + (k / 2) * 0.3))
	mb.add_prism(0.16, 0.16, 0.5, 6, Palette.ALTAR_RED, _xf(t.x + 0.75, 0.81, t.z + 0.3))                      # đèn kéo quân
	mb.add_pyramid(0.2, 0.14, 6, Palette.GOLD, _xf(t.x + 0.75, 1.31, t.z + 0.3))
	_moon.add_child(mb.commit_instance("Feast"))
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.WINDOW_GLOW
	lamp.omni_range = 6.0
	lamp.light_energy = 0.0
	lamp.set_meta("max_energy", 1.4)
	lamp.add_to_group("night_light")
	lamp.position = t + Vector3(0.75, 1.3, 0.3)
	_moon.add_child(lamp)


# --- Theo ngày ------------------------------------------------------------------------------------------

## Kỳ lễ đang diễn ra theo ngày âm lịch: "tet", "gieng", "trungthu" hoặc rỗng.
func mode_now() -> String:
	if calendar == null:
		return ""
	var l := calendar.lunar()
	if bool(l.leap):
		return ""
	var d := int(l.day)
	var m := int(l.month)
	if (m == 12 and d >= 25) or (m == 1 and d <= 7):
		return "tet"
	if m == 1 and d >= 13 and d <= 15:
		return "gieng"
	if m == 8 and d >= 13 and d <= 15:
		return "trungthu"
	return ""


## Mùng 1 → mùng 7 tháng Giêng: đi chúc Tết.
func is_tet_days() -> bool:
	if calendar == null:
		return false
	var l := calendar.lunar()
	return not bool(l.leap) and int(l.month) == 1 and int(l.day) <= 7


func _apply() -> void:
	mode = mode_now()
	if _tet == null:
		return
	_tet.visible = mode == "tet"
	_bunting.visible = mode != ""
	_moon.visible = mode == "trungthu"
	if calendar != null and int(calendar.lunar().year) != lixi_year and is_tet_days():
		lixi_year = int(calendar.lunar().year)
		lixi.clear()


## Dòng cho sổ tay.
func status_text() -> String:
	match mode:
		"tet":
			return "Tết Nguyên đán — cây nêu, hoa đào khắp làng" + (" · đi chúc Tết được mừng tuổi" if is_tet_days() else " · sắp Tết")
		"gieng":
			return "Hội làng rằm tháng Giêng — cờ hội dọc đường trục"
		"trungthu":
			return "Tết Trung thu — tối rằm trẻ con rước đèn ông sao"
	return "không có lễ hội"


## Đang giờ rước đèn (tối rằm tháng Tám, trời không mưa).
func parade_time(h: float) -> bool:
	if calendar == null or mode != "trungthu" or int(calendar.lunar().day) != 15:
		return false
	if weather != null and weather.kind in ["drizzle", "storm"]:
		return false
	return h >= parade_hours.x and h < parade_hours.y


## Đích của đứa trẻ rước đèn: lần lượt đầu đường trục phía đình rồi phía cổng.
func parade_target(v: Villager) -> Vector3:
	var to_dinh := not bool(v.get_meta("parade_to_gate", false))
	var z: float = (village.alley_z[village.alley_z.size() - 1] + 3.0) if to_dinh else (village.gate_point().y - 7.0)
	return Vector3(village.lane_x(z) + _rng.randf_range(-0.8, 0.8), 0.05, z)


## Villagers gọi khi đứa trẻ tới một đầu đường: thắp đèn ông sao, quay lại đầu kia; hết giờ thì cất đèn về nhà.
func on_parade_arrive(v: Villager) -> void:
	var h := day_night.time_of_day if day_night != null else 19.0
	var lan := v.get_node_or_null("StarLantern") as Node3D
	if not parade_time(h):
		if lan != null:
			lan.visible = false
		v.remove_meta("parade_to_gate")
		v.dwell = 0.0
		return
	if lan == null:
		lan = _make_lantern(v)
	lan.visible = true
	v.set_meta("parade_to_gate", not bool(v.get_meta("parade_to_gate", false)))
	villagers._next_activity(v, "trungthu")
	v.activity_text = "đang rước đèn ông sao"


func _make_lantern(v: Villager) -> Node3D:
	var s: float = float((v.get("_look") as Dictionary).get("scale", 0.66)) if v.get("_look") is Dictionary else 0.66
	var n := Node3D.new()
	n.name = "StarLantern"
	v.add_child(n)
	var stick := MeshBuilder.new(3, 0.0)
	stick.add_limb(Vector3(0.24, 0.85 * s, 0.18), Vector3(0.3, 1.75 * s + 0.25, 0.25), 0.012, 0.01, 4, Palette.BAMBOO_STEM)
	n.add_child(stick.commit_instance("Stick"))
	var star := MeshInstance3D.new()
	star.mesh = _star_mesh
	star.material_override = _star_mat
	star.position = Vector3(0.3, 1.75 * s + 0.45, 0.25)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(star)
	if v.get_index() % 3 == 0:
		var l := OmniLight3D.new()
		l.light_color = Palette.WINDOW_GLOW
		l.omni_range = 4.5
		l.light_energy = 0.9
		l.shadow_enabled = false
		l.position = star.position
		n.add_child(l)
	return n


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		if mode_now() != mode:
			_apply()
		var h := day_night.time_of_day if day_night != null else 12.0
		# Đốt pháo: giao thừa (vừa sang mùng 1 tháng Giêng) và 6 giờ sáng mùng 1
		if _last_hour >= 0.0 and calendar != null:
			var l := calendar.lunar()
			var first := not bool(l.leap) and int(l.month) == 1 and int(l.day) == 1
			if first and ((_last_hour > 20.0 and h < 4.0) or (_last_hour < 6.0 and h >= 6.0 and h - _last_hour < 1.0)):
				light_firecrackers()
		_last_hour = h
	# Pháo nổ lách tách
	if _crack_t > 0.0:
		_crack_t -= delta
		_pop_t -= delta
		if _pop_t <= 0.0:
			_pop_t = _rng.randf_range(0.04, 0.16)
			if soundscape != null:
				soundscape.play_at("pop", _crack_pos + Vector3(_rng.randf_range(-2, 2), 1.0, _rng.randf_range(-2, 2)), _rng.randf_range(-2.0, 3.0), _rng.randf_range(0.8, 1.3))
		if _crack_t <= 0.0 and _sparks != null:
			_sparks.emitting = false
	# Trống ếch theo đoàn rước đèn: "tùng… rinh rinh"
	if mode == "trungthu" and soundscape != null and villagers != null and day_night != null and parade_time(day_night.time_of_day):
		_drum_t -= delta
		if _drum_t <= 0.0:
			_drum_i = (_drum_i + 1) % 4
			_drum_t = [0.5, 0.25, 0.25, 0.5][_drum_i]
			for v in villagers.people:
				if v.activity == "trungthu" and v.visible:
					soundscape.play_at("drum", v.global_position + Vector3(0, 1, 0), -8.0, 1.5 if _drum_i == 0 else 2.1)
					break


func light_firecrackers() -> void:
	firecrackers += 1
	_crack_t = 9.0
	_pop_t = 0.0
	if _sparks != null:
		_sparks.emitting = true


# --- Chúc Tết ---------------------------------------------------------------------------------------------

## Câu chúc Tết thêm vào khung thoại (mùng 1–7, mỗi người một lần mỗi năm).
func dialog_options(v: Villager, _dlg: Dialogue) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_tet_days():
		return out
	var real: Villager = v.get_meta("proxy_of", v)
	if lixi.has(real.display_name):
		return out
	out.append({"key": "tet", "text": "Chúc mừng năm mới {npc}{a}!", "answer": func() -> String: return greet(real)})
	return out


func greet(v: Villager) -> String:
	lixi.append(v.display_name)
	if v.role in ["kid", "herder"]:
		if inventory != null and inventory.spend(1):
			return "Em chúc {you} năm mới mạnh khoẻ, phát tài! … A, {you} mừng tuổi em ạ? Em xin! (Bạn mừng tuổi 1 nghìn)"
		return "Em chúc {you} năm mới mạnh khoẻ, phát tài ạ!"
	var n := _rng.randi_range(lixi_range.x, lixi_range.y)
	if inventory != null:
		inventory.earn(n)
	return ["Năm mới {self} chúc {you} mạnh khoẻ, làm ăn tấn tới! {Self} mừng tuổi {you} này. (Được %d nghìn)" % n,
			"Chúc {you} năm mới an khang! Lấy may đầu năm nhé, {self} mừng tuổi {you}. (Được %d nghìn)" % n][_rng.randi_range(0, 1)]
