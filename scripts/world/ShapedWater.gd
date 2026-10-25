class_name ShapedWater
extends WaterVolume
## 形状更复杂的水体（亚特兰蒂斯用）：
##   · 环形水道：圆柱水体挖掉中间（inner_radius > 0），三圈环城水道各是一个；
##   · 去掉一个球（exclude_radius > 0）：穹顶外的大海 = 整片海的盒子减去气泡穹顶，穹顶里面是空气。
## 其余和 WaterVolume 一样（WaterVolume.find 会找到它，水下滤镜、游泳都照常）。

@export var inner_radius := 0.0
@export var exclude_center := Vector3.ZERO      ## 世界坐标
@export var exclude_radius := 0.0


func contains(world_point: Vector3) -> bool:
	if exclude_radius > 0.0 and world_point.distance_to(exclude_center) < exclude_radius:
		return false
	if not super.contains(world_point):
		return false
	if inner_radius > 0.0:
		var p := to_local(world_point)
		return Vector2(p.x, p.z).length() >= inner_radius
	return true


## 环形水道（open top：有水面，能浮起来、爬上岸）。
static func create_ring(id: StringName, center: Vector3, r_in: float, r_out: float, height: float) -> ShapedWater:
	var v := ShapedWater.new()
	v.name = "Water_%s" % id
	v.volume_id = id
	v.position = center
	v.radius = r_out
	v.inner_radius = r_in
	v.size = Vector3(r_out * 2.0, height, r_out * 2.0)
	v.open_top = true
	return v


## 一整片海减去一个球（没有水面：水里不浮也不沉）。
static func create_sea(id: StringName, center: Vector3, box: Vector3, hole_center: Vector3, hole_radius: float, speed := 1.0) -> ShapedWater:
	var v := ShapedWater.new()
	v.name = "Water_%s" % id
	v.volume_id = id
	v.position = center
	v.size = box
	v.open_top = false
	v.exclude_center = hole_center
	v.exclude_radius = hole_radius
	v.speed_scale = speed
	return v
