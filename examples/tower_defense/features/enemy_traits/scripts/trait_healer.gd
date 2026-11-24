@tool
class_name TraitHealer
extends EnemyTrait
## 治療：每隔一段時間幫附近的怪（包括自己）補血。

## 補多遠（像素）
@export_range(16, 300, 8, "suffix:px") var heal_range: float = 80.0
## 一次補多少血
@export_range(0.5, 50.0, 0.5) var amount: float = 2.0
## 隔幾秒補一次
@export_range(0.2, 10.0, 0.1, "suffix:秒") var interval: float = 2.0

var _timer: float = 0.0
var _pulse: float = 0.0


func trait_name() -> String:
	return "治療"


func labels() -> Dictionary:
	return {"heal_range": "補多遠", "amount": "一次補幾滴", "interval": "隔幾秒補"}


func apply() -> void:
	_timer = interval


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or walker == null:
		return
	_timer -= delta
	_pulse = maxf(_pulse - delta, 0.0)
	if _timer <= 0.0:
		_timer = interval
		heal_nearby()
	queue_redraw()


## 幫範圍內的怪補血，回傳補了幾隻
func heal_nearby() -> int:
	var healed: int = 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy.has_method("heal") and enemy.global_position.distance_to(global_position) <= heal_range:
			enemy.call("heal", amount)
			healed += 1
	_pulse = 0.4
	return healed


func _draw() -> void:
	# 身上的綠色十字；補血時一圈綠光往外擴
	draw_rect(Rect2(-1.5, -5, 3, 10), Color("7be08f"))
	draw_rect(Rect2(-5, -1.5, 10, 3), Color("7be08f"))
	if _pulse > 0.0:
		var t: float = 1.0 - _pulse / 0.4
		draw_arc(Vector2.ZERO, heal_range * t, 0.0, TAU, 32, Color(0.5, 1, 0.6, 0.6 * (1.0 - t)), 2.0)
