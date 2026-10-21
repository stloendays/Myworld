class_name WorldTerrain
extends RefCounted
## 解析式地形高度函数 h(x, z)。网格、碰撞、树木摆放、出生点都调用它，保证彼此一致。
## 组成：基础高度 + 低频噪声 + 细节噪声 + 山丘 → 平台压平 → 湖盆下挖 → 地图边缘陡坡（自然封闭）
## → 建筑地下室基坑（pits：矩形内直接降到坑底，被建筑的首层地坪和地下室墙体完全遮住）。

static var _noise: FastNoiseLite = null
static var _detail: FastNoiseLite = null
static var _cfg: Dictionary = {}
static var _lake: Dictionary = {}


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


## 地形网格的半边长（米）。比可活动区 ±125 m 略大，使采样数为 2^n+1（Jolt 高度场最优）。
static func extent() -> float:
	_ensure()
	return float(_cfg.get("extent", 128.0))


## 湖泊椭圆归一化半径：1.0 约为岸线。
static func lake_radius(x: float, z: float) -> float:
	_ensure()
	var c := WorldLayout.v2(_lake["center"])
	var r := WorldLayout.v2(_lake["radii"])
	return Vector2((x - c.x) / r.x, (z - c.y) / r.y).length()


## 用于地表颜色变化的低频噪声，范围约 [-1, 1]。
static func color_variation(x: float, z: float) -> float:
	_ensure()
	return _noise.get_noise_2d(z * 1.7 + 311.0, x * 1.7 - 97.0)


static func height_at(x: float, z: float) -> float:
	_ensure()
	var p := Vector2(x, z)
	var h := float(_cfg["base_height"])
	h += _noise.get_noise_2d(x, z) * float(_cfg["noise_amplitude"])
	h += _detail.get_noise_2d(x, z) * float(_cfg["detail_amplitude"])
	for hill in _cfg.get("hills", []):
		var sigma := float(hill["sigma"])
		var d2 := p.distance_squared_to(WorldLayout.v2(hill["center"]))
		h += float(hill["height"]) * exp(-d2 / (2.0 * sigma * sigma))
	for pad in _cfg.get("pads", []):
		var radius := float(pad["radius"])
		var d := p.distance_to(WorldLayout.v2(pad["center"]))
		var t := 1.0 - smoothstep(radius, radius + float(pad["blend"]), d)
		h = lerpf(h, float(pad["height"]), t)
	var s := 1.0 - smoothstep(float(_lake["inner"]), float(_lake["outer"]), lake_radius(x, z))
	h = lerpf(h, float(_lake["bed_height"]), s)
	# 湖中小岛：在湖盆之上隆起，顶部比水面高 top 米
	for isl in _lake.get("islands", []):
		var radius := float(isl["radius"])
		var t := 1.0 - smoothstep(radius * 0.45, radius, p.distance_to(WorldLayout.v2(isl["center"])))
		if t > 0.0:
			h = lerpf(h, WorldLayout.water_level() + float(isl["top"]) + _detail.get_noise_2d(x, z) * 0.15, t)
	var b0 := float(_cfg["boundary_start"])
	var b1 := float(_cfg["boundary_end"])
	var tx := maxf(0.0, (absf(x) - b0) / (b1 - b0))
	var tz := maxf(0.0, (absf(z) - b0) / (b1 - b0))
	h += float(_cfg["boundary_height"]) * (tx * tx + tz * tz)
	for pit in _cfg.get("pits", []):
		var r: Array = pit["rect"]
		if x >= float(r[0]) and x <= float(r[2]) and z >= float(r[1]) and z <= float(r[3]):
			return float(pit["floor"])
	return h


## 地表坡度（|∇h|，1.0 ≈ 45°），用中心差分。
static func slope_at(x: float, z: float) -> float:
	var dx := (height_at(x + 0.5, z) - height_at(x - 0.5, z))
	var dz := (height_at(x, z + 0.5) - height_at(x, z - 0.5))
	return Vector2(dx, dz).length()
