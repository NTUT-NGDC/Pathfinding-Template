@tool
class_name UnitTraitCounter
extends UnitTrait
## 反擊：被打之後，打得到對方就還手（還手不會再被還手）。

## 還手時的攻擊是幾成
@export_range(0.1, 2.0, 0.1) var power: float = 0.8

var _countering: bool = false



func trait_name() -> String:
	return "反擊"


func description() -> String:
	return "被打會還手"


func labels() -> Dictionary:
	return {"power": "還手的力道×"}


func modify_attack(now: float, _target: Unit, _battle: TacticsBattle) -> float:
	return now * power if _countering else now


func after_hit(attacker: Unit, _damage: int, is_counter: bool, battle: TacticsBattle) -> void:
	if is_counter or attacker.is_down or not battle.in_range(unit, battle.cell_of(unit), battle.cell_of(attacker)):
		return
	_countering = true
	await battle.strike(unit, attacker, true)
	_countering = false
