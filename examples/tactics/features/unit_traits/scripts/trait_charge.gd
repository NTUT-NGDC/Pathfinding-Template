@tool
class_name UnitTraitCharge
extends UnitTrait
## 突擊：這一輪每走一格，攻擊多一點。

## 每走一格多多少攻擊
@export_range(0.5, 10.0, 0.5) var per_step: float = 1.0
## 最多多多少
@export_range(1.0, 30.0, 1.0) var limit: float = 5.0



func trait_name() -> String:
	return "突擊"


func description() -> String:
	return "走越遠打越痛"


func labels() -> Dictionary:
	return {"per_step": "每格多", "limit": "最多"}


func modify_attack(power: float, _target: Unit, _battle: TacticsBattle) -> float:
	return power + minf(unit.steps_taken * per_step, limit)
