shader_type spatial;
// 泳池水面（半透明）：从上往下看，浅处清澈、深处偏蓝，能看到池底瓷砖；
// 从水下往上看是一层亮蓝的水面（背面）。微微起伏的法线波纹。

render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.42, 0.82, 0.88);
uniform vec3 deep_color : source_color = vec3(0.04, 0.30, 0.46);
uniform float depth_fade = 3.0;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * 0.12;
	vec3 na = texture(ripple_a, uv + vec2(TIME * 0.02, TIME * 0.013)).rgb;
	vec3 nb = texture(ripple_b, uv * 1.7 - vec2(TIME * 0.016, -TIME * 0.021)).rgb;
	NORMAL_MAP = mix(na, nb, 0.5);
	NORMAL_MAP_DEPTH = 0.25;
	if (FRONT_FACING) {
		float raw = texture(depth_tex, SCREEN_UV).r;
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		view.xyz /= view.w;
		float d = max(0.0, VERTEX.z - view.z);
		float t = clamp(d / depth_fade, 0.0, 1.0);
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		ALBEDO = mix(shallow_color, deep_color, t);
		ALPHA = mix(mix(0.25, 0.8, t), 1.0, fresnel * 0.7);
		ROUGHNESS = 0.04;
		SPECULAR = 0.6;
	} else {
		ALBEDO = vec3(0.55, 0.82, 0.92);
		EMISSION = vec3(0.08, 0.20, 0.26);
		ALPHA = 0.6;
		ROUGHNESS = 0.2;
	}
}
