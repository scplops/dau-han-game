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

var _st := SurfaceTool.new()
var _count: int = 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st.set_smooth_group(-1)  # -1 = không làm mượt => flat shading


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


## Số tam giác đã thêm.
func triangle_count() -> int:
	return _count


## Kết thúc và trả về mesh (đã gán vật liệu mặc định).
func commit(mat: Material = null) -> ArrayMesh:
	_st.generate_normals()
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
	_st.set_color(color)
	_st.add_vertex(a)
	_st.add_vertex(b)
	_st.add_vertex(c)
	_count += 1
	return self


## Tứ giác (2 tam giác), các đỉnh theo thứ tự vòng quanh.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color,
		inside: Vector3, xform: Transform3D = Transform3D.IDENTITY) -> MeshBuilder:
	add_triangle(a, b, c, color, inside, xform)
	add_triangle(a, c, d, color, inside, xform)
	return self


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
