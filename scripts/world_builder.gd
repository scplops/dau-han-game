extends Node3D
## Dựng toàn cảnh khi chạy: đặt độ dày sương rồi gọi `build()`
## của từng builder con theo thứ tự trong cây scene (Terrain trước, các vật sau).

@export var world_environment: WorldEnvironment

@export_group("Không khí")
## Màu trời, mặt trời, ánh sáng môi trường do DayNight điều khiển theo giờ.
@export_range(0.0, 0.05, 0.0005) var fog_density: float = 0.0035

@export_group("Kiểm thử")
## Hiện hàng khối mẫu của MeshBuilder (bước 2). Sẽ tắt khi có cảnh thật.
@export var show_test_shapes: bool = false
@export var random_seed: int = 20261103


func _ready() -> void:
	_apply_atmosphere()
	for child in get_children():
		if child.has_method("build"):
			child.call("build")
	if show_test_shapes:
		_build_test_shapes()


func _apply_atmosphere() -> void:
	if world_environment != null:
		world_environment.environment.fog_density = fog_density


## Hàng khối mẫu để kiểm tra MeshBuilder: flat shading, màu đỉnh, gộp nhiều khối.
func _build_test_shapes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var mb := MeshBuilder.new()
	mb.add_box(Vector3(2, 2, 2), Palette.WALL, _at(-12.0))
	mb.add_prism(1.0, 1.0, 2.5, 6, Palette.BAMBOO_STEM, _at(-8.0))      # lăng trụ 6 cạnh
	mb.add_prism(1.4, 0.7, 1.8, 7, Palette.MOUNTAIN, _at(-4.0))         # chóp cụt
	mb.add_pyramid(1.3, 3.0, 5, Palette.BAMBOO_LEAF, _at(0.0))          # chóp nhọn
	mb.add_wedge(Vector3(2.6, 1.4, 2.2), Palette.ROOF, _at(4.0), Palette.WALL_DARK)
	mb.add_blob(Vector3(1.3, 1.1, 1.3), Palette.BANYAN_LEAF_2, rng, 0.2, _at(8.0))

	# Khối ghép: nhà nhỏ (tường + mái + cửa) trong cùng một mesh
	var house: Transform3D = _at(12.0)
	mb.add_box(Vector3(2.4, 1.4, 1.8), Palette.WALL, house)
	mb.add_wedge(Vector3(2.8, 1.1, 2.3), Palette.ROOF,
			house * Transform3D(Basis(), Vector3(0, 1.4, 0)), Palette.WALL_DARK)
	mb.add_box(Vector3(0.5, 0.9, 0.05), Palette.WOOD,
			house * Transform3D(Basis(), Vector3(0, 0, 0.92)))

	var mi := mb.commit_instance("TestShapes")
	add_child(mi)
	print("TestShapes: %d tam giác" % mb.triangle_count())


static func _at(x: float, z: float = 0.0) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, 0.0, z))
