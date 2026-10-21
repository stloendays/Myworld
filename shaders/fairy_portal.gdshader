shader_type spatial;
// 仙境传送门的门面：圆形，两种柔和的颜色按螺旋慢慢转，中心发白，边缘渐隐。不受光照（自己就是光）。
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 color_a : source_color = vec4(0.55, 0.88, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.96, 0.62, 1.0, 1.0);
uniform float speed = 0.8;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float swirl = sin(a * 3.0 + r * 9.0 - TIME * speed * 2.5) * 0.5 + 0.5;
	float sparkle = pow(max(0.0, sin(a * 17.0 + TIME * 1.3) * sin(r * 31.0 - TIME * 2.1)), 12.0);
	vec3 c = mix(color_a.rgb, color_b.rgb, swirl);
	c += vec3(1.0) * (pow(1.0 - r, 3.0) * 0.9 + sparkle * 0.6);
	ALBEDO = c;
	ALPHA = smoothstep(1.0, 0.82, r) * (0.55 + 0.3 * swirl);
}
