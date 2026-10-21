@tool
class_name GroundCoverBuilder
extends Node3D
## 地被层：草丛、灌木、野花、蘑菇、树桩倒木、小石块、湖边睡莲（Kenney Nature Kit，CC0）。
## 按 40 m 区块生成 MultiMesh，并设置可见距离，远处自动不画。
## 分布与地形材质一致：草地上长草和花，林下有蘑菇、树桩，步道和空地中心保持干净。
## 只有树桩和倒木有碰撞。

const GENERATED := "Generated"
const NATURE := "res://assets/imported/kenney/nature/"
const CHUNK := 40.0

const GRASS_COLORS := [Color(0.50, 0.52, 0.22), Color(0.60, 0.55, 0.26), Color(0.44, 0.48, 0.20), Color(0.56, 0.50, 0.24)]
const BUSH_COLORS := [Color(0.30, 0.36, 0.16), Color(0.40, 0.36, 0.17), Color(0.55, 0.36, 0.14)]
const LILY_COLORS := [Color(0.25, 0.38, 0.18), Color(0.30, 0.42, 0.20)]

## where：grass 草地 / forest 林下 / any 任意陆地 / meadow 南部草甸 / shallow 浅水；density 为每平方米个数。
const ITEMS := [
	{"assets": ["grass", "grass_large"], "where": "grass", "density": 0.32, "scale": [2.2, 3.6], "colors": "grass", "view": 70.0},
	{"assets": ["grass_leafs", "grass"], "where": "forest", "density": 0.03, "scale": [2.0, 3.0], "colors": "grass", "view": 60.0},
	{"assets": ["plant_bush", "plant_bushDetailed", "plant_bushLarge", "plant_bushSmall"], "where": "any", "density": 0.008, "scale": [2.5, 4.0], "colors": "bush", "view": 140.0},
	{"assets": ["flower_purpleA", "flower_purpleB", "flower_redA", "flower_redB", "flower_yellowA", "flower_yellowB"], "where": "meadow", "density": 0.35, "scale": [2.6, 3.6], "colors": "grass", "view": 70.0},
	{"assets": ["flower_yellowA", "flower_purpleA"], "where": "grass", "density": 0.006, "scale": [2.6, 3.4], "colors": "grass", "view": 60.0},
	{"assets": ["mushroom_red", "mushroom_redGroup", "mushroom_tan", "mushroom_tanGroup"], "where": "forest", "density": 0.004, "scale": [2.0, 3.0], "colors": "white", "view": 40.0},
	{"assets": ["stump_old", "stump_roundDetailed"], "where": "forest", "density": 0.0012, "scale": [3.0, 4.2], "colors": "white", "view": 160.0, "collide": true},
	{"assets": ["log", "log_large"], "where": "forest", "density": 0.0008, "scale": [3.0, 4.5], "colors": "white", "view": 160.0, "collide": true},
	{"assets": ["rock_smallA", "rock_smallC", "rock_smallE", "rock_smallFlatA", "rock_smallFlatB"], "where": "any", "density": 0.006, "scale": [2.0, 4.0], "colors": "grass", "view": 90.0},
	{"assets": ["lily_large", "lily_small"], "where": "shallow", "density": 0.02, "scale": [3.0, 4.5], "colors": "lily", "view": 120.0},
]

var instance_count := 0
var _collision: StaticBody3D = null


func _ready() -> void:
	add_to_group("seasonal")
	rebuild()


## 换季：草丛、灌木按季节草色重新上色（睡莲、蘑菇等不变）。
func apply_season(season: StringName) -> void:
	var p := ClimateData.season_profile(season)
	var grass := ClimateData.colors(p.get("grass_colors"))
	if grass.is_empty():
		return
	var bush: Array = []
	for c in grass:
		bush.append((c as Color).darkened(0.25))
	var root := get_node_or_null(GENERATED)
	if root == null:
		return
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		match str(mmi.get_meta("palette", "")):
			"grass":
				ForestBuilder.recolor((mmi as MultiMeshInstance3D).multimesh, grass)
			"bush":
				ForestBuilder.recolor((mmi as MultiMeshInstance3D).multimesh, bush)


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = GENERATED
	add_child(root)
	instance_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Vegetation.cfg().get("seed", 1)) + 777
	var mn := WorldLayout.world_min()
	var mx := WorldLayout.world_max()
	var meadow := _meadow()
	if not Engine.is_editor_hint():
		_collision = StaticBody3D.new()
		_collision.name = "CoverCollision"
		_collision.collision_layer = PhysicsLayers.WORLD
		_collision.collision_mask = 0
		root.add_child(_collision)
	var cz := mn
	while cz < mx:
		var cx := mn
		while cx < mx:
			var chunk := Node3D.new()
			chunk.name = "Chunk_%d_%d" % [int(cx), int(cz)]
			root.add_child(chunk)
			for item in ITEMS:
				_fill_chunk(chunk, item, rng, Rect2(cx, cz, CHUNK, CHUNK), meadow)
			cx += CHUNK
		cz += CHUNK


func _meadow() -> Dictionary:
	for r in Vegetation.cfg().get("sparse_regions", []):
		if str(r["zone_id"]) == "south_meadow":
			return {"center": WorldLayout.v2(r["center"]), "radius": float(r["radius"])}
	return {"center": Vector2.ZERO, "radius": 0.0}


func _fill_chunk(chunk: Node3D, item: Dictionary, rng: RandomNumberGenerator, rect: Rect2, meadow: Dictionary) -> void:
	var assets: Array = item["assets"]
	var count := int(rect.get_area() * float(item["density"]))
	var per_asset := {}
	for a in assets:
		per_asset[a] = []
	for i in count:
		var x := rect.position.x + rng.randf() * rect.size.x
		var z := rect.position.y + rng.randf() * rect.size.y
		var asset: String = assets[rng.randi() % assets.size()]
		var s := rng.randf_range(float(item["scale"][0]), float(item["scale"][1]))
		var yaw := rng.randf() * TAU
		var tint := rng.randi()
		var keep := rng.randf()
		var y := 0.0
		var where: String = item["where"]
		if where == "shallow":
			var depth := WorldLayout.water_level() - WorldTerrain.height_at(x, z)
			if depth < 0.25 or depth > 1.4:
				continue
			y = WorldLayout.water_level() + 0.045 * s
		else:
			var w := _suitability(x, z, where, meadow)
			if keep > w:
				continue
			y = WorldTerrain.height_at(x, z) - 0.02
		per_asset[asset].append({"transform": Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, y, z)), "tint": tint})
	for asset in per_asset:
		var entries: Array = per_asset[asset]
		if entries.is_empty():
			continue
		var info := ArtMaterials.kenney_mesh(NATURE + asset + ".glb")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = info["mesh"]
		mm.instance_count = entries.size()
		var palette := _palette(str(item["colors"]))
		for i in entries.size():
			mm.set_instance_transform(i, entries[i]["transform"] * (info["transform"] as Transform3D))
			mm.set_instance_color(i, palette[int(entries[i]["tint"]) % palette.size()])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = asset
		mmi.multimesh = mm
		mmi.set_meta("palette", str(item["colors"]))
		mmi.visibility_range_end = float(item["view"])
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if float(item["view"]) < 100.0:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(mmi)
		instance_count += entries.size()
		if item.get("collide", false) and _collision != null:
			var aabb: AABB = info["aabb"]
			for e in entries:
				var xf: Transform3D = e["transform"]
				var box := BoxShape3D.new()
				box.size = aabb.size * xf.basis.get_scale() * 0.9
				var cs := CollisionShape3D.new()
				cs.shape = box
				cs.transform = Transform3D(xf.basis.orthonormalized(), xf * aabb.get_center())
				_collision.add_child(cs)


## 某处适合放该类地被的概率 [0, 1]。
func _suitability(x: float, z: float, where: String, meadow: Dictionary) -> float:
	var p := Vector2(x, z)
	var h := WorldTerrain.height_at(x, z)
	if h < WorldLayout.water_level() + 0.35:
		return 0.0
	if WorldLayout.distance_to_paths(p) < 1.8 or WorldTerrain.slope_at(x, z) > 0.6 or Vegetation.in_keepout(p):
		return 0.0
	var forest := clampf((Vegetation.base_density(x, z) - 0.3) / 0.35, 0.0, 1.0)
	match where:
		"grass":
			var clear := 0.5 if Vegetation.in_clearing(p) else 1.0
			return (1.0 - forest) * clear
		"forest":
			return forest
		"meadow":
			var r := float(meadow["radius"])
			return 1.0 - smoothstep(r * 0.5, r, p.distance_to(meadow["center"]))
		_:
			return 0.0 if Vegetation.in_clearing(p) else 1.0


func _palette(name: String) -> Array:
	match name:
		"grass":
			return GRASS_COLORS
		"bush":
			return BUSH_COLORS
		"lily":
			return LILY_COLORS
	return [Color.WHITE]
