class_name BlockyMesh
extends RefCounted
## 方块风格模型的公共工具：把“像素盒子”合成网格，提供像素质感材质。人物（CharacterModel）与
## 所有小动物（BlockyModel）共用，保证同一种画风。盒子格式：[x0, y0, z0, x1, y1, z1]（像素）。

static var _materials: Dictionary = {}


## pieces：[{box, color}]；resolve：Callable(color_key: String) -> Color；px：每像素米数。
static func build(pieces: Array, resolve: Callable, px: float, kind := "default") -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece in pieces:
		var b: Array = piece["box"]
		var lo := Vector3(float(b[0]), float(b[1]), float(b[2])) * px
		var hi := Vector3(float(b[3]), float(b[4]), float(b[5])) * px
		add_box(st, lo, hi, resolve.call(str(piece["color"])))
	var mesh := st.commit()
	mesh.surface_set_material(0, material(px, kind))
	return mesh


static func add_box(st: SurfaceTool, lo: Vector3, hi: Vector3, color: Color) -> void:
	var c := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var faces := [
		[[0, 3, 2, 1], Vector3.FORWARD], [[4, 5, 6, 7], Vector3.BACK],
		[[0, 4, 7, 3], Vector3.LEFT], [[1, 2, 6, 5], Vector3.RIGHT],
		[[3, 7, 6, 2], Vector3.UP], [[0, 1, 5, 4], Vector3.DOWN],
	]
	st.set_color(color)
	for f in faces:
		var q: Array = f[0]
		var n: Vector3 = f[1]
		MeshUtil.add_tri(st, c[q[0]], c[q[1]], c[q[2]], n)
		MeshUtil.add_tri(st, c[q[0]], c[q[2]], c[q[3]], n)


## 共用材质：顶点色 × 16×16 像素噪点贴图（最近邻采样，1 个贴图像素 = 1 个模型像素）。
## kind = "glow"：半透明自发光（水母、萤火虫）。
static func material(px: float, kind := "default") -> StandardMaterial3D:
	var key := "%s:%s" % [kind, px]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_texture()
	# 最近邻 + mipmap：近处是清楚的像素块，远处用缩小的贴图，人和动物走远了身上不再闪砂点
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / (16.0 * px)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	if kind == "glow":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission_energy_multiplier = 1.6
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission = Color(1.0, 1.0, 1.0)
		m.albedo_color = Color(1.0, 1.0, 1.0, 0.72)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = m
	return m


static var _noise: ImageTexture = null


static func _noise_texture() -> ImageTexture:
	if _noise == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1717
		for y in 16:
			for x in 16:
				var v := rng.randf_range(0.86, 1.0)
				img.set_pixel(x, y, Color(v, v, v))
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise
