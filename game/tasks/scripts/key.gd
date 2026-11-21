@tool
class_name KeyPickup
extends Task
## 鑰匙：玩家按 E 撿起來，就能打開同顏色的上鎖的門。撿到就算完成一個任務。
##
## 用法：把 key.tscn 拖進關卡，顏色選得跟上鎖的門一樣。

## 開哪個顏色的門
@export_enum("紅", "藍", "黃", "綠") var key_color: String = "紅":
	set(value):
		key_color = value
		queue_redraw()

@onready var _interact: Interactable = $Interactable


func _init() -> void:
	category = "鑰匙"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_interact.prompt = "撿起%s色鑰匙" % key_color
	_interact.interacted.connect(_on_interacted)


func _on_interacted(player: Player) -> void:
	player.add_key(key_color)
	_interact.enabled = false
	complete()
	visible = false                                               # 撿走了


func _draw() -> void:
	var color: Color = Door.KEY_COLORS.get(key_color, Color.WHITE)
	var dark: Color = color.darkened(0.5)
	# 鑰匙：圓頭＋桿子＋兩個齒
	draw_circle(Vector2(-6, 0), 6.0, dark)
	draw_circle(Vector2(-6, 0), 4.5, color)
	draw_circle(Vector2(-6, 0), 1.8, dark)
	draw_rect(Rect2(-1, -1.5, 12, 3), color)
	draw_rect(Rect2(7, 1, 2, 4), color)
	draw_rect(Rect2(3, 1, 2, 3), color)
