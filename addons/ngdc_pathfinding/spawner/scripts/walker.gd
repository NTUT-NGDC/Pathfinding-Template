@tool
class_name Walker
extends Node2D
## 會走路的小怪：生怪器預設出的敵人。一個圓圈＋頭上的血條，底下有 PathFollower 負責走路。
## 想做自己的敵人：複製 walker.tscn 改顏色、大小、血量，或做一個新場景（底下要有 PathFollower）。
##
## 被打：damage(傷害)；血扣到 0 發出 died 然後消失。

## 被打死了
signal died(walker: Walker)

## 走路速度（像素／秒）
@export_range(10, 500, 5, "suffix:px/s") var speed: float = 60.0:
	set(value):
		speed = value
		if is_node_ready():
			_follower().speed = value
## 血量
@export_range(1, 1000, 1) var max_health: float = 10.0
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


func _ready() -> void:
	health = max_health
	if Engine.is_editor_hint():
		return
	add_to_group("enemies")
	_follower().speed = speed


## 扣血，扣到 0 就死掉
func damage(amount: float) -> void:
	if health <= 0.0:
		return
	health -= amount
	queue_redraw()
	if health <= 0.0:
		var board: Node = get_tree().get_first_node_in_group("score")
		if board != null and board.has_method("add"):
			board.call("add", score)
		died.emit(self)
		queue_free()


func _follower() -> PathFollower:
	return $PathFollower as PathFollower


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color.darkened(0.5))
	draw_circle(Vector2.ZERO, radius - 2.0, color)
	if health < max_health and health > 0.0:
		draw_rect(Rect2(-radius, -radius - 7.0, radius * 2.0, 3.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-radius, -radius - 7.0, radius * 2.0 * health / max_health, 3.0), Color("4ab86a"))
