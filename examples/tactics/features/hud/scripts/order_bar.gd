class_name TacticsOrderBar
extends Control
## 行動順序：這一輪還沒動的棋子，由左到右（最左邊是現在輪到的）。

## 最多畫幾隻
const MAX_SHOWN: int = 14
const SPACING: float = 44.0

var _units: Array[Unit] = []
## 趕來支援的人 → 還要幾輪
var _late: Dictionary[Unit, int] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MAX_SHOWN * SPACING, 52)


func show_order(order: Array[Unit], late: Dictionary[Unit, int], round_number: int) -> void:
	_late.clear()
	for unit: Unit in late:
		_late[unit] = late[unit] - round_number
	_units = order.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_down)
	queue_redraw()


func _draw() -> void:
	for i: int in mini(_units.size(), MAX_SHOWN):
		var unit: Unit = _units[i]
		if not is_instance_valid(unit):
			continue
		var radius: float = 21.0 if i == 0 else 16.0
		var at: Vector2 = Vector2(26 + i * SPACING, 28)
		if i == 0:
			draw_circle(at, radius + 3.0, Color(1, 1, 0.5))
		Unit.draw_token(self, at, radius, unit.color, Unit.TEAM_COLORS[unit.team], unit.mark)
	var x: float = 26 + mini(_units.size(), MAX_SHOWN) * SPACING + 24
	for unit: Unit in _late:                                      # 還在路上的：畫淡一點，寫幾輪後到
		if not is_instance_valid(unit):
			continue
		Unit.draw_token(self, Vector2(x, 24), 13.0, unit.color.darkened(0.4), Unit.TEAM_COLORS[0].darkened(0.3), unit.mark)
		draw_string_outline(Unit.font(), Vector2(x - 40, 54), "%d 輪後到" % maxi(_late[unit], 1), HORIZONTAL_ALIGNMENT_CENTER, 80, 12, 5, Color.BLACK)
		draw_string(Unit.font(), Vector2(x - 40, 54), "%d 輪後到" % maxi(_late[unit], 1), HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color("8ec0ff"))
		x += 66.0
