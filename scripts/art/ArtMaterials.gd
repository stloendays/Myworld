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
}

static var _cache: Dictionary = {}


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


static func flat(color: Color, roughness := 0.85, tint_by_instance := false, metallic := 0.0) -> StandardMaterial3D:
	var key := "flat:%s:%s:%s:%s" % [color.to_html(), roughness, tint_by_instance, metallic]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if tint_by_instance:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
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


static func glass() -> StandardMaterial3D:
	if _cache.has("glass"):
		return _cache["glass"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.72, 0.80, 0.12)
	m.roughness = 0.03
	m.metallic_specular = 0.9
	_cache["glass"] = m
	return m


## 自制模型（Blender 导出的木屋、门板）的材质，按材质名查找。
static func named(name: String) -> Material:
	match name:
		"M_RoofSlate":
			return pbr("roof_slates_02", Color(0.50, 0.50, 0.55))
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
			return pbr("weathered_planks", Color(1.0, 0.9, 0.8))
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
			return flat(Color.WHITE, 0.9, true)
		"leafsFall":
			if asset.begins_with("canoe"):
				return flat(Color(0.55, 0.18, 0.11), 0.6)
			return flat(Color.WHITE, 0.9, true)
		"woodBark", "woodBarkDark":
			return pbr("pine_bark", Color(0.62, 0.52, 0.46), "world")
		"woodBirch":
			return flat(Color(0.66, 0.63, 0.58), 0.8)
		"woodInner":
			return flat(Color(0.76, 0.60, 0.42), 0.8)
		"grass":
			var g := flat(Color.WHITE, 0.9, true)
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			return g
		"dirt":
			return pbr("rock_face_03", Color(0.78, 0.75, 0.72), "world")
		"_defaultMat":
			if asset.begins_with("mushroom"):
				return flat(Color(0.90, 0.87, 0.80), 0.8)
			if asset.begins_with("rock"):
				return pbr("rock_face_03", Color(0.62, 0.60, 0.58), "world")
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
