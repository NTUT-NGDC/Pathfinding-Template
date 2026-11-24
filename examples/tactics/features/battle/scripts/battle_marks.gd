class_name BattleMarks
extends Node2D
## 戰鬥的記號（只管畫）：意圖箭頭、指定目標、要站到哪一格、指著一隻時其他變淡。
## 打算做什麼是 TacticsBattle 的 intents 算的。

var battle: TacticsBattle


func _init(of: TacticsBattle) -> void:
	battle = of
	z_index = 5


## 指著一隻的時候，跟它沒關係的棋子變淡
func highlight() -> void:
	var looked: Unit = _looked_at() if battle.show_intents and not battle.is_waiting else null
	var bright: Array[Unit] = battle.related_to(looked) if looked != null else ([] as Array[Unit])
	for unit: Unit in battle.fighters + battle.party:
		if is_instance_valid(unit):
			unit.self_modulate = Color(0.6, 0.6, 0.6, 0.55) if looked != null and not bright.has(unit) else Color.WHITE


## 箭頭：誰打算打誰（實線＝這一輪打得到、虛線＝還打不到，先靠近）；
## 指著一隻，它的（連走的路）和打算打它的會亮起來，其他的變淡
func _draw() -> void:
	if not battle.is_active():
		return
	if battle.focus != null and is_instance_valid(battle.focus) and not battle.focus.is_down:
		var at: Vector2 = to_local(battle.focus.global_position)
		draw_arc(at, 17.0, 0, TAU, 32, Color("ffb020"), 3.0)
		for i: int in 4:
			var side: Vector2 = Vector2.from_angle(PI / 2.0 * i)
			draw_line(at + side * 13.0, at + side * 23.0, Color("ffb020"), 3.0)
	if battle.is_waiting and battle.hovered != null and battle.target_units.has(battle.hovered):
		_draw_stand(battle.hovered)
	if not battle.show_intents:
		return
	var looked: Unit = _looked_at()
	for unit: Unit in battle.intents:
		if unit != looked:
			_draw_intent(unit, false, 1.0 if looked != null and battle.target_of(unit) == looked else 0.75 if looked == null else 0.15)
	if looked == null:
		return
	_draw_intent(looked, true)
	var pulse: float = 16.0 + 2.0 * sin(Time.get_ticks_msec() * 0.008)
	draw_arc(to_local(looked.global_position), 16.0, 0, TAU, 32, Color.WHITE, 2.5)
	var target: Unit = battle.target_of(looked)
	if target != null:
		draw_arc(to_local(target.global_position), pulse, 0, TAU, 32, _intent_color(looked, target), 3.0)


## 打這隻會站到哪一格（回合制選目標時）
func _draw_stand(target: Unit) -> void:
	var cell: Vector2i = battle.best_cell_to_hit(battle.current, target)
	var at: Vector2 = to_local(battle.grid.cell_center(cell))
	if cell != battle.cell_of(battle.current):
		draw_dashed_line(to_local(battle.current.global_position), at, Color(1, 1, 1, 0.7), 2.0, 6.0)
		draw_circle(at, 11.0, Color(battle.current.color, 0.55))
	draw_arc(at, 13.0, 0, TAU, 24, Color.WHITE, 2.0)


func _intent_color(unit: Unit, target: Unit) -> Color:
	if target.team == unit.team:
		return Color("7ee08a")
	return Color("ff5a4a") if unit.team == 1 else Color("5aa8ff")


func _draw_intent(unit: Unit, with_path: bool, alpha: float = 1.0) -> void:
	if not is_instance_valid(unit) or unit.is_down or battle.target_of(unit) == null:
		return
	var plan: Dictionary = battle.intents[unit]
	var sure: bool = plan["target"] != null
	var target: Unit = battle.target_of(unit)
	var color: Color = Color(_intent_color(unit, target), alpha)
	var from: Vector2 = to_local(unit.global_position)
	if with_path and not plan["path"].is_empty():
		var line: PackedVector2Array = PackedVector2Array([from])
		for step: Vector2i in plan["path"]:
			line.append(to_local(battle.grid.cell_center(step)))
		draw_polyline(line, Color(color, 0.9), 3.0)
		from = line[line.size() - 1]
		draw_circle(from, 5.0, color)
	_draw_arrow(from, to_local(target.global_position), color, sure)


func _draw_arrow(from: Vector2, to: Vector2, color: Color, solid: bool) -> void:
	var along: Vector2 = from.direction_to(to)
	var side: Vector2 = along.orthogonal() * 4.0                   # 稍微靠旁邊，互打的兩條才不會疊在一起
	var start: Vector2 = from + along * 8.0 + side
	var end: Vector2 = to - along * 12.0 + side
	if solid:
		draw_line(start, end - along * 6.0, color, 2.5)
	else:
		draw_dashed_line(start, end - along * 6.0, color, 2.0, 7.0)
	var wing: Vector2 = along.orthogonal() * 5.0
	draw_colored_polygon(PackedVector2Array([end, end - along * 9.0 + wing, end - along * 9.0 - wing]), color)


## 指著（或布陣時拿著）的棋子
func _looked_at() -> Unit:
	var unit: Unit = battle.hovered if battle.hovered != null else battle.picked
	return unit if unit != null and is_instance_valid(unit) and not unit.is_down and battle.is_active() else null
