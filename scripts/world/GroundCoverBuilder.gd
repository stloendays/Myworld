@tool
class_name GroundCoverBuilder
extends Node3D
## 地被层：草丛、灌木、野花、蘑菇、树桩倒木、小石块、湖边睡莲（Kenney Nature Kit，CC0）。
## 按 40 m 区块生成 MultiMesh，并设置可见距离，远处自动不画。草、花、蘑菇在着色器里按每一株离相机的距离慢慢缩小到 0
## （fade），整块只在全部缩没之后才剔除，走动时不会一整块冒出来或抖动淡出；其余地被（灌木、石块、树桩）按可见距离抖动淡出。
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
	{"assets": ["grass", "grass_large"], "where": "grass", "density": 0.32, "scale": [2.2, 3.6], "colors": "grass", "view": 68.0, "fade": [52.0, 68.0]},
	{"assets": ["grass_leafs", "grass"], "where": "forest", "density": 0.03, "scale": [2.0, 3.0], "colors": "grass", "view": 60.0, "fade": [45.0, 60.0]},
	{"assets": ["plant_bush", "plant_bushDetailed", "plant_bushLarge", "plant_bushSmall"], "where": "any", "density": 0.008, "scale": [2.5, 4.0], "colors": "bush", "view": 140.0},
	{"assets": ["flower_purpleA", "flower_purpleB", "flower_redA", "flower_redB", "flower_yellowA", "flower_yellowB"], "where": "meadow", "density": 0.35, "scale": [2.6, 3.6], "colors": "grass", "view": 68.0, "fade": [52.0, 68.0]},
	{"assets": ["flower_yellowA", "flower_purpleA"], "where": "grass", "density": 0.006, "scale": [2.6, 3.4], "colors": "grass", "view": 60.0, "fade": [45.0, 60.0]},
	{"assets": ["mushroom_red", "mushroom_redGroup", "mushroom_tan", "mushroom_tanGroup"], "where": "forest", "density": 0.004, "scale": [2.0, 3.0], "colors": "white", "view": 40.0, "fade": [30.0, 40.0]},
	{"assets": ["stump_old", "stump_roundDetailed"], "where": "forest", "density": 0.0012, "scale": [3.0, 4.2], "colors": "white", "view": 160.0, "collide": true},
	{"assets": ["log", "log_large"], "where": "forest", "density": 0.0008, "scale": [3.0, 4.5], "colors": "white", "view": 160.0, "collide": true},
	{"assets": ["rock_smallA", "rock_smallC", "rock_smallE", "rock_smallFlatA", "rock_smallFlatB"], "where": "any", "density": 0.006, "scale": [2.0, 4.0], "colors": "grass", "view": 130.0},
	{"assets": ["lily_large", "lily_small"], "where": "shallow", "density": 0.02, "scale": [3.0, 4.5], "colors": "lily", "view": 120.0},
]

## 地被用到的全部模型，给 ArtMaterials.preload_kenney 提前并行读取。
static func asset_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for item in ITEMS:
		for a in item["assets"]:
			if not out.has(NATURE + str(a) + ".glb"):
				out.append(NATURE + str(a) + ".glb")
	return out


var instance_count := 0
var _collision: StaticBody3D = null
## 地被只有离镜头这么近的块投影：远处灌木、倒木的影子在画面上只有几个像素，却要在太阳阴影的每一级里各画一遍
const SHADOW_NEAR := 48.0
## 地被单独放在渲染层 6：湖面反射探针重拍时不拍它（草丛灌木的倒影看不出来，却要在 6 个面里各画几百次）
const DETAIL_LAYER := 32
var shadows_allowed := true   ## 画质档位（PerformanceDirector）：低、中画质地被不投影
var _shadow_center := Vector2(INF, INF)
var _shadow_timer := 0.0


func _ready() -> void:
	add_to_group("seasonal")
	add_to_group("ground_cover")
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
			chunk.set_meta("center", Vector2(cx + CHUNK * 0.5, cz + CHUNK * 0.5))
			root.add_child(chunk)
			for item in ITEMS:
				_fill_chunk(chunk, item, rng, Rect2(cx, cz, CHUNK, CHUNK), meadow)
			cx += CHUNK
		cz += CHUNK


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_shadow_timer -= delta
	if _shadow_timer > 0.0:
		return
	_shadow_timer = 0.25
	var cam := get_viewport().get_camera_3d()
	if cam != null and Vector2(cam.global_position.x, cam.global_position.z).distance_to(_shadow_center) > 6.0:
		update_shadows()


## 镜头走动或画质改了以后：SHADOW_NEAR 以内的块里能投影的地被开投影，其余关掉。
func update_shadows() -> void:
	var root := get_node_or_null(GENERATED)
	var cam := get_viewport().get_camera_3d()
	if root == null or cam == null:
		return
	_shadow_center = Vector2(cam.global_position.x, cam.global_position.z)
	var reach := SHADOW_NEAR + CHUNK * 0.71
	for chunk in root.get_children():
		if not chunk.has_meta("center"):
			continue
		var near: bool = shadows_allowed and (chunk.get_meta("center") as Vector2).distance_to(_shadow_center) < reach
		var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for mmi in chunk.get_children():
			if mmi.has_meta("casts") and (mmi as GeometryInstance3D).cast_shadow != mode:
				(mmi as GeometryInstance3D).cast_shadow = mode


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
			if keep > _kind_factor(x, z, where, meadow):
				continue
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
		var fade: Array = item.get("fade", [])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = info["mesh"] if fade.is_empty() else _fading_mesh(asset, info["mesh"], fade)
		var palette := _palette(str(item["colors"]))
		var local: Transform3D = info["transform"]
		var xforms: Array[Transform3D] = []
		var colors := PackedColorArray()
		for e in entries:
			xforms.append((e["transform"] as Transform3D) * local)
			colors.append(palette[int(e["tint"]) % palette.size()])
		ForestBuilder.fill_instances(mm, xforms, colors)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = asset
		mmi.multimesh = mm
		mmi.set_meta("palette", str(item["colors"]))
		mmi.layers = DETAIL_LAYER
		if fade.is_empty():
			mmi.visibility_range_end = float(item["view"])
			mmi.visibility_range_end_margin = 15.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			# 草和花在着色器里逐株缩小到 0；整块只在最远一株也缩没之后才剔除（可见距离按块中心算，加半条对角线）
			mmi.visibility_range_end = float(fade[1]) + CHUNK * 0.75
		# 灌木、倒木、树桩这些看得远的才投影，而且只有离镜头 SHADOW_NEAR 以内的块投影（update_shadows）
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if float(item["view"]) >= 100.0:
			mmi.set_meta("casts", true)
			if Engine.is_editor_hint():
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	# 雪线下方 2 m 以上不长草和花
	if h > float(WorldLayout.section("terrain").get("snowline", 9999.0)) - 2.0:
		return 0.0
	# 便宜的判断在前（坡度要算 4 次地形高度）
	if Vegetation.in_keepout(p) or WorldLayout.distance_to_paths(p) < 1.8 or WorldTerrain.slope_at(x, z) > 0.6:
		return 0.0
	# 小溪河床、裂谷谷底不长草
	if WorldTerrain.channel_distance(x, z) < 0.6:
		return 0.0
	return _kind_factor(x, z, where, meadow)


## 适宜度里只和地被种类有关的那一项（林地密度、草甸距离、空地）。_suitability 的结果要么是 0、要么就是它，
## 所以随机数大于它的点不必再算高度、坡度和步道距离（结果不变，草甸那一项的候选点大多在这里就被淘汰）。
func _kind_factor(x: float, z: float, where: String, meadow: Dictionary) -> float:
	var p := Vector2(x, z)
	match where:
		"grass":
			var forest := clampf((Vegetation.base_density(x, z) - 0.3) / 0.35, 0.0, 1.0)
			var clear := 0.5 if Vegetation.in_clearing(p) else 1.0
			return (1.0 - forest) * clear
		"forest":
			return clampf((Vegetation.base_density(x, z) - 0.3) / 0.35, 0.0, 1.0)
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


## 地被网格的“远处逐株缩小”版本：同一个模型、材质换成 ArtMaterials.cover_fade 的变体（按资源和距离缓存）。
static var _fading: Dictionary = {}


static func _fading_mesh(asset: String, mesh: Mesh, fade: Array) -> Mesh:
	var key := "%s:%s:%s" % [asset, fade[0], fade[1]]
	if _fading.has(key) and is_instance_valid(_fading[key]):
		return _fading[key]
	var m := mesh.duplicate() as Mesh
	for i in m.get_surface_count():
		m.surface_set_material(i, ArtMaterials.cover_fade(m.surface_get_material(i), float(fade[0]), float(fade[1])))
	_fading[key] = m
	return m


## 离开这个世界时清掉（WorldTravel 调用）。
static func clear_cache() -> void:
	_fading.clear()
