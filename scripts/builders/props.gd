class_name Props
extends Node3D
## Chi tiết điểm xuyết: đá, bụi cỏ, hoa dại (MultiMesh), giếng, chum nước, đống rơm,
## lá súng và hoa sen trên ao.

@export var terrain: Terrain
@export var house: House
@export var bamboo: BambooGrove
@export var banyan: BanyanTree
@export var random_seed: int = 1011

@export_group("Rải ngẫu nhiên")
@export var scatter_extent: float = 28.0
@export_range(0, 3000) var grass_tuft_count: int = 1100
@export_range(0, 1000) var flower_count: int = 220
@export_range(0, 200) var rock_count: int = 40
@export var wind_strength: float = 0.05

@export_group("Vật thể")
@export var well_position: Vector3 = Vector3(-16.4, 0.0, -6.6)
@export var jar_position: Vector3 = Vector3(-6.2, 0.0, -9.4)
@export var haystack_position: Vector3 = Vector3(-20.5, 0.0, -3.0)
@export_range(0, 20) var lily_count: int = 9

var _noise := FastNoiseLite.new()


func build() -> void:
	if terrain == null:
		push_warning("Props: chưa gán terrain")
		return
	_noise.seed = random_seed
	_noise.frequency = 0.12
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	_scatter_grass(rng)
	_scatter_flowers(rng)
	_scatter_rocks(rng)

	var mb := MeshBuilder.new(random_seed, 0.05)
	mb.contact_shade_height = 0.4
	_build_well(mb)
	_build_jars(mb, rng)
	_build_haystack(mb, rng)
	add_child(mb.commit_instance("Objects"))

	var pond := MeshBuilder.new(random_seed + 1, 0.06)
	_build_lilies(pond, rng)
	var pond_node := pond.commit_instance("PondPlants")
	pond_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pond_node)


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## Chỗ trống trên cỏ: ngoài ruộng, ao, sân, đường, gốc cây.
func _is_free(x: float, z: float, margin: float = 0.0) -> bool:
	var p := Vector2(x, z)
	if terrain.field_rect.grow(0.6 + margin).has_point(p):
		return false
	if terrain.yard_rect.grow(0.4 + margin).has_point(p):
		return false
	if terrain.is_in_pond(x, z):
		return false
	for i in terrain.path_points.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, terrain.path_points[i], terrain.path_points[i + 1])
		if p.distance_to(q) < terrain.path_width * 0.7 + margin:
			return false
	if house != null:
		var kp := house.kitchen_position
		if p.distance_to(Vector2(kp.x, kp.z)) < 3.0 + margin:
			return false
	if banyan != null:
		var bp := banyan.tree_position
		if p.distance_to(Vector2(bp.x, bp.z)) < banyan.trunk_radius + 1.2 + margin:
			return false
	if bamboo != null and p.distance_to(Vector2(bamboo.center.x, bamboo.center.z)) < bamboo.spread * 0.6:
		return false
	return true


## Lấy điểm ngẫu nhiên, ưu tiên chỗ noise cao để vật mọc thành đám.
func _sample(rng: RandomNumberGenerator, margin: float, clumpy: bool) -> Vector3:
	for attempt in 30:
		var x := rng.randf_range(-scatter_extent, scatter_extent)
		var z := rng.randf_range(-scatter_extent, scatter_extent)
		if not _is_free(x, z, margin):
			continue
		var n := _noise.get_noise_2d(x, z) * 0.5 + 0.5
		if clumpy and rng.randf() > 0.08 + 0.92 * n * n:
			continue
		return Vector3(x, terrain.height_at(x, z), z)
	return Vector3.INF


func _make_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D],
		colors: Array[Color], mat: Material, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# --- Cỏ, hoa, đá --------------------------------------------------------------------

func _scatter_grass(rng: RandomNumberGenerator) -> void:
	var mb := MeshBuilder.new(random_seed + 2, 0.0)
	mb.contact_shade_height = 0.15
	mb.contact_shade_strength = 0.15
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var axis := Vector3.UP.cross(dir).normalized()
		mb.add_prism(0.04, 0.0, rng.randf_range(0.22, 0.34), 3, Color.WHITE,
				Transform3D(Basis(axis, deg_to_rad(rng.randf_range(15.0, 40.0))), dir * 0.04),
				rng.randf() * TAU, false)
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in grass_tuft_count:
		var p := _sample(rng, 0.0, true)
		if p == Vector3.INF:
			continue
		var s := rng.randf_range(0.7, 1.4)
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		# Gần màu nền cỏ, chỉ đậm hơn chút để đọc được khối
		colors.append(Palette.GRASS.darkened(rng.randf_range(0.0, 0.12)))
	_make_multimesh("GrassTufts", mb.commit(), xforms, colors,
			MeshBuilder.wind_material(wind_strength, 0.0, 0.35, 1.8), false)


func _scatter_flowers(rng: RandomNumberGenerator) -> void:
	var mb := MeshBuilder.new(random_seed + 3, 0.0)
	# Cuống xanh (màu đỉnh tối để gần như giữ màu lá), bông màu trắng để màu instance tô
	mb.add_prism(0.015, 0.012, 0.26, 3, Palette.GRASS.darkened(0.35), Transform3D.IDENTITY, 0.0, false)
	var petal_rng := RandomNumberGenerator.new()
	petal_rng.seed = random_seed
	mb.add_blob(Vector3(0.08, 0.05, 0.08), Color.WHITE, petal_rng, 0.15, _t(0.0, 0.25, 0.0))
	var palette: Array[Color] = [Palette.FLOWER_WHITE, Palette.FLOWER_YELLOW, Palette.FLOWER_PINK]
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in flower_count:
		var p := _sample(rng, 0.0, true)
		if p == Vector3.INF:
			continue
		var s := rng.randf_range(1.2, 1.7)
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		# Hoa cùng màu mọc gần nhau
		var idx := int(floor((_noise.get_noise_2d(p.x * 0.5, p.z * 0.5) * 0.5 + 0.5) * 2.999))
		colors.append(palette[clampi(idx, 0, 2)])
	_make_multimesh("Flowers", mb.commit(), xforms, colors,
			MeshBuilder.wind_material(wind_strength, 0.0, 0.3, 1.8), false)


func _scatter_rocks(rng: RandomNumberGenerator) -> void:
	# 3 dạng đá, mỗi dạng một MultiMesh
	var per := ceili(rock_count / 3.0)
	for v in 3:
		var mb := MeshBuilder.new(random_seed + 20 + v, 0.06)
		mb.add_blob(Vector3(0.35, 0.22, 0.28), Palette.ROCK if v != 1 else Palette.ROCK_DARK, rng, 0.3)
		var xforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		for i in per:
			var p := Vector3.INF
			# Một nửa số đá nằm quanh bờ ao
			if i % 2 == 0:
				var a := rng.randf() * TAU
				var r := terrain.pond_radius * rng.randf_range(1.15, 1.45)
				var q := terrain.pond_center + Vector2(cos(a), sin(a)) * r
				if _is_free(q.x, q.y):
					p = Vector3(q.x, terrain.height_at(q.x, q.y), q.y)
			if p == Vector3.INF:
				p = _sample(rng, 0.3, false)
			if p == Vector3.INF:
				continue
			var s := rng.randf_range(0.5, 1.6)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s))
			xforms.append(Transform3D(basis, p - Vector3(0, 0.05 * s, 0)))
			colors.append(Color.WHITE)
		var mat := MeshBuilder.material()
		_make_multimesh("Rocks%d" % v, mb.commit(), xforms, colors, mat, true)


# --- Giếng, chum, rơm ---------------------------------------------------------------

func _build_well(mb: MeshBuilder) -> void:
	var p := well_position
	var xf := Transform3D(Basis(), p)
	mb.add_prism(0.78, 0.78, 0.75, 10, Palette.PLINTH, xf)
	mb.add_prism(0.84, 0.84, 0.08, 10, Palette.WALL_DARK, xf * _t(0.0, 0.75, 0.0))
	mb.add_prism(0.56, 0.56, 0.86, 10, Palette.WINDOW_DARK, xf)     # lòng giếng tối
	# Giá gỗ + ròng rọc + gầu
	for s in [-1.0, 1.0]:
		mb.add_box(Vector3(0.1, 1.7, 0.1), Palette.WOOD, xf * _t(s * 0.95, 0.0, 0.0))
	mb.add_box(Vector3(2.1, 0.1, 0.12), Palette.WOOD, xf * _t(0.0, 1.7, 0.0))
	mb.add_prism(0.03, 0.03, 0.6, 4, Palette.WOOD_LIGHT, xf * _t(0.0, 1.1, 0.0))
	mb.add_prism(0.12, 0.15, 0.18, 7, Palette.WOOD_LIGHT, xf * _t(0.0, 0.95, 0.0))


func _build_jars(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(0.75, 0, 0.15), Vector3(0.3, 0, 0.7)]
	for i in offsets.size():
		var s := 1.0 - 0.15 * i
		var xf := Transform3D(Basis().scaled(Vector3.ONE * s), jar_position + offsets[i])
		mb.add_prism(0.22, 0.36, 0.36, 9, Palette.JAR, xf)
		mb.add_prism(0.36, 0.2, 0.34, 9, Palette.JAR, xf * _t(0.0, 0.36, 0.0))
		mb.add_prism(0.22, 0.22, 0.06, 9, Palette.JAR.darkened(0.2), xf * _t(0.0, 0.7, 0.0))
		if i != 1:
			mb.add_prism(0.25, 0.2, 0.06, 9, Palette.WOOD, xf * _t(0.0, 0.76, 0.0))  # nắp gỗ


func _build_haystack(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.4), haystack_position)
	mb.add_prism(1.15, 1.25, 0.6, 9, Palette.STRAW.darkened(0.08), xf)
	mb.add_prism(1.25, 0.15, 2.0, 9, Palette.STRAW, xf * _t(0.0, 0.6, 0.0), 0.2)
	mb.add_prism(0.04, 0.03, 0.6, 4, Palette.WOOD, xf * _t(0.0, 2.4, 0.0))
	# Vài cọng rơm rơi quanh chân
	for i in 6:
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.2, 1.7)
		mb.add_box(Vector3(0.5, 0.03, 0.06), Palette.STRAW,
				xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(cos(a) * d, 0.0, sin(a) * d)))


# --- Lá súng, hoa sen ---------------------------------------------------------------

func _build_lilies(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var y := terrain.water_level + 0.015
	for i in lily_count:
		var a := rng.randf() * TAU
		var r := terrain.pond_radius * rng.randf_range(0.35, 0.8)
		var q := terrain.pond_center + Vector2(cos(a), sin(a)) * r
		var s := rng.randf_range(0.25, 0.45)
		mb.add_prism(s, s, 0.02, 7, Palette.LILY, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, y, q.y)))
		if i % 3 == 0:
			mb.add_pyramid(0.1, 0.16, 6, Palette.LOTUS, _t(q.x + 0.1, y + 0.02, q.y))
