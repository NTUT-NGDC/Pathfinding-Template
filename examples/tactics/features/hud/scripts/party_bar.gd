class_name TacticsPartyBar
extends Control
## 隊員列（探索時左下角）：每一隻的頭像、血量，亮框＝現在控制的。點一下就換人控制。

const SPACING: float = 54.0

var party: TacticsParty


func _ready() -> void:
	custom_minimum_size = Vector2(0, 60)
	mouse_filter = Control.MOUSE_FILTER_STOP


func refresh() -> void:
	custom_minimum_size.x = party.members.size() * SPACING if party != null else 0.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		party.control_index(int(button.position.x / SPACING))
		accept_event()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()                                            # 血量會變


func _draw() -> void:
	if party == null:
		return
	for i: int in party.members.size():
		var unit: Unit = party.members[i]
		var at: Vector2 = Vector2(24 + i * SPACING, 26)
		if unit == party.leader():
			draw_circle(at, 22.0, Color(1, 1, 0.5))
		Unit.draw_token(self, at, 19.0, unit.color, Unit.TEAM_COLORS[0], unit.mark)
		var ratio: float = float(unit.health) / unit.max_health
		draw_rect(Rect2(at + Vector2(-19, 23), Vector2(38, 6)), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(at + Vector2(-18, 24), Vector2(36 * ratio, 4)), Color("4ab86a") if ratio > 0.5 else Color("e0a526") if ratio > 0.25 else Color("d94a4a"))
