shader_type spatial;
// 亚特兰蒂斯的气泡穹顶：几乎透明，边缘（掠射角）泛白和一点彩虹色，表面有缓慢流动的细纹。里外都看得到。

render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec3 tint : source_color = vec3(0.65, 0.92, 1.0);
uniform float alpha_center = 0.03;
uniform float alpha_rim = 0.38;

void fragment() {
	float ndv = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - ndv, 3.0);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float swirl = 0.5 + 0.5 * sin(wn.x * 18.0 + wn.y * 11.0 + TIME * 0.35) * sin(wn.z * 15.0 - TIME * 0.27);
	vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (rim * 1.3 + vec3(0.0, 0.33, 0.67)));
	ALBEDO = mix(tint, rainbow, 0.25 * rim) + vec3(swirl * 0.06);
	ALPHA = clamp(alpha_center + rim * alpha_rim + swirl * 0.02, 0.0, 0.6);
}
