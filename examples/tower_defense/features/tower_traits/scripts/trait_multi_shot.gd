@tool
class_name TraitMultiShot
extends TowerTrait
## 多重射擊：一次打好幾隻（打範圍內最近的幾隻）。

## 多打幾隻
@export_range(1, 10) var extra_targets: int = 2


func apply() -> void:
	tower.targets_per_shot += extra_targets


func _draw() -> void:
	for i: int in 3:
		draw_circle(Vector2.from_angle(TAU * i / 3.0 - PI / 2.0) * 6.0, 1.5, Color.WHITE)
