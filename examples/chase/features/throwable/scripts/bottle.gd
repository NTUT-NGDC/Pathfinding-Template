@tool
class_name Bottle
extends Node2D
## 地上的瓶子：玩家按 E 撿起來，之後按 1（技能 1）往面向的方向丟出去。
## 瓶子落地會碎掉、發出聲音，追逐 AI 會走過去查看，玩家可以趁機溜過去。
## 丟多遠、聲音多大在玩家（Player）的檢查器「瓶子」那一組調。
##
## 用法：把 bottle.tscn 拖進關卡。

## 被撿起來了
signal picked(player: Player)

## 一次撿到幾個
@export_range(1, 10) var amount: int = 1

const GLASS: Color = Color("6fbf8f")
const DARK: Color = Color("2c4a3a")

@onready var _interact: Interactable = $Interactable


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_interact.interacted.connect(_on_interacted)


func _on_interacted(player: Player) -> void:
	player.add_bottles(amount)
	picked.emit(player)
	queue_free()


func _draw() -> void:
	# 瓶子：瓶身＋瓶頸
	draw_rect(Rect2(-5, -4, 10, 13), DARK)
	draw_rect(Rect2(-4, -3, 8, 11), GLASS)
	draw_rect(Rect2(-2, -9, 4, 6), DARK)
	draw_rect(Rect2(-1, -8, 2, 5), GLASS)
	draw_line(Vector2(-2, -1), Vector2(-2, 6), Color(1, 1, 1, 0.5), 1.0)
