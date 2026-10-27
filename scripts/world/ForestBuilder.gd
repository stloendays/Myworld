@tool
class_name ForestBuilder
extends Node3D
## 针叶林 + 秋色阔叶树 + 岩石（Kenney Nature Kit，CC0，按本项目配色重新上色）。
## 固定随机种子，结果可复现；每个模型变体按 64 m 方格分块，每块一个 MultiMesh（树冠颜色由实例颜色决定）。
## 分块是为了让视锥剔除、阴影级联剔除、点光源阴影剔除和网格自动 LOD 生效：整张图一个 MultiMesh 时包围盒覆盖全图，
## 每盏带阴影的灯、每级阴影都要把全图的树画一遍（剖析：每帧约 630 万三角形，其中约 420 万来自树木投影）。
## M2 的 SeasonController 可按季节批量改实例颜色或把阔叶树换成 summer 变体。
## 碰撞：每棵树一个树干圆柱，每块大岩石一个盒子。

const GENERATED := "Generated"
const CHUNK := 128.0   ## 分块边长（米）：太小绘制调用变多，太大剔除失效
const NATURE := "res://assets/imported/kenney/nature/"
const BUFFER_META := "instance_buffer"   ## MultiMesh 上 CPU 侧实例数组的 meta 名

## kind = pine / broadleaf；height 为目标树高范围（米）；summer 为 M2 换季时使用的夏季模型。
const TREE_VARIANTS := [
	{"asset": "tree_pineTallA_detailed", "kind": "pine", "weight": 10.0, "height": [10.0, 15.0]},
	{"asset": "tree_pineTallB_detailed", "kind": "pine", "weight": 10.0, "height": [11.0, 17.0]},
	{"asset": "tree_pineTallC_detailed", "kind": "pine", "weight": 10.0, "height": [10.0, 15.0]},
	{"asset": "tree_pineTallD_detailed", "kind": "pine", "weight": 8.0, "height": [12.0, 18.0]},
	{"asset": "tree_pineDefaultA", "kind": "pine", "weight": 7.0, "height": [8.0, 12.0]},
	{"asset": "tree_pineDefaultB", "kind": "pine", "weight": 7.0, "height": [8.0, 12.0]},
	{"asset": "tree_pineRoundA", "kind": "pine", "weight": 5.0, "height": [7.0, 11.0]},
	{"asset": "tree_pineRoundC", "kind": "pine", "weight": 5.0, "height": [7.0, 10.0]},
	{"asset": "tree_pineRoundE", "kind": "pine", "weight": 5.0, "height": [7.0, 10.0]},
	{"asset": "tree_pineSmallA", "kind": "pine", "weight": 3.0, "height": [3.5, 6.0]},
	{"asset": "tree_pineSmallB", "kind": "pine", "weight": 3.0, "height": [3.5, 6.0]},
	{"asset": "tree_pineSmallC", "kind": "pine", "weight": 3.0, "height": [4.0, 6.5]},
	{"asset": "tree_oak_fall", "kind": "broadleaf", "weight": 3.0, "height": [6.0, 9.0], "summer": "tree_oak"},
	{"asset": "tree_default_fall", "kind": "broadleaf", "weight": 3.0, "height": [7.0, 10.0], "summer": "tree_default"},
	{"asset": "tree_detailed_fall", "kind": "broadleaf", "weight": 3.0, "height": [6.0, 9.0], "summer": "tree_detailed"},
	{"asset": "tree_fat_fall", "kind": "broadleaf", "weight": 2.0, "height": [5.0, 7.5], "summer": "tree_fat"},
]

const ROCK_VARIANTS := [
	{"asset": "rock_largeA", "scale": [2.0, 4.0]},
	{"asset": "rock_largeB", "scale": [2.0, 4.0]},
	{"asset": "rock_largeC", "scale": [2.0, 3.5]},
	{"asset": "rock_largeD", "scale": [1.8, 3.2]},
	{"asset": "rock_largeE", "scale": [2.0, 4.0]},
	{"asset": "rock_largeF", "scale": [1.8, 3.2]},
	{"asset": "rock_tallA", "scale": [1.6, 3.0]},
	{"asset": "rock_tallB", "scale": [1.6, 3.0]},
	{"asset": "rock_tallC", "scale": [1.6, 3.0]},
]

const PINE_COLORS := [Color(0.16, 0.26, 0.17), Color(0.13, 0.22, 0.15), Color(0.19, 0.29, 0.18), Color(0.15, 0.25, 0.20)]
const FALL_COLORS := [Color(0.76, 0.44, 0.17), Color(0.78, 0.60, 0.24), Color(0.62, 0.25, 0.14), Color(0.72, 0.50, 0.20)]
const MOSS_COLORS := [Color(0.30, 0.36, 0.16), Color(0.38, 0.40, 0.18)]

## 树林用到的全部模型（含夏季阔叶），给 ArtMaterials.preload_kenney 提前并行读取。
static func asset_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for v in TREE_VARIANTS:
		out.append(NATURE + str(v["asset"]) + ".glb")
		if v.has("summer"):
			out.append(NATURE + str(v["summer"]) + ".glb")
	for v in ROCK_VARIANTS:
		out.append(NATURE + str(v["asset"]) + ".glb")
	return out


var tree_count := 0
var rock_count := 0

var _collision: StaticBody3D = null


func _ready() -> void:
	add_to_group("seasonal")
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = GENERATED
	add_child(root)
	var cfg := Vegetation.cfg()
	var trees := _place_trees(cfg)
	var rocks := _place_rocks(cfg)
	tree_count = 0
	for t in trees.values():
		tree_count += (t as Array).size()
	rock_count = 0
	for r in rocks.values():
		rock_count += (r as Array).size()
	for asset in trees:
		var variant := _variant(asset)
		var tree_cells := _by_cell(trees[asset])
		for key in tree_cells:
			var tree_mmi := _multimesh(asset, tree_cells[key], 400.0)
			tree_mmi.set_meta("cell", key)
			tree_mmi.set_meta("kind", variant.get("kind", "pine"))
			tree_mmi.set_meta("fall_asset", asset)
			tree_mmi.set_meta("summer_asset", variant.get("summer", asset))
			root.add_child(tree_mmi)
	for asset in rocks:
		var rock_cells := _by_cell(rocks[asset])
		for key in rock_cells:
			var rock_mmi := _multimesh(asset, rock_cells[key], 300.0)
			rock_mmi.set_meta("cell", key)
			root.add_child(rock_mmi)
	if not Engine.is_editor_hint():
		_collision = _make_collision(trees, rocks)
		root.add_child(_collision)


var current_season: StringName = &"AUTUMN"


## 换季：针叶树按季节色板重新上色；阔叶树换成该季对应的模型（春夏绿叶 / 秋冬秋叶）并上色。
## 由 EnvironmentDirector 通过 "seasonal" 组调用；只改实例颜色与网格，不重建树木。
func apply_season(season: StringName) -> void:
	var p := ClimateData.season_profile(season)
	if p.is_empty():
		return
	current_season = season
	var pine := ClimateData.colors(p.get("pine_colors"))
	var broad := ClimateData.colors(p.get("broadleaf_colors"))
	var summer := str(p.get("broadleaf_mesh", "fall")) == "summer"
	var root := get_node_or_null(GENERATED)
	if root == null:
		return
	for child in root.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or not mmi.has_meta("kind"):
			continue
		if mmi.get_meta("kind") == "broadleaf":
			var asset: String = mmi.get_meta("summer_asset") if summer else mmi.get_meta("fall_asset")
			mmi.multimesh.mesh = ArtMaterials.kenney_mesh(NATURE + asset + ".glb")["mesh"]
			recolor(mmi.multimesh, broad)
		else:
			recolor(mmi.multimesh, pine)


## 按实例序号稳定地从色板取色（同一棵树每季取同一档颜色）。
## 改的是 fill_instances 留下的 CPU 侧实例数组里的颜色，再一次性整块上传（换季时几万个实例
## 逐个 set_instance_color 会卡一下）；没有这份数组的 MultiMesh 才逐个设置。
static func recolor(mm: MultiMesh, palette: Array) -> void:
	if palette.is_empty():
		return
	if mm.has_meta(BUFFER_META):
		var buf: PackedFloat32Array = mm.get_meta(BUFFER_META)
		for i in mm.instance_count:
			var c: Color = palette[(i * 7919 + 13) % palette.size()]
			var o := i * 16 + 12
			buf[o] = c.r
			buf[o + 1] = c.g
			buf[o + 2] = c.b
			buf[o + 3] = c.a
		mm.set_meta(BUFFER_META, buf)
		mm.buffer = buf
	else:
		for i in mm.instance_count:
			mm.set_instance_color(i, palette[(i * 7919 + 13) % palette.size()])
	# CPU 侧记录首个实例的颜色（无头模式下渲染服务器不保存实例数据，测试与调试读这里）
	mm.set_meta("tint_sample", palette[13 % palette.size()])


func _variant(asset: String) -> Dictionary:
	for v in TREE_VARIANTS:
		if v["asset"] == asset:
			return v
	return {}


## 测试用：临时关闭树木/岩石碰撞，以单独验证地形本身的边界封闭。
func set_collision_enabled(enabled: bool) -> void:
	if _collision != null:
		_collision.collision_layer = PhysicsLayers.WORLD if enabled else 0


## 返回 { asset: [ {transform, color, radius} ] }
func _place_trees(cfg: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 1))
	var spacing := float(cfg.get("min_spacing", 2.6))
	# 树木铺到地形网格边缘（±128 m），让地图外缘的山脊也被林冠覆盖；可活动区仍是 ±125 m
	var mx := WorldTerrain.extent() - 0.5
	var mn := -mx
	var grid := {}
	var result := {}
	for i in int(cfg.get("attempts", 20000)):
		var x := rng.randf_range(mn + 1.0, mx - 1.0)
		var z := rng.randf_range(mn + 1.0, mx - 1.0)
		var roll := rng.randf()
		var pick := rng.randf()
		var kind_roll := rng.randf()
		var size_roll := rng.randf()
		var yaw := rng.randf() * TAU
		var tint_roll := rng.randi()
		if roll > Vegetation.tree_density(x, z):
			continue
		var p := Vector2(x, z)
		if _too_close(grid, p, spacing):
			continue
		_insert(grid, p, spacing)
		var broadleaf_chance := 0.03 + 0.35 * pow(1.0 - Vegetation.base_density(x, z), 2.0)
		var kind := "broadleaf" if kind_roll < broadleaf_chance else "pine"
		var variant := _pick_variant(kind, pick)
		var info := ArtMaterials.kenney_mesh(NATURE + variant["asset"] + ".glb")
		var aabb: AABB = info["aabb"]
		var height := lerpf(float(variant["height"][0]), float(variant["height"][1]), size_roll)
		var s := height / maxf(aabb.size.y, 0.01)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		var palette: Array = FALL_COLORS if kind == "broadleaf" else PINE_COLORS
		var entry := {
			"transform": Transform3D(basis, Vector3(x, WorldTerrain.height_at(x, z) - 0.1, z)),
			"color": palette[tint_roll % palette.size()],
			"radius": 0.22 if height < 6.5 else 0.32,
		}
		var asset: String = variant["asset"]
		if not result.has(asset):
			result[asset] = []
		result[asset].append(entry)
	return result


func _pick_variant(kind: String, roll: float) -> Dictionary:
	var total := 0.0
	for v in TREE_VARIANTS:
		if v["kind"] == kind:
			total += float(v["weight"])
	var acc := 0.0
	for v in TREE_VARIANTS:
		if v["kind"] != kind:
			continue
		acc += float(v["weight"]) / total
		if roll <= acc:
			return v
	return TREE_VARIANTS[0]


func _place_rocks(cfg: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("rock_seed", 2))
	var mn := WorldLayout.world_min()
	var mx := WorldLayout.world_max()
	var result := {}
	var target := int(cfg.get("rock_count", 150))
	var placed := 0
	var tries := 0
	while placed < target and tries < target * 40:
		tries += 1
		var x := rng.randf_range(mn + 4.0, mx - 4.0)
		var z := rng.randf_range(mn + 4.0, mx - 4.0)
		var variant: Dictionary = ROCK_VARIANTS[rng.randi() % ROCK_VARIANTS.size()]
		var s := rng.randf_range(float(variant["scale"][0]), float(variant["scale"][1]))
		var yaw := rng.randf() * TAU
		var tint := rng.randi()
		var p := Vector2(x, z)
		var h := WorldTerrain.height_at(x, z)
		if h < -0.4 or WorldLayout.distance_to_paths(p) < 2.6 or Vegetation.in_clearing(p) or Vegetation.in_keepout(p):
			continue
		var entry := {
			"transform": Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, h - 0.08 * s, z)),
			"color": MOSS_COLORS[tint % MOSS_COLORS.size()],
		}
		var asset: String = variant["asset"]
		if not result.has(asset):
			result[asset] = []
		result[asset].append(entry)
		placed += 1
	# 地图边缘陡坡上的大块岩壁（不可到达，只做视觉）
	var rim := int(cfg.get("rim_rock_count", 90))
	var b0 := float(WorldLayout.section("terrain").get("boundary_start", 108.0))
	for i in rim:
		var side := i % 4
		var t := rng.randf_range(mn, mx)
		var depth := rng.randf_range(b0 + 3.0, mx - 1.0)
		var x := t if side < 2 else (depth if side == 2 else -depth)
		var z := (depth if side == 0 else -depth) if side < 2 else t
		var variant: Dictionary = ROCK_VARIANTS[6 + rng.randi() % 3]
		var s := rng.randf_range(6.0, 13.0)
		var entry := {
			"transform": Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s)),
				Vector3(x, WorldTerrain.height_at(x, z) - 0.6 * s, z)),
			"color": MOSS_COLORS[i % MOSS_COLORS.size()],
			"rim": true,
		}
		var asset: String = variant["asset"]
		if not result.has(asset):
			result[asset] = []
		result[asset].append(entry)
	return result


## 按 CHUNK 方格把实例分组（键 = 方格坐标）。
static func _by_cell(entries: Array) -> Dictionary:
	var cells := {}
	for e in entries:
		var o: Vector3 = (e["transform"] as Transform3D).origin
		var key := Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(e)
	return cells


## 一次性写入 MultiMesh 的全部实例（变换 + 颜色），比逐个 set_instance_* 快得多。
## 格式：每实例 16 个 float = 变换 3 行（basis 行 + origin 分量）+ 颜色 RGBA。
## 这份数组留在 meta 里，换季上色时只改颜色再整块上传（见 recolor）。
static func fill_instances(mm: MultiMesh, xforms: Array[Transform3D], colors: PackedColorArray) -> void:
	mm.instance_count = xforms.size()
	var buf := PackedFloat32Array()
	buf.resize(xforms.size() * 16)
	for i in xforms.size():
		var t := xforms[i]
		var b := t.basis
		var c := colors[i]
		var o := i * 16
		buf[o] = b.x.x
		buf[o + 1] = b.y.x
		buf[o + 2] = b.z.x
		buf[o + 3] = t.origin.x
		buf[o + 4] = b.x.y
		buf[o + 5] = b.y.y
		buf[o + 6] = b.z.y
		buf[o + 7] = t.origin.y
		buf[o + 8] = b.x.z
		buf[o + 9] = b.y.z
		buf[o + 10] = b.z.z
		buf[o + 11] = t.origin.z
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = c.a
	mm.buffer = buf
	mm.set_meta(BUFFER_META, buf)


func _multimesh(asset: String, entries: Array, visible_to: float) -> MultiMeshInstance3D:
	var info := ArtMaterials.kenney_mesh(NATURE + asset + ".glb")
	var local: Transform3D = info["transform"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = info["mesh"]
	var xforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	for e in entries:
		xforms.append((e["transform"] as Transform3D) * local)
		colors.append(e["color"])
	fill_instances(mm, xforms, colors)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = asset
	mmi.multimesh = mm
	mmi.visibility_range_end = visible_to
	return mmi


func _make_collision(trees: Dictionary, rocks: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "ForestCollision"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shapes := {}
	for asset in trees:
		for t in trees[asset]:
			var r := float(t["radius"])
			if not shapes.has(r):
				var cyl := CylinderShape3D.new()
				cyl.radius = r
				cyl.height = 4.0
				shapes[r] = cyl
			var cs := CollisionShape3D.new()
			cs.shape = shapes[r]
			cs.position = (t["transform"] as Transform3D).origin + Vector3(0.0, 2.0, 0.0)
			body.add_child(cs)
	for asset in rocks:
		var aabb: AABB = ArtMaterials.kenney_mesh(NATURE + asset + ".glb")["aabb"]
		for r in rocks[asset]:
			if r.get("rim", false):
				continue
			var xf: Transform3D = r["transform"]
			var size := aabb.size * xf.basis.get_scale() * 0.85
			if size.y < 0.5:
				continue
			var box := BoxShape3D.new()
			box.size = size
			var cs := CollisionShape3D.new()
			cs.shape = box
			cs.transform = Transform3D(xf.basis.orthonormalized(), xf * aabb.get_center())
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
