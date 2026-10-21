shader_type spatial;
// 泳池马赛克瓷砖（程序生成：小方砖 + 白色砖缝，颜色随机深浅），水面以下叠加流动的焦散光纹。
// water_level 为世界坐标下的水面高度（PoolHouse 写入）。

render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/caustics.gdshaderinc"

uniform vec3 tile_a : source_color = vec3(0.46, 0.78, 0.86);
uniform vec3 tile_b : source_color = vec3(0.30, 0.62, 0.78);
uniform vec3 grout : source_color = vec3(0.86, 0.90, 0.90);
uniform float tile_size = 0.1;
uniform float caustic_strength = 0.3;
uniform float water_level = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = abs(wnrm.y) > 0.5 ? wpos.xz : (abs(wnrm.x) > 0.5 ? wpos.zy : wpos.xy);
	vec2 g = uv / tile_size;
	vec2 f = fract(g);
	float line = 1.0 - step(0.07, f.x) * step(0.07, f.y);
	float h = fract(sin(dot(floor(g), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 tile = mix(tile_a, tile_b, h * 0.7);
	ALBEDO = mix(tile, grout, line);
	ROUGHNESS = mix(0.12, 0.7, line);
	SPECULAR = 0.6;
	float under = step(wpos.y, water_level);
	// 侧壁上的光纹比池底弱
	float c = caustics(wpos.xz * 0.9 + wpos.y * 0.3, TIME) * under * mix(0.45, 1.0, abs(wnrm.y));
	EMISSION = vec3(0.55, 0.85, 1.0) * c * caustic_strength;
}
