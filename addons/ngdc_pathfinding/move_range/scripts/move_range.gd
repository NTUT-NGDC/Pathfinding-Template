class_name MoveRange
extends Node2D
## 移動範圍：算出「幾點移動力內走得到的格子」並畫出來（戰棋點角色時亮起來的那些格子）。
## 走進沼澤這種「移動成本」高的格子會花比較多移動力。
##
## 用法：把 move_range.tscn 拖進場景（場景裡要有尋路地圖 PathGrid），然後
##   show_from(角色的位置, 移動力)：亮出範圍
##   clear()：收起來
## 玩家點了亮起來的格子，會發出 tile_selected(格子)；點範圍外面發出 cancelled。
##
## 演算法：從起點像水一樣往外擴散（BFS），但每走一格要扣掉那格的成本，扣到不夠就停。
## 成本都一樣時就是 BFS；有成本時，先擴散到花費最少的格子（Dijkstra）。

## 點了範圍裡的格子
signal tile_selected(cell: Vector2i)
## 點了範圍外面
signal cancelled()

## 範圍格子的顏色
@export var fill_color: Color = Color(0.3, 0.6, 1.0, 0.35)
## 範圍格子外框的顏色
@export var border_color: Color = Color(0.5, 0.8, 1.0, 0.8)
## 滑鼠指著的格子的顏色
@export var hover_color: Color = Color(1, 1, 1, 0.35)
## 打勾：滑鼠左鍵點格子會發出 tile_selected（關掉的話只畫，不接收點擊）
@export var clickable: bool = true

## 每個角色自己的規則（可以不放）：cost_rule.call(從哪格, 到哪格) → 走進去要花多少，負數＝不能走。
## 有放的話連牆的格子都會問（例如會飛的角色可以過牆）
var cost_rule: Callable = Callable()
## 走到這一格就得停下來嗎（可以不放）：stop_rule.call(格子) → true＝停
var stop_rule: Callable = Callable()
## 現在亮起來的格子 → 走到那格要花多少移動力
var cells: Dictionary[Vector2i, float] = {}
## 起點格子
var origin: Vector2i

var _grid: PathGrid
## 上一次 reachable_cells() 算的：每一格是從哪一格走過來的
var _came_from: Dictionary[Vector2i, Vector2i] = {}


func _ready() -> void:
	z_index = 1


## 從某個位置（全局座標）亮出 move_points 點移動力走得到的範圍
func show_from(global_from: Vector2, move_points: float) -> void:
	_grid = _find_grid()
	if _grid == null:
		push_warning("MoveRange：場景裡找不到尋路地圖（PathGrid）。")
		return
	origin = _grid.cell_of(global_from)
	cells = reachable_cells(origin, move_points)
	queue_redraw()


## 收起來
func clear() -> void:
	cells.clear()
	queue_redraw()


## 這一格在不在範圍裡
func has_cell(cell: Vector2i) -> bool:
	return cells.has(cell)


## 從 start 出發，move_points 點移動力內走得到哪些格子（格子 → 花了多少）
func reachable_cells(start: Vector2i, move_points: float) -> Dictionary[Vector2i, float]:
	_grid = _find_grid()
	if _grid == null:
		return {}
	var spent: Dictionary[Vector2i, float] = {start: 0.0}         # 走到每一格花了多少
	var frontier: Array[Vector2i] = [start]                        # 還要往外擴散的格子
	_came_from.clear()
	while not frontier.is_empty():
		var current: Vector2i = _take_cheapest(frontier, spent)    # 先處理花最少的（Dijkstra）
		if current != start and stop_rule.is_valid() and stop_rule.call(current):
			continue                                               # 走到這格就得停，不能再往外走
		for next: Vector2i in _neighbors(current):
			var step: float = _step_cost(current, next)
			if step < 0.0:
				continue                                           # 這個角色不能走
			var cost: float = spent[current] + step
			if cost > move_points + 0.001:
				continue                                           # 移動力不夠，走不到
			if spent.has(next) and spent[next] <= cost:
				continue                                           # 已經有更省的走法
			spent[next] = cost
			_came_from[next] = current
			frontier.append(next)
	return spent


## 上一次 reachable_cells() 的起點走到 cell 的路（不含起點）。走不到＝空的
func path_to(cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	while _came_from.has(cell):
		path.push_front(cell)
		cell = _came_from[cell]
	return path


## 旁邊的格子：有自己的規則就全部都問（連牆也問），沒有就只有走得到的
func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	if not cost_rule.is_valid():
		return _grid.neighbors(cell)
	var result: Array[Vector2i] = []
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _grid.astar.is_in_boundsv(cell + d):
			result.append(cell + d)
	return result


## 走一步要花多少（負數＝不能走）
func _step_cost(from: Vector2i, to: Vector2i) -> float:
	if cost_rule.is_valid():
		return cost_rule.call(from, to)
	return _grid.cost_of(to) * _step_length(from, to)


func _take_cheapest(frontier: Array[Vector2i], spent: Dictionary[Vector2i, float]) -> Vector2i:
	var best: int = 0
	for i: int in range(1, frontier.size()):
		if spent[frontier[i]] < spent[frontier[best]]:
			best = i
	var cell: Vector2i = frontier[best]
	frontier.remove_at(best)
	return cell


## 斜走一步算 1.5（戰棋常見的算法，比 1.41 好心算）
func _step_length(a: Vector2i, b: Vector2i) -> float:
	return 1.5 if a.x != b.x and a.y != b.y else 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not clickable or cells.is_empty() or _grid == null:
		return
	if event is InputEventMouseMotion:
		queue_redraw()
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		var at: Vector2 = to_global((make_input_local(button) as InputEventMouseButton).position)
		var cell: Vector2i = _grid.cell_of(at)
		get_viewport().set_input_as_handled()
		if cells.has(cell):
			tile_selected.emit(cell)
		else:
			cancelled.emit()


func _draw() -> void:
	if cells.is_empty() or _grid == null or not is_instance_valid(_grid):
		return
	var size: Vector2 = _grid.cell_size()
	var hover: Vector2i = _grid.cell_of(get_global_mouse_position())
	for cell: Vector2i in cells:
		var rect: Rect2 = Rect2(to_local(_grid.cell_center(cell)) - size / 2.0, size).grow(-1.0)
		draw_rect(rect, hover_color if cell == hover else fill_color)
		draw_rect(rect, border_color, false, 1.0)


func _find_grid() -> PathGrid:
	if _grid != null and is_instance_valid(_grid):
		return _grid
	return get_tree().get_first_node_in_group("path_grid") as PathGrid
