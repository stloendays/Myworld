class_name ZoneArea
extends Area3D
## 区域触发器：带稳定 zone_id。角色（有 entity_id 属性的物体）进出时写入 WorldState，
## 再由 WorldState 发 EventBus.zone_entered / zone_exited。M3 的 AudioDirector 订阅这些事件做室内外混音。

@export var zone_id: StringName = &""
@export var is_indoor := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.ACTORS
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	var actor_id: Variant = body.get("entity_id")
	if actor_id != null:
		WorldState.enter_zone(StringName(actor_id), zone_id, is_indoor)


func _on_body_exited(body: Node3D) -> void:
	var actor_id: Variant = body.get("entity_id")
	if actor_id != null:
		WorldState.exit_zone(StringName(actor_id), zone_id)


static func create_box(id: StringName, size: Vector3, pos: Vector3, indoor := false) -> ZoneArea:
	var zone := ZoneArea.new()
	zone.name = "Zone_%s" % id
	zone.zone_id = id
	zone.is_indoor = indoor
	zone.position = pos
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	zone.add_child(cs)
	return zone
