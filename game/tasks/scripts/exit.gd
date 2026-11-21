@tool
class_name Exit
extends StaticBody2D
## 出口：要求的任務都做完才會打開；玩家走進打開的出口就逃出去了（贏）。
## 關著的時候跟牆一樣擋路、擋視線。
##
## 用法：把 exit.tscn 拖進關卡，放在外牆的缺口上。
##   ・「要完成全部任務」打勾（預設）：關卡裡所有修理點、鑰匙都做完才開
##   ・不打勾：只看「要完成的任務」清單，把任務節點拖進清單裡
##   ・關卡裡沒有任何任務的話，一開始就是開的（記得放任務！）

## 出口打開了
signal opened()

@export_group("出口")
## 打勾：關卡裡全部的任務都要做完
@export var require_all_tasks: bool = true
## 不打勾時：只要完成這些任務（把修理點、鑰匙節點拖進來）
@export var required_tasks: Array[Task] = []
## 門板的方向：牆是橫的就選「橫」，牆是直的就選「直」
@export_enum("橫", "直") var orientation: int = 0:
	set(value):
		orientation = value
		queue_redraw()
## 打開時發出的聲音傳多遠（像素）。0＝不發出聲音
@export_range(0, 2000, 10, "suffix:px") var open_sound_radius: float = 0.0

const CLOSED_LAYERS: int = 1 | 2
const CLOSED_COLOR: Color = Color("6a6f78")
const OPEN_COLOR: Color = Color("3fd17a")

var is_open: bool = false
var _tasks: Array[Task] = []

@onready var _goal: Area2D = $Goal


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_goal.body_entered.connect(_on_goal_body_entered)
	_collect_tasks.call_deferred()                                # 等關卡裡的東西都準備好再數任務


func _collect_tasks() -> void:
	_tasks.clear()
	if require_all_tasks:
		for node: Node in get_tree().get_nodes_in_group("tasks"):
			_tasks.append(node as Task)
	else:
		for task: Task in required_tasks:
			if task != null:
				_tasks.append(task)
	for task: Task in _tasks:
		task.completed.connect(func(_t: Task) -> void: _check())
	_check()


## 還差幾個任務
func remaining() -> int:
	var count: int = 0
	for task: Task in _tasks:
		if not task.is_done:
			count += 1
	return count


func _check() -> void:
	if is_open or remaining() > 0:
		return
	is_open = true
	collision_layer = 0                                           # 打開：不擋路、不擋視線
	if open_sound_radius > 0.0:
		SoundBus.emit_sound(global_position, open_sound_radius)
	queue_redraw()
	opened.emit()


func _on_goal_body_entered(body: Node2D) -> void:
	if is_open and body is Player:
		(body as Player).escape()


func _draw() -> void:
	var color: Color = OPEN_COLOR if is_open else CLOSED_COLOR
	var panel: Rect2 = Rect2(-16, -8, 32, 16) if orientation == 0 else Rect2(-8, -16, 16, 32)
	draw_rect(panel, color)
	draw_rect(panel, color.darkened(0.5), false, 2.0)
	if is_open:
		draw_rect(panel.grow(3), Color(OPEN_COLOR, 0.35), false, 3.0)
	else:
		# 鎖著：畫一個 X
		draw_line(Vector2(-5, -5), Vector2(5, 5), color.darkened(0.5), 2.0)
		draw_line(Vector2(5, -5), Vector2(-5, 5), color.darkened(0.5), 2.0)
