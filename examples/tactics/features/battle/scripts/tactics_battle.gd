class_name TacticsBattle
extends Node2D
## 戰鬥：被發現 → 布陣（時間暫停）→ 照速度輪流行動 → 打完回到探索。
##
##   布陣：把我方擺在隊長附近亮起來的格子，按「開始戰鬥」
##   戰鬥：每一輪照速度由快到慢，每隻動一次（走＋打）。
##         輪到我方時：自動＝電腦幫你決定；回合制＝你自己點。隨時可以切換
##   敵人永遠是電腦（BattleAI）
##
## 走得到哪裡用尋路積木的 MoveRange 算（每隻的規則不一樣：會飛、沼澤行者、攔截……），
## 算好的路交給 PathFollower.walk() 走。

## 開始布陣
signal deploy_started()
## 開打了
signal fight_started()
## 新的一輪
signal round_started(number: int)
## 輪到誰
signal turn_started(unit: Unit)
## 打完了（won＝打贏）
signal ended(won: bool)
## 畫面要更新（換了選項、有人倒下……）
signal updated()
## 玩家做了選擇（回合制）
signal choice_made(choice: Dictionary)
## 日誌多了一行（BBCode，名字有顏色）
signal noted(text: String)

enum State { NONE, DEPLOY, FIGHT }

## 亮出移動範圍用的 MoveRange
@export var move_range: MoveRange
## 隊長走幾步以內可以布陣
@export_range(1, 12, 1) var deploy_range: int = 5
## 布陣時不能擺在離敵人幾格以內
@export_range(0, 6, 1) var deploy_gap: int = 2
## 戰場比大家站的地方往外多幾格
@export_range(1, 12, 1) var area_margin: int = 5
## 打幾輪還沒分勝負就算輸（不會卡住）
@export_range(5, 200, 1) var max_rounds: int = 40
## 每個動作之間停幾秒
@export_range(0.0, 2.0, 0.05) var pause_between: float = 0.25
## 畫面右邊留多寬給布陣、日誌（像素）
@export_range(0, 600, 10, "suffix:px") var side_panel: float = 280.0
## 戰場外面的顏色
@export var outside_color: Color = Color(0, 0, 0, 0.5)

const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

var state: State = State.NONE
## 自動（電腦幫我方決定）
var auto: bool = true:
	set(value):
		auto = value
		if auto and is_waiting:
			choice_made.emit({"kind": "auto"})                    # 輪到玩家的時候切成自動：這一步就交給電腦
		refresh_intents()
		updated.emit()
## 暫停（還是可以看棋子的數值）
var paused: bool = false:
	set(value):
		paused = value
		_apply_speed()
		updated.emit()
## 倍速
var game_speed: float = 1.0:
	set(value):
		game_speed = value
		_apply_speed()
		updated.emit()
## 我方隊伍（包括沒上場的）、最多上場幾隻（0＝不限）
var party: Array[Unit] = []
var party_size: int = 0
## 這場可以布陣的人（分開走時只有附近的）
var available: Array[Unit] = []
## 被發現的人：一定要上場
var anchor: Unit
## 趕來支援的人 → 第幾輪到
var late: Dictionary[Unit, int] = {}
## 這場打的小隊
var squads: Array[EnemySquad] = []
## 場上的棋子（兩邊都有，倒下的也在）
var fighters: Array[Unit] = []
## 這場是偷襲嗎（第一輪我方全部先動）
var is_ambush: bool = false
var round_number: int = 0
## 這一輪還沒動的（第一個就是現在輪到的）
var order: Array[Unit] = []
var current: Unit
## 戰場範圍（格子）
var area: Rect2i = Rect2i()
## 可以布陣的格子
var deploy_cells: Array[Vector2i] = []
## 正在等玩家選
var is_waiting: bool = false
## 這一步走過了（可以反悔）
var has_moved: bool = false
## 打得到的格子、可以打（補）的棋子：畫出來給玩家看
var attack_cells: Array[Vector2i] = []
var target_units: Array[Unit] = []
## 滑鼠指著的棋子、它走得到＋打得到的格子
var hovered: Unit
var threat_cells: Array[Vector2i] = []
## 布陣時拿起來的棋子
var picked: Unit
## 指定的目標：自動的我方優先打它（點敵人指定，再點一次取消）
var focus: Unit
## 畫出「誰打算打誰」的箭頭
var show_intents: bool = true:
	set(value):
		show_intents = value
		updated.emit()
		_redraw_marks()
## 電腦操作的棋子打算做什麼：棋子 → BattleAI.plan() 的結果。照現在的狀況猜的，有人動了就重算
var intents: Dictionary[Unit, Dictionary] = {}
## 擲骰子（1 失手、6 加倍）
var dice: bool = false
## 大於 0＝每次都骰到這個（測試用）
var fixed_roll: int = 0

var grid: PathGrid
var ai: BattleAI
var _map: TacticsMap
var _camera: FollowCamera
var _moves: Dictionary[Vector2i, float] = {}
var _turn_start_cell: Vector2i
## 探索時鏡頭放大幾倍（打完變回來）
var _zoom: float = 1.0
## 還沒重算意圖的棋子（一個畫面算一隻，才不會卡）
var _intent_todo: Array[Unit] = []
## 箭頭、指定目標畫在棋子上面
var _marks: Node2D
## 上一次 damage_of() 有哪些東西改了扣血（日誌用）
var _reasons: PackedStringArray = PackedStringArray()


func _ready() -> void:
	z_index = 1
	add_to_group("tactics_battle")
	ai = BattleAI.new(self)
	_marks = Node2D.new()
	_marks.z_index = 5
	_marks.draw.connect(_draw_marks)
	add_child(_marks)


func _process(_delta: float) -> void:
	if not is_active():
		return
	_redraw_marks()                                               # 箭頭跟著棋子走
	_highlight()
	if _intent_todo.is_empty() or (current != null and current.follower().is_moving()):
		return
	var unit: Unit = _intent_todo.pop_front()
	if is_instance_valid(unit) and not unit.is_down and fighters.has(unit):
		intents[unit] = ai.plan(unit, unit != current or not has_moved)
		intents[unit]["path"] = _intent_path(unit)
		if unit == hovered:
			updated.emit()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## 打開暫停選單：戰鬥自己的暫停就取消（不然時間停著，選單「回標題」的淡出會卡住）
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and paused:
		paused = false


func is_active() -> bool:
	return state != State.NONE


## 關卡準備好時呼叫
func setup(map: TacticsMap, camera: FollowCamera) -> void:
	_map = map
	_camera = camera
	auto = map.auto_battle
	party_size = map.party_size
	dice = map.dice
	grid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	move_range.clickable = false                                  # 點擊由這裡處理


# ---- 開始 ----

## 跟這隊敵人打。ambush＝偷襲成功，who＝被發現的我方（沒說就是探索時控制的人）
func start(squad: EnemySquad, ambush: bool = false, who: Unit = null) -> void:
	if is_active():
		return
	state = State.DEPLOY
	is_ambush = ambush
	squads = _with_support(squad)
	focus = null
	intents.clear()
	fighters.clear()
	for s: EnemySquad in squads:
		s.enter_battle()
		for enemy: Unit in s.members:
			_snap(enemy)
			fighters.append(enemy)
	for unit: Unit in party:
		unit.follower().stop()
	anchor = who if who != null else _party_node().leader()
	_snap(anchor)
	area = _make_area(anchor)
	_gather()
	deploy_cells = _make_deploy_cells(anchor)
	_auto_deploy()
	_show_area(true)
	_show_unit(null)
	note("[b]── %s%s ──[/b]" % ["偷襲！" if is_ambush else "遇到", "、".join(squads.map(func(s: EnemySquad) -> String: return s.data.squad_name))])
	refresh_intents()
	deploy_started.emit()
	updated.emit()
	queue_redraw()


## 在支援距離內的其他小隊也加入
func _with_support(squad: EnemySquad) -> Array[EnemySquad]:
	var result: Array[EnemySquad] = [squad]
	for node: Node in get_tree().get_nodes_in_group("enemy_squads"):
		var other: EnemySquad = node as EnemySquad
		if other == squad or other.is_queued_for_deletion() or other.data.support <= 0:
			continue
		if other.leader().global_position.distance_to(squad.leader().global_position) <= other.data.support * TacticsMap.CELL:
			result.append(other)
	return result


func _party_node() -> TacticsParty:
	return get_tree().get_first_node_in_group("tactics_party") as TacticsParty


## 誰可以布陣、誰要趕來：整隊走＝全部；分開走＝走路幾格以內（或站在戰場裡）的，其他的照走路距離算幾輪後到
func _gather() -> void:
	available.clear()
	late.clear()
	for unit: Unit in party:
		if unit == anchor or not _party_node().split or area.has_point(cell_of(unit)):
			available.append(unit)
			continue
		var path: PackedVector2Array = _way_to_anchor(unit)
		if path.is_empty() or grid.cell_of(path[path.size() - 1]) != cell_of(anchor):
			continue                                              # 走不到：這場不參加
		if path.size() - 1 <= _map.join_range:
			available.append(unit)
			continue
		var cost: float = 0.0
		for i: int in range(1, path.size()):
			if area.has_point(grid.cell_of(path[i])):
				break                                             # 走進戰場就算到了
			cost += 1.0 if unit.is_flying() else grid.cost_of(grid.cell_of(path[i]))
		late[unit] = maxi(ceili(cost / maxf(unit.move_points, 1.0)), 1) + 1


## 走去被發現的人那裡的路（會飛的＝直線）
func _way_to_anchor(unit: Unit) -> PackedVector2Array:
	if not unit.is_flying():
		return grid.find_path(unit.global_position, anchor.global_position)
	var steps: int = maxi(distance(cell_of(unit), cell_of(anchor)), 1)
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in steps + 1:
		path.append(unit.global_position.lerp(anchor.global_position, float(i) / steps))
	return path


## 最多上場幾隻
func limit() -> int:
	return mini(party_size, available.size()) if party_size > 0 else available.size()


## 趕到的人進場：從走過來的路進戰場的那一格（有人就旁邊）
func _arrive_late() -> void:
	for unit: Unit in late.keys():
		if late[unit] > round_number or (party_size > 0 and alive(0).size() >= party_size):
			continue
		late.erase(unit)
		var path: PackedVector2Array = _way_to_anchor(unit)
		var entry: Vector2i = cell_of(anchor)
		for point: Vector2 in path:
			if area.has_point(grid.cell_of(point)):
				entry = grid.cell_of(point)
				break
		unit.global_position = grid.cell_center(_nearest_free(entry, unit))
		fighters.append(unit)
		unit.provoked = false
		note("[b]%s 趕到了！[/b]" % name_of(unit))
		_pop_number(unit, "趕到！", Color("8ec0ff"))
		refresh_intents()


## 戰場：大家站的地方往外多幾格
func _make_area(leader: Unit) -> Rect2i:
	var rect: Rect2i = Rect2i(cell_of(leader), Vector2i.ONE)
	for unit: Unit in fighters:
		rect = rect.expand(cell_of(unit)).expand(cell_of(unit) + Vector2i.ONE)
	var map_rect: Rect2i = Rect2i(grid.astar.region)
	var margin: int = area_margin
	area = rect.grow(margin).intersection(map_rect)
	while area != map_rect and not _all_reachable(leader):        # 中間隔著牆、繞路要走到外面：戰場再大一點
		margin += 2
		area = rect.grow(margin).intersection(map_rect)
	return area


## 隊長在戰場裡走得到每一隻敵人旁邊嗎
func _all_reachable(leader: Unit) -> bool:
	_use_rules(leader, false)
	var reach: Dictionary[Vector2i, float] = move_range.reachable_cells(cell_of(leader), 9999.0)
	return fighters.all(func(u: Unit) -> bool: return reach.has(cell_of(u)))


## 可以布陣的格子：隊長走幾步以內、離敵人有一點距離
func _make_deploy_cells(leader: Unit) -> Array[Vector2i]:
	_use_rules(leader, false)
	var reach: Dictionary[Vector2i, float] = {}
	var cells: Array[Vector2i] = []
	for extra: int in range(0, 24, 3):                            # 人太多站不下：範圍大一點
		reach = move_range.reachable_cells(cell_of(leader), deploy_range + extra)
		for gap: int in range(deploy_gap, -1, -1):                # 還是太擠的話，可以靠敵人近一點
			cells.clear()
			for cell: Vector2i in reach:
				if grid.is_cell_walkable(cell) and fighters.all(func(e: Unit) -> bool: return distance(cell, cell_of(e)) > gap):
					cells.append(cell)
			if cells.size() >= limit():
				break
		if cells.size() >= limit():
			break
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return reach[a] < reach[b])
	return cells


## 先幫玩家擺好：隊長開始，一隻一隻放在最近的空格
func _auto_deploy() -> void:
	var free: Array[Vector2i] = deploy_cells.duplicate()
	var placed: int = 0
	var line: Array[Unit] = available.duplicate()
	line.erase(anchor)
	line.push_front(anchor)                                       # 被發現的人先擺
	for unit: Unit in line:
		var join: bool = placed < limit() and not free.is_empty()
		_set_on_field(unit, join)
		if not join:
			continue
		var cell: Vector2i = free.pop_front()
		unit.global_position = grid.cell_center(cell)
		placed += 1


# ---- 布陣 ----

func deployed() -> Array[Unit]:
	return available.filter(func(u: Unit) -> bool: return fighters.has(u))


## 上場或下場（被發現的人一定要上場）。回傳有沒有成功
func set_deployed(unit: Unit, on: bool) -> bool:
	if state != State.DEPLOY or on == fighters.has(unit):
		return false
	if not on:
		if unit == anchor:
			return false
		_set_on_field(unit, false)
	else:
		if deployed().size() >= limit():
			return false
		var cell: Vector2i = _free_deploy_cell()
		if cell.x < 0:
			return false
		_set_on_field(unit, true)
		unit.global_position = grid.cell_center(cell)
	picked = null
	refresh_intents()
	updated.emit()
	queue_redraw()
	return true


## 把我方擺到 cell（那格有自己人就交換）
func place(unit: Unit, cell: Vector2i) -> bool:
	if state != State.DEPLOY or not deploy_cells.has(cell) or not fighters.has(unit):
		return false
	var other: Unit = unit_at(cell)
	if other != null and other != unit:
		other.global_position = unit.global_position
	unit.global_position = grid.cell_center(cell)
	picked = null
	refresh_intents()
	updated.emit()
	queue_redraw()
	return true


func _free_deploy_cell() -> Vector2i:
	for cell: Vector2i in deploy_cells:
		if unit_at(cell) == null:
			return cell
	return Vector2i(-1, -1)


func _set_on_field(unit: Unit, on: bool) -> void:
	unit.follower().stop()
	unit.visible = on
	if on and not fighters.has(unit):
		fighters.append(unit)
	elif not on:
		fighters.erase(unit)


## 布陣好了，開打
func begin_fight() -> void:
	if state != State.DEPLOY:
		return
	state = State.FIGHT
	_apply_speed()                                                # 上一場選的倍速繼續用
	picked = null
	round_number = 0
	for unit: Unit in fighters:
		unit.provoked = false
		unit.alert_mark = ""
	fight_started.emit()
	refresh_intents()
	updated.emit()
	queue_redraw()
	_run()


# ---- 輪流 ----

func _run() -> void:
	while state == State.FIGHT:
		round_number += 1
		_arrive_late()
		order = make_order()
		note("[color=#bbbbbb]── 第 %d 輪 ──[/color]" % round_number)
		round_started.emit(round_number)
		while not order.is_empty():
			current = order[0]
			if not current.is_down:
				await _take_turn(current)
			order.erase(current)
			if _check_end():
				return
			refresh_intents()
		if round_number >= max_rounds:
			_finish(false, "打太久了，僵持不下……")
			return


## 這一輪的順序：速度快的先；一樣快的我方先。偷襲的第一輪，我方全部先動
func make_order() -> Array[Unit]:
	var result: Array[Unit] = alive(-1)
	var key: Callable = func(u: Unit) -> int: return u.speed * 2 + (1 if u.team == 0 else 0) + (1000 if is_ambush and round_number <= 1 and u.team == 0 else 0)
	result.sort_custom(func(a: Unit, b: Unit) -> bool:
		return key.call(a) > key.call(b) or (key.call(a) == key.call(b) and fighters.find(a) < fighters.find(b)))
	return result


func _take_turn(unit: Unit) -> void:
	unit.is_active = true
	unit.steps_taken = 0
	has_moved = false
	_turn_start_cell = cell_of(unit)
	for t: UnitTrait in unit.traits():
		t.turn_started(self)
	turn_started.emit(unit)
	updated.emit()
	await wait(pause_between)
	if unit.team == 0 and not auto:
		await _player_turn(unit)
	else:
		await ai_turn(unit)
	if is_instance_valid(unit):
		unit.is_active = false
	_clear_options()


## 電腦決定：走到哪、打誰
func ai_turn(unit: Unit) -> void:
	var plan: Dictionary = ai.plan(unit, not has_moved)
	if plan["cell"] != cell_of(unit):
		await walk(unit, plan["cell"])
	var target: Unit = plan["target"]
	if target != null and not target.is_down:
		await wait(pause_between)
		await act(unit, target)
	else:
		_note_moved(unit)
	await wait(pause_between)


## 玩家自己選：走 → 打（或待命），走完可以反悔
func _player_turn(unit: Unit) -> void:
	while true:
		_show_options(unit)
		is_waiting = true
		updated.emit()
		var choice: Dictionary = await choice_made
		is_waiting = false
		_clear_options()
		match String(choice["kind"]):
			"move":
				await walk(unit, choice["cell"])
				has_moved = true
				refresh_intents()
			"stay":
				has_moved = true                                  # 留在原地：跟走完一樣，接下來打或待命（可以反悔）
				refresh_intents()
			"attack":
				if choice["cell"] != cell_of(unit):
					await walk(unit, choice["cell"])
				await act(unit, choice["target"])
				return
			"undo":
				unit.global_position = grid.cell_center(_turn_start_cell)
				unit.steps_taken = 0
				has_moved = false
				refresh_intents()
			"auto":
				await ai_turn(unit)
				return
			_:
				_note_moved(unit)
				return


## 亮出走得到的、打得到的
func _show_options(unit: Unit) -> void:
	_moves.clear()
	if not has_moved:
		_moves = legal_moves(unit)
	move_range.origin = cell_of(unit)
	move_range.cells = _moves.duplicate()
	move_range.queue_redraw()
	attack_cells = cells_in_range(unit, cell_of(unit))
	target_units.clear()
	for other: Unit in alive(-1):
		if best_cell_to_hit(unit, other).x >= 0:
			target_units.append(other)
	queue_redraw()


func _clear_options() -> void:
	move_range.clear()
	_moves = {}
	attack_cells.clear()
	target_units.clear()
	queue_redraw()


## 從哪一格打 target 最好（現在站的地方打得到就不動；不然挑離它最遠、打得到的）。打不到＝(-1, -1)
func best_cell_to_hit(unit: Unit, target: Unit) -> Vector2i:
	if not can_target(unit, target):
		return Vector2i(-1, -1)
	if in_range(unit, cell_of(unit), cell_of(target)):
		return cell_of(unit)
	var best: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in _moves:
		if in_range(unit, cell, cell_of(target)) and (best.x < 0 or distance(cell, cell_of(target)) > distance(best, cell_of(target)) \
				or (distance(cell, cell_of(target)) == distance(best, cell_of(target)) and _moves[cell] < _moves[best])):
			best = cell
	return best


## 這一步結束（待命）
func choose_wait() -> void:
	if is_waiting:
		choice_made.emit({"kind": "wait"})


## 反悔：回到走之前的格子
func choose_undo() -> void:
	if is_waiting and has_moved:
		choice_made.emit({"kind": "undo"})


## 玩家點了一格
func choose_cell(cell: Vector2i) -> void:
	if not is_waiting or current == null:
		return
	var target: Unit = unit_at(cell)
	if target != null and target != current and target_units.has(target):
		choice_made.emit({"kind": "attack", "cell": best_cell_to_hit(current, target), "target": target})
	elif target == current and not has_moved:
		choice_made.emit({"kind": "stay"})
	elif target == null and _moves.has(cell):
		choice_made.emit({"kind": "move", "cell": cell})


# ---- 走路 ----

## 走得到、可以停下來的格子 → 花多少移動力
func legal_moves(unit: Unit) -> Dictionary[Vector2i, float]:
	_use_rules(unit)
	var cells: Dictionary[Vector2i, float] = move_range.reachable_cells(cell_of(unit), unit.move_points)
	for cell: Vector2i in cells.keys():
		if cell != cell_of(unit) and not can_stand(cell):
			cells.erase(cell)                                     # 牆（飛過去的）、有人站的格子不能停
	return cells


## 這隻走路的規則交給 MoveRange：地形、特性、敵人擋路、攔截。units＝要不要管別的棋子
func _use_rules(unit: Unit, units: bool = true) -> void:
	var flying: bool = unit.is_flying()
	var enemies: Dictionary[Vector2i, bool] = {}
	var caught: Dictionary[Vector2i, bool] = {}
	if units:
		for other: Unit in alive(1 - unit.team):
			var at: Vector2i = cell_of(other)
			enemies[at] = true
			if other.traits().any(func(t: UnitTrait) -> bool: return t.intercepts()):
				for d: Vector2i in DIRECTIONS:
					caught[at + d] = true
	move_range.cost_rule = func(_from: Vector2i, to: Vector2i) -> float:
		if not area.has_point(to) or (enemies.has(to) and not flying):
			return -1.0
		return unit.step_cost(grid.cost_of(to), not grid.is_cell_walkable(to))
	move_range.stop_rule = func(cell: Vector2i) -> bool: return caught.has(cell)


## 走到 cell（要是走得到的格子）
func walk(unit: Unit, cell: Vector2i) -> void:
	_use_rules(unit)
	move_range.reachable_cells(cell_of(unit), unit.move_points)
	var path: Array[Vector2i] = move_range.path_to(cell)
	if path.is_empty():
		return
	var points: PackedVector2Array = PackedVector2Array()
	for step: Vector2i in path:
		points.append(grid.cell_center(step))
	unit.steps_taken += path.size()
	unit.follower().speed = 220.0
	unit.follower().walk(points)
	await unit.follower().arrived
	unit.global_position = grid.cell_center(cell)


## 滑過去（擊退）
func slide(unit: Unit, cell: Vector2i) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(unit, "global_position", grid.cell_center(cell), 0.12)
	await tween.finished


## 可以停在這一格嗎
func can_stand(cell: Vector2i) -> bool:
	return area.has_point(cell) and grid.is_cell_walkable(cell) and unit_at(cell) == null


func _snap(unit: Unit) -> void:
	unit.follower().stop()
	var cell: Vector2i = cell_of(unit)
	if not grid.is_cell_walkable(cell) or _taken(cell, unit):
		cell = _nearest_free(cell, unit)
	unit.global_position = grid.cell_center(cell)


func _taken(cell: Vector2i, except: Unit) -> bool:
	return fighters.any(func(u: Unit) -> bool: return u != except and not u.is_down and cell_of(u) == cell)


## 附近最近的空格（像水一樣往外找）
func _nearest_free(from: Vector2i, unit: Unit) -> Vector2i:
	var seen: Dictionary[Vector2i, bool] = {from: true}
	var todo: Array[Vector2i] = [from]
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_front()
		if grid.is_cell_walkable(cell) and not _taken(cell, unit):
			return cell
		for d: Vector2i in DIRECTIONS:
			if not seen.has(cell + d) and grid.astar.is_in_boundsv(cell + d):
				seen[cell + d] = true
				todo.append(cell + d)
	return from


# ---- 打 ----

## 攻擊敵人，或幫自己人補血
func act(unit: Unit, target: Unit) -> void:
	if target.team == unit.team:
		await _lunge(unit, target)
		mend(target, unit.heal_power, "%s 補血" % name_of(unit))
		await wait(0.2)
	else:
		await strike(unit, target)


## 打一下。is_counter＝這一下是還手
func strike(unit: Unit, target: Unit, is_counter: bool = false) -> void:
	var damage: int = damage_of(unit, target)
	var reasons: PackedStringArray = _reasons.duplicate()
	var rolled: int = roll() if dice else 0
	if rolled == 6:
		damage *= 2
	if rolled > 0:
		reasons.insert(0, "骰 %d%s" % [rolled, " 失手" if rolled == 1 else " 加倍" if rolled == 6 else ""])
		_pop_number(unit, "骰 %d" % rolled, Color("ffe066"))
	var who: String = "%s%s → %s" % [name_of(unit), " 還手" if is_counter else "", name_of(target)]
	var why: String = "（%s）" % "、".join(reasons) if not reasons.is_empty() else ""
	await _lunge(unit, target)
	if rolled == 1:
		note("%s　沒打中%s" % [who, why])
		_pop_number(target, "失手", Color.WHITE)
		await wait(0.15)
		return
	note("%s　-%d%s" % [who, damage, why])
	_lose(target, damage)
	for t: UnitTrait in unit.traits():
		@warning_ignore("redundant_await")
		await t.after_attack(target, damage, self)                # 有的特性要等一下（例如擊退滑過去）
	if not target.is_down:
		for t: UnitTrait in target.traits():
			@warning_ignore("redundant_await")
			await t.after_hit(unit, damage, is_counter, self)
	await wait(0.15)


## 打下去會扣幾滴（特性、地形都算進去）。steps＝當作走了幾格（預覽用，-1＝照現在的）
func damage_of(unit: Unit, target: Unit, steps: int = -1) -> int:
	var real_steps: int = unit.steps_taken
	if steps >= 0:
		unit.steps_taken = steps
	var power: float = unit.attack
	_reasons.clear()
	for t: UnitTrait in unit.traits():
		power = _with_reason(t, power, t.modify_attack(power, target, self))
	unit.steps_taken = real_steps
	var damage: float = maxf(power - target.defense - terrain_defense(target), 1.0)
	if terrain_defense(target) > 0:
		_reasons.append("在%s" % TacticsMap.KIND_NAMES[kind_at(cell_of(target))])
	for t: UnitTrait in target.traits():
		damage = _with_reason(t, damage, t.modify_taken(damage, unit, self))
	for ally: Unit in units_beside(cell_of(target)):
		if ally.team == target.team:
			for t: UnitTrait in ally.traits():
				damage = _with_reason(t, damage, t.protect(damage, target))
	return maxi(roundi(damage), 1)


## 這個特性有改到數字的話記下來（日誌用）
func _with_reason(t: UnitTrait, before: float, after: float) -> float:
	if not is_equal_approx(before, after) and not _reasons.has(t.trait_name()):
		_reasons.append(t.trait_name())
	return after


## 擲一顆六面骰
func roll() -> int:
	return fixed_roll if fixed_roll > 0 else randi_range(1, 6)


## 站的地形多多少防禦
func terrain_defense(unit: Unit) -> int:
	return 0 if unit.is_flying() or _map == null else TacticsMap.KIND_DEFENSE[kind_at(cell_of(unit))]


func kind_at(cell: Vector2i) -> TacticsMap.Kind:
	return _map.kind_at(cell)


## 扣血＋跳數字＋記日誌。why＝為什麼（特性的名字）
func hurt(target: Unit, amount: int, why: String = "") -> void:
	if target.is_down:
		return
	note("　%s%s -%d" % ["" if why.is_empty() else why + "：", name_of(target), amount])
	_lose(target, amount)


func _lose(target: Unit, amount: int) -> void:
	if target.is_down:
		return
	target.take_damage(amount)
	_pop_number(target, "-%d" % amount, Color("ff6b5a"))
	if target.is_down:
		note("[b]%s 倒下了[/b]" % name_of(target))
		if target == focus:
			focus = null
		_fall(target)
	updated.emit()


## 補血＋跳數字＋記日誌。why＝為什麼（特性的名字）
func mend(target: Unit, amount: int, why: String = "") -> void:
	var healed: int = target.heal(amount)
	if healed > 0:
		note("%s%s +%d" % ["　" if why.is_empty() else why + " → ", name_of(target), healed])
		_pop_number(target, "+%d" % healed, Color("7ee08a"))
	updated.emit()


func _fall(unit: Unit) -> void:
	unit.create_tween().tween_property(unit, "modulate:a", 0.0, 0.3)


func _lunge(unit: Unit, target: Unit) -> void:
	var home: Vector2 = unit.global_position
	var toward: Vector2 = home + home.direction_to(target.global_position) * 10.0
	if distance(cell_of(unit), cell_of(target)) > 1:
		_shot(home, target.global_position, Color("7ee08a") if target.team == unit.team else Color("ffe066"))
	var tween: Tween = create_tween()
	tween.tween_property(unit, "global_position", toward, 0.08)
	tween.tween_property(unit, "global_position", home, 0.12)
	await tween.finished


## 遠程：畫一條飛過去的線
func _shot(from: Vector2, to: Vector2, color: Color) -> void:
	var line: Line2D = Line2D.new()
	line.width = 3.0
	line.default_color = color
	line.z_index = 5
	add_child(line)
	line.points = PackedVector2Array([to_local(from), to_local(to)])
	var tween: Tween = create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.25)
	tween.tween_callback(line.queue_free)


func _pop_number(unit: Unit, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.z_index = 20
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	label.global_position = unit.global_position + Vector2(-16, -44)
	var tween: Tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 18.0, 0.5)
	tween.tween_callback(label.queue_free)


## 可以對它動手嗎（不管距離）：敵人，或受傷的自己人（會治療的話）
func can_target(unit: Unit, other: Unit) -> bool:
	if other.is_down or other == unit:
		return false
	if other.team == unit.team:
		return unit.heal_power > 0 and other.health < other.max_health
	return true


## 站在 from 打得到 to 那一格嗎：距離夠、中間沒有牆；站在高地的遠程多一格
func in_range(unit: Unit, from: Vector2i, to: Vector2i) -> bool:
	var d: int = distance(from, to)
	var reach: int = unit.max_range
	if reach > 1 and kind_at(from) == TacticsMap.Kind.HIGH:
		reach += 1
	return d >= unit.min_range and d <= reach and (d <= 1 or clear_shot(from, to))


func cells_in_range(unit: Unit, from: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var reach: int = unit.max_range + 1
	for y: int in range(-reach, reach + 1):
		for x: int in range(-reach, reach + 1):
			var cell: Vector2i = from + Vector2i(x, y)
			if area.has_point(cell) and kind_at(cell) != TacticsMap.Kind.WALL and in_range(unit, from, cell):
				result.append(cell)
	return result


## 兩格中間沒有牆（遠程不能穿牆）
func clear_shot(from: Vector2i, to: Vector2i) -> bool:
	var steps: int = maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i: int in range(1, steps):
		var at: Vector2 = Vector2(from).lerp(Vector2(to), float(i) / steps)
		if kind_at(Vector2i(at.round())) == TacticsMap.Kind.WALL:
			return false
	return true


# ---- 結束 ----

func _check_end() -> bool:
	if alive(1).is_empty():
		_finish(true)
		return true
	if alive(0).is_empty():
		_finish(false, "我方全滅……")
		return true
	return false


func _finish(won: bool, message: String = "") -> void:
	state = State.NONE
	current = null
	focus = null
	late.clear()
	hovered = null
	_highlight()
	intents.clear()
	_intent_todo.clear()
	order.clear()
	note("[b]── %s ──[/b]" % ("打贏了" if won else "打輸了"))
	game_speed = game_speed                                       # 變回 1×
	paused = false
	_clear_options()
	if not won:
		updated.emit()
		ended.emit(false)
		GameFlow.lose(message)
		return
	for s: EnemySquad in squads:
		s.defeated()
	squads.clear()
	fighters.clear()
	_show_area(false)
	updated.emit()
	ended.emit(true)


func _apply_speed() -> void:
	Engine.time_scale = 0.0 if paused else (game_speed if state == State.FIGHT else 1.0)


## 等幾秒（遊戲時間：倍速會變快、暫停會停）
func wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var timer: Timer = Timer.new()                                # 自己底下的 Timer：換場景時跟著被刪掉
	timer.one_shot = true
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()


# ---- 問棋盤 ----

func cell_of(unit: Unit) -> Vector2i:
	return grid.cell_of(unit.global_position)


## 兩格差幾步（上下左右）
func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 還站著的（team＝-1：兩邊都要）
func alive(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit: Unit in fighters:
		if is_instance_valid(unit) and not unit.is_down and (team < 0 or unit.team == team):
			result.append(unit)
	return result


func unit_at(cell: Vector2i) -> Unit:
	for unit: Unit in alive(-1):
		if cell_of(unit) == cell:
			return unit
	return null


## 站在這一格旁邊（上下左右）的棋子
func units_beside(cell: Vector2i) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit: Unit in alive(-1):
		if distance(cell_of(unit), cell) == 1:
			result.append(unit)
	return result


# ---- 日誌 ----

## 記一行（名字用 name_of() 才有顏色）
func note(text: String) -> void:
	noted.emit(text)


## 日誌裡的名字：照隊伍上色；同一隊有好幾隻一樣的就編號
func name_of(unit: Unit) -> String:
	var same: Array[Unit] = fighters.filter(func(u: Unit) -> bool: return u.team == unit.team and u.display_name == unit.display_name)
	var text: String = unit.display_name + (str(same.find(unit) + 1) if same.size() > 1 else "")
	return "[color=#%s]%s[/color]" % ["8ec0ff" if unit.team == 0 else "ff9a8a", text]


func _note_moved(unit: Unit) -> void:
	note("[color=#bbbbbb]%s %s[/color]" % [name_of(unit), "走 %d 格" % unit.steps_taken if unit.steps_taken > 0 else "待命"])


# ---- 意圖、指定目標 ----

## 重新猜電腦操作的棋子打算做什麼（分好幾個畫面慢慢算）
func refresh_intents() -> void:
	_intent_todo.clear()
	if not is_active():
		return
	for unit: Unit in alive(-1):
		if unit.team == 1 or auto:
			_intent_todo.append(unit)
	for unit: Unit in intents.keys():
		if not _intent_todo.has(unit):
			intents.erase(unit)
	_redraw_marks()


## 打算走的路（指著它的時候畫）
func _intent_path(unit: Unit) -> Array[Vector2i]:
	if intents[unit]["cell"] == cell_of(unit):
		return []
	legal_moves(unit)
	return move_range.path_to(intents[unit]["cell"])


## 指定我方優先打誰（null＝取消）
func set_focus(unit: Unit) -> void:
	focus = unit
	if unit != null:
		note("指定目標：%s" % name_of(unit))
	refresh_intents()
	updated.emit()


## 這隻打算做什麼（畫面用）
func intent_text(unit: Unit) -> String:
	if not intents.has(unit):
		return ""
	var plan: Dictionary = intents[unit]
	if plan["target"] != null:
		return "%s%s" % ["補 " if plan["target"].team == unit.team else "打 ", plan["target"].display_name]
	return "往%s靠近" % plan["toward"].display_name if plan["toward"] != null else "守在原地"


# ---- 滑鼠、畫面 ----

func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or grid == null:
		return
	if event is InputEventMouseMotion:
		_show_unit(unit_at(_mouse_cell()))
		return
	if state == State.FIGHT and event.is_action_pressed("attack") and is_waiting:
		choose_wait()
		get_viewport().set_input_as_handled()
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		click(_mouse_cell())
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		if state == State.DEPLOY:
			picked = null
			updated.emit()
			queue_redraw()
		else:
			choose_undo()
		get_viewport().set_input_as_handled()


func _mouse_cell() -> Vector2i:
	return grid.cell_of(get_global_mouse_position())


## 左鍵點一格
func click(cell: Vector2i) -> void:
	var unit: Unit = unit_at(cell)
	if state == State.FIGHT and is_waiting:
		choose_cell(cell)
		return
	if unit != null and unit.team == 1:
		set_focus(null if focus == unit else unit)
		return
	if state == State.FIGHT:
		return
	if picked != null and deploy_cells.has(cell):
		place(picked, cell)
	elif unit != null and unit.team == 0:
		picked = unit
		updated.emit()
		queue_redraw()


## 滑鼠指著誰：顯示數值、它這一回合威脅得到的格子
func _show_unit(unit: Unit) -> void:
	if unit == hovered:
		return
	hovered = unit
	threat_cells = threat_of(unit) if unit != null and not is_waiting else ([] as Array[Vector2i])
	updated.emit()
	queue_redraw()
	_redraw_marks()


## 這隻一回合打得到的所有格子（走到哪裡＋打多遠）
func threat_of(unit: Unit) -> Array[Vector2i]:
	var found: Dictionary[Vector2i, bool] = {}
	for from: Vector2i in legal_moves(unit):
		for cell: Vector2i in cells_in_range(unit, from):
			found[cell] = true
	var result: Array[Vector2i] = []
	result.assign(found.keys())
	return result


func _show_area(on: bool) -> void:
	if _camera == null:
		return
	_camera.follow = not on
	_camera.limit_enabled = not on and _camera.use_limits         # 戰鬥時戰場放在畫面左邊，不管地圖邊界
	if not on:
		_camera.zoom = Vector2(_zoom, _zoom)
		return
	_zoom = _camera.zoom.x
	var rect: Rect2 = area_rect().grow(16)                        # 整個戰場放進畫面（上下留給順序和按鈕、右邊留給日誌）
	var fit: float = minf((1280.0 - side_panel) / rect.size.x, 560.0 / rect.size.y)
	_camera.zoom = Vector2.ONE * minf(_zoom, fit)
	_camera.global_position = rect.get_center() + Vector2(side_panel / 2.0 / _camera.zoom.x, 0)


## 戰場範圍（全域座標）
func area_rect() -> Rect2:
	var size: Vector2 = grid.cell_size()
	return Rect2(grid.cell_center(area.position) - size / 2.0, Vector2(area.size) * size)


func _draw() -> void:
	if not is_active():
		return
	var rect: Rect2 = area_rect()
	rect.position = to_local(rect.position)
	var far: Rect2 = rect.grow(4000)                              # 戰場外面變暗：上下左右四塊
	draw_rect(Rect2(far.position, Vector2(far.size.x, rect.position.y - far.position.y)), outside_color)
	draw_rect(Rect2(far.position.x, rect.end.y, far.size.x, far.end.y - rect.end.y), outside_color)
	draw_rect(Rect2(far.position.x, rect.position.y, rect.position.x - far.position.x, rect.size.y), outside_color)
	draw_rect(Rect2(rect.end.x, rect.position.y, far.end.x - rect.end.x, rect.size.y), outside_color)
	draw_rect(rect, Color(1, 1, 1, 0.4), false, 2.0)
	if state == State.DEPLOY:
		for cell: Vector2i in deploy_cells:
			_draw_cell(cell, Color(0.3, 0.6, 1.0, 0.3), Color(0.5, 0.8, 1.0, 0.8))
		if picked != null:
			_draw_cell(cell_of(picked), Color(1, 1, 0.5, 0.35), Color(1, 1, 0.5))
	for cell: Vector2i in threat_cells:
		_draw_cell(cell, Color(1, 0.35, 0.25, 0.18), Color(1, 0.4, 0.3, 0.25))
	for cell: Vector2i in attack_cells:
		_draw_cell(cell, Color(1, 0.35, 0.25, 0.22), Color(1, 0.4, 0.3, 0.5))
	for unit: Unit in target_units:
		if is_instance_valid(unit):
			_draw_cell(cell_of(unit), Color.TRANSPARENT, Color("7ee08a") if unit.team == 0 else Color("ff5a4a"), 3.0)


func _draw_cell(cell: Vector2i, fill: Color, border: Color, width: float = 1.0) -> void:
	var size: Vector2 = grid.cell_size()
	var rect: Rect2 = Rect2(to_local(grid.cell_center(cell)) - size / 2.0, size).grow(-1.0)
	if fill.a > 0.0:
		draw_rect(rect, fill)
	draw_rect(rect, border, false, width)


func _redraw_marks() -> void:
	if _marks != null:
		_marks.queue_redraw()


## 指著（或布陣時拿著）的棋子
func _looked_at() -> Unit:
	var unit: Unit = hovered if hovered != null else picked
	return unit if unit != null and is_instance_valid(unit) and not unit.is_down and is_active() else null


## 這隻打算打（補、靠近）誰，沒有＝null
func target_of(unit: Unit) -> Unit:
	if not intents.has(unit):
		return null
	var target: Unit = intents[unit]["target"] if intents[unit]["target"] != null else intents[unit]["toward"]
	return target if target != null and is_instance_valid(target) and not target.is_down else null


## 跟 unit 有關的棋子：它自己、它的目標、打算打它的
func related_to(unit: Unit) -> Array[Unit]:
	var result: Array[Unit] = [unit]
	for other: Unit in alive(-1):
		if other != unit and (target_of(unit) == other or target_of(other) == unit):
			result.append(other)
	return result


## 指著一隻的時候，跟它沒關係的棋子變淡
func _highlight() -> void:
	var looked: Unit = _looked_at() if show_intents and not is_waiting else null
	var bright: Array[Unit] = related_to(looked) if looked != null else ([] as Array[Unit])
	for unit: Unit in fighters + party:
		if is_instance_valid(unit):
			unit.self_modulate = Color(0.6, 0.6, 0.6, 0.55) if looked != null and not bright.has(unit) else Color.WHITE


## 箭頭：誰打算打誰（實線＝這一輪打得到、虛線＝還打不到，先靠近）；
## 指著一隻，它的（連走的路）和打算打它的會亮起來，其他的變淡
func _draw_marks() -> void:
	if not is_active():
		return
	if focus != null and is_instance_valid(focus) and not focus.is_down:
		var at: Vector2 = to_local(focus.global_position)
		_marks.draw_arc(at, 17.0, 0, TAU, 32, Color("ffb020"), 3.0)
		for i: int in 4:
			var side: Vector2 = Vector2.from_angle(PI / 2.0 * i)
			_marks.draw_line(at + side * 13.0, at + side * 23.0, Color("ffb020"), 3.0)
	if is_waiting and hovered != null and target_units.has(hovered):
		_draw_stand(hovered)
	if not show_intents:
		return
	var looked: Unit = _looked_at()
	for unit: Unit in intents:
		if unit != looked:
			_draw_intent(unit, false, 1.0 if looked != null and target_of(unit) == looked else 0.75 if looked == null else 0.15)
	if looked == null:
		return
	_draw_intent(looked, true)
	var pulse: float = 16.0 + 2.0 * sin(Time.get_ticks_msec() * 0.008)
	_marks.draw_arc(to_local(looked.global_position), 16.0, 0, TAU, 32, Color.WHITE, 2.5)
	var target: Unit = target_of(looked)
	if target != null:
		_marks.draw_arc(to_local(target.global_position), pulse, 0, TAU, 32, _intent_color(looked, target), 3.0)


## 打這隻會站到哪一格（回合制選目標時）
func _draw_stand(target: Unit) -> void:
	var cell: Vector2i = best_cell_to_hit(current, target)
	var at: Vector2 = to_local(grid.cell_center(cell))
	if cell != cell_of(current):
		_marks.draw_dashed_line(to_local(current.global_position), at, Color(1, 1, 1, 0.7), 2.0, 6.0)
		_marks.draw_circle(at, 11.0, Color(current.color, 0.55))
	_marks.draw_arc(at, 13.0, 0, TAU, 24, Color.WHITE, 2.0)


func _intent_color(unit: Unit, target: Unit) -> Color:
	if target.team == unit.team:
		return Color("7ee08a")
	return Color("ff5a4a") if unit.team == 1 else Color("5aa8ff")


func _draw_intent(unit: Unit, with_path: bool, alpha: float = 1.0) -> void:
	if not is_instance_valid(unit) or unit.is_down or target_of(unit) == null:
		return
	var plan: Dictionary = intents[unit]
	var sure: bool = plan["target"] != null
	var target: Unit = target_of(unit)
	var color: Color = Color(_intent_color(unit, target), alpha)
	var from: Vector2 = to_local(unit.global_position)
	if with_path and not plan["path"].is_empty():
		var line: PackedVector2Array = PackedVector2Array([from])
		for step: Vector2i in plan["path"]:
			line.append(to_local(grid.cell_center(step)))
		_marks.draw_polyline(line, Color(color, 0.9), 3.0)
		from = line[line.size() - 1]
		_marks.draw_circle(from, 5.0, color)
	_draw_arrow(from, to_local(target.global_position), color, sure)


func _draw_arrow(from: Vector2, to: Vector2, color: Color, solid: bool) -> void:
	var along: Vector2 = from.direction_to(to)
	var side: Vector2 = along.orthogonal() * 4.0                   # 稍微靠旁邊，互打的兩條才不會疊在一起
	var start: Vector2 = from + along * 8.0 + side
	var end: Vector2 = to - along * 12.0 + side
	if solid:
		_marks.draw_line(start, end - along * 6.0, color, 2.5)
	else:
		_marks.draw_dashed_line(start, end - along * 6.0, color, 2.0, 7.0)
	var wing: Vector2 = along.orthogonal() * 5.0
	_marks.draw_colored_polygon(PackedVector2Array([end, end - along * 9.0 + wing, end - along * 9.0 - wing]), color)
