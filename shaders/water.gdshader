shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// Mặt nước (mục 47): sóng lớn ở đỉnh như cũ; pháp tuyến pha giữa mặt phẳng low-poly và gợn sóng nhỏ mịn
// (`smoothness`), phản chiếu trời mạnh dần khi nhìn xiên (Fresnel), lấp lánh nắng. Màu vẫn lấy từ màu đỉnh:
// giữa ao đậm, mép bờ sáng; alpha màu đỉnh = mức lay sóng (mép bờ = 0 để nước không hở khỏi bờ).
// Không dùng depth texture nên chạy được cả ở renderer Compatibility.

uniform float wave_height = 0.035;
uniform float wave_speed = 0.9;
uniform float wave_scale = 1.1;
uniform float opacity : hint_range(0.0, 1.0) = 0.86;
uniform float shininess : hint_range(0.0, 1.0) = 0.25;
uniform float smoothness : hint_range(0.0, 1.0) = 0.75;     // 0 = mặt phẳng từng tam giác, 1 = gợn mịn
uniform float ripple_strength = 0.16;
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.65;
uniform vec3 sky_tint : source_color = vec3(0.72, 0.82, 0.9);
global uniform float weather_rain;    // 0..1, mưa làm mặt nước lăn tăn và sẫm lại
global uniform float weather_wind;

varying vec3 world_pos;

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
	world_pos = w;
}

// Độ dốc (d/dx, d/dz) của lớp gợn nhỏ: vài con sóng sin chạy chéo nhau, gió to / mưa thì gợn mạnh hơn
vec2 ripple_slope(vec2 p, float t) {
	vec2 g = vec2(0.0);
	g += vec2(0.92, 0.39) * cos(dot(p, vec2(0.92, 0.39)) * 2.3 + t * 1.6) * 1.0;
	g += vec2(-0.45, 0.89) * cos(dot(p, vec2(-0.45, 0.89)) * 3.7 - t * 2.1) * 0.7;
	g += vec2(0.71, -0.70) * cos(dot(p, vec2(0.71, -0.70)) * 6.1 + t * 2.9) * 0.45;
	g += vec2(0.2, 0.98) * cos(dot(p, vec2(0.2, 0.98)) * 11.0 - t * 3.7) * 0.25;
	return g;
}

void fragment() {
	vec3 flat_n = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	float amp = ripple_strength * (0.7 + 0.3 * clamp(weather_wind, 0.0, 2.5) + 1.2 * weather_rain);
	vec2 s = ripple_slope(world_pos.xz, TIME) * amp;
	vec3 smooth_n = normalize((VIEW_MATRIX * vec4(normalize(vec3(-s.x, 1.0, -s.y)), 0.0)).xyz);
	NORMAL = normalize(mix(flat_n, smooth_n, smoothness));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 base = srgb_to_linear(COLOR.rgb) * (1.0 - 0.22 * weather_rain);
	// Nhìn xiên: mặt nước ngả màu trời và đục hơn (phản chiếu); nhìn thẳng xuống: trong, thấy đáy
	ALBEDO = mix(base, srgb_to_linear(sky_tint), fres * reflect_strength * 0.6);
	ALPHA = mix(opacity, 1.0, fres * reflect_strength);
	ROUGHNESS = mix(1.0 - shininess, 0.06, reflect_strength) * (1.0 + 2.0 * weather_rain);
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
