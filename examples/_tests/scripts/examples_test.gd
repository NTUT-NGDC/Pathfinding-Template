extends Node
## 三個範例的自動測試：
## 1. 追逐：寶物 3 個＋發電機、都完成出口才打開、走進出口就贏；開門條件（全部／指定／數量／一開始就開）；
##    守衛被聲音引開後會走回崗位；站在門口按 E 會退出去把門關上；
##    捕獸夾（AI 繞開、夾住、AI 追丟會放）、警報（AI 過來、冷卻）、瓶子（撿、丟、撞牆、引開守衛）；
##    發電機會發出聲音；鏡頭固定在畫面中間；被追逐 AI 碰到就輸；上鎖的門要鑰匙
## 2. 塔防：蓋牆扣錢、不能把路堵死、錢不夠蓋不了、塔會打怪、怪走到基地扣血
## 3. 戰棋：點棋子亮出移動範圍、走過去、走到敵人旁邊會攻擊、敵方回合往我方靠近
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

func _test_tactics() -> void:
	print("--- 戰棋 ---")
	await _load(TACTICS)
	await _frames(3)
	var manager: TurnManager = _level.get_node("TurnManager")
	var move_range: MoveRange = _level.get_node("MoveRange")
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var allies: Array[Unit] = manager.units_of(0)
	var enemies: Array[Unit] = manager.units_of(1)
	_expect(allies.size() == 3 and enemies.size() == 3, "我方 3 隻、敵方 3 隻")
	_expect(manager.turn == 0 and (_level.get_node("HUD/Info/TurnLabel") as Label).text == "我方回合", "一開始是我方回合")
	var unit: Unit = allies[0]
	await _click(grid.cell_of(unit.global_position), move_range)
	_expect(not move_range.cells.is_empty(), "點我方棋子：亮出移動範圍（%d 格）" % move_range.cells.size())
	var start: Vector2i = grid.cell_of(unit.global_position)
	var target: Vector2i = start + Vector2i(3, 0)
	_expect(move_range.has_cell(target) and not move_range.has_cell(start + Vector2i(5, 0)), "移動力 4：走得到 3 格外、5 格外走不到")
	await _click(target, move_range)
	await _wait_until(func() -> bool: return not manager.busy, 200)
	_expect(grid.cell_of(unit.global_position) == target and unit.has_moved, "點格子：走過去、變成走過了")

	# 攻擊：把一個敵人放到我方旁邊，另一個我方走到它旁邊
	var enemy: Unit = enemies[0]
	enemy.global_position = grid.cell_center(target + Vector2i(2, 0))
	var attacker: Unit = allies[1]
	var next_to_enemy: Vector2i = target + Vector2i(2, 1)
	attacker.global_position = grid.cell_center(next_to_enemy + Vector2i(-1, 0))
	await _click(grid.cell_of(attacker.global_position), move_range)
	await _click(next_to_enemy, move_range)
	await _wait_until(func() -> bool: return not manager.busy, 200)
	_expect(enemy.health == enemy.max_health - 1, "走到敵人旁邊：打一下（%d/%d）" % [enemy.health, enemy.max_health])

	# 結束回合 → 敵方往我方靠近 → 回到我方
	var far_enemy: Unit = enemies[2]
	var before: float = _nearest_ally_distance(manager, far_enemy, grid)
	manager.end_player_turn()
	await _wait_until(func() -> bool: return manager.turn == 0, 600)
	_expect(manager.turn == 0, "敵方回合結束：回到我方回合")
	if is_instance_valid(far_enemy):
		_expect(_nearest_ally_distance(manager, far_enemy, grid) < before, "敵人往最近的我方靠近")
	_expect(manager.units_of(0).all(func(u: Unit) -> bool: return not u.has_moved), "新的回合：我方都可以再走")


func _nearest_ally_distance(manager: TurnManager, enemy: Unit, grid: PathGrid) -> float:
	var best: float = INF
	for ally: Unit in manager.units_of(0):
		best = minf(best, Vector2(grid.cell_of(ally.global_position) - grid.cell_of(enemy.global_position)).length())
	return best


func _click(cell: Vector2i, any_node: Node2D) -> void:
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = any_node.get_global_transform_with_canvas() * any_node.to_local(grid.cell_center(cell))
	click.global_position = click.position
	(_level.get_node("TurnManager") as TurnManager)._unhandled_input(click)
	await _frames(2)


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
