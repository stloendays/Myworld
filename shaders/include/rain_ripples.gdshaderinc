// 雨点涟漪：在世界 XZ 平面上按 1 m 网格随机落点，每个落点扩散一圈衰减的波纹。
// 返回法线在 XZ 方向的扰动量（未乘雨量）。湖面、地面水坑共用。

float ripple_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rain_ripple(vec2 p, float time, float density) {
	vec2 cell = floor(p);
	vec2 acc = vec2(0.0);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 c = cell + vec2(float(i), float(j));
			float h = ripple_hash(c);
			if (h > density) {
				continue;
			}
			vec2 center = c + vec2(fract(h * 13.7), fract(h * 71.3));
			float t = fract(time * 0.9 + h * 7.0);
			vec2 d = p - center;
			float r = length(d);
			float ring = t * 0.85;
			float wave = sin((r - ring) * 38.0) * smoothstep(0.16, 0.0, abs(r - ring)) * (1.0 - t);
			acc += (r > 0.001 ? d / r : vec2(0.0)) * wave;
		}
	}
	return acc;
}
