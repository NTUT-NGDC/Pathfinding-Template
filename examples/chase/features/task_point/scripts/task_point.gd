@tool
class_name TaskPoint
extends Node2D
## 任務點：玩家按住 E 一段時間就完成（發電機、電腦、保險箱、拉桿……改名字和秒數就好）。
## 做的時候每隔一段時間發出聲音，追逐 AI 可能會聽到。中途離開會保留進度。
##
## 用法：把 task_point.tscn 拖進關卡，在檢查器改名字、要按住幾秒、聲音多大、顏色。
## 「算進出口條件」打勾的話，出口要等它完成才會打開（看出口的「開門條件」）。
##
## 它是一個「目標」：在 objectives 群組、有 required／is_done／category、完成時發出 completed。

## 完成了
signal completed(objective: Node)

## 叫什麼（畫面左上角會顯示「發電機 0/1」，玩家頭上會顯示「E 修理發電機」）
@export var task_name: String = "發電機":
	set(value):
		task_name = value
		_update_prompt()
## 玩家頭上提示的動詞，例如「修理」「駭入」「打開」「拉下」
@export var action: String = "修理":
	set(value):
		action = value
		_update_prompt()
## 打勾：算進出口的開門條件
@export var required: bool = true
## 要按住幾秒。0＝按一下就完成
@export_range(0.0, 30.0, 0.5, "suffix:秒") var hold_time: float = 6.0
## 做的時候聲音傳多遠（像素）。0＝不會發出聲音
@export_range(0, 800, 10, "suffix:px") var sound_radius: float = 300.0
## 每隔幾秒發出一次聲音
@export_range(0.2, 5.0, 0.1, "suffix:秒") var sound_interval: float = 1.0
## 機器的顏色
@export var color: Color = Color("5d646e"):
	set(value):
		color = value
		queue_redraw()

const DARK: Color = Color("2c3036")
const SPARK: Color = Color("ffcc33")
const DONE_COLOR: Color = Color("4ab86a")

var is_done: bool = false
## 分類（給出口和畫面左上角的計數用）＝名字
var category: String:
	get:
		return task_name
## 做了幾秒
var progress: float = 0.0
var _sound_timer: float = 0.0

@onready var _interact: Interactable = $Interactable


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("objectives")


func _ready() -> void:
	_update_prompt()
	if Engine.is_editor_hint():
		return
	_interact.held.connect(_work)
	_interact.interacted.connect(func(player: Player) -> void: _work(player, 0.0))


func _work(_player: Player, delta: float) -> void:
	if is_done:
		return
	progress = minf(progress + delta, hold_time)
	_sound_timer -= delta
	if _sound_timer <= 0.0 and sound_radius > 0.0:
		SoundBus.emit_sound(global_position, sound_radius)
		_sound_timer = sound_interval
	if progress >= hold_time:
		is_done = true
		_interact.enabled = false
		completed.emit(self)
	queue_redraw()


func _update_prompt() -> void:
	if is_node_ready():
		_interact.prompt = action + task_name


func _draw() -> void:
	# 機器：方塊＋齒輪
	draw_rect(Rect2(-14, -12, 28, 24), DARK)
	draw_rect(Rect2(-12, -10, 24, 20), DONE_COLOR if is_done else color)
	draw_circle(Vector2.ZERO, 6.0, DARK)
	for i: int in 6:
		draw_line(Vector2.ZERO, Vector2.from_angle(TAU * i / 6.0) * 8.0, DARK, 3.0)
	draw_circle(Vector2.ZERO, 2.5, Color.WHITE if is_done else SPARK)
	# 進度條（開始做了才顯示）
	if progress > 0.0 and not is_done and hold_time > 0.0:
		draw_rect(Rect2(-16, -22, 32, 5), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-16, -22, 32 * progress / hold_time, 5), SPARK)
