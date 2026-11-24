@tool
class_name UnitTraitArea
extends UnitTrait
## 範圍攻擊：打到的敵人旁邊（上下左右）的敵人也會扣血。

## 旁邊的扣幾成
@export_range(0.1, 1.0, 0.1) var ratio: float = 0.5



func trait_name() -> String:
	return "範圍攻擊"


func description() -> String:
	return "打到的敵人旁邊也會扣血"


func labels() -> Dictionary:
	return {"ratio": "旁邊扣幾成"}


func after_attack(target: Unit, damage: int, battle: TacticsBattle) -> void:
	for other: Unit in battle.units_beside(battle.cell_of(target)):
		if other.team != unit.team and other != target:
			battle.hurt(other, maxi(roundi(damage * ratio), 1), trait_name())
