@tool
class_name UnitTraitGuard
extends UnitTrait
## 守護：旁邊（上下左右）的自己人被打時少扣血。

## 旁邊的自己人扣幾成
@export_range(0.1, 1.0, 0.05) var ratio: float = 0.6



func trait_name() -> String:
	return "守護"


func description() -> String:
	return "旁邊的自己人少受傷"


func labels() -> Dictionary:
	return {"ratio": "旁邊只扣幾成"}


func protect(damage: float, _ally: Unit) -> float:
	return damage * ratio


func draw_on(on: Unit) -> void:
	on.draw_arc(Vector2.ZERO, 14.0, PI * 0.15, PI * 0.85, 12, Color("d9d9e6"), 3.0)
