@tool
class_name TerrainBuilder
extends Node3D
## 生成地形网格与高度场碰撞：257×257 采样、1 m 间距，覆盖 ±128 m（可活动区 ±125 m）。
## 高度来自 WorldTerrain.height_at()，网格与碰撞逐点一致。
## 外观：terrain.gdshader 五层 PBR 混合（草地 / 林下落叶 / 土路 / 岩石 / 湖岸），
## 顶点色写入混合权重：R 落叶、G 土路、B 岩石、A 湖岸。

const GENERATED := "Generated"
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const PATH_WIDTH := 1.6
## 层顺序必须与 terrain.gdshader 一致。
const LAYERS := ["leafy_grass", "forest_leaves_04", "rocky_trail", "rock_face_03", "brown_mud_rocks_01"]
const LAYER_TINTS := [Color(0.92, 0.88, 0.72), Color(0.88, 0.80, 0.72), Color(0.92, 0.86, 0.80), Color(0.80, 0.78, 0.76), Color(0.85, 0.82, 0.78)]

var material: ShaderMaterial = null


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
		root.add_child(_make_occluder(heights, n, ext))


## 遮挡剔除用的粗地形（4 m 间距）：每个顶点取周围 4×4 m 里最低的高度再压低 0.5 m，
## 所以遮挡体永远在真实地面以下，不会把地面上的草、石头误剔；山包后面、地下水族馆四周的东西被挡住时就不画。
func _make_occluder(h: PackedFloat32Array, n: int, ext: float) -> OccluderInstance3D:
	var step := 4
	var m := (n - 1) / step + 1
	var verts := PackedVector3Array()
	for gz in m:
		for gx in m:
			var lowest := INF
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var ix := clampi(gx * step + dx, 0, n - 1)
					var iz := clampi(gz * step + dz, 0, n - 1)
					lowest = minf(lowest, h[iz * n + ix])
			verts.append(Vector3(-ext + float(gx * step), lowest - 0.5, -ext + float(gz * step)))
	var idx := PackedInt32Array()
	for gz in m - 1:
		for gx in m - 1:
			var a := gz * m + gx
			idx.append_array([a, a + 1, a + m, a + 1, a + m + 1, a + m])
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	var oi := OccluderInstance3D.new()
	oi.name = "TerrainOccluder"
	oi.occluder = occ
	return oi


func _make_mesh(h: PackedFloat32Array, n: int, ext: float) -> MeshInstance3D:
	var path_d := _path_distance_field(n, ext)
	var water := WorldLayout.water_level()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var weights := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	weights.resize(n * n)
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
			weights[i] = _blend_weights(p, nrm, path_d[i], water)

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
	arrays[Mesh.ARRAY_COLOR] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	material = _make_material()
	mesh.surface_set_material(0, material)

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	return mi


func _make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("albedo_layers", _layer_array("diff"))
	mat.set_shader_parameter("normal_layers", _layer_array("nor_gl"))
	mat.set_shader_parameter("rough_layers", _layer_array("rough"))
	var sizes := PackedFloat32Array()
	for id in LAYERS:
		sizes.append(float(ArtMaterials.SIZE_M[id]))
	mat.set_shader_parameter("layer_size", sizes)
	var tints := PackedVector3Array()
	for c in LAYER_TINTS:
		tints.append(Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("layer_tint", tints)
	var terrain := WorldLayout.section("terrain")
	mat.set_shader_parameter("snowline", float(terrain.get("snowline", 9999.0)))
	mat.set_shader_parameter("snowline_band", float(terrain.get("snowline_band", 3.0)))
	return mat


## 把五层同类贴图合成一个 Texture2DArray。贴图导入时已是显存压缩格式（BC1 / BC4 / BC5）+ mipmap，
## 五层格式一致就直接用压缩数据（每层约 0.7 MB）；不一致时才统一成 1024² RGBA8 + mipmap 再压缩成 BC。
func _layer_array(map: String) -> Texture2DArray:
	var images: Array[Image] = []
	for id in LAYERS:
		images.append(ArtMaterials.texture(id, map).get_image())
	var uniform := true
	for img in images:
		uniform = uniform and img.is_compressed() and img.has_mipmaps() and img.get_format() == images[0].get_format() \
			and img.get_size() == images[0].get_size()
	if not uniform:
		for i in images.size():
			var img := images[i].duplicate() as Image
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != 1024 or img.get_height() != 1024:
				img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
			img.generate_mipmaps()
			img.compress(Image.COMPRESS_S3TC)
			images[i] = img
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return arr


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


## 顶点混合权重：R 林下落叶、G 土路、B 岩石、A 湖岸；草地为剩余部分。优先级：岩石 > 湖岸 > 土路 > 落叶。
func _blend_weights(p: Vector3, nrm: Vector3, path_dist: float, water: float) -> Color:
	var rock := clampf((1.0 - nrm.y - 0.17) / 0.12, 0.0, 1.0)
	var shore := clampf((water + 0.9 - p.y) / 0.7, 0.0, 1.0)
	var path := clampf((PATH_WIDTH - path_dist) / 0.7, 0.0, 1.0)
	var patch := 0.5 + 0.5 * WorldTerrain.color_variation(p.x, p.z)
	var forest := clampf((Vegetation.base_density(p.x, p.z) - 0.3) / 0.35 + (patch - 0.5) * 0.5, 0.0, 1.0)
	if Vegetation.in_clearing(Vector2(p.x, p.z)):
		forest *= 0.3
	var free := 1.0 - rock
	shore *= free
	free -= shore
	path *= free
	free -= path
	forest *= free
	return Color(forest, path, rock, shore)


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
