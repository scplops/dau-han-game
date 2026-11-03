class_name BambooGrove
extends Node3D
## Lũy tre: một cụm thân tre nhiều đốt, hơi nghiêng ra ngoài, chùm lá ở phần ngọn.
## Lá là mesh riêng ("Leaves") để gắn shader gió.

@export var random_seed: int = 5105
@export var center: Vector3 = Vector3(2.5, 0.0, -15.5)
@export_range(1, 30) var culm_count: int = 14
@export var spread: float = 2.2
@export var height_range: Vector2 = Vector2(6.0, 9.5)
@export var stem_radius_range: Vector2 = Vector2(0.07, 0.11)
@export var segment_range: Vector2 = Vector2(0.55, 0.85)
@export var max_lean_deg: float = 18.0
@export_range(2, 10) var leaf_clusters: int = 6

var leaves_node: MeshInstance3D


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var stems := MeshBuilder.new(random_seed, 0.05)
	stems.contact_shade_height = 0.8
	var leaves := MeshBuilder.new(random_seed + 1, 0.07)

	for i in culm_count:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * spread
		var out_dir := Vector3(cos(ang), 0.0, sin(ang))
		var base := center + out_dir * r
		# Nghiêng ra phía ngoài cụm, càng ở rìa càng nghiêng
		var lean := deg_to_rad(rng.randf_range(2.0, max_lean_deg) * (0.4 + 0.6 * r / spread))
		var axis := Vector3.UP.cross(out_dir).normalized()
		var xf := Transform3D(Basis(axis, lean), base)
		var h := rng.randf_range(height_range.x, height_range.y)
		_build_culm(stems, xf, h, rng)
		_build_leaves(leaves, xf, h, rng)

	# Măng non quanh gốc
	for i in 6:
		var a := rng.randf() * TAU
		var p := center + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.5, spread + 0.6)
		stems.add_pyramid(0.12, rng.randf_range(0.4, 0.9), 5, Palette.BAMBOO_LEAF_DARK,
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))

	add_child(stems.commit_instance("Stems"))
	leaves_node = leaves.commit_instance("Leaves")
	add_child(leaves_node)


func _build_culm(mb: MeshBuilder, xf: Transform3D, h: float, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(stem_radius_range.x, stem_radius_range.y)
	var y := 0.0
	while y < h:
		var seg := minf(rng.randf_range(segment_range.x, segment_range.y), h - y)
		mb.add_prism(r, r * 0.96, seg, 6, Palette.BAMBOO_STEM, xf * Transform3D(Basis(), Vector3(0, y, 0)))
		# Đốt tre: vòng hơi phình
		mb.add_prism(r * 1.3, r * 1.3, 0.05, 6, Palette.BAMBOO_NODE,
				xf * Transform3D(Basis(), Vector3(0, y + seg - 0.025, 0)), 0.0, false)
		y += seg
		r *= 0.96


func _build_leaves(mb: MeshBuilder, xf: Transform3D, h: float, rng: RandomNumberGenerator) -> void:
	for k in leaf_clusters:
		var t := float(k) / float(leaf_clusters - 1)
		# Lá tụ ở 40% phần ngọn, toả rộng ra như ngọn tre vươn và rủ
		var y := lerpf(h * 0.6, h * 0.97, t)
		var side := rng.randf() * TAU
		var off := Vector3(cos(side), 0.0, sin(side)) * rng.randf_range(0.5, 1.3) * (1.0 - t * 0.4)
		var col := Palette.BAMBOO_LEAF if rng.randf() < 0.6 else Palette.BAMBOO_LEAF_DARK
		var size := lerpf(1.15, 0.7, t)
		var rad := Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.35, 0.5), rng.randf_range(0.9, 1.3)) * size
		# Khối lá + chóp lá rủ xuống bên dưới
		mb.add_blob(rad, col, rng, 0.3, xf * Transform3D(Basis(), Vector3(0, y - rad.y, 0) + off))
		var droop := Transform3D(Basis(Vector3.RIGHT, PI).rotated(Vector3.UP, rng.randf() * TAU),
				Vector3(0, y - rad.y * 0.3, 0) + off)
		mb.add_pyramid(rad.x * 0.8, 1.1 * size + 0.4, 5, Palette.BAMBOO_LEAF_DARK, xf * droop)
	# Ngọn cong rủ: chóp lá nghiêng hẳn sang một bên
	var tip_dir := rng.randf() * TAU
	var tip_basis := Basis(Vector3(cos(tip_dir), 0.0, sin(tip_dir)), deg_to_rad(rng.randf_range(35.0, 60.0)))
	mb.add_pyramid(0.4, 1.6, 5, Palette.BAMBOO_LEAF, xf * Transform3D(tip_basis, Vector3(0, h - 0.4, 0)))
