class_name Vegetation
extends RefCounted
## 植被分布规则（树木密度、空地、步道走廊），由 world_layout.json → forest 驱动。
## ForestBuilder 用它摆树，TerrainBuilder 用它决定林下落叶地表，GroundCoverBuilder 用它摆草和花，
## 三者因此一致：有树的地方地面是落叶，空地和草甸是草。

static var _cfg: Dictionary = {}
## 解析好的区域（每次调用不再查字典）：中心 + [半径, 系数]
static var _clear_c := PackedVector2Array()
static var _clear_r: PackedFloat64Array = []
static var _region_c := PackedVector2Array()
static var _region: PackedFloat64Array = []
static var _sparse_c := PackedVector2Array()
static var _sparse: PackedFloat64Array = []
static var _keepout: PackedFloat64Array = []
static var _base_d := 0.2
static var _edge_band := 24.0
static var _edge_d := 0.85
static var _world_max := 125.0


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = WorldLayout.section("forest")
		_parse()
	return _cfg


static func _parse() -> void:
	_clear_c = PackedVector2Array()
	_clear_r = PackedFloat64Array()
	for c in _cfg.get("clearings", []):
		_clear_c.append(WorldLayout.v2(c["center"]))
		_clear_r.append(float(c["radius"]))
	_region_c = PackedVector2Array()
	_region = PackedFloat64Array()
	for r in _cfg.get("regions", []):
		_region_c.append(WorldLayout.v2(r["center"]))
		_region.append_array([float(r["radius"]), float(r["density"])])
	_sparse_c = PackedVector2Array()
	_sparse = PackedFloat64Array()
	for r in _cfg.get("sparse_regions", []):
		_sparse_c.append(WorldLayout.v2(r["center"]))
		_sparse.append_array([float(r["radius"]), float(r["factor"])])
	_keepout = PackedFloat64Array()
	for k in WorldLayout.data().get("keepouts", []):
		var r: Array = k["rect"]
		_keepout.append_array([float(r[0]), float(r[1]), float(r[2]), float(r[3])])
	_base_d = float(_cfg.get("base_density", 0.2))
	_edge_band = float(_cfg.get("edge_band", 24.0))
	_edge_d = float(_cfg.get("edge_density", 0.85))
	_world_max = WorldLayout.world_max()


static func reset_cache() -> void:
	_cfg = {}


## 建筑占地（含台基）：树、岩石、草、动物都不进入。
static func in_keepout(p: Vector2) -> bool:
	cfg()
	for i in range(0, _keepout.size(), 4):
		if p.x >= _keepout[i] and p.x <= _keepout[i + 2] and p.y >= _keepout[i + 1] and p.y <= _keepout[i + 3]:
			return true
	return false


static func in_clearing(p: Vector2) -> bool:
	cfg()
	for i in _clear_c.size():
		if p.distance_to(_clear_c[i]) < _clear_r[i]:
			return true
	return false


## 林地基础密度 [0, 1]，不含逐点排除（湖水、空地、步道）。
static func base_density(x: float, z: float) -> float:
	var p := Vector2(x, z)
	cfg()
	var mx := _world_max
	var edge := minf(mx - absf(x), mx - absf(z))
	var d := _base_d
	for i in _region_c.size():
		var radius := _region[i * 2]
		var dist := p.distance_to(_region_c[i])
		d = maxf(d, _region[i * 2 + 1] * (1.0 - smoothstep(radius * 0.6, radius, dist)))
	if edge < _edge_band:
		d = maxf(d, _edge_d)
	for i in _sparse_c.size():
		var radius := _sparse[i * 2]
		var dist := p.distance_to(_sparse_c[i])
		d *= lerpf(_sparse[i * 2 + 1], 1.0, smoothstep(radius * 0.7, radius, dist))
	return d


## 高山系数：低于 limit - 4 m 为 1，到 limit 渐变为 0（树木用林线 treeline，草和花用雪线下方 2 m）。
static func below(limit: float, h: float) -> float:
	return 1.0 - smoothstep(limit - 4.0, limit, h)


static func treeline() -> float:
	return float(cfg().get("treeline", 9999.0))


## 树木摆放密度：在基础密度上排除湖水、空地、步道走廊和可达区域内的陡坡，并稀疏湖岸。
static func tree_density(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var c := cfg()
	var water := WorldLayout.water_level()
	var h := WorldTerrain.height_at(x, z)
	if h < water + 0.6 or in_clearing(p) or in_keepout(p):
		return 0.0
	if WorldLayout.distance_to_paths(p) < float(c.get("path_clearance", 3.0)):
		return 0.0
	var mx := WorldLayout.world_max()
	var edge := minf(mx - absf(x), mx - absf(z))
	var inner_limit := float(WorldLayout.section("terrain").get("boundary_start", 108.0)) - 2.0
	if edge > mx - inner_limit and WorldTerrain.slope_at(x, z) > float(c.get("max_slope", 0.9)):
		return 0.0
	var d := base_density(x, z) * below(treeline(), h)
	if h < water + 1.3:
		d *= float(c.get("shore_thinning", 0.3))
	return d
