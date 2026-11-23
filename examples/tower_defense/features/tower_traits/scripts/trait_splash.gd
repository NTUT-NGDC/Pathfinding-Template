@tool
class_name TraitSplash
extends TowerTrait
## 範圍傷害：打到一隻怪時，旁邊的怪也會被炸到。

## 炸多大（像素）
@export_range(8, 200, 4, "suffix:px") var splash_radius: float = 48.0
## 旁邊的怪受到幾成傷害（0.5＝一半）
@export_range(0.1, 1.0, 0.05) var splash_ratio: float = 0.5

var _boom_at: Vector2
var _boom_time: float = 0.0


func on_hit(enemy: Node2D, damage: float) -> void:
	var center: Vector2 = enemy.global_position
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var other: Node2D = node as Node2D
		if other != enemy and other.has_method("damage") and other.global_position.distance_to(center) <= splash_radius:
			other.call("damage", damage * splash_ratio)
	_boom_at = center
	_boom_time = 0.2


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_boom_time = maxf(_boom_time - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 3.0, Color("ff9a4a"))
	if _boom_time > 0.0:
		draw_circle(to_local(_boom_at), splash_radius * (1.0 - _boom_time / 0.2 * 0.5), Color(1, 0.6, 0.2, _boom_time * 2.0))
