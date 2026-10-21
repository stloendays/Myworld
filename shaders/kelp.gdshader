shader_type spatial;
// 海带：竖直的细长条带，越往上摆得越大，像在水流里轻轻摇；双面渲染，越往上颜色越浅、带一点透光。

render_mode cull_disabled, diffuse_burley;

uniform vec3 base_color : source_color = vec3(0.18, 0.32, 0.12);
uniform vec3 tip_color : source_color = vec3(0.45, 0.58, 0.22);
uniform float height = 3.0;
uniform float sway = 0.35;
uniform float phase = 0.0;

varying float h01;

void vertex() {
	h01 = clamp(VERTEX.y / height, 0.0, 1.0);
	float bend = h01 * h01;
	VERTEX.x += sin(TIME * 0.9 + phase + VERTEX.y * 0.8) * sway * bend;
	VERTEX.z += cos(TIME * 0.7 + phase * 1.3 + VERTEX.y * 0.6) * sway * 0.6 * bend;
}

void fragment() {
	ALBEDO = mix(base_color, tip_color, h01);
	ROUGHNESS = 0.6;
	BACKLIGHT = vec3(0.25, 0.35, 0.1) * h01;
}
