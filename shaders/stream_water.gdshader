shader_type spatial;
// 小溪水面：顺着河床的一条水带。UV.x 横跨水面（0..1），UV.y 沿流向的距离（米）；顶点色 R = 陡度（0 平缓、1 瀑布）。
// 两层程序噪声法线顺流滚动；陡处和石头边泛白沫、流得更快；两岸边缘渐透明，接进河床的砂石里。

render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

global uniform float rain_amount;

uniform vec3 deep_color : source_color = vec3(0.05, 0.16, 0.18);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.30, 0.28);
uniform float flow_speed = 0.9;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float ripples(vec2 uv) {
	return vnoise(uv) * 0.6 + vnoise(uv * 2.3 + 7.1) * 0.3 + vnoise(uv * 5.1 - 3.7) * 0.1;
}

void fragment() {
	float steep = COLOR.r;
	float speed = flow_speed * (1.0 + steep * 3.0);
	vec2 uv_a = vec2(UV.x * 2.2, UV.y * 0.9 - TIME * speed);
	vec2 uv_b = vec2(UV.x * 3.1 + 5.0, UV.y * 1.7 - TIME * speed * 1.35);
	float e = 0.08;
	float h0 = ripples(uv_a) + ripples(uv_b) * 0.5;
	float hx = ripples(uv_a + vec2(e, 0.0)) + ripples(uv_b + vec2(e, 0.0)) * 0.5;
	float hy = ripples(uv_a + vec2(0.0, e)) + ripples(uv_b + vec2(0.0, e)) * 0.5;
	NORMAL_MAP = normalize(vec3((h0 - hx) * 4.0, (h0 - hy) * 4.0, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.9 + rain_amount * 0.6;
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
	// 白沫只在瀑布、急流和石头边缘，平缓处只有零星几条
	float foam = smoothstep(0.78, 0.98, h0 * 0.5 + steep * 0.5 + (1.0 - edge) * 0.12);
	vec3 water = mix(shallow_color, deep_color, edge * 0.8);
	ALBEDO = mix(water, vec3(0.9, 0.94, 0.95), foam);
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(mix(0.55, 0.95, foam) * mix(0.3, 1.0, edge) + steep * 0.25, 0.0, 1.0);
}
