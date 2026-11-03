class_name StaticBatch
extends RefCounted
## 静态合批：建好世界以后，把不会动的小网格按材质合成少数几个网格。
## 每个 MeshInstance3D 在主画面和太阳阴影的每一级里各要一次绘制调用；木屋、泳池馆、石头小屋、小溪、码头、
## 卷轴的木架都是几百个小方块拼的，合并以后同一格子里同一种材质只画一次，画面不变。
##
## 哪些能并：普通的 MeshInstance3D（没有脚本、没有子节点、不在任何组里、可见、没有叠加材质和蒙皮），
## 材质是不透明（或 alpha 剪裁）的标准材质，不是公告板、不按物体空间做三平面贴图、不按物体距离淡出，
## 而且没有被任何脚本变量引用（门板、灯泡、卷轴杆这类运行时要动、要换材质的部件都存在脚本变量里）。
## 并到哪：从网格往上找最近一个“单位”——有脚本的节点、被脚本变量引用的节点、或者合批根。
## 合成的网格就挂在这个单位下面，所以脚本整体移动、隐藏、删掉这个单位时，合成的网格跟着一起。
## 同一单位里再按 CELL 米的空间格子分开，保留视锥剔除的粒度；投影、可见层、可见距离不同的分开。
##
## 看不见的不画（2026-11 联机与流畅度）：
##   · 按大小分档：最长边不到 0.7 m 的小摆件（杯子、书、栏杆小柱）离镜头 DETAIL_FINE 米外不画，
##     不到 2 m 的（椅子、桌子、木箱）DETAIL_SMALL 米外不画（都带淡出）；大件（墙、屋顶、地板）不受影响。
##     屋里的家具、码头的小零件在远处只有几个像素，却要占主画面和阴影各一次绘制调用。
##   · 遮挡体（只给 occluder_units 里的建筑本体，它们从不移动：会动的东西做遮挡体，引擎每帧都要重建遮挡结构，
##     一条漂着的独木舟就让 CPU 占用翻了十倍）：并进来的不透明大块面（墙、地板、屋顶、楼板，最长边 ≥ 2 m 且第二长边 ≥ 1 m）的三角形
##     同时做成这个单位的遮挡体（OccluderInstance3D）。站在屋外看不见屋里的家具，进了屋看不见墙外的树林、
##     地被和别的房子，引擎的遮挡剔除就不提交它们。窗洞、门洞本来就没有三角形，透过去看得见的照常画。

const CELL := 24.0
const BATCH_PREFIX := "StaticBatch_"
const OCCLUDER_NAME := "StaticOccluder"
const SKIP := 2   ## referenced 里的这个值：整棵子树都不碰（玩家、小动物、树林这种）
const DETAIL_FINE := 55.0
const DETAIL_SMALL := 110.0
const DETAIL_MARGIN := 6.0
const OCCLUDER_MIN := Vector2(2.0, 1.0)   ## 最长边、第二长边（米）


## 合并 roots 里每棵子树的静态网格；skip 里的节点整棵子树不碰；occluder_units 里的单位（建筑本体）顺便生成遮挡体。返回 {"meshes": 并掉的网格数, "batches": 合成的网格数}。
static func merge_all(tree: SceneTree, roots: Array, skip: Array = [], occluder_units: Array = []) -> Dictionary:
	var referenced := _referenced_nodes(tree)
	for n in skip:
		if n is Node and is_instance_valid(n):
			referenced[(n as Node).get_instance_id()] = SKIP
	var stats := {"meshes": 0, "batches": 0, "detail": 0, "occluders": 0, "occluder_tris": 0}
	for root in roots:
		if root is Node3D and is_instance_valid(root):
			var s := merge(root as Node3D, referenced, occluder_units)
			for k in stats:
				stats[k] += int(s.get(k, 0))
	return stats


## 按大小分档的可见距离（0 = 不限）：只给没设过可见距离的部件。
static func detail_range(longest: float) -> float:
	if longest < 0.7:
		return DETAIL_FINE
	if longest < 2.0:
		return DETAIL_SMALL
	return 0.0


## 这个部件能不能当遮挡体：完全不透明、正面剔除（双面的薄片多半是叶子、布）、够大块。
static func occludes(m: MeshInstance3D, extents: Vector3) -> bool:
	var e := [extents.x, extents.y, extents.z]
	e.sort()
	if float(e[2]) < OCCLUDER_MIN.x or float(e[1]) < OCCLUDER_MIN.y:
		return false
	if (m.layers & 1) == 0:
		return false   # 不在主画面层（反射专用、第一人称手臂……）
	for si in m.mesh.get_surface_count():
		var b := _material(m, si) as BaseMaterial3D
		if b != null and (b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.cull_mode != BaseMaterial3D.CULL_BACK):
			return false
	return true


static func merge(root: Node3D, referenced: Dictionary, occluder_units: Array = []) -> Dictionary:
	var groups := {}
	var members := {}
	var occluders := {}   ## 单位 id -> {"unit": Node3D, "parts": [[arrays, global_transform], ...]}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		if not _eligible(m, referenced):
			continue
		var unit := _unit(m, root, referenced)
		if unit == null:
			continue
		var xf := unit.global_transform.affine_inverse() * m.global_transform
		var center := xf * m.get_aabb().get_center()
		var cell := Vector3i(floori(center.x / CELL), floori(center.y / CELL), floori(center.z / CELL))
		var extents := (m.global_transform * m.get_aabb()).size
		var detail := detail_range(maxf(extents.x, maxf(extents.y, extents.z))) if m.visibility_range_end <= 0.0 else 0.0
		var occ := occluder_units.has(unit) and occludes(m, extents)
		if occ:
			var uid := unit.get_instance_id()
			if not occluders.has(uid):
				occluders[uid] = {"unit": unit, "parts": []}
		for si in m.mesh.get_surface_count():
			var mat := _material(m, si)
			var arrays := m.mesh.surface_get_arrays(si)
			if occ:
				occluders[unit.get_instance_id()]["parts"].append([arrays, m.global_transform])
			var k := str([unit.get_instance_id(), cell, mat.get_instance_id() if mat != null else 0, m.cast_shadow, m.layers,
				m.visibility_range_begin, m.visibility_range_end, m.visibility_range_begin_margin, m.visibility_range_end_margin,
				m.visibility_range_fade_mode, m.ignore_occlusion_culling, m.extra_cull_margin, _signature(arrays), detail])
			if not groups.has(k):
				groups[k] = {"holder": m.get_parent(), "material": mat, "template": m, "parts": [], "detail": detail}
			groups[k]["parts"].append([arrays, m.global_transform])
			groups[k]["holder"] = _common_ancestor(groups[k]["holder"], m.get_parent())
		members[m.get_instance_id()] = m
	# 合格的网格整块并进去（多材质的网格每个面进各自的组），原件删掉，每个面都恰好画一次
	var batches := 0
	var detail_batches := 0
	for k in groups:
		var g: Dictionary = groups[k]
		var t := g["template"] as MeshInstance3D
		# 挂在这一组成员最近的共同父节点下面（脚本按名字删掉 Generated 之类的容器重建时，合成的网格跟着一起删）
		var holder := g["holder"] as Node3D
		var to_holder := holder.global_transform.affine_inverse()
		for part in g["parts"]:
			part[1] = to_holder * (part[1] as Transform3D)
		var mi := MeshInstance3D.new()
		mi.name = BATCH_PREFIX + str(batches)
		mi.mesh = _build_mesh(g["parts"], g["material"])
		mi.cast_shadow = t.cast_shadow
		mi.layers = t.layers
		mi.visibility_range_begin = t.visibility_range_begin
		mi.visibility_range_end = t.visibility_range_end
		mi.visibility_range_begin_margin = t.visibility_range_begin_margin
		mi.visibility_range_end_margin = t.visibility_range_end_margin
		mi.visibility_range_fade_mode = t.visibility_range_fade_mode
		mi.ignore_occlusion_culling = t.ignore_occlusion_culling
		mi.extra_cull_margin = t.extra_cull_margin
		if float(g["detail"]) > 0.0:
			mi.visibility_range_end = g["detail"]
			mi.visibility_range_end_margin = DETAIL_MARGIN
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			detail_batches += 1
		holder.add_child(mi)
		batches += 1
	var occluder_tris := 0
	for uid in occluders:
		occluder_tris += _build_occluder(occluders[uid]["unit"], occluders[uid]["parts"])
	for id in members:
		var m := members[id] as MeshInstance3D
		m.get_parent().remove_child(m)
		m.queue_free()
	return {"meshes": members.size(), "batches": batches, "detail": detail_batches, "occluders": occluders.size(), "occluder_tris": occluder_tris}


## 把一个单位里能挡视线的大块面做成一个遮挡体，挂在单位下面（单位移动、隐藏、删掉时跟着一起）。返回三角形数。
static func _build_occluder(unit: Node3D, parts: Array) -> int:
	var to_unit := unit.global_transform.affine_inverse()
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for part in parts:
		var arrays: Array = part[0]
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array((to_unit * (part[1] as Transform3D)) * v)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		for i in idx:
			indices.append(base + i)
	if indices.is_empty():
		return 0
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, indices)
	var oi := OccluderInstance3D.new()
	oi.name = OCCLUDER_NAME
	oi.occluder = occ
	unit.add_child(oi)
	return indices.size() / 3


static func _eligible(m: MeshInstance3D, referenced: Dictionary) -> bool:
	if m.get_class() != "MeshInstance3D" or m.get_script() != null or m.mesh == null or not m.is_visible_in_tree():
		return false
	if m.get_child_count() > 0 or m.material_overlay != null or m.transparency > 0.0 or m.skin != null:
		return false
	if referenced.has(m.get_instance_id()) or m.name.begins_with(BATCH_PREFIX) or m.get_parent() is Skeleton3D:
		return false
	for grp in m.get_groups():
		if not str(grp).begins_with("_"):
			return false
	if m.mesh is ArrayMesh and (m.mesh as ArrayMesh).get_blend_shape_count() > 0:
		return false
	for si in m.mesh.get_surface_count():
		if m.mesh is ArrayMesh and (m.mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		if not _static_material(_material(m, si)):
			return false
	return true


## 网格往上最近的单位：有脚本的、被脚本变量引用的、或合批根。中间只允许普通的 Node3D / StaticBody3D。
static func _unit(m: MeshInstance3D, root: Node3D, referenced: Dictionary) -> Node3D:
	var unit: Node3D = null
	var p := m.get_parent()
	while p != null:
		if int(referenced.get(p.get_instance_id(), 0)) == SKIP:
			return null
		if unit == null:
			if p == root or p.get_script() != null or referenced.has(p.get_instance_id()):
				unit = p as Node3D
				if unit == null:
					return null
			elif not (p.get_class() == "Node3D" or p.get_class() == "StaticBody3D"):
				return null
		if p == root:
			return unit
		p = p.get_parent()
	return null


static func _material(m: MeshInstance3D, si: int) -> Material:
	if m.material_override != null:
		return m.material_override
	var o := m.get_surface_override_material(si)
	return o if o != null else m.mesh.surface_get_material(si)


static func _static_material(mat: Material) -> bool:
	if mat == null:
		return true
	if not mat is BaseMaterial3D or mat.next_pass != null:
		return false
	var b := mat as BaseMaterial3D
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and b.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return false
	if b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or b.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
		return false
	if (b.uv1_triplanar and not b.uv1_world_triplanar) or (b.uv2_triplanar and not b.uv2_world_triplanar):
		return false
	return not b.use_point_size and not b.fixed_size


## 一个面有哪些数组（法线、切线、颜色、UV、UV2）：只有格式一样的面才能首尾相接。
static func _signature(arrays: Array) -> int:
	var sig := 0
	for a in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[a] != null:
			sig |= 1 << a
	return sig


static func _build_mesh(parts: Array, mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var first: Array = parts[0][0]
	for part in parts:
		var arrays: Array = part[0]
		var xf: Transform3D = part[1]
		var base := verts.size()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		verts.append_array(xf * v)
		var flip := xf.basis.determinant() < 0.0
		if first[Mesh.ARRAY_NORMAL] != null:
			var n: PackedVector3Array = Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)
			for i in n.size():
				n[i] = n[i].normalized()
			normals.append_array(n)
		if first[Mesh.ARRAY_TANGENT] != null:
			var tg: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			var out_t := PackedFloat32Array()
			out_t.resize(tg.size())
			for i in range(0, tg.size(), 4):
				var t := (xf.basis * Vector3(tg[i], tg[i + 1], tg[i + 2])).normalized()
				out_t[i] = t.x
				out_t[i + 1] = t.y
				out_t[i + 2] = t.z
				out_t[i + 3] = -tg[i + 3] if flip else tg[i + 3]
			tangents.append_array(out_t)
		if first[Mesh.ARRAY_COLOR] != null:
			colors.append_array(arrays[Mesh.ARRAY_COLOR])
		if first[Mesh.ARRAY_TEX_UV] != null:
			uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])
		if first[Mesh.ARRAY_TEX_UV2] != null:
			uv2s.append_array(arrays[Mesh.ARRAY_TEX_UV2])
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		var out_i := PackedInt32Array()
		out_i.resize(idx.size())
		for i in range(0, idx.size() - 2, 3):
			# 镜像变换会把三角形的绕向翻过来，换回去，背面剔除才对
			out_i[i] = base + idx[i]
			out_i[i + 1] = base + (idx[i + 2] if flip else idx[i + 1])
			out_i[i + 2] = base + (idx[i + 1] if flip else idx[i + 2])
		indices.append_array(out_i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_INDEX] = indices
	if first[Mesh.ARRAY_NORMAL] != null:
		out[Mesh.ARRAY_NORMAL] = normals
	if first[Mesh.ARRAY_TANGENT] != null:
		out[Mesh.ARRAY_TANGENT] = tangents
	if first[Mesh.ARRAY_COLOR] != null:
		out[Mesh.ARRAY_COLOR] = colors
	if first[Mesh.ARRAY_TEX_UV] != null:
		out[Mesh.ARRAY_TEX_UV] = uvs
	if first[Mesh.ARRAY_TEX_UV2] != null:
		out[Mesh.ARRAY_TEX_UV2] = uv2s
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	if mat != null:
		mesh.surface_set_material(0, mat)
	return mesh


## 所有脚本变量里引用到的节点（直接引用，或放在数组、字典里）。
static func _referenced_nodes(tree: SceneTree) -> Dictionary:
	var out := {}
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.get_script() == null:
			continue
		for p in n.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_collect(n.get(p["name"]), out, 0)
	return out


static func _collect(v: Variant, out: Dictionary, depth: int) -> void:
	if depth > 3:
		return
	if typeof(v) == TYPE_OBJECT:
		if is_instance_valid(v) and v is Node:
			out[(v as Node).get_instance_id()] = true
	elif v is Array:
		for e in v:
			_collect(e, out, depth + 1)
	elif v is Dictionary:
		for k in v:
			_collect(k, out, depth + 1)
			_collect(v[k], out, depth + 1)



## 两个节点最近的共同祖先（都在同一个单位里，所以一定找得到，最远就是单位本身）。
static func _common_ancestor(a: Node, b: Node) -> Node:
	var n := a
	while n != null and n != b and not n.is_ancestor_of(b):
		n = n.get_parent()
	return n
