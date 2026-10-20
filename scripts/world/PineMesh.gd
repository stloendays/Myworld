class_name PineMesh
extends RefCounted
## 灰盒阶段的低多边形针叶树（约 9 m 高）：表面 0 = 树干，表面 1 = 四层树冠。
## 树冠颜色由 MultiMesh 实例颜色决定，以后季节系统可按实例批量调色。
## 正式美术阶段用 GLB 树木替换（见 assets/licenses.csv）。

const TIERS := [
	[1.5, 3.4, 2.15],
	[3.2, 3.1, 1.75],
	[4.9, 2.8, 1.35],
	[6.5, 2.7, 0.9],
]

static var _cache: ArrayMesh = null


static func build() -> ArrayMesh:
	if _cache != null:
		return _cache
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshUtil.add_frustum(trunk, Vector3.ZERO, -0.3, 3.0, 0.24, 0.12, 6)
	var mesh := trunk.commit()

	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var phase := 0.0
	for tier in TIERS:
		MeshUtil.add_cone(crown, Vector3.ZERO, float(tier[0]), float(tier[1]), float(tier[2]), 7, phase)
		phase += 0.45
	crown.commit(mesh)

	var trunk_mat := MeshUtil.material(Color(0.30, 0.20, 0.13), 0.9)
	var crown_mat := StandardMaterial3D.new()
	crown_mat.vertex_color_use_as_albedo = true
	crown_mat.vertex_color_is_srgb = true
	crown_mat.roughness = 0.9
	mesh.surface_set_material(0, trunk_mat)
	mesh.surface_set_material(1, crown_mat)
	_cache = mesh
	return mesh
