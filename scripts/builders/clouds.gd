class_name Clouds
extends Node3D
## Vài đám mây low-poly trôi chậm qua phía trên cảnh, đổ bóng nhẹ xuống ruộng.
## Bay thấp hơn camera vì góc nhìn chéo từ trên không thấy được bầu trời xa.

@export var random_seed: int = 1212
@export_range(0, 20) var cloud_count: int = 9
@export var height_range: Vector2 = Vector2(16.0, 24.0)
@export var z_range: Vector2 = Vector2(-175.0, -35.0)
@export var x_extent: float = 140.0
@export var speed: float = 0.5
@export var cast_shadows: bool = true

var _clouds: Array[Node3D] = []


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for i in cloud_count:
		var mb := MeshBuilder.new(random_seed + i, 0.03)
		var size := rng.randf_range(0.8, 1.25)
		mb.add_blob(Vector3(2.8, 1.2, 2.0) * size, Palette.CLOUD, rng, 0.2)
		for k in rng.randi_range(2, 4):
			var off := Vector3(rng.randf_range(-2.6, 2.6), rng.randf_range(-0.3, 0.5), rng.randf_range(-1.2, 1.2)) * size
			var r := Vector3(rng.randf_range(1.3, 2.0), rng.randf_range(0.8, 1.1), rng.randf_range(1.1, 1.6)) * size
			mb.add_blob(r, Palette.CLOUD, rng, 0.2, Transform3D(Basis(), off))
		var node := mb.commit_instance("Cloud%d" % i)
		if not cast_shadows:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Rải đều theo x để không dồn cục
		var x := lerpf(-x_extent, x_extent, (i + rng.randf_range(0.2, 0.8)) / maxf(cloud_count, 1))
		node.position = Vector3(x, rng.randf_range(height_range.x, height_range.y),
				rng.randf_range(z_range.x, z_range.y))
		node.rotation.y = rng.randf_range(-0.4, 0.4)
		add_child(node)
		_clouds.append(node)


func _process(delta: float) -> void:
	for c in _clouds:
		c.position.x += speed * delta
		if c.position.x > x_extent:
			c.position.x -= x_extent * 2.0
