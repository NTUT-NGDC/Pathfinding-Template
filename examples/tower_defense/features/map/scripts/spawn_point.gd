@tool
extends Node2D
## 多出來的出怪口：MapLoader 照地圖放的，生怪器會從這裡出怪（生怪器的 More Spawn Points）。只是畫一個框。


func _draw() -> void:
	draw_rect(Rect2(-14, -14, 28, 28), Color(0.9, 0.3, 0.3, 0.8), false, 3.0)
	draw_line(Vector2(-8, 0), Vector2(8, 0), Color(0.9, 0.3, 0.3, 0.8), 3.0)
	draw_line(Vector2(0, -8), Vector2(0, 8), Color(0.9, 0.3, 0.3, 0.8), 3.0)
