class_name TacticsParty
extends Node2D
## 我方隊伍（探索時）：WASD 或滑鼠左鍵控制一個人，其他人照陣形自己找路跟上。
## 整隊／分開（Tab）：分開時只有控制的人會動，其他人站在原地。Q、點頭像、點棋子換人控制，1～4 換陣形。
## 會飛的人直線飛，可以越過牆（岩石），不會被地形拖慢。
## 左鍵點地上＝自己繞路走過去，按住＝跟著滑鼠走，點寶箱＝走過去搜；按 WASD 就取消。
## 碰到地上的物資會撿起來；寶箱旁邊按 E 搜括；其他地方按 E 紮營休息：花一份物資、等幾秒，全隊回復一些血。
## 搜括、紮營的時候不能走，被敵人注意到就會中斷。

## 隊伍有變化（血量、物資、紮營）
signal changed()

## 換人控制
signal control_changed(unit: Unit)

## 走路的速度（像素／秒）
@export_range(40, 400, 5, "suffix:px/s") var walk_speed: float = 130.0
## 隊友離前面的人多遠就跟上、陣形的間隔（像素）
@export_range(16, 120, 2, "suffix:px") var follow_distance: float = 34.0
## 紮營時離多近的隊友會一起回血（像素）
@export_range(32, 1000, 8, "suffix:px") var camp_range: float = 200.0
## 紮營要幾秒
@export_range(0.5, 10.0, 0.5, "suffix:秒") var camp_time: float = 2.5
## 搜一個寶箱要幾秒
@export_range(0.0, 10.0, 0.5, "suffix:秒") var search_time: float = 1.5
## 離寶箱多近可以搜（像素）
@export_range(16, 120, 2, "suffix:px") var search_distance: float = 46.0
## 離物資多近會撿起來（像素）
@export_range(8, 64, 2, "suffix:px") var pickup_distance: float = 24.0

var members: Array[Unit] = []
## 分開走
var split: bool = false
## 整隊走時的陣形
var formation: TacticsFormation.Kind = TacticsFormation.Kind.COLUMN
var supplies: int = 0
## 正在紮營幾秒了（0＝沒有）
var camping: float = 0.0
## 正在搜哪個寶箱（null＝沒有）、搜幾秒了
var searching: TacticsChest
var searched: float = 0.0
## 最後一個訊息（HUD 顯示）
var message: String = ""

var battle: TacticsBattle
var _map: TacticsMap
var _grid: PathGrid
## 地圖左上角在哪裡
var _origin: Vector2
## 左鍵按著（跟著滑鼠走）、上次叫它走去哪、隔多久再重新找路
var _holding: bool = false
var _goal: Vector2
var _controlled: Unit
## 陣形朝哪個方向、隔多久再重新排
var _heading: Vector2 = Vector2.RIGHT
var _arrange_time: float = 0.0
var _repath_time: float = 0.0
## 點了哪個寶箱、同伴（走到旁邊就搜、招募）
var _want: Node2D

## 隊長的身體半徑（撞牆用）
const BODY: float = 9.0


func _ready() -> void:
	add_to_group("tactics_party")


## 照地圖把隊伍放好（units＝帶了誰）
func setup(map: TacticsMap, at: Vector2, tactics_battle: TacticsBattle, units: Array[String], first_formation: int) -> void:
	_map = map
	battle = tactics_battle
	supplies = map.supplies
	_origin = at - map.cell_center(map.start_cell)
	_grid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	for path: String in units:
		_add_unit(path, at)
	formation = first_formation as TacticsFormation.Kind
	split = map.allow_split and map.start_split
	control(members[0])
	battle.party = members
	battle.ended.connect(_on_battle_ended)
	battle.deploy_started.connect(queue_redraw)                   # 開打了：路線不畫了


func _add_unit(path: String, at: Vector2) -> Unit:
	var unit: Unit = (load(path) as PackedScene).instantiate() as Unit
	unit.team = 0
	add_child(unit)
	unit.global_position = at
	unit.z_index = 2
	members.append(unit)
	unit.follower().arrived.connect(queue_redraw)
	unit.follower().use_pathfinding = not unit.is_flying()        # 會飛的不找路，直線飛
	return unit


## 現在控制的人（整隊走時帶頭的）
func leader() -> Unit:
	return _controlled if is_instance_valid(_controlled) and members.has(_controlled) else members[0]


## 隊長：隊伍的第一隻（走到目標格要他）
func captain() -> Unit:
	return members[0]


## 敵人看得到誰：分開走時每個人都會被看到，整隊走時看帶頭的
func exposed() -> Array[Unit]:
	return members if split else ([leader()] as Array[Unit])


# ---- 控制誰、整隊或分開、陣形 ----

## 換人控制（鏡頭跟著他）
func control(unit: Unit) -> void:
	if _controlled != null and is_instance_valid(_controlled):
		stop_walking()
		_controlled.remove_from_group("player")
	_controlled = unit
	unit.follower().stop()
	unit.add_to_group("player")                                   # 鏡頭跟著它
	for other: Unit in members:
		other.z_index = 3 if other == unit else 2
	control_changed.emit(unit)
	changed.emit()
	queue_redraw()


func control_index(index: int) -> void:
	if is_exploring() and index >= 0 and index < members.size() and members[index] != leader():
		interrupt("換人，中斷了")
		control(members[index])


## 切換整隊／分開。回傳有沒有成功
func set_split(on: bool) -> bool:
	if on == split or not is_exploring() or (on and not _map.allow_split):
		return false
	split = on
	for unit: Unit in members:
		if unit != leader():
			unit.follower().stop()
	say("分開走：只有你控制的人會動" if split else "整隊走：大家跟上")
	return true


## 這一關可不可以分開走
func can_split() -> bool:
	return _map != null and _map.allow_split


func set_formation(kind: int) -> void:
	if kind == formation or kind < 0 or kind >= TacticsFormation.NAMES.size() or not is_exploring():
		return
	formation = kind as TacticsFormation.Kind
	for unit: Unit in members:
		if unit != leader():
			unit.follower().stop()
	say("陣形：" + TacticsFormation.NAMES[formation])


## 正在探索（沒在打、沒有布陣）
func is_exploring() -> bool:
	return battle != null and not battle.is_active() and not GameFlow.is_finished() and not members.is_empty()


func _physics_process(delta: float) -> void:
	if not is_exploring():
		_holding = false
		_want = null
		return
	if camping > 0.0:
		_camp(delta)
	elif searching != null:
		_search(delta)
	else:
		_walk(delta)
	if not split:
		_follow_leader(delta)


## 控制的人：WASD 走，撞到牆會沿著牆滑；沒按 WASD 就照左鍵點的地方走
func _walk(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed: float = walk_speed                                 # 沼澤、森林走起來慢（會飛的不管）
	if not leader().is_flying():
		speed /= sqrt(_cost_at(leader().global_position))
	if direction == Vector2.ZERO:
		_walk_to_goal(speed, delta)
		return
	stop_walking()
	leader().facing = direction.normalized()
	var step: Vector2 = direction * speed * delta
	var moved_x: bool = step.x != 0.0 and _try_move(Vector2(step.x, 0))
	var moved_y: bool = step.y != 0.0 and _try_move(Vector2(0, step.y))
	if not moved_x and not moved_y:                               # 正對著斜的牆：往旁邊滑
		for side: float in [-PI / 4.0, PI / 4.0]:
			if _try_move(step.rotated(side) * 0.7):
				break


# ---- 左鍵移動 ----

## 走去 at（全局座標），自己繞路。點到寶箱就走過去搜
func walk_to(at: Vector2) -> void:
	_want = null
	for node: Node in get_tree().get_nodes_in_group("tactics_chests") + get_tree().get_nodes_in_group("tactics_allies"):
		var chest: TacticsChest = node as TacticsChest
		if (chest == null or not chest.opened) and (node as Node2D).global_position.distance_to(at) < 20.0:
			_want = node as Node2D
	_goal = at
	if leader().is_flying():
		at = at.clamp(_bounds().position, _bounds().end)
	leader().follower().go_to(at)


## 不走了（按了 WASD、開始搜）
func stop_walking() -> void:
	_holding = false
	_want = null
	if leader().follower().is_moving():
		leader().follower().stop()
		queue_redraw()


func _walk_to_goal(speed: float, delta: float) -> void:
	var follower: PathFollower = leader().follower()
	_repath_time -= delta
	if _holding and _repath_time <= 0.0 and get_global_mouse_position().distance_to(_goal) > 12.0:
		_repath_time = 0.12
		walk_to(get_global_mouse_position())
	if not follower.is_moving():
		return
	follower.speed = speed
	if follower.move_direction != Vector2.ZERO:
		leader().facing = follower.move_direction
	queue_redraw()
	if is_instance_valid(_want) and _want.global_position.distance_to(leader().global_position) < search_distance * 0.8:
		var found: Node2D = _want
		stop_walking()
		if found is TacticsAlly:
			recruit(found as TacticsAlly)
		else:
			start_search(found as TacticsChest)


## 走得過去就走。回傳有沒有動
func _try_move(step: Vector2) -> bool:
	var to: Vector2 = leader().global_position + step
	if leader().is_flying():
		if not _bounds().has_point(to):
			return false
		leader().global_position = to
		return true
	if not _grid.is_walkable(to):
		return false                                              # 中心要在走得到的格子裡（尋路、視野都看格子）
	for i: int in 8:
		if _is_wall(to + Vector2.from_angle(TAU * i / 8.0) * BODY):
			return false
	leader().global_position = to
	return true


## 地圖的範圍（會飛的也不能飛出去）
func _bounds() -> Rect2:
	return Rect2(_origin, Vector2(_map.size * TacticsMap.CELL)).grow(-BODY)


## 牆照畫出來的圓滑邊緣算；地圖以外的障礙物看尋路地圖
func _is_wall(at: Vector2) -> bool:
	if _map.sample(TacticsMap.Kind.WALL, at - _origin) >= 0.5:
		return true
	return not _grid.is_walkable(at) and _map.kind_at(_map.cell_at(at - _origin)) != TacticsMap.Kind.WALL


func _cost_at(at: Vector2) -> float:
	return _grid.cost_of(_grid.cell_of(at))


## 隊友跟上：一列＝一個跟一個，其他陣形＝走到自己的位置
func _follow_leader(delta: float) -> void:
	var line: Array[Unit] = [leader()]
	for unit: Unit in members:
		if unit != leader():
			line.append(unit)
	if formation != TacticsFormation.Kind.COLUMN:
		_arrange(line, delta)
		return
	for i: int in range(1, line.size()):
		var unit: Unit = line[i]
		var ahead: Unit = line[i - 1]
		var far: float = unit.global_position.distance_to(ahead.global_position)
		unit.follower().speed = walk_speed * (1.0 if far < follow_distance * 2.5 else 1.6)   # 落後太多就跑
		if far > follow_distance and not unit.follower().is_moving():
			unit.follower().follow(ahead)
		elif far < follow_distance * 0.8 and unit.follower().is_moving():
			unit.follower().stop()


## 排陣形：每隔一小段時間，叫每一隻走去自己的位置（旁邊是牆就擠到最近的空格）
func _arrange(line: Array[Unit], delta: float) -> void:
	_arrange_time -= delta
	if _arrange_time > 0.0:
		return
	_arrange_time = 0.15
	_heading = Vector2.from_angle(rotate_toward(_heading.angle(), leader().facing.angle(), 0.5))   # 慢慢轉，急轉彎才不會全部亂跑
	var front: Vector2i = _grid.cell_of(leader().global_position)
	var taken: Dictionary[Vector2i, bool] = {front: true}
	for i: int in range(1, line.size()):
		var unit: Unit = line[i]
		var want: Vector2 = leader().global_position + TacticsFormation.offset(formation, i, line.size(), _heading, follow_distance)
		var to: Vector2 = want.clamp(_bounds().position, _bounds().end)
		if not unit.is_flying():
			var cell: Vector2i = TacticsFormation.slot(_grid, front, want, taken)
			taken[cell] = true
			if _grid.cell_of(want) != cell:
				to = _grid.cell_center(cell)
		var far: float = unit.global_position.distance_to(to)
		unit.follower().speed = walk_speed * (1.15 if far < follow_distance * 2.0 else 1.6)
		if far > 8.0:
			unit.follower().go_to(to)
		elif unit.follower().is_moving():
			unit.follower().stop()


## 拿到物資
func take_supply(amount: int = 1, how: String = "拿到") -> void:
	supplies += amount
	say("%s %d 份營地物資（現在 %d）" % [how, amount, supplies])


## 紮營、搜括到一半被打斷
func interrupt(why: String) -> void:
	if camping > 0.0 or searching != null:
		camping = 0.0
		searching = null
		say(why)
		queue_redraw()


# ---- 寶箱 ----

## 最近的、搜得到、還沒搜過的寶箱（沒有＝null）
func nearest_chest() -> TacticsChest:
	var best: TacticsChest = null
	var best_distance: float = search_distance
	for node: Node in get_tree().get_nodes_in_group("tactics_chests"):
		var chest: TacticsChest = node as TacticsChest
		var far: float = chest.global_position.distance_to(leader().global_position)
		if not chest.opened and far <= best_distance:
			best = chest
			best_distance = far
	return best


## 最近的、招募得到的同伴（沒有＝null）
func nearest_ally() -> TacticsAlly:
	var best: TacticsAlly = null
	var best_distance: float = search_distance
	for node: Node in get_tree().get_nodes_in_group("tactics_allies"):
		var ally: TacticsAlly = node as TacticsAlly
		var far: float = ally.global_position.distance_to(leader().global_position)
		if far <= best_distance and not ally.is_queued_for_deletion():
			best = ally
			best_distance = far
	return best


## 招募：當場加入隊伍，過關之後進隊伍池
func recruit(ally: TacticsAlly) -> void:
	var unit: Unit = _add_unit(ally.unit_path, ally.global_position)
	(get_tree().get_first_node_in_group("tactics_level") as TacticsLevel).recruited[ally.key] = ally.unit_path
	ally.queue_free()
	say("%s 加入隊伍！（過關之後會留下來）" % unit.display_name)


## 開始搜。回傳有沒有成功
func start_search(chest: TacticsChest) -> bool:
	if chest == null or chest.opened:
		return false
	if _is_noticed():
		say("有敵人注意到你，不能搜")
		return false
	searching = chest
	searched = 0.0
	say("搜括中……")
	return true


func _search(delta: float) -> void:
	if _is_noticed():
		interrupt("被發現了，中斷！")
		return
	searched += delta
	queue_redraw()
	if searched < search_time:
		return
	var chest: TacticsChest = searching
	searching = null
	chest.open(self)
	queue_redraw()


# ---- 紮營 ----

func _unhandled_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_holding = button.pressed and is_exploring() and camping <= 0.0 and searching == null
		if _holding:
			var picked: Unit = _member_at(get_global_mouse_position())
			if picked != null:
				_holding = false
				control(picked)                                   # 點到隊友：換控制他
			else:
				walk_to(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and is_exploring():
		if key.physical_keycode == KEY_TAB:
			set_split(not split)
		elif key.physical_keycode == KEY_Q:
			control_index((members.find(leader()) + 1) % members.size())
		elif key.physical_keycode >= KEY_1 and key.physical_keycode < KEY_1 + TacticsFormation.NAMES.size():
			set_formation(key.physical_keycode - KEY_1)
		else:
			_interact(event)
			return
		get_viewport().set_input_as_handled()
		return
	_interact(event)


## 滑鼠點到哪個隊友（控制中的不算）
func _member_at(at: Vector2) -> Unit:
	for unit: Unit in members:
		if unit != leader() and unit.global_position.distance_to(at) < 14.0:
			return unit
	return null


func _interact(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and is_exploring():
		var chest: TacticsChest = nearest_chest()
		var ally: TacticsAlly = nearest_ally()
		if camping > 0.0 or searching != null:
			interrupt("不休息了" if camping > 0.0 else "不搜了")
		elif ally != null:
			recruit(ally)
		elif chest != null:
			stop_walking()
			start_search(chest)
		else:
			stop_walking()
			start_camp()
		get_viewport().set_input_as_handled()


## 開始紮營。回傳有沒有成功
func start_camp() -> bool:
	if supplies <= 0:
		say("沒有營地物資了")
		return false
	if _camp_members().all(func(u: Unit) -> bool: return u.health >= u.max_health):
		say("%s都很健康，不用休息" % ("附近的人" if split else "大家"))
		return false
	if _is_noticed():
		say("有敵人注意到你，不能紮營")
		return false
	camping = 0.001
	say("紮營中……")
	return true


func _camp(delta: float) -> void:
	if _is_noticed():
		interrupt("被發現了，中斷！")
		return
	camping += delta
	queue_redraw()
	if camping < camp_time:
		return
	camping = 0.0
	supplies -= 1
	for unit: Unit in _camp_members():
		unit.heal(ceili(unit.max_health * _map.camp_heal))
	say("休息好了（剩 %d 份物資）" % supplies)
	queue_redraw()


## 紮營會回血的人：分開走時只有附近的
func _camp_members() -> Array[Unit]:
	return members.filter(func(u: Unit) -> bool: return not split or u.global_position.distance_to(leader().global_position) <= camp_range)


func _is_noticed() -> bool:
	return get_tree().get_nodes_in_group("enemy_squads").any(func(n: Node) -> bool: return (n as EnemySquad).alert > 0.0)


# ---- 打完 ----

func _on_battle_ended(won: bool) -> void:
	if not won:
		return
	for i: int in range(members.size() - 1, -1, -1):
		var unit: Unit = members[i]
		if unit.is_down:
			if _map.revive or i == 0:                             # 隊長一定會站起來（還活著才打得贏）
				unit.revive(1)
			else:
				members.remove_at(i)
				battle.party = members
				unit.queue_free()
				continue
		unit.modulate.a = 1.0
		unit.visible = true
		unit.is_active = false
	control(leader())
	say("打贏了！")


func say(text: String) -> void:
	message = text
	if battle != null:
		battle.note(text)
	changed.emit()


func _draw() -> void:
	if members.is_empty():
		return
	var at: Vector2 = to_local(leader().global_position)
	if is_exploring() and leader().follower().is_moving():        # 左鍵移動：要走的路和終點
		var line: PackedVector2Array = PackedVector2Array([at])
		for point: Vector2 in leader().follower().path:
			line.append(to_local(point))
		for i: int in line.size() - 1:
			draw_dashed_line(line[i], line[i + 1], Color(1, 1, 1, 0.55), 2.0, 6.0)
		draw_arc(line[line.size() - 1], 7.0, 0, TAU, 20, Color(1, 1, 1, 0.8), 2.0)
	if searching != null:
		draw_arc(to_local(searching.global_position), 22.0, -PI / 2, -PI / 2 + TAU * searched / maxf(search_time, 0.01), 32, Color("f0d060"), 4.0)
	if camping <= 0.0:
		return
	draw_colored_polygon(PackedVector2Array([at + Vector2(-26, 14), at + Vector2(0, -24), at + Vector2(26, 14)]), Color(0.85, 0.65, 0.35, 0.5))
	draw_arc(at, 30.0, -PI / 2, -PI / 2 + TAU * camping / camp_time, 32, Color("7ee08a"), 4.0)
