shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Gió cho lúa, tre, tán cây: đỉnh càng cao càng lay, gốc đứng yên.
// Pha lấy theo vị trí world nên mỗi khóm/cây lay lệch nhịp nhau.
// Màu lấy từ màu đỉnh (đã nhân màu instance nếu là MultiMesh), giữ flat shading.

uniform float strength = 0.12;        // biên độ (m) ở phần cao nhất
uniform float speed = 1.4;            // tốc độ dao động
uniform vec2 direction = vec2(1.0, 0.35);
uniform float base_height = 0.0;      // dưới độ cao này (toạ độ cục bộ) đứng yên
uniform float sway_height = 1.0;      // khoảng cao để biên độ tăng từ 0 lên tối đa
uniform float gust_scale = 0.08;      // độ rộng của "làn gió" chạy qua cảnh
global uniform float weather_wind;    // hệ số gió theo thời tiết (Weather đặt), 1 = bình thường

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92),
			lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp((VERTEX.y - base_height) / sway_height, 0.0, 1.0);
	h *= h;
	vec2 dir = normalize(direction);
	float along = dot(world.xz, dir);
	float phase = along * gust_scale * 6.2831 + dot(origin.xz, vec2(1.7, 2.3));
	float t = TIME * speed;
	float wave = sin(t + phase) * 0.65 + sin(t * 2.1 + phase * 1.7 + world.x * 0.5) * 0.35;
	// Cơn gió mạnh yếu chậm rãi lan qua cảnh
	float gust = 0.6 + 0.4 * sin(t * 0.23 - along * 0.05);
	// Gió mạnh: lay xa hơn và bị đẩy nghiêng hẳn theo chiều gió
	float w = max(weather_wind, 0.0);
	vec3 offset_world = vec3(dir.x, 0.0, dir.y) * (wave * w + max(w - 1.0, 0.0) * 0.6) * gust * strength * h;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset_world;
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
