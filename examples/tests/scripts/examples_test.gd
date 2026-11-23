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
##   godot --headless --path . res://examples/tests/examples_test.tscn

const CHASE: String = "res://examples/chase/levels/chase.tscn"
const TOWER_DEFENSE: String = "res://examples/tower_defense/levels/tower_defense.tscn"
const TACTICS: String = "res://examples/tactics/levels/tactics.tscn"
const TIME_SCALE: float = 3.0

var _failures: int = 0
var _level: Node


func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	await _test_chase()
	await _test_tower_defense()
	await _test_tactics()
	Engine.time_scale = 1.0
	get_tree().paused = false
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
	_expect(not grid.is_cell_walkable(open_cell), "牆擋路")
	_expect(not builder.build(open_cell), "同一格不能蓋兩次")
	_expect(builder.remove(open_cell) and grid.is_cell_walkable(open_cell), "右鍵拆掉：又可以走")

	# 把基地圍起來，最後一格不能蓋（會堵死）
	var base_cell: Vector2i = grid.cell_of(base.global_position)
	money.score = 100
	var sealed: bool = true
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
