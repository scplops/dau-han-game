class_name MeshBuilder
extends RefCounted
## Sinh mesh low-poly flat-shaded bằng SurfaceTool.
## Một MeshBuilder gom nhiều khối (mỗi khối một màu) thành MỘT mesh duy nhất,
## dùng chung một vật liệu đọc màu đỉnh, nên ít draw call.
##
## Ví dụ:
##   var mb := MeshBuilder.new()
##   mb.add_box(Vector3(4, 2.5, 3), Palette.WALL)
##   mb.add_wedge(Vector3(4.6, 1.5, 3.8), Palette.ROOF, Transform3D(Basis(), Vector3(0, 2.5, 0)))
##   mesh_instance.mesh = mb.commit()
##
## Quy ước: mọi khối có ĐÁY nằm ở y = 0 và tâm đáy ở gốc toạ độ;
## dùng tham số `xform` để dời / xoay / co giãn.

static var _shared_material: StandardMaterial3D

## Độ lệch màu ngẫu nhiên của từng mặt (0 = tắt, 0.04 = ±4% độ sáng).
## Làm mặt đất, tường, tán lá bớt đơn điệu mà không thêm đa giác.
var color_jitter: float = 0.0
## Bóng tiếp xúc: đỉnh thấp hơn độ cao này (toạ độ sau xform) bị tối dần về phía đất.
## 0 = tắt. Dùng cho vật đứng trên đất (nhà, cây, đá), KHÔNG dùng cho mặt đất.
var contact_shade_height: float = 0.0
var contact_shade_strength: float = 0.25

var _st := SurfaceTool.new()
var _count: int = 0
var _rng: RandomNumberGenerator


## `seed_value` quyết định độ lệch màu, để cảnh giống nhau mỗi lần chạy.
func _init(seed_value: int = 1, jitter: float = 0.0) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	color_jitter = jitter
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st.set_smooth_group(-1)  # pháp tuyến tự đặt ở _tri (mặt phẳng hoặc mượt)


## Vật liệu dùng chung: màu lấy từ màu đỉnh, nhám hoàn toàn.
static func material() -> StandardMaterial3D:
	if _shared_material == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 1.0
		mat.metallic = 0.0
		_shared_material = mat
	return _shared_material


## Vật liệu gió (shaders/wind_sway.gdshader). `base_height`/`sway_height` theo toạ độ
## cục bộ của mesh: dưới base đứng yên, lên tới base + sway thì lay mạnh nhất.
static func wind_material(strength: float, base_height: float, sway_height: float,
		speed: float = 1.4) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wind_sway.gdshader") as Shader
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("base_height", base_height)
	mat.set_shader_parameter("sway_height", sway_height)
	mat.set_shader_parameter("speed", speed)
	return mat


## Số tam giác đã thêm.
func triangle_count() -> int:
	return _count


## Kết thúc và trả về mesh (đã gán vật liệu mặc định).
func commit(mat: Material = null) -> ArrayMesh:
	# Pháp tuyến đã đặt sẵn ở từng đỉnh (_tri): mặt phẳng = pháp tuyến mặt, khối mượt = pháp tuyến cong
	_st.set_material(mat if mat != null else material())
	return _st.commit()


## Tạo luôn MeshInstance3D từ mesh đã dựng.
func commit_instance(node_name: String = "Mesh", mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = commit(mat)
	return mi


# --- Khối cơ bản -------------------------------------------------------------

## Tam giác đơn. `inside` là một điểm nằm phía sau mặt (thường là tâm khối):
## thứ tự đỉnh được tự đảo để pháp tuyến luôn hướng ra ngoài.
func add_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color,
		inside: Vector3, xform: Transform3D = Transform3D.IDENTITY) -> MeshBuilder:
	_tri(a, b, c, vary(color), inside, xform)
	return self


## Tứ giác (2 tam giác cùng một màu), các đỉnh theo thứ tự vòng quanh.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color,
		inside: Vector3, xform: Transform3D = Transform3D.IDENTITY) -> MeshBuilder:
	var col := vary(color)
	_tri(a, b, c, col, inside, xform)
	_tri(a, c, d, col, inside, xform)
	return self


## Màu sau khi lệch ngẫu nhiên theo `color_jitter`.
func vary(color: Color) -> Color:
	if color_jitter <= 0.0:
		return color
	var k := 1.0 + _rng.randf_range(-color_jitter, color_jitter)
	var out := Color(color.r * k, color.g * k, color.b * k, color.a)
	out.h = wrapf(out.h + _rng.randf_range(-color_jitter, color_jitter) * 0.12, 0.0, 1.0)
	return out


## Tam giác; `na/nb/nc` (toạ độ cục bộ) là pháp tuyến mượt từng đỉnh — bỏ trống thì dùng pháp tuyến mặt.
func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color,
		inside: Vector3, xform: Transform3D,
		na: Vector3 = Vector3.ZERO, nb: Vector3 = Vector3.ZERO, nc: Vector3 = Vector3.ZERO) -> void:
	a = xform * a
	b = xform * b
	c = xform * c
	inside = xform * inside
	# Godot: mặt trước theo chiều kim đồng hồ, pháp tuyến = (c - a) x (b - a)
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		var tmp := b
		b = c
		c = tmp
		var tn := nb
		nb = nc
		nc = tn
		n = -n
	n = n.normalized()
	var smooth := na != Vector3.ZERO
	var nbasis := xform.basis.inverse().transposed() if smooth else Basis()
	var verts := [a, b, c]
	var norms := [na, nb, nc]
	for k in 3:
		var v: Vector3 = verts[k]
		_st.set_color(_shade(color, v))
		_st.set_normal((nbasis * (norms[k] as Vector3)).normalized() if smooth else n)
		_st.add_vertex(v)
	_count += 1


## Tối dần phần sát đất (bóng tiếp xúc giả).
func _shade(color: Color, v: Vector3) -> Color:
	if contact_shade_height <= 0.0 or v.y >= contact_shade_height:
		return color
	var t := clampf(1.0 - v.y / contact_shade_height, 0.0, 1.0)
	return color.darkened(contact_shade_strength * t)


## Hộp chữ nhật kích thước `size`, đáy ở y = 0.
func add_box(size: Vector3, color: Color,
		xform: Transform3D = Transform3D.IDENTITY) -> MeshBuilder:
	var h := Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	var y := size.y
	var p := [
		Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z),
		Vector3(-h.x, y, -h.z), Vector3(h.x, y, -h.z), Vector3(h.x, y, h.z), Vector3(-h.x, y, h.z),
	]
	var center := Vector3(0, y * 0.5, 0)
	add_quad(p[0], p[1], p[2], p[3], color, center, xform)  # đáy
	add_quad(p[4], p[5], p[6], p[7], color, center, xform)  # nóc
	add_quad(p[0], p[1], p[5], p[4], color, center, xform)  # sau
	add_quad(p[3], p[2], p[6], p[7], color, center, xform)  # trước
	add_quad(p[0], p[3], p[7], p[4], color, center, xform)  # trái
	add_quad(p[1], p[2], p[6], p[5], color, center, xform)  # phải
	return self


## Lăng trụ / chóp cụt / chóp nhọn `sides` cạnh.
## radius_top = 0 => chóp nhọn; radius_top = radius_bottom => lăng trụ đều.
func add_prism(radius_bottom: float, radius_top: float, height: float, sides: int,
		color: Color, xform: Transform3D = Transform3D.IDENTITY,
		angle_offset: float = 0.0, cap_bottom: bool = true) -> MeshBuilder:
	sides = maxi(sides, 3)
	var center := Vector3(0, height * 0.5, 0)
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides:
		var ang := angle_offset + TAU * float(i) / float(sides)
		var dir := Vector3(cos(ang), 0, sin(ang))
		bottom.append(dir * radius_bottom)
		top.append(dir * radius_top + Vector3(0, height, 0))
	var apex := Vector3(0, height, 0)
	var base_center := Vector3.ZERO
	for i in sides:
		var j := (i + 1) % sides
		if radius_top <= 0.0:
			add_triangle(bottom[i], bottom[j], apex, color, center, xform)
		else:
			add_quad(bottom[i], bottom[j], top[j], top[i], color, center, xform)
			add_triangle(top[i], top[j], apex, color, center, xform)
		if cap_bottom:
			add_triangle(bottom[i], bottom[j], base_center, color, center, xform)
	return self


## Chóp nhọn (nón) — rút gọn của add_prism với radius_top = 0.
func add_pyramid(radius: float, height: float, sides: int, color: Color,
		xform: Transform3D = Transform3D.IDENTITY) -> MeshBuilder:
	return add_prism(radius, 0.0, height, sides, color, xform)


## Lăng trụ tam giác nằm ngang (hình mái hai dốc).
## size.x: chiều dài nóc mái, size.y: chiều cao, size.z: bề rộng chân mái.
## `end_color`: màu hai đầu hồi (mặc định bằng `color`).
func add_wedge(size: Vector3, color: Color,
		xform: Transform3D = Transform3D.IDENTITY,
		end_color: Color = Color(0, 0, 0, 0)) -> MeshBuilder:
	var ends := color if end_color.a == 0.0 else end_color
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var center := Vector3(0, size.y / 3.0, 0)
	var l0 := Vector3(-hx, 0, -hz)
	var l1 := Vector3(-hx, 0, hz)
	var lt := Vector3(-hx, size.y, 0)
	var r0 := Vector3(hx, 0, -hz)
	var r1 := Vector3(hx, 0, hz)
	var rt := Vector3(hx, size.y, 0)
	add_quad(l0, r0, rt, lt, color, center, xform)  # dốc sau
	add_quad(l1, r1, rt, lt, color, center, xform)  # dốc trước
	add_triangle(l0, l1, lt, ends, center, xform)   # hồi trái
	add_triangle(r0, r1, rt, ends, center, xform)   # hồi phải
	add_quad(l0, r0, r1, l1, color, center, xform)  # đáy
	return self


## Khúc trụ nối điểm a tới điểm b (thân cây, cành, sừng, cán...).
func add_limb(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, color: Color,
		xform: Transform3D = Transform3D.IDENTITY) -> MeshBuilder:
	var dir := b - a
	if dir.length() < 0.0001:
		return self
	var n := dir.normalized()
	var axis := Vector3.UP.cross(n)
	var basis := Basis()
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(n))
	elif n.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	return add_prism(r0, r1, dir.length(), sides, color, xform * Transform3D(basis, a))


# --- Khối bo tròn, mặt mượt (dùng cho người: "low-poly mềm") ----------------------------

## Vành tròn theo profile [(y, bán kính, góc φ của pháp tuyến)…] quanh trục y, nối các vành
## bằng dải tứ giác. `smooth`: pháp tuyến cong theo φ (khối tròn); `ny_scale` làm dẹt theo y.
func _lathe(profile: Array, sides: int, col: Color, scale_xz: Vector2, xform: Transform3D,
		smooth: bool, ny_scale: float = 1.0) -> void:
	var rings: Array = []
	var nrings: Array = []
	for pr: Vector3 in profile:
		var ring: Array[Vector3] = []
		var nring: Array[Vector3] = []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			ring.append(Vector3(cos(a) * pr.y * scale_xz.x, pr.x, sin(a) * pr.y * scale_xz.y))
			nring.append(Vector3(cos(pr.z) * cos(a) / scale_xz.x, sin(pr.z) / ny_scale, cos(pr.z) * sin(a) / scale_xz.y).normalized())
		rings.append(ring)
		nrings.append(nring)
	for k in profile.size() - 1:
		var r0: Array[Vector3] = rings[k]
		var r1: Array[Vector3] = rings[k + 1]
		var n0: Array[Vector3] = nrings[k]
		var n1: Array[Vector3] = nrings[k + 1]
		var inside := Vector3(0, ((profile[k] as Vector3).x + (profile[k + 1] as Vector3).x) * 0.5, 0)
		for i in sides:
			var j := (i + 1) % sides
			if (profile[k] as Vector3).y > 0.0001:
				if smooth:
					_tri(r0[i], r0[j], r1[j], col, inside, xform, n0[i], n0[j], n1[j])
				else:
					_tri(r0[i], r0[j], r1[j], col, inside, xform)
			if (profile[k + 1] as Vector3).y > 0.0001:
				if smooth:
					_tri(r0[i], r1[j], r1[i], col, inside, xform, n0[i], n1[j], n1[i])
				else:
					_tri(r0[i], r1[j], r1[i], col, inside, xform)


## Ống bo tròn hai đầu (bắp tay, bắp chân, thân người) từ điểm a tới b, bán kính r0 → r1.
## Mặc định mặt mượt; `scale_xz` để dẹt ống (thân người dẹt trước sau).
func add_capsule(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, color: Color,
		xform: Transform3D = Transform3D.IDENTITY, smooth: bool = true,
		scale_xz: Vector2 = Vector2.ONE) -> MeshBuilder:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return self
	var n := dir / length
	var axis := Vector3.UP.cross(n)
	var basis := Basis()
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(n))
	elif n.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	var profile: Array = []
	var cap := 3
	for i in cap + 1:
		var phi := -PI * 0.5 + PI * 0.5 * float(i) / cap
		profile.append(Vector3(r0 * sin(phi), r0 * cos(phi), phi))
	for i in cap + 1:
		var phi := PI * 0.5 * float(i) / cap
		profile.append(Vector3(length + r1 * sin(phi), r1 * cos(phi), phi))
	_lathe(profile, sides, vary(color), scale_xz, xform * Transform3D(basis, a), smooth)
	return self


## Khối trứng / cầu dẹt (đầu, bàn tay, bàn chân, hông). Đáy ở y = 0 như các khối khác.
func add_ellipsoid(radius: Vector3, color: Color, xform: Transform3D = Transform3D.IDENTITY,
		sides: int = 10, rings: int = 6, smooth: bool = true) -> MeshBuilder:
	var profile: Array = []
	for i in rings + 1:
		var phi := -PI * 0.5 + PI * float(i) / rings
		profile.append(Vector3(radius.y + radius.y * sin(phi), cos(phi), phi))
	_lathe(profile, sides, vary(color), Vector2(radius.x, radius.z), xform, smooth, radius.y)
	return self


## Đa diện ngẫu nhiên (khối đá, tán cây): khối 20 mặt có đỉnh bị xô lệch.
## `radius` co giãn theo từng trục; `jitter` 0..0.5 là độ méo.
## Tâm khối ở y = radius.y để đáy chạm đất.
func add_blob(radius: Vector3, color: Color, rng: RandomNumberGenerator,
		jitter: float = 0.2, xform: Transform3D = Transform3D.IDENTITY) -> MeshBuilder:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var raw := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var center := Vector3(0, radius.y, 0)
	var verts: Array[Vector3] = []
	for v: Vector3 in raw:
		var k := 1.0 + rng.randf_range(-jitter, jitter)
		verts.append(v.normalized() * radius * k + center)
	for f: Array in faces:
		add_triangle(verts[f[0]], verts[f[1]], verts[f[2]], color, center, xform)
	return self
