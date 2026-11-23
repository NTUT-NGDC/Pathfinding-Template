@tool
extends Node2D
## 牆塊：Builder 蓋的牆，只是畫出來；擋路是 Builder 叫尋路地圖 set_blocked()。

## 顏色
@export var color: Color = Color("6b7080"):
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-15, -15, 30, 30), color.darkened(0.4))
	draw_rect(Rect2(-13, -13, 26, 26), color)
	draw_rect(Rect2(-13, -13, 26, 5), color.lightened(0.2))
