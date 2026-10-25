shader_type spatial;
// 云海浮岛脚下的云海：两层缓慢漂移的噪声叠出云团，亮面朝太阳一侧偏暖，暗面偏紫；远处交给雾。
render_mode unshaded, cull_disabled;

uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform vec3 lit_color : source_color = vec3(1.0, 0.86, 0.78);
uniform vec3 shade_color : source_color = vec3(0.66, 0.6, 0.78);
uniform float scale_a = 0.006;
uniform float scale_b = 0.017;
uniform vec2 drift = vec2(0.004, 0.0015);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float a = texture(noise_a, p * scale_a + TIME * drift).r;
	float b = texture(noise_b, p * scale_b - TIME * drift * 1.7).r;
	float n = smoothstep(0.25, 0.85, a * 0.65 + b * 0.35);
	ALBEDO = mix(shade_color, lit_color, n);
}
