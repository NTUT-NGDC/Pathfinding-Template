@tool
class_name TraitFast
extends EnemyTrait
## 加速：走路速度變快。

## 速度乘以幾
@export_range(1.0, 5.0, 0.1) var speed_multiplier: float = 1.6


func apply() -> void:
	walker.speed *= speed_multiplier


func _draw() -> void:
	# 身後兩條速度線
	var r: float = walker.radius if walker != null else 10.0
	for y: float in [-4.0, 4.0]:
		draw_line(Vector2(-r - 10.0, y), Vector2(-r - 3.0, y), Color(1, 1, 1, 0.7), 2.0)
