@tool
class_name ForestBuilder
extends Node3D
## 按 world_layout.json 的 forest 配置用固定随机种子摆放针叶林和岩石（结果可复现）。
## 渲染：MultiMesh（树一套、岩石一套）；碰撞：每棵树一个树干圆柱，较大岩石一个球。
## 避让：湖水、步道走廊、木屋/湖岸/观景点空地；边缘带加密以自然封闭地图。

const GENERATED := "Generated"

var tree_count := 0
var rock_count := 0

var _cfg: Dictionary = {}
var _trunk_body: StaticBody3D = null


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = GENERATED
	add_child(root)
	_cfg = WorldLayout.section("forest")
	var trees := _place_trees()
	var rocks := _place_rocks()
	tree_count = trees.size()
	rock_count = rocks.size()
	root.add_child(_tree_multimesh(trees))
	root.add_child(_rock_multimesh(rocks))
	if not Engine.is_editor_hint():
		_trunk_body = _make_collision(trees, rocks)
		root.add_child(_trunk_body)


## 测试用：临时关闭树木/岩石碰撞，以单独验证地形本身的边界封闭。
func set_collision_enabled(enabled: bool) -> void:
	if _trunk_body != null:
		_trunk_body.collision_layer = PhysicsLayers.WORLD if enabled else 0


func _place_trees() -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_cfg.get("seed", 1))
	var spacing := float(_cfg.get("min_spacing", 2.6))
	var mn := WorldLayout.world_min()
	var mx := WorldLayout.world_max()
	var grid := {}
	var result: Array[Transform3D] = []
	for i in int(_cfg.get("attempts", 20000)):
		var x := rng.randf_range(mn + 1.0, mx - 1.0)
		var z := rng.randf_range(mn + 1.0, mx - 1.0)
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(0.7, 1.35)
		var stretch := rng.randf_range(0.9, 1.15)
		if roll > _tree_density(x, z):
			continue
		var p := Vector2(x, z)
		if _too_close(grid, p, spacing):
			continue
		_insert(grid, p, spacing)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * stretch, s))
		result.append(Transform3D(basis, Vector3(x, WorldTerrain.height_at(x, z), z)))
	return result


func _tree_density(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var water := WorldLayout.water_level()
	var h := WorldTerrain.height_at(x, z)
	if h < water + 0.6:
		return 0.0
	for c in _cfg.get("clearings", []):
		if p.distance_to(WorldLayout.v2(c["center"])) < float(c["radius"]):
			return 0.0
	if WorldLayout.distance_to_paths(p) < float(_cfg.get("path_clearance", 3.0)):
		return 0.0
	var mx := WorldLayout.world_max()
	var edge := minf(mx - absf(x), mx - absf(z))
	var inner_limit := float(WorldLayout.section("terrain").get("boundary_start", 108.0)) - 2.0
	if edge > mx - inner_limit and WorldTerrain.slope_at(x, z) > float(_cfg.get("max_slope", 0.9)):
		return 0.0
	var d := float(_cfg.get("base_density", 0.2))
	for r in _cfg.get("regions", []):
		var radius := float(r["radius"])
		var dist := p.distance_to(WorldLayout.v2(r["center"]))
		d = maxf(d, float(r["density"]) * (1.0 - smoothstep(radius * 0.6, radius, dist)))
	if edge < float(_cfg.get("edge_band", 24.0)):
		d = maxf(d, float(_cfg.get("edge_density", 0.85)))
	for r in _cfg.get("sparse_regions", []):
		var radius := float(r["radius"])
		var dist := p.distance_to(WorldLayout.v2(r["center"]))
		d *= lerpf(float(r["factor"]), 1.0, smoothstep(radius * 0.7, radius, dist))
	if h < water + 1.3:
		d *= float(_cfg.get("shore_thinning", 0.3))
	return d


func _place_rocks() -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_cfg.get("rock_seed", 2))
	var mn := WorldLayout.world_min()
	var mx := WorldLayout.world_max()
	var result: Array[Transform3D] = []
	var target := int(_cfg.get("rock_count", 150))
	var tries := 0
	while result.size() < target and tries < target * 40:
		tries += 1
		var x := rng.randf_range(mn + 4.0, mx - 4.0)
		var z := rng.randf_range(mn + 4.0, mx - 4.0)
		var s := rng.randf_range(0.35, 1.5)
		var flat := rng.randf_range(0.45, 0.8)
		var yaw := rng.randf() * TAU
		var p := Vector2(x, z)
		var h := WorldTerrain.height_at(x, z)
		if h < -0.4 or WorldLayout.distance_to_paths(p) < 2.6:
			continue
		var blocked := false
		for c in _cfg.get("clearings", []):
			if p.distance_to(WorldLayout.v2(c["center"])) < float(c["radius"]):
				blocked = true
		if blocked:
			continue
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s * rng.randf_range(0.8, 1.3), s * flat, s))
		result.append(Transform3D(basis, Vector3(x, h - 0.12 * s, z)))
	return result


func _tree_multimesh(trees: Array[Transform3D]) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_cfg.get("seed", 1)) + 17
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PineMesh.build()
	mm.instance_count = trees.size()
	for i in trees.size():
		mm.set_instance_transform(i, trees[i])
		var shade := rng.randf()
		mm.set_instance_color(i, Color(0.11, 0.20, 0.15).lerp(Color(0.19, 0.30, 0.19), shade))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Pines"
	mmi.multimesh = mm
	return mmi


func _rock_multimesh(rocks: Array[Transform3D]) -> MultiMeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 4
	sphere.material = MeshUtil.material(Color(0.42, 0.40, 0.40), 0.95)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = rocks.size()
	for i in rocks.size():
		mm.set_instance_transform(i, rocks[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rocks"
	mmi.multimesh = mm
	return mmi


func _make_collision(trees: Array[Transform3D], rocks: Array[Transform3D]) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "ForestCollision"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.3
	trunk.height = 4.0
	for t in trees:
		var cs := CollisionShape3D.new()
		cs.shape = trunk
		cs.position = t.origin + Vector3(0.0, 2.0, 0.0)
		body.add_child(cs)
	for r in rocks:
		var sx := r.basis.get_scale()
		if minf(sx.x, sx.z) < 0.6:
			continue
		var sphere := SphereShape3D.new()
		sphere.radius = 0.45 * minf(sx.x, sx.z)
		var cs := CollisionShape3D.new()
		cs.shape = sphere
		cs.position = r.origin
		body.add_child(cs)
	return body


func _too_close(grid: Dictionary, p: Vector2, r: float) -> bool:
	var cell := Vector2i(floori(p.x / r), floori(p.y / r))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := cell + Vector2i(dx, dz)
			if grid.has(key):
				for q in grid[key]:
					if p.distance_to(q) < r:
						return true
	return false


func _insert(grid: Dictionary, p: Vector2, r: float) -> void:
	var key := Vector2i(floori(p.x / r), floori(p.y / r))
	if not grid.has(key):
		grid[key] = []
	grid[key].append(p)
