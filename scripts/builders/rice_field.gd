class_name RiceField
extends Node3D
## Lúa: hàng nghìn khóm nhỏ (MultiMesh) trồng theo luống trong 3 thửa ruộng,
## mỗi thửa một sắc xanh, lay theo gió. Chừa chỗ trống cho trâu và người đứng.
## Giữ lại vị trí / thửa / thứ tự cấy của từng khóm (`base_xforms`, `paddy_of`, `order01`) để `Farming`
## (mục 33) đổi cao thấp, màu, cấy dần, gặt dần theo mùa vụ; `ears_mm` là bông lúa (ẩn tới khi trổ).

@export var terrain: Terrain
@export var random_seed: int = 8108

@export_group("Khóm lúa")
@export_range(1, 4) var columns_per_strip: int = 3
@export var row_spacing: float = 0.3
@export var position_jitter: float = 0.05
@export var clump_height: float = 0.55
@export var scale_range: Vector2 = Vector2(0.85, 1.2)
@export_range(3, 9) var blades_per_clump: int = 5
@export_range(0.0, 0.2) var color_variation: float = 0.06
## Khoảng cách tối thiểu tới tim bờ ruộng.
@export var dike_margin: float = 0.45
## Các vùng không trồng lúa: (x, z, bán kính) — chỗ trâu và người đứng.
@export var clear_zones: PackedVector3Array = PackedVector3Array([
	Vector3(-4.6, 9.6, 1.9), Vector3(-7.0, 12.2, 0.9)])

@export_group("Gió")
@export var wind_strength: float = 0.07
@export var wind_speed: float = 1.6
@export var cast_shadows: bool = false

var clump_count: int = 0
var mm: MultiMesh
var ears_mm: MultiMesh
var base_xforms: Array[Transform3D] = []
var base_colors: Array[Color] = []
## Thửa (0…) của từng khóm và thứ tự cấy / gặt 0…1 trong thửa (theo luống, từ đầu bờ này sang bờ kia).
var paddy_of: PackedInt32Array = PackedInt32Array()
var order01: PackedFloat32Array = PackedFloat32Array()
var paddy_count: int = 0


func build() -> void:
	if terrain == null:
		push_warning("RiceField: chưa gán terrain")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var colors: Array[Color] = [Palette.RICE_1, Palette.RICE_2, Palette.RICE_3]

	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var rects := terrain.paddy_rects()
	paddy_count = rects.size()
	for i in rects.size():
		var r := rects[i].grow(-dike_margin)
		var base_col := colors[i % colors.size()]
		var x := rects[i].position.x
		var main_w := terrain.furrow_spacing - terrain.furrow_width
		while x < r.end.x:
			for c in columns_per_strip:
				var cx := x + main_w * (c + 0.5) / columns_per_strip
				if cx < r.position.x or cx > r.end.x:
					continue
				var z := r.position.y
				while z < r.end.y:
					var p := Vector3(cx + rng.randf_range(-position_jitter, position_jitter), 0.03,
							z + rng.randf_range(-position_jitter, position_jitter))
					if not _is_cleared(p):
						var s := rng.randf_range(scale_range.x, scale_range.y)
						var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
						xforms.append(Transform3D(basis, p))
						var k := 1.0 + rng.randf_range(-color_variation, color_variation)
						cols.append(Color(base_col.r * k, base_col.g * k, base_col.b * k))
						paddy_of.append(i)
						# Cấy / gặt theo từng luống từ bờ tây sang bờ đông, trong luống từ bắc xuống nam
						var fx := (p.x - rects[i].position.x) / rects[i].size.x
						var fz := (p.z - rects[i].position.y) / rects[i].size.y
						order01.append(clampf(floorf(fx * 12.0) / 12.0 + fz / 12.0, 0.0, 1.0))
					z += row_spacing
			x += terrain.furrow_spacing

	base_xforms = xforms
	base_colors = cols
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _make_clump_mesh(rng)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
	clump_count = xforms.size()
	print("RiceField: %d khóm lúa" % clump_count)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RiceClumps"
	mmi.multimesh = mm
	mmi.material_override = MeshBuilder.wind_material(wind_strength, 0.0, clump_height, wind_speed)
	if not cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# Bông lúa: chùm hạt rủ xuống trên ngọn khóm, ẩn (co về 0) tới khi lúa trổ bông
	ears_mm = MultiMesh.new()
	ears_mm.transform_format = MultiMesh.TRANSFORM_3D
	ears_mm.use_colors = true
	ears_mm.mesh = _make_ear_mesh()
	ears_mm.instance_count = xforms.size()
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in xforms.size():
		ears_mm.set_instance_transform(i, zero)
		ears_mm.set_instance_color(i, Palette.RICE_1)
	var emi := MultiMeshInstance3D.new()
	emi.name = "RiceEars"
	emi.multimesh = ears_mm
	emi.material_override = MeshBuilder.wind_material(wind_strength * 1.6, -0.1, 0.25, wind_speed)
	emi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emi)


## Bông lúa: 3 nhánh hạt cong rủ xuống từ gốc (gốc = ngọn khóm lúa).
func _make_ear_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new(random_seed + 7, 0.0)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var d := Vector3(cos(a), 0, sin(a))
		mb.add_limb(Vector3(0, -0.02, 0), d * 0.07 + Vector3(0, 0.05, 0), 0.012, 0.016, 4, Color.WHITE)
		mb.add_limb(d * 0.07 + Vector3(0, 0.05, 0), d * 0.13 - Vector3(0, 0.03, 0), 0.016, 0.006, 4, Color(0.92, 0.92, 0.92))
	return mb.commit()


func _is_cleared(p: Vector3) -> bool:
	for zone in clear_zones:
		if Vector2(p.x - zone.x, p.z - zone.y).length() < zone.z:
			return true
	return false


## Một khóm: vài lá mảnh hình chóp 3 cạnh xoè ra. Màu trắng xám để màu instance
## (màu từng thửa) quyết định sắc lúa; gốc tối dần.
func _make_clump_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new(random_seed, 0.0)
	mb.contact_shade_height = clump_height * 0.5
	mb.contact_shade_strength = 0.3
	for i in blades_per_clump:
		var a := TAU * i / blades_per_clump + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var axis := Vector3.UP.cross(dir).normalized()
		var tilt := deg_to_rad(rng.randf_range(8.0, 28.0))
		var h := clump_height * rng.randf_range(0.75, 1.0)
		var shade := rng.randf_range(0.95, 1.05)
		mb.add_prism(0.035, 0.0, h, 3, Color(shade, shade, shade),
				Transform3D(Basis(axis, tilt), dir * 0.03), rng.randf() * TAU, false)
	return mb.commit()
