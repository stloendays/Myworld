shader_type spatial;
// 地被里的纯色部件（花瓣、蘑菇伞）：和 StandardMaterial3D 的纯色材质一样，只多一件事——
// 远处逐株缩小消失（实例原点离相机 fade_near → fade_far 米之间从原大缩到 0），和同一株的草叶（foliage.gdshader）同步。

render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness_value = 0.8;
uniform float metallic_value = 0.0;
uniform float fade_near = 50.0;
uniform float fade_far = 65.0;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX *= 1.0 - smoothstep(fade_near, fade_far, distance(origin, CAMERA_POSITION_WORLD));
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
