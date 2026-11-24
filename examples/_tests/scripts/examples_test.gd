extends Node
## 三個範例的自動測試：
## 1. 追逐：寶物 3 個＋發電機、都完成出口才打開、走進出口就贏；開門條件（全部／指定／數量／一開始就開）；
##    守衛被聲音引開後會走回崗位；站在門口按 E 會退出去把門關上；
##    捕獸夾（AI 繞開、夾住、AI 追丟會放）、警報（AI 過來、冷卻）、瓶子（撿、丟、撞牆、引開守衛）；
##    發電機會發出聲音；鏡頭固定在畫面中間；被追逐 AI 碰到就輸；上鎖的門要鑰匙
## 2. 塔防：蓋牆扣錢、不能把路堵死、錢不夠蓋不了、塔會打怪、怪走到基地扣血
## 3. 戰棋：探索（撞牆、隊友跟上、物資、紮營）、被發現、偷襲、支援、布陣、速度順序、自動／回合制切換、
##    走／打／反悔、倍速和暫停、隊伍池、編隊、陣形、整隊／分開、趕來支援、每一種特性、四種個性、指定目標、意圖、日誌、骰子、寶箱、掉落、勝利條件、倒下站起來、三張範例地圖打得完、編輯器五頁
##
## 在命令列執行：
##   godot --headless --path . res://examples/_tests/examples_test.tscn

const ScriptErrors = preload("res://core/tests/scripts/script_error_counter.gd")
const CHASE: String = "res://examples/chase/levels/chase.tscn"
const TOWER_DEFENSE: String = "res://examples/tower_defense/levels/tower_defense.tscn"
const TACTICS: String = "res://examples/tactics/levels/tactics.tscn"
const TIME_SCALE: float = 3.0

var _failures: int = 0
## 腳本錯誤也算失敗（會讓測試函式中斷、跑不到 _expect）
var _script_errors: ScriptErrors = ScriptErrors.new()
var _level: Node


func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	await _test_chase()
	await _test_tower_defense()
	await _test_tactics()
	Engine.time_scale = 1.0
	get_tree().paused = false
	_failures += _script_errors.report()
	if _failures == 0:
		print("[範例測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[範例測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


# ---- 追逐 ----

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


# ---- 塔防 ----

func _test_tower_defense() -> void:
	print("--- 塔防 ---")
	await _load(TOWER_DEFENSE)
	var builder: Builder = _level.get_node("Builder")
	var spawner: Spawner = _level.get_node("Spawner")
	var base: Node2D = _level.get_node("Base")
	var money: ScoreDisplay = _level.get_node("HUD/Info/Money")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	spawner.autostart = false
	_expect(money.score == 12, "一開始 12 元")
	var open_cell: Vector2i = grid.cell_of(base.global_position) + Vector2i(-5, 3)
	builder.selected = 0
	_expect(builder.build(open_cell) and money.score == 11, "蓋牆：扣 1 元")
	_expect(grid.is_cell_walkable(open_cell) and grid.cost_of(open_cell) == 12.0, "牆：走得過去但很貴（要先打破）")
	_expect(not builder.build(open_cell), "同一格不能蓋兩次")
	_expect(builder.remove(open_cell) and grid.cost_of(open_cell) == 1.0 and grid.obstacle_at(open_cell) == null, "右鍵拆掉：不貴了")

	# 把基地圍起來，最後一格不能蓋（會堵死）
	var base_cell: Vector2i = grid.cell_of(base.global_position)
	money.score = 100
	builder.selected = 1                                          # 塔打不壞，所以不能堵死
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(-1, 1)]:
		var cell: Vector2i = base_cell + d
		if grid.is_cell_walkable(cell) and builder.can_build(cell):
			builder.build(cell)
	_expect(grid.has_path(spawner.global_position, base.global_position), "蓋了一圈：路還是通的（會堵死的那格蓋不下去）")
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(-1, 1)]:
		builder.remove(base_cell + d)
	money.score = 0
	builder.selected = 1
	_expect(not builder.build(open_cell), "錢不夠：蓋不了塔")

	# 塔打怪：在出怪口旁邊放一座塔，怪從旁邊經過會被打死
	money.score = 10
	var tower_cell: Vector2i = grid.cell_of(spawner.global_position) + Vector2i(3, -1)
	_expect(builder.build(tower_cell), "蓋塔：扣 4 元（剩 %d）" % money.score)
	var wave: Wave = Wave.new()
	wave.count = 1
	wave.speed = 40.0
	wave.health = 2.0
	var walker_id: int = spawner.spawn(wave).get_instance_id()
	await _wait_until(func() -> bool: return not is_instance_id_valid(walker_id), 300)
	_expect(not is_instance_id_valid(walker_id) and int(base.get("health")) == 10, "塔把經過的怪打死，基地沒事")
	_expect(money.score > 6, "打死怪加錢（%d）" % money.score)

	# 怪走到基地：扣血
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	builder.remove(tower_cell)
	wave.speed = 300.0
	wave.health = 100.0
	spawner.spawn(wave)
	await _wait_until(func() -> bool: return int(base.get("health")) < 10, 400)
	_expect(int(base.get("health")) == 9, "怪走到基地：扣 1 滴血（reached_goal → take_hit）")

	await _test_td_map()
	await _test_td_multi()
	await _test_td_build_rules()
	await _test_td_walls()
	await _test_td_upgrade()
	await _test_td_enemy_traits()
	await _test_td_towers_and_hud()
	await _test_map_editor()
	await _test_wave_page()
	await _test_enemy_page()
	await _test_td_levels()


## 打得壞的牆：堵死會拆、繞路便宜就繞、成本高低決定、多隻一起打、飛行怪不理牆、沼澤上的牆、不能斜鑽
func _test_td_walls() -> void:
	await _load_td()
	var loader: MapLoader = _level.get_node("MapLoader")
	var builder: Builder = _level.get_node("Builder")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var spawner: Spawner = _level.get_node("Spawner")
	var money: ScoreDisplay = _level.get_node("HUD/Info/Money")
	var base: Node2D = builder.goal_points()[0]
	spawner.win_when_cleared = false                              # 這裡自己生怪，不要關卡的波次跑來干擾
	spawner.wave_table = null
	spawner.waves = []
	money.score = 1000
	builder.selected = 0
	var start: Vector2i = grid.cell_of(spawner.global_position)

	# 一面牆：繞路便宜就繞
	var wall_cell: Vector2i = start + Vector2i(2, 0)
	builder.build(wall_cell)
	_expect(not _path_has(grid, spawner.global_position, base.global_position, wall_cell), "一面牆：繞過去比較便宜，不拆")

	# 一整排牆：堵死，可以蓋，怪會拆
	var all_built: bool = true
	for y: int in loader.map.size.y:
		var cell: Vector2i = grid.cell_of(loader.to_global(loader.map.cell_center(Vector2i(3, y))))
		if not builder.buildings.has(cell) and grid.is_cell_walkable(cell):
			all_built = builder.build(cell) and all_built
	_expect(all_built and grid.has_path(spawner.global_position, base.global_position), "用牆整排堵死：可以蓋，路還是通的（要拆牆）")
	var middle: Vector2i = start + Vector2i(2, 0)
	var wall: TDWall = builder.buildings[middle] as TDWall
	_expect(wall != null and _path_has(grid, spawner.global_position, base.global_position, middle), "堵死：走直的拆中間那面")
	_expect(builder.building_text(middle) == "牆 6/6", "滑鼠移到牆上：血量（%s）" % builder.building_text(middle))

	var wave: Wave = Wave.new()
	wave.speed = 200.0
	wave.health = 500.0
	var a: Walker = spawner.spawn(wave)
	var follower: PathFollower = a.get_node("PathFollower")
	await _wait_until(func() -> bool: return wall.health < 5.0, 600)
	_expect(follower.is_breaking() and wall.health < 5.0 and a.global_position.distance_to(wall.global_position) < 40.0, "怪走到牆前停下來打（牆 %.1f 滴血）" % wall.health)
	var refund_before: int = money.score
	var alone_health: float = wall.health
	await _physics_frames(30)
	var alone: float = alone_health - wall.health
	var b: Walker = spawner.spawn(wave)
	await _wait_until(func() -> bool: return (b.get_node("PathFollower") as PathFollower).is_breaking(), 600)
	wall.health = 6.0
	await _physics_frames(30)
	var together: float = 6.0 - wall.health
	_expect(together > alone * 1.8, "兩隻一起打：快一倍（%.2f → %.2f）" % [alone, together])
	await _wait_until(func() -> bool: return not builder.buildings.has(middle), 1200)
	_expect(not builder.buildings.has(middle) and grid.obstacle_at(middle) == null and grid.cost_of(middle) == 1.0, "牆被打破：那一格恢復可以走")
	_expect(money.score == refund_before, "被打破的牆不退錢")
	await _wait_until(func() -> bool: return is_instance_valid(a) and is_instance_valid(b) and a.global_position.x > grid.cell_center(middle).x + 64.0 and b.global_position.x > grid.cell_center(middle).x + 64.0, 600)
	_expect(is_instance_valid(a) and a.global_position.x > grid.cell_center(middle).x + 64.0 and b.global_position.x > grid.cell_center(middle).x + 64.0, "打破之後：兩隻都繼續走（不會卡住）")

	# 正在打的牆被玩家拆掉：怪不會卡住
	builder.build(middle)
	var c: Walker = spawner.spawn(wave)
	await _wait_until(func() -> bool: return (c.get_node("PathFollower") as PathFollower).is_breaking(), 600)
	_expect((c.get_node("PathFollower") as PathFollower).is_breaking(), "牆補回去：下一隻又停下來打")
	builder.remove(middle)
	await _wait_until(func() -> bool: return is_instance_valid(c) and c.global_position.x > grid.cell_center(middle).x + 64.0, 600)
	_expect(is_instance_valid(c) and c.global_position.x > grid.cell_center(middle).x + 64.0, "打到一半牆被玩家拆掉：繼續走")

	# 會飛的怪不理牆
	builder.build(middle)
	var flyer: Walker = spawner.adopt((load("res://examples/tower_defense/features/enemies/flyer.tscn") as PackedScene).instantiate(), spawner.global_position)
	flyer.speed = 200.0
	await _wait_until(func() -> bool: return is_instance_valid(flyer) and flyer.global_position.x > grid.cell_center(middle).x + 64.0, 600)
	_expect((builder.buildings[middle] as TDWall).health == 6.0 and is_instance_valid(flyer) and flyer.global_position.x > grid.cell_center(middle).x, "會飛的怪：不打牆，直接飛過去")

	# 拆牆等於多走幾格：便宜就拆、貴就繞（開一個遠遠的缺口）
	var gap: Vector2i = grid.cell_of(loader.to_global(loader.map.cell_center(Vector2i(3, 1))))
	builder.remove(gap)
	wall = builder.buildings[middle]
	wall.break_cost = 5.0
	wall.obstacle_changed.emit()
	_expect(_path_has(grid, spawner.global_position, base.global_position, middle), "缺口很遠、拆牆便宜（5）：拆牆")
	for cell: Vector2i in builder.buildings:
		(builder.buildings[cell] as TDWall).break_cost = 60.0
		(builder.buildings[cell] as TDWall).obstacle_changed.emit()
	_expect(_path_has(grid, spawner.global_position, base.global_position, gap), "拆牆很貴（60）：寧可繞到遠遠的缺口")

	# 沼澤上的牆：拆掉之後還是沼澤
	var swamp: Vector2i = Vector2i(-1, -1)
	for y: int in loader.map.size.y:
		for x: int in loader.map.size.x:
			if loader.map.is_swamp(Vector2i(x, y)):
				swamp = grid.cell_of(loader.to_global(loader.map.cell_center(Vector2i(x, y))))
	builder.build(swamp)
	var on_swamp: float = grid.cost_of(swamp)
	(builder.buildings[swamp] as TDWall).damage(999.0)
	_expect(on_swamp == 12.0 and grid.cost_of(swamp) == loader.swamp_cost, "沼澤上的牆打破：還是沼澤（%.0f → %.0f）" % [on_swamp, grid.cost_of(swamp)])

	# 不能從斜放的兩面牆中間鑽過去
	_expect(grid.diagonal == 0, "塔防不斜走：不會從斜放的牆中間鑽過去")

	# 打不壞的牆：跟以前一樣不能走、不能堵死
	await _load_td()
	builder = _level.get_node("Builder")
	grid = get_tree().get_first_node_in_group("path_grid")
	spawner = _level.get_node("Spawner")
	(_level.get_node("HUD/Info/Money") as ScoreDisplay).score = 100
	var hard: TDWall = builder.wall_scene.instantiate()
	hard.breakable = false
	var packed: PackedScene = PackedScene.new()
	packed.pack(hard)
	hard.free()
	builder.wall_scene = packed
	(builder.get("_wall_sample") as TDWall).breakable = false
	builder.selected = 0
	start = grid.cell_of(spawner.global_position)
	var last_reason: String = ""
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]:
		if not builder.build(start + d):
			last_reason = builder.why_not(start + d)
	_expect(not grid.is_cell_walkable(start + Vector2i(1, 0)) and last_reason == "會把路堵死：怪會走不到基地", "Breakable 不勾：牆不能走、不能堵死（%s）" % last_reason)
	builder.remove(start + Vector2i(1, 0))
	_expect(grid.is_cell_walkable(start + Vector2i(1, 0)), "打不壞的牆拆掉：又可以走")


## 從 from 到 to 的路有沒有經過 cell
func _path_has(grid: PathGrid, from: Vector2, to: Vector2, cell: Vector2i) -> bool:
	for point: Vector2 in grid.find_path(from, to):
		if grid.cell_of(point) == cell:
			return true
	return false


func _physics_frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## 升級：價格、數值、滿級、錢不夠、退錢、左鍵點塔
func _test_td_upgrade() -> void:
	await _load_td()
	var builder: Builder = _level.get_node("Builder")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var spawner: Spawner = _level.get_node("Spawner")
	var money: ScoreDisplay = _level.get_node("HUD/Info/Money")
	await _frames(2)
	money.score = 100
	builder.selected = 1
	var cell: Vector2i = grid.cell_of(spawner.global_position) + Vector2i(3, 3)
	builder.build(cell)
	var tower: Tower = builder.tower_at(cell)
	_expect(tower.level == 1 and tower.upgrade_cost() == 3 and builder.building_text(cell) == "Lv1 → Lv2　3 元", "升級價格：照強幾倍算（%s）" % builder.building_text(cell))
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = builder.get_global_transform_with_canvas() * builder.to_local(grid.cell_center(cell))
	builder._unhandled_input(click)
	_expect(tower.level == 2 and money.score == 93, "左鍵點塔：升到 Lv2、扣 3 元（剩 %d）" % money.score)
	_expect(is_equal_approx(tower.damage, 1.5) and is_equal_approx(tower.attack_range, 105.6) and is_equal_approx(tower.fire_interval, 0.5), "Lv2：傷害 ×1.5、射程 ×1.1、攻速不變")
	money.score = 3
	_expect(not builder.upgrade(cell) and builder.why_not_upgrade(cell) == "錢不夠（升級要 4 元）" and builder.building_text(cell).ends_with("（錢不夠）") and tower.level == 2, "錢不夠：不能升（%s）" % builder.why_not_upgrade(cell))
	money.score = 100
	_expect(builder.upgrade(cell) and money.score == 96 and is_equal_approx(tower.damage, 2.25) and tower.spent == 11, "Lv3：扣 4 元、傷害 2.25、總共花 11 元")
	_expect(not builder.upgrade(cell) and builder.building_text(cell) == "已經滿級（Lv3）" and money.score == 96, "滿級：不能再升、不扣錢")
	builder.remove(cell)
	_expect(money.score == 101, "拆掉：退總共花的一半（5 元）")
	tower = (load("res://examples/tower_defense/features/tower/multi_tower.tscn") as PackedScene).instantiate()
	_level.add_child(tower)
	var prices: Array[int] = [tower.upgrade_cost()]
	tower.upgrade()
	prices.append(tower.upgrade_cost())
	_expect(prices == [7, 11], "連射塔：升級 7、11 元（%s）" % [prices])
	tower.speed_per_level = 2.0
	tower.upgrade()
	_expect(is_equal_approx(tower.fire_interval, 0.25) and not tower.upgrade(), "攻速 ×2：間隔變一半")
	tower.queue_free()
	builder.build(cell)
	builder.tower_at(cell).max_level = 1
	_expect(builder.why_not_upgrade(cell) == "這種塔不能升級", "最高等級 1：不能升級")


## 塔防關卡會把倍速按鈕設回 1×，測試要再調回來
func _load_td() -> void:
	await _load(TOWER_DEFENSE)
	(_level.get_node("Spawner") as Spawner).autostart = false
	Engine.time_scale = TIME_SCALE


## 地圖：岩石不能走、不能蓋；沼澤比較貴；出怪口、基地搬到地圖上的位置
func _test_td_map() -> void:
	await _load_td()
	var loader: MapLoader = _level.get_node("MapLoader")
	var map: TDMap = loader.map
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var builder: Builder = _level.get_node("Builder")
	var rock_cell: Vector2i = Vector2i(-1, -1)
	var swamp_cell: Vector2i = Vector2i(-1, -1)
	for y: int in map.size.y:
		for x: int in map.size.x:
			if rock_cell.x < 0 and map.is_rock(Vector2i(x, y)):
				rock_cell = Vector2i(x, y)
			if swamp_cell.x < 0 and map.is_swamp(Vector2i(x, y)):
				swamp_cell = Vector2i(x, y)
	_expect(rock_cell.x >= 0 and swamp_cell.x >= 0, "預設地圖有岩石、有沼澤")
	var rock_grid: Vector2i = grid.cell_of(loader.to_global(map.cell_center(rock_cell)))
	var swamp_grid: Vector2i = grid.cell_of(loader.to_global(map.cell_center(swamp_cell)))
	_expect(not grid.is_cell_walkable(rock_grid) and not builder.can_build(rock_grid), "岩石：怪不能走、不能蓋")
	_expect(grid.is_cell_walkable(swamp_grid) and grid.cost_of(swamp_grid) == loader.swamp_cost, "沼澤：可以走、比較貴（%.0f）" % grid.cost_of(swamp_grid))
	var spawner: Spawner = _level.get_node("Spawner")
	var base: Node2D = _level.get_node("Base")
	_expect(grid.cell_of(spawner.global_position) == grid.cell_of(loader.to_global(map.cell_center(map.spawn_cells[0]))) \
		and grid.cell_of(base.global_position) == grid.cell_of(loader.to_global(map.cell_center(map.base_cells[0]))), "出怪口、基地在地圖指定的格子")
	_expect(grid.has_path(spawner.global_position, base.global_position), "預設地圖：出怪口走得到基地")

	# 試玩：地圖編輯器放的地圖優先
	var custom: TDMap = TDMap.new()
	custom.ensure()
	custom.spawn_cells = [Vector2i(2, 2)]
	custom.base_cells = [Vector2i(30, 12)]
	custom.paint(TDMap.Kind.ROCK, custom.cell_center(Vector2i(10, 10)), 20.0)
	MapLoader.test_map = custom
	await _load_td()
	loader = _level.get_node("MapLoader")
	grid = get_tree().get_first_node_in_group("path_grid")
	_expect(loader.is_test_play and loader.map == custom and not grid.is_cell_walkable(grid.cell_of(loader.to_global(custom.cell_center(Vector2i(10, 10))))),
		"試玩：用地圖編輯器的地圖（岩石擋路）")
	_expect(MapLoader.test_map == null, "試玩的地圖用過就清掉（下次開關卡用回原本的）")
	await _load_td()
	_expect(not (_level.get_node("MapLoader") as MapLoader).is_test_play, "一般開關卡：不是試玩")


## 好幾個出怪口、好幾個基地：輪流出、每一波指定、走最近的基地；三種基地規則；不能堵死任何一個出怪口；鏡頭邊界
func _test_td_multi() -> void:
	MapLoader.test_map = load("res://examples/tower_defense/maps/two_gates.tres").duplicate(true)
	await _load_td()
	var spawner: Spawner = _level.get_node("Spawner")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var builder: Builder = _level.get_node("Builder")
	var group: BaseGroup = _level.get_node("BaseGroup")
	var points: Array[Node2D] = spawner.spawn_points()
	var bases: Array[Node2D] = (_level.get_node("MapLoader") as MapLoader).bases
	_expect(points.size() == 2 and bases.size() == 2 and spawner.targets().size() == 2, "兩個出怪口、兩個基地")
	var wave: Wave = Wave.new()
	wave.speed = 1.0
	var first: Node2D = spawner.spawn(wave)
	var second: Node2D = spawner.spawn(wave)
	_expect(first.global_position == points[0].global_position and second.global_position == points[1].global_position, "輪流：第 1 隻從出怪口 1、第 2 隻從出怪口 2")
	wave.spawn_point = 2
	var third: Node2D = spawner.spawn(wave)
	_expect(third.global_position == points[1].global_position, "每一波指定：Spawn Point 2 都從出怪口 2 出")
	_expect(first.get_meta("target") == bases[0] and second.get_meta("target") == bases[1], "每隻怪走向路最短的基地（上面的去上面、下面的去下面）")
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await _frames(1)

	# 共用一條血
	_expect(group.mode == 0 and group.status_text() == "基地 10/10", "預設：共用一條血（%s）" % group.status_text())
	group.on_base_hit(bases[0] as Base)
	group.on_base_hit(bases[1] as Base)
	_expect(group.shared_health == 8 and (bases[1] as Base).health == 8, "共用一條血：哪個基地被摸都扣同一條")
	# 全部被打爆才輸
	group.mode = 2
	(bases[0] as Base).set_health(1)
	group.on_base_hit(bases[0] as Base)
	await _frames(1)
	_expect(group.bases().size() == 1 and not GameFlow.is_finished() and spawner.targets().size() == 1, "全爆才輸：爆了一個，怪改去另一個、還沒輸")
	(bases[1] as Base).set_health(1)
	group.on_base_hit(bases[1] as Base)
	await _frames(1)
	_expect(GameFlow.is_finished() and _result_title().contains("失敗"), "全爆才輸：全部爆了才輸")

	MapLoader.test_map = load("res://examples/tower_defense/maps/two_gates.tres").duplicate(true)
	await _load_td()
	group = _level.get_node("BaseGroup")
	group.mode = 1
	bases = (_level.get_node("MapLoader") as MapLoader).bases
	(bases[1] as Base).set_health(1)
	group.on_base_hit(bases[1] as Base)
	_expect(GameFlow.is_finished(), "一個爆就輸：一個被打爆就輸")

	# 塔不能堵死：把出怪口 1 圍起來，最後一格蓋不下去
	MapLoader.test_map = load("res://examples/tower_defense/maps/two_gates.tres").duplicate(true)
	await _load_td()
	spawner = _level.get_node("Spawner")
	grid = get_tree().get_first_node_in_group("path_grid")
	builder = _level.get_node("Builder")
	(_level.get_node("HUD/Info/Money") as ScoreDisplay).score = 100
	builder.selected = 1
	var start: Vector2i = grid.cell_of(spawner.spawn_points()[0].global_position)
	var blocked_last: bool = false
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(-1, 0)]:
		if grid.is_cell_walkable(start + d) and not builder.build(start + d):
			blocked_last = true
	var others_reach: bool = true
	for point: Node2D in spawner.spawn_points():
		var reach_any: bool = false
		for base: Node2D in builder.goal_points():
			reach_any = reach_any or grid.has_path(point.global_position, base.global_position)
		others_reach = others_reach and reach_any
	_expect(blocked_last and others_reach, "不能堵死：每個出怪口都還走得到基地")
	var placed: Node2D = builder.buildings.values()[0]
	_expect(placed.global_position == grid.cell_center(builder.buildings.keys()[0]), "蓋的東西就在點的那一格（以前會偏右下）")

	var camera: PanCamera = _level.get_node("PanCamera")
	var map: TDMap = (_level.get_node("MapLoader") as MapLoader).map
	_expect(camera.limit_rect.size == Vector2(map.size * 32) + Vector2(128, 176), "鏡頭邊界：地圖大小＋上下左右留給畫面上的字和按鈕")


## 怪物掛件：加速、厚血＋裝甲、會飛、分裂、治療
func _test_td_enemy_traits() -> void:
	await _load_td()
	var spawner: Spawner = _level.get_node("Spawner")
	var base: Node2D = _level.get_node("Base")
	var enemies: String = "res://examples/tower_defense/features/enemies/"
	var wave: Wave = Wave.new()
	wave.speed = 50.0
	wave.health = 4.0

	wave.enemy_scene = load(enemies + "fast_walker.tscn")
	var fast: Walker = spawner.spawn(wave)
	_expect(is_equal_approx(fast.speed, 80.0), "加速：速度 ×1.6（%.0f）" % fast.speed)

	wave.enemy_scene = load(enemies + "tank_walker.tscn")
	var tank: Walker = spawner.spawn(wave)
	tank.damage(2.0)
	_expect(tank.max_health == 12.0 and tank.health == 11.0, "厚血 ×3、裝甲扣一半（%.0f／%.0f）" % [tank.health, tank.max_health])

	wave.enemy_scene = load(enemies + "flyer.tscn")
	var flyer: Walker = spawner.spawn(wave)
	var follower: PathFollower = flyer.get_node("PathFollower")
	_expect(not follower.use_pathfinding and follower.path.size() == 1 and follower.path[0] == base.global_position, "會飛：不尋路，直線飛向基地")

	wave.enemy_scene = load(enemies + "splitter.tscn")
	var splitter: Walker = spawner.spawn(wave)
	var before: int = spawner.alive
	var count: int = get_tree().get_nodes_in_group("enemies").size()
	splitter.damage(100.0)
	await _frames(2)
	_expect(spawner.alive == before + 1 and get_tree().get_nodes_in_group("enemies").size() == count + 1, "分裂：死掉變 2 隻小的，算進生怪器（場上 %d 隻）" % spawner.alive)

	wave.enemy_scene = load(enemies + "healer_walker.tscn")
	var healer: Walker = spawner.spawn(wave)
	fast.global_position = healer.global_position + Vector2(20, 0)
	fast.damage(3.0)
	var hp: float = fast.health
	var healed: int = (healer.get_node("Healer") as TraitHealer).heal_nearby()
	_expect(healed >= 2 and fast.health > hp, "治療：幫附近的怪補血（%.0f → %.0f）" % [hp, fast.health])

	var misplaced: TraitFast = (load("res://examples/tower_defense/features/enemy_traits/fast.tscn") as PackedScene).instantiate()
	_level.add_child(misplaced)
	_expect(not misplaced._get_configuration_warnings().is_empty(), "掛件沒放在怪物底下：有警告")


## 砲塔掛件、蓋不同的塔、倍速
func _test_td_towers_and_hud() -> void:
	await _load_td()
	var spawner: Spawner = _level.get_node("Spawner")
	var builder: Builder = _level.get_node("Builder")
	var money: ScoreDisplay = _level.get_node("HUD/Info/Money")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var bar: HBoxContainer = _level.get_node("HUD/BuildBar")
	_expect(bar.get_child_count() == builder.option_count() and builder.option_count() == 5, "下面的按鈕：牆＋4 種塔")
	(bar.get_child(2) as Button).pressed.emit()
	_expect(builder.selected == 2 and builder.cost_of(2) == 6, "按「緩速塔」：選到、6 元")
	money.score = 100
	var cell: Vector2i = grid.cell_of(spawner.global_position) + Vector2i(2, -1)
	_expect(builder.build(cell) and money.score == 94, "蓋緩速塔：扣 6 元")
	var built_slow: bool = builder.buildings[cell] is Tower and (builder.buildings[cell] as Tower).cost == 6
	builder.remove(cell)
	_expect(money.score == 97, "拆掉：退一半（3 元）")

	var wave: Wave = Wave.new()
	wave.speed = 30.0
	wave.health = 50.0
	var a: Walker = spawner.spawn(wave)
	var b: Walker = spawner.spawn(wave)
	var c: Walker = spawner.spawn(wave)
	for w: Walker in [a, b, c]:
		w.get_node("PathFollower").stop()
		w.global_position = grid.cell_center(cell + Vector2i(6, 0))
	b.global_position += Vector2(16, 0)
	c.global_position += Vector2(200, 0)                          # 遠的那隻：範圍傷害打不到
	var slow: Tower = (load("res://examples/tower_defense/features/tower/slow_tower.tscn") as PackedScene).instantiate()
	_level.add_child(slow)
	slow.global_position = a.global_position + Vector2(-40, 0)
	await _wait_until(func() -> bool: return a.is_slowed(), 60)
	_expect(a.is_slowed() and is_equal_approx(a.get_node("PathFollower").speed, 15.0), "緩速塔：打到的怪變慢一半")
	slow.queue_free()
	a.health = 50.0
	b.health = 50.0
	var splash: Tower = (load("res://examples/tower_defense/features/tower/splash_tower.tscn") as PackedScene).instantiate()
	_level.add_child(splash)
	splash.global_position = a.global_position + Vector2(-40, 0)
	await _wait_until(func() -> bool: return a.health < 50.0, 60)
	_expect(a.health == 49.0 and b.health == 49.25 and c.health == 50.0, "範圍塔：旁邊的怪扣 0.75（%.2f／%.2f／%.2f）" % [a.health, b.health, c.health])
	splash.queue_free()
	var multi: Tower = (load("res://examples/tower_defense/features/tower/tower.tscn") as PackedScene).instantiate()
	multi.add_child((load("res://examples/tower_defense/features/tower_traits/multi_shot.tscn") as PackedScene).instantiate())
	_level.add_child(multi)
	multi.global_position = a.global_position + Vector2(-40, 0)
	multi.attack_range = 400.0
	_expect(multi.targets_per_shot == 3 and multi.pick_targets(3).size() == 3, "多重射擊：一次打 3 隻")
	multi.queue_free()
	var multi_tower: Tower = (load("res://examples/tower_defense/features/tower/multi_tower.tscn") as PackedScene).instantiate()
	_level.add_child(multi_tower)
	_expect(multi_tower.targets_per_shot == 3 and multi_tower.display_name == "連射塔", "連射塔：一次打 3 隻")
	multi_tower.queue_free()

	# 先打誰
	var picker: Tower = (load("res://examples/tower_defense/features/tower/tower.tscn") as PackedScene).instantiate()
	_level.add_child(picker)
	picker.set_physics_process(false)                             # 只看它選誰，不要真的打
	picker.attack_range = 400.0
	picker.global_position = a.global_position + Vector2(-40, 0)
	a.health = 20.0
	b.health = 50.0
	c.health = 5.0
	_expect(picker.pick_targets(1) == [a], "先打誰：離塔最近（預設）")
	picker.target_priority = Tower.Priority.MOST_HEALTH
	_expect(picker.pick_targets(1) == [b], "先打誰：血最多")
	picker.target_priority = Tower.Priority.LEAST_HEALTH
	_expect(picker.pick_targets(1) == [c], "先打誰：血最少")
	for w: Walker in [a, b, c]:
		(w.get_node("PathFollower") as PathFollower).speed = 0.0
		(w.get_node("PathFollower") as PathFollower).go_to(builder.goal_points()[0].global_position)
	picker.target_priority = Tower.Priority.CLOSEST_TO_BASE
	_expect((c.get_node("PathFollower") as PathFollower).remaining_distance() < (a.get_node("PathFollower") as PathFollower).remaining_distance() and picker.pick_targets(1) == [c], "先打誰：最接近基地（剩下的路最短）")
	(c.get_node("PathFollower") as PathFollower).stop()
	_expect((c.get_node("PathFollower") as PathFollower).remaining_distance() == INF and picker.pick_targets(1) != [c], "沒有在走的怪：排最後")
	picker.target_priority = Tower.Priority.NEAREST
	a.damage(1000.0)
	_expect(picker.pick_targets(3).size() == 2 and not picker.pick_targets(3).has(a), "剛被打死、還沒消失的怪：不打")
	picker.queue_free()

	# 名字和數字鍵
	_expect(builder.option_label(3) == "範圍塔 6 元" and builder.option_label(4) == "連射塔 10 元", "按鈕的字：塔的 Display Name（%s）" % builder.option_label(4))
	var number: InputEventKey = InputEventKey.new()
	number.physical_keycode = KEY_5
	number.pressed = true
	builder._unhandled_input(number)
	_expect(builder.selected == 4 and (bar.get_child(4) as Button).text.begins_with("5 "), "按 5：選到連射塔")
	number.physical_keycode = KEY_1
	number.keycode = KEY_1
	builder._unhandled_input(number)
	_expect(builder.selected == 0, "按 1：選到牆")
	var same_name: Builder = Builder.new()
	same_name.tower_scenes = [load("res://examples/tower_defense/features/tower/tower.tscn"), load("res://examples/tower_defense/features/tower/tower.tscn")]
	_level.add_child(same_name)
	_expect(same_name.option_label(1) == "塔 4 元" and same_name.option_label(2) == "塔2 4 元", "名字一樣的塔：後面的加號碼（%s）" % same_name.option_label(2))
	same_name.queue_free()
	_expect(built_slow, "蓋出來的是緩速塔")

	var speed_button: Button = _level.get_node("HUD/SpeedButton")
	speed_button.pressed.emit()
	_expect(Engine.time_scale == 2.0 and speed_button.text == "▶ 2×", "倍速：按一下變 2×")
	speed_button.pressed.emit()
	speed_button.pressed.emit()
	_expect(Engine.time_scale == 1.0, "倍速：3× 再按回到 1×")
	Engine.time_scale = TIME_SCALE


## 地圖編輯器：畫、擦、放出怪口、存檔、讀檔
func _test_map_editor() -> void:
	await _load("res://examples/tower_defense/map_editor/map_editor.tscn")
	var editor: Node2D = _level
	var map: TDMap = editor.get("map")
	var cell: Vector2i = Vector2i(12, 6)
	_expect(not GameFlow.is_pause_enabled(), "編輯時：沒有暫停選單（右上角沒有「選單」、Esc 沒反應）")
	editor.set("tool", 0)
	editor.call("paint_at", map.cell_center(cell))
	_expect(map.is_rock(cell), "左鍵：畫岩石")
	editor.call("paint_at", map.cell_center(cell), true)
	_expect(not map.is_rock(cell), "右鍵：擦掉")
	editor.set("tool", 1)
	editor.call("paint_at", map.cell_center(cell))
	_expect(map.is_swamp(cell), "選沼澤：畫沼澤")
	editor.call("place", 3, Vector2i(3, 4))
	editor.call("place", 4, Vector2i(20, 4))
	editor.call("place", 4, Vector2i(20, 9))
	_expect(map.spawn_cells.has(Vector2i(3, 4)) and map.base_cells.size() == 3, "放出怪口、多放兩個基地（%d 個基地）" % map.base_cells.size())
	_expect(not editor.call("place", 4, Vector2i(3, 4)), "同一格不能同時是出怪口和基地")
	_expect(editor.call("unplace", 4, Vector2i(20, 9)) and map.base_cells.size() == 2, "右鍵：拿掉一個基地")
	editor.call("resize_map", Vector2i(50, 20))
	_expect(map.size == Vector2i(50, 20) and map.is_swamp(cell) and map.base_cells.has(Vector2i(20, 4)), "改大小：畫好的地形、基地留著")
	editor.call("resize_map", Vector2i(15, 20))
	_expect(map.size == Vector2i(15, 20) and map.is_swamp(cell) and not map.base_cells.has(Vector2i(20, 4)), "改小：超出去的基地拿掉")
	_expect(editor.call("check_map") == "至少要放一個基地", "沒有基地：不能存檔、不能試玩")
	editor.call("place", 4, Vector2i(10, 15))
	var editor_camera: PanCamera = get_tree().get_first_node_in_group("pan_camera")
	_expect(editor_camera != null and editor_camera.limit_rect.size == Vector2(15 * 32 + 128, 20 * 32 + 176), "改大小：鏡頭邊界跟著變")

	var name_edit: LineEdit = editor.get("_name_edit")
	name_edit.text = "_test_map"
	editor.call("update_save_buttons")
	_expect(editor.call("is_dirty") and (editor.get("_save_button") as Button).text == "存檔＊", "改了地圖：存檔按鈕多一個＊")
	var path: String = editor.call("save_map")
	_expect(not editor.call("is_dirty") and (editor.get("_save_button") as Button).text == "存檔", "地圖存好：＊不見")
	editor.call("paint_at", map.cell_center(Vector2i(6, 6)))
	var painted_dirty: bool = editor.call("is_dirty")
	map.restore(editor.get("saved_state"))
	_expect(painted_dirty and not editor.call("is_dirty"), "再畫就又沒存；退回存檔時的樣子就不算")
	_expect(path.ends_with("maps/_test_map.tres") and FileAccess.file_exists(path), "存檔：存進 maps/ 資料夾")
	editor.call("_new")
	_expect(not (editor.get("map") as TDMap).is_swamp(cell), "新地圖：空的")
	_expect(editor.call("load_map", path) and (editor.get("map") as TDMap).is_swamp(cell) and (editor.get("map") as TDMap).spawn_cells.has(Vector2i(3, 4)) and (editor.get("map") as TDMap).size == Vector2i(15, 20), "讀檔：地形、出怪口、大小都回來了")
	_expect((editor.call("map_files") as PackedStringArray).has(path), "讀檔清單裡有這張")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 形狀工具：矩形、圓形、油漆桶
	editor.call("_new")
	map = editor.get("map")
	editor.set("tool", 2)                                         # 高地
	map.paint_rect(TDMap.Kind.HIGH, Rect2(map.cell_center(Vector2i(2, 2)) - Vector2(16, 16), Vector2(32 * 4, 32 * 3)))
	_expect(map.is_high(Vector2i(2, 2)) and map.is_high(Vector2i(5, 4)) and not map.is_high(Vector2i(6, 4)), "矩形：剛好 4×3 格高地")
	map.paint_ellipse(TDMap.Kind.ROCK, Rect2(map.cell_center(Vector2i(20, 8)) - Vector2(64, 48), Vector2(128, 96)))
	_expect(map.is_rock(Vector2i(20, 8)) and map.is_rock(Vector2i(19, 8)) and not map.is_rock(Vector2i(18, 6)), "圓形：中間有、角落沒有")
	editor.set("tool", 1)                                         # 沼澤
	var filled: int = editor.call("fill_at", map.cell_center(Vector2i(3, 3)))
	_expect(filled > 0 and map.is_swamp(Vector2i(2, 2)) and map.is_swamp(Vector2i(5, 4)) and not map.is_swamp(Vector2i(10, 10)), "油漆桶：只換掉點到的那一塊高地")
	filled = editor.call("fill_at", map.cell_center(Vector2i(10, 10)))
	_expect(map.is_swamp(Vector2i(10, 10)) and not map.is_swamp(Vector2i(20, 8)) and map.is_rock(Vector2i(20, 8)), "油漆桶：空地整片變沼澤，岩石擋住不會被塗")
	editor.call("fill_at", map.cell_center(Vector2i(10, 10)), true)
	_expect(not map.is_swamp(Vector2i(10, 10)) and map.is_rock(Vector2i(20, 8)), "右鍵油漆桶：擦掉那一片沼澤")

	# 上一步、下一步
	_expect(editor.call("undo") and map.is_swamp(Vector2i(10, 10)), "上一步：擦掉的沼澤回來了")
	_expect(editor.call("undo") and not map.is_swamp(Vector2i(10, 10)), "再上一步：油漆桶倒的沼澤不見了")
	_expect(editor.call("redo") and map.is_swamp(Vector2i(10, 10)), "下一步：又倒回去")
	editor.call("place", 3, Vector2i(30, 2))
	_expect(not editor.call("redo"), "做了新的事：下一步的紀錄清掉")
	editor.call("resize_map", Vector2i(20, 20))
	_expect(editor.call("undo") and map.size == Vector2i(36, 17) and map.is_rock(Vector2i(20, 8)), "改大小也能上一步（大小、地形都回來）")
	_expect(editor.call("undo") and not map.spawn_cells.has(Vector2i(30, 2)), "放出怪口也能上一步")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_Z
	key.ctrl_pressed = true
	key.pressed = true
	editor.call("_unhandled_input", key)
	_expect(not map.is_swamp(Vector2i(10, 10)), "Ctrl＋Z：上一步")
	key.keycode = KEY_Y
	editor.call("_unhandled_input", key)
	_expect(map.is_swamp(Vector2i(10, 10)), "Ctrl＋Y：下一步")
	editor.call("_new")
	_expect(not editor.call("undo"), "新地圖：沒有上一步")

	# 哪種地面可以蓋塔、蓋牆
	map = editor.get("map")
	var tower_checks: Array[CheckBox] = editor.get("_tower_checks")
	var wall_checks: Array[CheckBox] = editor.get("_wall_checks")
	_expect(tower_checks.size() == 4 and tower_checks[TDMap.Ground.FLOOR].button_pressed and not tower_checks[TDMap.Ground.ROCK].button_pressed and not wall_checks[TDMap.Ground.HIGH].button_pressed, "勾選：預設空地、沼澤、高地可以蓋塔，岩石不行；牆不能蓋高地")
	tower_checks[TDMap.Ground.ROCK].button_pressed = true
	_expect(TDMap.has_ground(map.tower_ground, TDMap.Ground.ROCK), "勾岩石：岩石也可以蓋塔")
	editor.call("undo")
	_expect(not TDMap.has_ground(map.tower_ground, TDMap.Ground.ROCK) and not tower_checks[TDMap.Ground.ROCK].button_pressed, "上一步：取消勾選（勾選框也跟著變）")

	# 在編輯器裡試玩（不換場景）
	editor.call("_new")
	map = editor.get("map")
	map.tower_ground = (1 << TDMap.Ground.HIGH) | (1 << TDMap.Ground.ROCK)
	map.wall_ground = 0
	map.paint_rect(TDMap.Kind.HIGH, Rect2(map.cell_center(Vector2i(10, 2)) - Vector2(16, 16), Vector2(64, 64)))
	map.paint_rect(TDMap.Kind.ROCK, Rect2(map.cell_center(Vector2i(20, 2)) - Vector2(16, 16), Vector2(64, 64)))
	_expect(editor.call("start_test") and editor.call("is_testing"), "▶ 試玩：開始（沒有換場景）")
	await _frames(4)
	Engine.time_scale = TIME_SCALE
	var play: Node = editor.get("_play")
	var builder: Builder = play.get_node("Builder")
	var loader: MapLoader = play.get_node("MapLoader")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	_expect(get_tree().current_scene != play and loader.is_test_play and play.get_parent() == editor, "試玩的關卡放在編輯器底下")
	_expect(not (editor.get("_ui") as CanvasLayer).visible and (editor.get("_stop_button") as Button).visible, "試玩時：編輯的介面藏起來、出現「停止試玩」")
	_expect(GameFlow.is_pause_enabled(), "試玩時：有暫停選單")
	_expect(builder.tower_ground == map.tower_ground and not builder.has_walls() and builder.options() == [1, 2, 3, 4], "地圖的規則交給 Builder：高地和岩石可以蓋塔、沒有牆")
	(play.get_node("HUD/Info/Money") as ScoreDisplay).score = 100
	var high_cell: Vector2i = grid.cell_of(loader.to_global(map.cell_center(Vector2i(10, 2))))
	var floor_cell: Vector2i = grid.cell_of(loader.to_global(map.cell_center(Vector2i(10, 8))))
	var rock_cell: Vector2i = grid.cell_of(loader.to_global(map.cell_center(Vector2i(20, 2))))
	_expect(builder.why_not(floor_cell) == "塔只能蓋在高地、岩石上", "空地：蓋不了，說明原因（%s）" % builder.why_not(floor_cell))
	_expect(not grid.is_cell_walkable(high_cell) and builder.build(high_cell), "高地：怪不能走、可以蓋塔")
	builder.remove(high_cell)
	_expect(not grid.is_cell_walkable(high_cell), "拆掉高地上的塔：高地還是不能走")
	_expect(builder.build(rock_cell), "岩石有勾：岩石上也能蓋塔")
	builder.remove(rock_cell)
	_expect(not grid.is_cell_walkable(rock_cell), "拆掉岩石上的塔：岩石還是不能走")

	# 暫停選單、勝敗畫面的「回標題」換成「回地圖編輯器」
	_expect(GameFlow.title_button_text() == "回地圖編輯器", "試玩中：回標題換成「回地圖編輯器」")
	GameFlow.lose("試玩輸了")
	await _frames(1)
	var result: Node = null
	for child: Node in GameFlow.get_children():
		if child.scene_file_path.ends_with("result_screen.tscn") and not child.is_queued_for_deletion():
			result = child
	var back: Button = result.get_node("%TitleButton") if result != null else null
	_expect(back != null and back.text == "回地圖編輯器", "勝敗畫面：按鈕寫「回地圖編輯器」")
	back.pressed.emit()
	await _frames(2)
	_expect(not editor.call("is_testing") and not GameFlow.is_finished() and not get_tree().paused and is_instance_valid(editor) and editor.is_inside_tree(), "按「回地圖編輯器」：停止試玩、不換場景")
	_expect(GameFlow.title_button_text().is_empty() and not GameFlow.is_pause_enabled(), "停止試玩：回標題換回來、暫停選單又藏起來")
	_expect(editor.call("start_test"), "再試玩一次")
	await _frames(4)
	Engine.time_scale = TIME_SCALE
	editor.call("stop_test")
	await _frames(2)
	_expect(not editor.call("is_testing") and (editor.get("_ui") as CanvasLayer).visible and (editor.get("_camera") as PanCamera).is_current(), "■ 停止試玩：回到編輯，地圖還在")
	_expect(editor.get("map") == map and map.is_high(Vector2i(10, 2)), "停止後地圖沒變")
	editor.set("editing", null)
	editor.set("resume_test", false)


## 蓋不了的時候說明原因；固定路線型的範例地圖
func _test_td_build_rules() -> void:
	await _load_td()
	var builder: Builder = _level.get_node("Builder")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var loader: MapLoader = _level.get_node("MapLoader")
	var money: ScoreDisplay = _level.get_node("HUD/Info/Money")
	var spawner: Spawner = _level.get_node("Spawner")
	var rock_cell: Vector2i = Vector2i(-1, -1)
	for y: int in loader.map.size.y:
		for x: int in loader.map.size.x:
			if rock_cell.x < 0 and loader.map.is_rock(Vector2i(x, y)):
				rock_cell = grid.cell_of(loader.to_global(loader.map.cell_center(Vector2i(x, y))))
	builder.selected = 1
	money.score = 0
	var open: Vector2i = grid.cell_of(spawner.global_position) + Vector2i(3, 2)
	_expect(builder.why_not(open) == "錢不夠（要 4 元）", "錢不夠：說明要幾元（%s）" % builder.why_not(open))
	money.score = 100
	_expect(builder.why_not(rock_cell) == "塔只能蓋在空地、沼澤、高地上", "岩石：說明哪裡才能蓋（%s）" % builder.why_not(rock_cell))
	_expect(builder.why_not(grid.cell_of(spawner.global_position)) == "出怪口、基地上不能蓋", "出怪口上：說明不能蓋")
	var start: Vector2i = grid.cell_of(spawner.global_position)
	var reason: String = ""
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(-1, 0)]:
		if grid.is_cell_walkable(start + d) and not builder.build(start + d):
			reason = builder.why_not(start + d)
	_expect(reason == "會把路堵死：怪會走不到基地", "用塔把出怪口圍起來：最後一格說明會堵死（%s）" % reason)

	MapLoader.test_map = load("res://examples/tower_defense/maps/fixed_route.tres").duplicate(true)
	await _load_td()
	builder = _level.get_node("Builder")
	grid = get_tree().get_first_node_in_group("path_grid")
	spawner = _level.get_node("Spawner")
	var bar: HBoxContainer = _level.get_node("HUD/BuildBar")
	await _frames(2)
	_expect(not builder.has_walls() and builder.tower_ground == 1 << TDMap.Ground.HIGH and bar.get_child_count() == 4, "固定路線地圖：沒有牆的按鈕、塔只能蓋高地")
	var bases: Array[Node2D] = builder.goal_points()
	var path: PackedVector2Array = grid.find_path(spawner.global_position, bases[0].global_position)
	_expect(not path.is_empty() and grid.cell_of(path[path.size() - 1]) == grid.cell_of(bases[0].global_position), "固定路線地圖：怪走得到基地")


## 編輯器的波次頁：加減搬複製、同時出、實際血量、上一步、存讀檔、從第幾波試玩
func _test_wave_page() -> void:
	TDWavePage.editing = null
	await _load("res://examples/tower_defense/map_editor/map_editor.tscn")
	var editor: Node2D = _level
	editor.call("load_map", "res://examples/tower_defense/maps/two_gates.tres")
	editor.call("set_page", 1)
	var page: TDWavePage = editor.get("_wave_page")
	_expect(page.visible and not (editor.get("_map_tools") as Control).visible and page.spawn_count == 2, "波次頁：地圖工具藏起來、有 2 個出怪口")
	_expect(page.groups().size() == 6 and page.table.table_name == "default", "一開始是 default 的 6 波")
	var level: Node = (load(TOWER_DEFENSE) as PackedScene).instantiate()
	_expect((level.get_node("Spawner") as Spawner).wave_table != null and (level.get_node("Spawner") as Spawner).wave_groups().size() == 6, "關卡的 Spawner 用波次檔（6 波）")
	level.free()

	var tank: Wave = page.groups()[4][0]
	var texts: Array = page.call("_row_text", tank)
	_expect(texts[0] == "→ 18（要打 36）", "實際血量：填 6、厚血 ×3、裝甲減半（%s）" % texts[0])
	_expect(get_tree().get_nodes_in_group("enemies").is_empty(), "算數值用的怪不會留在場上")
	page.add_row(0)
	_expect(page.groups().size() == 6 and page.groups()[0].size() == 2 and int(page.summary(page.groups()[0])["count"]) == 11, "＋同時出：第 1 波變兩種怪、共 11 隻")
	page.set_value(page.groups()[0][1], "enemy_scene", load("res://examples/tower_defense/features/enemies/flyer.tscn"))
	page.set_value(page.groups()[0][1], "spawn_point", 2)
	page.copy_wave(0)
	_expect(page.groups().size() == 7 and page.groups()[1].size() == 2 and page.groups()[1][1] != page.groups()[0][1], "複製整波")
	page.add_wave()
	_expect(page.groups().size() == 8, "＋新的一波")
	_expect(page.move_wave(7, -1) and not page.move_wave(0, -1), "往前移；第一波不能再往前")
	_expect(page.delete_row(1, 1) and page.groups()[1].size() == 1 and page.delete_row(1, 0) and page.groups().size() == 7, "✕：拿掉一種；空了就整波拿掉")
	for i: int in 4:
		editor.call("undo")
	_expect(page.groups().size() == 7 and page.groups()[1].size() == 2, "上一步：退回複製完的樣子（%d 波）" % page.groups().size())
	editor.call("redo")
	_expect(page.groups().size() == 8, "下一步")
	page.set_table_value("start_delay", 0.5)
	page.set_table_value("time_between_waves", 1.0)

	(page.get("_name_edit") as LineEdit).text = "_test_waves"
	editor.call("update_save_buttons")
	_expect(page.is_dirty() and (page.get("_save_button") as Button).text == "存檔＊", "改了波次：存檔按鈕多一個＊")
	var path: String = page.save()
	_expect(not page.is_dirty() and (page.get("_save_button") as Button).text == "存檔", "波次存好：＊不見")
	_expect(path.ends_with("waves/_test_waves.tres") and FileAccess.file_exists(path) and page.files().has(path), "存檔：存進 waves/ 資料夾")
	page.new_table()
	_expect(page.groups().size() == 1, "新的：1 波")
	_expect(not page.delete_row(0, 0), "最後一種怪不能拿掉")
	editor.call("undo")
	_expect(page.groups().size() == 8, "按到「新的」：上一步拿得回來")
	_expect(page.load_table(path) and page.groups().size() == 8 and page.groups()[0][1].spawn_point == 2 and page.groups()[0][1].enemy_scene.resource_path.ends_with("flyer.tscn") and page.table.start_delay == 0.5, "讀檔：怪、出怪口、等待時間都回來了")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 打到一半的數字：存檔、試玩前會先算數
	var spin: SpinBox = page.get("_start_delay")
	spin.get_line_edit().grab_focus()
	spin.get_line_edit().text = "3"
	page.commit()
	_expect(is_equal_approx(page.table.start_delay, 3.0), "打到一半的數字：先算數（%.1f）" % page.table.start_delay)
	page.set_table_value("start_delay", 0.0)

	# 從第 2 波試玩：用這份波次、補前面幾波的錢
	var bonus: int = page.money_before(2)
	page.test_requested.emit(2)
	await _frames(4)
	Engine.time_scale = TIME_SCALE
	var play: Node = editor.get("_play")
	_expect(editor.call("is_testing") and bonus == 11, "▶ 從這波試玩：開始（前面 1 波 %d 元）" % bonus)
	var spawner: Spawner = play.get_node("Spawner")
	_expect(spawner.wave_groups().size() == 8 and spawner.start_wave == 2 and (play.get_node("HUD/Info/Money") as ScoreDisplay).score == 12 + bonus, "試玩：用現在排的波次、錢有補（%d）" % (play.get_node("HUD/Info/Money") as ScoreDisplay).score)
	await _wait_until(func() -> bool: return spawner.alive >= 2, 300)
	var kinds: Array[String] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not kinds.has(node.scene_file_path):
			kinds.append(node.scene_file_path)
	_expect(spawner.wave_number == 2 and kinds.size() == 2, "第 2 波：兩種怪一起出")
	_expect(MapLoader.test_waves == null and MapLoader.test_start_wave == 1, "試玩的波次用過就清掉")
	editor.call("stop_test")
	await _frames(2)
	_expect(page.is_visible_in_tree() and page.groups().size() == 8, "停止試玩：回到波次頁，排的還在")
	editor.call("set_page", 0)
	TDWavePage.editing = null
	editor.set("editing", null)
	editor.set("resume_test", false)


## 編輯器的怪物頁：改數值、勾掛件、新怪、複製、存檔（一般的繼承場景）、上一步、普通怪不能改
func _test_enemy_page() -> void:
	TDEnemyPage.editing = {}
	TDEnemyPage.editing_path = ""
	TDWavePage.editing = null
	await _load("res://examples/tower_defense/map_editor/map_editor.tscn")
	var editor: Node2D = _level
	editor.call("set_page", 2)
	var page: TDEnemyPage = editor.get("_enemy_page")
	var tank_path: String = "res://examples/tower_defense/features/enemies/tank_walker.tscn"
	var tank_trait: String = "res://examples/tower_defense/features/enemy_traits/tank.tscn"
	var fast_trait: String = "res://examples/tower_defense/features/enemy_traits/fast.tscn"
	var split_trait: String = "res://examples/tower_defense/features/enemy_traits/split.tscn"
	page.open(tank_path)
	_expect(page.data["display_name"] == "坦克" and page.data["traits"].size() == 2 and is_equal_approx(page.data["traits"][tank_trait]["health_multiplier"], 3.0), "讀怪物：名字、掛件、掛件的數字")
	_expect((page.get("_stats") as Label).text.begins_with("實際血量　30（減傷：要打 60）"), "預覽旁邊寫實際血量")
	_expect(get_tree().get_nodes_in_group("enemies").is_empty(), "預覽的怪不算場上的怪")
	page.open(TDEnemyInfo.DEFAULT_PATH)
	page.set_value("speed", 999.0)
	_expect(page.is_locked() and page.data["speed"] == 60.0 and page.save().is_empty(), "普通怪（尋路積木）不能改、不能存")

	page.new_enemy()
	page.set_value("display_name", "_測試怪")
	page.set_value("speed", 80.0)
	page.set_value("max_health", 20.0)
	page.set_value("score", 5)
	page.set_trait(tank_trait, true)
	page.set_trait_value(tank_trait, "health_multiplier", 2.0)
	page.set_trait(fast_trait, true)
	await _frames(2)
	_expect((page.get("_stats") as Label).text.contains("實際血量　40") and (page.get("_stats") as Label).text.contains("實際速度　128"), "預覽：20×2 血、80×1.6 速度（%s）" % (page.get("_stats") as Label).text.get_slice("\n", 0))
	editor.call("undo")
	_expect(not page.data["traits"].has(fast_trait), "上一步：掛件取消")
	editor.call("redo")
	_expect(page.data["traits"].has(fast_trait), "下一步：掛件回來")
	var path: String = page.save()
	var text: String = FileAccess.get_file_as_string(path)
	_expect(path.ends_with("features/enemies/_測試怪.tscn") and text.contains("walker.tscn") and text.contains("instance=ExtResource") and not text.contains("walker.gd"), "新怪存成繼承 walker 的一般場景")
	var made: Walker = (load(path) as PackedScene).instantiate()
	_level.add_child(made)
	_expect(made.max_health == 40.0 and made.speed == 128.0 and made.score == 5 and made.display_name == "_測試怪", "存出來的怪：掛件真的有效（%.0f 血、速度 %.0f）" % [made.max_health, made.speed])
	made.free()
	_expect((editor.get("_wave_page") as TDWavePage).get("_enemy_paths").has(path), "波次頁的清單有新怪")

	# 再改一次：換掉掛件，用過的波次馬上是新的
	var scene_before: PackedScene = load(path)
	page.set_trait(fast_trait, false)
	page.set_trait(split_trait, true)
	page.set_trait_value(split_trait, "count", 3)
	page.set_value("speed", 50.0)
	_expect(TDEnemyPage.dirty and (page.get("_save_button") as Button).text == "存檔＊", "改了怪物：存檔按鈕多一個＊")
	page.set_value("score", 7)
	page.set_value("score", 5)
	page.save()
	made = scene_before.instantiate()
	_level.add_child(made)
	_expect(made.speed == 50.0 and made.has_node("Split") and (made.get_node("Split") as TraitSplit).count == 3 and not made.has_node("Fast") and not TDEnemyPage.dirty, "改掛件再存：已經在用的波次也是新的")
	made.free()
	page.copy_enemy()
	_expect(page.path.is_empty() and page.data["display_name"] == "_測試怪2" and page.data["traits"].size() == 2, "複製成新怪")
	page.set_value("display_name", "_測試怪")
	_expect(page.save().is_empty(), "已經有同名的怪：不會蓋掉")
	page.open(tank_path)
	editor.call("undo")
	_expect(page.path.is_empty() and page.data["display_name"] == "_測試怪", "沒存檔就換到別隻：上一步拿得回來")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 範例的怪讀出來再存，內容不會變
	var same: bool = true
	for enemy_path: String in TDEnemyInfo.walker_paths():
		if enemy_path == TDEnemyInfo.DEFAULT_PATH or enemy_path == path:
			continue
		var before: Dictionary = TDEnemyInfo.read(enemy_path)
		var copy_path: String = TDEnemyInfo.ENEMIES_DIR + "_copy_test.tscn"
		same = TDEnemyInfo.write(copy_path, before) == OK and TDEnemyInfo.read(copy_path) == before and same
		DirAccess.remove_absolute(ProjectSettings.globalize_path(copy_path))
	_expect(same, "範例的 5 種怪：讀出來再存，一模一樣")
	editor.call("set_page", 0)
	TDEnemyPage.editing = {}
	TDEnemyPage.editing_path = ""
	TDEnemyPage.dirty = false
	TDWavePage.editing = null
	editor.set("editing", null)


## 做成關卡：繼承 tower_defense.tscn、換地圖和波次；要先存檔；不會蓋掉；範例的兩個關卡玩得起來
func _test_td_levels() -> void:
	for level_name: String in ["two_gates", "fixed_route"]:
		await _load("res://examples/tower_defense/levels/%s.tscn" % level_name)
		Engine.time_scale = TIME_SCALE
		var loader: MapLoader = _level.get_node("MapLoader")
		var spawner: Spawner = _level.get_node("Spawner")
		var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
		_expect(loader.map.resource_path.ends_with(level_name + ".tres") and spawner.wave_table.resource_path.ends_with("waves/default.tres") and loader.camera != null and loader.spawners.size() == 1, "關卡 %s：換了地圖，其他繼承 tower_defense.tscn" % level_name)
		_expect(not loader.bases.is_empty() and grid.has_path(spawner.global_position, loader.bases[0].global_position), "關卡 %s：怪走得到基地" % level_name)

	TDWavePage.editing = null
	await _load("res://examples/tower_defense/map_editor/map_editor.tscn")
	var editor: Node2D = _level
	editor.call("_new")
	_expect(String(editor.call("make_level")).is_empty(), "新地圖還沒存檔：不能做成關卡")
	(editor.get("_name_edit") as LineEdit).text = "_test_level_map"
	var map_path: String = editor.call("save_map")
	var page: TDWavePage = editor.get("_wave_page")
	page.add_wave()
	_expect(String(editor.call("make_level")).is_empty(), "波次改了沒存檔：不能做成關卡")
	(page.get("_name_edit") as LineEdit).text = "_test_level_waves"
	var waves_path: String = page.save()
	var path: String = editor.call("make_level")
	_expect(path.ends_with("levels/_test_level_map__test_level_waves.tscn") and FileAccess.file_exists(path), "做成關卡：檔名＝地圖名＋波次名")
	_expect(String(editor.call("make_level")).is_empty(), "已經有這一關：不會蓋掉")
	var made: Node = (load(path) as PackedScene).instantiate() if not path.is_empty() else null
	_expect(made != null and (made.get_node("MapLoader") as MapLoader).map.resource_path == map_path and (made.get_node("Spawner") as Spawner).wave_groups().size() == 7 and made.has_node("HUD/BuildBar"), "做出來的關卡：地圖、波次是剛剛存的，其他都在")
	if made != null:
		made.free()
	for file: String in [map_path, waves_path, path]:
		if not file.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	TDWavePage.editing = null
	editor.set("editing", null)
	editor.set("resume_test", false)


# ---- 戰棋 ----

const UNITS: String = "res://examples/tactics/features/units/"

func _test_tactics() -> void:
	print("--- 戰棋 ---")
	TacticsPool.save_path = "user://_test_tactics_party.json"
	TacticsPool.clear()
	_test_tactics_map()
	await _test_tactics_pool()
	await _test_tactics_explore()
	await _test_tactics_party()
	await _test_tactics_start()
	await _test_tactics_turns()
	await _test_tactics_traits()
	await _test_tactics_minds()
	await _test_tactics_focus()
	await _test_tactics_end()
	await _test_tactics_examples()
	await _test_tactics_editor()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TacticsPool.save_path))
	TacticsPool.save_path = "user://tactics_party.json"


## 測試用的地圖：外面一圈牆、裡面空地
func _tac_map(size: Vector2i, start: Vector2i, party: Array) -> TacticsMap:
	var map: TacticsMap = TacticsMap.new()
	map.size = size
	map.start_cell = start
	map.supplies = 1
	map.choose_party = false                                      # 測試不用編隊
	map.ensure()
	map.paint_cells(TacticsMap.Kind.WALL, Rect2i(Vector2i.ZERO, size))
	map.paint_cells(TacticsMap.Kind.PLAIN, Rect2i(Vector2i.ONE, size - Vector2i(2, 2)))
	for unit: String in party:
		map.party.append(UNITS + unit + ".tscn")
	return map


func _tac_squad(map: TacticsMap, units: Array, settings: Dictionary = {}) -> TacticsSquad:
	var squad: TacticsSquad = TacticsSquad.new()
	for unit: Array in units:
		squad.add(UNITS + String(unit[0]) + ".tscn", unit[1])
	for key: String in settings:
		squad.set(key, settings[key])
	map.squads.append(squad)
	return squad


## 用這張地圖開一關（動作之間不等，測試比較快）
func _tac_load(map: TacticsMap) -> TacticsBattle:
	TacticsLevel.test_map = map
	await _load(TACTICS)
	Engine.time_scale = TIME_SCALE
	var battle: TacticsBattle = _level.get_node("Battle")
	battle.pause_between = 0.0
	return battle


func _tac_party() -> TacticsParty:
	return _level.get_node("Party")


func _tac_squads() -> Array[EnemySquad]:
	return (_level.get_node("TacticsLevel") as TacticsLevel).squads


func _tac_put(battle: TacticsBattle, unit: Unit, cell: Vector2i) -> void:
	unit.global_position = battle.grid.cell_center(cell)


func _tac_wait(battle: TacticsBattle, condition: Callable, frames: int = 600) -> void:
	await _wait_until(func() -> bool: return condition.call() or not battle.is_active(), frames)


## 直接開打：兩邊擺在指定的格子，回合制（自己操作）
func _tac_duel(party: Array, enemies: Array, size: Vector2i = Vector2i(24, 12)) -> TacticsBattle:
	var map: TacticsMap = _tac_map(size, Vector2i(4, 6), party.map(func(a: Array) -> String: return a[0]))
	map.auto_battle = false
	map.party_size = 8
	_tac_squad(map, enemies, {"instant": true})
	var battle: TacticsBattle = await _tac_load(map)
	battle.auto = false
	for i: int in party.size():
		_tac_put(battle, battle.party[i], party[i][1])
	for i: int in enemies.size():
		_tac_put(battle, battle.squads[0].members[i], enemies[i][1])
	battle.area = Rect2i(Vector2i.ZERO, size)
	return battle


func _test_tactics_map() -> void:
	var map: TacticsMap = _tac_map(Vector2i(20, 12), Vector2i(3, 5), ["swordsman"])
	map.paint_cells(TacticsMap.Kind.SWAMP, Rect2i(5, 3, 2, 2))
	_expect(map.kind_at(Vector2i(6, 4)) == TacticsMap.Kind.SWAMP and map.kind_at(Vector2i(0, 0)) == TacticsMap.Kind.WALL, "地圖：畫得上沼澤，外圈是牆")
	_expect(map.fill(TacticsMap.Kind.FOREST, map.cell_center(Vector2i(5, 3))) > 0 and map.kind_at(Vector2i(6, 4)) == TacticsMap.Kind.FOREST, "地圖：油漆桶換掉相連的一塊")
	map.paint(TacticsMap.Kind.WALL, map.cell_center(Vector2i(12, 6)), 40.0)
	_expect(map.kind_at(Vector2i(12, 6)) == TacticsMap.Kind.WALL and map.kind_at(Vector2i(13, 6)) == TacticsMap.Kind.WALL and map.kind_at(Vector2i(13, 7)) == TacticsMap.Kind.PLAIN, "地圖：圓筆刷，格子看中心在不在裡面")
	map.paint_cells(TacticsMap.Kind.SWAMP, Rect2i(12, 6, 1, 1))
	_expect(map.kind_at(Vector2i(12, 6)) == TacticsMap.Kind.SWAMP and map.sample(TacticsMap.Kind.WALL, map.cell_center(Vector2i(12, 6))) == 0.0, "地圖：畫上沼澤，底下的牆擦掉；方的和圓的可以混用")
	map.paint_cells(TacticsMap.Kind.PLAIN, Rect2i(10, 4, 5, 5))
	map.chests = {Vector2i(18, 3): 2}
	_expect(not map.problem().is_empty(), "地圖：沒有敵人就不能玩（%s）" % map.problem())
	_tac_squad(map, [["archer", Vector2i(15, 5)], ["knight", Vector2i(18, 10)]])
	_expect(map.problem().is_empty(), "地圖：有敵人就能玩")
	var before: Dictionary = map.snapshot()
	map.resize(Vector2i(17, 12))
	_expect(map.squads[0].members.size() == 1 and map.chests.is_empty() and map.kind_at(Vector2i(6, 4)) == TacticsMap.Kind.FOREST, "改小：外面的敵人拿掉，畫好的留著")
	map.restore(before)
	_expect(map.snapshot() == before and map.squads[0].members.size() == 2 and map.chests.size() == 1, "還原：跟改之前一模一樣")
	map.win = TacticsMap.Win.BOSS
	_expect(not map.problem().is_empty(), "勝利條件是首領，但沒有首領小隊：不能玩")


## 探索：撞牆、隊友跟上、撿物資、紮營
func _test_tactics_explore() -> void:
	var map: TacticsMap = _tac_map(Vector2i(30, 14), Vector2i(4, 6), ["swordsman", "archer", "healer"])
	map.paint_cells(TacticsMap.Kind.WALL, Rect2i(9, 1, 1, 12))
	map.supply_cells = [Vector2i(7, 6)]
	map.chests = {Vector2i(4, 3): 2, Vector2i(6, 3): 0}
	_tac_squad(map, [["knight", Vector2i(26, 6)]], {"start_angle": 0.0})
	var battle: TacticsBattle = await _tac_load(map)
	var party: TacticsParty = _tac_party()
	_expect(party.members.size() == 3 and party.leader().is_in_group("player") and not battle.is_active(), "探索：隊伍 3 隻，隊長是鏡頭和視野的目標")
	Input.action_press("move_right")
	await _frames(120)
	Input.action_release("move_right")
	var x: float = party.leader().global_position.x
	_expect(x > 7 * 32 and x < 9 * 32, "探索：往右走，撞到牆就停（%.0f）" % x)
	await _frames(60)
	_expect(party.members[2].global_position.x > 5 * 32, "探索：隊友跟上來")
	_expect(party.supplies == 2 and get_tree().get_nodes_in_group("tactics_party").size() == 1, "探索：撿到物資（%d）" % party.supplies)
	_expect(not party.start_camp(), "紮營：大家都滿血，不用休息")
	party.leader().take_damage(15)
	party.members[1].take_damage(10)
	var hurt: int = party.leader().health
	_expect(party.start_camp(), "紮營：有人受傷就可以")
	await _wait_until(func() -> bool: return party.camping <= 0.0, 400)
	_expect(party.supplies == 1 and party.leader().health == hurt + 12, "紮營：花一份物資、回復一半的血（%d → %d）" % [hurt, party.leader().health])
	party.leader().take_damage(10)
	party.start_camp()
	_tac_squads()[0].alert = 0.5
	await _frames(2)
	_expect(party.camping == 0.0 and party.supplies == 1, "紮營：敵人注意到就中斷，物資不會少")
	_tac_squads()[0].alert = 0.0
	party.supplies = 0
	_expect(not party.start_camp(), "紮營：沒有物資不能休息")
	# 寶箱
	party.leader().global_position = battle.grid.cell_center(Vector2i(4, 4))
	var chest: TacticsChest = party.nearest_chest()
	_expect(chest != null and chest.amount == 2 and party.start_search(chest), "寶箱：走到旁邊可以搜")
	_tac_squads()[0].alert = 0.5
	await _frames(2)
	_expect(party.searching == null and not chest.opened, "寶箱：敵人注意到就中斷")
	_tac_squads()[0].alert = 0.0
	party.start_search(chest)
	await _wait_until(func() -> bool: return party.searching == null, 400)
	_expect(chest.opened and party.supplies == 2 and party.nearest_chest() != chest, "寶箱：搜到 2 份物資，不能再搜一次")
	# 左鍵移動
	party.leader().global_position = battle.grid.cell_center(Vector2i(2, 2))
	party.walk_to(battle.grid.cell_center(Vector2i(2, 11)))
	await _frames(20)
	_expect(party.leader().follower().is_moving() and party.leader().global_position.y > 3 * 32, "左鍵移動：自己走過去")
	Input.action_press("move_up")
	await _frames(3)
	Input.action_release("move_up")
	_expect(not party.leader().follower().is_moving(), "左鍵移動：按 WASD 就取消")
	party.leader().global_position = battle.grid.cell_center(Vector2i(2, 8))
	party.walk_to(battle.grid.cell_center(Vector2i(6, 3)))
	await _wait_until(func() -> bool: return party.searching != null, 600)
	_expect(party.searching != null and party.searching.amount == 0, "左鍵移動：點寶箱，走過去就搜")
	await _wait_until(func() -> bool: return party.searching == null, 400)
	_expect(party.nearest_chest() == null and party.supplies == 2, "空的寶箱：沒有東西")
	# 圓滑的牆：照邊緣擋
	party.leader().global_position = battle.grid.cell_center(Vector2i(4, 9))
	(_level.get_node("TacticsLevel") as TacticsLevel).map.paint(TacticsMap.Kind.WALL, battle.grid.cell_center(Vector2i(7, 9)) - Vector2(16, 0), 14.0)
	Input.action_press("move_right")
	await _frames(60)
	Input.action_release("move_right")
	x = party.leader().global_position.x
	_expect(x > 6 * 32 - 24 and x < 7 * 32, "圓滑的牆：撞到邊緣就停，不是整格（%.0f）" % x)


## 隊伍池：起始隊伍、招募、過關獎勵、固定隊伍、試玩不存
func _test_tactics_pool() -> void:
	var start: Array[String] = TacticsPool.start_units()
	_expect(start.size() >= 5 and TacticsPool.units() == start, "隊伍池：一開始只有起始隊伍（%d 人）" % start.size())
	var map: TacticsMap = _tac_map(Vector2i(24, 12), Vector2i(4, 6), [])
	map.map_name = "_test_pool"
	map.win = TacticsMap.Win.GOAL
	map.goal_cells = [Vector2i(20, 6)]
	map.allies = {Vector2i(6, 3): UNITS + "mage.tscn"}
	map.rewards = [UNITS + "assassin.tscn"]
	_tac_squad(map, [["lizard", Vector2i(22, 10)]], {"start_angle": 0.0, "view_distance": 40.0})
	_expect(map.problem().is_empty() and map.roster() == start, "沒有固定隊伍：用隊伍池")
	var battle: TacticsBattle = await _tac_load(map.copy())
	var party: TacticsParty = _tac_party()
	_expect(party.members.size() == start.size() and party.nearest_ally() == null, "隊伍池：全部都帶進來")
	party.walk_to(battle.grid.cell_center(Vector2i(6, 3)))
	await _wait_until(func() -> bool: return party.members.size() > start.size(), 400)
	_expect(party.members.size() == start.size() + 1 and party.members[start.size()].display_name == "法師" and battle.party.size() == start.size() + 1, "招募：點同伴走過去，當場加入")
	_expect(TacticsPool.units() == start, "招募：還沒過關，隊伍池還沒有他")
	battle = await _tac_load(map.copy())
	await _frames(2)
	_expect(get_tree().get_nodes_in_group("tactics_allies").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).size() == 1, "重來：同伴還在，要重新招募")
	party = _tac_party()
	party.leader().global_position = battle.grid.cell_center(Vector2i(6, 4))
	await _frames(2)
	_press(KEY_E)
	await _frames(2)
	_expect(party.members.size() == start.size() + 1, "招募：走到旁邊按 E")
	party.captain().global_position = battle.grid.cell_center(Vector2i(20, 6))
	await _frames(4)
	_expect(GameFlow.is_finished() and TacticsPool.units().size() == start.size() + 2, "過關：招募到的和獎勵都進隊伍池（%d 人）" % TacticsPool.units().size())
	TacticsPool._loaded_path = ""
	_expect(TacticsPool.units().size() == start.size() + 2, "隊伍池：關掉重開還在")
	battle = await _tac_load(map.copy())
	await _frames(2)
	party = _tac_party()
	_expect(get_tree().get_nodes_in_group("tactics_allies").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).is_empty() and party.members.size() == start.size() + 2, "再玩一次：同伴不會再出現，隊伍多兩個")
	party.captain().global_position = battle.grid.cell_center(Vector2i(20, 6))
	await _frames(4)
	_expect(TacticsPool.units().size() == start.size() + 2, "再過一次：獎勵不會重複拿")
	map.party = [UNITS + "knight.tscn"]
	_expect(map.roster().size() == 1, "固定隊伍：只用這些人")
	TacticsPool.begin_test()
	_expect(TacticsPool.units() == start and TacticsPool.add("a", UNITS + "mage.tscn") and TacticsPool.units().size() == start.size() + 1, "試玩：從起始隊伍開始")
	TacticsPool.end_test()
	_expect(TacticsPool.units().size() == start.size() + 2, "試玩：不會動到真正的存檔")
	TacticsPool.clear()
	_expect(TacticsPool.units() == start, "清掉存檔：只剩起始隊伍")


## 陣形、整隊／分開、換人控制、趕來支援、上場人數不限
func _test_tactics_party() -> void:
	var map: TacticsMap = _tac_map(Vector2i(50, 16), Vector2i(8, 8), ["swordsman", "archer", "healer", "knight", "mage", "cavalry", "flyer"])
	_tac_squad(map, [["lizard", Vector2i(46, 2)]], {"start_angle": 0.0, "view_distance": 60.0})
	var battle: TacticsBattle = await _tac_load(map.copy())
	var party: TacticsParty = _tac_party()
	var camera: FollowCamera = _level.get_node("FollowCamera")
	for kind: int in [1, 2, 3]:
		_press(KEY_1 + kind)
		party.leader().global_position = battle.grid.cell_center(Vector2i(8, 8))
		party.leader().facing = Vector2.RIGHT
		await _frames(150)
		var bad: int = 0
		for i: int in range(1, party.members.size()):
			var want: Vector2 = party.leader().global_position + TacticsFormation.offset(party.formation, i, 7, Vector2.RIGHT, party.follow_distance)
			if party.members[i].global_position.distance_to(want) > 14.0:
				bad += 1
		_expect(party.formation == kind and bad == 0, "陣形「%s」：每一隻都走到自己的位置（差太遠 %d 隻）" % [TacticsFormation.NAMES[kind], bad])
	party.leader().global_position = battle.grid.cell_center(Vector2i(1, 1))
	await _frames(150)
	_expect(party.members.all(func(u: Unit) -> bool: return u.is_flying() or battle.grid.is_walkable(u.global_position)), "陣形：在牆角會擠到空的格子")
	# 分開走
	_press(KEY_TAB)
	await _frames(2)
	_expect(party.split and party.exposed().size() == 7, "Tab：分開走，每個人都會被看到")
	var stay: Vector2 = party.members[1].global_position
	party.leader().global_position = battle.grid.cell_center(Vector2i(12, 12))
	await _frames(20)
	_expect(party.members[1].global_position == stay, "分開走：其他人站在原地")
	_press(KEY_Q)
	_press(KEY_Q)
	await _frames(2)
	_expect(party.leader() == party.members[2] and camera.target == party.members[2] and party.captain() == party.members[0], "Q：換控制下一個，鏡頭跟著他，隊長還是第 1 個")
	party.walk_to(battle.grid.cell_center(Vector2i(4, 8)))
	await _frames(60)
	_expect(party.members[2].global_position.distance_to(battle.grid.cell_center(Vector2i(4, 8))) < 40.0 and party.members[1].global_position == stay, "左鍵移動：走的是控制的人")
	# 開打：近的一起布陣、遠的趕來
	for i: int in 7:
		_tac_put(battle, party.members[i], Vector2i(2, 2 + i))
	party.control(party.members[4])
	_tac_put(battle, party.members[4], Vector2i(42, 3))
	_tac_put(battle, party.members[5], Vector2i(38, 6))
	_tac_squads()[0].leader().facing = Vector2.LEFT
	_tac_squads()[0].spotted.emit(_tac_squads()[0], false, party.members[5])
	_expect(battle.anchor == party.members[5] and battle.available.size() == 2 and battle.late.size() == 5, "分開走：10 格內的一起布陣，其他的在路上（%d 隻、%d 隻）" % [battle.available.size(), battle.late.size()])
	var far: Unit = party.members[0]
	var near_round: int = battle.late[party.members[6]]
	_expect(battle.late[far] > near_round and near_round > 1, "趕來支援：走得快的先到（飛行兵第 %d 輪、劍士第 %d 輪）" % [near_round, battle.late[far]])
	_expect(not battle.set_deployed(party.members[5], false), "布陣：被發現的人一定要上場")
	(_level.get_node("HUD") as TacticsHud).refresh()
	battle.auto = true
	_tac_squads()[0].leader().max_health = 9999
	_tac_squads()[0].leader().health = 9999
	_tac_squads()[0].leader().attack = 0
	battle.begin_fight()
	battle.game_speed = 6.0
	await _wait_until(func() -> bool: return battle.round_number >= near_round and battle.fighters.has(party.members[6]), 2000)
	_expect(battle.fighters.has(party.members[6]) and battle.area.has_point(battle.cell_of(party.members[6])) and not battle.late.has(party.members[6]), "趕來支援：到了就在戰場裡")
	await _wait_until(func() -> bool: return battle.late.is_empty(), 4000)
	_expect(battle.alive(0).size() == 7, "趕來支援：最後全部到齊")
	# 倍速留到下一場、上場不限
	battle.game_speed = 3.0
	_tac_squads()[0].leader().take_damage(99999)
	await _wait_until(func() -> bool: return not battle.is_active(), 600)
	map.win = TacticsMap.Win.GOAL
	map.goal_cells = [Vector2i(1, 1)]
	map.allow_split = false
	_tac_squad(map, [["lizard", Vector2i(40, 12)]], {"start_angle": 0.0, "view_distance": 60.0})
	battle = await _tac_load(map.copy())
	party = _tac_party()
	_expect(not party.set_split(true), "規則：不能分開走")
	battle.start(_tac_squads()[0])
	_expect(battle.deployed().size() == 7, "上場人數：預設不限，7 隻全上")
	battle.begin_fight()
	battle.game_speed = 3.0
	_tac_squads()[0].leader().take_damage(99999)
	await _wait_until(func() -> bool: return not battle.is_active(), 600)
	_expect(is_equal_approx(Engine.time_scale, 1.0) and is_equal_approx(battle.game_speed, 3.0), "打完：探索是 1×，選的倍速還記著")
	battle.start(_tac_squads()[0])
	battle.begin_fight()
	_expect(is_equal_approx(Engine.time_scale, 3.0), "下一場：還是 3×")


	# 編隊畫面
	map.choose_party = true
	map.party_max = 3
	map.map_name = "_test_setup"
	await _tac_load(map.copy())
	var level: TacticsLevel = _level.get_node("TacticsLevel")
	await _frames(3)
	var screen: TacticsPartySetup = level.setup_screen
	_expect(screen != null and screen.chosen == [0, 1, 2] and level.squads.is_empty() and not (_level.get_node("HUD") as TacticsHud).visible, "編隊：先選好前 3 個，敵人還沒出現")
	screen.toggle(6)
	_expect(screen.chosen.size() == 3, "編隊：滿了不能再選")
	screen.toggle(1)
	screen.toggle(6)
	screen.move(2, -1)
	screen.move(1, -1)
	_press(KEY_3)
	_expect(screen.chosen == [6, 0, 2] and screen.formation == TacticsFormation.Kind.ARROW, "編隊：換人、排順序、按 3 選箭頭")

	screen.go()
	await _frames(3)
	party = _tac_party()
	_expect(party.members.size() == 3 and party.captain().is_flying() and party.formation == TacticsFormation.Kind.ARROW and level.squads.size() == 2, "編隊：出發，隊長是飛行兵")
	# 飛行兵：探索時直線飛過牆
	battle = _level.get_node("Battle")
	for y: int in range(1, 15):
		level.map.paint_cells(TacticsMap.Kind.WALL, Rect2i(14, y, 2, 1))
		battle.grid.set_blocked(Vector2i(14, y), true)
		battle.grid.set_blocked(Vector2i(15, y), true)
	party.set_formation(0)
	_tac_put(battle, party.leader(), Vector2i(12, 8))
	Input.action_press("move_right")
	await _wait_until(func() -> bool: return party.leader().global_position.x > 15 * 32, 200)
	_expect(party.leader().lift > 8.0, "飛行兵：越過牆的時候升高（%.0f）" % party.leader().lift)
	await _wait_until(func() -> bool: return party.leader().global_position.x > 17 * 32, 200)
	Input.action_release("move_right")
	_expect(party.leader().global_position.x > 17 * 32, "飛行兵：WASD 飛過牆")
	party.walk_to(battle.grid.cell_center(Vector2i(10, 8)))
	await _wait_until(func() -> bool: return not party.leader().follower().is_moving(), 400)
	_expect(battle.grid.cell_of(party.leader().global_position) == Vector2i(10, 8), "飛行兵：左鍵也直線飛回來")
	# 重來：記得上次選的
	await _tac_load(map.copy())
	await _frames(3)
	screen = (_level.get_node("TacticsLevel") as TacticsLevel).setup_screen
	_expect(screen.chosen == [6, 0, 2] and screen.formation == TacticsFormation.Kind.ARROW, "編隊：重來會記得上次選的")


func _press(key: int) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key as Key
	event.keycode = key as Key
	event.pressed = true
	get_viewport().push_input(event)


## 被發現、偷襲、支援、布陣
func _test_tactics_start() -> void:
	var map: TacticsMap = _tac_map(Vector2i(30, 14), Vector2i(4, 6), ["swordsman", "archer", "healer", "knight", "mage"])
	map.party_size = 3
	_tac_squad(map, [["knight", Vector2i(18, 6)]], {"start_angle": 180.0, "view_distance": 200.0, "reaction_time": 0.5})
	_tac_squad(map, [["archer", Vector2i(24, 6)]], {"start_angle": 0.0, "support": 8})
	_tac_squad(map, [["lizard", Vector2i(27, 11)]], {"start_angle": 0.0})
	var battle: TacticsBattle = await _tac_load(map)
	var party: TacticsParty = _tac_party()
	await _frames(20)
	_expect(not battle.is_active(), "太遠：沒被發現")
	party.leader().global_position = battle.grid.cell_center(Vector2i(13, 6))
	await _frames(6)
	_expect(_tac_squads()[0].alert > 0.0 and _tac_squads()[0].leader().alert_mark == "?" and not battle.is_active(), "看到隊長：先 ?，還沒開打")
	party.leader().global_position = battle.grid.cell_center(Vector2i(4, 2))
	await _wait_until(func() -> bool: return _tac_squads()[0].alert <= 0.0, 400)
	_expect(_tac_squads()[0].alert <= 0.0 and _tac_squads()[0].leader().alert_mark == "", "走開：警戒值降回去")
	party.leader().global_position = battle.grid.cell_center(Vector2i(13, 6))
	await _wait_until(func() -> bool: return battle.is_active(), 200)
	_expect(battle.state == TacticsBattle.State.DEPLOY and not battle.is_ambush, "看滿反應時間：進入布陣")
	_expect(battle.squads.size() == 2, "支援：夠近、有設支援距離的小隊加入，其他的不會（%d 隊）" % battle.squads.size())
	_expect(battle.deployed().size() == 3 and not party.members[4].visible, "布陣：先擺好 3 隻，其他的沒上場")
	_expect(battle.deployed().all(func(u: Unit) -> bool: return battle.deploy_cells.has(battle.cell_of(u))), "布陣：都站在藍色格子裡")
	_expect(not battle.set_deployed(party.members[4], true) and not battle.set_deployed(party.leader(), false), "布陣：滿了不能再上，隊長不能下")
	_expect(battle.set_deployed(party.members[1], false) and battle.set_deployed(party.members[4], true) and battle.deployed().has(party.members[4]), "布陣：換人上場")
	var a: Vector2i = battle.cell_of(party.leader())
	var b: Vector2i = battle.cell_of(party.members[4])
	battle.click(b)
	_expect(battle.picked == party.members[4], "布陣：點自己的棋子拿起來")
	battle.click(a)
	_expect(battle.cell_of(party.leader()) == b and battle.cell_of(party.members[4]) == a, "布陣：點自己人＝交換位置")
	var free: Vector2i = battle._free_deploy_cell()
	battle.click(a)
	battle.click(free)
	_expect(battle.cell_of(party.members[4]) == free, "布陣：點藍色空格擺過去")
	_expect(not battle.place(party.members[4], Vector2i(28, 12)), "布陣：藍色以外不能擺")
	var other: EnemySquad = _tac_squads()[2]
	var at: Vector2 = other.leader().global_position
	await _frames(30)
	_expect(other.leader().global_position == at and battle.state == TacticsBattle.State.DEPLOY, "布陣：時間暫停，別的小隊不動")

	# 隊友也有視野、隊形、原地張望
	map = _tac_map(Vector2i(30, 14), Vector2i(2, 12), ["swordsman"])
	_tac_squad(map, [["knight", Vector2i(10, 4)], ["archer", Vector2i(12, 4)], ["mage", Vector2i(10, 6)]], {"start_angle": 0.0, "view_angle": 60.0, "reaction_time": 0.4})
	map.squads[0].patrol = [Vector2i(10, 4), Vector2i(20, 4)]
	_tac_squad(map, [["lizard", Vector2i(22, 9)], ["lizard", Vector2i(24, 9)]], {"start_angle": 0.0})
	battle = await _tac_load(map.copy())
	var group: EnemySquad = _tac_squads()[0]
	var stand: EnemySquad = _tac_squads()[1]
	var before: float = stand.members[1].facing.angle()
	await _frames(60)
	_expect(absf(angle_difference(before, stand.members[1].facing.angle())) > 0.1 and stand.members[1].global_position == battle.grid.cell_center(Vector2i(24, 9)), "沒有巡邏點：隊友也站在原地張望")
	await _wait_until(func() -> bool: return group.leader().global_position.x > 19 * 32 + 8, 900)
	await _frames(30)
	var shape: Array = group.members.map(func(u: Unit) -> Vector2i: return battle.grid.cell_of(u.global_position) - battle.grid.cell_of(group.leader().global_position))
	_expect(shape == [Vector2i.ZERO, Vector2i(2, 0), Vector2i(0, 2)], "巡邏：照擺的位置排成隊形一起走（%s）" % str(shape))
	var mate: Unit = stand.members[1]
	_tac_party().leader().global_position = mate.global_position + mate.facing * 70.0
	await _wait_until(func() -> bool: return stand.alert > 0.0, 60)
	_expect(stand.seen == _tac_party().leader() and stand.members[0].alert_mark != "", "隊友看到：全隊一起警戒")
	map.squads[1].leader_only = true
	battle = await _tac_load(map.copy())
	_expect(_tac_squads()[1].visions[1] == null and _tac_squads()[1].visions[0] != null, "只有帶頭的有視野：隊友沒有")
	map = _tac_map(Vector2i(30, 14), Vector2i(4, 6), ["swordsman", "archer", "healer", "knight", "mage"])
	map.party_size = 3
	_tac_squad(map, [["knight", Vector2i(18, 6)]], {"start_angle": 180.0})

	# 偷襲：從背後碰到
	map.squads[0].start_angle = 0.0
	battle = await _tac_load(map.copy())
	_tac_party().leader().global_position = battle.grid.cell_center(Vector2i(17, 6))
	await _frames(4)
	_expect(battle.is_active() and battle.is_ambush, "從背後碰到：偷襲")
	var order: Array[Unit] = battle.make_order()
	_expect(order[0].team == 0 and order[1].team == 0 and order[2].team == 0 and order[3].team == 1, "偷襲：第一輪我方全部先動")


## 速度順序、自動／回合制、走、打、反悔、倍速、暫停
func _test_tactics_turns() -> void:
	var battle: TacticsBattle = await _tac_duel([["swordsman", Vector2i(4, 6)], ["cavalry", Vector2i(4, 8)]], [["knight", Vector2i(9, 6)], ["assassin", Vector2i(20, 6)]])
	_expect(battle.state == TacticsBattle.State.DEPLOY, "一開始就開打：直接進布陣")
	battle.is_ambush = false
	var marks: Array = battle.make_order().map(func(u: Unit) -> String: return u.mark)
	_expect(marks == ["刺", "騎", "劍", "盾"], "順序：照速度由快到慢（%s）" % "".join(marks))
	battle.begin_fight()
	await _tac_wait(battle, func() -> bool: return battle.is_waiting)
	var cavalry: Unit = battle.party[1]
	_expect(battle.current == cavalry and battle.is_waiting, "輪到騎兵：等玩家選")
	_expect(battle.move_range.cells.size() > 10 and battle.move_range.has_cell(Vector2i(7, 8)) and not battle.move_range.has_cell(Vector2i(12, 8)), "回合制：亮出走得到的格子（移動力 6）")
	battle.click(Vector2i(8, 8))
	await _tac_wait(battle, func() -> bool: return battle.is_waiting and battle.has_moved)
	_expect(battle.cell_of(cavalry) == Vector2i(8, 8) and cavalry.steps_taken == 4, "點藍色格子：走過去（4 格）")
	_expect(battle.move_range.cells.is_empty(), "走過了：不能再走")
	battle.choose_undo()
	await _tac_wait(battle, func() -> bool: return battle.is_waiting and not battle.has_moved)
	_expect(battle.cell_of(cavalry) == Vector2i(4, 8) and cavalry.steps_taken == 0, "反悔：回到原本的格子")
	var knight: Unit = battle.squads[0].members[0]
	_expect(battle.target_units.has(knight), "走過去打得到的敵人：紅框")
	battle.click(Vector2i(4, 8))
	await _tac_wait(battle, func() -> bool: return battle.is_waiting and battle.has_moved)
	_expect(battle.cell_of(cavalry) == Vector2i(4, 8) and battle.move_range.cells.is_empty() and not battle.target_units.has(knight), "點自己：留在原地，只能打站著打得到的")
	battle.choose_undo()
	await _tac_wait(battle, func() -> bool: return battle.is_waiting and not battle.has_moved)
	_expect(battle.target_units.has(knight), "留在原地也可以反悔")
	battle.hovered = knight
	(_level.get_node("HUD") as TacticsHud).refresh()
	var before: int = knight.health
	battle.click(Vector2i(9, 6))                                 # 直接點敵人：走到打得到的格子再打
	await _tac_wait(battle, func() -> bool: return battle.current != cavalry)
	_expect(battle.distance(battle.cell_of(cavalry), Vector2i(9, 6)) == 1 and knight.health < before, "直接點敵人：走過去打（扣 %d）" % (before - knight.health))

	# 暫停、倍速
	battle.game_speed = 3.0
	_expect(is_equal_approx(Engine.time_scale, 3.0), "倍速：3×")
	battle.paused = true
	_expect(is_zero_approx(Engine.time_scale), "暫停：時間停住")
	get_tree().paused = true
	_expect(not battle.paused and Engine.time_scale > 0.0, "戰鬥暫停時打開選單：時間恢復，換場景不會卡住")
	get_tree().paused = false
	_expect(is_equal_approx(Engine.time_scale, 3.0), "繼續：回到 3×")
	(_level.get_node("HUD") as TacticsHud).next_speed()
	_expect(is_equal_approx(battle.game_speed, 1.0), "倍速按鈕：3× 之後回到 1×")
	battle.game_speed = 3.0

	# 待命、切換成自動
	await _tac_wait(battle, func() -> bool: return battle.is_waiting)
	var sword: Unit = battle.current
	battle.choose_wait()
	await _tac_wait(battle, func() -> bool: return battle.current != sword)
	_expect(battle.current != sword, "待命：換下一隻")
	await _tac_wait(battle, func() -> bool: return battle.is_waiting)
	var waiting: Unit = battle.current
	battle.auto = true
	await _tac_wait(battle, func() -> bool: return battle.current != waiting)
	_expect(not battle.is_waiting and battle.current != waiting, "輪到玩家時切成自動：電腦接手這一步")
	await _wait_until(func() -> bool: return not battle.is_active(), 4000)
	_expect(not battle.is_active(), "自動：打到分出勝負")


## 每一種特性
func _test_tactics_traits() -> void:
	# 飛行、沼澤行者、攔截
	var battle: TacticsBattle = await _tac_duel([["flyer", Vector2i(4, 6)], ["lizard", Vector2i(4, 8)], ["swordsman", Vector2i(4, 10)]], [["knight", Vector2i(18, 2)]])
	battle.state = TacticsBattle.State.FIGHT
	battle._map.paint_cells(TacticsMap.Kind.SWAMP, Rect2i(5, 7, 3, 4))
	battle._map.paint_cells(TacticsMap.Kind.WALL, Rect2i(6, 5, 1, 2))
	for y: int in range(7, 11):
		for x: int in range(5, 8):
			battle.grid.set_cost(Vector2i(x, y), 3.0)
	for y: int in [5, 6]:
		battle.grid.set_blocked(Vector2i(6, y), true)
	var moves: Dictionary[Vector2i, float] = battle.legal_moves(battle.party[0])
	_expect(moves.has(Vector2i(8, 6)) and not moves.has(Vector2i(6, 6)) and moves[Vector2i(6, 8)] == 4.0, "飛行：越過牆、沼澤一格算 1，不能停在牆上")
	_expect(battle.legal_moves(battle.party[1]).has(Vector2i(7, 8)), "沼澤行者：沼澤像平地")
	_expect(battle.legal_moves(battle.party[2]).has(Vector2i(5, 10)) and not battle.legal_moves(battle.party[2]).has(Vector2i(6, 10)), "一般棋子：沼澤一格算 3")
	_tac_put(battle, battle.party[2], Vector2i(14, 3))
	_tac_put(battle, battle.squads[0].members[0], Vector2i(16, 2))
	moves = battle.legal_moves(battle.party[2])
	_expect(moves.has(Vector2i(15, 2)) and moves.has(Vector2i(16, 3)) and not moves.has(Vector2i(17, 3)), "攔截：走到重裝兵旁邊就得停")
	_expect(not moves.has(Vector2i(16, 2)), "敵人的格子不能走")

	# 突擊、反擊、守護、地形防禦
	battle = await _tac_duel([["cavalry", Vector2i(4, 6)], ["assassin", Vector2i(4, 8)]], [["swordsman", Vector2i(10, 6)], ["knight", Vector2i(10, 9)]])
	battle.state = TacticsBattle.State.FIGHT
	var cavalry: Unit = battle.party[0]
	var sword: Unit = battle.squads[0].members[0]
	var knight: Unit = battle.squads[0].members[1]
	_expect(battle.damage_of(cavalry, sword, 0) == 4 and battle.damage_of(cavalry, sword, 4) == 8, "突擊：走 4 格多 4 點（4 → 8）")
	battle._map.paint_cells(TacticsMap.Kind.FOREST, Rect2i(Vector2i(10, 6), Vector2i.ONE))
	_expect(battle.damage_of(cavalry, sword, 0) == 3, "森林：防禦 +1")
	battle._map.paint_cells(TacticsMap.Kind.PLAIN, Rect2i(Vector2i(10, 6), Vector2i.ONE))
	_tac_put(battle, knight, Vector2i(10, 7))
	_expect(battle.damage_of(cavalry, sword, 4) == roundi(8 * 0.6), "守護：旁邊有重裝兵，只扣六成")
	_tac_put(battle, knight, Vector2i(20, 2))
	_tac_put(battle, cavalry, Vector2i(9, 6))
	cavalry.steps_taken = 0
	var before: int = cavalry.health
	await battle.strike(cavalry, sword)
	_expect(cavalry.health == before - roundi(7 * 0.8 - 2), "反擊：劍士還手（扣 %d）" % (before - cavalry.health))
	# 吸血
	var assassin: Unit = battle.party[1]
	assassin.take_damage(10)
	_tac_put(battle, assassin, Vector2i(10, 5))
	before = assassin.health
	sword.heal(99)
	await battle.strike(assassin, sword)
	_expect(assassin.health == before + 3 - roundi(7 * 0.8), "吸血：扣 6 補 3，再被還手（%d → %d）" % [before, assassin.health])

	# 範圍、擊退、治療
	battle = await _tac_duel([["mage", Vector2i(8, 6)], ["hammer", Vector2i(4, 8)], ["healer", Vector2i(4, 3)]], [["archer", Vector2i(10, 6)], ["lizard", Vector2i(11, 6)], ["lizard", Vector2i(10, 8)]])
	battle.state = TacticsBattle.State.FIGHT
	var archer: Unit = battle.squads[0].members[0]
	var near: Unit = battle.squads[0].members[1]
	var far: Unit = battle.squads[0].members[2]
	await battle.strike(battle.party[0], archer)
	_expect(archer.health == archer.max_health - 8 and near.health == near.max_health - 4 and far.health == far.max_health, "範圍攻擊：旁邊的扣一半，遠的沒事")
	var hammer: Unit = battle.party[1]
	_tac_put(battle, hammer, Vector2i(10, 9))
	before = far.health
	await battle.strike(hammer, far)
	_expect(battle.cell_of(far) == Vector2i(10, 7) and far.health == before - 7, "擊退：推開一格")
	_tac_put(battle, hammer, Vector2i(10, 8))
	before = far.health
	await battle.strike(hammer, far)
	_expect(battle.cell_of(far) == Vector2i(10, 7) and far.health == before - 10, "擊退：後面有人推不動，多扣 3")
	var healer: Unit = battle.party[2]
	_tac_put(battle, healer, Vector2i(8, 4))
	_expect(not battle.can_target(healer, battle.party[0]), "治療：沒受傷的不能補")
	battle.party[0].take_damage(10)
	before = battle.party[0].health
	_expect(battle.can_target(healer, battle.party[0]), "治療：受傷的可以補")
	await battle.act(healer, battle.party[0])
	_expect(battle.party[0].health == before + 7, "治療：補 7")
	# 射程、高地、牆
	var bow: Unit = archer
	_tac_put(battle, bow, Vector2i(14, 6))
	_expect(not battle.in_range(bow, Vector2i(14, 6), Vector2i(15, 6)) and battle.in_range(bow, Vector2i(14, 6), Vector2i(17, 6)) and not battle.in_range(bow, Vector2i(14, 6), Vector2i(18, 6)), "弓箭手：旁邊打不到，2～3 格打得到")
	battle._map.paint_cells(TacticsMap.Kind.HIGH, Rect2i(Vector2i(14, 6), Vector2i.ONE))
	_expect(battle.in_range(bow, Vector2i(14, 6), Vector2i(18, 6)), "高地：遠程多一格")
	battle._map.paint_cells(TacticsMap.Kind.WALL, Rect2i(Vector2i(16, 6), Vector2i.ONE))
	_expect(not battle.in_range(bow, Vector2i(14, 6), Vector2i(17, 6)), "牆擋住遠程")


## 電腦的四種個性
func _test_tactics_minds() -> void:
	var battle: TacticsBattle = await _tac_duel([["swordsman", Vector2i(8, 6)], ["mage", Vector2i(11, 9)]], [["lizard", Vector2i(11, 6)]])
	battle.state = TacticsBattle.State.FIGHT
	var foe: Unit = battle.squads[0].members[0]
	foe.mind = Unit.Mind.CHARGE
	battle.party[1].take_damage(8)
	foe.mind = Unit.Mind.WEAKEST
	_expect(battle.ai.plan(foe)["target"] == battle.party[1], "挑最弱的：打血少的法師")
	foe.mind = Unit.Mind.GUARD
	_tac_put(battle, battle.party[0], Vector2i(2, 2))
	_tac_put(battle, battle.party[1], Vector2i(2, 9))
	_expect(battle.ai.plan(foe)["cell"] == Vector2i(11, 6), "守衛：沒有人靠近就不動")
	foe.take_damage(1)
	_expect(battle.ai.plan(foe)["cell"] != Vector2i(11, 6), "守衛：被打過就醒來")
	foe.mind = Unit.Mind.CHARGE
	var plan: Dictionary = battle.ai.plan(foe)
	_expect(plan["target"] == null and battle.distance(plan["cell"], Vector2i(2, 9)) < battle.distance(Vector2i(11, 6), Vector2i(2, 9)), "衝鋒：打不到就往敵人靠近")
	foe.mind = Unit.Mind.DISTANCE
	foe.max_range = 3
	_tac_put(battle, battle.party[1], Vector2i(10, 6))
	plan = battle.ai.plan(foe)
	_expect(plan["target"] == battle.party[1] and battle.distance(plan["cell"], Vector2i(10, 6)) == 3, "保持距離：站到打得到的最遠處")
	# 隔著牆：繞路
	battle = await _tac_duel([["swordsman", Vector2i(4, 6)]], [["lizard", Vector2i(12, 6)]])
	battle.state = TacticsBattle.State.FIGHT
	for y: int in range(1, 10):
		battle.grid.set_blocked(Vector2i(9, y), true)
	foe = battle.squads[0].members[0]
	plan = battle.ai.plan(foe)
	_expect((plan["cell"] as Vector2i).y > 6, "路被牆擋住：往缺口繞（%s）" % plan["cell"])


## 指定目標、意圖、骰子、日誌
func _test_tactics_focus() -> void:
	var battle: TacticsBattle = await _tac_duel([["swordsman", Vector2i(8, 6)], ["healer", Vector2i(6, 6)]], [["lizard", Vector2i(10, 6)], ["knight", Vector2i(8, 9)], ["archer", Vector2i(20, 9)]])
	battle.auto = true
	var sword: Unit = battle.party[0]
	var lizard: Unit = battle.squads[0].members[0]
	var knight: Unit = battle.squads[0].members[1]
	var archer: Unit = battle.squads[0].members[2]
	var lines: PackedStringArray = PackedStringArray()
	battle.noted.connect(func(text: String) -> void: lines.append(text))
	for unit: Unit in [lizard, knight]:
		battle.set_focus(unit)
		_expect(battle.ai.plan(sword)["target"] == unit, "指定目標：兩隻都打得到，打指定的（%s）" % unit.display_name)
	battle.set_focus(archer)
	_expect(battle.ai.plan(sword)["target"] != null, "指定目標：這一輪打不到，就先打別人")
	_tac_put(battle, lizard, Vector2i(20, 2))
	_tac_put(battle, knight, Vector2i(8, 1))
	sword.move_points = 2
	var plan: Dictionary = battle.ai.plan(sword)
	_expect(plan["target"] == null and plan["toward"] == archer and (plan["cell"] as Vector2i).x > 8, "指定目標：誰都打不到，就往它走")
	battle.set_focus(null)
	_expect(battle.ai.plan(sword)["toward"] == knight, "取消指定：往最近的走")
	sword.take_damage(sword.health - 2)
	_tac_put(battle, knight, Vector2i(6, 8))
	battle.set_focus(knight)
	_expect(battle.ai.plan(battle.party[1])["target"] == sword, "指定目標：補師還是先救快倒的")
	battle.click(battle.cell_of(knight))
	_expect(battle.focus == null, "再點一次：取消指定")
	battle.click(battle.cell_of(knight))
	_expect(battle.focus == knight and lines[lines.size() - 1].contains("指定目標"), "點敵人：指定目標，有寫進日誌")
	await _frames(12)
	_expect(battle.intents.size() == 5 and battle.intents[knight]["target"] != null, "意圖：五隻都算好了（重裝兵%s）" % battle.intent_text(knight))
	battle.hovered = knight
	(_level.get_node("HUD") as TacticsHud).refresh()
	battle._redraw_marks()
	await _frames(2)
	_expect(battle.related_to(knight).has(battle.target_of(knight)) and lizard.self_modulate.a < 1.0 and knight.self_modulate.a == 1.0, "指著一隻：有關的亮、其他的變淡")
	battle.hovered = null
	await _frames(2)
	_expect(lizard.self_modulate.a == 1.0, "沒指著：全部變回來")
	battle.auto = false
	_expect(battle.intents.size() == 3, "回合制：只畫敵人的意圖")
	knight.take_damage(999)
	battle._lose(lizard, 999)
	_expect(battle.focus == knight, "指定的還在（直接改血不會清）")
	battle.set_focus(archer)
	battle._lose(archer, 999)
	_expect(battle.focus == null, "打倒指定目標：自動取消")

	# 日誌：特性、加成都寫出來；骰子
	battle = await _tac_duel([["cavalry", Vector2i(9, 6)], ["assassin", Vector2i(4, 8)]], [["swordsman", Vector2i(10, 6)], ["swordsman", Vector2i(20, 6)]])
	battle.state = TacticsBattle.State.FIGHT
	lines.clear()
	battle.noted.connect(func(text: String) -> void: lines.append(text))
	var cavalry: Unit = battle.party[0]
	var foe: Unit = battle.squads[0].members[0]
	cavalry.steps_taken = 3
	await battle.strike(cavalry, foe)
	_expect(lines[0].contains("騎兵") and lines[0].contains("劍士1") and lines[0].contains("突擊"), "日誌：誰打誰、加成（%s）" % lines[0])
	_expect(lines.size() == 2 and lines[1].contains("還手"), "日誌：還手")
	var text: RichTextLabel = (_level.get_node("HUD") as TacticsHud).get("_log_text")
	_expect(text.get_parsed_text().contains("突擊") and not text.get_parsed_text().contains("[color"), "日誌：畫面上有，沒有標籤")
	var assassin: Unit = battle.party[1]
	assassin.take_damage(10)
	_tac_put(battle, assassin, Vector2i(10, 5))
	lines.clear()
	await battle.strike(assassin, foe)
	_expect("".join(lines).contains("吸血"), "日誌：吸血")
	foe.heal(99)
	battle.dice = true
	var misses: int = 0
	var doubles: int = 0
	for i: int in 6:
		foe.is_down = false
		foe.health = foe.max_health
		cavalry.health = cavalry.max_health
		lines.clear()
		battle.fixed_roll = i % 6 + 1
		cavalry.steps_taken = 0
		await battle.strike(cavalry, foe)
		if foe.health == foe.max_health and lines[0].contains("失手") and lines.size() == 1:
			misses += 1
		elif foe.health == foe.max_health - 8 and lines[0].contains("加倍"):
			doubles += 1
	_expect(misses == 1 and doubles == 1, "骰子：1 失手（也不會被還手）、6 加倍，其他照常")


## 打完：倒下站起來、沒有站起來、勝利條件
func _test_tactics_end() -> void:
	var map: TacticsMap = _tac_map(Vector2i(30, 14), Vector2i(4, 6), ["swordsman", "archer", "healer"])
	_tac_squad(map, [["lizard", Vector2i(12, 6)]], {"drop_supplies": 2})
	_tac_squad(map, [["lizard", Vector2i(26, 11)]], {"boss": true, "start_angle": 0.0})
	map.win = TacticsMap.Win.BOSS
	var battle: TacticsBattle = await _tac_load(map.copy())
	var party: TacticsParty = _tac_party()
	battle.start(_tac_squads()[0])
	battle.begin_fight()
	party.members[1].take_damage(999)
	battle.squads[0].members[0].take_damage(999)
	await _wait_until(func() -> bool: return not battle.is_active(), 400)
	await _frames(4)
	_expect(not battle.is_active() and not GameFlow.is_finished(), "打倒一隊：回到探索，還沒贏（要打倒首領）")
	_expect(party.members[1].health == 1 and party.members[1].visible and not party.members[1].is_down, "倒下的人：1 滴血站起來")
	_expect(_tac_squads().size() == 1 and party.is_exploring(), "打倒的小隊不見了")
	var bags: Array[Node] = _level.find_children("*", "TacticsSupply", true, false)
	_expect(bags.size() == 1 and (bags[0] as TacticsSupply).amount == 2, "掉落：打倒的小隊掉 2 份物資")
	party.leader().global_position = (bags[0] as Node2D).global_position
	await _frames(3)
	_expect(party.supplies == 3, "掉落：走過去撿（%d）" % party.supplies)
	battle.start(_tac_squads()[0])
	battle.begin_fight()
	battle.squads[0].members[0].take_damage(999)
	await _wait_until(func() -> bool: return GameFlow.is_finished(), 400)
	_expect(GameFlow.is_finished() and _result_title().contains("勝利"), "打倒首領小隊：勝利")

	map.revive = false
	map.win = TacticsMap.Win.GOAL
	map.goal_cells = [Vector2i(5, 11)]
	battle = await _tac_load(map.copy())
	party = _tac_party()
	battle.start(_tac_squads()[0])
	battle.begin_fight()
	party.members[1].take_damage(999)
	battle.squads[0].members[0].take_damage(999)
	await _wait_until(func() -> bool: return not battle.is_active(), 400)
	await _frames(2)
	_expect(party.members.size() == 2, "取消站起來：倒下的人離隊")
	party.leader().global_position = battle.grid.cell_center(Vector2i(5, 11))
	await _frames(3)
	_expect(GameFlow.is_finished() and _result_title().contains("勝利"), "隊長走到目標格：勝利")

	battle = await _tac_load(map.copy())
	battle.start(_tac_squads()[0])
	battle.begin_fight()
	for unit: Unit in battle.deployed():
		unit.take_damage(999)
	await _wait_until(func() -> bool: return GameFlow.is_finished(), 400)
	_expect(GameFlow.is_finished() and not _result_title().contains("勝利"), "上場的全部倒下：輸")


## 三張範例地圖：放得好、自動打得完一場
func _test_tactics_examples() -> void:
	for level_name: String in ["tactics", "boss", "arena"]:
		await _load("res://examples/tactics/levels/%s.tscn" % level_name)
		var battle: TacticsBattle = _level.get_node("Battle")
		var level: TacticsLevel = _level.get_node("TacticsLevel")
		await _frames(3)
		_expect(level.setup_screen != null and level.setup_screen.chosen.size() == level.map.party_max and level.squads.is_empty(), "關卡 %s：先編隊，已經選好 %d 個" % [level_name, level.map.party_max])
		level.setup_screen.go()
		await _frames(3)
		_expect(level.map.problem().is_empty() and not level.squads.is_empty() and _tac_party().members.size() == level.map.party_max, "關卡 %s：可以玩（%d 隊敵人）" % [level_name, level.squads.size()])
		for squad: EnemySquad in level.squads:
			_expect(battle.grid.has_path(_tac_party().leader().global_position, squad.leader().global_position), "關卡 %s：走得到「%s」" % [level_name, squad.data.squad_name])
		if not battle.is_active():
			_tac_party().leader().global_position = level.squads[0].leader().global_position + Vector2(-128, 0)
			battle.start(level.squads[0])
		battle.pause_between = 0.0
		battle.auto = true
		battle.begin_fight()
		battle.game_speed = 6.0
		await _wait_until(func() -> bool: return not battle.is_active(), 6000)
		_expect(not battle.is_active() and battle.round_number < battle.max_rounds, "關卡 %s：自動打完第一場（%d 輪）" % [level_name, battle.round_number])


## 編輯器：畫、放、上一步、存讀、試玩、小隊、棋子、規則、做成關卡
func _test_tactics_editor() -> void:
	await _load("res://examples/tactics/map_editor/map_editor.tscn")
	Engine.time_scale = TIME_SCALE
	var editor: Node2D = _level
	editor.call("new_map")
	var map: TacticsMap = editor.get("map")
	var squads: TacticsSquadPage = editor.get("_squad_page")
	var rules: TacticsRulePage = editor.get("_rule_page")
	var units: TacticsUnitPage = editor.get("_unit_page")
	editor.call("_set_tool", 3)
	editor.call("press", map.cell_center(Vector2i(8, 8)), false)
	editor.call("release", map.cell_center(Vector2i(8, 8)))
	_expect(map.kind_at(Vector2i(8, 8)) == TacticsMap.Kind.FOREST, "編輯器：畫森林")
	editor.call("press", map.cell_center(Vector2i(8, 8)), true)
	editor.call("release", map.cell_center(Vector2i(8, 8)))
	_expect(map.kind_at(Vector2i(8, 8)) == TacticsMap.Kind.PLAIN, "編輯器：右鍵擦掉")
	editor.set("snap", true)
	editor.set("brush", 16.0)
	editor.call("press", map.cell_center(Vector2i(8, 8)) + Vector2(12, -12), false)
	editor.call("release", map.cell_center(Vector2i(8, 8)))
	_expect(map.kind_at(Vector2i(8, 8)) == TacticsMap.Kind.FOREST and map.kind_at(Vector2i(9, 8)) == TacticsMap.Kind.PLAIN and map.sample(TacticsMap.Kind.FOREST, Vector2(8 * 32 + 1, 8 * 32 + 1)) > 0.5, "編輯器：對齊格子，畫滿剛好一格")
	editor.call("undo")
	editor.set("snap", false)
	editor.call("_set_shape", 1)
	editor.call("press", map.cell_center(Vector2i(10, 3)), false)
	editor.call("release", map.cell_center(Vector2i(12, 5)))
	_expect(map.kind_at(Vector2i(12, 5)) == TacticsMap.Kind.FOREST and map.kind_at(Vector2i(13, 5)) == TacticsMap.Kind.PLAIN, "編輯器：矩形")
	editor.call("undo")
	_expect(map.kind_at(Vector2i(12, 5)) == TacticsMap.Kind.PLAIN, "編輯器：上一步")
	editor.call("redo")
	_expect(map.kind_at(Vector2i(12, 5)) == TacticsMap.Kind.FOREST, "編輯器：下一步")
	editor.call("_set_shape", 2)
	editor.call("press", map.cell_center(Vector2i(20, 12)), false)
	editor.call("release", map.cell_center(Vector2i(26, 16)))
	_expect(map.kind_at(Vector2i(23, 14)) == TacticsMap.Kind.FOREST and map.kind_at(Vector2i(20, 12)) == TacticsMap.Kind.PLAIN, "編輯器：圓形（角落沒畫到）")
	editor.call("undo")
	editor.call("_set_tool", 8)
	editor.set("chest_amount", 3)
	editor.call("place", Vector2i(6, 6))
	_expect(map.chests == {Vector2i(6, 6): 3}, "編輯器：放寶箱")
	editor.set("chest_amount", 2)
	_expect(bool(editor.call("place", Vector2i(6, 6))) and map.chests[Vector2i(6, 6)] == 2 and not bool(editor.call("place", Vector2i(6, 6))), "編輯器：點寶箱改份數")
	_expect(bool(editor.call("unplace", Vector2i(6, 6))) and map.chests.is_empty(), "編輯器：右鍵拿掉寶箱")
	editor.call("undo")
	_expect(map.chests.size() == 1, "編輯器：上一步，寶箱回來")
	_expect(not bool(editor.call("start_test")), "編輯器：沒有敵人不能試玩")
	editor.call("_set_tool", 9)
	editor.set("unit_path", UNITS + "mage.tscn")
	_expect(bool(editor.call("place", Vector2i(5, 9))) and map.allies == {Vector2i(5, 9): UNITS + "mage.tscn"}, "編輯器：放同伴")
	editor.set("unit_path", UNITS + "knight.tscn")
	_expect(bool(editor.call("place", Vector2i(5, 9))) and map.allies[Vector2i(5, 9)].ends_with("knight.tscn"), "編輯器：點同伴換一種")
	editor.call("_set_tool", 10)
	_expect(not bool(editor.call("place", Vector2i(0, 0))), "編輯器：牆上不能放")
	_expect(bool(editor.call("place", Vector2i(25, 8))) and map.squads.size() == 1 and map.squads[0].members.size() == 1, "編輯器：放敵人（沒有小隊就自動新增）")
	_expect(not bool(editor.call("place", Vector2i(25, 8))), "編輯器：同一格不能放兩隻")
	editor.call("place", Vector2i(27, 8))
	editor.call("_set_tool", 11)
	editor.call("place", Vector2i(20, 8))
	_expect(map.squads[0].members.size() == 2 and map.squads[0].patrol == [Vector2i(20, 8)], "編輯器：第二隻、巡邏點")
	editor.call("_set_tool", 10)
	editor.call("unplace", Vector2i(27, 8))
	_expect(map.squads[0].members.size() == 1, "編輯器：右鍵拿掉敵人")

	editor.call("set_page", 1)
	squads.set_value("view_distance", 300.0)
	await get_tree().create_timer(0.4, true, false, true).timeout
	var on_screen: Vector2 = editor.get_viewport().get_canvas_transform() * (editor.OFFSET + map.cell_center(map.squads[0].cells[0]))
	_expect(on_screen.x > 830.0 and on_screen.x < 1280.0 and on_screen.y > 50.0 and on_screen.y < 690.0, "小隊頁：畫面移到那一隊，沒被面板擋住（%s）" % on_screen)
	squads.set_value("drop_supplies", 2)
	squads.add_squad()
	_expect(map.squads.size() == 2 and squads.index == 1, "小隊頁：新小隊")
	editor.call("undo")
	_expect(map.squads.size() == 1 and map.squads[0].view_distance == 300.0, "小隊頁：上一步退掉新小隊")
	editor.call("set_page", 3)
	_expect(map.party.is_empty(), "新地圖：沒有固定隊伍（用隊伍池）")
	for unit: String in ["swordsman", "archer", "knight"]:
		rules.add_member(UNITS + unit + ".tscn")
	var count: int = map.party.size()
	rules.add_member(UNITS + "mage.tscn")
	rules.move_up(count)
	_expect(map.party.size() == count + 1 and map.party[count - 1].ends_with("mage.tscn"), "規則頁：加一隻、往上移")
	rules.set_value("auto_battle", false)
	rules.set_value("dice", true)
	rules.add_reward(UNITS + "lizard.tscn")
	rules.add_reward(UNITS + "flyer.tscn")
	rules.remove_reward(0)
	rules.set_value("choose_party", false)
	rules.set_value("party_max", 3)
	rules.set_value("formation", 2)
	rules.set_value("start_split", true)
	rules.remove_member(count - 1)
	_expect(map.party.size() == count and not map.auto_battle, "規則頁：拿掉一隻、改成回合制")

	# 存檔、讀檔、做成關卡
	_expect(bool(editor.call("is_dirty")), "編輯器：改了還沒存")
	_expect(String(editor.call("make_level")).is_empty(), "編輯器：沒存檔不能做成關卡")
	(editor.get("_name_edit") as LineEdit).text = "_test_tactics_map"
	var saved: Dictionary = map.snapshot()
	var path: String = editor.call("save_map")
	_expect(FileAccess.file_exists(path) and not bool(editor.call("is_dirty")), "編輯器：存檔")
	var made: String = editor.call("make_level")
	_expect(FileAccess.file_exists(made) and String(editor.call("make_level")).is_empty(), "編輯器：做成關卡，不會蓋掉")
	editor.call("new_map")
	_expect(bool(editor.call("load_map", path)) and (editor.get("map") as TacticsMap).snapshot() == saved, "編輯器：讀回來一模一樣")
	map = editor.get("map")
	_expect(map.rewards == [UNITS + "flyer.tscn"] and map.allies.size() == 1, "編輯器：過關獎勵、同伴有存")
	_expect(not map.choose_party and map.party_max == 3 and map.formation == 2 and map.start_split and map.party_size == 0, "編輯器：陣形、分開走有存，上場預設不限")
	_expect(map.dice and map.squads[0].drop_supplies == 2 and map.chests.size() == 1, "編輯器：骰子、掉落、寶箱都有存")

	# 試玩
	_expect(bool(editor.call("start_test")) and bool(editor.call("is_testing")), "編輯器：試玩")
	await _frames(5)
	var play: Node = editor.get("_play")
	_expect((play.get_node("Party") as TacticsParty).members.size() == count and not (play.get_node("Battle") as TacticsBattle).auto, "試玩：用編輯中的隊伍和規則")
	editor.call("stop_test")
	await _frames(2)
	_expect(not bool(editor.call("is_testing")), "編輯器：停止試玩")

	_expect(not TacticsPool.testing, "編輯器：停止試玩，隊伍池變回玩家的")
	# 隊伍頁
	editor.call("set_page", 4)
	var pool: TacticsPoolPage = editor.get("_pool_page")
	var backup: PackedByteArray = FileAccess.get_file_as_bytes(TacticsPool.PATH)
	var before_pool: Array[String] = TacticsPool.start_units()
	pool.add_member(UNITS + "lizard.tscn")
	pool.move_up(before_pool.size())
	_expect(pool.is_dirty() and TacticsPool.start_units() == before_pool, "隊伍頁：改了還沒存")
	_expect(pool.save() and not pool.is_dirty() and TacticsPool.start_units().size() == before_pool.size() + 1, "隊伍頁：存成起始隊伍")
	pool.start = before_pool.duplicate()
	pool.save()
	var pool_file: FileAccess = FileAccess.open(TacticsPool.PATH, FileAccess.WRITE)
	pool_file.store_buffer(backup)
	pool_file.close()

	# 棋子頁
	editor.call("set_page", 2)
	units.open(UNITS + "archer.tscn")
	units.copy_unit()
	units.set_value("display_name", "_test_unit")
	units.set_value("attack", 9)
	var fly: String = "res://examples/tactics/features/unit_traits/flying.tscn"
	var charge: String = "res://examples/tactics/features/unit_traits/charge.tscn"
	units.set_trait(fly, true)
	units.set_trait(charge, true)
	units.set_trait_value(charge, "limit", 9.0)
	await _frames(2)
	var unit_path: String = units.save()
	_expect(FileAccess.file_exists(unit_path), "棋子頁：存成新棋子（%s）" % unit_path)
	var unit: Unit = (load(unit_path) as PackedScene).instantiate()
	add_child(unit)
	_expect(unit.attack == 9 and unit.min_range == 2 and unit.traits().size() == 2 and unit.is_flying(), "棋子頁：數值、特性都對")
	unit.free()
	units.set_trait(fly, false)
	units.save()
	var data: Dictionary = TacticsUnitInfo.read(unit_path)
	_expect((data["traits"] as Dictionary).size() == 1 and data["traits"][charge]["limit"] == 9.0, "棋子頁：取消特性、欄位有存")
	_expect(units.undo(), "棋子頁：上一步")
	for file: String in [path, made, unit_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	TacticsUnitPage.editing = {}
	TacticsUnitPage.editing_path = ""
	TacticsUnitPage.dirty = false
	editor.set("editing", null)
	editor.set("resume_test", false)
	editor.set("page", 0)


# ---- 工具 ----

func _load(path: String) -> void:
	get_tree().paused = false
	if _level != null:
		_level.queue_free()
		await _frames(1)
	for child: Node in GameFlow.get_children():
		child.queue_free()                                        # 清掉上一個的勝敗畫面
	await _frames(1)
	_level = (load(path) as PackedScene).instantiate()
	add_child(_level)
	await _frames(3)


func _freeze_group(group: String) -> void:
	for node: Node in get_tree().get_nodes_in_group(group):
		node.process_mode = Node.PROCESS_MODE_DISABLED


func _result_title() -> String:
	for child: Node in GameFlow.get_children():
		if child.name == "ResultScreen":
			return (child.get_node("%ResultTitle") as Label).text
	return ""


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
