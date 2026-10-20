@tool
class_name TerrainBuilder
extends Node3D
## 生成地形网格与高度场碰撞：257×257 采样、1 m 间距，覆盖 ±128 m（可活动区 ±125 m）。
## 高度来自 WorldTerrain.height_at()，网格与碰撞逐点一致。
## 顶点色按高度/坡度/步道距离区分草地、湖岸、湖底、岩石和土路（季节变色在 M2 接入）。

const GENERATED := "Generated"
const PATH_WIDTH := 1.7

const COLOR_GRASS := Color(0.33, 0.37, 0.18)
const COLOR_DRY_GRASS := Color(0.47, 0.42, 0.22)
const COLOR_SHORE := Color(0.50, 0.42, 0.32)
const COLOR_LAKEBED := Color(0.20, 0.18, 0.15)
const COLOR_ROCK := Color(0.40, 0.38, 0.38)
const COLOR_PATH := Color(0.45, 0.34, 0.23)


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var old := get_node_or_null(GENERATED)
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = GENERATED
	add_child(root)

	var ext := WorldTerrain.extent()
	var n := int(ext * 2.0) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in n:
		var z := -ext + float(iz)
		for ix in n:
			heights[iz * n + ix] = WorldTerrain.height_at(-ext + float(ix), z)

	root.add_child(_make_mesh(heights, n, ext))
	if not Engine.is_editor_hint():
		root.add_child(_make_collision(heights, n))


func _make_mesh(h: PackedFloat32Array, n: int, ext: float) -> MeshInstance3D:
	var path_d := _path_distance_field(n, ext)
	var water := WorldLayout.water_level()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var p := Vector3(-ext + float(ix), h[i], -ext + float(iz))
			var hl := h[iz * n + maxi(ix - 1, 0)]
			var hr := h[iz * n + mini(ix + 1, n - 1)]
			var hd := h[maxi(iz - 1, 0) * n + ix]
			var hu := h[mini(iz + 1, n - 1) * n + ix]
			var nrm := Vector3(hl - hr, 2.0, hd - hu).normalized()
			verts[i] = p
			normals[i] = nrm
			colors[i] = _ground_color(p, nrm, path_d[i], water)

	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = d
			indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	return mi


func _make_collision(h: PackedFloat32Array, n: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = PhysicsLayers.WORLD | PhysicsLayers.TERRAIN
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


func _ground_color(p: Vector3, nrm: Vector3, path_dist: float, water: float) -> Color:
	var v := WorldTerrain.color_variation(p.x, p.z)
	var c := COLOR_GRASS.lerp(COLOR_DRY_GRASS, clampf(0.5 + 0.6 * v, 0.0, 1.0))
	if p.y < water + 0.35:
		c = COLOR_SHORE.lerp(COLOR_LAKEBED, clampf((water + 0.35 - p.y) / 1.5, 0.0, 1.0))
	elif p.y < water + 0.9:
		c = COLOR_SHORE.lerp(c, (p.y - water - 0.35) / 0.55)
	var slope := 1.0 - nrm.y
	if slope > 0.2:
		c = c.lerp(COLOR_ROCK, clampf((slope - 0.2) / 0.15, 0.0, 1.0))
	if path_dist < PATH_WIDTH:
		c = c.lerp(COLOR_PATH, clampf((PATH_WIDTH - path_dist) / 0.6, 0.0, 1.0))
	return c


## 每个网格顶点到最近步道的距离；只在每段步道的包围盒内计算。
func _path_distance_field(n: int, ext: float) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	field.resize(n * n)
	field.fill(999.0)
	var margin := PATH_WIDTH + 1.0
	for pts in WorldLayout.path_polylines():
		for s in range(pts.size() - 1):
			var a := pts[s]
			var b := pts[s + 1]
			var x0 := maxi(int(floor(minf(a.x, b.x) - margin + ext)), 0)
			var x1 := mini(int(ceil(maxf(a.x, b.x) + margin + ext)), n - 1)
			var z0 := maxi(int(floor(minf(a.y, b.y) - margin + ext)), 0)
			var z1 := mini(int(ceil(maxf(a.y, b.y) + margin + ext)), n - 1)
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var p := Vector2(-ext + ix, -ext + iz)
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
					var i := iz * n + ix
					if d < field[i]:
						field[i] = d
	return field
