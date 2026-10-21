class_name Vegetation
extends RefCounted
## 植被分布规则（树木密度、空地、步道走廊），由 world_layout.json → forest 驱动。
## ForestBuilder 用它摆树，TerrainBuilder 用它决定林下落叶地表，GroundCoverBuilder 用它摆草和花，
## 三者因此一致：有树的地方地面是落叶，空地和草甸是草。

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = WorldLayout.section("forest")
	return _cfg


static func reset_cache() -> void:
	_cfg = {}


## 建筑占地（含台基）：树、岩石、草、动物都不进入。
static func in_keepout(p: Vector2) -> bool:
	for k in WorldLayout.data().get("keepouts", []):
		var r: Array = k["rect"]
		if p.x >= float(r[0]) and p.x <= float(r[2]) and p.y >= float(r[1]) and p.y <= float(r[3]):
			return true
	return false


static func in_clearing(p: Vector2) -> bool:
	for c in cfg().get("clearings", []):
		if p.distance_to(WorldLayout.v2(c["center"])) < float(c["radius"]):
			return true
	return false


## 林地基础密度 [0, 1]，不含逐点排除（湖水、空地、步道）。
static func base_density(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var c := cfg()
	var mx := WorldLayout.world_max()
	var edge := minf(mx - absf(x), mx - absf(z))
	var d := float(c.get("base_density", 0.2))
	for r in c.get("regions", []):
		var radius := float(r["radius"])
		var dist := p.distance_to(WorldLayout.v2(r["center"]))
		d = maxf(d, float(r["density"]) * (1.0 - smoothstep(radius * 0.6, radius, dist)))
	if edge < float(c.get("edge_band", 24.0)):
		d = maxf(d, float(c.get("edge_density", 0.85)))
	for r in c.get("sparse_regions", []):
		var radius := float(r["radius"])
		var dist := p.distance_to(WorldLayout.v2(r["center"]))
		d *= lerpf(float(r["factor"]), 1.0, smoothstep(radius * 0.7, radius, dist))
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
