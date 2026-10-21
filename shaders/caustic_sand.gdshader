shader_type spatial;
// 水族箱底沙：Poly Haven 沙地贴图（世界坐标平铺）+ 流动焦散光纹（只在朝上的面）。

render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/caustics.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.85);
uniform float tile_m = 2.0;
uniform float caustic_strength = 0.35;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 侧面按法线换投影平面，避免顶视投影在竖直面上拉成条纹
	vec2 uv = (abs(wnrm.y) > 0.5 ? wpos.xz : (abs(wnrm.x) > 0.5 ? wpos.zy : wpos.xy)) / tile_m;
	ALBEDO = texture(albedo_tex, uv).rgb * tint;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = 0.9;
	EMISSION = vec3(0.45, 0.8, 1.0) * caustics(wpos.xz * 1.1, TIME) * caustic_strength * smoothstep(0.5, 0.9, wnrm.y);
}
