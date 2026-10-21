shader_type spatial;
// 积雪覆盖层：作为室外材质的 next_pass 叠在原表面上，只盖朝上的面（屋顶、树冠、岩石顶、码头）。
// 覆盖度来自全局参数 snow_cover；没有积雪时 ArtMaterials 会把 next_pass 摘掉，不额外绘制。

render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

global uniform float snow_cover;
uniform float coverage_bias = 0.0;

varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float up = smoothstep(0.25, 0.7, world_normal.y);
	float grain = hash(floor(world_pos.xz * 6.0)) * 0.25;
	float a = up * clamp(snow_cover * 1.5 + coverage_bias - grain, 0.0, 1.0);
	ALBEDO = vec3(0.90, 0.93, 0.98);
	ROUGHNESS = 0.75;
	ALPHA = a;
}
