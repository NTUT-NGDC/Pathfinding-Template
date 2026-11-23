@tool
class_name Tower
extends Node2D
## 塔：每隔一段時間打範圍內最近的敵人（group「enemies」，要有 damage()）。塔本身也擋路。
## 想做別種塔（緩速、範圍傷害）：複製這個資料夾改。

## 打多遠（像素）
@export_range(32, 400, 8, "suffix:px") var attack_range: float = 96.0:
	set(value):
		attack_range = value
		queue_redraw()
## 一次打多少血
@export_range(0.5, 50, 0.5) var damage: float = 1.0
## 隔幾秒打一次
@export_range(0.1, 5.0, 0.1, "suffix:秒") var fire_interval: float = 0.5
## 顏色
@export var color: Color = Color("4a7bd9"):
	set(value):
		color = value
		queue_redraw()

var _cooldown: float = 0.0
## 剛剛打的位置（畫子彈線用）、還要畫幾秒
var _shot_at: Vector2
var _shot_time: float = 0.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown -= delta
	_shot_time -= delta
	if _cooldown <= 0.0:
		var enemy: Node2D = nearest_enemy()
		if enemy != null:
			enemy.call("damage", damage)
			_shot_at = enemy.global_position
			_shot_time = 0.1
			_cooldown = fire_interval
	queue_redraw()


## 範圍內最近的敵人（沒有就是 null）
func nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_distance: float = attack_range
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance <= best_distance and enemy.has_method("damage"):
			best = enemy
			best_distance = distance
	return best


func _draw() -> void:
	draw_rect(Rect2(-14, -14, 28, 28), color.darkened(0.5))
	draw_circle(Vector2.ZERO, 9.0, color)
	draw_circle(Vector2.ZERO, 4.0, color.lightened(0.4))
	draw_arc(Vector2.ZERO, attack_range, 0.0, TAU, 48, Color(color, 0.18), 1.0)
	if _shot_time > 0.0:
		draw_line(Vector2.ZERO, to_local(_shot_at), Color(1, 1, 0.6), 2.0)
