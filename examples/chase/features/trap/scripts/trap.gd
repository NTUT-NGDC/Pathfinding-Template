@tool
class_name Trap
extends Node2D
## 捕獸夾：玩家踩到會被夾住幾秒不能動，還會發出聲音（追逐 AI 會跑過來）。
## 追逐 AI 尋路時會把它當成很貴的格子，能繞就繞開（按 F1 看路徑就看得到 AI 繞路）。
##
## 用法：把 trap.tscn 拖進關卡（遊戲開始時會自動對齊格子）。
## 想讓追逐 AI 追丟人時自己放：在追逐 AI 底下加 trap_dropper.tscn。
##
## 這是尋路積木的「會變的障礙物」：加進 group「path_obstacles」，有 blocks_path、path_cost，尋路地圖會自動登記。

## 夾到玩家了
signal triggered(player: Player)
## 尋路地圖要知道成本變了
signal obstacle_changed()

## 夾住幾秒
@export_range(0.0, 10.0, 0.5, "suffix:秒") var hold_time: float = 2.0
## 夾到時聲音傳多遠（像素）。0＝不出聲
@export_range(0, 800, 10, "suffix:px") var sound_radius: float = 300.0
## 打勾：追逐 AI 尋路時會繞開它
@export var ai_avoids: bool = true:
	set(value):
		ai_avoids = value
		obstacle_changed.emit()
## 打勾：夾完就消失。不打勾：玩家離開之後又會張開
@export var one_shot: bool = true
## 夾子的顏色
@export var color: Color = Color("9aa0a8"):
	set(value):
		color = value
		queue_redraw()

## 追逐 AI 繞開時，走一格等於走幾格
const AVOID_COST: float = 8.0
const DARK: Color = Color("3a3e44")

## 夾住了（還沒鬆開）
var is_closed: bool = false
## 給尋路地圖看：不擋路（只是很貴）
var blocks_path: bool:
	get:
		return false
## 給尋路地圖看：要繞開的話很貴
var path_cost: float:
	get:
		return AVOID_COST if ai_avoids and not is_closed else 1.0

var _victim: Player
var _hold_timer: float = 0.0

@onready var _area: Area2D = $Area2D


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("path_obstacles")
		add_to_group("traps")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_area.body_entered.connect(_on_body_entered)
	_register.call_deferred()


## 遊戲中途才放下的夾子（追逐 AI 放的），尋路地圖已經建好了，要自己登記
func _register() -> void:
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	if grid != null and grid.obstacle_at(grid.cell_of(global_position)) != self:
		grid.register_obstacle(self)


## 把夾子拿掉（也會從尋路地圖取消登記）
func remove() -> void:
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	if grid != null:
		grid.unregister_obstacle(self)
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	var player: Player = body as Player
	if player == null or is_closed:
		return
	is_closed = true
	_victim = player
	_hold_timer = hold_time
	player.stun(hold_time)
	if sound_radius > 0.0:
		SoundBus.emit_sound(global_position, sound_radius)
	triggered.emit(player)
	obstacle_changed.emit()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_closed:
		return
	_hold_timer -= delta
	if _hold_timer > 0.0:
		return
	if one_shot:
		remove()
	elif not _area.overlaps_body(_victim):
		is_closed = false                                         # 玩家走開了：重新張開
		_victim = null
		obstacle_changed.emit()
		queue_redraw()


func _draw() -> void:
	# 夾子：一個圓盤＋兩排鋸齒；夾住時鋸齒合起來
	draw_circle(Vector2.ZERO, 11.0, DARK)
	draw_circle(Vector2.ZERO, 9.0, color.darkened(0.3))
	var gap: float = 1.0 if is_closed else 5.0
	for side: float in [-1.0, 1.0]:
		var y: float = side * gap
		draw_line(Vector2(-9, y), Vector2(9, y), color, 2.0)
		for i: int in 4:
			var x: float = -7.5 + i * 5.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 2.0, y), Vector2(x + 2.0, y), Vector2(x, y - side * 4.0)]), color)
	draw_circle(Vector2.ZERO, 2.0, DARK)
