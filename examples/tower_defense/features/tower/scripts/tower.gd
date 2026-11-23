@tool
class_name Tower
extends Node2D
## 塔：每隔一段時間打範圍內最近的敵人（group「enemies」，要有 damage()）。塔本身也擋路。
## 滑鼠移到塔上會顯示射程。
##
## 想做別種塔：把「砲塔掛件」（tower_traits/）拖到塔底下，例如緩速、範圍傷害、多重射擊，可以掛好幾個。
## 範例裡的緩速塔、範圍塔就是「塔＋掛件」（tower/slow_tower.tscn、tower/splash_tower.tscn）。

## 打到敵人了（掛件用：緩速、範圍傷害……）
signal hit(enemy: Node2D, damage: float)

## 蓋一座要多少錢
@export_range(0, 100, 1) var cost: int = 4
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

## 一次打幾隻（多重射擊掛件會加）
var targets_per_shot: int = 1
## 顯示射程（滑鼠移到塔上、或蓋塔前預覽時）
var show_range: bool = false

var _cooldown: float = 0.0
## 剛剛打的位置（畫子彈線用）、還要畫幾秒
var _shots: PackedVector2Array = PackedVector2Array()
var _shot_time: float = 0.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown -= delta
	_shot_time -= delta
	if _cooldown <= 0.0:
		var enemies: Array[Node2D] = nearest_enemies(targets_per_shot)
		if not enemies.is_empty():
			_shots.clear()
			for enemy: Node2D in enemies:
				_shots.append(enemy.global_position)
				enemy.call("damage", damage)
				hit.emit(enemy, damage)
			_shot_time = 0.1
			_cooldown = fire_interval
	show_range = global_position.distance_to(get_global_mouse_position()) <= 16.0
	queue_redraw()


## 範圍內最近的敵人（沒有就是 null）
func nearest_enemy() -> Node2D:
	var enemies: Array[Node2D] = nearest_enemies(1)
	return null if enemies.is_empty() else enemies[0]


## 範圍內最近的 count 隻敵人（近的在前面）
func nearest_enemies(count: int) -> Array[Node2D]:
	var in_range: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy.has_method("damage") and global_position.distance_to(enemy.global_position) <= attack_range:
			in_range.append(enemy)
	in_range.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return in_range.slice(0, count)


func _draw() -> void:
	draw_rect(Rect2(-14, -14, 28, 28), color.darkened(0.5))
	draw_circle(Vector2.ZERO, 9.0, color)
	draw_circle(Vector2.ZERO, 4.0, color.lightened(0.4))
	if show_range or Engine.is_editor_hint():
		draw_circle(Vector2.ZERO, attack_range, Color(color, 0.12))
		draw_arc(Vector2.ZERO, attack_range, 0.0, TAU, 48, Color(color, 0.7), 2.0)
	if _shot_time > 0.0:
		for at: Vector2 in _shots:
			draw_line(Vector2.ZERO, to_local(at), Color(1, 1, 0.6), 2.0)
