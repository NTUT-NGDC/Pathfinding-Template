class_name PathFollower
extends Node2D
## 跟著路徑走：放在任何角色（Node2D、CharacterBody2D）底下，給目標它就會繞路走過去。
##   go_to(位置)：走到一個固定的點
##   follow(節點)：一直追著某個節點（每隔「重算間隔」秒重算一次路，例如追玩家）
##   walk(路)：照你給的路走，不自己找路（例如戰棋照移動範圍算好的路走）
##   stop()：停下來
## 地圖變了（放了牆、門打開）會自動重算路徑。
## 遇到關著的門（有 open() 的障礙物）會停下來，等「開門要幾秒」再打開。
## 遇到打得壞的東西（有 damage()、is_broken 的障礙物，例如塔防的牆）會停下來打，打破再走。
##
## 角色是 CharacterBody2D 的話用 move_and_slide()（會撞牆）；其他 Node2D 直接移動位置。
## 需要場景裡有一個尋路地圖（PathGrid）。

## 走到目標了（follow 模式追到節點旁邊時也會發）
signal arrived()
## 走不到目標（只能走到離目標最近的地方）
signal path_blocked()

@export_group("移動")
## 走路速度（像素／秒）
@export_range(10, 1000, 5, "suffix:px/s") var speed: float = 100.0
## 追著節點時，隔幾秒重算一次路（不要每一幀算，很貴）
@export_range(0.05, 2.0, 0.05, "suffix:秒") var repath_interval: float = 0.2
## 使用尋路。關掉 → 不找路，直接朝目標直線走（會卡在牆上）
@export var use_pathfinding: bool = true
## 開一扇門要幾秒
@export_range(0.0, 5.0, 0.1, "suffix:秒") var door_open_time: float = 1.0
## 打擋路的東西（打得壞的牆）：每秒扣幾滴血
@export_range(0.1, 100.0, 0.1) var break_power: float = 1.0
## 離路徑點多近就算到了（像素）
@export_range(1.0, 32.0, 1.0, "suffix:px") var arrive_distance: float = 4.0

@export_group("外觀")
## 按 F2 時路徑線的顏色
@export var path_color: Color = Color(1, 0.4, 0.4, 0.9)

## 現在要走的路（全局座標）
var path: PackedVector2Array = PackedVector2Array()
## 正在走的方向（沒在走就是 0），主人可以用來決定面向
var move_direction: Vector2 = Vector2.ZERO

var _body: Node2D
var _grid: PathGrid
var _target_point: Vector2
var _target_node: Node2D
var _has_target: bool = false
## 照指定的路走（walk()），不要自己重新找路
var _fixed_path: bool = false
var _repath_timer: float = 0.0
var _door: Node2D
var _door_timer: float = 0.0


func _ready() -> void:
	top_level = true                                              # 路徑用全局座標畫，不跟著主人轉
	position = Vector2.ZERO
	z_index = 5
	_body = get_parent() as Node2D
	if _body == null:
		push_warning("PathFollower 要放在一個 Node2D（角色）底下。")


## 走到某個位置（全局座標）
func go_to(target: Vector2) -> void:
	_target_node = null
	_target_point = target
	_has_target = true
	_fixed_path = false
	_repath()


## 一直追著某個節點走
func follow(target: Node2D) -> void:
	_target_node = target
	_has_target = true
	_fixed_path = false
	_repath()


## 照指定的路走（全局座標），走完發 arrived
func walk(points: PackedVector2Array) -> void:
	_target_node = null
	_has_target = true
	_fixed_path = true
	_door = null
	path = points.duplicate()


## 停下來
func stop() -> void:
	_has_target = false
	_target_node = null
	path.clear()
	move_direction = Vector2.ZERO
	_door = null
	queue_redraw()
	var body: CharacterBody2D = _body as CharacterBody2D
	if body != null:
		body.velocity = Vector2.ZERO


## 還有沒有在走（或在追）
func is_moving() -> bool:
	return _has_target


## 沿著路走到終點還有多遠（像素）。沒有路＝INF
func remaining_distance() -> float:
	if _body == null or not _has_target or path.is_empty():
		return INF
	var total: float = 0.0
	var from: Vector2 = _body.global_position
	for point: Vector2 in path:
		total += from.distance_to(point)
		from = point
	return total


## 正在開門（或打擋路的東西）嗎
func is_opening_door() -> bool:
	return _door != null


## 正在打擋路的東西嗎
func is_breaking() -> bool:
	return is_instance_valid(_door) and _is_breakable(_door)


## 打得壞、還沒壞的障礙物
func _is_breakable(node: Node2D) -> bool:
	return node.has_method("damage") and node.get("is_broken") == false and node.get("blocks_path") != true


func _physics_process(delta: float) -> void:
	_connect_grid()
	if _body == null or not _has_target:
		return
	if _target_node != null:
		if not is_instance_valid(_target_node):
			stop()
			return
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath()                                             # 追節點：每隔一段時間重算一次
	if _door != null:
		_update_door(delta)
		return
	follow_path(delta)
	queue_redraw()


## 沿著路走：朝下一個點前進，到了就換下一個
func follow_path(delta: float) -> void:
	while not path.is_empty() and _body.global_position.distance_to(path[0]) < arrive_distance:
		path.remove_at(0)                                         # 這個點到了，換下一個
	if path.is_empty():
		_on_path_done()
		return
	if _start_opening_door(path[0]):                              # 下一格是關著的門：先停下來開門
		return
	move_direction = _body.global_position.direction_to(path[0])
	var body: CharacterBody2D = _body as CharacterBody2D
	if body != null:
		# 快到路徑點時放慢，不要一步衝過頭（畫面卡的時候 delta 很大，不放慢會在點附近來回晃）
		var step_speed: float = minf(speed, _body.global_position.distance_to(path[0]) / maxf(delta, 0.0001))
		body.velocity = move_direction * step_speed
		body.move_and_slide()
	else:
		_body.global_position = _body.global_position.move_toward(path[0], speed * delta)


func _on_path_done() -> void:
	move_direction = Vector2.ZERO
	var body: CharacterBody2D = _body as CharacterBody2D
	if body != null:
		body.velocity = Vector2.ZERO
	if _target_node != null:
		if _body.global_position.distance_to(_target_node.global_position) < _cell_length():
			arrived.emit()                                        # 追到旁邊了，繼續跟著
		return
	_has_target = false
	arrived.emit()


func _repath() -> void:
	_repath_timer = repath_interval
	var target: Vector2 = _target_node.global_position if _target_node != null else _target_point
	path = _make_path(target)


func _make_path(target: Vector2) -> PackedVector2Array:
	_grid = _find_grid()
	if not use_pathfinding or _grid == null or _body == null:
		return PackedVector2Array([target])                      # 不找路：直接走直線
	var result: PackedVector2Array = _grid.find_path(_body.global_position, target)
	if result.is_empty():
		return result
	result.remove_at(0)                                           # 第一個點是自己站的那格，不用走回去
	var reaches_target: bool = result.is_empty() or _grid.cell_of(result[result.size() - 1]) == _grid.cell_of(target)
	if not reaches_target:
		path_blocked.emit()
	elif _grid.is_walkable(target):
		# 最後一段走到確切的位置，不是格子中心
		if result.is_empty():
			result.append(target)
		else:
			result[result.size() - 1] = target
	return result


## 下一個點是關著的門（或打得壞的東西）、而且已經走到前面 → 開始開門（打它）
func _start_opening_door(next_point: Vector2) -> bool:
	if _grid == null or not use_pathfinding or _fixed_path:
		return false
	var door: Node2D = _grid.obstacle_at(_grid.cell_of(next_point))
	if door == null:
		return false
	var closed_door: bool = door.has_method("open") and door.get("is_open") == false and door.get("blocks_path") != true
	if not closed_door and not _is_breakable(door):
		return false
	if _body.global_position.distance_to(door.global_position) > _cell_length() + arrive_distance:
		return false
	_door = door
	_door_timer = door_open_time
	move_direction = _body.global_position.direction_to(door.global_position)
	var body: CharacterBody2D = _body as CharacterBody2D
	if body != null:
		body.velocity = Vector2.ZERO
	return true


func _update_door(delta: float) -> void:
	_door_timer -= delta
	if not is_instance_valid(_door) or _door.get("is_open") == true or _door.get("is_broken") == true:
		_door = null                                              # 別人先開了（打破了）
	elif not _door.has_method("open"):
		_door.call("damage", break_power * delta)                 # 打得壞的東西：一直打到破（破了會發 map_changed，在那裡重新找路）
		return
	elif _door_timer <= 0.0:
		_door.call("open")
		_door = null
	if _door == null and _has_target:
		_repath()


func _cell_length() -> float:
	return _grid.cell_size().x if _grid != null else 32.0


## 找到尋路地圖，地圖變了就重算路徑
func _connect_grid() -> void:
	var grid: PathGrid = _find_grid()
	if grid != null and not grid.map_changed.is_connected(_on_map_changed):
		grid.map_changed.connect(_on_map_changed)


func _on_map_changed() -> void:
	if not is_instance_valid(_door) or not _door.has_method("open"):
		_door = null                                              # 在打牆：地圖變了就重新想要繞路還是繼續打（牆扣的血會留著）
	if _has_target and _door == null and not _fixed_path:
		_repath()


func _find_grid() -> PathGrid:
	if _grid != null and is_instance_valid(_grid):
		return _grid
	_grid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	return _grid


func _draw() -> void:
	if not PathDebug.show_paths or not _has_target or _body == null:
		return
	var points: PackedVector2Array = PackedVector2Array([_body.global_position])
	points.append_array(path)
	if points.size() >= 2:
		draw_polyline(points, path_color, 2.0)
