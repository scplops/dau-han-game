extends Node3D
## Dựng toàn cảnh khi chạy. Bước 1: không khí (trời, sương, ánh sáng) + nền cỏ phẳng.
## Các builder chi tiết (địa hình, nhà, tre...) sẽ được gọi từ đây ở các bước sau.

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D

@export_group("Nền")
@export var ground_size: float = 240.0

@export_group("Không khí")
@export_range(0.0, 2.0) var sun_energy: float = 1.1
@export_range(0.0, 2.0) var ambient_energy: float = 0.45
@export_range(0.0, 0.05, 0.0005) var fog_density: float = 0.0035


func _ready() -> void:
	_apply_atmosphere()
	_build_ground()


## Gán màu từ Palette cho trời, sương, ánh sáng môi trường và mặt trời.
func _apply_atmosphere() -> void:
	if world_environment != null:
		var env := world_environment.environment
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat != null:
			sky_mat.sky_top_color = Palette.SKY_TOP
			sky_mat.sky_horizon_color = Palette.SKY
			sky_mat.ground_horizon_color = Palette.SKY
			sky_mat.ground_bottom_color = Palette.MOUNTAIN_DARK
		env.ambient_light_color = Palette.AMBIENT
		env.ambient_light_energy = ambient_energy
		env.fog_light_color = Palette.FOG
		env.fog_density = fog_density
	if sun != null:
		sun.light_color = Palette.SUN
		sun.light_energy = sun_energy


## Mặt phẳng cỏ tạm thời (bước 3 sẽ thay bằng địa hình thật).
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.GRASS
	mat.roughness = 1.0
	mat.metallic = 0.0
	plane.material = mat
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	add_child(ground)
