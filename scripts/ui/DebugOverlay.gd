extends CanvasLayer
## F3 调试信息：帧率、世界坐标、朝向、所在区域、室内/室外、准星目标。用于核对坐标与室内外连续性。

const COMPASS := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]

var _label: Label
var _accum := 0.0


func _ready() -> void:
	layer = 5
	var panel := PanelContainer.new()
	panel.theme = GameSettings.ui_theme()
	panel.position = Vector2(12, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	panel.add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = not visible


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.1 or not visible:
		return
	_accum = 0.0
	var player := get_tree().get_first_node_in_group("local_player") as FirstPersonController
	if player == null:
		return
	var p := player.global_position
	var heading := player.heading_degrees()
	var zones := WorldState.zones_of(player.entity_id)
	var target := player.focused_target()
	var lines := PackedStringArray()
	lines.append("FPS %d  ·  帧时 %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())])
	lines.append("位置  X %.1f   Y %.2f   Z %.1f" % [p.x, p.y, p.z])
	lines.append("朝向  %.0f°（%s）" % [heading, COMPASS[int(round(heading / 45.0)) % 8]])
	lines.append("区域  %s  ·  %s" % [", ".join(PackedStringArray(zones)) if not zones.is_empty() else "—",
		"室内" if WorldState.is_indoors(player.entity_id) else "室外"])
	if target != null:
		lines.append("目标  %s（%s）" % [target.uid, target.get_state()])
	_label.text = "\n".join(lines)
