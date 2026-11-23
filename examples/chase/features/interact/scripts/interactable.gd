class_name Interactable
extends Area2D
## 「可以按 E 互動」的範圍：門、躲藏點、修理點、鑰匙……都在自己底下放一個。
## 玩家靠近時頭上會出現提示（例如「E 開門」），按 E 就發出 interacted，
## 按住 E 每一幀發出 held（修理點用），放開或走遠發出 released。
##
## 它只負責「玩家按了 E」，按了之後要做什麼，由擁有它的場景接 signal 決定。

## 按下 E
signal interacted(player: Player)
## 按住 E（每一幀）
signal held(player: Player, delta: float)
## 放開 E，或是按住時走出範圍
signal released(player: Player)

## 「互動」是第 5 個物理層
const INTERACT_LAYER: int = 1 << 4

## 玩家頭上的提示文字（「E 」會自動加在前面）
@export var prompt: String = "互動"
## 關掉就不能互動（例如任務做完了）
@export var enabled: bool = true


func _ready() -> void:
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	monitoring = false
