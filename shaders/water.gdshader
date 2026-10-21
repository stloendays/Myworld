shader_type spatial;
// 湖面（不透明 + 屏幕空间反射）：两层滚动法线噪声做微风波纹，树林、木屋与天空的倒影由
// 环境的 SSR 提供（只有不透明表面能接收 SSR）。水深由网格顶点色 R 给出（0 = 岸边，1 ≥ 3 m），
// 岸边偏浅、偏浑，湖心偏深。不做物理水体模拟。

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/rain_ripples.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.30, 0.27, 0.30);
uniform vec3 deep_color : source_color = vec3(0.035, 0.045, 0.085);
uniform float ripple_scale = 0.05;
uniform float ripple_speed = 0.015;
uniform float ripple_strength = 0.18;
uniform float roughness_value = 0.02;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
global uniform float rain_amount;

varying vec3 world_pos;
varying float depth01;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth01 = COLOR.r;
}

void fragment() {
	vec2 uv = world_pos.xz * ripple_scale;
	vec3 na = texture(ripple_a, uv + vec2(TIME * ripple_speed, TIME * ripple_speed * 0.6)).rgb;
	vec3 nb = texture(ripple_b, uv * 2.3 - vec2(TIME * ripple_speed * 0.8, -TIME * ripple_speed * 1.1)).rgb;
	NORMAL_MAP = mix(na, nb, 0.5);
	// 下雨时水面更碎、更粗糙（雨点打出的细纹）
	vec3 nc = texture(ripple_b, uv * 9.0 + vec2(TIME * 0.31, -TIME * 0.27)).rgb;
	NORMAL_MAP = normalize(mix(NORMAL_MAP, nc, rain_amount * 0.6));
	if (rain_amount > 0.01) {
		vec2 r = rain_ripple(world_pos.xz * 1.6, TIME, 0.55) * rain_amount;
		NORMAL_MAP = normalize(NORMAL_MAP + vec3(r.x, -r.y, 0.0) * 0.45);
	}
	NORMAL_MAP_DEPTH = ripple_strength * (1.0 + rain_amount * 2.5);
	ALBEDO = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, depth01));
	ROUGHNESS = roughness_value + rain_amount * 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
