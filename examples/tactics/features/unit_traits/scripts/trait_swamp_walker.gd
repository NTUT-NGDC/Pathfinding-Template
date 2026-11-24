@tool
class_name UnitTraitSwampWalker
extends UnitTrait
## 沼澤行者：沼澤、森林、高地都只花固定的移動力。

## 難走的地形走一格算多少
@export_range(1.0, 5.0, 0.5) var cost: float = 1.0



func trait_name() -> String:
	return "沼澤行者"


func description() -> String:
	return "難走的地形像平地一樣好走"


func labels() -> Dictionary:
	return {"cost": "走一格算"}


func step_cost(now: float, _base: float, blocked: bool) -> float:
	return now if blocked or now < 0.0 else minf(now, cost)
