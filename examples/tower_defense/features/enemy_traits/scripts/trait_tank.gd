@tool
class_name TraitTank
extends EnemyTrait
## 厚血：血量變多，身體也變大一點。

## 血量乘以幾
@export_range(1.0, 10.0, 0.5) var health_multiplier: float = 3.0
## 身體大幾像素
@export_range(0, 16, 1, "suffix:px") var size_bonus: float = 4.0


func apply() -> void:
	walker.max_health *= health_multiplier
	walker.radius += size_bonus
