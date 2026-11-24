@tool
class_name UnitTraitLifesteal
extends UnitTrait
## 吸血：打到人之後，自己補一部分的血。

## 補扣血的幾成
@export_range(0.1, 1.0, 0.1) var ratio: float = 0.5



func trait_name() -> String:
	return "吸血"


func description() -> String:
	return "打人的時候補自己的血"


func labels() -> Dictionary:
	return {"ratio": "補幾成"}


func after_attack(_target: Unit, damage: int, battle: TacticsBattle) -> void:
	battle.mend(unit, maxi(roundi(damage * ratio), 1), trait_name())
