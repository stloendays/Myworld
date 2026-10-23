class_name WorldTerrain
extends RefCounted
## 解析式地形高度函数 h(x, z)。网格、碰撞、树木摆放、出生点都调用它，保证彼此一致。
## 组成：基础高度 + 低频噪声 + 细节噪声 + 山丘 → 平台压平 → 湖盆下挖 → 地图边缘陡坡（自然封闭）
## → 建筑地下室基坑（pits：矩形内直接降到坑底，被建筑的首层地坪和地下室墙体完全遮住）
## → 沟槽（channels：小溪河床、裂谷；沿折线下挖，沟底高度在第一次调用时按原地形算好）。
## 布局参数在第一次调用时解析成定长数组（每次调用不再查字典、不再把 JSON 数组转 Vector2），
## 公式和运算顺序与按字典计算完全相同，结果逐位一致；加载时地被、地形网格要调用几十万次。

static var _noise: FastNoiseLite = null
static var _detail: FastNoiseLite = null
static var _cfg: Dictionary = {}
static var _lake: Dictionary = {}

static var _base := 0.0
static var _noise_amp := 0.0
static var _detail_amp := 0.0
static var _b0 := 0.0
static var _b1 := 0.0
static var _boundary_h := 0.0
static var _hill_c := PackedVector2Array()
static var _hill: PackedFloat64Array = []          ## 每座山 [height, sigma]
static var _pad_c := PackedVector2Array()
static var _pad: PackedFloat64Array = []           ## 每个平台 [radius, blend, height]
static var _isl_c := PackedVector2Array()
static var _isl: PackedFloat64Array = []           ## 每座岛 [radius, top]
static var _pit: PackedFloat64Array = []           ## 每个基坑 [x0, z0, x1, z1, floor]
static var _lake_c := Vector2.ZERO
static var _lake_r := Vector2.ONE
static var _lake_inner := 0.0
static var _lake_outer := 1.0
static var _lake_bed := 0.0
static var _water := 0.0
## 沟槽：每条 {id, kind, pts（1 m 一个点的中线）, s（沿线距离）, bed（沟底高度）, water（水面高度，小溪才有）,
## inner（沟底半宽）, outer（沟顶半宽）, wet_end（水面画到第几个点，之后流进湖里）, box（包围盒）}
static var _ch: Array[Dictionary] = []


static func reset_cache() -> void:
	_noise = null
	_detail = null


static func _ensure() -> void:
	if _noise != null:
		return
	_cfg = WorldLayout.section("terrain")
	_lake = WorldLayout.section("lake")
	var seed_value := int(_cfg.get("seed", 1))
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = seed_value
	_noise.frequency = float(_cfg.get("noise_frequency", 0.012))
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.seed = seed_value + 1
	_detail.frequency = float(_cfg.get("detail_frequency", 0.09))
	_detail.fractal_type = FastNoiseLite.FRACTAL_NONE
	_base = float(_cfg["base_height"])
	_noise_amp = float(_cfg["noise_amplitude"])
	_detail_amp = float(_cfg["detail_amplitude"])
	_b0 = float(_cfg["boundary_start"])
	_b1 = float(_cfg["boundary_end"])
	_boundary_h = float(_cfg["boundary_height"])
	_hill_c = PackedVector2Array()
	_hill = PackedFloat64Array()
	for hill in _cfg.get("hills", []):
		_hill_c.append(WorldLayout.v2(hill["center"]))
		_hill.append_array([float(hill["height"]), float(hill["sigma"])])
	_pad_c = PackedVector2Array()
	_pad = PackedFloat64Array()
	for pad in _cfg.get("pads", []):
		_pad_c.append(WorldLayout.v2(pad["center"]))
		_pad.append_array([float(pad["radius"]), float(pad["blend"]), float(pad["height"])])
	_pit = PackedFloat64Array()
	for pit in _cfg.get("pits", []):
		var r: Array = pit["rect"]
		_pit.append_array([float(r[0]), float(r[1]), float(r[2]), float(r[3]), float(pit["floor"])])
	_lake_c = WorldLayout.v2(_lake["center"])
	_lake_r = WorldLayout.v2(_lake["radii"])
	_lake_inner = float(_lake["inner"])
	_lake_outer = float(_lake["outer"])
	_lake_bed = float(_lake["bed_height"])
	_water = WorldLayout.water_level()
	_isl_c = PackedVector2Array()
	_isl = PackedFloat64Array()
	for isl in _lake.get("islands", []):
		_isl_c.append(WorldLayout.v2(isl["center"]))
		_isl.append_array([float(isl["radius"]), float(isl["top"])])
	_build_channels()


## 地形网格的半边长（米）。比可活动区 ±125 m 略大，使采样数为 2^n+1（Jolt 高度场最优）。
static func extent() -> float:
	_ensure()
	return float(_cfg.get("extent", 128.0))


## 湖泊椭圆归一化半径：1.0 约为岸线。
static func lake_radius(x: float, z: float) -> float:
	_ensure()
	return Vector2((x - _lake_c.x) / _lake_r.x, (z - _lake_c.y) / _lake_r.y).length()


## 用于地表颜色变化的低频噪声，范围约 [-1, 1]。
static func color_variation(x: float, z: float) -> float:
	_ensure()
	return _noise.get_noise_2d(z * 1.7 + 311.0, x * 1.7 - 97.0)


static func height_at(x: float, z: float) -> float:
	_ensure()
	for i in range(0, _pit.size(), 5):
		if x >= _pit[i] and x <= _pit[i + 2] and z >= _pit[i + 1] and z <= _pit[i + 3]:
			return _pit[i + 4]
	var h := _raw(x, z)
	for c in _ch:
		if (c["box"] as Rect2).has_point(Vector2(x, z)):
			h = _carve(c, Vector2(x, z), h)
	return h


## 不含基坑、沟槽的地形（沟底高度按它算）。
static func _raw(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _base
	h += _noise.get_noise_2d(x, z) * _noise_amp
	h += _detail.get_noise_2d(x, z) * _detail_amp
	for i in _hill_c.size():
		var sigma := _hill[i * 2 + 1]
		var d2 := p.distance_squared_to(_hill_c[i])
		h += _hill[i * 2] * exp(-d2 / (2.0 * sigma * sigma))
	for i in _pad_c.size():
		var radius := _pad[i * 3]
		var d := p.distance_to(_pad_c[i])
		var t := 1.0 - smoothstep(radius, radius + _pad[i * 3 + 1], d)
		h = lerpf(h, _pad[i * 3 + 2], t)
	var s := 1.0 - smoothstep(_lake_inner, _lake_outer, Vector2((x - _lake_c.x) / _lake_r.x, (z - _lake_c.y) / _lake_r.y).length())
	h = lerpf(h, _lake_bed, s)
	# 湖中小岛：在湖盆之上隆起，顶部比水面高 top 米
	for i in _isl_c.size():
		var radius := _isl[i * 2]
		var t := 1.0 - smoothstep(radius * 0.45, radius, p.distance_to(_isl_c[i]))
		if t > 0.0:
			h = lerpf(h, _water + _isl[i * 2 + 1] + _detail.get_noise_2d(x, z) * 0.15, t)
	var tx := maxf(0.0, (absf(x) - _b0) / (_b1 - _b0))
	var tz := maxf(0.0, (absf(z) - _b0) / (_b1 - _b0))
	h += _boundary_h * (tx * tx + tz * tz)
	return h


## 沟槽下挖：离中线 d 米处的地面压到“沟底 → 原地面”的过渡上（只往下挖，不会垫高）。
## creek（小溪）：沟底宽、两岸缓坡；gorge（裂谷）：沟底窄、两壁近乎垂直。
static func _carve(c: Dictionary, p: Vector2, h: float) -> float:
	var near := _nearest(c, p)
	var d: float = near.x
	var b: float = near.y
	var inner: float = c["inner"]
	var outer: float = c["outer"]
	if d >= outer:
		return h
	var t := smoothstep(inner * (0.55 if c["kind"] == "creek" else 1.0), outer, d)
	return minf(h, lerpf(b, h, t))


## 到中线最近点：Vector2(距离, 该处沟底高度)。
static func _nearest(c: Dictionary, p: Vector2) -> Vector2:
	var pts: PackedVector2Array = c["pts"]
	var bed: PackedFloat64Array = c["bed"]
	var best := INF
	var best_b := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var dd := p.distance_squared_to(a + ab * t)
		if dd < best:
			best = dd
			best_b = lerpf(bed[i], bed[i + 1], t)
	return Vector2(sqrt(best), best_b)


## 解析沟槽：中线每 1 m 取一点，按原地形算沟底（小溪沿流向只降不升，跌水处整体下落 drop 米形成瀑布；
## 裂谷两端 taper 米内渐浅，可以从两头走下去）。
static func _build_channels() -> void:
	_ch.clear()
	for cfg: Dictionary in _cfg.get("channels", []):
		var raw_pts: Array = cfg["points"]
		var pts := PackedVector2Array()
		var s := PackedFloat64Array()
		var acc := 0.0
		for i in raw_pts.size() - 1:
			var a := WorldLayout.v2(raw_pts[i])
			var b := WorldLayout.v2(raw_pts[i + 1])
			var n := maxi(1, int(ceil(a.distance_to(b))))
			for k in n:
				var q := a.lerp(b, float(k) / n)
				if not pts.is_empty():
					acc += pts[pts.size() - 1].distance_to(q)
				pts.append(q)
				s.append(acc)
		var last := WorldLayout.v2(raw_pts[raw_pts.size() - 1])
		acc += pts[pts.size() - 1].distance_to(last)
		pts.append(last)
		s.append(acc)
		var kind := str(cfg.get("kind", "creek"))
		var depth := float(cfg.get("depth", 1.0))
		var bed := PackedFloat64Array()
		bed.resize(pts.size())
		var falls: Array = cfg.get("falls", [])
		var taper := float(cfg.get("taper", 0.0))
		for i in pts.size():
			var raw := _raw(pts[i].x, pts[i].y)
			if kind == "gorge":
				var k := smoothstep(0.0, taper, s[i]) * smoothstep(0.0, taper, acc - s[i])
				bed[i] = raw - depth * k
			else:
				bed[i] = raw - depth
				for f: Array in falls:
					if s[i] >= float(f[0]) and i > 0:
						var j := s.bsearch(float(f[0])) - 1
						bed[i] = minf(bed[i], bed[maxi(j, 0)] - float(f[1]))
				if i > 0:
					bed[i] = minf(bed[i], bed[i - 1])
		var water := PackedFloat64Array()
		var wet_end := pts.size() - 1
		if kind == "creek":
			water.resize(pts.size())
			var wd := float(cfg.get("water_depth", 0.3))
			for i in pts.size():
				water[i] = bed[i] + wd
				if water[i] < _water + 0.05 and wet_end == pts.size() - 1:
					wet_end = i
		var inner := float(cfg.get("inner", 1.5))
		var outer := float(cfg.get("outer", 3.0))
		var box := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			box = box.expand(q)
		box = box.grow(outer + 0.5)
		_ch.append({"id": str(cfg["id"]), "kind": kind, "pts": pts, "s": s, "bed": bed, "water": water,
			"inner": inner, "outer": outer, "wet_end": wet_end, "box": box, "falls": falls})


## 所有沟槽（StreamBuilder 画水面、桥、溪边石头；测试读）。
static func channels() -> Array[Dictionary]:
	_ensure()
	return _ch


## 离最近沟槽的“沟底边缘”多远（负数 = 在沟底里）；附近没有沟槽返回 INF。树、草、动物用它避开河床和裂谷。
static func channel_distance(x: float, z: float, kind := "") -> float:
	_ensure()
	var best := INF
	for c in _ch:
		if (kind == "" or c["kind"] == kind) and (c["box"] as Rect2).has_point(Vector2(x, z)):
			best = minf(best, _nearest(c, Vector2(x, z)).x - float(c["inner"]))
	return best


## 地表坡度（|∇h|，1.0 ≈ 45°），用中心差分。
static func slope_at(x: float, z: float) -> float:
	var dx := (height_at(x + 0.5, z) - height_at(x - 0.5, z))
	var dz := (height_at(x, z + 0.5) - height_at(x, z - 0.5))
	return Vector2(dx, dz).length()
