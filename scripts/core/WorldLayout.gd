class_name WorldLayout
extends RefCounted
## 世界布局数据（坐标、区域、路径）的唯一读取入口。
## 数据源：res://data/world/world_layout.json。地形、建筑、树木、区域都从这里取坐标，
## 场景脚本里不硬编码位置。约定：单位米，X/Z ∈ [-125, 125]，北 = -Z，Y 向上。

const PATH := "res://data/world/world_layout.json"

static var _data: Dictionary = {}
static var _paths: Array[PackedVector2Array] = []
static var _paths_ready := false


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("WorldLayout: 无法解析 %s" % PATH)
	return _data


## 编辑 JSON 后在编辑器里调用，清空所有缓存。
static func reload() -> void:
	_data = {}
	_paths = []
	_paths_ready = false
	WorldTerrain.reset_cache()


static func section(key: String) -> Dictionary:
	var value: Variant = data().get(key, {})
	if value is Dictionary:
		return value
	return {}


static func v2(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func world_min() -> float:
	return float(section("bounds").get("min", -125.0))


static func world_max() -> float:
	return float(section("bounds").get("max", 125.0))


static func water_level() -> float:
	return float(data().get("water_level", 0.0))


static func zones() -> Array:
	return data().get("zones", [])


static func path_polylines() -> Array[PackedVector2Array]:
	if not _paths_ready:
		_paths = []
		for path in data().get("paths", []):
			var pts := PackedVector2Array()
			for p in path["points"]:
				pts.append(v2(p))
			_paths.append(pts)
		_paths_ready = true
	return _paths


static func path_points(path_id: String) -> PackedVector2Array:
	for path in data().get("paths", []):
		if str(path["id"]) == path_id:
			var pts := PackedVector2Array()
			for p in path["points"]:
				pts.append(v2(p))
			return pts
	return PackedVector2Array()


## 点到任意步道中心线的最短水平距离（米）。
static func distance_to_paths(p: Vector2) -> float:
	var best := INF
	for pts in path_polylines():
		for i in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			best = minf(best, p.distance_to(q))
	return best
