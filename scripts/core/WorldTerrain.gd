class_name WorldTerrain
extends RefCounted
## 解析式地形高度函数 h(x, z)。网格、碰撞、树木摆放、出生点都调用它，保证彼此一致。
## 组成：基础高度 + 低频噪声 + 细节噪声 + 山丘 → 平台压平 → 湖盆下挖 → 地图边缘陡坡（自然封闭）
## → 建筑地下室基坑（pits：矩形内直接降到坑底，被建筑的首层地坪和地下室墙体完全遮住）。
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


## 地表坡度（|∇h|，1.0 ≈ 45°），用中心差分。
static func slope_at(x: float, z: float) -> float:
	var dx := (height_at(x + 0.5, z) - height_at(x - 0.5, z))
	var dz := (height_at(x, z + 0.5) - height_at(x, z - 0.5))
	return Vector2(dx, dz).length()
