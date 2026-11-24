@tool
class_name Walker
extends Node2D
## 會走路的小怪：生怪器預設出的敵人。一個圓圈＋頭上的血條，底下有 PathFollower 負責走路。
## 想做自己的敵人：複製 walker.tscn 改顏色、大小、血量，或做一個新場景（底下要有 PathFollower）。
##
## 被打：damage(傷害)；血扣到 0 發出 died 然後消失。補血：heal()；緩速：slow()。
## 想讓怪有特性（加速、裝甲、會飛……）：把塔防範例的「怪物掛件」拖到它底下。

## 被打死了
signal died(walker: Walker)

## 名字（塔防的編輯器裡顯示）
@export var display_name: String = "普通怪"
## 走路速度（像素／秒）
@export_range(10, 500, 5, "suffix:px/s") var speed: float = 60.0:
	set(value):
		speed = value
		if is_node_ready():
			_follower().speed = value
## 血量
@export_range(1, 1000, 1) var max_health: float = 10.0
## 打牆的力氣：每秒扣打得壞的牆幾滴血
@export_range(0.1, 100.0, 0.1) var wall_damage: float = 1.0
## 打死給幾分（場景裡有起手包的分數 ScoreDisplay 的話會自動加）
@export_range(0, 1000, 1) var score: int = 1
## 顏色
@export var color: Color = Color("d9534f"):
	set(value):
		color = value
		queue_redraw()
## 半徑（像素）
@export_range(4, 32, 1, "suffix:px") var radius: float = 10.0:
	set(value):
		radius = value
		queue_redraw()

var health: float = 0.0
## 受到的傷害乘以這個數字（裝甲掛件會調低）
var damage_taken_multiplier: float = 1.0
## 被緩速：速度乘以幾、還剩幾秒
var _slow_factor: float = 1.0
var _slow_time: float = 0.0


func _ready() -> void:
	health = max_health
	if Engine.is_editor_hint():
		return
	add_to_group("enemies")
	_follower().speed = speed
	_follower().break_power = wall_damage


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _slow_time <= 0.0:
		return
	_slow_time -= delta
	if _slow_time <= 0.0:
		_slow_factor = 1.0
		_follower().speed = speed                                 # 緩速結束：恢復原本的速度
		queue_redraw()


## 扣血，扣到 0 就死掉
func damage(amount: float) -> void:
	if health <= 0.0:
		return
	health -= amount * damage_taken_multiplier
	queue_redraw()
	if health <= 0.0:
		var board: Node = get_tree().get_first_node_in_group("score")
		if board != null and board.has_method("add"):
			board.call("add", score)
		died.emit(self)
		queue_free()


## 補血（不會超過最大血量）
func heal(amount: float) -> void:
	if health <= 0.0:
		return
	health = minf(health + amount, max_health)
	queue_redraw()


## 緩速：速度乘以 factor（0.5＝慢一半），持續 seconds 秒。同時被緩速好幾次，取最慢的、最久的
func slow(factor: float, seconds: float) -> void:
	_slow_factor = minf(_slow_factor if _slow_time > 0.0 else 1.0, factor)
	_slow_time = maxf(_slow_time, seconds)
	_follower().speed = speed * _slow_factor
	queue_redraw()


## 是不是正在被緩速
func is_slowed() -> bool:
	return _slow_time > 0.0


func _follower() -> PathFollower:
	return $PathFollower as PathFollower


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color.darkened(0.5))
	draw_circle(Vector2.ZERO, radius - 2.0, color)
	if is_slowed():
		draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 24, Color(0.5, 0.8, 1.0, 0.9), 2.0)   # 被緩速：藍色的圈
	if health < max_health and health > 0.0:
		draw_rect(Rect2(-radius, -radius - 7.0, radius * 2.0, 3.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-radius, -radius - 7.0, radius * 2.0 * health / max_health, 3.0), Color("4ab86a"))
