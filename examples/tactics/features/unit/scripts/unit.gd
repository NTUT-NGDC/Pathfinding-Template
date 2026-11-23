@tool
class_name Unit
extends Node2D
## 棋子：我方或敵方。底下有 PathFollower 負責走路。回合怎麼輪由 TurnManager 決定。
##
## 用法：把 unit.tscn 拖進關卡，放在格子上，在檢查器選隊伍、移動力、血量。

## 被打死了
signal died(unit: Unit)

## 我方（玩家控制）或敵方（電腦控制）
@export_enum("我方", "敵方") var team: int = 0:
	set(value):
		team = value
		queue_redraw()
## 一回合可以走多遠（沼澤一格算 3）
@export_range(1, 20, 1) var move_points: int = 4
## 幾滴血
@export_range(1, 20, 1) var max_health: int = 3
## 打一下扣幾滴
@export_range(1, 20, 1) var attack: int = 1
## 走路速度（像素／秒，只影響看起來多快）
@export_range(50, 800, 10, "suffix:px/s") var speed: float = 220.0

const TEAM_COLORS: Array[Color] = [Color("4a7bd9"), Color("d94a4a")]

var health: int = 0
## 這回合走過了
var has_moved: bool = false:
	set(value):
		has_moved = value
		queue_redraw()
## 被選起來了
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()


func _ready() -> void:
	health = max_health
	if Engine.is_editor_hint():
		return
	add_to_group("units_team_%d" % team)
	follower().speed = speed


func follower() -> PathFollower:
	return $PathFollower as PathFollower


## 被打，血扣到 0 就死掉
func take_damage(amount: int) -> void:
	health -= amount
	queue_redraw()
	if health <= 0:
		died.emit(self)
		queue_free()


func _draw() -> void:
	var color: Color = TEAM_COLORS[team]
	if has_moved:
		color = color.darkened(0.45)                              # 走過了：變暗
	if selected:
		draw_circle(Vector2.ZERO, 15.0, Color(1, 1, 0.5))
	draw_circle(Vector2.ZERO, 12.0, color.darkened(0.5))
	draw_circle(Vector2.ZERO, 10.0, color)
	# 血量：頭上一排小方塊
	var hp: int = health if not Engine.is_editor_hint() else max_health
	for i: int in max_health:
		var x: float = -max_health * 3.0 + i * 6.0
		draw_rect(Rect2(x, -20, 5, 4), Color("4ab86a") if i < hp else Color(0, 0, 0, 0.6))
