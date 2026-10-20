class_name ZonesBuilder
extends Node3D
## 按 world_layout.json → zones 生成室外区域触发器（湖泊、码头、北部针叶林等），
## 让每个地点都有稳定 zone_id。木屋室内区域由 Cabin 自己生成（zone_id = cabin_interior）。


func _ready() -> void:
	for z in WorldLayout.zones():
		var c := WorldLayout.v2(z["center"])
		var s := WorldLayout.v2(z["size"])
		var y := WorldTerrain.height_at(c.x, c.y)
		add_child(ZoneArea.create_box(StringName(z["zone_id"]), Vector3(s.x, 80.0, s.y), Vector3(c.x, y + 20.0, c.y)))
