@tool
class_name Spawner
extends Node2D
## 生怪器：照「波次表」一波一波出怪，生出來的怪自動繞路走向目標（基地）。
## 路被擋住、地圖變了，怪會即時改路。
##
## 用法：把 spawner.tscn 拖到出怪的地方，在檢查器：
##   ・Target：把基地（任何 Node2D）拖進來
##   ・Waves：按「＋」加一波，設定出幾隻、間隔、速度、血量（敵人場景空著＝預設的 Walker）
##   ・走到基地就輸／全部打完就贏：打勾就會呼叫起手包的 GameFlow
##   ・波次也可以存成檔案（WaveTable），拖進 Wave Table；有放就用它，不看 Waves
##   ・一波混好幾種怪：那幾列的 With Previous 打勾（跟上一列同時出）
## 怪走到基地會發出 reached_goal，然後消失。
##
## 好幾個出怪口，三種做法：
##   ・輪流：把別的出怪口（任何 Node2D，例如 Marker2D）拖進 More Spawn Points，怪輪流從每個出來
##   ・每一波指定：在波次的 Spawn Point 填第幾個出怪口（1＝生怪器自己，2 以後＝More Spawn Points；0＝輪流）
##   ・各自一份波次表：放好幾個生怪器。全部生怪器都打完才算贏
## 好幾個基地：把別的基地拖進 More Targets，每隻怪出生時走向「路最短」的那個（會飛的怪看直線距離）。

## 第幾波開始了（從 1 開始數）
signal wave_started(wave_number: int)
## 生出一隻怪
signal spawned(enemy: Node2D)
## 有怪走到目標了
signal reached_goal(enemy: Node2D)
## 所有波次都出完、而且場上的怪都沒了
signal all_cleared()
## 一波裡的其中一列出完了（自己用）
signal _row_done()

const DEFAULT_ENEMY: PackedScene = preload("res://addons/ngdc_pathfinding/spawner/walker.tscn")

@export_group("生怪")
## 怪要走去哪（基地）
@export var target: Node2D
## 更多基地：怪會走向路最短的那個
@export var more_targets: Array[Node2D] = []
## 更多出怪口（生怪器自己是第 1 個）
@export var more_spawn_points: Array[Node2D] = []
## 波次檔（有放就用它的波次、等待時間，不看下面的 Waves、Time Between Waves、Start Delay）
@export var wave_table: WaveTable
## 從第幾波開始（測試後面的波次用）
@export_range(1, 100, 1) var start_wave: int = 1
## 波次表：一波出什麼、幾隻、間隔多久
@export var waves: Array[Wave] = []
## 每一波之間休息幾秒
@export_range(0.0, 60.0, 0.5, "suffix:秒") var time_between_waves: float = 3.0
## 遊戲開始就出怪（關掉的話要自己呼叫 start()）
@export var autostart: bool = true
## 第一波之前等幾秒
@export_range(0.0, 60.0, 0.5, "suffix:秒") var start_delay: float = 2.0

@export_group("勝負")
## 有怪走到目標就輸（呼叫起手包的 GameFlow.lose()）
@export var lose_when_reached: bool = true
## 所有波次打完就贏（呼叫起手包的 GameFlow.win()）
@export var win_when_cleared: bool = true

## 現在是第幾波（0＝還沒開始）
var wave_number: int = 0
## 場上還活著的怪
var alive: int = 0

var _spawning: bool = false
var _done_spawning: bool = false
## 輪流出怪：下一隻從第幾個出怪口
var _next_point: int = 0


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("spawners")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if autostart:
		start()


## 開始出怪
func start() -> void:
	if _spawning:
		return
	_spawning = true
	_run.call_deferred()


## 等幾秒（用自己底下的 Timer：生怪器被刪掉時，計時也跟著停，不會繼續出怪）
func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var timer: Timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()


func _run() -> void:
	await _wait(wave_table.start_delay if wave_table != null else start_delay)
	var groups: Array[Array] = wave_groups()
	for i: int in range(start_wave - 1, groups.size()):
		wave_number = i + 1
		wave_started.emit(wave_number)
		await _spawn_group(groups[i])
		if i < groups.size() - 1:
			await _wait(wave_table.time_between_waves if wave_table != null else time_between_waves)
	_done_spawning = true
	_check_cleared()


## 一波一波分好的波次（Wave Table 有放就用它的）
func wave_groups() -> Array[Array]:
	return wave_table.groups() if wave_table != null else WaveTable.group(waves)


## 出一波：每一列各自照自己的間隔同時出，全部出完才算出完
func _spawn_group(rows: Array) -> void:
	var left: Array[int] = [rows.size()]
	for row: Wave in rows:
		_spawn_row(row, left)
	while left[0] > 0:
		await _row_done


func _spawn_row(row: Wave, left: Array[int]) -> void:
	for n: int in row.count:
		spawn(row)
		await _wait(row.interval)
	left[0] -= 1
	_row_done.emit()


## 生一隻怪，叫它走向目標
func spawn(wave: Wave = null) -> Node2D:
	var scene: PackedScene = wave.enemy_scene if wave != null and wave.enemy_scene != null else DEFAULT_ENEMY
	var enemy: Node2D = scene.instantiate()
	enemy.global_position = global_position
	if wave != null and wave.speed > 0.0:
		enemy.set("speed", wave.speed)
	if wave != null and wave.health > 0.0:
		enemy.set("max_health", wave.health)
	return adopt(enemy, spawn_position(wave.spawn_point if wave != null else 0))


## 所有出怪口（生怪器自己＋More Spawn Points）
func spawn_points() -> Array[Node2D]:
	var points: Array[Node2D] = [self]
	for point: Variant in more_spawn_points:                      # Variant：被刪掉的節點不能放進有型別的變數
		if is_instance_valid(point):
			points.append(point)
	return points


## 這一隻從哪裡出：which＝0 輪流，1 以後＝第幾個出怪口
func spawn_position(which: int = 0) -> Vector2:
	var points: Array[Node2D] = spawn_points()
	if which >= 1 and which <= points.size():
		return points[which - 1].global_position
	var point: Node2D = points[_next_point % points.size()]
	_next_point += 1
	return point.global_position


## 所有還在的基地（Target＋More Targets）
func targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Variant in [target] + more_targets:                 # Variant：被打爆刪掉的基地不能放進有型別的變數
		if is_instance_valid(node) and (node as Node2D).is_inside_tree() and not (node as Node2D).is_queued_for_deletion():
			result.append(node)
	return result


## 從 from 出發，走哪個基地的路成本最低（會飛的怪 use_pathfinding 關掉 → 看直線距離）
func pick_target(from: Vector2, follower: PathFollower = null) -> Node2D:
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	var best: Node2D = null
	var best_length: float = INF
	for node: Node2D in targets():
		var length: float = from.distance_to(node.global_position)
		if grid != null and (follower == null or follower.use_pathfinding):
			var path: PackedVector2Array = grid.find_path(from, node.global_position)
			if path.is_empty() or grid.cell_of(path[path.size() - 1]) != grid.cell_of(node.global_position):
				continue                                          # 走不到這個基地
			length = grid.path_cost(path)                         # 沼澤、要拆的牆也算進去
		if length < best_length:
			best = node
			best_length = length
	return best


## 基地少了一個（被打爆）：還在走的怪改去別的基地
func retarget_all() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy.get_meta("spawner", null) != self:
			continue
		var old: Variant = enemy.get_meta("target", null)
		if old is Node2D and targets().has(old):
			continue
		var follower: PathFollower = _follower_of(enemy)
		var goal: Node2D = pick_target(enemy.global_position, follower)
		enemy.set_meta("target", goal)
		if follower != null and goal != null:
			follower.go_to(goal.global_position)


## 把一隻怪交給生怪器管：放進場景、走向目標、算進「場上還有幾隻」。
## 不是從出怪口出來的怪（例如分裂出來的小怪）也用這個，才會被算進勝負。
## 怪身上會記著是哪個生怪器（get_meta("spawner")）
func adopt(enemy: Node2D, at: Vector2) -> Node2D:
	enemy.set_meta("spawner", self)
	get_parent().add_child(enemy)                                 # 放在生怪器旁邊，不會跟著生怪器移動
	enemy.global_position = at
	alive += 1
	enemy.tree_exited.connect(_on_enemy_gone)
	var follower: PathFollower = _follower_of(enemy)
	var goal: Node2D = pick_target(at, follower)
	enemy.set_meta("target", goal)                                # 走向哪個基地（reached_goal 時看這個）
	if follower != null and goal != null:
		follower.arrived.connect(_on_enemy_arrived.bind(enemy))
		follower.go_to(goal.global_position)
	spawned.emit(enemy)
	return enemy


func _on_enemy_arrived(enemy: Node2D) -> void:
	reached_goal.emit(enemy)
	enemy.queue_free()
	if lose_when_reached:
		var flow: Node = get_node_or_null("/root/GameFlow")
		if flow != null:
			flow.call("lose", "敵人衝進基地了！")


func _on_enemy_gone() -> void:
	alive -= 1
	_check_cleared()


## 這個生怪器打完了沒（波次都出完、場上沒有它的怪）
func is_cleared() -> bool:
	return _done_spawning and alive <= 0


func _check_cleared() -> void:
	if not is_cleared() or not is_inside_tree():
		return
	all_cleared.emit()
	for other: Node in get_tree().get_nodes_in_group("spawners"):
		if other != self and (other as Spawner).win_when_cleared and not (other as Spawner).is_cleared():
			return                                                # 還有別的生怪器沒打完：還不算贏
	if win_when_cleared:
		var flow: Node = get_node_or_null("/root/GameFlow")
		if flow != null and not bool(flow.call("is_finished")):
			flow.call("win", "守住了！")


func _follower_of(enemy: Node2D) -> PathFollower:
	for child: Node in enemy.get_children():
		if child is PathFollower:
			return child
	return null


func _draw() -> void:
	# 出怪口：一個空心的方框（遊戲中也看得到，表示怪從這裡出來）
	draw_rect(Rect2(-14, -14, 28, 28), Color(0.9, 0.3, 0.3, 0.8), false, 3.0)
	draw_line(Vector2(-8, 0), Vector2(8, 0), Color(0.9, 0.3, 0.3, 0.8), 3.0)
	draw_line(Vector2(0, -8), Vector2(0, 8), Color(0.9, 0.3, 0.3, 0.8), 3.0)
	if Engine.is_editor_hint() and target != null:
		draw_line(Vector2.ZERO, to_local(target.global_position), Color(0.9, 0.3, 0.3, 0.5), 2.0)
	if Engine.is_editor_hint():
		for point: Variant in more_spawn_points:
			if is_instance_valid(point):
				draw_line(Vector2.ZERO, to_local((point as Node2D).global_position), Color(0.9, 0.3, 0.3, 0.3), 1.0)
