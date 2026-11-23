class_name Builder
extends Node2D
## 蓋東西：按 1 選牆、按 2 選塔，滑鼠左鍵點格子蓋下去，右鍵拆掉（退一半的錢）。
## 牆和塔都會擋路，怪物會即時改路；但不能把路完全堵死（蓋下去會堵死的格子會變紅、蓋不下去）。
## 錢就是畫面上的分數（起手包的 ScoreDisplay），打死怪會加錢。
##
## 用法：拖進場景，在檢查器把生怪器（Spawner）和基地拖進來。

## 蓋了一個東西
signal built(cell: Vector2i, what: int)

const WALL_SCENE: PackedScene = preload("res://examples/tower_defense/features/builder/block.tscn")
const TOWER_SCENE: PackedScene = preload("res://examples/tower_defense/features/tower/tower.tscn")

## 出怪的地方（檢查會不會把路堵死用）
@export var spawner: Node2D
## 基地
@export var base: Node2D
## 牆多少錢
@export_range(0, 100, 1) var wall_cost: int = 1
## 塔多少錢
@export_range(0, 100, 1) var tower_cost: int = 4

## 現在要蓋什麼：0 牆、1 塔
var selected: int = 0
## 蓋好的東西：格子 → 節點
var buildings: Dictionary[Vector2i, Node2D] = {}

var _grid: PathGrid
var _money: ScoreDisplay


func _ready() -> void:
	z_index = 3


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_1"):
		selected = 0
	elif event.is_action_pressed("skill_2"):
		selected = 1
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or not _ready_to_build():
		return
	var cell: Vector2i = _grid.cell_of(to_global((make_input_local(button) as InputEventMouseButton).position))
	if button.button_index == MOUSE_BUTTON_LEFT:
		build(cell)
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		remove(cell)
	get_viewport().set_input_as_handled()


## 在 cell 蓋現在選的東西；蓋不了回傳 false
func build(cell: Vector2i) -> bool:
	if not _ready_to_build() or not can_build(cell):
		return false
	var node: Node2D = (WALL_SCENE if selected == 0 else TOWER_SCENE).instantiate()
	node.global_position = _grid.cell_center(cell)
	get_parent().add_child(node)
	buildings[cell] = node
	_money.add(-_cost())
	_grid.set_blocked(cell, true)                                 # 擋路：怪會即時改路
	built.emit(cell, selected)
	return true


## 拆掉 cell 上的東西，退一半的錢
func remove(cell: Vector2i) -> bool:
	if not buildings.has(cell):
		return false
	var node: Node2D = buildings[cell]
	_money.add(int((tower_cost if node is Tower else wall_cost) / 2.0))
	node.queue_free()
	buildings.erase(cell)
	_grid.clear_blocked(cell)
	return true


## 這一格能不能蓋：空地、錢夠、沒有怪站在上面、蓋下去不會把路堵死
func can_build(cell: Vector2i) -> bool:
	if not _grid.is_cell_walkable(cell) or buildings.has(cell) or _money.score < _cost():
		return false
	for node: Node in [spawner, base]:
		if node != null and _grid.cell_of((node as Node2D).global_position) == cell:
			return false
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if _grid.cell_of((enemy as Node2D).global_position) == cell:
			return false
	return spawner == null or base == null or not _grid.would_block(cell, spawner.global_position, base.global_position)


func _cost() -> int:
	return wall_cost if selected == 0 else tower_cost


func _ready_to_build() -> bool:
	if _grid == null or not is_instance_valid(_grid):
		_grid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	if _money == null or not is_instance_valid(_money):
		_money = get_tree().get_first_node_in_group("score") as ScoreDisplay
	return _grid != null and _money != null and not GameFlow.is_finished()


func _process(_delta: float) -> void:
	queue_redraw()


## 滑鼠指著的格子：綠色＝可以蓋、紅色＝不行
func _draw() -> void:
	if not _ready_to_build():
		return
	var cell: Vector2i = _grid.cell_of(get_global_mouse_position())
	if not _grid.astar.is_in_boundsv(cell):
		return
	var rect: Rect2 = Rect2(to_local(_grid.cell_center(cell)) - _grid.cell_size() / 2.0, _grid.cell_size())
	var ok: bool = can_build(cell)
	draw_rect(rect, Color(0.3, 1, 0.4, 0.3) if ok else Color(1, 0.3, 0.3, 0.3))
	draw_rect(rect, Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3), false, 2.0)
