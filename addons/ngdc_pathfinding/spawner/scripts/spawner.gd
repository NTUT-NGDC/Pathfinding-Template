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
## 怪走到基地會發出 reached_goal，然後消失。

## 第幾波開始了（從 1 開始數）
signal wave_started(wave_number: int)
## 生出一隻怪
signal spawned(enemy: Node2D)
## 有怪走到目標了
signal reached_goal(enemy: Node2D)
## 所有波次都出完、而且場上的怪都沒了
signal all_cleared()

const DEFAULT_ENEMY: PackedScene = preload("res://addons/ngdc_pathfinding/spawner/walker.tscn")

@export_group("生怪")
## 怪要走去哪（基地）
@export var target: Node2D
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
	await _wait(start_delay)
	for i: int in waves.size():
		var wave: Wave = waves[i]
		if wave == null:
			continue
		wave_number = i + 1
		wave_started.emit(wave_number)
		for n: int in wave.count:
			spawn(wave)
			await _wait(wave.interval)
		if i < waves.size() - 1:
			await _wait(time_between_waves)
	_done_spawning = true
	_check_cleared()


## 生一隻怪，叫它走向目標
func spawn(wave: Wave = null) -> Node2D:
	var scene: PackedScene = wave.enemy_scene if wave != null and wave.enemy_scene != null else DEFAULT_ENEMY
	var enemy: Node2D = scene.instantiate()
	enemy.global_position = global_position
	if wave != null and wave.speed > 0.0:
		enemy.set("speed", wave.speed)
	if wave != null and wave.health > 0.0:
		enemy.set("max_health", wave.health)
	get_parent().add_child(enemy)                                 # 放在生怪器旁邊，不會跟著生怪器移動
	alive += 1
	enemy.tree_exited.connect(_on_enemy_gone)
	var follower: PathFollower = _follower_of(enemy)
	if follower != null and target != null:
		follower.arrived.connect(_on_enemy_arrived.bind(enemy))
		follower.go_to(target.global_position)
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


func _check_cleared() -> void:
	if not _done_spawning or alive > 0 or not is_inside_tree():
		return
	all_cleared.emit()
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
