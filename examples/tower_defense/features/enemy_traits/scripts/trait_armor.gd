@tool
class_name TraitArmor
extends EnemyTrait
## 裝甲：受到的傷害變少。

## 受到的傷害乘以幾（0.5＝只扣一半）
@export_range(0.05, 1.0, 0.05) var damage_multiplier: float = 0.5


func apply() -> void:
	walker.damage_taken_multiplier *= damage_multiplier


func _draw() -> void:
	# 外面一圈鐵灰色的殼
	var r: float = walker.radius if walker != null else 10.0
	draw_arc(Vector2.ZERO, r + 1.0, 0.0, TAU, 24, Color("9aa0a8"), 3.0)
