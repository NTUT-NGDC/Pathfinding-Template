class_name TacticsSupply
extends Node2D
## 地上的營地物資：我方誰走過去都會撿起來。TacticsLevel 照地圖放，打倒有「掉落物資」的小隊也會掉。

## 這一袋有幾份
var amount: int = 1


func _physics_process(_delta: float) -> void:
	var party: TacticsParty = get_tree().get_first_node_in_group("tactics_party") as TacticsParty
	if party == null or not party.is_exploring():
		return
	if party.members.any(func(u: Unit) -> bool: return u.global_position.distance_to(global_position) < party.pickup_distance):
		party.take_supply(amount, "撿到")
		queue_free()


func _draw() -> void:
	TacticsTerrain.draw_supply(self, Vector2.ZERO)
	if amount > 1:
		draw_string(Unit.font(), Vector2(8, -4), "×%d" % amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
