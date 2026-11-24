extends "res://examples/_tests/scripts/example_test.gd"
## 戰棋範例的自動測試：
## 探索（撞牆、隊友跟上、物資、紮營）、被發現、偷襲、支援、布陣、速度順序、自動／回合制切換、
##    走／打／反悔、倍速和暫停、隊伍池、編隊、陣形、整隊／分開、趕來支援、每一種特性、四種個性、指定目標、意圖、日誌、骰子、寶箱、掉落、勝利條件、倒下站起來、三張範例地圖打得完、編輯器五頁
##
## 在命令列執行：
##   godot --headless --fixed-fps 60 --path . res://examples/_tests/tactics_test.tscn

const TACTICS: String = "res://examples/tactics/levels/tactics.tscn"
const UNITS: String = "res://examples/tactics/features/units/"


func _run() -> void:
	await _test_tactics()


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

	battle.auto = true
	battle.turn_started.connect(func(unit: Unit) -> void:
		if unit == knight and not unit.is_down:
			battle.hurt(unit, 999, "中毒"))
	var lines_after: PackedStringArray = PackedStringArray()
	battle.noted.connect(func(text: String) -> void:
		if knight.is_down and text.contains(battle.name_of(knight)) and not text.contains("倒下") and not text.contains("中毒"):
			lines_after.append(text))
	await _tac_wait(battle, func() -> bool: return knight.is_down)
	await _frames(20)
	_expect(knight.is_down and lines_after.is_empty(), "輪到時被毒倒：這一輪不會再動（%s）" % "、".join(lines_after))
	battle = await _tac_duel([["swordsman", Vector2i(4, 6)], ["cavalry", Vector2i(4, 8)]], [["knight", Vector2i(9, 6)], ["assassin", Vector2i(20, 6)]])
	battle.begin_fight()
	await _tac_wait(battle, func() -> bool: return battle.is_waiting)

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
	editor.call("set_tool", 3)
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
	editor.call("set_shape", 1)
	editor.call("press", map.cell_center(Vector2i(10, 3)), false)
	editor.call("release", map.cell_center(Vector2i(12, 5)))
	_expect(map.kind_at(Vector2i(12, 5)) == TacticsMap.Kind.FOREST and map.kind_at(Vector2i(13, 5)) == TacticsMap.Kind.PLAIN, "編輯器：矩形")
	editor.call("undo")
	_expect(map.kind_at(Vector2i(12, 5)) == TacticsMap.Kind.PLAIN, "編輯器：上一步")
	editor.call("redo")
	_expect(map.kind_at(Vector2i(12, 5)) == TacticsMap.Kind.FOREST, "編輯器：下一步")
	editor.call("set_shape", 2)
	editor.call("press", map.cell_center(Vector2i(20, 12)), false)
	editor.call("release", map.cell_center(Vector2i(26, 16)))
	_expect(map.kind_at(Vector2i(23, 14)) == TacticsMap.Kind.FOREST and map.kind_at(Vector2i(20, 12)) == TacticsMap.Kind.PLAIN, "編輯器：圓形（角落沒畫到）")
	editor.call("undo")
	editor.call("set_tool", 8)
	editor.set("chest_amount", 3)
	editor.call("place", Vector2i(6, 6))
	_expect(map.chests == {Vector2i(6, 6): 3}, "編輯器：放寶箱")
	editor.set("chest_amount", 2)
	_expect(bool(editor.call("place", Vector2i(6, 6))) and map.chests[Vector2i(6, 6)] == 2 and not bool(editor.call("place", Vector2i(6, 6))), "編輯器：點寶箱改份數")
	_expect(bool(editor.call("unplace", Vector2i(6, 6))) and map.chests.is_empty(), "編輯器：右鍵拿掉寶箱")
	editor.call("undo")
	_expect(map.chests.size() == 1, "編輯器：上一步，寶箱回來")
	_expect(not bool(editor.call("start_test")), "編輯器：沒有敵人不能試玩")
	editor.call("set_tool", 9)
	editor.set("unit_path", UNITS + "mage.tscn")
	_expect(bool(editor.call("place", Vector2i(5, 9))) and map.allies == {Vector2i(5, 9): UNITS + "mage.tscn"}, "編輯器：放同伴")
	editor.set("unit_path", UNITS + "knight.tscn")
	_expect(bool(editor.call("place", Vector2i(5, 9))) and map.allies[Vector2i(5, 9)].ends_with("knight.tscn"), "編輯器：點同伴換一種")
	editor.call("set_tool", 10)
	_expect(not bool(editor.call("place", Vector2i(0, 0))), "編輯器：牆上不能放")
	_expect(bool(editor.call("place", Vector2i(25, 8))) and map.squads.size() == 1 and map.squads[0].members.size() == 1, "編輯器：放敵人（沒有小隊就自動新增）")
	_expect(not bool(editor.call("place", Vector2i(25, 8))), "編輯器：同一格不能放兩隻")
	editor.call("place", Vector2i(27, 8))
	editor.call("set_tool", 11)
	editor.call("place", Vector2i(20, 8))
	_expect(map.squads[0].members.size() == 2 and map.squads[0].patrol == [Vector2i(20, 8)], "編輯器：第二隻、巡邏點")
	editor.call("set_tool", 10)
	editor.call("unplace", Vector2i(27, 8))
	_expect(map.squads[0].members.size() == 1, "編輯器：右鍵拿掉敵人")

	editor.call("set_page", 1)
	squads.set_value("view_distance", 300.0)
	await _wait_until(func() -> bool: return not (editor.get("_camera_tween") as Tween).is_running(), 600)
	await _frames(2)
	var on_screen: Vector2 = editor.get_viewport().get_canvas_transform() * ((editor.get("origin") as Vector2) + map.cell_center(map.squads[0].cells[0]))
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

	var drawn: TacticsMap = (load("res://examples/tactics/maps/default.tres") as TacticsMap).copy()
	var text: String = MapText.to_text(drawn)
	var before_text: Dictionary = drawn.snapshot()
	_expect(MapText.apply(drawn, text).is_empty() and drawn.snapshot() == before_text, "轉成文字再寫回去：沒改的話一模一樣（小隊、規則也在）")
	_expect(MapText.apply(drawn, text.replace("f", "~")).is_empty() and MapText.to_text(drawn) == text.replace("f", "~"), "文字把森林改成沼澤")

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
	units.copy_scene()
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
	var data: Dictionary = TacticsUnitInfo.scenes.read(unit_path)
	_expect((data["traits"] as Dictionary).size() == 1 and data["traits"][charge]["limit"] == 9.0, "棋子頁：取消特性、欄位有存")
	_expect(units.undo(), "棋子頁：上一步")
	for file: String in [path, made, unit_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	LevelEditor.forget_sessions()
