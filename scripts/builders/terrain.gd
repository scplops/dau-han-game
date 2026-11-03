class_name Terrain
extends Node3D
## Địa hình: nền cỏ gợn nhẹ, 3 thửa ruộng có bờ, ao nước, đường đất.
## Toạ độ: x sang phải, z về phía camera (tiền cảnh là z dương), y lên trên.
## Các builder sau (nhà, lúa, nhân vật...) dùng `height_at()` và các vùng bên dưới
## để đặt vật thể đúng chỗ.

@export var random_seed: int = 3103

@export_group("Nền")
@export var grid_extent: float = 32.0        # lưới chi tiết từ -extent đến +extent
@export var cell_size: float = 1.0
@export var skirt_extent: float = 160.0      # mặt phẳng phẳng bao ngoài, tan vào sương
@export var noise_amplitude: float = 0.35
@export var noise_frequency: float = 0.07
@export_range(0.0, 0.2) var ground_jitter: float = 0.035

@export_group("Ruộng")
## Khối ruộng (x, z, rộng, sâu); chia thành 3 thửa bởi `field_dividers`.
@export var field_rect: Rect2 = Rect2(-18.0, 2.0, 26.0, 16.0)
@export var field_dividers: PackedFloat32Array = PackedFloat32Array([-9.0, 0.0])
@export var furrow_spacing: float = 1.0
@export var furrow_width: float = 0.25
@export var dike_bottom_width: float = 0.9
@export var dike_top_width: float = 0.45
@export var dike_height: float = 0.28
@export var dike_wobble: float = 0.18        # độ cong vẹo của bờ ruộng

@export_group("Ao")
@export var pond_center: Vector2 = Vector2(15.0, 0.5)
@export var pond_radius: float = 4.6
@export var pond_depth: float = 0.7
@export var water_level: float = -0.18

@export_group("Sân & đường")
## Vùng phẳng dành cho nhà và sân (bước 4).
@export var yard_rect: Rect2 = Rect2(-18.5, -18.0, 15.5, 14.0)
@export var path_points: PackedVector2Array = PackedVector2Array([
	Vector2(-10.5, -4.2), Vector2(-9.6, -2.2), Vector2(-9.9, 0.0), Vector2(-9.0, 2.0)])
@export var path_width: float = 1.1

var _noise := FastNoiseLite.new()
var _pond_shape := PackedFloat32Array()      # bán kính tương đối theo góc


func build() -> void:
	_noise.seed = random_seed
	_noise.frequency = noise_frequency
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_make_pond_shape()

	var ground := MeshBuilder.new(random_seed, ground_jitter)
	_build_ground(ground)
	add_child(ground.commit_instance("Ground"))

	var details := MeshBuilder.new(random_seed + 1, 0.06)
	_build_fields(details)
	_build_path(details)
	add_child(details.commit_instance("FieldsAndPath"))

	add_child(_build_water())


# --- Truy vấn cho các builder khác -----------------------------------------------

## Độ cao mặt đất tại (x, z).
func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var pond_t := _pond_factor(p)
	if pond_t < 1.0:
		# Lòng ao: dốc nhanh ở mép, phẳng ở giữa
		return -pond_depth * clampf((1.0 - pond_t) * 3.0, 0.0, 1.0)
	var flat := _distance_to_features(p)
	var mask := smoothstep(0.5, 4.0, flat)
	# Mép lưới về 0 để khớp với mặt phẳng bao ngoài
	var edge := maxf(absf(x), absf(z))
	mask *= 1.0 - smoothstep(grid_extent - 6.0, grid_extent, edge)
	return _noise.get_noise_2d(x, z) * noise_amplitude * mask


## Hình chữ nhật của từng thửa ruộng (tính tới tim bờ).
func paddy_rects() -> Array[Rect2]:
	var xs: Array[float] = [field_rect.position.x]
	for d in field_dividers:
		xs.append(d)
	xs.append(field_rect.end.x)
	var rects: Array[Rect2] = []
	for i in xs.size() - 1:
		rects.append(Rect2(xs[i], field_rect.position.y, xs[i + 1] - xs[i], field_rect.size.y))
	return rects


## Điểm có nằm trong lòng ao không.
func is_in_pond(x: float, z: float) -> bool:
	return _pond_factor(Vector2(x, z)) < 1.0


# --- Nền --------------------------------------------------------------------------

func _build_ground(mb: MeshBuilder) -> void:
	var n := int(grid_extent * 2.0 / cell_size)
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			var x := -grid_extent + ix * cell_size
			var z := -grid_extent + iz * cell_size
			heights[iz * (n + 1) + ix] = height_at(x, z)

	for iz in n:
		for ix in n:
			var x0 := -grid_extent + ix * cell_size
			var z0 := -grid_extent + iz * cell_size
			var x1 := x0 + cell_size
			var z1 := z0 + cell_size
			var a := Vector3(x0, heights[iz * (n + 1) + ix], z0)
			var b := Vector3(x1, heights[iz * (n + 1) + ix + 1], z0)
			var c := Vector3(x1, heights[(iz + 1) * (n + 1) + ix + 1], z1)
			var d := Vector3(x0, heights[(iz + 1) * (n + 1) + ix], z1)
			# Đổi hướng đường chéo xen kẽ cho lưới bớt đều
			if (ix + iz) % 2 == 0:
				_ground_tri(mb, a, b, c)
				_ground_tri(mb, a, c, d)
			else:
				_ground_tri(mb, a, b, d)
				_ground_tri(mb, b, c, d)

	# Mặt phẳng bao ngoài lưới
	var e := grid_extent
	var s := skirt_extent
	var below := Vector3(0, -1, 0)
	mb.add_quad(Vector3(-s, 0, -s), Vector3(s, 0, -s), Vector3(s, 0, -e), Vector3(-s, 0, -e), Palette.GRASS, below)
	mb.add_quad(Vector3(-s, 0, e), Vector3(s, 0, e), Vector3(s, 0, s), Vector3(-s, 0, s), Palette.GRASS, below)
	mb.add_quad(Vector3(-s, 0, -e), Vector3(-e, 0, -e), Vector3(-e, 0, e), Vector3(-s, 0, e), Palette.GRASS, below)
	mb.add_quad(Vector3(e, 0, -e), Vector3(s, 0, -e), Vector3(s, 0, e), Vector3(e, 0, e), Palette.GRASS, below)


func _ground_tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Chỉ bờ ao mới có màu đất; chỗ trũng tự nhiên vẫn là cỏ
	var mid := (a + b + c) / 3.0
	var color := Palette.EARTH if _pond_factor(Vector2(mid.x, mid.z)) < 1.12 else Palette.GRASS
	mb.add_triangle(a, b, c, color, (a + b + c) / 3.0 + Vector3.DOWN)


# --- Ruộng ------------------------------------------------------------------------

func _build_fields(mb: MeshBuilder) -> void:
	var colors: Array[Color] = [Palette.RICE_1, Palette.RICE_2, Palette.RICE_3]
	var rects := paddy_rects()
	var y := 0.03
	var up_inside := Vector3(0, -1, 0)
	for i in rects.size():
		var r := rects[i]
		var col := colors[i % colors.size()]
		# Luống chạy dọc theo z (hướng về camera) để tạo chiều sâu phối cảnh
		var x := r.position.x
		while x < r.end.x - 0.01:
			var main_end := minf(x + furrow_spacing - furrow_width, r.end.x)
			var furrow_end := minf(x + furrow_spacing, r.end.x)
			_flat_rect(mb, x, main_end, r.position.y, r.end.y, y, col, up_inside)
			if furrow_end > main_end:
				_flat_rect(mb, main_end, furrow_end, r.position.y, r.end.y, y, Palette.RICE_FURROW, up_inside)
			x = furrow_end

	# Bờ ruộng: viền ngoài + các bờ chia thửa, hơi cong vẹo cho tự nhiên
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed + 10
	var fr := field_rect
	var outline := PackedVector2Array([
		fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y),
		fr.position])
	_build_dike(mb, outline, rng)
	for d in field_dividers:
		_build_dike(mb, PackedVector2Array([Vector2(d, fr.position.y), Vector2(d, fr.end.y)]), rng)


func _flat_rect(mb: MeshBuilder, x0: float, x1: float, z0: float, z1: float, y: float,
		color: Color, inside: Vector3) -> void:
	mb.add_quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1),
			color, inside)


## Bờ đất tiết diện hình thang chạy theo đường gấp khúc `points`.
func _build_dike(mb: MeshBuilder, points: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	# Chia nhỏ mỗi đoạn ~3 m và xô lệch ngang để bờ không thẳng tắp
	var pts := PackedVector2Array()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 3.0))
		var side := (b - a).normalized().orthogonal()
		for s in steps:
			var t := float(s) / steps
			var p := a.lerp(b, t)
			if s > 0:
				p += side * rng.randf_range(-dike_wobble, dike_wobble)
			pts.append(p)
	pts.append(points[points.size() - 1])

	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		# Kéo dài mỗi đoạn một chút để các khúc nối liền, không hở
		a -= dir * dike_top_width * 0.5
		b += dir * dike_top_width * 0.5
		var side := dir.orthogonal()
		var hb := dike_bottom_width * 0.5
		var ht := dike_top_width * 0.5
		var h := dike_height * rng.randf_range(0.85, 1.1)
		var a3 := Vector3(a.x, 0.0, a.y)
		var b3 := Vector3(b.x, 0.0, b.y)
		var s3 := Vector3(side.x, 0.0, side.y)
		var up := Vector3(0, h, 0)
		var bl0 := a3 - s3 * hb
		var br0 := a3 + s3 * hb
		var bl1 := b3 - s3 * hb
		var br1 := b3 + s3 * hb
		var tl0 := a3 - s3 * ht + up
		var tr0 := a3 + s3 * ht + up
		var tl1 := b3 - s3 * ht + up
		var tr1 := b3 + s3 * ht + up
		var inside := (a3 + b3) * 0.5 + up * 0.4
		mb.add_quad(tl0, tr0, tr1, tl1, Palette.DIKE, inside)   # mặt bờ
		mb.add_quad(bl0, tl0, tl1, bl1, Palette.DIKE, inside)   # sườn trái
		mb.add_quad(br0, tr0, tr1, br1, Palette.DIKE, inside)   # sườn phải
		mb.add_quad(bl0, br0, tr0, tl0, Palette.DIKE, inside)   # đầu
		mb.add_quad(bl1, br1, tr1, tl1, Palette.DIKE, inside)   # cuối


# --- Đường đất --------------------------------------------------------------------

func _build_path(mb: MeshBuilder) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed + 20
	var pts := _densify(path_points, 0.8)
	var inside := Vector3(0, -1, 0)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in pts.size():
		var p := pts[i]
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == pts.size() - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		var side := dir.normalized().orthogonal()
		var w := path_width * 0.5 * rng.randf_range(0.8, 1.15)
		var y := height_at(p.x, p.y) + 0.04
		var l := Vector3(p.x - side.x * w, y, p.y - side.y * w)
		var r := Vector3(p.x + side.x * w, y, p.y + side.y * w)
		if i > 0:
			mb.add_quad(prev_l, prev_r, r, l, Palette.EARTH, (prev_l + r) * 0.5 + inside)
		prev_l = l
		prev_r = r


static func _densify(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size() - 1:
		var n := maxi(1, int(points[i].distance_to(points[i + 1]) / step))
		for s in n:
			out.append(points[i].lerp(points[i + 1], float(s) / n))
	out.append(points[points.size() - 1])
	return out


# --- Ao ---------------------------------------------------------------------------

const POND_SEGMENTS := 28


func _make_pond_shape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed + 30
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	_pond_shape.resize(POND_SEGMENTS)
	for i in POND_SEGMENTS:
		var ang := TAU * i / POND_SEGMENTS
		# Bán kính dao động theo vài sóng sin => hình bất quy tắc nhưng mềm
		_pond_shape[i] = 1.0 + 0.16 * sin(2.0 * ang + p1) + 0.08 * sin(5.0 * ang + p2)


## 0 ở tâm ao, 1 ở mép ao, > 1 bên ngoài.
func _pond_factor(p: Vector2) -> float:
	var d := p - pond_center
	var ang := fposmod(atan2(d.y, d.x), TAU)
	var f := ang / TAU * POND_SEGMENTS
	var i0 := int(f) % POND_SEGMENTS
	var i1 := (i0 + 1) % POND_SEGMENTS
	var r := lerpf(_pond_shape[i0], _pond_shape[i1], f - floorf(f)) * pond_radius
	return d.length() / r


## Mặt nước: các vòng đồng tâm theo hình ao; vòng ngoài sáng (viền) và không lay sóng.
func _build_water() -> MeshInstance3D:
	var rings: Array[float] = [0.0, 0.3, 0.55, 0.78, 0.93, 1.05]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for r in rings:
		var ring: Array[Vector3] = []
		for i in POND_SEGMENTS:
			ring.append(_pond_point(i, maxf(r, 0.001)))
		pts.append(ring)
	for ri in rings.size() - 1:
		for i in POND_SEGMENTS:
			var j := (i + 1) % POND_SEGMENTS
			var a0: Vector3 = pts[ri][i]
			var a1: Vector3 = pts[ri][j]
			var b0: Vector3 = pts[ri + 1][i]
			var b1: Vector3 = pts[ri + 1][j]
			# Thứ tự đỉnh để mặt trước hướng lên trên
			for v in [[a0, ri], [b0, ri + 1], [b1, ri + 1], [a0, ri], [b1, ri + 1], [a1, ri]]:
				_water_vertex(st, v[0], rings[v[1]])
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader") as Shader
	var mi := MeshInstance3D.new()
	mi.name = "PondWater"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _water_vertex(st: SurfaceTool, p: Vector3, r: float) -> void:
	var edge := smoothstep(0.75, 1.0, r)
	var col := Palette.WATER.lerp(Palette.WATER_LIGHT, edge)
	col.a = 1.0 - smoothstep(0.85, 1.0, r)   # mép bờ không lay sóng
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(p)


func _pond_point(i: int, scale: float) -> Vector3:
	var ang := TAU * i / POND_SEGMENTS
	var r := _pond_shape[i] * pond_radius * scale
	return Vector3(pond_center.x + cos(ang) * r, water_level, pond_center.y + sin(ang) * r)


# --- Khoảng cách tới các vùng cần giữ phẳng ---------------------------------------

func _distance_to_features(p: Vector2) -> float:
	var d := _rect_distance(p, field_rect.grow(1.0))
	d = minf(d, _rect_distance(p, yard_rect))
	d = minf(d, maxf(0.0, (_pond_factor(p) - 1.0) * pond_radius))
	for i in path_points.size() - 1:
		d = minf(d, _segment_distance(p, path_points[i], path_points[i + 1]) - path_width)
	return maxf(d, 0.0)


static func _rect_distance(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dz).length()


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
