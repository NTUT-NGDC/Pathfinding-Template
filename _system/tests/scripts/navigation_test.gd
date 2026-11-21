extends Node
## 格子與障礙物的自動測試：
## 1. tile 擋不擋路：牆、玻璃擋；草叢、地板不擋
## 2. 門：關著可以走但比較貴；上鎖＝牆；鑰匙顏色要對才解得開；開著就不貴了
## 3. PathFollower：會繞路、遇到門會停下來開門（發出聲音）；關掉尋路會卡在牆上
## 4. 門口有人時關不起來
##
## 測試地圖（10×7 格，每格 32px）：
##   第 5 行是一整排牆，(5,3) 是門；(2,1) 玻璃、(2,4) 草叢
##   有些測試會在 (5,1) 開一個缺口當第二條路
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/navigation_test.tscn

const TILESET: TileSet = preload("res://game/level/tileset/tileset.tres")
const DOOR_SCENE: PackedScene = preload("res://game/level/door.tscn")
const SOURCE: int = 0
const WALL: Vector2i = Vector2i(2, 0)
const GLASS: Vector2i = Vector2i(3, 0)
const BUSH: Vector2i = Vector2i(4, 0)
const FLOOR: Vector2i = Vector2i(0, 0)
const DOOR_CELL: Vector2i = Vector2i(5, 3)
const GAP_CELL: Vector2i = Vector2i(5, 1)

var _failures: int = 0
var _walls: TileMapLayer
var _floor: TileMapLayer
var _grid: LevelGrid
var _door: Door
var _sounds: int = 0


func _ready() -> void:
	_build_level()
	SoundBus.sound_emitted.connect(func(_p: Vector2, _r: float) -> void: _sounds += 1)
	await get_tree().physics_frame

	_test_tiles()
	_test_door_in_grid()
	_test_door_weight()
	await _test_follower_through_door()
	await _test_follower_without_pathfinding()
	await _test_door_blocked()

	if _failures == 0:
		print("[格子與障礙物測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[格子與障礙物測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _build_level() -> void:
	_floor = TileMapLayer.new()
	_floor.tile_set = TILESET
	add_child(_floor)
	for x: int in 10:
		for y: int in 7:
			_floor.set_cell(Vector2i(x, y), SOURCE, FLOOR)

	_walls = TileMapLayer.new()
	_walls.tile_set = TILESET
	add_child(_walls)
	for y: int in 7:
		if y != DOOR_CELL.y:
			_walls.set_cell(Vector2i(5, y), SOURCE, WALL)
	_walls.set_cell(Vector2i(2, 1), SOURCE, GLASS)
	_walls.set_cell(Vector2i(2, 4), SOURCE, BUSH)

	_door = DOOR_SCENE.instantiate()
	_door.orientation = 1
	_door.position = _center(DOOR_CELL) + Vector2(5, -3)          # 故意放歪，應該會自動對齊
	add_child(_door)

	_grid = LevelGrid.new()
	add_child(_grid)
	_grid.setup(_walls, _floor)


func _test_tiles() -> void:
	print("--- tile 擋不擋路 ---")
	_expect(_grid.blocks_path(Vector2i(5, 0)), "牆擋路")
	_expect(_grid.blocks_path(Vector2i(2, 1)), "玻璃擋路")
	_expect(not _grid.blocks_path(Vector2i(2, 4)), "草叢不擋路")
	_expect(not _grid.blocks_path(Vector2i(1, 1)), "地板不擋路")
	_expect(not _grid.is_walkable(_center(Vector2i(20, 3))), "地圖外面走不到")
	_expect(_grid.cell_of(Vector2(170, 100)) == Vector2i(5, 3), "座標 → 格子")
	_expect(_door.global_position == _center(DOOR_CELL), "門自動對齊格子中心")


func _test_door_in_grid() -> void:
	print("--- 門在格子裡 ---")
	var from: Vector2 = _center(Vector2i(1, 3))
	var to: Vector2 = _center(Vector2i(8, 3))
	var path: PackedVector2Array = _grid.find_path(from, to)
	_expect(_ends_at(path, Vector2i(8, 3)) and _passes(path, DOOR_CELL), "門關著：還是可以穿過門走過去")

	_door.locked = true
	_door.state_changed.emit(_door)
	path = _grid.find_path(from, to)
	_expect(not _grid.is_walkable(_center(DOOR_CELL)), "上鎖的門＝牆")
	_expect(not _ends_at(path, Vector2i(8, 3)), "上鎖：走不過去（只走到最近的地方）")
	_expect(not path.is_empty() and _grid.cell_of(path[path.size() - 1]).x == 4, "上鎖：停在門前")

	_expect(not _door.open(), "上鎖的門打不開")
	_expect(not _door.unlock("藍"), "顏色不對的鑰匙解不開")
	_expect(_door.unlock("紅"), "顏色對的鑰匙解得開")
	_expect(not _door.is_open, "解鎖後還是關著")
	path = _grid.find_path(from, to)
	_expect(_ends_at(path, Vector2i(8, 3)), "解鎖後又走得過去")


func _test_door_weight() -> void:
	print("--- 關著的門比較貴 ---")
	_walls.erase_cell(GAP_CELL)                                   # 開一個缺口當第二條路
	_grid.setup(_walls, _floor)
	var from: Vector2 = _center(Vector2i(1, 3))
	var to: Vector2 = _center(Vector2i(8, 3))
	var path: PackedVector2Array = _grid.find_path(from, to)
	_expect(_passes(path, GAP_CELL) and not _passes(path, DOOR_CELL), "門關著：寧願繞一點路走缺口")
	_door.open()
	path = _grid.find_path(from, to)
	_expect(_passes(path, DOOR_CELL), "門開著：直接穿過門")
	_door.close()
	_walls.set_cell(GAP_CELL, SOURCE, WALL)                       # 補回去
	_grid.setup(_walls, _floor)


func _test_follower_through_door() -> void:
	print("--- PathFollower 穿過門 ---")
	var body: CharacterBody2D = _make_body(_center(Vector2i(1, 5)))
	var follower: PathFollower = body.get_node("PathFollower")
	follower.speed = 300.0
	follower.door_open_time = 0.3
	var arrived: Array[bool] = [false]
	follower.arrived.connect(func() -> void: arrived[0] = true)
	var sounds_before: int = _sounds
	var target: Vector2 = _center(Vector2i(8, 1)) + Vector2(5, 3)
	follower.go_to(target)

	var saw_waiting: bool = false
	for i: int in 300:
		await get_tree().physics_frame
		if follower.is_opening_door():
			saw_waiting = true
		if arrived[0]:
			break
	_expect(saw_waiting, "走到門前會停下來開門")
	_expect(_door.is_open, "門被打開了")
	_expect(_sounds > sounds_before, "開門發出聲音")
	_expect(arrived[0], "走到目標")
	_expect(body.global_position.distance_to(target) < 6.0, "停在確切的目標位置（差 %.1f px）" % body.global_position.distance_to(target))
	body.queue_free()
	await get_tree().physics_frame
	_door.close()


func _test_follower_without_pathfinding() -> void:
	print("--- 關掉尋路 ---")
	var body: CharacterBody2D = _make_body(_center(Vector2i(2, 0)))
	var follower: PathFollower = body.get_node("PathFollower")
	follower.speed = 300.0
	follower.use_pathfinding = false
	var arrived: Array[bool] = [false]
	follower.arrived.connect(func() -> void: arrived[0] = true)
	follower.go_to(_center(Vector2i(8, 0)))
	for i: int in 90:
		await get_tree().physics_frame
	_expect(not arrived[0], "直線走過不去")
	_expect(body.global_position.x < 5 * 32, "卡在牆的左邊（x=%.0f）" % body.global_position.x)
	body.queue_free()
	await get_tree().physics_frame


func _test_door_blocked() -> void:
	print("--- 門口有人 ---")
	_door.open()
	var body: CharacterBody2D = _make_body(_center(DOOR_CELL))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(not _door.close(), "有人站在門口：關不起來")
	body.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(_door.close(), "人走開：關得起來")


## 做一個像殺手的角色：圓形碰撞（半徑 12）、第 4 層（殺手）、撞第 1 層（擋路）
func _make_body(at: Vector2) -> CharacterBody2D:
	var body: CharacterBody2D = CharacterBody2D.new()
	body.collision_layer = 8
	body.collision_mask = 1
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	body.add_child(shape)
	var follower: PathFollower = PathFollower.new()
	follower.name = "PathFollower"
	body.add_child(follower)
	body.position = at
	add_child(body)
	return body


func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * 32.0 + Vector2(16, 16)


func _passes(path: PackedVector2Array, cell: Vector2i) -> bool:
	for point: Vector2 in path:
		if _grid.cell_of(point) == cell:
			return true
	return false


func _ends_at(path: PackedVector2Array, cell: Vector2i) -> bool:
	return not path.is_empty() and _grid.cell_of(path[path.size() - 1]) == cell


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
