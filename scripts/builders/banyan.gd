class_name BanyanTree
extends Node3D
## Cây đa: thân to, rễ bạnh, cành chĩa, rễ phụ buông xuống, tán gồm nhiều khối đa diện.
## Tán là mesh riêng ("Leaves") để gắn shader gió.

@export var random_seed: int = 6106
@export var tree_position: Vector3 = Vector3(9.0, 0.0, -7.5)
@export var trunk_height: float = 3.6
@export var trunk_radius: float = 1.0
@export var canopy_radius: float = 4.4
@export var canopy_height: float = 5.6
@export_range(2, 8) var big_blobs: int = 4
@export_range(0, 12) var small_blobs: int = 7
@export_range(0, 20) var aerial_roots: int = 9

@export_group("Gió")
@export var wind_strength: float = 0.12
@export var wind_speed: float = 0.8

var leaves_node: MeshInstance3D


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var wood := MeshBuilder.new(random_seed, 0.05)
	wood.contact_shade_height = 1.0
	var leaves := MeshBuilder.new(random_seed + 1, 0.06)
	var p := tree_position

	# Thân
	wood.add_prism(trunk_radius, trunk_radius * 0.62, trunk_height, 8, Palette.BANYAN_TRUNK,
			Transform3D(Basis(), p), 0.2)
	# Rễ bạnh: các gờ thấp toả ra quanh gốc
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var axis := Vector3.UP.cross(dir).normalized()
		var root := Transform3D(Basis(axis, deg_to_rad(72.0)), p + dir * trunk_radius * 0.4)
		wood.add_prism(0.38, 0.06, rng.randf_range(1.5, 2.1), 4, Palette.BANYAN_TRUNK, root, PI / 4.0)

	# Cành lớn chĩa lên các phía
	var tips: Array[Vector3] = []
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var axis := Vector3.UP.cross(dir).normalized()
		var tilt := deg_to_rad(rng.randf_range(40.0, 58.0))
		var start := p + Vector3(0, trunk_height - 0.4, 0)
		var basis := Basis(axis, tilt)
		var length := rng.randf_range(2.4, 3.2)
		wood.add_prism(0.38, 0.14, length, 6, Palette.BANYAN_TRUNK, Transform3D(basis, start))
		tips.append(start + basis * Vector3(0, length, 0))

	# Tán: vài khối lớn ở giữa + khối nhỏ ở rìa
	var colors: Array[Color] = [Palette.BANYAN_LEAF_1, Palette.BANYAN_LEAF_2]
	for i in big_blobs:
		var a := TAU * i / big_blobs + rng.randf_range(-0.3, 0.3)
		var off := Vector3(cos(a), 0.0, sin(a)) * canopy_radius * rng.randf_range(0.25, 0.45)
		var rad := Vector3(rng.randf_range(2.4, 3.0), rng.randf_range(1.5, 1.9), rng.randf_range(2.4, 3.0))
		var cy := canopy_height + rng.randf_range(-0.4, 0.6)
		leaves.add_blob(rad, colors[i % 2], rng, 0.18,
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + off + Vector3(0, cy - rad.y, 0)))
	for i in small_blobs:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0.0, sin(a)) * canopy_radius * rng.randf_range(0.6, 0.85)
		var rad := Vector3.ONE * rng.randf_range(1.1, 1.7) * Vector3(1.0, 0.75, 1.0)
		var cy := canopy_height + rng.randf_range(-1.2, 0.2)
		var col := Palette.BANYAN_LEAF_DARK if cy < canopy_height - 0.5 else colors[i % 2]
		leaves.add_blob(rad, col, rng, 0.22,
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + off + Vector3(0, cy - rad.y, 0)))
	# Khối đỉnh
	leaves.add_blob(Vector3(2.0, 1.4, 2.0), Palette.BANYAN_LEAF_2, rng, 0.2,
			Transform3D(Basis(), p + Vector3(0, canopy_height + 0.6, 0)))

	# Rễ phụ buông từ dưới tán
	for i in aerial_roots:
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.4, canopy_radius * 0.7)
		var top_y := canopy_height - rng.randf_range(1.0, 1.6)
		var len_ := rng.randf_range(1.2, top_y - 0.4)
		var base := p + Vector3(cos(a) * d, top_y - len_, sin(a) * d)
		wood.add_prism(0.045, 0.03, len_, 4, Palette.BANYAN_TRUNK, Transform3D(Basis(), base))

	add_child(wood.commit_instance("Wood"))
	var wind := MeshBuilder.wind_material(wind_strength, trunk_height, canopy_height, wind_speed)
	leaves_node = leaves.commit_instance("Leaves", wind)
	add_child(leaves_node)
