// 水下焦散：两层移动的 Voronoi 边缘叠加，得到池底/沙底上流动的光纹（0..1）。

vec2 caustic_hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float caustic_layer(vec2 p, float time) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 o = vec2(float(i), float(j));
			vec2 h = caustic_hash2(cell + o);
			vec2 pt = o + 0.5 + 0.45 * sin(time * 0.8 + 6.2831 * h);
			float d = length(pt - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float e = smoothstep(0.22, 0.0, d2 - d1);
	return e * e;
}

float caustics(vec2 p, float time) {
	return clamp(caustic_layer(p * 1.3, time) * 0.65 + caustic_layer(p * 2.1 + 3.7, time * 1.3) * 0.5, 0.0, 1.0);
}
