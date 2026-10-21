shader_type sky;
// 风格化天空：天顶—地平线渐变、太阳盘与光晕、月亮、星空、飘动的云。
// 所有参数由 EnvironmentDirector 按时间、季节、天气每帧写入：
//   night 0..1（星星与月光）、overcast 0..1（灰化与压暗）、cloud_coverage（越小云越多）。

uniform vec3 top_color : source_color = vec3(0.18, 0.21, 0.55);
uniform vec3 horizon_color : source_color = vec3(0.93, 0.56, 0.66);
uniform vec3 ground_color : source_color = vec3(0.12, 0.10, 0.18);
uniform float horizon_curve = 0.35;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.72, 0.52);
uniform float sun_disk_deg = 1.6;
uniform float sun_glow = 0.18;
uniform float sun_glow_strength = 1.4;
uniform float sun_visibility = 1.0;
uniform float moon_disk_deg = 1.4;
uniform float night = 0.0;
uniform float overcast = 0.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_softness = 0.22;
uniform float cloud_opacity = 0.75;
uniform float cloud_scale = 0.35;
uniform vec2 cloud_wind = vec2(0.004, 0.0015);
uniform vec3 cloud_lit : source_color = vec3(0.98, 0.70, 0.72);
uniform vec3 cloud_shade : source_color = vec3(0.38, 0.33, 0.55);

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(h, horizon_curve));
	} else {
		col = mix(horizon_color, ground_color, pow(min(-h * 3.0, 1.0), 0.6));
	}

	// 星空：只在晴朗夜晚、地平线以上
	if (h > 0.0 && night > 0.01 && !AT_CUBEMAP_PASS) {
		vec3 cell = floor(d * 220.0);
		float star = step(0.9975, hash(cell));
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + hash(cell + 3.1) * 3.0) + hash(cell) * 30.0);
		col += vec3(0.9, 0.92, 1.0) * star * twinkle * night * (1.0 - overcast) * smoothstep(0.0, 0.25, h);
	}

	float sun_amount = 0.0;
	if (LIGHT0_ENABLED) {
		vec3 sun_dir = normalize(LIGHT0_DIRECTION);
		float ang = acos(clamp(dot(d, sun_dir), -1.0, 1.0));
		float disk_r = radians(sun_disk_deg);
		float disk = 1.0 - smoothstep(disk_r * 0.85, disk_r, ang);
		float glow = exp(-ang / max(sun_glow, 0.001)) * sun_visibility;
		sun_amount = glow;
		col += sun_tint * glow * sun_glow_strength * 0.35;
		if (!AT_CUBEMAP_PASS) {
			col += sun_tint * disk * LIGHT0_ENERGY * 6.0 * sun_visibility;
		}
	}
	if (LIGHT1_ENABLED && !AT_CUBEMAP_PASS) {
		vec3 moon_dir = normalize(LIGHT1_DIRECTION);
		float ang = acos(clamp(dot(d, moon_dir), -1.0, 1.0));
		float disk_r = radians(moon_disk_deg);
		float disk = 1.0 - smoothstep(disk_r * 0.9, disk_r, ang);
		col += vec3(0.85, 0.88, 0.95) * disk * night * (1.0 - overcast * 0.85) * 1.5;
		col += vec3(0.25, 0.30, 0.45) * exp(-ang / 0.08) * night * 0.15;
	}

	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * cloud_scale + TIME * cloud_wind;
		float n = texture(cloud_noise, uv).r * 0.7 + texture(cloud_noise, uv * 2.7 + 0.37).r * 0.3;
		float cov = smoothstep(cloud_coverage, cloud_coverage + cloud_softness, n);
		cov = max(cov, overcast * 0.85);
		cov *= smoothstep(0.0, 0.18, h);
		vec3 cc = mix(cloud_shade, cloud_lit, clamp(sun_amount * 1.6 + 0.25, 0.0, 1.0));
		col = mix(col, cc, cov * cloud_opacity);
	}
	COLOR = col;
}
