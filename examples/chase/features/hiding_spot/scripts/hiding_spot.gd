@tool
class_name HidingSpot
extends Node2D
## 躲藏點（櫃子、床底）：玩家按 E 躲進去，殺手就看不到、碰不到；再按一次 E 出來。
## 但如果殺手「親眼看到你躲進去」，它會走過來把你抓出來。所以要趁殺手沒在看的時候躲。
##
## 用法：把 hiding_spot.tscn 拖進關卡，放在房間裡（不會擋路）。

## 外觀：櫃子或床（只差在樣子）
@export_enum("櫃子", "床") var style: int = 0:
	set(value):
		style = value
		queue_redraw()

const WOOD: Color = Color("7a5236")
const WOOD_DARK: Color = Color("4e3322")
const SHEET: Color = Color("c9d2e0")

@onready var _interact: Interactable = $Interactable


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("hiding_spots")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_interact.interacted.connect(_on_interacted)


func _on_interacted(player: Player) -> void:
	if player.is_hidden:
		player.leave_hiding()
	else:
		player.hide_in(self)


func _draw() -> void:
	if style == 0:
		# 櫃子：方塊＋兩扇門的縫和把手
		draw_rect(Rect2(-14, -15, 28, 30), WOOD)
		draw_rect(Rect2(-14, -15, 28, 30), WOOD_DARK, false, 2.0)
		draw_line(Vector2(0, -13), Vector2(0, 13), WOOD_DARK, 2.0)
		draw_rect(Rect2(-4, -2, 2, 4), WOOD_DARK)
		draw_rect(Rect2(2, -2, 2, 4), WOOD_DARK)
	else:
		# 床：床架＋棉被＋枕頭（一格寬、兩格長）
		draw_rect(Rect2(-14, -30, 28, 60), WOOD)
		draw_rect(Rect2(-12, -16, 24, 44), SHEET)
		draw_rect(Rect2(-10, -27, 20, 9), Color.WHITE)
		draw_rect(Rect2(-14, -30, 28, 60), WOOD_DARK, false, 2.0)
