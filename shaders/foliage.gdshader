shader_type spatial;
// 植被（树冠、草叶、苔藓）：颜色来自 MultiMesh 实例颜色（sRGB），随风摆动、积雪变白、雨后颜色加深。
// 摆幅随顶点在模型里的高度平方增加，树根和草根不动；sink_in_snow 的草在厚雪里被埋住；地被远处逐株缩小消失（fade_near / fade_far）。
// 风力、风向、积雪、湿润度来自全局参数（EnvironmentDirector 写入）。

render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

global uniform float wind_strength;
global uniform vec2 wind_direction;
global uniform float snow_cover;
global uniform float wetness;

uniform float sway = 0.6;           // 风力 1 时顶端的最大位移（米）
uniform float sway_height = 1.5;    // 模型空间里的“顶端高度”
uniform bool sink_in_snow = false;
uniform float roughness_value = 0.9;
// 单独摆放的模型（不是 MultiMesh，没有实例颜色、顶点色是白的）用它给苔藓、叶子上色；MultiMesh 里保持白色不影响实例颜色
uniform vec4 base_tint : source_color = vec4(1.0);
// 地被（草）远处逐株缩小消失：fade_far > 0 时，实例原点离相机 fade_near → fade_far 米之间从原大缩到 0（不再整块抖动淡出）
uniform float fade_near = 0.0;
uniform float fade_far = 0.0;

varying vec3 world_normal;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.5);
	float phase = TIME * 1.7 + dot(origin.xz, vec2(0.37, 0.21));
	float gust = sin(phase) * 0.65 + sin(phase * 2.3 + 1.7) * 0.3;
	float amount = sway * h * h * (0.12 + wind_strength);
	vec3 disp = vec3(wind_direction.x, 0.0, wind_direction.y) * amount * (0.55 + gust * 0.6);
	disp.y = -abs(amount) * 0.15 * (0.5 + 0.5 * gust);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * disp;
	if (sink_in_snow) {
		VERTEX.y *= 1.0 - smoothstep(0.2, 0.9, snow_cover) * 0.92;
	}
	if (fade_far > 0.0) {
		VERTEX *= 1.0 - smoothstep(fade_near, fade_far, distance(origin, CAMERA_POSITION_WORLD));
	}
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo = srgb_to_linear(COLOR.rgb) * base_tint.rgb;
	float snow = smoothstep(0.15, 0.6, world_normal.y) * clamp(snow_cover * 1.5, 0.0, 1.0);
	albedo *= mix(1.0, 0.72, wetness * (1.0 - snow));
	albedo = mix(albedo, vec3(0.86, 0.89, 0.95), snow);
	ALBEDO = albedo;
	ROUGHNESS = mix(roughness_value, 0.45, wetness * (1.0 - snow));
}
