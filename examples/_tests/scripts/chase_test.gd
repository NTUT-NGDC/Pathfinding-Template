extends "res://examples/_tests/scripts/example_test.gd"
## 追逐範例的自動測試：
## 寶物 3 個＋發電機、都完成出口才打開、走進出口就贏；開門條件（全部／指定／數量／一開始就開）；
##    守衛被聲音引開後會走回崗位；站在門口按 E 會退出去把門關上；
##    捕獸夾（AI 繞開、夾住、AI 追丟會放）、警報（AI 過來、冷卻）、瓶子（撿、丟、撞牆、引開守衛）；
##    發電機會發出聲音；鏡頭固定在畫面中間；被追逐 AI 碰到就輸；上鎖的門要鑰匙
##
## 在命令列執行：
##   godot --headless --fixed-fps 60 --path . res://examples/_tests/chase_test.tscn

const CHASE: String = "res://examples/chase/levels/chase.tscn"


func _run() -> void:
	await _test_chase()
	await _test_chase_editor()


func _test_chase() -> void:
	print("--- 追逐 ---")
	await _load(CHASE)
	_freeze_group("chase_ai")
	var player: Player = get_tree().get_first_node_in_group("player")
	var exit: Exit = get_tree().get_first_node_in_group("exits")
	var treasures: Array[Pickup] = []
	var key: Pickup = null
	for node: Node in get_tree().get_nodes_in_group("pickups"):
		var pickup: Pickup = node as Pickup
		if pickup.kind == "寶物":
			treasures.append(pickup)
		else:
			key = pickup
	_expect(treasures.size() == 3 and key != null, "3 個寶物＋1 把鑰匙")
	_expect(get_tree().get_nodes_in_group("chase_ai").size() == 2, "2 隻追逐 AI")
	_expect(exit != null and not exit.is_open, "一開始出口關著")
	var generator: TaskPoint = _level.get_node("Generator")
	var counter: Label = _level.get_node("HUD/Info/ObjectiveCounter")
	_expect(counter.text == "寶物 0/3　發電機 0/1", "畫面顯示「寶物 0/3　發電機 0/1」（%s）" % counter.text)
	var camera: FollowCamera = _level.get_node("FollowCamera")
	_expect(camera.is_current() and camera.get_screen_center_position().is_equal_approx(Vector2(640, 360)), "鏡頭：固定在畫面中間")
	var locked: Node2D = null
	for door: Node in get_tree().get_nodes_in_group("path_obstacles"):
		if door.get("locked") == true:
			locked = door
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	_expect(locked != null and not grid.is_cell_walkable(grid.cell_of(locked.global_position)), "上鎖的門：尋路地圖當牆")

	for treasure: Pickup in treasures:
		treasure.call("_on_interacted", player)
	await _frames(2)
	_expect(not exit.is_open and counter.text.begins_with("寶物 3/3"), "撿完 3 個寶物：發電機還沒修，出口不開")
	var heard: Array[float] = []
	SoundBus.instance().sound_emitted.connect(func(_p: Vector2, radius: float) -> void: heard.append(radius))
	generator.call("_work", player, 2.0)
	_expect(not generator.is_done and heard.size() == 1, "修發電機：還沒修好、發出聲音")
	generator.call("_work", player, generator.hold_time)
	await _frames(2)
	_expect(generator.is_done and exit.is_open and counter.text.contains("發電機 1/1"), "修好發電機：出口打開（%s）" % counter.text)
	player.global_position = exit.global_position + Vector2(0, -24)
	await _frames(2)
	Input.action_press("move_down")
	await _wait_until(func() -> bool: return GameFlow.is_finished(), 120)
	Input.action_release("move_down")
	_expect(GameFlow.is_finished() and _result_title().contains("勝利"), "走進出口：勝利畫面")

	await _test_open_conditions()
	await _test_guard_returns()
	await _test_close_door_in_doorway()
	await _test_trap()
	await _test_trap_dropper()
	await _test_alarm()
	await _test_bottle()

	await _load(CHASE)
	player = get_tree().get_first_node_in_group("player")
	var killer: ChaseAI = _level.get_node("ChaseAI")
	_level.get_node("Guard").process_mode = Node.PROCESS_MODE_DISABLED
	killer.reaction_time = 0.0
	player.global_position = killer.global_position + Vector2(60, 0)
	killer.start_angle = 0.0
	await _wait_until(func() -> bool: return GameFlow.is_finished(), 200)
	_expect(GameFlow.is_finished() and _result_title().contains("失敗"), "被追逐 AI 碰到：失敗畫面")


func _test_open_conditions() -> void:
	await _load(CHASE)
	_freeze_group("chase_ai")
	var player: Player = get_tree().get_first_node_in_group("player")
	var exit: Exit = get_tree().get_first_node_in_group("exits")
	var generator: TaskPoint = _level.get_node("Generator")
	var treasure: Pickup = _level.get_node("Treasure")
	var counter: Label = _level.get_node("HUD/Info/ObjectiveCounter")
	exit.open_when = 1                                            # 指定：只要發電機
	exit.targets = [generator]
	exit.call("_collect")
	await _frames(2)
	_expect(not exit.is_open and counter.text == "發電機 0/1", "指定：只看清單裡的發電機（%s）" % counter.text)
	generator.hold_time = 0.0
	generator.call("_work", player, 0.0)
	await _frames(2)
	_expect(exit.is_open, "指定：發電機修好就開（寶物沒撿也開）")

	await _load(CHASE)
	_freeze_group("chase_ai")
	player = get_tree().get_first_node_in_group("player")
	exit = get_tree().get_first_node_in_group("exits")
	treasure = _level.get_node("Treasure")
	counter = _level.get_node("HUD/Info/ObjectiveCounter")
	exit.open_when = 2                                            # 數量：4 個目標裡完成 1 個
	exit.needed = 1
	exit.call("_collect")
	await _frames(2)
	_expect(not exit.is_open and counter.text == "目標 0/1", "數量：顯示「目標 0/1」（%s）" % counter.text)
	treasure.call("_on_interacted", player)
	await _frames(2)
	_expect(exit.is_open, "數量：撿 1 個寶物就開")

	await _load(CHASE)
	exit = get_tree().get_first_node_in_group("exits")
	exit.open_when = 3
	exit.call("_collect")
	await _frames(2)
	_expect(exit.is_open, "一開始就開")


## 玩家站在門那格按 E：門關上，玩家被推到比較近的那一側
func _test_close_door_in_doorway() -> void:
	await _load(CHASE)
	_freeze_group("chase_ai")
	var player: Player = get_tree().get_first_node_in_group("player")
	var door: Door = null
	for node: Node in get_tree().get_nodes_in_group("path_obstacles"):
		if node is Door and not (node as Door).locked:
			door = node
			break
	door.open()
	var axis: Vector2 = Vector2.DOWN if door.orientation == 0 else Vector2.RIGHT
	player.global_position = door.global_position - axis * 4.0      # 站在門那格，稍微偏上（左）
	await _frames(3)
	_expect(door.is_blocked(), "門口：偵測得到玩家")
	door.call("_on_interacted", player)
	var offset: Vector2 = player.global_position - door.global_position
	_expect(not door.is_open and offset.is_equal_approx(-axis * Door.STEP_OUT_DISTANCE), "站在門口按 E：門關上、玩家退到比較近的那一側（%s）" % offset)
	await _frames(3)
	_expect(not door.is_blocked() and player.global_position.distance_to(door.global_position + offset) < 1.0, "退出去之後沒有卡在門裡")


## 捕獸夾：AI 會繞開；玩家踩到被夾住、發出聲音；夾完消失，那一格回到原本的成本
func _test_trap() -> void:
	await _load(CHASE)
	_freeze_group("chase_ai")
	var player: Player = get_tree().get_first_node_in_group("player")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var trap: Trap = _level.get_node("Trap")
	var cell: Vector2i = grid.cell_of(trap.global_position)
	_expect(grid.cost_of(cell) == Trap.AVOID_COST, "捕獸夾：尋路地圖登記成很貴的格子（%.0f）" % grid.cost_of(cell))
	var path: PackedVector2Array = grid.find_path(grid.cell_center(cell + Vector2i.LEFT), grid.cell_center(cell + Vector2i.RIGHT))
	_expect(not path.is_empty() and not path.has(grid.cell_center(cell)), "捕獸夾：AI 的路繞開它")
	var heard: Array[float] = []
	SoundBus.instance().sound_emitted.connect(func(_p: Vector2, radius: float) -> void: heard.append(radius))
	player.global_position = trap.global_position
	await _frames(3)
	_expect(trap.is_closed and player.stun_time > 0.0 and heard.has(trap.sound_radius), "踩到捕獸夾：被夾住、發出聲音")
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	_expect(player.global_position.distance_to(trap.global_position) < 1.0, "被夾住：按方向鍵也不能動")
	var trap_ref: WeakRef = weakref(trap)                         # 夾子會被刪掉，lambda 不能直接抓它
	await _wait_until(func() -> bool: return trap_ref.get_ref() == null, 300)
	_expect(not is_instance_valid(trap) and player.stun_time == 0.0 and grid.cost_of(cell) == 1.0, "夾完：夾子消失、可以動、那一格回到原本的成本")


## 追逐 AI 追丟（進入搜尋）時在腳下放捕獸夾，最多 3 個
func _test_trap_dropper() -> void:
	await _load(CHASE)
	_freeze_group("chase_ai")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var killer: ChaseAI = _level.get_node("ChaseAI")
	var dropper: TrapDropper = killer.get_node("TrapDropper")
	var before: int = get_tree().get_nodes_in_group("traps").size()
	killer.call("_set_state", ChaseAI.State.SEARCH)
	await _frames(2)
	var cell: Vector2i = grid.cell_of(killer.global_position)
	_expect(get_tree().get_nodes_in_group("traps").size() == before + 1 and grid.obstacle_at(cell) is Trap, "追丟了（搜尋）：在腳下放一個捕獸夾")
	for i: int in 4:
		killer.global_position = grid.cell_center(cell + Vector2i(i + 1, 1))
		dropper.drop()
		await _frames(2)
	_expect(dropper.traps.size() == dropper.max_traps and grid.obstacle_at(cell) == null, "最多 %d 個：最舊的消失、那一格取消登記" % dropper.max_traps)
	# 玩家踩掉其中一個（夾子被刪掉），AI 再放一個：清單要正常（以前這裡會報 Array 型別錯誤）
	var player: Player = get_tree().get_first_node_in_group("player")
	var stepped: Node2D = dropper.traps[0]
	player.global_position = stepped.global_position
	await _wait_until(func() -> bool: return player.stun_time > 0.0, 30)
	await _wait_until(func() -> bool: return player.stun_time == 0.0, 300)
	await _frames(2)
	killer.global_position = grid.cell_center(cell + Vector2i(1, 3))
	dropper.dropped_one_shot = false
	var added: Node2D = dropper.drop()
	var all_valid: bool = true
	for item: Variant in dropper.traps:
		all_valid = all_valid and is_instance_valid(item)
	_expect(added != null and dropper.traps.size() == dropper.max_traps and all_valid, "踩掉一個再放：清單只留還在的（%d 個）" % dropper.traps.size())
	_expect(added != null and (added as Trap).one_shot == false, "放下的夾子踩過會不會消失：照 TrapDropper 的設定")


## 警報：踩到發出大聲音，附近的 AI 過來查看；冷卻中不會再響
func _test_alarm() -> void:
	await _load(CHASE)
	_level.get_node("ChaseAI").process_mode = Node.PROCESS_MODE_DISABLED
	var player: Player = get_tree().get_first_node_in_group("player")
	var alarm: Alarm = _level.get_node("Alarm")
	var guard: ChaseAI = _level.get_node("Guard")
	var rings: Array[int] = [0]
	alarm.rang.connect(func(_p: Player) -> void: rings[0] += 1)
	player.global_position = alarm.global_position
	await _frames(3)
	_expect(rings[0] == 1 and guard.state == ChaseAI.State.INVESTIGATE, "踩到警報：響了、守衛過來查看")
	player.global_position = alarm.global_position + Vector2(64, 0)
	await _frames(3)
	player.global_position = alarm.global_position
	await _frames(3)
	_expect(rings[0] == 1, "冷卻中：再踩一次不會響")


## 瓶子：撿起來、按 1 丟出去，撞牆停在牆前面，落地的聲音把守衛引過去
func _test_bottle() -> void:
	await _load(CHASE)
	_level.get_node("ChaseAI").process_mode = Node.PROCESS_MODE_DISABLED
	var player: Player = get_tree().get_first_node_in_group("player")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var guard: ChaseAI = _level.get_node("Guard")
	var counter: Label = _level.get_node("HUD/Info/BottleCounter")
	_expect(not counter.visible, "沒有瓶子：不顯示瓶子數")
	(_level.get_node("Bottle") as Bottle).call("_on_interacted", player)
	(_level.get_node("Bottle2") as Bottle).call("_on_interacted", player)
	await _frames(2)
	_expect(player.bottles == 2 and counter.visible and counter.text.begins_with("瓶子 2"), "撿 2 個瓶子（%s）" % counter.text)
	# 往牆丟：停在牆前面
	var start_cell: Vector2i = grid.cell_of(player.global_position)
	var wall_x: float = grid.cell_center(Vector2i(0, start_cell.y)).x + 16.0
	var landing: Vector2 = ThrownBottle.landing_point(player, Vector2.LEFT, player.throw_distance)
	_expect(landing.x > wall_x and landing.x < wall_x + 20.0, "往牆丟：停在牆前面（%.0f）" % (landing.x - wall_x))
	# 在守衛正後方往前丟（守衛面向左，張望也看不到正後方）：守衛聽到、過去查看
	player.global_position = guard.global_position + Vector2(64, 0)
	player.facing = Vector2.LEFT
	var heard: Array[Vector2] = []
	var bottle_radius: float = player.bottle_sound_radius
	SoundBus.instance().sound_emitted.connect(func(p: Vector2, radius: float) -> void:
		if radius == bottle_radius: heard.append(p))
	await _frames(2)
	_expect(player.throw_bottle() and player.bottles == 1, "按 1：丟出去，剩 1 個")
	await _wait_until(func() -> bool: return not heard.is_empty(), 120)
	await _frames(3)
	_expect(not heard.is_empty() and heard[0].distance_to(player.global_position) > 100.0, "瓶子落地：發出聲音")
	_expect(guard.state == ChaseAI.State.INVESTIGATE, "守衛聽到瓶子：過去查看")


## 守衛（沒有巡邏點）被聲音引開，查看完會走回崗位
func _test_guard_returns() -> void:
	await _load(CHASE)
	_level.get_node("ChaseAI").process_mode = Node.PROCESS_MODE_DISABLED
	var guard: ChaseAI = _level.get_node("Guard")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var home: Vector2 = guard.global_position
	var sound_at: Vector2 = Vector2.INF
	for offset: Vector2 in [Vector2(-96, 0), Vector2(0, 96), Vector2(96, 0), Vector2(0, -96)]:
		if grid.is_cell_walkable(grid.cell_of(home + offset)):
			sound_at = home + offset
			break
	_expect(sound_at != Vector2.INF, "守衛旁邊找得到走得到的地方")
	if sound_at == Vector2.INF:
		return
	guard.call("_on_heard", sound_at)
	await _wait_until(func() -> bool: return guard.global_position.distance_to(sound_at) < 20.0, 400)
	_expect(guard.state == ChaseAI.State.INVESTIGATE and guard.global_position.distance_to(home) > 60.0, "守衛：聽到聲音走過去查看")
	await _wait_until(func() -> bool: return guard.state == ChaseAI.State.PATROL and guard.global_position.distance_to(home) < 20.0, 600)
	_expect(guard.global_position.distance_to(home) < 20.0, "守衛：查看完走回崗位（離崗位 %.0f px）" % guard.global_position.distance_to(home))


## 編輯器：讀寫關卡、畫、放、移動、巡邏點、出口指定、上一步、試玩
func _test_chase_editor() -> void:
	print("--- 追逐編輯器 ---")
	var before: ChaseMap = ChaseMap.read(CHASE)
	_expect(before.objects.size() == 21 and before.size == Vector2i(36, 18) and before.problem().is_empty(), "讀關卡：物件、大小（%d 個物件）" % before.objects.size())
	var copy_path: String = "res://examples/chase/levels/_test_chase.tscn"
	_expect(before.write(copy_path) == OK and ChaseMap.read(copy_path).snapshot() == before.snapshot(), "讀出來再存：一模一樣")
	var made: Node = (load(copy_path) as PackedScene).instantiate()
	_expect(made.has_node("HUD/Info/Hint") and made.has_node("PathGrid") and made.get_node("ChaseAI").get_child_count() > 5, "其他節點（HUD、尋路地圖、巡邏點）都在")
	made.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(copy_path))

	await _load("res://examples/chase/map_editor/map_editor.tscn")
	var editor: Node2D = _level
	var panel: ChaseObjectPanel = editor.get("_panel")
	editor.call("new_map")
	var map: ChaseMap = editor.get("map")
	_expect(map.problem().is_empty() and map.objects.size() == 2, "新關卡：有玩家、出口，可以玩")
	_press_cell(editor, 3, Vector2i(10, 5))
	_expect(map.walls.get(Vector2i(10, 5)) == ChaseMap.Tile.WALL, "畫牆")
	_press_cell(editor, 3, Vector2i(10, 5), true)
	_expect(not map.walls.has(Vector2i(10, 5)) and map.floors.has(Vector2i(10, 5)), "右鍵：擦掉牆，地板還在")
	editor.call("set_shape", LevelEditor.Shape.RECT)
	editor.call("set_tool", 3)
	editor.call("press", map.center_of(Vector2i(20, 2)), false)
	editor.call("release", map.center_of(Vector2i(20, 12)))
	_expect(map.walls.has(Vector2i(20, 2)) and map.walls.has(Vector2i(20, 12)) and not map.walls.has(Vector2i(21, 5)), "矩形：一道牆")
	editor.call("set_shape", LevelEditor.Shape.FILL)
	editor.call("set_tool", 2)
	editor.call("press", map.center_of(Vector2i(20, 14)), false)
	_expect(map.floors[Vector2i(5, 5)] == ChaseMap.Tile.SWAMP and map.walls.has(Vector2i(20, 5)), "油漆桶：地板變沼澤，牆留著")
	editor.call("undo")
	_expect(map.floors[Vector2i(5, 5)] == ChaseMap.Tile.WOOD, "上一步")
	editor.call("set_shape", LevelEditor.Shape.BRUSH)

	var first: int = editor.get("select_tool") + 1
	editor.call("set_tool", first)
	_expect(not bool(editor.call("place", Vector2i(6, 6))), "只能有一個玩家")
	editor.call("set_tool", first + 6)
	_expect(bool(editor.call("place", Vector2i(20, 5))) and not map.walls.has(Vector2i(20, 5)) and map.objects[2]["values"]["orientation"] == 1, "門放在牆上：開一個缺口，方向照牆")
	editor.call("set_tool", first + 3)
	_expect(not bool(editor.call("place", Vector2i(20, 6))), "牆上不能放寶物")
	editor.call("place", Vector2i(25, 5))
	editor.call("place", Vector2i(26, 5))
	_expect(map.objects[3]["name"] == "Treasure" and map.objects[4]["name"] == "Treasure2", "放兩個寶物，名字不一樣")
	editor.call("set_tool", first + 2)
	editor.call("place", Vector2i(30, 8))
	panel.set_value("reaction_time", 2.5)
	panel.set_dropper(true)
	_expect(map.objects[5]["values"]["reaction_time"] == 2.5 and not (map.objects[5]["dropper"] as Dictionary).is_empty(), "敵人：改反應時間、追丟時放夾子")
	editor.call("set_tool", editor.get("patrol_tool"))
	editor.call("place", Vector2i(30, 12))
	editor.call("place", Vector2i(25, 12))
	_expect((map.objects[5]["points"] as Array).size() == 2, "放巡邏點")
	editor.call("unplace", Vector2i(25, 12))
	_expect((map.objects[5]["points"] as Array).size() == 1, "右鍵拿掉巡邏點")
	editor.call("set_tool", editor.get("select_tool"))
	editor.call("press", map.objects[3]["position"], false)
	editor.call("_mouse_moved", map.center_of(Vector2i(27, 7)))
	editor.call("release", map.center_of(Vector2i(27, 7)))
	_expect(map.cell_of(map.objects[3]["position"]) == Vector2i(27, 7), "選取：拖著移動")
	editor.call("undo")
	_expect(map.cell_of(map.objects[3]["position"]) == Vector2i(25, 5), "移動也能上一步")
	editor.call("select", 1)
	panel.set_value("open_when", 1)
	panel.set_target("Treasure2", true)
	await _frames(2)
	_expect(panel.visible, "選到出口：右邊有面板")
	var labels: PackedStringArray = PackedStringArray()
	for field: Dictionary in ChaseMap.fields_of(ChaseMap.ENEMY):
		labels.append(field["label"])
	_expect(labels.has("看多遠") and labels.has("反應時間"), "欄位的中文名字從 ## 註解讀")
	editor.call("set_page", 1)
	(editor.get("_setting_page") as ChaseSettingPage).set_value("radius", 300.0)
	editor.call("set_page", 0)

	(editor.get("_name_edit") as LineEdit).text = "_test_chase"
	_expect(bool(editor.call("is_dirty")), "改了還沒存")
	var path: String = editor.call("save_map")
	_expect(path == copy_path and not bool(editor.call("is_dirty")), "存成關卡場景")
	var saved: Dictionary = map.snapshot()
	editor.call("new_map")
	_expect(bool(editor.call("load_map", path)) and (editor.get("map") as ChaseMap).snapshot() == saved, "讀回來一模一樣")
	map = editor.get("map")

	_expect(bool(editor.call("start_test")), "試玩")
	await _frames(6)
	Engine.time_scale = TIME_SCALE
	var play: Node = editor.get("_play")
	var exit: Exit = play.get_node("Exit")
	var enemy: ChaseAI = play.get_node("Enemy")
	_expect(get_tree().get_nodes_in_group("chase_ai") == [enemy] and get_tree().get_nodes_in_group("player").size() == 1, "試玩：編輯器裡看的物件不會混進去")
	_expect(exit.open_when == 1 and exit.tracked == [play.get_node("Treasure2")] and enemy.has_node("TrapDropper") and enemy.reaction_time == 2.5, "試玩：出口只看指定的寶物、敵人的設定都在")
	(play.get_node("Treasure2") as Pickup).call("_on_interacted", play.get_node("Player"))
	await _frames(2)
	_expect(exit.is_open, "撿到指定的寶物：出口打開")
	editor.call("stop_test")
	await _frames(2)
	_expect(not bool(editor.call("is_testing")) and (editor.get("map") as ChaseMap).snapshot() == saved, "停止試玩：回到編輯，關卡沒變")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(copy_path))
	LevelEditor.forget_sessions()


func _press_cell(editor: Node2D, tool: int, cell: Vector2i, erase: bool = false) -> void:
	editor.call("set_tool", tool)
	editor.call("press", editor.call("cell_center", cell), erase)
	editor.call("release", editor.call("cell_center", cell))
