class_name WaterVolume
extends Node3D
## 可游泳的水体（泳池、玻璃水管、水族馆的下潜池）。湖不是 WaterVolume：MVP 湖里只能涉水。
## 形状：局部坐标的盒子（size，中心在本节点）或竖直圆柱（radius + height，中心在本节点）。
## open_top 表示顶面是空气中的水面（可以浮出水面换气）；玻璃水管两端连着别的水体，顶面不开放。
## 角色控制器通过 WaterVolume.find(point) 判断是否在水中，水下滤镜用 camera_underwater()。

@export var volume_id: StringName = &""
@export var size := Vector3(4.0, 2.0, 4.0)
@export var radius := 0.0          ## > 0 时为圆柱，size.y 为高度
@export var open_top := true


func _ready() -> void:
	add_to_group("water_volume")


func contains(world_point: Vector3) -> bool:
	var p := to_local(world_point)
	if absf(p.y) > size.y * 0.5:
		return false
	if radius > 0.0:
		return Vector2(p.x, p.z).length() <= radius
	return absf(p.x) <= size.x * 0.5 and absf(p.z) <= size.z * 0.5


## 水面的世界高度；不开放的水体返回 INF（在里面浮不出水面）。
func surface_y() -> float:
	return global_position.y + size.y * 0.5 if open_top else INF


static func find(tree: SceneTree, world_point: Vector3) -> WaterVolume:
	for v in tree.get_nodes_in_group("water_volume"):
		if (v as WaterVolume).contains(world_point):
			return v
	return null


static func create_box(id: StringName, center: Vector3, box_size: Vector3, top_open := true) -> WaterVolume:
	var v := WaterVolume.new()
	v.name = "Water_%s" % id
	v.volume_id = id
	v.position = center
	v.size = box_size
	v.open_top = top_open
	return v


static func create_cylinder(id: StringName, center: Vector3, r: float, height: float) -> WaterVolume:
	var v := WaterVolume.new()
	v.name = "Water_%s" % id
	v.volume_id = id
	v.position = center
	v.radius = r
	v.size = Vector3(r * 2.0, height, r * 2.0)
	v.open_top = false
	return v
