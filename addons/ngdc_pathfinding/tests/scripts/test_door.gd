extends Node2D
## 測試用的門：示範「會變的障礙物」要有什麼（PathGrid.register_obstacle）。
## 範例裡真正的門在 examples/chase/features/door/。

signal obstacle_changed()

## 上鎖＝擋路
var blocks_path: bool = false
## 關著的門比較貴（走路的人要停下來開門）
var path_cost: float = 4.0
var is_open: bool = false


func _enter_tree() -> void:
	add_to_group("path_obstacles")


func open() -> void:
	if blocks_path:
		return
	is_open = true
	path_cost = 1.0
	obstacle_changed.emit()


func set_locked(locked: bool) -> void:
	blocks_path = locked
	obstacle_changed.emit()
