extends Node
## 尋路積木的自動測試：
## 1. 尋路地圖：牆、玻璃擋路，草叢、地板不擋；沒畫地板的地方不能走；沼澤成本 3；斜走模式
## 2. 會變的地圖：set_blocked、門（障礙物）上鎖／關著比較貴／打開；would_block；map_changed
## 3. 跟著路徑走：繞牆、停下來開門、關掉尋路會卡牆、follow 追節點、地圖變了自動改路、非 CharacterBody2D 也能走
## 4. 移動範圍：移動力 3 走得到的格子；沼澤吃比較多移動力；點格子發 tile_selected
## 5. 生怪器：照波次出怪、怪走到目標發 reached_goal、打死全部發 all_cleared
## 6. 點擊移動：點選、框選、下指令
##
## 在命令列執行：
##   godot --headless --path . res://addons/ngdc_pathfinding/tests/pathfinding_test.tscn

const ScriptErrors = preload("res://core/tests/scripts/script_error_counter.gd")
const TILESET: TileSet = preload("res://addons/ngdc_pathfinding/grid/tileset/tileset.tres")
const TestDoor: GDScript = preload("res://addons/ngdc_pathfinding/tests/scripts/test_door.gd")
const WALKER_SCENE: PackedScene = preload("res://addons/ngdc_pathfinding/spawner/walker.tscn")
const WOOD: Vector2i = Vector2i(0, 0)
const WALL: Vector2i = Vector2i(2, 0)
const GLASS: Vector2i = Vector2i(3, 0)
const BUSH: Vector2i = Vector2i(4, 0)
const SWAMP: Vector2i = Vector2i(5, 0)
const TIME_SCALE: float = 3.0

var _failures: int = 0
## 腳本錯誤也算失敗（會讓測試函式中斷、跑不到 _expect）
var _script_errors: ScriptErrors = ScriptErrors.new()
var _level: Node2D
var _grid: PathGrid
var _walls: TileMapLayer
var _floor: TileMapLayer


func _ready() -> void:
	get_tree().current_scene = null
	Engine.time_scale = TIME_SCALE
	await _test_grid()
	await _test_dynamic_map()
	await _test_follower()
	await _test_move_range()
	await _test_spawner()
	await _test_click_mover()
	Engine.time_scale = 1.0
	_failures += _script_errors.report()
	if _failures == 0:
		print("[尋路積木測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[尋路積木測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


# 地圖：# 牆 G 玻璃 B 草叢 ~ 沼澤 . 地板 空白＝房子外面
const MAP: Array[String] = [
	"############",
	"#....#.....#",
	"#.G..#..~~.#",
	"#....#..~~.#",
	"#.B........#",
	"#....#.....#",
	"############",
]


func _test_grid() -> void:
	print("--- 尋路地圖 ---")
	await _build(MAP)
	_expect(_grid.blocks_path(Vector2i(0, 0)), "牆擋路")
	_expect(_grid.blocks_path(Vector2i(2, 2)), "玻璃擋路")
	_expect(not _grid.blocks_path(Vector2i(2, 4)), "草叢不擋路")
	_expect(not _grid.blocks_path(Vector2i(1, 1)), "地板不擋路")
	_expect(not _grid.is_walkable(_center(Vector2i(20, 3))), "沒畫地板的地方不能走")
	_expect(is_equal_approx(_grid.cost_of(Vector2i(8, 2)), 3.0) and is_equal_approx(_grid.cost_of(Vector2i(1, 1)), 1.0), "沼澤成本 3、地板成本 1")
	var path: PackedVector2Array = _grid.find_path(_center(Vector2i(1, 2)), _center(Vector2i(10, 2)))
	_expect(_ends_at(path, Vector2i(10, 2)) and _passes(path, Vector2i(5, 4)), "繞過牆，從缺口 (5,4) 過去")
	path = _grid.find_path(_center(Vector2i(7, 2)), _center(Vector2i(10, 3)))
	_expect(not _passes(path, Vector2i(8, 2)) and not _passes(path, Vector2i(9, 3)), "沼澤比較貴：寧願繞開")
	_expect(_grid.neighbors(Vector2i(7, 4)).size() == 8, "空地：8 個方向都走得到（%d）" % _grid.neighbors(Vector2i(7, 4)).size())
	_expect(_grid.neighbors(Vector2i(1, 1)).size() == 2, "(1,1) 斜下方是玻璃：不能斜走過去，只剩 2 個鄰居（%d）" % _grid.neighbors(Vector2i(1, 1)).size())


func _test_dynamic_map() -> void:
	print("--- 會變的地圖 ---")
	await _build(MAP)
	var changes: Array[int] = [0]
	_grid.map_changed.connect(func() -> void: changes[0] += 1)
	var from: Vector2 = _center(Vector2i(1, 2))
	var to: Vector2 = _center(Vector2i(10, 2))
	_expect(_grid.would_block(Vector2i(5, 4), from, to), "堵住缺口 (5,4) 會讓路不通")
	_expect(_grid.is_cell_walkable(Vector2i(5, 4)), "would_block 只是試試看，不會真的堵")
	_expect(not _grid.would_block(Vector2i(3, 3), from, to), "堵 (3,3) 不影響")
	_grid.set_blocked(Vector2i(5, 4), true)
	_expect(not _grid.has_path(from, to) and changes[0] == 1, "set_blocked：路不通、發 map_changed")
	_grid.clear_blocked(Vector2i(5, 4))
	_expect(_grid.has_path(from, to), "clear_blocked：又通了")

	var door: Node2D = TestDoor.new()
	door.position = _center(Vector2i(5, 4)) + Vector2(6, -5)       # 故意放歪
	_level.add_child(door)
	_grid.register_obstacle(door)
	_expect(door.global_position == _center(Vector2i(5, 4)), "門自動對齊格子中心")
	_expect(_grid.obstacle_at(Vector2i(5, 4)) == door, "obstacle_at 找得到門")
	_expect(is_equal_approx(_grid.astar.get_point_weight_scale(Vector2i(5, 4)), 4.0) and _grid.has_path(from, to), "關著的門：走得過去但比較貴")
	door.call("set_locked", true)
	_expect(not _grid.has_path(from, to), "上鎖：走不過去")
	door.call("set_locked", false)
	door.call("open")
	_expect(is_equal_approx(_grid.astar.get_point_weight_scale(Vector2i(5, 4)), 1.0), "門打開：不貴了")

	# 拿掉障礙物：底下原本的成本還在
	_grid.set_cost(Vector2i(3, 3), 3.0)
	var on_swamp: Node2D = TestDoor.new()
	on_swamp.position = _center(Vector2i(3, 3))
	_level.add_child(on_swamp)
	_grid.register_obstacle(on_swamp)
	var with_door: float = _grid.cost_of(Vector2i(3, 3))
	_grid.unregister_obstacle(on_swamp)
	_expect(with_door == 4.0 and _grid.cost_of(Vector2i(3, 3)) == 3.0, "拿掉障礙物：底下的沼澤成本還在（%.0f → %.0f）" % [with_door, _grid.cost_of(Vector2i(3, 3))])
	on_swamp.queue_free()


func _test_follower() -> void:
	print("--- 跟著路徑走 ---")
	await _build(MAP)
	var door: Node2D = TestDoor.new()
	door.position = _center(Vector2i(5, 4))
	_level.add_child(door)
	_grid.register_obstacle(door)
	var body: CharacterBody2D = _make_body(_center(Vector2i(1, 2)))
	var follower: PathFollower = body.get_node("PathFollower")
	follower.speed = 300.0
	follower.door_open_time = 0.3
	var arrived: Array[bool] = [false]
	follower.arrived.connect(func() -> void: arrived[0] = true)
	var target: Vector2 = _center(Vector2i(10, 4)) + Vector2(4, 3)
	follower.go_to(target)
	var waited: bool = false
	for i: int in 300:
		await get_tree().physics_frame
		waited = waited or follower.is_opening_door()
		if arrived[0]:
			break
	_expect(waited and bool(door.get("is_open")), "走到門前停下來開門")
	_expect(arrived[0] and body.global_position.distance_to(target) < 6.0, "走到確切的目標位置")

	follower.use_pathfinding = false
	arrived[0] = false
	follower.go_to(_center(Vector2i(1, 2)))
	await _frames(60)
	follower.use_pathfinding = true
	_expect(not arrived[0], "關掉尋路：直線走過不去")

	# 追節點；地圖變了自動改路
	var mover: Node2D = Node2D.new()
	mover.position = _center(Vector2i(1, 5))
	_level.add_child(mover)
	var walker: PathFollower = PathFollower.new()
	mover.add_child(walker)
	walker.speed = 200.0
	var goal: Node2D = Node2D.new()
	goal.position = _center(Vector2i(10, 5))
	_level.add_child(goal)
	walker.follow(goal)
	await _frames(2)
	_expect(_path_passes(walker.path, Vector2i(5, 4)), "一開始的路經過缺口 (5,4)")
	_grid.set_blocked(Vector2i(5, 4), true)
	_grid.set_blocked(Vector2i(5, 5), true)
	await _frames(1)
	_expect(walker.path.is_empty() or not _path_passes(walker.path, Vector2i(5, 4)), "地圖變了：自動重算路徑")
	_grid.clear_blocked(Vector2i(5, 5))
	await _wait_until(func() -> bool: return mover.global_position.distance_to(goal.global_position) < 40.0, 300)
	_expect(mover.global_position.distance_to(goal.global_position) < 40.0, "Node2D（不是 CharacterBody2D）也能追到節點")
	goal.position = _center(Vector2i(1, 1))
	await _wait_until(func() -> bool: return mover.global_position.distance_to(goal.global_position) < 40.0, 400)
	_expect(mover.global_position.distance_to(goal.global_position) < 40.0, "目標移動了：繼續追過去")


func _test_move_range() -> void:
	print("--- 移動範圍 ---")
	await _build([
		"#########",
		"#.......#",
		"#.......#",
		"#..~....#",
		"#.......#",
		"#########",
	])
	_grid.diagonal = 0
	_grid.setup(_walls, _floor)
	var range_node: MoveRange = MoveRange.new()
	_level.add_child(range_node)
	range_node.show_from(_center(Vector2i(1, 1)), 3.0)
	_expect(range_node.has_cell(Vector2i(4, 1)) and not range_node.has_cell(Vector2i(5, 1)), "移動力 3：往右走到第 3 格，第 4 格走不到")
	_expect(range_node.has_cell(Vector2i(3, 2)) and not range_node.has_cell(Vector2i(4, 2)), "不斜走：(3,2) 要 3 步走得到、(4,2) 要 4 步走不到")
	_expect(not range_node.has_cell(Vector2i(3, 3)), "沼澤成本 3：(3,3) 要花 3+3 走不到")
	range_node.show_from(_center(Vector2i(3, 2)), 3.0)
	_expect(range_node.has_cell(Vector2i(3, 3)) and not range_node.has_cell(Vector2i(3, 4)), "從旁邊踩進沼澤剛好 3 點，再往前就沒了")
	var selected: Array[Vector2i] = []
	range_node.tile_selected.connect(func(cell: Vector2i) -> void: selected.append(cell))
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _center(Vector2i(4, 2))
	click.global_position = click.position
	range_node._unhandled_input(click)
	_expect(selected.size() == 1, "點範圍裡的格子：發出 tile_selected")
	range_node.clear()
	_expect(range_node.cells.is_empty(), "clear：收起來")


func _test_spawner() -> void:
	print("--- 生怪器 ---")
	await _build(MAP)
	var base: Node2D = Node2D.new()
	base.position = _center(Vector2i(10, 2))
	_level.add_child(base)
	var spawner: Spawner = Spawner.new()
	spawner.position = _center(Vector2i(1, 2))
	spawner.target = base
	spawner.start_delay = 0.1
	spawner.lose_when_reached = false
	spawner.win_when_cleared = false
	var wave: Wave = Wave.new()
	wave.count = 3
	wave.interval = 0.2
	wave.speed = 200.0
	spawner.waves = [wave]
	var started: Array[int] = []
	var reached: Array[int] = [0]
	var cleared: Array[bool] = [false]
	spawner.wave_started.connect(func(n: int) -> void: started.append(n))
	spawner.reached_goal.connect(func(_e: Node2D) -> void: reached[0] += 1)
	spawner.all_cleared.connect(func() -> void: cleared[0] = true)
	_level.add_child(spawner)
	await _wait_until(func() -> bool: return get_tree().get_nodes_in_group("enemies").size() >= 1, 60)
	_expect(started == [1], "第 1 波開始")
	await _wait_until(func() -> bool: return cleared[0], 600)
	_expect(reached[0] == 3, "3 隻都走到基地（%d）" % reached[0])
	_expect(cleared[0], "全部出完、場上沒怪：all_cleared")

	# 打死的怪也算
	var walker: Walker = WALKER_SCENE.instantiate()
	walker.max_health = 5.0
	_level.add_child(walker)
	var died: Array[bool] = [false]
	walker.died.connect(func(_w: Walker) -> void: died[0] = true)
	walker.damage(2.0)
	_expect(not died[0] and is_equal_approx(walker.health, 3.0), "Walker 扣血")
	walker.damage(5.0)
	_expect(died[0], "Walker 血扣到 0：died")


func _test_click_mover() -> void:
	print("--- 點擊移動 ---")
	await _build(MAP)
	var mover: ClickMover = ClickMover.new()
	_level.add_child(mover)
	var units: Array[Node2D] = []
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 5)]:
		var unit: Node2D = Node2D.new()
		unit.position = _center(cell)
		unit.add_to_group("units")
		var follower: PathFollower = PathFollower.new()
		unit.add_child(follower)
		follower.speed = 300.0
		_level.add_child(unit)
		units.append(unit)
	_expect(mover.unit_at(_center(Vector2i(2, 1)) + Vector2(5, 5)) == units[1], "點到角色")
	_expect(mover.unit_at(_center(Vector2i(4, 4))) == null, "點到空地：沒有角色")
	mover.select(mover.units_in_rect(Rect2(_center(Vector2i(1, 1)) - Vector2(20, 20), Vector2(90, 40))))
	_expect(mover.selected.size() == 2, "框選：選到上面兩個（%d）" % mover.selected.size())
	mover.command(_center(Vector2i(8, 4)))
	await _wait_until(func() -> bool: return units[0].global_position.distance_to(_center(Vector2i(8, 4))) < 30.0, 300)
	_expect(units[0].global_position.distance_to(_center(Vector2i(8, 4))) < 30.0, "下指令：選到的角色走過去")
	_expect(units[2].global_position == _center(Vector2i(3, 5)), "沒選到的不動")
	mover.allow_multi_select = false
	mover.select(units)
	_expect(mover.selected.size() == 1, "不能多選：只留一個")
	mover.allow_multi_select = true
	mover.select(units)
	units[0].free()                                               # 選到的角色被刪掉（例如被打死）
	await _frames(3)
	_expect(mover.selected.size() == 2, "選到的角色被刪掉：從選取裡拿掉（%d）" % mover.selected.size())


# ---- 工具 ----

func _build(map: Array) -> void:
	if _level != null:
		_level.queue_free()
		await _frames(1)
	_level = Node2D.new()
	add_child(_level)
	_floor = TileMapLayer.new()
	_floor.tile_set = TILESET
	_level.add_child(_floor)
	_walls = TileMapLayer.new()
	_walls.tile_set = TILESET
	_level.add_child(_walls)
	for y: int in map.size():
		var row: String = map[y]
		for x: int in row.length():
			var cell: Vector2i = Vector2i(x, y)
			match row[x]:
				" ": continue
				"~": _floor.set_cell(cell, 0, SWAMP)
				_: _floor.set_cell(cell, 0, WOOD)
			match row[x]:
				"#": _walls.set_cell(cell, 0, WALL)
				"G": _walls.set_cell(cell, 0, GLASS)
				"B": _walls.set_cell(cell, 0, BUSH)
	_grid = PathGrid.new()
	_grid.auto_setup = false
	_level.add_child(_grid)
	_grid.setup(_walls, _floor)
	await _frames(2)


func _make_body(at: Vector2) -> CharacterBody2D:
	var body: CharacterBody2D = CharacterBody2D.new()
	body.collision_layer = 8
	body.collision_mask = 1
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 11.0
	shape.shape = circle
	body.add_child(shape)
	var follower: PathFollower = PathFollower.new()
	follower.name = "PathFollower"
	body.add_child(follower)
	body.position = at
	_level.add_child(body)
	return body


func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * 32.0 + Vector2(16, 16)


func _passes(path: PackedVector2Array, cell: Vector2i) -> bool:
	return _path_passes(path, cell)


func _path_passes(path: PackedVector2Array, cell: Vector2i) -> bool:
	for point: Vector2 in path:
		if _grid.cell_of(point) == cell:
			return true
	return false


func _ends_at(path: PackedVector2Array, cell: Vector2i) -> bool:
	return not path.is_empty() and _grid.cell_of(path[path.size() - 1]) == cell


func _wait_until(condition: Callable, max_frames: int) -> void:
	for i: int in max_frames:
		if condition.call():
			return
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
