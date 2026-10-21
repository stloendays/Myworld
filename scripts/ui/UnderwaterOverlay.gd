extends CanvasLayer
## 水下滤镜：当前相机在任一 WaterVolume 的水面以下时显示（泳池、玻璃水管、下潜池）。

const SHADER := preload("res://shaders/underwater.gdshader")

var underwater := false
var _rect: ColorRect


func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_rect.material = mat
	add_child(_rect)
	_rect.visible = false


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	underwater = false
	if cam != null:
		var p := cam.global_position
		var v := WaterVolume.find(get_tree(), p)
		underwater = v != null and p.y < v.surface_y() - 0.03
	_rect.visible = underwater
