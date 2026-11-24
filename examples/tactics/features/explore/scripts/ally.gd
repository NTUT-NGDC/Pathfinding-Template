class_name TacticsAlly
extends Node2D
## 可以招募的同伴：走到旁邊按 E 就加入隊伍，當場能用；過關之後才會留在玩家的隊伍池。
## 在編輯器的「地圖」頁放，TacticsLevel 照地圖擺（招募過的就不會再出現）。

## 哪一種棋子
var unit_path: String = ""
## 隊伍池用來記「哪裡來的」
var key: String = ""

var _unit: Unit
var _near: bool = false


func _ready() -> void:
	add_to_group("tactics_allies")
	_unit = (load(unit_path) as PackedScene).instantiate() as Unit


func _exit_tree() -> void:
	if is_instance_valid(_unit):
		_unit.free()


func display_name() -> String:
	return _unit.display_name


func _physics_process(_delta: float) -> void:
	var party: TacticsParty = get_tree().get_first_node_in_group("tactics_party") as TacticsParty
	var near: bool = party != null and party.is_exploring() and party.nearest_ally() == self
	if near != _near:
		_near = near
		queue_redraw()


func _draw() -> void:
	Unit.draw_token(self, Vector2.ZERO, Unit.RADIUS, _unit.color, Color("4ab86a"), _unit.mark)
	if _near:
		draw_string_outline(Unit.font(), Vector2(-50, -20), "E 招募", HORIZONTAL_ALIGNMENT_CENTER, 100, 13, 5, Color.BLACK)
		draw_string(Unit.font(), Vector2(-50, -20), "E 招募", HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color("7ee08a"))
