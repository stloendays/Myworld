extends Node
## 开发工具（无窗口可跑）：加载世界后逐项检查容易出错的摆放，打印问题清单。
##   Godot_console.exe --headless --path . res://devtools/GlitchProbe.tscn
## · 立牌：向下找地面（悬空多高）、向上找遮挡（是不是埋进了岩体 / 屋顶下）；
## · 独木舟：位置、模型是否加载、是否在相机可见层、离水面多高；
## · 桥：桥面与两岸地面、溪水水面、相邻桥板是否有重合面（闪烁的常见原因）。

var _main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	for i in 90:
		await get_tree().physics_frame
	_signs()
	_canoe()
	_bridges()
	get_tree().quit()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD | PhysicsLayers.TERRAIN)
	return get_viewport().world_3d.direct_space_state.intersect_ray(q)


func _signs() -> void:
	var boards := _main.find_children("*", "SignBoard", true, false)
	print("== 立牌 %d 块" % boards.size())
	for b: Node3D in boards:
		var p := b.global_position
		var down := _ray(p + Vector3(0.0, 0.6, 0.0), p - Vector3(0.0, 40.0, 0.0))
		var up := _ray(p + Vector3(0.0, 2.6, 0.0), p + Vector3(0.0, 60.0, 0.0))
		var gap := p.y - (down["position"] as Vector3).y if not down.is_empty() else INF
		var h := WorldTerrain.height_at(p.x, p.z)
		var flag := ""
		if gap > 0.25:
			flag += " 【悬空 %.2f m】" % gap
		if gap < -0.25:
			flag += " 【埋进地下 %.2f m】" % -gap
		if not up.is_empty() and (up["position"] as Vector3).y - p.y < 4.0:
			flag += " 【头顶 %.1f m 有遮挡 %s】" % [(up["position"] as Vector3).y - p.y, up["collider"].get_parent().name]
		print("  %-40s (%.1f, %.2f, %.1f) 地形 %.2f 射线地面 %s%s" % [str(b.get_path()).right(40), p.x, p.y, p.z, h,
			"%.2f" % (down["position"] as Vector3).y if not down.is_empty() else "无", flag])


func _canoe() -> void:
	var canoes := _main.find_children("*", "Canoe", true, false)
	print("== 独木舟 %d 条" % canoes.size())
	for c: Node3D in canoes:
		var meshes := c.find_children("*", "MeshInstance3D", true, false)
		var vis := 0
		var aabb := AABB()
		for mi: MeshInstance3D in meshes:
			if mi.is_visible_in_tree() and mi.mesh != null:
				vis += 1
				aabb = aabb.merge(mi.global_transform * mi.get_aabb()) if aabb.size != Vector3.ZERO else mi.global_transform * mi.get_aabb()
		var layers := PackedStringArray()
		for mi: MeshInstance3D in meshes:
			layers.append(str(mi.layers))
		print("  位置 %s 可见 %s 网格 %d（可见且有网格 %d）层 %s 包围盒 %s 水面 %.2f" % [c.global_position, c.is_visible_in_tree(),
			meshes.size(), vis, ",".join(layers), aabb, WorldLayout.water_level()])
		for ch in c.get_children():
			print("    子节点 %s %s 可见 %s" % [ch.name, ch.get_class(), ch.get("visible")])


func _bridges() -> void:
	var streams := _main.find_children("*", "Streams", true, false)
	for s in streams:
		for root: Node3D in s.get("bridges"):
			var meshes := root.find_children("*", "MeshInstance3D", true, false)
			print("== 桥 %s：网格 %d 个" % [root.name, meshes.size()])
			# 两两检查：同一材质、包围盒有重叠体积且某个轴上表面几乎重合 → 可能 z-fighting
			var boxes := []
			for mi: MeshInstance3D in meshes:
				boxes.append([mi, mi.global_transform * mi.get_aabb()])
			var overlaps := 0
			for i in boxes.size():
				for j in range(i + 1, boxes.size()):
					var a: AABB = boxes[i][1]
					var b: AABB = boxes[j][1]
					if a.intersects(b):
						var inter := a.intersection(b)
						if inter.size.x > 0.02 and inter.size.z > 0.02 and inter.size.y > 0.005:
							overlaps += 1
			print("  包围盒相交的网格对：%d" % overlaps)
			var first: MeshInstance3D = meshes[0] if not meshes.is_empty() else null
			if first != null:
				print("  第一块网格 %s 材质 %s 层 %d 透明度 %s" % [first.name, first.get_active_material(0), first.layers,
					first.get_active_material(0).get("transparency") if first.get_active_material(0) != null else "?"])
		var creek := s.find_children("*", "MeshInstance3D", false, false)
		for mi: MeshInstance3D in creek:
			print("  溪流网格 %s 包围盒 %s" % [mi.name, mi.global_transform * mi.get_aabb()])
