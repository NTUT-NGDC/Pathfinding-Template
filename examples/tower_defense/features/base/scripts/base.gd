@tool
class_name Base
extends Node2D
## 基地：怪走到這裡就扣一滴血。可以放好幾個，扣血、輸的規則看關卡裡的基地規則（BaseGroup）。
## 關卡裡沒有 BaseGroup 的話：自己扣血，扣光就輸。

## 被打到了（剩幾滴血）
signal hit(health: int)
## 被打爆了（「全部被打爆才輸」的規則才會發生）
signal destroyed()

## 幾滴血（基地規則選「共用一條血」時看 BaseGroup 的血量）
@export_range(1, 100, 1) var max_health: int = 10
## 顏色
@export var color: Color = Color("4ab86a"):
	set(value):
		color = value
		queue_redraw()

var health: int = 0
## 被打爆了
var is_destroyed: bool = false


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("bases")


func _ready() -> void:
	health = max_health


## 怪走到基地了（生怪器的 reached_goal 會連過來；有 BaseGroup 的話交給它決定）
func take_hit(_enemy: Node2D = null) -> void:
	var group: BaseGroup = get_tree().get_first_node_in_group("base_group") as BaseGroup
	if group != null:
		group.on_base_hit(self)
		return
	if health <= 0:
		return
	set_health(health - 1)
	if health <= 0:
		GameFlow.lose("基地被攻破了！")


## 改血量（畫面上的血條跟著變）
func set_health(value: int) -> void:
	health = value
	hit.emit(health)
	queue_redraw()


## 打爆：從基地清單拿掉，怪會改去別的基地
func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("bases")
	destroyed.emit()
	queue_free()


func _draw() -> void:
	draw_rect(Rect2(-16, -16, 32, 32), color.darkened(0.5))
	draw_rect(Rect2(-13, -13, 26, 26), color)
	draw_rect(Rect2(-5, -2, 10, 15), color.darkened(0.5))                # 門
	var ratio: float = clampf(float(health) / max_health, 0.0, 1.0) if max_health > 0 and not Engine.is_editor_hint() else 1.0
	draw_rect(Rect2(-16, -24, 32, 4), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-16, -24, 32 * ratio, 4), Color("4ab86a").lerp(Color("d94a4a"), 1.0 - ratio))
