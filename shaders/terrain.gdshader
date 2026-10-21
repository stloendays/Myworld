shader_type spatial;
// 地形五层 PBR 混合：0 草地 · 1 林下落叶 · 2 土路 · 3 岩石（三平面投影）· 4 湖岸泥石。
// 权重来自顶点色：R 落叶、G 土路、B 岩石、A 湖岸，草地 = 1 - 其余之和。
// 法线在世界空间扰动后写回 NORMAL，地形网格不需要切线。
// 季节色调、积雪、湿润度来自全局着色器参数（EnvironmentDirector 每帧写入）。

render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_layers : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray rough_layers : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer_size[5];
uniform vec3 layer_tint[5] : source_color;
uniform float normal_strength = 0.8;
uniform float blend_sharpness = 2.5;
global uniform vec4 season_tint;
global uniform float snow_cover;
global uniform float wetness;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_n(vec3 c) {
	return c * 2.0 - 1.0;
}

// 平面（XZ）采样，做两种尺度混合以减弱重复感
void sample_planar(int layer, float scale_mix, out vec3 alb, out vec3 nrm, out float rgh) {
	float s = 1.0 / layer_size[layer];
	vec3 uv_a = vec3(wpos.xz * s, float(layer));
	vec3 uv_b = vec3(wpos.zx * s * 0.37 + vec2(0.31, 0.17), float(layer));
	alb = mix(texture(albedo_layers, uv_a).rgb, texture(albedo_layers, uv_b).rgb, scale_mix);
	vec3 n = unpack_n(texture(normal_layers, uv_a).rgb);
	nrm = vec3(n.x, 0.0, -n.y);
	rgh = texture(rough_layers, uv_a).r;
}

void sample_triplanar(int layer, out vec3 alb, out vec3 nrm, out float rgh) {
	float s = 1.0 / layer_size[layer];
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 ax = vec3(wpos.zy * s, float(layer));
	vec3 ay = vec3(wpos.xz * s, float(layer));
	vec3 az = vec3(wpos.xy * s, float(layer));
	alb = texture(albedo_layers, ax).rgb * bw.x + texture(albedo_layers, ay).rgb * bw.y + texture(albedo_layers, az).rgb * bw.z;
	vec3 nx = unpack_n(texture(normal_layers, ax).rgb);
	vec3 ny = unpack_n(texture(normal_layers, ay).rgb);
	vec3 nz = unpack_n(texture(normal_layers, az).rgb);
	// 贴图 v 轴向下：绿色通道（法线 +Y）指向世界坐标减小的方向
	nrm = vec3(0.0, -nx.y, nx.x) * bw.x + vec3(ny.x, 0.0, -ny.y) * bw.y + vec3(nz.x, -nz.y, 0.0) * bw.z;
	rgh = texture(rough_layers, ax).r * bw.x + texture(rough_layers, ay).r * bw.y + texture(rough_layers, az).r * bw.z;
}

void fragment() {
	vec4 w = COLOR;
	float ws[5] = float[5](max(0.0, 1.0 - (w.r + w.g + w.b + w.a)), w.r, w.g, w.b, w.a);
	// 用贴图明度做“高度混合”，让交界处呈碎块状而不是平滑渐变
	float total = 0.0;
	vec3 alb = vec3(0.0);
	vec3 nrm = vec3(0.0);
	float rgh = 0.0;
	float scale_mix = 0.35;
	for (int i = 0; i < 5; i++) {
		if (ws[i] < 0.002) {
			continue;
		}
		vec3 a;
		vec3 n;
		float r;
		if (i == 3) {
			sample_triplanar(i, a, n, r);
		} else {
			sample_planar(i, scale_mix, a, n, r);
		}
		float lum = dot(a, vec3(0.333));
		float k = pow(ws[i] * (0.6 + lum), blend_sharpness);
		alb += a * layer_tint[i] * k;
		nrm += n * k;
		rgh += r * k;
		total += k;
	}
	alb /= max(total, 1e-4);
	nrm /= max(total, 1e-4);
	rgh /= max(total, 1e-4);

	alb *= season_tint.rgb;
	vec3 n_world = normalize(wnrm + nrm * normal_strength);
	// 积雪先盖平地，再随覆盖度往坡面扩展；用贴图明度打散边缘
	float snow_edge = mix(0.85, 0.45, snow_cover);
	float snow = smoothstep(snow_edge, snow_edge + 0.15, n_world.y + (dot(alb, vec3(0.333)) - 0.3) * 0.4) * smoothstep(0.0, 0.25, snow_cover);
	alb = mix(alb, vec3(0.92, 0.94, 0.98), snow);
	alb *= mix(1.0, 0.55, wetness * (1.0 - snow));
	rgh = mix(rgh, 0.25, wetness * (1.0 - snow));
	rgh = mix(rgh, 0.6, snow);

	ALBEDO = alb;
	ROUGHNESS = clamp(rgh, 0.05, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
}
