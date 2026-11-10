shader_type sky;

// Bầu trời (mục 47): dải màu chân trời → đỉnh trời do DayNight đặt theo giờ, quầng sáng quanh mặt trời, đĩa mặt
// trời / mặt trăng (cùng một đèn — ban đêm đèn là trăng), sao đêm, mây ti mỏng trên cao.
// Không dùng TIME (để bản đồ phản chiếu không phải vẽ lại mỗi khung) — mây trôi bằng `cloud_shift` do script đẩy.

uniform vec3 top_color : source_color = vec3(0.35, 0.55, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.96, 0.9, 0.78);
uniform vec3 ground_color : source_color = vec3(0.6, 0.55, 0.45);
uniform float night : hint_range(0.0, 1.0) = 0.0;       // 0 = ngày, 1 = đêm (hiện sao, đĩa sáng là trăng)
uniform float cover : hint_range(0.0, 1.0) = 0.0;       // độ phủ mây của thời tiết (che mặt trời, sao)
uniform float disk_size : hint_range(0.005, 0.1) = 0.028;
uniform float star_density : hint_range(0.0, 0.05) = 0.012;
uniform float cirrus : hint_range(0.0, 1.0) = 0.35;     // mây ti mỏng
uniform vec2 cloud_shift = vec2(0.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	// Dải màu: chân trời sáng, lên cao đậm dần; dưới chân trời ngả màu đất
	vec3 col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.42));
	if (up < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-up * 5.0, 0.0, 1.0));
	}
	float clear = 1.0 - cover;
	float sd = dot(dir, LIGHT0_DIRECTION);
	vec3 light = LIGHT0_COLOR * clamp(LIGHT0_ENERGY, 0.0, 2.0);
	// Quầng sáng rộng quanh mặt trời / trăng + vệt sáng sát chân trời phía đó
	float halo = pow(max(sd, 0.0), 6.0) * 0.22 + pow(max(sd, 0.0), 48.0) * 0.5;
	float low = 1.0 - clamp(abs(up) * 3.0, 0.0, 1.0);
	col += light * halo * mix(1.0, 0.45, night) * clear * (0.6 + 0.8 * low);
	// Mây ti: vệt mỏng trên cao, nhạt dần về chân trời
	if (up > 0.02) {
		vec2 uv = dir.xz / (up + 0.25) * 1.6 + cloud_shift;
		float c = smoothstep(0.52, 0.86, fbm(uv * vec2(1.0, 2.2)));
		float amt = c * cirrus * smoothstep(0.02, 0.3, up) * mix(1.0, 0.25, night);
		vec3 cloud_col = mix(horizon_color, vec3(1.0), 0.55) + light * 0.12;
		col = mix(col, cloud_col, amt * (0.35 + 0.4 * cover));
	}
	// Sao: chỉ ban đêm, trời quang; mỗi ô một ngôi, sáng tối khác nhau
	if (night > 0.01 && up > 0.0) {
		vec3 p = dir * 140.0;
		vec3 cell = floor(p);
		float h = hash13(cell);
		if (h > 1.0 - star_density) {
			vec3 f = fract(p) - 0.5;
			float d = length(f);
			float b = smoothstep(0.45, 0.0, d) * (0.4 + 0.6 * hash13(cell + 7.0));
			col += vec3(0.9, 0.93, 1.0) * b * night * clear * clear * smoothstep(0.0, 0.25, up) * 1.4;
		}
	}
	// Đĩa mặt trời / mặt trăng
	float ang = acos(clamp(sd, -1.0, 1.0));
	float disk = 1.0 - smoothstep(disk_size * 0.82, disk_size, ang);
	vec3 disk_col = mix(vec3(1.0, 0.93, 0.75) * 2.2, vec3(0.95, 0.96, 1.0) * 1.1, night);
	col = mix(col, disk_col, disk * clear * smoothstep(-0.02, 0.03, LIGHT0_DIRECTION.y));
	COLOR = col;
}
