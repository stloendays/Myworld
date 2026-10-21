shader_type spatial;
// 地下水族馆大厅地面：深色抛光水磨石（细小骨料点）+ 从大缸玻璃透出来的流动水纹光，离玻璃越远越淡。
// glass_z 为大缸玻璃所在的世界 Z，glass_side = -1 表示缸在玻璃的 -Z 一侧（PoolHouse 写入）。

render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/caustics.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.10, 0.13, 0.17);
uniform vec3 chip_color : source_color = vec3(0.30, 0.36, 0.42);
uniform float glass_z = 0.0;
uniform float glass_side = -1.0;
uniform float caustic_reach = 6.0;
uniform float caustic_strength = 0.25;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(wpos.xz * 45.0);
	float chip = step(0.82, hash(cell)) * (0.4 + 0.6 * hash(cell + 7.0));
	ALBEDO = mix(base_color, chip_color, chip * 0.6);
	ROUGHNESS = 0.22 + chip * 0.2;
	SPECULAR = 0.6;
	float d = max(0.0, (wpos.z - glass_z) * -glass_side);
	float fade = 1.0 - smoothstep(0.0, caustic_reach, d);
	EMISSION = vec3(0.25, 0.65, 0.95) * caustics(wpos.xz * 0.8, TIME * 0.8) * fade * caustic_strength;
}
