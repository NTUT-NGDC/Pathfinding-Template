@tool
class_name TraitSlow
extends TowerTrait
## 緩速：打到的怪變慢一陣子（怪身上會出現藍色的圈）。

## 速度變成幾倍（0.5＝慢一半）
@export_range(0.1, 1.0, 0.05) var slow_factor: float = 0.5
## 慢幾秒
@export_range(0.1, 10.0, 0.1, "suffix:秒") var slow_time: float = 1.5


func on_hit(enemy: Node2D, _damage: float) -> void:
	if enemy.has_method("slow"):
		enemy.call("slow", slow_factor, slow_time)


func _draw() -> void:
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, Color(0.5, 0.8, 1.0), 2.0)
