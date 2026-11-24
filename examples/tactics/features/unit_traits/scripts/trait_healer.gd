@tool
class_name UnitTraitHealer
extends UnitTrait
## 治療：可以選受傷的自己人補血（取代攻擊）。射程跟攻擊一樣。

## 一次補多少
@export_range(1, 50, 1) var amount: int = 7



func trait_name() -> String:
	return "治療"


func description() -> String:
	return "可以幫自己人補血"


func labels() -> Dictionary:
	return {"amount": "補多少"}


func apply() -> void:
	unit.heal_power += amount


func draw_on(on: Unit) -> void:
	on.draw_rect(Rect2(5, 6, 9, 3), Color("4ad07a"))
	on.draw_rect(Rect2(8, 3, 3, 9), Color("4ad07a"))
