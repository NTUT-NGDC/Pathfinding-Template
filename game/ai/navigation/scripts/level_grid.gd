class_name LevelGrid
extends Node
## 關卡的尋路格子：遊戲開始時，從「牆」那張 TileMapLayer 自動建出 Godot 內建的 AStarGrid2D。
## 殺手要走去哪裡，就問它 find_path()。
##
## 哪些格子不能走？看 tile 有沒有「擋路」的碰撞（TileSet 的物理層 0）：
##   牆、玻璃有 → 不能走；草叢、地板沒有 → 可以走
## 所以想新增一種障礙物，只要在 TileSet 幫它加碰撞就好，不用改程式。
##
## 門：沒鎖的門可以走，但比較「貴」（殺手要停下來開門）；上鎖的門當成牆。
## 門開關、上鎖、解鎖時會自動更新格子。
##
## 關卡（EscapeLevel）執行時會自動建立這個節點，不用自己放。
## 整個場景只有一個，用 group「level_grid」找：get_tree().get_first_node_in_group("level_grid")

## 格子變了（門開關、解鎖）。正在走路的人可以重算路徑
signal grid_changed()

## 「擋路」是 TileSet 的第幾個物理層
const PATH_PHYSICS_LAYER: int = 0
## 走過一扇關著的門，等於多走幾格（讓殺手沒必要時不會專門去開門）
const CLOSED_DOOR_WEIGHT: float = 4.0

## Godot 內建的格子 A*（想看 A* 中間怎麼找，去 A* 實驗室）
var astar: AStarGrid2D = AStarGrid2D.new()

var _walls: TileMapLayer
var _floor: TileMapLayer
## 格子座標 → 那一格的門
var _doors: Dictionary[Vector2i, Door] = {}


func _enter_tree() -> void:
	add_to_group("level_grid")


## 開始用：walls 是畫牆、玻璃、草叢的那張 TileMapLayer，floor 是地板那張。
## 有給地板的話，沒畫地板的地方（房子外面的空白）也不能走
func setup(walls: TileMapLayer, floor: TileMapLayer = null) -> void:
	_walls = walls
	_floor = floor
	var region: Rect2i = walls.get_used_rect()
	if floor != null:
		region = region.merge(floor.get_used_rect())
	build_grid(region)
	for node: Node in get_tree().get_nodes_in_group("doors"):
		register_door(node as Door)


## 建格子：每一格看它擋不擋路
func build_grid(region: Rect2i) -> void:
	astar.region = region                                          # 地圖的範圍（格子座標）
	astar.cell_size = Vector2(_walls.tile_set.tile_size)           # 一格多大
	astar.offset = astar.cell_size / 2.0                           # 路徑點放在格子中心
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES  # 旁邊沒有障礙物才能斜走
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE        # 可以斜走時用的距離估計
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()                                                 # 套用設定，所有格子先變成可以走
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var cell: Vector2i = Vector2i(x, y)
			astar.set_point_solid(cell, blocks_path(cell))         # 擋路的格子設成不能走


## 這一格擋不擋路：tile 有「擋路」碰撞，或是房子外面的空白（沒有地板也沒有 tile）
func blocks_path(cell: Vector2i) -> bool:
	var data: TileData = _walls.get_cell_tile_data(cell)
	if data != null:
		return data.get_collision_polygons_count(PATH_PHYSICS_LAYER) > 0
	return _floor != null and _floor.get_cell_source_id(cell) == -1


## 從 from 走到 to 的路（全局座標，第一個點是起點那格的中心）。
## 走不到的話，走到離 to 最近、走得到的地方；起點本身不能走就回傳空的
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var from_cell: Vector2i = cell_of(from)
	var to_cell: Vector2i = cell_of(to)
	if not astar.is_in_boundsv(from_cell) or astar.is_point_solid(from_cell):
		return PackedVector2Array()
	to_cell = _clamp_to_region(to_cell)
	var local_path: PackedVector2Array = astar.get_point_path(from_cell, to_cell, true)
	var path: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in local_path:
		path.append(_walls.to_global(point))
	return path


## 全局座標在第幾格
func cell_of(global_position: Vector2) -> Vector2i:
	return _walls.local_to_map(_walls.to_local(global_position))


## 某一格中心的全局座標
func cell_center(cell: Vector2i) -> Vector2:
	return _walls.to_global(_walls.map_to_local(cell))


## 這個位置走不走得過去（門關著也算走得過去，上鎖才不行）
func is_walkable(global_position: Vector2) -> bool:
	var cell: Vector2i = cell_of(global_position)
	return astar.is_in_boundsv(cell) and not astar.is_point_solid(cell)


## 某一格的門（沒有門就是 null）
func door_at(cell: Vector2i) -> Door:
	return _doors.get(cell, null)


## 把一扇門登記到格子上：門會對齊到格子中心，之後開關門自動更新這一格
func register_door(door: Door) -> void:
	if door == null:
		return
	var cell: Vector2i = cell_of(door.global_position)
	door.global_position = cell_center(cell)
	_doors[cell] = door
	if not door.state_changed.is_connected(_on_door_changed):
		door.state_changed.connect(_on_door_changed)
	_apply_door(cell, door)


## 門的狀態 → 這一格能不能走、要多少代價
func _apply_door(cell: Vector2i, door: Door) -> void:
	if not astar.is_in_boundsv(cell):
		return
	astar.set_point_solid(cell, door.locked)                       # 上鎖＝牆
	astar.set_point_weight_scale(cell, 1.0 if door.is_open else CLOSED_DOOR_WEIGHT)


func _on_door_changed(door: Door) -> void:
	_apply_door(cell_of(door.global_position), door)
	grid_changed.emit()


func _clamp_to_region(cell: Vector2i) -> Vector2i:
	var region: Rect2i = astar.region
	return Vector2i(
		clampi(cell.x, region.position.x, region.end.x - 1),
		clampi(cell.y, region.position.y, region.end.y - 1))
