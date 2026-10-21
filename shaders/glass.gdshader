shader_type spatial;
// 木屋玻璃：通透的浅色玻璃 + 下雨时的雨痕（流下的水线与静止水珠），强度来自全局参数 rain_amount。
// 雨痕是窗面自己的效果，室内看出去也能看到“窗上有雨”，而室内本身没有降水粒子。

render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

global uniform float rain_amount;
uniform vec4 tint : source_color = vec4(0.62, 0.72, 0.80, 0.12);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// 玻璃面大致朝 ±X，用世界 (z, y) 作平面坐标
	vec2 p = vec2(world_pos.z + world_pos.x * 0.3, world_pos.y);
	vec2 g = p * vec2(7.0, 1.2);
	float column = floor(g.x);
	float speed = 0.25 + hash(vec2(column, 1.0)) * 0.6;
	float y = fract(g.y + TIME * speed + hash(vec2(column, 7.0)));
	float trail = smoothstep(0.0, 0.04, y) * smoothstep(0.45, 0.06, y);
	float lane = smoothstep(0.10, 0.0, abs(fract(g.x) - 0.5)) * step(0.5, hash(vec2(column, 3.0)));
	vec2 cell = floor(p * 16.0);
	vec2 f = fract(p * 16.0) - 0.5;
	float drop = step(0.82, hash(cell)) * smoothstep(0.22, 0.08, length(f));
	float wet = clamp(trail * lane + drop, 0.0, 1.0) * rain_amount;

	ALBEDO = mix(tint.rgb, vec3(0.80, 0.85, 0.92), wet * 0.5);
	ALPHA = tint.a + wet * 0.28;
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
