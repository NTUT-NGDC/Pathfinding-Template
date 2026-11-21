class_name PathFollower
extends Node
## 走路元件：放在一個 CharacterBody2D 底下，叫它 go_to(位置)，它就會問 LevelGrid 找路、沿著格子走過去。
## 遇到關著的門會停下來，等 door_open_time 秒把門打開再繼續走。
##
## 「使用尋路」關掉的話，不找路，直接朝目標直線走（會卡在牆上）。
##
## 誰在用：殺手。之後別的角色要會走路，也可以放一個。

## 走到目標了
signal arrived()

## 離路徑點多近就算到了（像素）
const ARRIVE_DISTANCE: float = 4.0

## 走路速度（像素／秒），由主人每個狀態自己設定
var speed: float = 100.0
## 開一扇門要幾秒
var door_open_time: float = 1.0
## 關掉 → 不找路，直接朝目標直線走
var use_pathfinding: bool = true
## 現在要走的路（全局座標）
var path: PackedVector2Array = PackedVector2Array()
## 正在走的方向（沒在走就是 0），主人可以用來決定面向
var move_direction: Vector2 = Vector2.ZERO

var _body: CharacterBody2D
var _grid: LevelGrid
var _target: Vector2
var _has_target: bool = false
## 正在開門：剩幾秒
var _door_timer: float = 0.0
var _door: Door


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	if _body == null:
		push_warning("PathFollower 要放在 CharacterBody2D 底下。")


## 走到某個位置（全局座標）。再叫一次就重算路徑
func go_to(target: Vector2) -> void:
	_target = target
	_has_target = true
	path = _make_path(target)


## 停下來
func stop() -> void:
	_has_target = false
	path.clear()
	move_direction = Vector2.ZERO
	_door = null
	if _body != null:
		_body.velocity = Vector2.ZERO


## 還有沒有在走
func is_moving() -> bool:
	return _has_target


## 正在開門嗎
func is_opening_door() -> bool:
	return _door != null


func _physics_process(delta: float) -> void:
	if _body == null or not _has_target:
		return
	if _door != null:
		_update_door(delta)
		return
	follow_path()


## 沿著路走：朝下一個點前進，到了就換下一個
func follow_path() -> void:
	while not path.is_empty() and _body.global_position.distance_to(path[0]) < ARRIVE_DISTANCE:
		path.remove_at(0)                                          # 這個點到了，換下一個
	if path.is_empty():
		stop()
		arrived.emit()
		return
	if _start_opening_door(path[0]):                               # 下一格是關著的門：先停下來開門
		return
	move_direction = _body.global_position.direction_to(path[0])
	_body.velocity = move_direction * speed
	_body.move_and_slide()


func _make_path(target: Vector2) -> PackedVector2Array:
	_grid = _find_grid()
	if not use_pathfinding or _grid == null:
		return PackedVector2Array([target])                       # 不找路：直接走直線
	var result: PackedVector2Array = _grid.find_path(_body.global_position, target)
	if result.is_empty():
		return result
	result.remove_at(0)                                           # 第一個點是自己站的那格，不用走回去
	# 找得到目標那一格的話，最後一段走到確切的位置，不是格子中心
	var reaches_target: bool = result.is_empty() or _grid.cell_of(result[result.size() - 1]) == _grid.cell_of(target)
	if reaches_target and _grid.is_walkable(target):
		if result.is_empty():
			result.append(target)
		else:
			result[result.size() - 1] = target
	return result


## 下一個點是關著的門、而且已經走到門前 → 開始開門
func _start_opening_door(next_point: Vector2) -> bool:
	if _grid == null or not use_pathfinding:
		return false
	var door: Door = _grid.door_at(_grid.cell_of(next_point))
	if door == null or door.is_open or door.locked:
		return false
	var reach: float = _grid.astar.cell_size.x + ARRIVE_DISTANCE
	if _body.global_position.distance_to(door.global_position) > reach:
		return false
	_door = door
	_door_timer = door_open_time
	_body.velocity = Vector2.ZERO
	move_direction = _body.global_position.direction_to(door.global_position)
	return true


func _update_door(delta: float) -> void:
	_door_timer -= delta
	if _door.is_open:                                             # 別人先開了
		_door = null
	elif _door_timer <= 0.0:
		_door.open()
		_door = null
	if _door == null and _has_target:
		path = _make_path(_target)                                # 門開了，重算一次路


func _find_grid() -> LevelGrid:
	if _grid != null and is_instance_valid(_grid):
		return _grid
	return get_tree().get_first_node_in_group("level_grid") as LevelGrid
