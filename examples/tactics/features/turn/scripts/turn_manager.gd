class_name TurnManager
extends Node
## 回合：我方回合 → 敵方回合 → 我方回合……
##   我方回合：點自己的棋子 → 亮出移動範圍（MoveRange）→ 點格子走過去 → 走完打旁邊的敵人
##              全部走完、或按「結束回合」，換敵方
##   敵方回合：每個敵人走向最近的我方（只能走移動範圍內的格子），走完打旁邊的我方
## 敵人全滅就贏，我方全滅就輸（起手包的 GameFlow）。
##
## 用法：拖進關卡，在檢查器把 MoveRange、回合文字（Label）、結束回合按鈕拖進來。

## 換回合了（0 我方、1 敵方）
signal turn_changed(team: int)

## 亮出移動範圍用的 MoveRange
@export var move_range: MoveRange
## 顯示「我方回合」的文字（可以不放）
@export var turn_label: Label
## 結束回合的按鈕（可以不放）
@export var end_turn_button: Button

const TEAM_NAMES: Array[String] = ["我方回合", "敵方回合"]
const ADJACENT: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## 現在是誰的回合
var turn: int = 0
## 正在有人走路（走完才能下一步）
var busy: bool = false

var _grid: PathGrid
var _selected: Unit


func _ready() -> void:
	if end_turn_button != null:
		end_turn_button.pressed.connect(end_player_turn)
	_start.call_deferred()


func _start() -> void:
	_grid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	move_range.clickable = false                                  # 點擊由這裡處理
	_begin_turn(0)


func _unhandled_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or turn != 0 or busy or _grid == null:
		return
	var at: Vector2 = move_range.to_global((move_range.make_input_local(button) as InputEventMouseButton).position)
	get_viewport().set_input_as_handled()
	if button.button_index == MOUSE_BUTTON_RIGHT:
		_select(null)
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell: Vector2i = _grid.cell_of(at)
	var unit: Unit = unit_at(cell)
	if unit != null and unit.team == 0 and not unit.has_moved:
		_select(unit)                                             # 點自己的棋子：選它
	elif _selected != null and move_range.has_cell(cell) and (unit == null or unit == _selected):
		_move(_selected, cell)                                    # 點範圍裡的格子：走過去


## 結束我方回合（按鈕）
func end_player_turn() -> void:
	if turn == 0 and not busy:
		_select(null)
		_begin_turn(1)


func _select(unit: Unit) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.selected = false
	_selected = unit
	move_range.clear()
	if unit == null:
		return
	unit.selected = true
	move_range.show_from(unit.global_position, unit.move_points)
	for other: Unit in all_units():
		if other != unit:
			move_range.cells.erase(_grid.cell_of(other.global_position))   # 有人站的格子不能停


## 叫棋子走到 cell，走完打旁邊的敵人
func _move(unit: Unit, cell: Vector2i) -> void:
	busy = true
	_select(null)
	unit.has_moved = true
	unit.follower().go_to(_grid.cell_center(cell))
	if unit.follower().is_moving():
		await unit.follower().arrived
	_attack_adjacent(unit)
	busy = false
	if _check_game_over():
		return
	if turn == 0 and units_of(0).all(func(u: Unit) -> bool: return u.has_moved):
		_begin_turn(1)                                            # 我方全部走完：換敵方


func _begin_turn(team: int) -> void:
	turn = team
	for unit: Unit in all_units():
		unit.has_moved = false
	if turn_label != null:
		turn_label.text = TEAM_NAMES[team]
	if end_turn_button != null:
		end_turn_button.disabled = team != 0
	turn_changed.emit(team)
	if team == 1:
		_enemy_turn()


## 敵方回合：每個敵人走向最近的我方
func _enemy_turn() -> void:
	for enemy: Unit in units_of(1):
		if not is_instance_valid(enemy) or GameFlow.is_finished():
			continue
		await _wait(0.3)
		if not is_instance_valid(enemy):
			continue
		var cell: Vector2i = _best_cell_toward_players(enemy)
		await _move(enemy, cell)
		if GameFlow.is_finished():
			return
	_begin_turn(0)


## 等幾秒（用自己底下的 Timer：換場景時跟著被刪掉，不會在別的場景繼續跑）
func _wait(seconds: float) -> void:
	var timer: Timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()


## 移動範圍內，離最近的我方最近的格子（最簡單的敵人 AI）
func _best_cell_toward_players(enemy: Unit) -> Vector2i:
	var reachable: Dictionary[Vector2i, float] = move_range.reachable_cells(_grid.cell_of(enemy.global_position), enemy.move_points)
	var best: Vector2i = _grid.cell_of(enemy.global_position)
	var best_distance: float = INF
	for cell: Vector2i in reachable:
		var occupant: Unit = unit_at(cell)
		if occupant != null and occupant != enemy:
			continue
		for player: Unit in units_of(0):
			var distance: float = Vector2(cell - _grid.cell_of(player.global_position)).length()
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best


## 打旁邊（上下左右）的第一個敵人
func _attack_adjacent(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	var cell: Vector2i = _grid.cell_of(unit.global_position)
	for d: Vector2i in ADJACENT:
		var target: Unit = unit_at(cell + d)
		if target != null and target.team != unit.team:
			target.take_damage(unit.attack)
			return


func _check_game_over() -> bool:
	if units_of(1).is_empty():
		GameFlow.win("敵人全滅！")
		return true
	if units_of(0).is_empty():
		GameFlow.lose("我方全滅……")
		return true
	return false


## 某一格上的棋子（沒有就是 null）
func unit_at(cell: Vector2i) -> Unit:
	for unit: Unit in all_units():
		if _grid.cell_of(unit.global_position) == cell:
			return unit
	return null


func units_of(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("units_team_%d" % team):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			result.append(node as Unit)
	return result


func all_units() -> Array[Unit]:
	var result: Array[Unit] = units_of(0)
	result.append_array(units_of(1))
	return result
