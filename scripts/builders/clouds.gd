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
## Số mây tối đa khi trời phủ kín (Weather đặt `coverage`).
@export_range(0, 40) var max_clouds: int = 24

## 0 = trời quang (chỉ `cloud_count` đám), 1 = phủ kín, mây xám đen.
var coverage: float = 0.0:
	set = set_coverage

var _clouds: Array[Node3D] = []
var _material: StandardMaterial3D
var _speed_mul: float = 1.0


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	for i in max_clouds:
		var mb := MeshBuilder.new(random_seed + i, 0.03)
		var size := rng.randf_range(0.8, 1.25)
		mb.add_blob(Vector3(2.8, 1.2, 2.0) * size, Palette.CLOUD, rng, 0.2)
		for k in rng.randi_range(2, 4):
			var off := Vector3(rng.randf_range(-2.6, 2.6), rng.randf_range(-0.3, 0.5), rng.randf_range(-1.2, 1.2)) * size
			var r := Vector3(rng.randf_range(1.3, 2.0), rng.randf_range(0.8, 1.1), rng.randf_range(1.1, 1.6)) * size
			mb.add_blob(r, Palette.CLOUD, rng, 0.2, Transform3D(Basis(), off))
		var node := mb.commit_instance("Cloud%d" % i, _material)
		if not cast_shadows:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Rải đều theo x để không dồn cục
		var x := lerpf(-x_extent, x_extent, (i + rng.randf_range(0.2, 0.8)) / maxf(max_clouds, 1))
		node.position = Vector3(x, rng.randf_range(height_range.x, height_range.y),
				rng.randf_range(z_range.x, z_range.y))
		node.rotation.y = rng.randf_range(-0.4, 0.4)
		add_child(node)
		_clouds.append(node)
	# Thứ tự hiện thêm mây ngẫu nhiên để mây dày lên đều khắp, không dồn một phía
	for i in range(_clouds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := _clouds[i]
		_clouds[i] = _clouds[j]
		_clouds[j] = tmp
	set_coverage(coverage)


func set_coverage(value: float) -> void:
	coverage = clampf(value, 0.0, 1.0)
	if _material == null:
		return
	var n := roundi(lerpf(cloud_count, max_clouds, coverage))
	for i in _clouds.size():
		_clouds[i].visible = i < n
	_material.albedo_color = Color.WHITE.lerp(Palette.STORM_CLOUD, smoothstep(0.4, 1.0, coverage))
	_speed_mul = 1.0 + 2.0 * smoothstep(0.6, 1.0, coverage)


func _process(delta: float) -> void:
	for c in _clouds:
		c.position.x += speed * _speed_mul * delta
		if c.position.x > x_extent:
			c.position.x -= x_extent * 2.0
