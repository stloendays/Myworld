class_name SignsBuilder
extends Node3D
## 按 world_layout.json → signs 摆放室外解说立牌（文字见 data/world/signs.json）。
## 建筑内部的立牌由建筑自己放。


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for s in WorldLayout.data().get("signs", []):
		var p := WorldLayout.v2(s["pos"])
		var sign := SignBoard.create(str(s["text"]), str(s.get("style", "stand")), float(s.get("width", 1.4)), float(s.get("scale", 1.0)))
		add_child(sign)
		sign.global_position = Vector3(p.x, WorldTerrain.height_at(p.x, p.y), p.y)
		sign.rotation.y = deg_to_rad(float(s.get("yaw_deg", 0.0)))
