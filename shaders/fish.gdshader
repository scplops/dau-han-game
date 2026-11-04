shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Cá (MultiMesh): thân uốn, đuôi ngoe nguẩy theo thời gian; mỗi con một nhịp (INSTANCE_ID).
// Mesh cá hướng +z là đầu, đuôi ở z âm. Màu = màu đỉnh × màu instance (chép đỏ, vàng, trắm…).

uniform float swim_speed = 9.0;
uniform float wiggle = 0.07;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92),
			lessThan(c, vec3(0.04045)));
}

void vertex() {
	float tail = clamp(-VERTEX.z / 0.3, 0.0, 1.0);
	float ph = float(INSTANCE_ID) * 1.73;
	VERTEX.x += sin(TIME * swim_speed + ph - VERTEX.z * 7.0) * wiggle * (0.25 + tail);
}

void fragment() {
	// Pháp tuyến phẳng từng mặt (giữ chất low-poly sau khi thân bị uốn)
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ROUGHNESS = 0.45;
	SPECULAR = 0.45;
}
