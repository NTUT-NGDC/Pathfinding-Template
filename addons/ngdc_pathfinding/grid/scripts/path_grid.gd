class_name PathGrid
extends Node
## 尋路地圖：從 TileMapLayer 自動建出 Godot 內建的 AStarGrid2D（格子 A*）。
## 會走路的角色（PathFollower）、移動範圍（MoveRange）都問它。整個場景放一個就好。
##
## 用法：把 path_grid.tscn 拖進場景，在檢查器把「牆」那張 TileMapLayer 拖進 Walls（地板那張拖進 Floor，可以不放）。
##
## 哪些格子不能走？看 tile 有沒有「擋路」的碰撞（TileSet 的物理層 0）：
##   牆、玻璃有 → 不能走；草叢、地板沒有 → 可以走。有放 Floor 的話，沒畫地板的地方也不能走
## 走起來多慢？看 tile 的自訂資料「移動成本」：沼澤 3＝走一格等於走三格，A* 會考慮要不要繞路。
## 會變的障礙物（門、塔）：呼叫 set_blocked()／set_cost()，或做成 obstacle（見 register_obstacle()）。
##
## 找它：get_tree().get_first_node_in_group("path_grid")

## 地圖變了（牆被放下、門打開……）。正在走路的角色會自動重算路徑
signal map_changed()

## tile 的「擋路」是 TileSet 的第幾個物理層
const PATH_PHYSICS_LAYER: int = 0
## tile 的自訂資料：移動成本
const COST_DATA: String = "移動成本"

## 畫牆、玻璃、草叢的 TileMapLayer
@export var walls: TileMapLayer
## 畫地板的 TileMapLayer（可以不放）。有放的話，沒畫地板的地方不能走，地板的「移動成本」也會算進去
@export var floor_layer: TileMapLayer
## 斜走：不斜走／旁邊沒有障礙物才能斜走／都可以斜走（會貼著牆角切過去）
@export_enum("不斜走", "旁邊沒有障礙物才能斜走", "都可以斜走") var diagonal: int = 1
## 遊戲開始時自動建地圖（關掉的話要自己呼叫 setup()）
@export var auto_setup: bool = true

## Godot 內建的格子 A*（想看 A* 中間怎麼找，去 A* 實驗室）
var astar: AStarGrid2D = AStarGrid2D.new()

## 程式設定的擋路格子（會蓋過 tile）：格子 → 擋不擋
var _blocked: Dictionary[Vector2i, bool] = {}
## 程式設定的成本：格子 → 成本
var _costs: Dictionary[Vector2i, float] = {}
## 登記的障礙物：格子 → 節點
var _obstacles: Dictionary[Vector2i, Node2D] = {}
## 障礙物底下原本用程式設定的擋路、成本（例如沼澤），拿掉障礙物時還原
var _under_blocked: Dictionary[Vector2i, bool] = {}
var _under_costs: Dictionary[Vector2i, float] = {}


func _enter_tree() -> void:
	add_to_group("path_grid")


func _ready() -> void:
	if auto_setup and walls != null:
		setup.call_deferred(walls, floor_layer)                   # 等場景裡的東西都準備好再建


## 開始用（auto_setup 打勾的話會自動呼叫）
func setup(walls_layer: TileMapLayer, floor_tiles: TileMapLayer = null) -> void:
	walls = walls_layer
	floor_layer = floor_tiles
	var region: Rect2i = walls.get_used_rect()
	if floor_layer != null:
		region = region.merge(floor_layer.get_used_rect())
	build_grid(region)
	for node: Node in get_tree().get_nodes_in_group("path_obstacles"):
		register_obstacle(node as Node2D)
	PathDebug.watch_grid(self)
	map_changed.emit()


## 建格子：每一格看它擋不擋路、走起來多貴
func build_grid(region: Rect2i) -> void:
	astar.region = region                                          # 地圖的範圍（格子座標）
	astar.cell_size = Vector2(walls.tile_set.tile_size)            # 一格多大
	astar.offset = astar.cell_size / 2.0                           # 路徑點放在格子中心
	astar.diagonal_mode = [AStarGrid2D.DIAGONAL_MODE_NEVER, AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES, AStarGrid2D.DIAGONAL_MODE_ALWAYS][diagonal]
	var heuristic: AStarGrid2D.Heuristic = AStarGrid2D.HEURISTIC_MANHATTAN if diagonal == 0 else AStarGrid2D.HEURISTIC_OCTILE
	astar.default_compute_heuristic = heuristic                    # 估計離終點多遠的方法
	astar.default_estimate_heuristic = heuristic
	astar.update()                                                 # 套用設定，所有格子先變成可以走
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			_refresh_cell(Vector2i(x, y))


## 這一格擋不擋路：程式設定的 → tile 的「擋路」碰撞 → 房子外面（沒有地板也沒有 tile）
func blocks_path(cell: Vector2i) -> bool:
	if _blocked.has(cell):
		return _blocked[cell]
	var data: TileData = walls.get_cell_tile_data(cell)
	if data != null:
		return data.get_collision_polygons_count(PATH_PHYSICS_LAYER) > 0
	return floor_layer != null and floor_layer.get_cell_source_id(cell) == -1


## 走進這一格的成本：程式設定的 → 地板和牆那層 tile 的「移動成本」取比較大的（沒設定＝1）
func cost_of(cell: Vector2i) -> float:
	if _costs.has(cell):
		return _costs[cell]
	return maxf(maxf(_tile_cost(walls, cell), _tile_cost(floor_layer, cell)), 1.0)


func _tile_cost(layer: TileMapLayer, cell: Vector2i) -> float:
	if layer == null or layer.tile_set == null or not layer.tile_set.has_custom_data_layer_by_name(COST_DATA):
		return 1.0
	var data: TileData = layer.get_cell_tile_data(cell)
	return 1.0 if data == null else float(data.get_custom_data(COST_DATA))


func _refresh_cell(cell: Vector2i) -> void:
	if not astar.is_in_boundsv(cell):
		return
	astar.set_point_solid(cell, blocks_path(cell))
	astar.set_point_weight_scale(cell, cost_of(cell))


# ---- 找路 ----

## 從 from 走到 to 的路（全局座標，第一個點是起點那格的中心）。
## 走不到的話，走到離 to 最近、走得到的地方；起點本身不能走就回傳空的
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var from_cell: Vector2i = cell_of(from)
	if not is_cell_walkable(from_cell):
		return PackedVector2Array()
	var local_path: PackedVector2Array = astar.get_point_path(from_cell, _clamp_to_region(cell_of(to)), true)
	var path: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in local_path:
		path.append(walls.to_global(point))
	return path


## 走完一條路要多少成本（像素 × 每一格的移動成本）：沼澤、要拆的牆都會算進去
func path_cost(path: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in path.size() - 1:
		total += path[i].distance_to(path[i + 1]) * cost_of(cell_of(path[i + 1]))
	return total


## 兩個位置之間有沒有路（塔防放塔前檢查會不會把路堵死）
func has_path(from: Vector2, to: Vector2) -> bool:
	var path: PackedVector2Array = find_path(from, to)
	return not path.is_empty() and cell_of(path[path.size() - 1]) == cell_of(to)


## 如果把 cell 堵起來，from 還走不走得到 to？（不會真的堵）
func would_block(cell: Vector2i, from: Vector2, to: Vector2) -> bool:
	if not is_cell_walkable(cell):
		return false
	astar.set_point_solid(cell, true)
	var blocked: bool = not has_path(from, to)
	astar.set_point_solid(cell, false)
	return blocked


# ---- 格子和座標 ----

## 全局座標在第幾格
func cell_of(global_position: Vector2) -> Vector2i:
	return walls.local_to_map(walls.to_local(global_position))


## 某一格中心的全局座標
func cell_center(cell: Vector2i) -> Vector2:
	return walls.to_global(walls.map_to_local(cell))


## 一格多大（像素）
func cell_size() -> Vector2:
	return astar.cell_size


func is_walkable(global_position: Vector2) -> bool:
	return is_cell_walkable(cell_of(global_position))


func is_cell_walkable(cell: Vector2i) -> bool:
	return astar.is_in_boundsv(cell) and not astar.is_point_solid(cell)


## 旁邊走得到的格子（照斜走設定），移動範圍會用
func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if is_cell_walkable(cell + d):
			result.append(cell + d)
	if diagonal == 0:
		return result
	for d: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var corner_free: bool = is_cell_walkable(cell + Vector2i(d.x, 0)) and is_cell_walkable(cell + Vector2i(0, d.y))
		if is_cell_walkable(cell + d) and (diagonal == 2 or corner_free):
			result.append(cell + d)
	return result


# ---- 會變的地圖 ----

## 用程式把一格設成擋路／不擋路（例如塔防放牆）
func set_blocked(cell: Vector2i, blocked: bool) -> void:
	_blocked[cell] = blocked
	_refresh_cell(cell)
	map_changed.emit()


## 取消 set_blocked()，回到 tile 原本的樣子
func clear_blocked(cell: Vector2i) -> void:
	_blocked.erase(cell)
	_refresh_cell(cell)
	map_changed.emit()


## 用程式設定一格的移動成本（例如殭屍覺得堅固的門很貴）
func set_cost(cell: Vector2i, cost: float) -> void:
	_costs[cell] = maxf(cost, 1.0)
	_refresh_cell(cell)
	map_changed.emit()


## 登記一個會變的障礙物（門）。節點要有：
##   屬性 blocks_path（bool）、path_cost（float）、signal obstacle_changed
## 放在 group「path_obstacles」的節點，setup() 時會自動登記，並對齊到格子中心
## 打得壞的障礙物（牆）：再加上 is_broken（bool）、damage(傷害)，PathFollower 走到前面會停下來打
func register_obstacle(node: Node2D) -> void:
	if node == null:
		return
	var cell: Vector2i = cell_of(node.global_position)
	node.global_position = cell_center(cell)
	if not _obstacles.has(cell):
		if _blocked.has(cell):
			_under_blocked[cell] = _blocked[cell]
		if _costs.has(cell):
			_under_costs[cell] = _costs[cell]
	_obstacles[cell] = node
	if node.has_signal("obstacle_changed") and not node.is_connected("obstacle_changed", _on_obstacle_changed.bind(node)):
		node.connect("obstacle_changed", _on_obstacle_changed.bind(node))
	_apply_obstacle(cell, node)


## 取消登記障礙物（例如陷阱消失了、牆被打破了）：那一格回到登記之前的樣子
func unregister_obstacle(node: Node2D) -> void:
	var cell: Vector2i = cell_of(node.global_position)
	if _obstacles.get(cell) != node:
		return
	_obstacles.erase(cell)
	_blocked.erase(cell)
	_costs.erase(cell)
	if _under_blocked.has(cell):
		_blocked[cell] = _under_blocked[cell]
	if _under_costs.has(cell):
		_costs[cell] = _under_costs[cell]
	_under_blocked.erase(cell)
	_under_costs.erase(cell)
	if node.has_signal("obstacle_changed") and node.is_connected("obstacle_changed", _on_obstacle_changed.bind(node)):
		node.disconnect("obstacle_changed", _on_obstacle_changed.bind(node))
	_refresh_cell(cell)
	map_changed.emit()


## 某一格的障礙物（沒有就是 null）
func obstacle_at(cell: Vector2i) -> Node2D:
	return _obstacles.get(cell, null)


func _apply_obstacle(cell: Vector2i, node: Node2D) -> void:
	_blocked[cell] = bool(node.get("blocks_path"))
	var cost: Variant = node.get("path_cost")
	if cost != null:
		_costs[cell] = maxf(float(cost), 1.0)
	_refresh_cell(cell)


func _on_obstacle_changed(node: Node2D) -> void:
	_apply_obstacle(cell_of(node.global_position), node)
	map_changed.emit()


func _clamp_to_region(cell: Vector2i) -> Vector2i:
	var region: Rect2i = astar.region
	return Vector2i(clampi(cell.x, region.position.x, region.end.x - 1), clampi(cell.y, region.position.y, region.end.y - 1))
