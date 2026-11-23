@tool
extends Node2D
## 基地：怪走到這裡就扣一滴血，扣光就輸。
## 生怪器的 reached_goal 已經在關卡裡連到 take_hit（檢查器的「節點」分頁看得到）。

## 被打到了（剩幾滴血）
signal hit(health: int)

## 幾滴血
@export_range(1, 100, 1) var max_health: int = 10
## 顏色
@export var color: Color = Color("4ab86a"):
	set(value):
		color = value
		queue_redraw()

var health: int = 0


func _ready() -> void:
	health = max_health


## 怪走到基地了
func take_hit(_enemy: Node2D = null) -> void:
	if health <= 0:
		return
	health -= 1
	hit.emit(health)
	queue_redraw()
	if health <= 0:
		GameFlow.lose("基地被攻破了！")


func _draw() -> void:
	draw_rect(Rect2(-16, -16, 32, 32), color.darkened(0.5))
	draw_rect(Rect2(-13, -13, 26, 26), color)
	draw_rect(Rect2(-5, -2, 10, 15), color.darkened(0.5))                # 門
	var ratio: float = float(health) / max_health if max_health > 0 and not Engine.is_editor_hint() else 1.0
	draw_rect(Rect2(-16, -24, 32, 4), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-16, -24, 32 * ratio, 4), Color("4ab86a").lerp(Color("d94a4a"), 1.0 - ratio))
