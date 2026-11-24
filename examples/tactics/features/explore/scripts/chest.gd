class_name TacticsChest
extends Node2D
## 寶箱：控制的人走到旁邊按 E 搜括（要花一點時間，被敵人注意到會中斷），裡面是營地物資。
## 在編輯器的「地圖」頁放，TacticsLevel 照地圖擺。

## 裡面有幾份物資（0＝空的）
var amount: int = 1
## 搜過了
var opened: bool = false

var _near: bool = false


func _ready() -> void:
	add_to_group("tactics_chests")


func _physics_process(_delta: float) -> void:
	var party: TacticsParty = get_tree().get_first_node_in_group("tactics_party") as TacticsParty
	var near: bool = party != null and party.is_exploring() and party.nearest_chest() == self
	if near != _near:
		_near = near
		queue_redraw()


## 打開：物資給隊伍
func open(party: TacticsParty) -> void:
	if opened:
		return
	opened = true
	queue_redraw()
	if amount > 0:
		party.take_supply(amount, "寶箱裡有")
	else:
		party.say("寶箱是空的")


func _draw() -> void:
	TacticsTerrain.draw_chest(self, Vector2.ZERO, opened)
	if _near and not opened:
		draw_string_outline(Unit.font(), Vector2(-40, -18), "E 搜括", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, 5, Color.BLACK)
		draw_string(Unit.font(), Vector2(-40, -18), "E 搜括", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color("f0d9a0"))
