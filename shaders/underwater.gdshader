shader_type canvas_item;
// 水下画面：轻微晃动的折射、偏蓝绿的色调、四周压暗。相机在 WaterVolume 水面以下时由 UnderwaterOverlay 打开。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.10, 0.46, 0.56);
uniform float strength = 0.5;

void fragment() {
	vec2 uv = SCREEN_UV + vec2(sin(SCREEN_UV.y * 28.0 + TIME * 2.1), cos(SCREEN_UV.x * 24.0 + TIME * 1.7)) * 0.0035;
	vec3 c = textureLod(screen_tex, uv, 0.35).rgb;
	float lum = dot(c, vec3(0.333));
	vec3 water = tint * (0.55 + lum * 1.4);
	c = mix(c, water, strength);
	float vig = smoothstep(1.05, 0.25, length(SCREEN_UV - 0.5));
	COLOR = vec4(c * mix(0.55, 1.0, vig), 1.0);
}
