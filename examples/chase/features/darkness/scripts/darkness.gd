class_name Darkness
extends CanvasLayer
## 黑暗：畫面變暗，只看得到玩家周圍一圈（用 shader 畫）。想做恐怖感就放，想公平就不放或把半徑開大。
## 追逐 AI 的視野錐、? ! 畫在更上層，不會被蓋掉（不想讓玩家看到視野錐：追逐 AI 的「顯示視野錐」關掉）。
##
## 用法：把 darkness.tscn 拖進關卡，調半徑、多暗。它會自動找 group「player」。

const SHADER: Shader = preload("res://examples/chase/features/darkness/shaders/darkness.gdshader")

## 看得到的半徑（像素）
@export_range(60, 800, 10, "suffix:px") var radius: float = 240.0
## 邊緣漸層的寬度（像素）
@export_range(0, 300, 10, "suffix:px") var softness: float = 100.0
## 外面有多暗：1＝全黑
@export_range(0.0, 1.0, 0.05) var darkness: float = 0.9

var _rect: ColorRect
var _material: ShaderMaterial
var _player: Node2D


func _ready() -> void:
	layer = 10
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	# 玩家的世界座標 → 畫面座標（鏡頭移動時也對得上）
	var screen_position: Vector2 = _player.get_viewport().get_canvas_transform() * _player.global_position
	_material.set_shader_parameter("center", screen_position)
	_material.set_shader_parameter("rect_size", _rect.size)
	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("softness", minf(softness, radius))
	_material.set_shader_parameter("darkness", darkness)
