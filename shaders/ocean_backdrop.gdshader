shader_type spatial;
// 大缸后壁的“深海背景”：上浅下深的海水渐变，远处若隐若现的礁石剪影，叠一层慢慢流动的焦散。
// 自发光为主（像布景灯打亮的背景板），不受地下室灯光影响。

render_mode unshaded, cull_back;

#include "res://shaders/include/caustics.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.02, 0.09, 0.18);
uniform vec3 shallow : source_color = vec3(0.10, 0.42, 0.60);
uniform float y_bottom = -10.0;
uniform float y_top = -4.0;

varying vec3 wpos;

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float a = fract(sin(i * 12.9898) * 43758.5453);
	float b = fract(sin((i + 1.0) * 12.9898) * 43758.5453);
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = clamp((wpos.y - y_bottom) / (y_top - y_bottom), 0.0, 1.0);
	vec3 col = mix(deep, shallow, t * t);
	// 远处礁石剪影：沿水平方向的起伏轮廓
	float along = wpos.x + wpos.z;
	float ridge = y_bottom + 0.8 + noise1(along * 0.35) * 1.6 + noise1(along * 1.3) * 0.4;
	float rock = 1.0 - smoothstep(ridge - 0.05, ridge + 0.05, wpos.y);
	col = mix(col, deep * 0.6, rock * 0.85);
	col += vec3(0.2, 0.5, 0.7) * caustics(vec2(along, wpos.y) * 0.6, TIME * 0.5) * 0.12 * t;
	ALBEDO = col;
}
