shader_type spatial;
// 流动的水面（亚特兰蒂斯的水渠、喷泉水柱）：沿 UV 的 y 方向滚动的条纹 + 泛光，半透明。

render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec3 deep : source_color = vec3(0.12, 0.55, 0.7);
uniform vec3 foam : source_color = vec3(0.8, 0.97, 1.0);
uniform float speed = 1.6;
uniform float stripes = 6.0;

void fragment() {
	float v = UV.y * stripes - TIME * speed;
	float s = 0.5 + 0.5 * sin(v * 6.2831 + sin(UV.x * 9.0 + TIME) * 1.5);
	float f = smoothstep(0.75, 1.0, s);
	ALBEDO = mix(deep, foam, f * 0.7);
	ALPHA = 0.62 + f * 0.25;
}
