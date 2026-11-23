extends Node
## 視野、聲音、追逐 AI 的自動測試：
## 1. 視野三關（投影片 Slide 2）：A 太遠、B 在背後、C 隔著牆、D 正前方 → 只看到 D
##    關掉「牆會擋視線」看得到 C；關掉「檢查角度」看得到 B；玻璃看得穿、草叢看不穿、躲起來看不到
## 2. 聽覺：範圍內聽得到、範圍外聽不到、倍率、關掉耳朵
## 3. 追逐 AI：巡邏來回、聽到聲音去查看、看到 → 懷疑 → 追擊、追丟 → 搜尋 → 巡邏、
##    不記得最後位置 → 直接巡邏、追到就抓、看到躲進去會拖出來、沒看到就不會、關掉尋路會卡牆
##
## 在命令列執行：
##   godot --headless --path . res://addons/ngdc_pathfinding/tests/chase_ai_test.tscn

const ScriptErrors = preload("res://core/tests/scripts/script_error_counter.gd")
const TILESET: TileSet = preload("res://addons/ngdc_pathfinding/grid/tileset/tileset.tres")
const TestTarget: GDScript = preload("res://addons/ngdc_pathfinding/tests/scripts/test_target.gd")
const CHASE_SCENE: PackedScene = preload("res://addons/ngdc_pathfinding/chase_ai/chase_ai.tscn")
## 測試跑快一點（遊戲時間 3 倍速）
const TIME_SCALE: float = 3.0

var _failures: int = 0
## 腳本錯誤也算失敗（會讓測試函式中斷、跑不到 _expect）
var _script_errors: ScriptErrors = ScriptErrors.new()
var _level: Node2D
var _player: Node2D


func _ready() -> void:
	get_tree().current_scene = null
	Engine.time_scale = TIME_SCALE
	await _test_vision()
	await _test_hearing()
	await _test_patrol()
	await _test_investigate()
	await _test_suspicious_and_chase()
	await _test_lose_sight()
	await _test_catch()
	await _test_hide_seen()
	await _test_hide_unseen()
	await _test_no_pathfinding()
	Engine.time_scale = 1.0

	_failures += _script_errors.report()
	if _failures == 0:
		print("[追逐 AI 測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[追逐 AI 測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


# ---- 視野 ----

func _test_vision() -> void:
	print("--- 視野三關（Slide 2）---")
	# 殺手在 (5,5) 面向右；(8,4)～(8,6) 是牆、(5,8) 是玻璃、(5,2) 是草叢
	await _build([
		"..................",
		"..................",
		".....B............",
		"..................",
		"........#.........",
		"........#.........",
		"........#.........",
		"..................",
		".....G............",
		"..................",
	])
	var eye: Node2D = Node2D.new()
	eye.position = _center(Vector2i(5, 5))
	_level.add_child(eye)
	var vision: VisionSensor = VisionSensor.new()
	eye.add_child(vision)
	vision.view_distance = 260.0
	vision.view_angle = 90.0
	vision.facing = Vector2.RIGHT
	await _frames(2)

	var a: Vector2 = eye.position + Vector2(400, 0)               # 正前方但很遠
	var b: Vector2 = eye.position + Vector2(-60, 0)               # 背後很近
	var c: Vector2 = eye.position + Vector2(160, 0)               # 正前方，中間隔一面牆
	var d: Vector2 = eye.position + Vector2(80, -60)              # 前面不遠（往上 37 度）
	_expect(not await _sees(vision, a), "A 太遠：看不到")
	_expect(not await _sees(vision, b), "B 在背後：看不到")
	_expect(not await _sees(vision, c), "C 隔著牆：看不到")
	_expect(await _sees(vision, d), "D 正前方：看得到")

	vision.walls_block_sight = false
	_expect(await _sees(vision, c), "關掉「牆會擋視線」：隔牆也看得到 C")
	vision.walls_block_sight = true
	vision.check_angle = false
	_expect(await _sees(vision, b), "關掉「檢查角度」：背後的 B 也看得到")
	_expect(not await _sees(vision, c), "關掉角度，牆還是會擋")

	vision.facing = Vector2.DOWN
	_expect(await _sees(vision, _center(Vector2i(5, 9))), "玻璃看得穿")
	vision.facing = Vector2.UP
	_expect(not await _sees(vision, _center(Vector2i(5, 1))), "草叢看不穿")
	_expect(not await _sees(vision, _center(Vector2i(5, 2))), "躲在草叢裡看不到")
	vision.check_angle = true
	vision.facing = Vector2.RIGHT
	_player.global_position = d
	_player.set("is_hidden", true)
	_expect(not vision.can_see(_player), "躲起來：看不到")
	_player.set("is_hidden", false)

	var cone: PackedVector2Array = vision.get_cone_polygon()
	_expect(cone.size() == vision.cone_rays + 2, "視野錐：%d 條射線＋自己的位置" % vision.cone_rays)
	var shortest: float = INF
	for point: Vector2 in cone.slice(1):
		shortest = minf(shortest, point.length())
	_expect(shortest < 100.0, "視野錐被牆切掉（最短 %.0f px）" % shortest)


func _sees(vision: VisionSensor, at: Vector2) -> bool:
	_player.global_position = at
	await _frames(1)
	return vision.can_see(_player)


# ---- 聽覺 ----

func _test_hearing() -> void:
	print("--- 聲音 ---")
	var ear: Ear = Ear.new()
	ear.position = Vector2(100, 100)
	_level.add_child(ear)
	var heard: Array[Vector2] = []
	ear.heard.connect(func(at: Vector2) -> void: heard.append(at))
	SoundBus.emit_sound(Vector2(250, 100), 200.0)
	_expect(heard.size() == 1 and heard[0] == Vector2(250, 100), "範圍內：聽得到，知道聲音在哪")
	SoundBus.emit_sound(Vector2(400, 100), 200.0)
	_expect(heard.size() == 1, "範圍外：聽不到")
	ear.range_multiplier = 2.0
	SoundBus.emit_sound(Vector2(400, 100), 200.0)
	_expect(heard.size() == 2, "聽力倍率 2：遠一點也聽得到")
	ear.enabled = false
	SoundBus.emit_sound(Vector2(150, 100), 200.0)
	_expect(heard.size() == 2, "關掉耳朵：聽不到")
	ear.queue_free()


# ---- 殺手 ----

const OPEN_MAP: Array[String] = [
	"####################",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"####################",
]


func _test_patrol() -> void:
	print("--- 巡邏 ---")
	await _build(OPEN_MAP, Vector2i(18, 6))
	_player.set("is_hidden", true)                                      # 這個測試不要被看到
	var killer: ChaseAI = _spawn_killer(Vector2i(2, 1), 0.0, [Vector2i(8, 1), Vector2i(14, 1)])
	killer.patrol_wait = 0.2
	var reached_far: bool = false
	var came_back: bool = false
	for i: int in 600:
		await get_tree().physics_frame
		if killer.global_position.distance_to(_center(Vector2i(14, 1))) < 8.0:
			reached_far = true
		if reached_far and killer.global_position.x < _center(Vector2i(9, 1)).x:
			came_back = true
			break
	_expect(killer.state == ChaseAI.State.PATROL, "一直在巡邏")
	_expect(reached_far, "走到最後一個巡邏點")
	_expect(came_back, "來回：再走回來")


func _test_investigate() -> void:
	print("--- 聽到聲音 ---")
	await _build(OPEN_MAP, Vector2i(18, 6))
	_player.set("is_hidden", true)                                      # 這個測試不要被看到
	var killer: ChaseAI = _spawn_killer(Vector2i(2, 3), 180.0, [])
	await _frames(2)
	var sound_at: Vector2 = _center(Vector2i(10, 5))
	SoundBus.emit_sound(sound_at, 400.0)
	await _frames(1)
	_expect(killer.state == ChaseAI.State.INVESTIGATE, "聽到聲音 → 查看")
	await _wait_until(func() -> bool: return killer.global_position.distance_to(sound_at) < 10.0, 400)
	_expect(killer.global_position.distance_to(sound_at) < 10.0, "走到聲音的位置")
	await _wait_until(func() -> bool: return killer.state == ChaseAI.State.PATROL, 400)
	_expect(killer.state == ChaseAI.State.PATROL, "看一看沒東西 → 回去巡邏")

	killer.has_hearing = false
	await _frames(1)
	SoundBus.emit_sound(_center(Vector2i(4, 3)), 400.0)
	await _frames(1)
	_expect(killer.state == ChaseAI.State.PATROL, "關掉耳朵：聽到也不理")


func _test_suspicious_and_chase() -> void:
	print("--- 看到玩家 ---")
	await _build(OPEN_MAP, Vector2i(18, 6))
	_player.global_position = _center(Vector2i(16, 3))
	var killer: ChaseAI = _spawn_killer(Vector2i(2, 3), 0.0, [])
	killer.reaction_time = 1.0
	killer.view_distance = 600.0
	await _frames(3)
	_expect(killer.state == ChaseAI.State.SUSPICIOUS, "看到 → 懷疑（?）")
	var start: Vector2 = killer.global_position
	await _frames(10)                                             # 遊戲時間 0.5 秒
	_expect(killer.state == ChaseAI.State.SUSPICIOUS and killer.alert > 0.3, "懷疑時警戒值慢慢上升（%.0f%%）" % (killer.alert * 100.0))
	_expect(killer.global_position.distance_to(start) < 2.0, "懷疑時站著不動")
	await _wait_until(func() -> bool: return killer.state == ChaseAI.State.CHASE, 60)
	_expect(killer.state == ChaseAI.State.CHASE, "警戒值滿 → 追擊（!）")

	await _build(OPEN_MAP, Vector2i(18, 6))
	_player.global_position = _center(Vector2i(10, 3))
	killer = _spawn_killer(Vector2i(2, 3), 0.0, [])
	killer.reaction_time = 0.0
	await _frames(3)
	_expect(killer.state == ChaseAI.State.CHASE, "反應時間 0：一看到就追")


func _test_lose_sight() -> void:
	print("--- 追丟 ---")
	# 中間一道牆，玩家瞬間移到牆後面
	var map: Array[String] = OPEN_MAP.duplicate()
	map[2] = "#.........#........#"
	map[3] = "#.........#........#"
	map[4] = "#.........#........#"
	await _build(map, Vector2i(18, 6))
	_player.global_position = _center(Vector2i(8, 3))
	var killer: ChaseAI = _spawn_killer(Vector2i(2, 3), 0.0, [])
	killer.reaction_time = 0.0
	killer.search_time = 1.0
	await _frames(3)
	var last_seen: Vector2 = _player.global_position
	_player.global_position = _center(Vector2i(15, 3))
	await _frames(2)
	_expect(killer.state == ChaseAI.State.SEARCH, "看不到了 → 搜尋")
	await _wait_until(func() -> bool: return killer.global_position.distance_to(last_seen) < 12.0, 300)
	_expect(killer.global_position.distance_to(last_seen) < 12.0, "走到最後看到的位置")
	await _wait_until(func() -> bool: return killer.state == ChaseAI.State.PATROL, 300)
	_expect(killer.state == ChaseAI.State.PATROL, "找不到 → 回去巡邏")

	await _build(map, Vector2i(18, 6))
	_player.global_position = _center(Vector2i(8, 3))
	killer = _spawn_killer(Vector2i(2, 3), 0.0, [])
	killer.reaction_time = 0.0
	killer.remember_last_position = false
	await _frames(3)
	_player.global_position = _center(Vector2i(15, 3))
	await _frames(2)
	_expect(killer.state == ChaseAI.State.PATROL, "關掉「記住最後位置」：馬上回去巡邏")


func _test_catch() -> void:
	print("--- 追到就抓 ---")
	await _build(OPEN_MAP, Vector2i(18, 6))
	_player.global_position = _center(Vector2i(12, 4))
	var killer: ChaseAI = _spawn_killer(Vector2i(2, 3), 0.0, [])
	killer.reaction_time = 0.0
	killer.view_distance = 500.0
	await _wait_until(func() -> bool: return _was_caught(), 300)
	_expect(_was_caught(), "追到玩家：被抓")


func _test_hide_seen() -> void:
	print("--- 看到玩家躲進去 ---")
	await _build(OPEN_MAP, Vector2i(18, 6))
	var spot: Node2D = _spawn_spot(Vector2i(14, 3))
	_player.global_position = _center(Vector2i(13, 3))
	var killer: ChaseAI = _spawn_killer(Vector2i(2, 3), 0.0, [])
	killer.reaction_time = 3.0
	killer.view_distance = 500.0
	await _frames(5)
	_expect(killer.state == ChaseAI.State.SUSPICIOUS, "看到玩家（懷疑中）")
	_player.call("hide_in", spot)
	await _wait_until(func() -> bool: return _was_caught(), 400)
	_expect(_was_caught(), "親眼看到躲進去 → 被拖出來")


func _test_hide_unseen() -> void:
	print("--- 沒看到玩家躲進去 ---")
	await _build(OPEN_MAP, Vector2i(18, 6))
	var spot: Node2D = _spawn_spot(Vector2i(14, 3))
	_player.global_position = _center(Vector2i(13, 3))
	var killer: ChaseAI = _spawn_killer(Vector2i(2, 3), 180.0, [Vector2i(16, 3)])   # 面向左邊，看不到玩家
	killer.patrol_wait = 5.0
	await _frames(2)
	_player.call("hide_in", spot)
	await _frames(240)
	_expect(not _was_caught(), "背對著躲：殺手走過去也抓不到")


func _test_no_pathfinding() -> void:
	print("--- 關掉尋路 ---")
	var map: Array[String] = OPEN_MAP.duplicate()
	for row: int in range(1, 6):
		map[row] = "#.......#..........#"
	await _build(map, Vector2i(18, 6))
	_player.global_position = _center(Vector2i(12, 3))
	var killer: ChaseAI = _spawn_killer(Vector2i(3, 3), 0.0, [])
	killer.reaction_time = 0.0
	killer.walls_block_sight = false
	killer.view_distance = 600.0
	killer.use_pathfinding = false
	await _frames(120)
	_expect(killer.state == ChaseAI.State.CHASE, "隔牆看到、正在追")
	_expect(killer.global_position.x < 8 * 32, "直線衝：卡在牆上（x=%.0f）" % killer.global_position.x)


# ---- 工具 ----

## 用字串地圖建關卡：# 牆、G 玻璃、B 草叢、. 地板。玩家放在 player_cell
func _build(map: Array, player_cell: Vector2i = Vector2i(0, 0)) -> void:
	if _level != null:
		_level.queue_free()
		await _frames(1)
	_level = Node2D.new()
	add_child(_level)
	var floor_layer: TileMapLayer = TileMapLayer.new()
	floor_layer.tile_set = TILESET
	_level.add_child(floor_layer)
	var walls: TileMapLayer = TileMapLayer.new()
	walls.tile_set = TILESET
	_level.add_child(walls)
	for y: int in map.size():
		var row: String = map[y]
		for x: int in row.length():
			var cell: Vector2i = Vector2i(x, y)
			floor_layer.set_cell(cell, 0, Vector2i(0, 0))
			match row[x]:
				"#": walls.set_cell(cell, 0, Vector2i(2, 0))
				"G": walls.set_cell(cell, 0, Vector2i(3, 0))
				"B": walls.set_cell(cell, 0, Vector2i(4, 0))
	var grid: PathGrid = PathGrid.new()
	grid.auto_setup = false
	_level.add_child(grid)
	grid.setup(walls, floor_layer)
	_player = TestTarget.new()
	_player.position = _center(player_cell)
	_level.add_child(_player)
	await _frames(2)


func _spawn_killer(cell: Vector2i, angle: float, patrol: Array[Vector2i]) -> ChaseAI:
	var killer: ChaseAI = CHASE_SCENE.instantiate()
	killer.lose_when_caught = false
	killer.position = _center(cell)
	killer.start_angle = angle
	for point: Vector2i in patrol:
		var marker: Marker2D = Marker2D.new()
		marker.position = _center(point) - killer.position
		killer.add_child(marker)
	_level.add_child(killer)
	return killer


func _spawn_spot(cell: Vector2i) -> Node2D:
	var spot: Node2D = Node2D.new()
	spot.position = _center(cell)
	_level.add_child(spot)
	return spot


func _wait_until(condition: Callable, max_frames: int) -> void:
	for i: int in max_frames:
		if condition.call():
			return
		await get_tree().physics_frame


func _was_caught() -> bool:
	return int(_player.get("caught_count")) > 0


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * 32.0 + Vector2(16, 16)


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
