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
// Mùa (Seasons đặt): lá xanh ngả dần sang `season_leaf` theo `season_mix`; hoa theo mùa nở theo `season_bloom`.
global uniform vec3 season_leaf;
global uniform float season_mix;
global uniform float season_bloom;
uniform float season_scale = 1.0;     // 0 = không đổi màu theo mùa (lúa — màu do mùa vụ quyết định)
uniform float flower_season = 0.0;    // 1 = mesh có hoa đỏ chỉ nở mùa hạ (phượng); ngoài mùa hoa thành lá

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
	vec3 c = COLOR.rgb;
	// Hoa phượng: ngoài mùa hạ thì chỗ hoa đỏ là lá xanh
	float red = clamp((c.r - max(c.g, c.b)) * 5.0, 0.0, 1.0) * flower_season * (1.0 - season_bloom);
	c = mix(c, vec3(0.36, 0.56, 0.25) * (0.8 + 0.4 * c.r), red);
	// Lá xanh ngả màu theo mùa, giữ độ sáng tối của từng mặt
	float green = clamp((c.g - max(c.r, c.b)) * 7.0, 0.0, 1.0);
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	vec3 target = season_leaf * (lum / max(dot(season_leaf, vec3(0.3, 0.55, 0.15)), 0.05));
	c = mix(c, target, green * season_mix * season_scale);
	ALBEDO = srgb_to_linear(c);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
