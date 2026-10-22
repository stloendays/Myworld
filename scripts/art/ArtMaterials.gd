@tool
class_name ArtMaterials
extends RefCounted
## 正式美术材质库：Poly Haven PBR 贴图（CC0，1k）+ Kenney 模型的材质名重映射。
## - named(name)：木屋 GLB 与门板等自制模型使用的材质（M_ 开头，按 Blender 材质名查找）。
## - for_kenney(asset, material)：把 Kenney 的平涂卡通色改成本项目的风格化写实配色/贴图。
## 贴图尺寸（米）来自 Poly Haven 的 dimensions，保证木板、石板按真实尺度平铺。
## 自制模型的 UV 以米为单位，所以 uv1_scale = 1 / 贴图边长。

const TEX_DIR := "res://assets/imported/textures/"

const SIZE_M := {
	"leafy_grass": 2.0, "forest_leaves_04": 1.5, "rocky_trail": 2.0, "rock_face_03": 2.7,
	"brown_mud_rocks_01": 1.3, "roof_slates_02": 3.0, "brown_planks_05": 1.0, "wood_floor": 1.7,
	"weathered_planks": 2.0, "stained_pine": 0.9, "rough_pine_door": 2.0, "rustic_stone_wall": 1.52,
	"slate_floor": 2.29, "wool_boucle": 0.35, "poly_wool_herringbone": 0.27, "pine_bark": 2.0,
	"floor_tiles_02": 4.0, "concrete_floor_01": 2.0, "damp_beach_sand": 2.0,
}

const SNOW_OVERLAY := preload("res://shaders/snow_overlay.gdshader")
const GLASS_SHADER := preload("res://shaders/glass.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")

static var _cache: Dictionary = {}
static var _snowable: Array[BaseMaterial3D] = []
static var _snow_pass: ShaderMaterial = null
static var _snow_on := false


## 立牌用的羊皮纸面：程序生成（暖米色 + 细噪点纤维 + 四边渐深），带一点自发光，夜里也读得清。
static func parchment() -> StandardMaterial3D:
	if _cache.has("parchment"):
		return _cache["parchment"]
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.035
	var fiber := FastNoiseLite.new()
	fiber.seed = 11
	fiber.frequency = 0.25
	var base := Color(0.95, 0.89, 0.74)
	var edge := Color(0.78, 0.64, 0.44)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n
			var v := (y + 0.5) / n
			var d := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var c := base.lerp(edge, 1.0 - smoothstep(0.0, 0.16, d))
			var k := noise.get_noise_2d(x, y) * 0.05 + fiber.get_noise_2d(x * 0.3, y * 3.0) * 0.025
			img.set_pixel(x, y, Color(c.r + k, c.g + k, c.b + k * 0.8))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.95
	m.emission_enabled = true
	m.emission = Color(0.95, 0.88, 0.72)
	m.emission_energy_multiplier = 0.12
	_cache["parchment"] = m
	return m


## 仙境水晶：半透明、自发光、表面光滑。
static func crystal(color: Color) -> StandardMaterial3D:
	var key := "crystal:" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.72)
	m.roughness = 0.12
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	_cache[key] = m
	return m


static func texture(id: String, map: String) -> Texture2D:
	return load("%s%s/%s_%s_1k.jpg" % [TEX_DIR, id, id, map]) as Texture2D


## PBR 材质。mode："uv"（模型自带米制 UV）、"world"（世界空间三平面投影）、"fit"（UV 0..1 铺满一次）。
static func pbr(id: String, tint := Color.WHITE, mode := "uv", roughness_offset := 0.0) -> StandardMaterial3D:
	var key := "pbr:%s:%s:%s:%s" % [id, tint.to_html(), mode, roughness_offset]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = id
	m.albedo_texture = texture(id, "diff")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = texture(id, "nor_gl")
	m.roughness_texture = texture(id, "rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = clampf(1.0 + roughness_offset, 0.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var size := float(SIZE_M.get(id, 2.0))
	match mode:
		"world":
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_triplanar_sharpness = 4.0
			m.uv1_scale = Vector3.ONE / size
		"fit":
			m.uv1_scale = Vector3.ONE
		_:
			m.uv1_scale = Vector3(1.0 / size, 1.0 / size, 1.0)
	_cache[key] = m
	return m


static func flat(color: Color, roughness := 0.85, tint_by_instance := false, metallic := 0.0, double_sided := false) -> StandardMaterial3D:
	var key := "flat:%s:%s:%s:%s:%s" % [color.to_html(), roughness, tint_by_instance, metallic, double_sided]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if tint_by_instance:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m

static func glow(color: Color, energy: float) -> StandardMaterial3D:
	var key := "glow:%s:%s" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


## 纯色织物：只借用 wool_boucle 的法线与粗糙度表现针织纹理，不用它的格纹底色。
static func fabric(color: Color) -> StandardMaterial3D:
	var key := "fabric:" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := pbr("wool_boucle", Color.WHITE, "world").duplicate() as StandardMaterial3D
	m.albedo_texture = null
	m.albedo_color = color
	_cache[key] = m
	return m


## 木屋玻璃：带雨痕的透明玻璃（glass.gdshader，雨量来自全局参数 rain_amount）。
static func glass() -> ShaderMaterial:
	if _cache.has("glass"):
		return _cache["glass"]
	var m := ShaderMaterial.new()
	m.shader = GLASS_SHADER
	_cache["glass"] = m
	return m


## 植被材质（foliage.gdshader）：tree 树冠大幅慢摆、bush 灌木、grass 草叶（厚雪会埋住）、moss 岩石苔藓（不摆）。
## 积雪、风、湿润都在着色器内处理，所以不挂积雪覆盖层。
static func foliage(kind: String) -> ShaderMaterial:
	var key := "foliage:" + kind
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	match kind:
		"tree":
			m.set_shader_parameter("sway", 0.11)
			m.set_shader_parameter("sway_height", 1.6)
		"bush":
			m.set_shader_parameter("sway", 0.05)
			m.set_shader_parameter("sway_height", 0.35)
		"grass":
			m.set_shader_parameter("sway", 0.12)
			m.set_shader_parameter("sway_height", 0.22)
			m.set_shader_parameter("sink_in_snow", true)
		_:
			m.set_shader_parameter("sway", 0.0)
	_cache[key] = m
	return m


## 室内用的清透玻璃（水族箱、玻璃水管），不带雨痕。
static func clear_glass() -> StandardMaterial3D:
	if _cache.has("clear_glass"):
		return _cache["clear_glass"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.70, 0.86, 0.92, 0.10)
	m.roughness = 0.02
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["clear_glass"] = m
	return m


## 放一件 Kenney 摆件：center 为底面中心（局部坐标，y 为底面高度），yaw 为朝向（度，0 = 正面朝 +Z）。
static func kenney_prop(path: String, center: Vector3, yaw_deg: float, scale: float) -> Node3D:
	var info := kenney_mesh(path)
	var aabb: AABB = info["aabb"]
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3(scale, scale, scale))
	var bottom_center := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	var asset := path.get_file().get_basename()
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.name = asset
	node.transform = Transform3D(basis, center - basis * bottom_center)
	restyle_kenney(node, asset)
	return node


## 标记为室外朝天的材质：下雪积雪时叠加 snow_overlay 覆盖层。
static func snowable(m: Material) -> Material:
	var base := m as BaseMaterial3D
	if base != null and not _snowable.has(base):
		_snowable.append(base)
		if _snow_on:
			base.next_pass = _snow_material()
	return m


## 有积雪时给所有室外材质挂上覆盖层，没有时摘掉（不白白多画一遍）。
static func set_snow_overlay(enabled: bool) -> void:
	_snow_on = enabled
	for m in _snowable:
		m.next_pass = _snow_material() if enabled else null


static func _snow_material() -> ShaderMaterial:
	if _snow_pass == null:
		_snow_pass = ShaderMaterial.new()
		_snow_pass.shader = SNOW_OVERLAY
	return _snow_pass


## 自制模型（Blender 导出的木屋、门板）的材质，按材质名查找。
static func named(name: String) -> Material:
	match name:
		"M_RoofSlate":
			return snowable(pbr("roof_slates_02", Color(0.50, 0.50, 0.55)))
		"M_Lining":
			return pbr("brown_planks_05", Color(1.0, 0.70, 0.44))
		"M_Siding":
			return pbr("brown_planks_05", Color(0.62, 0.40, 0.25))
		"M_Beam":
			return pbr("stained_pine", Color(0.95, 0.72, 0.55))
		"M_Frame":
			return pbr("stained_pine", Color(0.30, 0.22, 0.18))
		"M_Floor":
			return pbr("wood_floor", Color(0.95, 0.85, 0.75))
		"M_Deck":
			return snowable(pbr("weathered_planks", Color(1.0, 0.9, 0.8)))
		"M_Stone":
			return pbr("rustic_stone_wall")
		"M_Hearth":
			return pbr("slate_floor", Color(0.6, 0.6, 0.62))
		"M_Door":
			return pbr("rough_pine_door", Color(0.9, 0.8, 0.72), "fit")
		"M_Glass":
			return glass()
		"M_Metal":
			return flat(Color(0.05, 0.05, 0.05), 0.45, false, 0.7)
		"M_FireGlow":
			return glow(Color(1.0, 0.42, 0.10), 5.0)
		"M_LampGlow":
			return glow(Color(1.0, 0.78, 0.50), 2.2)
		"M_Fabric":
			return fabric(Color(0.80, 0.74, 0.65))
		"M_Rug":
			return pbr("poly_wool_herringbone", Color(0.92, 0.88, 0.80), "world")
		"M_Cushion":
			return fabric(Color(0.58, 0.30, 0.19))
	return flat(Color(0.8, 0.0, 0.8))


## Kenney 模型材质重映射。asset 为模型文件名（不含扩展名），material 为其材质名。
static func for_kenney(asset: String, material: String) -> Material:
	match material:
		# 树冠、草叶：白色底色，实际颜色由 MultiMesh 实例颜色给出（便于季节批量换色）
		"leafsDark", "leafsGreen":
			return foliage("tree" if asset.begins_with("tree") else "bush")
		"leafsFall":
			if asset.begins_with("canoe"):
				return flat(Color(0.55, 0.18, 0.11), 0.6)
			return foliage("tree")
		"woodBark", "woodBarkDark":
			return pbr("pine_bark", Color(0.62, 0.52, 0.46), "world")
		"woodBirch":
			return flat(Color(0.66, 0.63, 0.58), 0.8)
		"woodInner":
			return flat(Color(0.76, 0.60, 0.42), 0.8)
		"grass":
			return foliage("moss" if asset.begins_with("rock") else "grass")
		"dirt":
			return snowable(pbr("rock_face_03", Color(0.78, 0.75, 0.72), "world"))
		"_defaultMat":
			if asset.begins_with("mushroom"):
				return flat(Color(0.90, 0.87, 0.80), 0.8)
			if asset.begins_with("rock"):
				return snowable(pbr("rock_face_03", Color(0.62, 0.60, 0.58), "world"))
			return flat(Color(0.3, 0.26, 0.2), 0.9)
		"colorPurple":
			return flat(Color(0.47, 0.34, 0.64), 0.7)
		"colorRed":
			return flat(Color(0.72, 0.18, 0.15), 0.6)
		"colorYellow":
			return flat(Color(0.88, 0.70, 0.26), 0.7)
		"colorTan":
			return flat(Color(0.78, 0.64, 0.46), 0.8)
		"wood":
			if asset.begins_with("canoe"):
				return pbr("weathered_planks", Color(0.95, 0.8, 0.65), "world")
			return pbr("stained_pine", Color(0.9, 0.68, 0.52), "world")
		"woodDark":
			return pbr("stained_pine", Color(0.45, 0.32, 0.25), "world")
		"carpet":
			if asset.begins_with("rug"):
				return named("M_Rug")
			if asset.begins_with("pillow"):
				return named("M_Cushion")
			return named("M_Fabric")
		"carpetDarker":
			return pbr("poly_wool_herringbone", Color(0.55, 0.42, 0.34), "world")
		"carpetWhite":
			return flat(Color(0.88, 0.85, 0.78), 0.9)
		"plant":
			return flat(Color(0.22, 0.38, 0.18), 0.8)
		"metal":
			return flat(Color(0.12, 0.12, 0.12), 0.45, false, 0.6)
		"metalMedium":
			return flat(Color(0.28, 0.28, 0.28), 0.5, false, 0.5)
		"lamp":
			return named("M_LampGlow")
	return flat(Color(0.5, 0.5, 0.5))


## 在后台线程里提前开始读这些 GLB（Main 进入场景树时调用）。之后 kenney_mesh 里的 load() 会等着用
## 同一个后台任务的结果，几十个模型并行读，不再在主线程上一个接一个读。
static func preload_kenney(paths: PackedStringArray) -> void:
	for path in paths:
		if not _cache.has("mesh:" + path) and ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path, "PackedScene", true)


## 读取 GLB 中的第一个网格（含节点变换），并按材质名重新上色，返回可直接用于 MultiMesh 的网格。
static func kenney_mesh(path: String) -> Dictionary:
	var key := "mesh:" + path
	if _cache.has(key):
		return _cache[key]
	var scene := load(path) as PackedScene
	var root := scene.instantiate()
	var mi := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var xf := mi.transform
	var p := mi.get_parent()
	while p != null and p != root:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	var asset := path.get_file().get_basename()
	var mesh := mi.mesh.duplicate() as Mesh
	for s in mesh.get_surface_count():
		var old := mesh.surface_get_material(s)
		mesh.surface_set_material(s, for_kenney(asset, old.resource_name if old != null else ""))
	var result := {"mesh": mesh, "transform": xf, "aabb": xf * mi.mesh.get_aabb()}
	root.free()
	_cache[key] = result
	return result


## 把场景实例中所有网格表面按 Kenney 规则重新上色（单个摆件用）。
static func restyle_kenney(node: Node, asset: String) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var old := mesh.surface_get_material(s)
			(mi as MeshInstance3D).set_surface_override_material(s, for_kenney(asset, old.resource_name if old != null else ""))


## 把自制 GLB 中的表面按材质名换成材质库里的材质。
static func restyle_named(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var old := mesh.surface_get_material(s)
			if old != null:
				(mi as MeshInstance3D).set_surface_override_material(s, named(old.resource_name))
