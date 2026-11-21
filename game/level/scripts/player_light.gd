class_name PlayerLight
extends CanvasLayer
## 玩家視野圈：蓋一層黑色在畫面上，玩家周圍挖一個洞（用 shader 畫）。
## 關卡（EscapeLevel）會依「害怕 vs 公平」的設定自動建立，不用自己放。

const SHADER: Shader = preload("res://game/level/shaders/player_light.gdshader")

var radius: float = 200.0
var softness: float = 80.0
var darkness: float = 0.92
var player: Node2D

var _rect: ColorRect
var _material: ShaderMaterial


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
	if player == null or not is_instance_valid(player):
		return
	# 玩家的世界座標 → 畫面座標（鏡頭移動時也對得上）
	var screen_position: Vector2 = player.get_viewport().get_canvas_transform() * player.global_position
	_material.set_shader_parameter("center", screen_position)
	_material.set_shader_parameter("rect_size", _rect.size)
	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("softness", minf(softness, radius))
	_material.set_shader_parameter("darkness", darkness)
