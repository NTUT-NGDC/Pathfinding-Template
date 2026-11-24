class_name EnemySquad
extends Node2D
## 一隊敵人（探索時）：照地圖上擺的隊形，一起沿著巡邏點走；沒有巡邏點就站在原地各自張望。
## 每一隻都有視野（小隊可以改成只有帶頭的有），警戒值整隊共用：
##   有人看到我方 → ?（警戒值慢慢升）→ 滿了 ! → 開打
##   我方在沒被看到的時候碰到任何一隻 → 偷襲（第一輪我方全部先動）
## 設定都在地圖的 TacticsSquad，用編輯器的「小隊」頁改。

## 開打了（ambush＝被偷襲，who＝被看到、碰到的我方）
signal spotted(squad: EnemySquad, ambush: bool, who: Unit)

var data: TacticsSquad
var members: Array[Unit] = []
## 警戒值 0～1，滿了就開打
var alert: float = 0.0
## 每一隻的視野（順序跟 members 一樣；沒有視野的是 null）
var visions: Array[VisionSensor] = []
var battle: TacticsBattle
## 現在看到的我方（沒看到＝null）
var seen: Unit

var _points: Array[Vector2] = []
var _next: int = 0
var _direction: int = 1
var _wait_time: float = 0.0
var _look_time: float = 0.0
## 正在走去下一個巡邏點
var _going: bool = false
## 走到一半停下來了（在懷疑），等一下要繼續走
var _halted: bool = false
## 每一隻一開始站的位置（跟帶頭的差多遠＝隊形）
var _homes: Array[Vector2] = []
## 每一隻張望時以哪個方向為中心
var _look_angles: Array[float] = []
var _in_battle: bool = false
var _grid: PathGrid

## 碰到多近算偷襲（像素）
const TOUCH: float = 36.0
## 看不到之後，警戒值每秒降多少
const CALM: float = 0.35
## 走到巡邏點停幾秒
const PATROL_WAIT: float = 1.0
## 張望時左右轉幾度
const LOOK_ANGLE: float = 40.0


func _ready() -> void:
	add_to_group("enemy_squads")


func setup(squad: TacticsSquad, map: TacticsMap, origin: Vector2, tactics_battle: TacticsBattle) -> void:
	data = squad
	battle = tactics_battle
	_grid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	for i: int in squad.members.size():
		var unit: Unit = (load(squad.members[i]) as PackedScene).instantiate() as Unit
		unit.team = 1
		add_child(unit)
		unit.global_position = origin + map.cell_center(squad.cells[i])
		unit.z_index = 2
		unit.follower().use_pathfinding = not unit.is_flying()    # 會飛的不找路，直線飛
		members.append(unit)
		_homes.append(unit.global_position)
		_look_angles.append(squad.look_angle(i))
		unit.facing = Vector2.from_angle(_look_angles[i])
		visions.append(_make_vision(unit, i))
	for cell: Vector2i in squad.patrol:
		_points.append(origin + map.cell_center(cell))


func _make_vision(unit: Unit, index: int) -> VisionSensor:
	if data.view_of(index) <= 0.0:
		return null
	var vision: VisionSensor = VisionSensor.new()
	vision.view_distance = data.view_of(index)
	vision.view_angle = data.view_angle
	vision.target_group = ""                                      # 看誰由小隊決定（我方分開走時有好幾個人）
	vision.cone_rays = 24 if index == 0 else 12
	unit.add_child(vision)
	return vision


func leader() -> Unit:
	return members[0]


## 看到我方的誰（沒有＝null）
func look_for() -> Unit:
	for unit: Unit in _party().exposed():
		if visions.any(func(v: VisionSensor) -> bool: return v != null and v.can_see(unit)):
			return unit
	return null


func _party() -> TacticsParty:
	return get_tree().get_first_node_in_group("tactics_party") as TacticsParty


func _physics_process(delta: float) -> void:
	if _in_battle or battle == null or battle.is_active() or members.is_empty() or GameFlow.is_finished():
		_show_cones(false)
		return
	_show_cones(true)
	_update_alert(delta)
	if battle.is_active():
		return                                                    # 剛剛開打了
	if alert > 0.0:
		_suspect(delta)
	else:
		_patrol(delta)
	for i: int in members.size():
		if visions[i] == null:
			continue
		visions[i].facing = members[i].facing
		if alert > 0.0:
			visions[i].cone_color = Color(1, 0.85, 0.2, 0.25 if i == 0 else 0.16)
		else:
			visions[i].cone_color = Color(1, 1, 1, 0.16 if i == 0 else 0.1)


func _show_cones(on: bool) -> void:
	for vision: VisionSensor in visions:
		if vision != null:
			vision.show_cone = on


## 警戒值：有人看得到就升、看不到就降；滿了開打；沒發現你就被碰到＝偷襲
func _update_alert(delta: float) -> void:
	seen = look_for()
	if seen != null:
		alert += delta / maxf(data.reaction_time, 0.01)
	else:
		alert = maxf(alert - CALM * delta, 0.0)
	for unit: Unit in members:
		unit.alert_mark = "!" if alert >= 1.0 else "?" if alert > 0.0 else ""
	if alert >= 1.0 and seen != null:
		spotted.emit(self, false, seen)
		return
	for unit: Unit in _party().exposed():
		if members.any(func(u: Unit) -> bool: return u.global_position.distance_to(unit.global_position) < TOUCH):
			spotted.emit(self, seen == null, unit)
			return


## 在懷疑：停下來，看得到的話全隊轉過去
func _suspect(delta: float) -> void:
	_halted = _going
	for unit: Unit in members:
		unit.follower().stop()
		if seen != null:
			_face(unit, seen.global_position - unit.global_position, delta)


# ---- 巡邏 ----

func _patrol(delta: float) -> void:
	if _points.is_empty():
		_stand(delta)
		return
	if _going:
		if _halted:
			_halted = false
			_send()                                               # 沒事了，繼續走
		_march(delta)
		return
	_look_around(delta)
	_wait_time -= delta
	if _wait_time <= 0.0 and (_points.size() > 1 or leader().global_position.distance_to(_points[0]) > 8.0):
		_going = true
		_send()


## 全隊走去下一個巡邏點，每一隻走到自己在隊形裡的位置
func _send() -> void:
	var taken: Dictionary[Vector2i, bool] = {}
	var goal: Vector2i = _grid.cell_of(_points[_next])
	for i: int in members.size():
		var cell: Vector2i = TacticsFormation.slot(_grid, goal, _points[_next] + _homes[i] - _homes[0], taken)
		taken[cell] = true
		members[i].follower().speed = data.patrol_speed
		members[i].follower().go_to(_grid.cell_center(cell))


## 走路中：落後的走快一點、超前的走慢一點，全部到了才算到
func _march(delta: float) -> void:
	var moving: bool = false
	var lead: PathFollower = leader().follower()
	var ahead: float = lead.remaining_distance()
	for i: int in members.size():
		var follower: PathFollower = members[i].follower()
		if not follower.is_moving():
			continue
		moving = true
		if follower.move_direction != Vector2.ZERO:
			_face(members[i], follower.move_direction, delta)
			_look_angles[i] = follower.move_direction.angle()     # 走到之後繼續看這個方向
		if i > 0:
			var ratio: float = follower.remaining_distance() / maxf(ahead, 1.0) if ahead != INF and follower.remaining_distance() != INF else 1.2
			follower.speed = data.patrol_speed * clampf(ratio, 0.7, 1.5)
	if moving:
		return
	_going = false
	_wait_time = PATROL_WAIT
	_look_time = 0.0
	if _points.size() == 1:
		return
	if data.patrol_mode == 1:
		_next = (_next + 1) % _points.size()
		return
	if _next + _direction < 0 or _next + _direction >= _points.size():
		_direction = -_direction                                  # 來回：到底就往回走
	_next += _direction


## 沒有巡邏點：每一隻站在自己的位置張望（離開了就走回去）
func _stand(delta: float) -> void:
	for i: int in members.size():
		var follower: PathFollower = members[i].follower()
		if follower.is_moving():
			_face(members[i], follower.move_direction, delta)
		elif members[i].global_position.distance_to(_homes[i]) > 8.0:
			follower.speed = data.patrol_speed
			follower.go_to(_homes[i])
	_look_around(delta)


## 站著的左右張望，每一隻的節奏錯開
func _look_around(delta: float) -> void:
	_look_time += delta
	for i: int in members.size():
		if not members[i].follower().is_moving():
			_face(members[i], Vector2.from_angle(_look_angles[i] + deg_to_rad(LOOK_ANGLE) * sin(_look_time * 0.8 + i * 1.9)), delta)


## 慢慢轉過去
func _face(unit: Unit, direction: Vector2, delta: float) -> void:
	if direction != Vector2.ZERO:
		unit.facing = Vector2.from_angle(rotate_toward(unit.facing.angle(), direction.angle(), deg_to_rad(300.0) * delta))


# ---- 戰鬥 ----

func enter_battle() -> void:
	_in_battle = true
	_show_cones(false)
	for unit: Unit in members:
		unit.follower().stop()
		unit.alert_mark = "!"


## 全滅了：掉物資（純戰棋沒有探索，直接給）
func defeated() -> void:
	if data.drop_supplies > 0:
		battle.note("%s掉了 %d 份營地物資" % [data.squad_name, data.drop_supplies])
		if data.instant:
			_party().take_supply(data.drop_supplies)
		else:
			var supply: TacticsSupply = TacticsSupply.new()
			supply.amount = data.drop_supplies
			get_parent().add_child(supply)
			supply.global_position = leader().global_position
	remove_from_group("enemy_squads")
	queue_free()
