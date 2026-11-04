class_name River
extends Node3D
## Sông hình móng ngựa ôm ba mặt làng (tây, bắc, đông), hai đầu chảy xa ra đồng.
## - Bờ: mái đất dốc xuống nước + đê đắp cao phủ cỏ + mái thoải xuống ruộng.
## - Mặt nước: shader nước (sóng nhẹ, viền sáng sát bờ), hơi trong để thấy cá.
## - Cá: MultiMesh bơi xuôi ngược dọc sông, thỉnh thoảng nhảy lên tạo gợn tròn.
## - Sen: các đầm sát bờ (lá nổi, lá vươn cao, hoa hồng/trắng, nụ), lay theo gió.
## - Vài con đò neo ven bờ.
## Đường tim sông lấy theo elip của làng (`Village.center`), nới ra `offset_radii`.

@export var village: Village
@export var random_seed: int = 5150

@export_group("Hình dáng")
@export var offset_radii: Vector2 = Vector2(120.0, 88.0)
@export var arc_degrees: Vector2 = Vector2(180.0, 360.0)     # từ tây, qua bắc, sang đông
@export var west_tail: PackedVector2Array = PackedVector2Array([Vector2(-430, -40), Vector2(-320, -44), Vector2(-225, -48), Vector2(-160, -55), Vector2(-130, -72)])
@export var east_tail: PackedVector2Array = PackedVector2Array([Vector2(130, -72), Vector2(160, -55), Vector2(225, -48), Vector2(320, -44), Vector2(430, -40)])
@export var width_range: Vector2 = Vector2(11.0, 17.0)
## Cả lòng sông nằm TRÊN nền cỏ (y = 0) để nền không lộ qua làn nước trong.
@export var bed_level: float = 0.06
@export var water_level: float = 0.32
@export var levee_height: float = 0.85
@export_range(0.3, 1.0) var water_opacity: float = 0.58

@export_group("Cá")
@export_range(0, 400) var fish_count: int = 220
@export var fish_speed: Vector2 = Vector2(0.5, 1.4)
@export var jump_interval: Vector2 = Vector2(1.2, 3.5)
@export var jump_view_distance: float = 90.0

@export_group("Sen")
@export_range(0, 40) var lotus_patches: int = 12
@export var lotus_wind: float = 0.05

@export_group("Đò")
@export_range(0, 6) var boats: int = 3

## Chiều dài sông (m), có sau build().
var length: float = 0.0
## Tâm các đầm sen và vị trí các con đò (để chụp ảnh / NPC dùng sau này).
var lotus_spots: Array[Vector3] = []
var boat_spots: Array[Vector3] = []
## Các con đò (node riêng, có vùng bấm "Lên đò"); BoatRide gắn hành động lên đò.
var boat_nodes: Array[Node3D] = []
## Bến nước ở cuối mỗi lối ra sông: {path (từ khe lũy tre tới đầu cầu ván, có độ cao),
## spot (chỗ đứng trên cầu ván), face (góc quay mặt ra sông), name,
## fish_spot (ghế ngồi câu cạnh cầu ván, mục 16)}. Có sau build().
var landings: Array[Dictionary] = []
## Chỗ ngồi câu: lệch dọc bờ so với cầu ván (m), ghế đẩu cao (m).
@export var fish_spot_offset: float = 3.0
@export var stool_height: float = 0.3

var _pts := PackedVector2Array()        # tim sông, mỗi ~2,5 m một điểm
var _cum := PackedFloat32Array()        # độ dài cộng dồn tới từng điểm
var _rng := RandomNumberGenerator.new()

# Cá
var _fish_mm: MultiMesh
var _fish: Array[Dictionary] = []
var _jump_timer: float = 0.0
var _ripples: Array[MeshInstance3D] = []
var _ripple_age: Array[float] = []
var _time: float = 0.0


func build() -> void:
	_rng.seed = random_seed
	_make_centerline()
	_build_banks()
	add_child(_build_water())
	_build_landings()
	_build_lotus()
	_build_boats()
	_build_fish()
	print("River: dài %d m, %d cá, %d đầm sen" % [int(length), fish_count, lotus_patches])


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


# --- Tim sông -------------------------------------------------------------------------

func _make_centerline() -> void:
	var c := village.center if village != null else Vector2(0, -105)
	var raw := PackedVector2Array(west_tail)
	var a := arc_degrees.x
	while a <= arc_degrees.y:
		var r := deg_to_rad(a)
		# Uốn khúc: bán kính dao động nhẹ theo góc
		var k := 1.0 + 0.045 * sin(3.0 * r + 1.0) + 0.025 * sin(7.0 * r + 0.4)
		raw.append(c + Vector2(cos(r) * offset_radii.x * k, sin(r) * offset_radii.y * k))
		a += 4.0
	raw.append_array(east_tail)
	# Làm mượt (Chaikin) rồi chia đều
	for it in 3:
		var sm := PackedVector2Array([raw[0]])
		for i in raw.size() - 1:
			sm.append(raw[i].lerp(raw[i + 1], 0.25))
			sm.append(raw[i].lerp(raw[i + 1], 0.75))
		sm.append(raw[raw.size() - 1])
		raw = sm
	_pts = Terrain._densify(raw, 2.5)
	_cum.resize(_pts.size())
	_cum[0] = 0.0
	for i in range(1, _pts.size()):
		_cum[i] = _cum[i - 1] + _pts[i].distance_to(_pts[i - 1])
	length = _cum[_cum.size() - 1]


## Nửa bề rộng sông tại độ dài s.
func half_width(s: float) -> float:
	var t := 0.5 + 0.35 * sin(s * 0.013 + 0.7) + 0.15 * sin(s * 0.041)
	return lerpf(width_range.x, width_range.y, clampf(t, 0.0, 1.0)) * 0.5


## Vị trí (x, z) và hướng chảy tại độ dài s.
func sample(s: float) -> Array:
	s = clampf(s, 0.0, length)
	var lo := 0
	var hi := _cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(_cum[hi] - _cum[lo], 0.001)
	var f := (s - _cum[lo]) / seg
	var p := _pts[lo].lerp(_pts[hi], f)
	var tan := (_pts[hi] - _pts[lo]).normalized()
	return [p, tan]


func _tangent(i: int) -> Vector2:
	var a := _pts[maxi(i - 1, 0)]
	var b := _pts[mini(i + 1, _pts.size() - 1)]
	return (b - a).normalized()


# --- Bờ + đê ---------------------------------------------------------------------------

func _build_banks() -> void:
	var mb := MeshBuilder.new(random_seed, 0.04)
	# Mặt cắt một bên: [khoảng cách thêm so với mép nước, độ cao, màu]
	var lv := levee_height
	var profile: Array = [
		[-1.2, bed_level, Palette.RIVER_BED],
		[0.0, water_level + 0.02, Palette.EARTH.darkened(0.1)],
		[1.0, lv * 0.65, Palette.EARTH],
		[1.7, lv, Palette.DIKE],
		[3.9, lv, Palette.DIKE.lerp(Palette.GRASS, 0.3)],
		[6.4, 0.0, Palette.GRASS],
	]
	for side: float in [-1.0, 1.0]:
		var prev: Array = []
		for i in _pts.size():
			var p := _pts[i]
			var n := _tangent(i).orthogonal() * side
			var hw := half_width(_cum[i])
			var row: Array = []
			for pr in profile:
				var d: float = hw + float(pr[0])
				row.append(Vector3(p.x + n.x * d, pr[1], p.y + n.y * d))
			if not prev.is_empty():
				for k in profile.size() - 1:
					var a: Vector3 = prev[k]
					var b: Vector3 = prev[k + 1]
					var c: Vector3 = row[k + 1]
					var d: Vector3 = row[k]
					mb.add_quad(a, b, c, d, profile[k + 1][2], (a + c) * 0.5 + Vector3(0, -3, 0))
			prev = row
	# Lòng sông: dải bùn sẫm phủ kín giữa hai chân bờ
	var bed := MeshBuilder.new(random_seed + 1, 0.08)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in _pts.size():
		var p := _pts[i]
		var n := _tangent(i).orthogonal()
		var hw := half_width(_cum[i]) - 1.1
		var l := Vector3(p.x - n.x * hw, bed_level, p.y - n.y * hw)
		var r := Vector3(p.x + n.x * hw, bed_level, p.y + n.y * hw)
		if i > 0:
			bed.add_quad(prev_l, prev_r, r, l, Palette.RIVER_BED, (prev_l + r) * 0.5 + Vector3(0, -3, 0))
		prev_l = l
		prev_r = r
	var bed_node := bed.commit_instance("RiverBed")
	bed_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed_node)
	var node := mb.commit_instance("Banks")
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


# --- Lối xuống sông + bến nước ----------------------------------------------------------

## Độ cao mặt bờ theo khoảng cách tới mép nước (d < 0: dưới nước).
func bank_height(d: float) -> float:
	var lv := levee_height
	var prof: Array = [[-1.2, bed_level], [0.0, water_level + 0.02], [1.0, lv * 0.65], [1.7, lv], [3.9, lv], [6.4, 0.0]]
	if d <= prof[0][0]:
		return bed_level
	for i in prof.size() - 1:
		var a: Array = prof[i]
		var b: Array = prof[i + 1]
		if d <= b[0]:
			return lerpf(a[1], b[1], (d - a[0]) / (b[0] - a[0]))
	return 0.0


## Điểm tim sông gần (x, z) nhất: trả về độ dài s.
func nearest_s(q: Vector2) -> float:
	var best := 0.0
	var bd := INF
	for i in _pts.size():
		var d := _pts[i].distance_squared_to(q)
		if d < bd:
			bd = d
			best = _cum[i]
	return best


func _build_landings() -> void:
	if village == null or village.access_paths.is_empty():
		return
	var path_mb := MeshBuilder.new(random_seed + 30, 0.06)
	var glow := MeshBuilder.new(random_seed + 32, 0.0)
	var wharf := MeshBuilder.new(random_seed + 31, 0.05)
	wharf.contact_shade_height = water_level + 0.4
	var names: Array[String] = ["Bến sông phía tây", "Bến sông phía đông", "Bến sông phía bắc"]
	for ai in village.access_paths.size():
		var acc: Dictionary = village.access_paths[ai]
		var exit: Vector2 = acc.exit
		var out: Vector2 = acc.out
		var s := nearest_s(exit + out * 12.0)
		var smp := sample(s)
		var c: Vector2 = smp[0]
		var tan: Vector2 = smp[1]
		var n := tan.orthogonal()
		if (exit - c).dot(n) < 0.0:
			n = -n                                     # n hướng từ tim sông về phía làng
		var hw := half_width(s)
		var edge := c + n * hw                        # mép nước phía làng
		# Đường đất từ khe lũy tre leo qua đê xuống mép nước (độ cao bám theo mặt cắt bờ)
		var pts3 := PackedVector3Array()
		var steps := maxi(4, int(exit.distance_to(edge) / 0.8))
		for k in steps + 1:
			var q := exit.lerp(edge + n * 0.6, float(k) / steps)
			var lat := (q - c).dot(n)
			var y := maxf(bank_height(lat - hw), 0.0) + 0.04
			pts3.append(Vector3(q.x, y, q.y))
		_strip3(path_mb, pts3, 2.2, Palette.EARTH)
		# Bậc đá xuống nước
		var face := atan2(-n.x, -n.y)
		var down := Basis(Vector3.UP, face)
		for k in 3:
			var q2 := edge - n * (0.15 + k * 0.45)
			var top := water_level + 0.12 - k * 0.14
			wharf.add_box(Vector3(2.4, maxf(top - bed_level, 0.05), 0.5), Palette.PLINTH.darkened(0.05 * k),
					Transform3D(down, Vector3(q2.x, bed_level, q2.y)))
		# Cầu ván (cầu ao) chìa ra sông: mặt ván trên cọc tre
		var deck_y := water_level + 0.28
		var start := edge - n * 0.4
		var deck_len := 3.6
		var mid := start - n * deck_len * 0.5
		wharf.add_box(Vector3(1.2, 0.07, deck_len), Palette.WOOD_LIGHT, Transform3D(down, Vector3(mid.x, deck_y, mid.y)))
		for k in 5:
			var pk := start - n * (0.2 + k * (deck_len - 0.4) / 4.0)
			wharf.add_box(Vector3(1.24, 0.02, 0.06), Palette.WOOD, Transform3D(down, Vector3(pk.x, deck_y + 0.07, pk.y)))
			for side in [-0.55, 0.55]:
				var post := pk + tan * float(side)
				wharf.add_prism(0.05, 0.05, deck_y - bed_level, 5, Palette.BAMBOO_STEM, _t(post.x, bed_level, post.y))
		# Tảng đá giặt + chum nước ở mép bến
		var wash := edge + tan * 1.8 - n * 0.2
		wharf.add_box(Vector3(0.9, water_level + 0.1 - bed_level, 0.6), Palette.ROCK, Transform3D(Basis(Vector3.UP, face + 0.3), Vector3(wash.x, bed_level, wash.y)))
		var jar := edge + n * 1.3 - tan * 1.6
		var jy := bank_height(1.3) 
		wharf.add_prism(0.2, 0.3, 0.3, 9, Palette.JAR, _t(jar.x, jy, jar.y))
		wharf.add_prism(0.3, 0.18, 0.28, 9, Palette.JAR, _t(jar.x, jy + 0.3, jar.y))
		var fish_spot := _build_fish_seat(wharf, glow, edge, n, tan, face)
		var spot3 := start - n * (deck_len - 0.6)
		pts3.append(Vector3(start.x, deck_y + 0.04, start.y))
		pts3.append(Vector3(spot3.x, deck_y + 0.04, spot3.y))
		landings.append({"path": pts3, "spot": Vector3(spot3.x, deck_y + 0.04, spot3.y), "face": face,
				"wash": Vector3(wash.x, water_level + 0.12, wash.y), "edge": Vector3(edge.x, water_level + 0.05, edge.y),
				"name": names[ai] if ai < names.size() else "Bến sông", "fish_spot": fish_spot})
	var pn := path_mb.commit_instance("RiverPaths")
	pn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pn)
	add_child(wharf.commit_instance("Wharves"))
	# Kính đèn bão ở chỗ ngồi câu: sáng ban đêm (DayNight chỉnh độ phát sáng)
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.vertex_color_is_srgb = true
	gm.emission_enabled = true
	gm.emission = Palette.WINDOW_GLOW
	gm.emission_energy_multiplier = 0.0
	var gl := glow.commit_instance("FishLanternGlass", gm)
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gl.add_to_group("night_glow")
	add_child(gl)


## Chỗ ngồi câu cạnh cầu ván: phiến đá kê phẳng trên mái bờ, ghế đẩu, giỏ cá, đèn bão
## treo trên cọc tre. Trả về vị trí mặt đất dưới ghế (người câu ngồi quay mặt ra sông).
func _build_fish_seat(mb: MeshBuilder, glow: MeshBuilder, edge: Vector2, n: Vector2, tan: Vector2,
		face: float) -> Vector3:
	var p := edge - tan * fish_spot_offset + n * 0.45
	var top := bank_height(0.45) + 0.05
	var base := water_level - 0.08
	var rot := Basis(Vector3.UP, face)
	# Phiến đá kê (đỉnh phẳng ngang)
	mb.add_box(Vector3(1.2, top - base, 1.1), Palette.ROCK, Transform3D(rot.rotated(Vector3.UP, 0.08), Vector3(p.x, base, p.y)))
	var seat := Transform3D(rot, Vector3(p.x, top, p.y))
	# Ghế đẩu gỗ thấp
	for sx: float in [-0.13, 0.13]:
		for sz: float in [-0.11, 0.11]:
			mb.add_box(Vector3(0.04, stool_height - 0.04, 0.04), Palette.WOOD, seat * _t(sx, 0.0, sz - 0.12))
	mb.add_box(Vector3(0.36, 0.04, 0.3), Palette.WOOD_LIGHT, seat * _t(0.0, stool_height - 0.04, -0.12))
	# Giỏ cá tre đan (bầu, miệng thắt) bên phải người ngồi
	var basket := seat * _t(-0.55, 0.0, 0.05)
	mb.add_prism(0.13, 0.19, 0.16, 8, Palette.THATCH_DARK, basket)
	mb.add_prism(0.19, 0.09, 0.14, 8, Palette.THATCH, basket * _t(0, 0.16, 0))
	mb.add_prism(0.1, 0.11, 0.05, 8, Palette.BAMBOO_NODE, basket * _t(0, 0.3, 0))
	# Hộp mồi nhỏ bên trái
	mb.add_box(Vector3(0.16, 0.08, 0.12), Palette.JAR, seat * _t(0.42, 0.0, 0.1))
	# Cọc tre cắm sau ghế, đèn bão treo ở móc
	var post := seat * _t(-0.8, 0.0, -0.35)
	mb.add_prism(0.03, 0.025, 1.35, 5, Palette.BAMBOO_STEM, post)
	mb.add_limb(Vector3(0, 1.3, 0), Vector3(0, 1.3, 0.22), 0.015, 0.015, 4, Palette.BAMBOO_STEM, post)
	var lamp := post * _t(0, 0.86, 0.22)
	mb.add_prism(0.07, 0.07, 0.03, 6, Palette.WINDOW_DARK, lamp)
	mb.add_prism(0.05, 0.03, 0.06, 6, Palette.WINDOW_DARK, lamp * _t(0, 0.2, 0))
	mb.add_limb(Vector3(0, 0.26, 0), Vector3(0, 0.44, 0), 0.006, 0.006, 3, Palette.WINDOW_DARK, lamp)
	glow.add_prism(0.055, 0.045, 0.17, 6, Palette.WINDOW_GLOW.lightened(0.2), lamp * _t(0, 0.03, 0))
	var light := OmniLight3D.new()
	light.name = "FishLantern"
	light.light_color = Palette.WINDOW_GLOW
	light.omni_range = 5.0
	light.light_energy = 0.0
	light.set_meta("max_energy", 1.3)
	light.shadow_enabled = false
	light.position = (lamp * _t(0, 0.12, 0)).origin
	light.add_to_group("night_light")
	add_child(light)
	return Vector3(p.x, top, p.y)


## Dải đường theo các điểm 3D (giữ độ cao từng điểm), bề rộng `w`.
func _strip3(mb: MeshBuilder, pts: PackedVector3Array, w: float, col: Color) -> void:
	var pl := Vector3.ZERO
	var pr := Vector3.ZERO
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var dir := Vector2(b.x - a.x, b.z - a.z).normalized().orthogonal() * w * 0.5
		var l := pts[i] + Vector3(dir.x, 0, dir.y)
		var r := pts[i] - Vector3(dir.x, 0, dir.y)
		if i > 0:
			mb.add_quad(pl, pr, r, l, col, (pl + r) * 0.5 + Vector3(0, -2, 0))
		pl = l
		pr = r


# --- Mặt nước ---------------------------------------------------------------------------

func _build_water() -> MeshInstance3D:
	var fracs: Array[float] = [-1.1, -0.85, -0.5, 0.0, 0.5, 0.85, 1.1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev: Array = []
	for i in _pts.size():
		var p := _pts[i]
		var n := _tangent(i).orthogonal()
		var hw := half_width(_cum[i])
		var row: Array = []
		for f in fracs:
			row.append([Vector3(p.x + n.x * hw * f, water_level, p.y + n.y * hw * f), absf(f)])
		if not prev.is_empty():
			for k in fracs.size() - 1:
				_water_tri(st, prev[k], prev[k + 1], row[k + 1])
				_water_tri(st, prev[k], row[k + 1], row[k])
		prev = row
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader") as Shader
	mat.set_shader_parameter("opacity", water_opacity)
	mat.set_shader_parameter("wave_height", 0.04)
	mat.set_shader_parameter("wave_scale", 0.55)
	mat.set_shader_parameter("shininess", 0.35)
	var mi := MeshInstance3D.new()
	mi.name = "RiverWater"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Tam giác mặt nước, tự đảo thứ tự để mặt trước hướng lên. Mỗi đỉnh: [vị trí, |tỉ lệ ngang|].
func _water_tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var verts: Array = [a, b, c]
	if (pc - pa).cross(pb - pa).y < 0.0:
		verts = [a, c, b]
	for v in verts:
		var f: float = v[1]
		var col := Palette.WATER.lerp(Palette.WATER_LIGHT, smoothstep(0.6, 1.0, f))
		col.a = 1.0 - smoothstep(0.7, 1.0, f)    # sát bờ không lay sóng
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])


# --- Sen -------------------------------------------------------------------------------

func _build_lotus() -> void:
	var pads: Array[Transform3D] = []
	var pad_cols: Array[Color] = []
	var raised: Array[Transform3D] = []
	var pink: Array[Transform3D] = []
	var white: Array[Transform3D] = []
	var buds: Array[Transform3D] = []
	for i in lotus_patches:
		# Rải đều dọc sông, mỗi đầm sát một bên bờ
		var s := length * (i + _rng.randf_range(0.25, 0.75)) / maxf(lotus_patches, 1)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var smp := sample(s)
		var p: Vector2 = smp[0]
		var tan: Vector2 = smp[1]
		var nrm := tan.orthogonal()
		var hw := half_width(s)
		var radius := _rng.randf_range(2.8, 5.0)
		var center := p + nrm * side * (hw - radius * 0.55 - 0.4)
		lotus_spots.append(Vector3(center.x, water_level, center.y))
		var spot := func() -> Vector3:
			for attempt in 8:
				var u := _rng.randf_range(-1.0, 1.0) * radius * 1.7
				var v := _rng.randf_range(-1.0, 1.0) * radius * 0.6
				var q := center + tan * u + nrm * v
				# Không ra khỏi lòng sông
				var lat := (q - p).dot(nrm)
				if absf(lat) < hw - 0.7:
					return Vector3(q.x, water_level, q.y)
			return Vector3(center.x, water_level, center.y)
		for k in _rng.randi_range(28, 42):
			var q: Vector3 = spot.call()
			var sc := _rng.randf_range(0.7, 1.4)
			pads.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, 1.0, sc)), q + Vector3(0, 0.015, 0)))
			pad_cols.append(Palette.LILY.darkened(_rng.randf_range(-0.08, 0.15)))
		for k in _rng.randi_range(6, 12):
			var q2: Vector3 = spot.call()
			var sc2 := _rng.randf_range(0.8, 1.2)
			raised.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2)).scaled(Vector3.ONE * sc2),
					q2 + Vector3(0, _rng.randf_range(0.25, 0.7), 0)))
		for k in _rng.randi_range(4, 9):
			var q3: Vector3 = spot.call()
			var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), q3 + Vector3(0, _rng.randf_range(0.35, 0.75), 0))
			if _rng.randf() < 0.25:
				white.append(xf)
			else:
				pink.append(xf)
		for k in _rng.randi_range(3, 6):
			var q4: Vector3 = spot.call()
			buds.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), q4 + Vector3(0, _rng.randf_range(0.4, 0.8), 0)))

	var wind := MeshBuilder.wind_material(lotus_wind, -0.8, 1.4, 1.1)
	_multimesh("LotusPads", _pad_mesh(), pads, pad_cols, MeshBuilder.material(), false)
	_multimesh("LotusLeaves", _raised_leaf_mesh(), raised, [], wind, true)
	_multimesh("LotusPink", _flower_mesh(Palette.LOTUS, Palette.LOTUS.lightened(0.35)), pink, [], wind, true)
	_multimesh("LotusWhite", _flower_mesh(Palette.FLOWER_WHITE, Palette.LOTUS.lightened(0.55)), white, [], wind, true)
	_multimesh("LotusBuds", _bud_mesh(), buds, [], wind, true)


func _multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], cols: Array,
		mat: Material, shadows: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = 160.0
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _pad_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new(1, 0.0)
	# Lá sen nổi: đĩa 9 cạnh trắng (màu instance tô xanh), gân giữa sẫm hơn
	mb.add_prism(0.34, 0.34, 0.02, 9, Color.WHITE)
	mb.add_prism(0.05, 0.05, 0.025, 6, Color(0.8, 0.85, 0.75))
	return mb.commit()


func _raised_leaf_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new(2, 0.05)
	mb.add_limb(Vector3(0, -0.8, 0), Vector3(0, 0, 0), 0.015, 0.012, 4, Palette.LILY.darkened(0.3))
	# Lá vươn cao hình phễu nông
	mb.add_prism(0.05, 0.4, 0.13, 10, Palette.LILY, Transform3D.IDENTITY, 0.0, true)
	mb.add_prism(0.04, 0.36, 0.135, 10, Palette.LILY.lightened(0.12), Transform3D.IDENTITY, 0.0, false)
	return mb.commit()


func _flower_mesh(petal: Color, inner: Color) -> ArrayMesh:
	var mb := MeshBuilder.new(3, 0.03)
	mb.add_limb(Vector3(0, -0.85, 0), Vector3(0, 0, 0), 0.014, 0.012, 4, Palette.LILY.darkened(0.3))
	# Đài sen ở giữa
	mb.add_prism(0.05, 0.07, 0.07, 8, Palette.FLOWER_YELLOW.lerp(Palette.LILY, 0.4), _t(0, 0.04, 0))
	# Hai vòng cánh: vòng ngoài xoè rộng, vòng trong khum lại
	for ring in 2:
		var n := 8 if ring == 0 else 6
		var tilt := 0.85 if ring == 0 else 0.38
		var h := 0.24 if ring == 0 else 0.2
		for k in n:
			var a := TAU * (k + 0.5 * ring) / n
			var out := Vector3(cos(a), 0, sin(a))
			var axis := Vector3.UP.cross(out).normalized()
			var xf := Transform3D(Basis(axis, tilt), out * 0.04 + Vector3(0, 0.02, 0))
			mb.add_pyramid(0.065, h, 4, petal if ring == 0 else inner, xf)
	return mb.commit()


func _bud_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new(4, 0.03)
	mb.add_limb(Vector3(0, -0.9, 0), Vector3(0, 0, 0), 0.014, 0.012, 4, Palette.LILY.darkened(0.3))
	mb.add_prism(0.04, 0.08, 0.1, 6, Palette.LOTUS.darkened(0.05))
	mb.add_pyramid(0.08, 0.2, 6, Palette.LOTUS, _t(0, 0.1, 0))
	return mb.commit()


# --- Đò --------------------------------------------------------------------------------

func _build_boats() -> void:
	if boats <= 0:
		return
	# Một mesh đò dùng chung (toạ độ cục bộ: mũi đò hướng +z), mỗi con một node riêng để chèo được
	var mb := MeshBuilder.new(random_seed + 7, 0.04)
	var hull := Palette.WOOD.darkened(0.15)
	# Thân đò dài, hai đầu vót nhọn hơi vểnh
	mb.add_box(Vector3(1.0, 0.4, 3.2), hull)
	mb.add_box(Vector3(0.84, 0.04, 3.0), Palette.WOOD_LIGHT, _t(0, 0.39, 0))
	for e: float in [-1.0, 1.0]:
		var tip := Transform3D(Basis(Vector3.RIGHT, e * (PI * 0.5 - 0.35)), Vector3(0, 0.0, e * 1.6))
		mb.add_pyramid(0.5, 1.0, 4, hull, tip)
	# Mui đò bằng tre đan (nửa ống) + mép mui sẫm hai đầu
	var mui := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.2, 0.75))
	mb.add_prism(0.62, 0.62, 1.5, 12, Palette.THATCH_DARK, mui, 0.0, false)
	for e: float in [-1.0, 1.0]:
		mb.add_prism(0.66, 0.66, 0.06, 12, Palette.BAMBOO_NODE, mui * _t(0, 0.72 + e * 0.72, 0), 0.0, false)
	var boat_mesh := mb.commit()
	var pole := MeshBuilder.new(random_seed + 8, 0.04)
	pole.add_limb(Vector3(0.3, 0.4, -1.2), Vector3(0.6, 3.2, -2.2), 0.025, 0.02, 4, Palette.BAMBOO_STEM)
	var pole_mesh := pole.commit()
	for i in boats:
		var s := length * (0.22 + 0.56 * float(i) / maxf(boats - 1, 1)) + _rng.randf_range(-20, 20)
		var smp := sample(s)
		var p: Vector2 = smp[0]
		var tan: Vector2 = smp[1]
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := p + tan.orthogonal() * side * (half_width(s) - 1.7)
		var yaw := atan2(tan.x, tan.y) + _rng.randf_range(-0.15, 0.15)
		var node := Node3D.new()
		node.name = "Boat%d" % i
		node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, water_level - 0.15, pos.y))
		node.add_to_group("boat")             # không dựng va chạm tĩnh cho đò (đò di chuyển được)
		add_child(node)
		var mi := MeshInstance3D.new()
		mi.name = "Hull"
		mi.mesh = boat_mesh
		node.add_child(mi)
		var pm := MeshInstance3D.new()
		pm.name = "Pole"                      # sào chống dựng sẵn, ẩn đi khi có người chèo
		pm.mesh = pole_mesh
		node.add_child(pm)
		var target := HouseEntry.make_click_target(node, _t(0, 0.6, 0), Vector3(1.4, 1.2, 3.6), "Lên đò")
		target.set_meta("boat_index", i)
		boat_spots.append(node.position)
		boat_nodes.append(node)


# --- Cá --------------------------------------------------------------------------------

func _build_fish() -> void:
	if fish_count <= 0:
		return
	var mb := MeshBuilder.new(9, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	mb.add_blob(Vector3(0.09, 0.08, 0.28), Color.WHITE, rng, 0.05)
	mb.add_pyramid(0.09, 0.18, 4, Color(0.85, 0.85, 0.85),
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(0.25, 1.0, 1.0)), Vector3(0, 0.08, -0.26)))
	mb.add_pyramid(0.05, 0.12, 3, Color(0.85, 0.85, 0.85), _t(0, 0.15, -0.02))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fish.gdshader") as Shader
	var mesh := mb.commit(mat)

	_fish_mm = MultiMesh.new()
	_fish_mm.transform_format = MultiMesh.TRANSFORM_3D
	_fish_mm.use_colors = true
	_fish_mm.mesh = mesh
	_fish_mm.instance_count = fish_count
	var colors: Array[Color] = [Palette.BEAK, Palette.HIBISCUS, Palette.FLOWER_YELLOW, Palette.ROCK, Palette.ROCK_DARK, Palette.FLOWER_WHITE]
	for i in fish_count:
		var col := colors[_rng.randi_range(0, colors.size() - 1)]
		_fish_mm.set_instance_color(i, col)
		_fish.append({
			"kind": colors.find(col),
			"held": false,
			"pos": Vector3.ZERO,
			"yaw": 0.0,
			"s": _rng.randf_range(5.0, length - 5.0),
			"lat": _rng.randf_range(-0.6, 0.6),
			"dir": -1.0 if _rng.randf() < 0.5 else 1.0,
			"speed": _rng.randf_range(fish_speed.x, fish_speed.y),
			"phase": _rng.randf() * TAU,
			"depth": _rng.randf_range(0.03, 0.09),
			"size": _rng.randf_range(1.0, 1.7),
			"jump": -1.0,
		})
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Fish"
	mmi.multimesh = _fish_mm
	mmi.custom_aabb = AABB(Vector3(-500, -3, -500), Vector3(1000, 6, 1000))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_jump_timer = _rng.randf_range(jump_interval.x, jump_interval.y)
	# Vài vòng gợn sóng dùng lại khi cá nhảy / khi câu
	for i in 8:
		var rp := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.0
		tm.rings = 20
		tm.ring_segments = 3
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(Palette.WATER_LIGHT.lightened(0.4), 0.0)
		tm.material = rm
		rp.mesh = tm
		rp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rp.visible = false
		add_child(rp)
		_ripples.append(rp)
		_ripple_age.append(-1.0)
	_update_fish(0.0)


func _process(delta: float) -> void:
	if _fish_mm == null or not is_visible_in_tree():
		return
	_time += delta
	_update_fish(delta)
	_update_ripples(delta)


func _update_fish(delta: float) -> void:
	# Chọn một con gần camera để nhảy
	_jump_timer -= delta
	if _jump_timer <= 0.0:
		_jump_timer = _rng.randf_range(jump_interval.x, jump_interval.y)
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			for attempt in 12:
				var f: Dictionary = _fish[_rng.randi_range(0, _fish.size() - 1)]
				var smp := sample(f.s)
				var p: Vector2 = smp[0]
				if float(f.jump) < 0.0 and not f.held and Vector2(cam.global_position.x, cam.global_position.z).distance_to(p) < jump_view_distance:
					f.jump = 0.0
					break
	for i in _fish.size():
		var f: Dictionary = _fish[i]
		if f.held:
			continue          # đang do Fishing điều khiển (bơi tới mồi, mắc câu)
		var s: float = f.s
		s += float(f.dir) * float(f.speed) * delta
		if s < 4.0 or s > length - 4.0:
			f.dir = -float(f.dir)
			s = clampf(s, 4.0, length - 4.0)
		f.s = s
		var smp := sample(s)
		var p: Vector2 = smp[0]
		var tan: Vector2 = smp[1] * float(f.dir)
		var hw := half_width(s)
		var lat: float = clampf(float(f.lat) + 0.25 * sin(_time * 0.35 + float(f.phase)), -0.85, 0.85)
		var pos2 := p + tan.orthogonal() * lat * (hw - 0.8)
		var y := water_level - float(f.depth)
		var yaw := atan2(tan.x, tan.y) + 0.12 * sin(_time * 0.9 + float(f.phase))
		var pitch := 0.0
		var jt: float = f.jump
		if jt >= 0.0:
			jt += delta / 0.85
			if jt >= 1.0:
				_spawn_ripple(Vector3(pos2.x, water_level + 0.02, pos2.y))
				jt = -1.0
			else:
				y = water_level + 0.75 * 4.0 * jt * (1.0 - jt) - float(f.depth) * (1.0 - jt)
				pitch = lerpf(-0.9, 0.9, jt)
				if jt - delta / 0.85 <= 0.0:
					_spawn_ripple(Vector3(pos2.x, water_level + 0.02, pos2.y))
			f.jump = jt
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		f.pos = Vector3(pos2.x, y, pos2.y)
		f.yaw = yaw
		_fish_mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * float(f.size)), Vector3(pos2.x, y, pos2.y)))


# --- Cá cho mini-game câu (mục 16) ----------------------------------------------------

## Vị trí (x, z) có nằm trong lòng sông không, chừa `margin` m tới mép nước.
func is_water(q: Vector2, margin: float = 0.5) -> bool:
	var s := nearest_s(q)
	var smp := sample(s)
	var lat := absf((q - (smp[0] as Vector2)).dot((smp[1] as Vector2).orthogonal()))
	return lat < half_width(s) - margin


## Con cá (không đang nhảy, không bị giữ) gần `pos` nhất trong bán kính; -1 nếu không có.
func fish_near(pos: Vector3, radius: float) -> int:
	var best := -1
	var bd := radius * radius
	for i in _fish.size():
		var f: Dictionary = _fish[i]
		if f.held or float(f.jump) >= 0.0:
			continue
		var o: Vector3 = f.pos
		var d := Vector2(o.x - pos.x, o.z - pos.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


## Giữ một con cá để Fishing tự đặt vị trí. Trả về {pos, yaw, kind, size}.
func grab_fish(i: int) -> Dictionary:
	var f: Dictionary = _fish[i]
	f.held = true
	return {"pos": f.pos, "yaw": float(f.yaw), "kind": int(f.kind), "size": float(f.size)}


## Đặt vị trí con cá đang giữ (yaw quanh trục đứng, pitch chúc đầu).
func pose_fish(i: int, pos: Vector3, yaw: float, pitch: float = 0.0, roll: float = 0.0) -> void:
	var f: Dictionary = _fish[i]
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	f.pos = pos
	f.yaw = yaw
	_fish_mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * float(f.size)), pos))


## Thả con cá đang giữ: bơi tiếp theo dòng từ chỗ hiện tại, quay đuôi chạy khỏi `away_from`.
func release_fish(i: int, away_from: Vector3) -> void:
	var f: Dictionary = _fish[i]
	var o: Vector3 = f.pos
	var q := Vector2(o.x, o.z)
	var s := nearest_s(q)
	var smp := sample(s)
	var tan: Vector2 = smp[1]
	var lat := (q - (smp[0] as Vector2)).dot(tan.orthogonal()) / maxf(half_width(s) - 0.8, 0.5)
	f.s = s
	f.lat = clampf(lat - 0.25 * sin(_time * 0.35 + float(f.phase)), -0.6, 0.6)
	f.dir = 1.0 if (q - Vector2(away_from.x, away_from.z)).dot(tan) >= 0.0 else -1.0
	f.held = false


## Cá đã câu lên: sinh lại một con ở đoạn sông xa chỗ câu.
func respawn_fish(i: int, away_from: Vector3) -> void:
	var f: Dictionary = _fish[i]
	var s0 := nearest_s(Vector2(away_from.x, away_from.z))
	f.s = wrapf(s0 + length * _rng.randf_range(0.3, 0.7), 5.0, length - 5.0)
	f.lat = _rng.randf_range(-0.6, 0.6)
	f.jump = -1.0
	f.held = false


## Gợn tròn trên mặt nước (cá giãy, phao rơi).
func splash(pos: Vector3) -> void:
	_spawn_ripple(Vector3(pos.x, water_level + 0.02, pos.z))


func _spawn_ripple(pos: Vector3) -> void:
	for i in _ripples.size():
		if _ripple_age[i] < 0.0:
			_ripples[i].position = pos
			_ripples[i].visible = true
			_ripple_age[i] = 0.0
			return


func _update_ripples(delta: float) -> void:
	for i in _ripples.size():
		if _ripple_age[i] < 0.0:
			continue
		_ripple_age[i] += delta / 1.4
		var a := _ripple_age[i]
		if a >= 1.0:
			_ripple_age[i] = -1.0
			_ripples[i].visible = false
			continue
		var r := lerpf(0.15, 1.6, a)
		_ripples[i].scale = Vector3(r, 0.15, r)
		var mat := (_ripples[i].mesh as TorusMesh).material as StandardMaterial3D
		mat.albedo_color.a = 0.7 * (1.0 - a)
