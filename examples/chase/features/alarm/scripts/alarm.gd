@tool
class_name Alarm
extends Node2D
## 警報（壓力板）：玩家踩到會發出很大的聲音、閃紅光，範圍內的追逐 AI 都會跑過來查看。
##
## 用法：把 alarm.tscn 拖進關卡，放在玩家會經過的地方（例如寶物前面的走廊）。
## 想陰險一點：「看得到」取消勾選，玩家要踩到才知道那裡有警報。

## 響了
signal rang(player: Player)

## 聲音傳多遠（像素）
@export_range(0, 1500, 10, "suffix:px") var sound_radius: float = 700.0
## 打勾：只響一次。不打勾：冷卻時間過了又會響
@export var one_shot: bool = false
## 響完幾秒之後才會再響
@export_range(0.0, 30.0, 0.5, "suffix:秒") var cooldown: float = 5.0
## 打勾：玩家看得到壓力板。不打勾：隱形，踩到才會閃
@export var visible_to_player: bool = true:
	set(value):
		visible_to_player = value
		queue_redraw()

const PLATE_COLOR: Color = Color("6b5a4a")
const DARK: Color = Color("3a3028")
const FLASH_COLOR: Color = Color(1.0, 0.2, 0.2)
## 閃紅光幾秒
const FLASH_TIME: float = 0.8

## 已經響過（只響一次的那種）
var has_rung: bool = false
var _cooldown_timer: float = 0.0
var _flash: float = 0.0

@onready var _area: Area2D = $Area2D


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("alarms")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var player: Player = body as Player
	if player != null:
		ring(player)


## 響一次（冷卻中、只響一次而且響過了就不響）。回傳有沒有響
func ring(player: Player = null) -> bool:
	if _cooldown_timer > 0.0 or (one_shot and has_rung):
		return false
	has_rung = true
	_cooldown_timer = cooldown
	_flash = FLASH_TIME
	SoundBus.emit_sound(global_position, sound_radius)
	rang.emit(player)
	return true


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var flashing: bool = _flash > 0.0
	if flashing:
		# 紅光：一圈一圈往外擴散
		var t: float = 1.0 - _flash / FLASH_TIME
		draw_circle(Vector2.ZERO, 14.0 + t * 40.0, Color(FLASH_COLOR, 0.35 * (1.0 - t)))
	var hidden: bool = not visible_to_player and not Engine.is_editor_hint()
	if hidden and not flashing:
		return
	var alpha: float = 0.4 if not visible_to_player else 1.0     # 編輯器裡隱形的畫半透明
	draw_rect(Rect2(-12, -12, 24, 24), Color(DARK, alpha))
	draw_rect(Rect2(-10, -10, 20, 20), Color(FLASH_COLOR if flashing else PLATE_COLOR, alpha))
	draw_circle(Vector2.ZERO, 3.0, Color(DARK, alpha))
