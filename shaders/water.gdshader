shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// Mặt ao low-poly: sóng nhẹ ở đỉnh, mỗi mặt tam giác phẳng (pháp tuyến tính lại
// theo đạo hàm màn hình), màu lấy từ màu đỉnh: giữa ao đậm, mép bờ sáng (viền nước).
// Kênh alpha của màu đỉnh = mức lay sóng (mép bờ = 0 để mặt nước không hở khỏi bờ).
// Không dùng depth texture nên chạy được cả ở renderer Compatibility.

uniform float wave_height = 0.035;
uniform float wave_speed = 0.9;
uniform float wave_scale = 1.1;
uniform float opacity : hint_range(0.0, 1.0) = 0.86;
uniform float shininess : hint_range(0.0, 1.0) = 0.25;
global uniform float weather_rain;    // 0..1, mưa làm mặt nước lăn tăn và sẫm lại

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92),
			lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float wave = sin(w.x * wave_scale + t) + sin(w.z * wave_scale * 1.3 - t * 1.2)
			+ 0.5 * sin((w.x + w.z) * wave_scale * 2.1 + t * 1.7);
	VERTEX.y += wave * 0.4 * wave_height * COLOR.a;
	// Gợn mưa: sóng nhỏ, nhanh, phủ cả mặt ao
	float r = sin(w.x * 7.0 + TIME * 9.0) * sin(w.z * 6.3 - TIME * 8.0);
	VERTEX.y += r * 0.025 * weather_rain * COLOR.a;
}

void fragment() {
	// Pháp tuyến phẳng của từng mặt => mặt nước lấp lánh kiểu low-poly
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = srgb_to_linear(COLOR.rgb) * (1.0 - 0.22 * weather_rain);
	ALPHA = opacity;
	ROUGHNESS = 1.0 - shininess;
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
