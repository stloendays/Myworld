shader_type spatial;
// 湖面：两层滚动法线噪声做微风波纹；按场景深度渐变颜色与透明度，岸边柔和过渡。
// 天空倒影来自环境辐照（Sky radiance）。不做物理水体模拟。

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.46, 0.38, 0.60);
uniform vec3 deep_color : source_color = vec3(0.10, 0.11, 0.27);
uniform float depth_fade = 2.5;
uniform float edge_fade = 0.5;
uniform float max_alpha = 0.93;
uniform float ripple_scale = 0.045;
uniform float ripple_speed = 0.018;
uniform float ripple_strength = 0.3;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * ripple_scale;
	vec3 na = texture(ripple_a, uv + vec2(TIME * ripple_speed, TIME * ripple_speed * 0.6)).rgb;
	vec3 nb = texture(ripple_b, uv * 1.9 - vec2(TIME * ripple_speed * 0.7, -TIME * ripple_speed)).rgb;
	NORMAL_MAP = mix(na, nb, 0.5);
	NORMAL_MAP_DEPTH = ripple_strength;

	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	view.xyz /= view.w;
	float water_depth = max(0.0, VERTEX.z - view.z);
	float t = clamp(water_depth / depth_fade, 0.0, 1.0);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);

	ALBEDO = mix(shallow_color, deep_color, t);
	ALPHA = clamp(water_depth / edge_fade, 0.0, 1.0) * mix(mix(0.5, max_alpha, t), 1.0, fresnel);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
