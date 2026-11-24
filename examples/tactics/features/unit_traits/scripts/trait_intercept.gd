@tool
class_name UnitTraitIntercept
extends UnitTrait
## 攔截：敵人走到這隻旁邊（上下左右）就得停下來，不能直接繞過去。


func trait_name() -> String:
	return "攔截"


func description() -> String:
	return "敵人走到旁邊就得停下來"


func intercepts() -> bool:
	return true


func draw_on(on: Unit) -> void:
	on.draw_arc(Vector2.ZERO, 16.0, 0, TAU, 24, Color(1, 1, 1, 0.35), 1.0)
