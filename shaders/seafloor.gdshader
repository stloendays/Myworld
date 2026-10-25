shader_type spatial;
// 亚特兰蒂斯的海床与城里的地面：沙地贴图（世界坐标平铺，侧面按法线换投影）× 顶点色 + 流动的焦散光纹（只在朝上的面）。
// caustic_strength 由 World04 随时刻调（白天亮、夜里几乎没有）。

render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/caustics.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 3.0;
uniform float caustic_strength = 0.35;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = (abs(wnrm.y) > 0.5 ? wpos.xz : (abs(wnrm.x) > 0.5 ? wpos.zy : wpos.xy)) / tile_m;
	ALBEDO = texture(albedo_tex, uv).rgb * COLOR.rgb;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = 0.9;
	EMISSION = vec3(0.45, 0.85, 1.0) * caustics(wpos.xz * 0.55, TIME * 0.8) * caustic_strength * smoothstep(0.5, 0.9, wnrm.y);
}
