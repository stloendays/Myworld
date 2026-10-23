class_name LakesideLife
extends Node3D
## Thin playable vertical slice: Q fishing near data-defined spots,
## low-poly cat schedule, luminous rain-after-night lantern, star collectible.
## Fox and meteor conditions are defined/testable, visual animation later.

var _timer := 0.0
var _fish_attempts := 0
var _cat: Node3D
var _lantern: Node3D
var _star: Node3D


func _ready() -> void:
	_cat = _make_cat()
	add_child(_cat)
	_lantern = _make_lantern()
	add_child(_lantern)
	_star = _make_star()
	add_child(_star)
	_update_world()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_Q:
		return
	var lobby := get_tree().get_first_node_in_group("lobby_menu")
	if lobby != null and lobby.is_open():
		return
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player == null:
		return
	var at := Vector2(player.global_position.x, player.global_position.z)
	for spot in LakesideEcology.data().get("fishing_spots", []):
		var s: Dictionary = spot
		if at.distance_to(WorldLayout.v2(s["center"])) > float(s["radius"]):
			continue
		_fish_attempts += 1
		var f := LakesideEcology.draw_fish(str(s["id"]), WorldState.world_day, _fish_attempts, String(WorldState.season_id), WorldState.time_minutes, String(WorldState.weather_id))
		if f.is_empty():
			EventBus.toast_requested.emit(tr("这里暂时没有鱼上钩"))
		else:
			EventBus.toast_requested.emit(tr("钓到：%s") % _translated(f))
			# Ephemeral progress only until the versioned SaveManager is ready.
			var counts: Dictionary = WorldState.flags.get("fishing_counts", {})
			counts[str(f["id"])] = int(counts.get(str(f["id"]), 0)) + 1
			WorldState.flags["fishing_counts"] = counts
		get_viewport().set_input_as_handled()
		return


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	_update_world()


func _update_world() -> void:
	var cat_info: Dictionary = LakesideEcology.data().get("cat", {})
	var weather: Dictionary = WeatherController.blended()
	var activity := LakesideEcology.cat_activity(WorldState.time_minutes, float(weather.get("rain", 0.0)), float(weather.get("snow", 0.0)))
	var c: Vector2 = WorldLayout.v2(cat_info.get(activity, [-67, 37]))
	_cat.position = Vector3(c.x, 2.45, c.y)
	_cat.rotation.y = 0.0 if activity == "sleep" else sin(WorldState.time_minutes / 120.0) * 0.25
	_lantern.visible = LakesideEcology.event_active("rain_lantern", WorldState.world_day, WorldState.time_minutes, String(WorldState.weather_id), WorldState.rain_recent)
	_star.visible = LakesideEcology.event_active("meteor_stardust", WorldState.world_day, WorldState.time_minutes, String(WorldState.weather_id), WorldState.rain_recent)
	if _lantern.visible:
		var t := Time.get_ticks_msec() / 1000.0
		_lantern.position.y = WorldLayout.water_level() + 0.7 + sin(t) * 0.12
		_lantern.rotation.y = t * 0.11
	if _star.visible:
		_star.rotate_y(0.03)


func _translated(info: Dictionary) -> String:
	if TranslationServer.get_locale().begins_with("en"):
		return str(info.get("name_en", info.get("name", "")))
	return str(info.get("name", ""))


func _material(c: Color, luminous := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if luminous:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.7
	return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, luminous := false) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color, luminous)
	mesh.position = pos
	parent.add_child(mesh)


func _make_cat() -> Node3D:
	var root := Node3D.new()
	root.name = "CabinCat"
	_box(root, Vector3(0, 0.22, 0), Vector3(0.52, 0.35, 0.75), Color(0.72, 0.50, 0.32))
	_box(root, Vector3(0, 0.48, -0.36), Vector3(0.48, 0.40, 0.42), Color(0.75, 0.52, 0.34))
	for x in [-0.17, 0.17]:
		_box(root, Vector3(x, 0.76, -0.48), Vector3(0.12, 0.24, 0.12), Color(0.67, 0.42, 0.27))
		_box(root, Vector3(x, 0.50, -0.59), Vector3(0.06, 0.075, 0.04), Color(0.08, 0.08, 0.06))
		for z in [-0.25, 0.25]:
			_box(root, Vector3(x, 0.09, z), Vector3(0.14, 0.19, 0.15), Color(0.55, 0.38, 0.26))
	_box(root, Vector3(0, 0.73, 0.5), Vector3(0.12, 0.52, 0.12), Color(0.70, 0.49, 0.33))
	return root


func _make_lantern() -> Node3D:
	var root := Node3D.new()
	root.name = "RainLantern"
	var cfg: Dictionary = _event("rain_lantern")
	var p := WorldLayout.v2(cfg.get("position", [7, 24]))
	root.position = Vector3(p.x, 0.7, p.y)
	_box(root, Vector3.ZERO, Vector3(0.55, 0.6, 0.55), Color(1.0, 0.75, 0.38), true)
	_box(root, Vector3(0, -0.38, 0), Vector3(0.68, 0.08, 0.68), Color(0.31, 0.21, 0.15))
	_box(root, Vector3(0, 0.38, 0), Vector3(0.68, 0.08, 0.68), Color(0.31, 0.21, 0.15))
	root.visible = false
	return root


func _make_star() -> Node3D:
	var root := Node3D.new()
	root.name = "MeteorStardust"
	var cfg: Dictionary = _event("meteor_stardust")
	var p := WorldLayout.v2(cfg.get("position", [99, -106]))
	root.position = Vector3(p.x, WorldTerrain.height_at(p.x, p.y) + 1.0, p.y)
	_box(root, Vector3.ZERO, Vector3(0.38, 0.38, 0.38), Color(0.63, 0.88, 1.0), true)
	root.visible = false
	return root


func _event(id: String) -> Dictionary:
	for event in LakesideEcology.data().get("events", []):
		if str(event.get("id", "")) == id:
			return event
	return {}
