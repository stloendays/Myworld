shader_type spatial;
// 从浮岛边上落进云海的瀑布（也用于岛上流向瀑布的小溪）：沿 UV.y 往下滚的水纹条带，两边渐透明，下端散成水雾。
render_mode cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D streaks : filter_linear_mipmap, repeat_enable;
uniform vec3 water_color : source_color = vec3(0.78, 0.9, 1.0);
uniform float speed = 0.9;
uniform float tiling = 3.0;
uniform float fade_bottom = 0.75;

void fragment() {
	vec2 uv = vec2(UV.x, UV.y * tiling - TIME * speed);
	float s = texture(streaks, vec2(uv.x * 2.0, uv.y)).r;
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	float bottom = 1.0 - smoothstep(fade_bottom, 1.0, UV.y);
	ALBEDO = mix(water_color * 0.85, vec3(1.0), smoothstep(0.55, 0.9, s));
	EMISSION = water_color * 0.15;
	ROUGHNESS = 0.2;
	ALPHA = clamp((0.45 + 0.5 * s) * edge * bottom, 0.0, 1.0);
}
