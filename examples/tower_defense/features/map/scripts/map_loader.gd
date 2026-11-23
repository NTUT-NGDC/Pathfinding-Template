@tool
class_name MapLoader
extends TerrainView
## 讀塔防地圖：鋪地板（照地圖大小）、畫出地形，告訴尋路地圖哪些格子是岩石（不能走、不能蓋）、
## 高地（怪不能走、可以蓋塔）、沼澤（怪走起來慢），再照地圖放出怪口和基地。編輯器裡打開關卡就看得到地形和位置。
##
## 用法：在檢查器把 maps/ 資料夾裡的地圖（.tres）拖進 Map 就換地圖。
## 地圖用 map_editor/map_editor.tscn 畫（打開按 F6）。
##
## 出怪口怎麼分給生怪器：
##   ・Spawners 只放一個：地圖上所有出怪口都給它（第 1 個放生怪器，其他的變成它的 More Spawn Points）
##   ・Spawners 放好幾個：第 1 個出怪口給第 1 個生怪器、第 2 個給第 2 個……（各自一份波次表）
## 基地：照地圖上的基地數量放 Base Scene，全部交給每個生怪器（怪走向路最短的那個）。

## 地圖準備好了（尋路地圖已經登記好岩石、沼澤）
signal map_ready()

## 生怪器（照上面的規則分出怪口）
@export var spawners: Array[Spawner] = []
## 基地長什麼樣子（地圖上有幾個基地就放幾個）
@export var base_scene: PackedScene = preload("res://examples/tower_defense/features/base/base.tscn")
## 地板那張 TileMapLayer（照地圖大小鋪地板）
@export var floor_layer: TileMapLayer
## 可以移動縮放的鏡頭（照地圖大小設邊界）
@export var camera: PanCamera
## 沼澤走一格等於走幾格
@export_range(1.0, 10.0, 0.5) var swamp_cost: float = 3.0

## 地圖編輯器按「試玩」時放在這裡，關卡就用這張，不用 Map 欄位那張
static var test_map: TDMap
## 是不是地圖編輯器裡的試玩
var is_test_play: bool = false
## 放好的基地
var bases: Array[Node2D] = []

const SPAWN_POINT: PackedScene = preload("res://examples/tower_defense/features/map/spawn_point.tscn")
## 地板用 TileSet 的哪一格
const FLOOR_TILE: Vector2i = Vector2i(0, 0)
## 鏡頭邊界比地圖多留的空間（左、上、右、下）：上面放文字、下面放按鈕
const CAMERA_MARGIN: Rect2 = Rect2(64, 48, 64, 128)


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("map_loader")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if test_map != null:
		map = test_map
		test_map = null
		is_test_play = true
	_apply.call_deferred()



func _apply() -> void:
	if map == null:
		return
	_build_floor()
	_place_bases()
	_place_spawns()
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	if grid == null:
		push_warning("MapLoader：場景裡找不到尋路地圖（PathGrid）。")
		return
	grid.setup(grid.walls, floor_layer if floor_layer != null else grid.floor_layer)   # 地板換了大小：重建尋路地圖
	for y: int in map.size.y:
		for x: int in map.size.x:
			var cell: Vector2i = Vector2i(x, y)
			var grid_cell: Vector2i = grid.cell_of(to_global(map.cell_center(cell)))
			if map.is_rock(cell) or map.is_high(cell):
				grid.set_blocked(grid_cell, true)                 # 岩石、高地：怪不能走
			elif map.is_swamp(cell):
				grid.set_cost(grid_cell, swamp_cost)
	if camera != null:
		var area: Rect2 = Rect2(global_position, Vector2(map.size * TDMap.CELL))
		area = area.grow_individual(CAMERA_MARGIN.position.x, CAMERA_MARGIN.position.y, CAMERA_MARGIN.size.x, CAMERA_MARGIN.size.y)
		camera.global_position = area.get_center()
		camera.set_limit_rect(area)
	var builder: Builder = get_tree().get_first_node_in_group("builder") as Builder
	if builder != null:
		builder.set_rules(map.tower_ground, map.wall_ground)      # 哪種地面能蓋塔、能蓋牆（迷宮型還是固定路線型）
	var group: BaseGroup = get_tree().get_first_node_in_group("base_group") as BaseGroup
	if group != null:
		group.refresh()                                           # 基地是剛剛才放的：血條照基地規則顯示
	map_ready.emit()


## 照地圖大小鋪地板
func _build_floor() -> void:
	if floor_layer == null:
		return
	floor_layer.clear()
	var origin: Vector2i = floor_layer.local_to_map(floor_layer.to_local(global_position))
	for y: int in map.size.y:
		for x: int in map.size.x:
			floor_layer.set_cell(origin + Vector2i(x, y), 0, FLOOR_TILE)


func _place_bases() -> void:
	for old: Variant in bases:
		if is_instance_valid(old):
			(old as Node2D).queue_free()
	bases.clear()
	for i: int in map.base_cells.size():
		var base: Node2D = base_scene.instantiate()
		base.name = "Base" if i == 0 else "Base%d" % (i + 1)
		get_parent().add_child(base)
		base.global_position = to_global(map.cell_center(map.base_cells[i]))
		bases.append(base)
	for spawner: Spawner in spawners:
		if spawner == null:
			continue
		spawner.target = bases[0] if not bases.is_empty() else null
		spawner.more_targets = bases.slice(1)


func _place_spawns() -> void:
	var valid: Array[Spawner] = []
	for spawner: Spawner in spawners:
		if spawner != null:
			valid.append(spawner)
			spawner.more_spawn_points = []
	if valid.is_empty() or map.spawn_cells.is_empty():
		return
	for i: int in map.spawn_cells.size():
		var at: Vector2 = to_global(map.cell_center(map.spawn_cells[i]))
		if i < valid.size():
			valid[i].global_position = at                         # 一個生怪器一個出怪口
			continue
		var point: Node2D = SPAWN_POINT.instantiate()             # 出怪口比生怪器多：多的給最後一個生怪器輪流用
		point.name = "SpawnPoint%d" % (i + 1)
		get_parent().add_child(point)
		point.global_position = at
		var owner_spawner: Spawner = valid[valid.size() - 1]
		owner_spawner.more_spawn_points.append(point)


## 某個位置（全域座標）在地圖上是什麼地形：TDMap.Kind 的值，-1＝空地（或不在地圖裡）
func terrain_at(at: Vector2) -> int:
	if map == null:
		return -1
	var cell: Vector2i = map.cell_at(to_local(at))
	if not map.has_cell(cell):
		return -1
	if map.is_rock(cell):
		return TDMap.Kind.ROCK
	if map.is_high(cell):
		return TDMap.Kind.HIGH
	if map.is_swamp(cell):
		return TDMap.Kind.SWAMP
	return -1


func _should_draw_floor() -> bool:
	return Engine.is_editor_hint()                                # 遊戲中地板由 TileMapLayer 畫；編輯器裡先畫個底色預覽


func _draw() -> void:
	super._draw()
	if not Engine.is_editor_hint() or map == null:
		return
	# 編輯器裡預覽出怪口、基地的位置（遊戲開始才會真的放上去）
	for cell: Vector2i in map.spawn_cells:
		draw_rect(Rect2(map.cell_center(cell) - Vector2(14, 14), Vector2(28, 28)), Color(0.9, 0.3, 0.3), false, 3.0)
	for cell: Vector2i in map.base_cells:
		draw_rect(Rect2(map.cell_center(cell) - Vector2(13, 13), Vector2(26, 26)), Color("4ab86a"))
