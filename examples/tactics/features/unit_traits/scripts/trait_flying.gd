@tool
class_name UnitTraitFlying
extends UnitTrait
## 飛行：每一格都只花 1 點移動力，可以飛過牆和敵人（不能停在上面）；不吃地形的防禦。
## 探索時直線飛，不用繞路。平常飄著，越過牆的時候升高。

## 平常飄多高、越過牆時多高（像素）
const LOW: float = 5.0
const HIGH: float = 14.0

var _time: float = 0.0
var _grid: PathGrid


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or unit == null or not unit.is_visible_in_tree():
		return
	if not is_instance_valid(_grid):
		_grid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	_time += delta
	var over_wall: bool = _grid != null and not _grid.is_walkable(unit.global_position)
	var height: float = (HIGH if over_wall else LOW) + sin(_time * 4.0) * 1.5
	unit.lift = lerpf(unit.lift, height, minf(delta * 10.0, 1.0))


func trait_name() -> String:
	return "飛行"


func description() -> String:
	return "不管地形，可以飛過牆和敵人"


func step_cost(_cost: float, _base: float, _blocked: bool) -> float:
	return 1.0


func is_flying() -> bool:
	return true


func draw_on(on: Unit) -> void:
	for side: float in [-1.0, 1.0]:
		on.draw_colored_polygon(PackedVector2Array([Vector2(side * 10, -2), Vector2(side * 21, -9), Vector2(side * 18, 3)]), Color(1, 1, 1, 0.9))
