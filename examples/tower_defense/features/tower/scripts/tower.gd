@tool
class_name Tower
extends Node2D
## 塔：每隔一段時間打範圍內的敵人（group「enemies」，要有 damage()），先打誰看 Target Priority。塔本身也擋路。
## 滑鼠移到塔上會顯示射程。
##
## 想做別種塔：把「砲塔掛件」（tower_traits/）拖到塔底下，例如緩速、範圍傷害、多重射擊，可以掛好幾個。
## 範例裡的緩速塔、範圍塔、連射塔就是「塔＋掛件」（tower/ 資料夾裡的 slow_tower、splash_tower、multi_tower）。

## 打到敵人了（掛件用：緩速、範圍傷害……）
signal hit(enemy: Node2D, damage: float)
## 升級了（掛件也可以接這個，讓自己的數字跟著變）
signal upgraded(level: int)

## 先打誰
enum Priority { NEAREST, CLOSEST_TO_BASE, MOST_HEALTH, LEAST_HEALTH }

## 名字（下面的按鈕上顯示的字）
@export var display_name: String = "塔"
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
## 範圍內有好幾隻時先打誰（最接近基地：剩下的路最短的那隻）
@export_enum("離塔最近", "最接近基地", "血最多", "血最少") var target_priority: int = Priority.NEAREST
## 顏色
@export var color: Color = Color("4a7bd9"):
	set(value):
		color = value
		queue_redraw()

@export_group("升級")
## 最高等級（1＝不能升級）
@export_range(1, 10, 1) var max_level: int = 3
## 每升一級，傷害變幾倍
@export_range(1.0, 5.0, 0.05) var damage_per_level: float = 1.5
## 每升一級，射程變幾倍
@export_range(1.0, 3.0, 0.05) var range_per_level: float = 1.1
## 每升一級，攻速變幾倍（2＝打的間隔變一半）
@export_range(1.0, 3.0, 0.05) var speed_per_level: float = 1.0
## 升級價格的倍率：升級價＝現在的價值 ×（三個倍率相乘 － 1）× 這個數字
@export_range(0.1, 5.0, 0.1) var upgrade_price: float = 1.0

## 現在幾級
var level: int = 1
## 總共花了多少錢（蓋＋升級，拆掉退一半）
var spent: int = 0
## 現在值多少錢（每升一級乘上「強了幾倍」，用來算下一級的價格）
var _value: float = 0.0

## 一次打幾隻（多重射擊掛件會加）
var targets_per_shot: int = 1
## 顯示射程（滑鼠移到塔上、或蓋塔前預覽時）
var show_range: bool = false

var _cooldown: float = 0.0
## 剛剛打的位置（畫子彈線用）、還要畫幾秒
var _shots: PackedVector2Array = PackedVector2Array()
var _shot_time: float = 0.0


func _ready() -> void:
	spent = cost
	_value = float(cost)


## 升一級會強幾倍
func power_per_level() -> float:
	return damage_per_level * range_per_level * speed_per_level


## 還能不能升級
func can_upgrade() -> bool:
	return level < max_level


## 升下一級要多少錢（強了幾倍就照比例算，最少 1 元）
func upgrade_cost() -> int:
	return maxi(roundi(_value * (power_per_level() - 1.0) * upgrade_price), 1)


## 升一級（錢由 Builder 扣）
func upgrade() -> bool:
	if not can_upgrade():
		return false
	spent += upgrade_cost()
	_value *= power_per_level()
	level += 1
	damage *= damage_per_level
	attack_range *= range_per_level
	fire_interval /= speed_per_level
	upgraded.emit(level)
	queue_redraw()
	return true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown -= delta
	_shot_time -= delta
	if _cooldown <= 0.0:
		var enemies: Array[Node2D] = pick_targets(targets_per_shot)
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


## 範圍內要打的 count 隻敵人（照 Target Priority 排，先打的在前面；一樣的話打近的）
func pick_targets(count: int) -> Array[Node2D]:
	var in_range: Array[Node2D] = []
	var scores: Dictionary[Node2D, float] = {}
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy == null or not enemy.has_method("damage") or _is_dead(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= attack_range:
			in_range.append(enemy)
			scores[enemy] = _priority_score(enemy)
	in_range.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		if scores[a] != scores[b]:
			return scores[a] < scores[b]
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return in_range.slice(0, count)


## 已經死了、等著消失的（同一幀被別座塔打死），不要浪費一發
func _is_dead(enemy: Node2D) -> bool:
	var health: Variant = enemy.get("health")
	return health != null and float(health) <= 0.0


## 排隊的分數：小的先打
func _priority_score(enemy: Node2D) -> float:
	var health: Variant = enemy.get("health")
	match target_priority:
		Priority.CLOSEST_TO_BASE:
			var follower: PathFollower = enemy.get_node_or_null("PathFollower") as PathFollower
			return follower.remaining_distance() if follower != null else INF
		Priority.MOST_HEALTH:
			return -float(health) if health != null else 0.0
		Priority.LEAST_HEALTH:
			return float(health) if health != null else 0.0
	return 0.0                                                    # 離塔最近：分數都一樣，照距離排


func _draw() -> void:
	draw_rect(Rect2(-14, -14, 28, 28), color.darkened(0.5))
	draw_circle(Vector2.ZERO, 9.0, color)
	draw_circle(Vector2.ZERO, 4.0, color.lightened(0.4))
	if level > 1:
		for i: int in level:                                      # 等級：幾級就幾個小點
			draw_circle(Vector2((i - (level - 1) / 2.0) * 5.0, 15.5), 2.0, Color("ffd75e"))
	if show_range or Engine.is_editor_hint():
		draw_circle(Vector2.ZERO, attack_range, Color(color, 0.12))
		draw_arc(Vector2.ZERO, attack_range, 0.0, TAU, 48, Color(color, 0.7), 2.0)
	if _shot_time > 0.0:
		for at: Vector2 in _shots:
			draw_line(Vector2.ZERO, to_local(at), Color(1, 1, 0.6), 2.0)
