class_name Mountains
extends Node3D
## Hậu cảnh: một dải đồi thấp ngay sau cảnh và một dãy núi xa, nhạt dần về màu sương.

@export var random_seed: int = 7107
@export_group("Đồi gần")
@export_range(0, 30) var hill_count: int = 11
@export var hill_z_range: Vector2 = Vector2(-40.0, -58.0)
@export var hill_height_range: Vector2 = Vector2(5.0, 12.0)
@export var hill_radius_range: Vector2 = Vector2(9.0, 16.0)
@export_range(0.0, 1.0) var hill_haze: float = 0.12
@export_group("Núi xa")
@export_range(0, 30) var peak_count: int = 10
@export var peak_z_range: Vector2 = Vector2(-80.0, -125.0)
@export var peak_height_range: Vector2 = Vector2(16.0, 34.0)
@export var peak_radius_range: Vector2 = Vector2(18.0, 30.0)
@export_range(0.0, 1.0) var peak_haze: float = 0.4
@export var x_extent: float = 95.0


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var mb := MeshBuilder.new(random_seed, 0.05)
	_row(mb, rng, peak_count, peak_z_range, peak_height_range, peak_radius_range, peak_haze)
	_row(mb, rng, hill_count, hill_z_range, hill_height_range, hill_radius_range, hill_haze)
	var node := mb.commit_instance("MountainsMesh")
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _row(mb: MeshBuilder, rng: RandomNumberGenerator, count: int, z_range: Vector2,
		h_range: Vector2, r_range: Vector2, haze: float) -> void:
	for i in count:
		# Rải đều theo x, xô lệch ngẫu nhiên để không thành hàng
		var x := lerpf(-x_extent, x_extent, (i + rng.randf_range(0.1, 0.9)) / count)
		var z := rng.randf_range(z_range.x, z_range.y)
		var h := rng.randf_range(h_range.x, h_range.y)
		var r := rng.randf_range(r_range.x, r_range.y)
		var base_col := Palette.MOUNTAIN if rng.randf() < 0.55 else Palette.MOUNTAIN_DARK
		var col := base_col.lerp(Palette.FOG, haze)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(1.0, 1.6), 1.0, 1.0))
		mb.add_prism(r, r * rng.randf_range(0.04, 0.15), h, rng.randi_range(5, 7), col,
				Transform3D(basis, Vector3(x, -0.6, z)))
