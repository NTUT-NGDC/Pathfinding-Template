@tool
class_name Exit
extends StaticBody2D
## 出口：一定要撿的東西（Pickup 的 required）都撿到才會打開；玩家走進打開的出口就贏了。
## 關著的時候跟牆一樣擋路、擋視線。
##
## 用法：把 exit.tscn 拖進關卡，放在外牆的缺口上。
## 關卡裡沒有任何一定要撿的東西的話，一開始就是開的。

## 出口打開了
signal opened()
## 一定要撿的東西的進度變了（撿了幾個、總共幾個）
signal progress_changed(picked: int, total: int)

## 門板的方向：牆是橫的就選「橫」，牆是直的就選「直」
@export_enum("橫", "直") var orientation: int = 0:
	set(value):
		orientation = value
		queue_redraw()

const CLOSED_LAYERS: int = 1 | 2
const CLOSED_COLOR: Color = Color("6a6f78")
const OPEN_COLOR: Color = Color("3fd17a")

var is_open: bool = false
var _required: Array[Pickup] = []

@onready var _goal: Area2D = $Goal


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("exits")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_goal.body_entered.connect(_on_goal_body_entered)
	_collect.call_deferred()                                      # 等關卡裡的東西都準備好再數


func _collect() -> void:
	for node: Node in get_tree().get_nodes_in_group("pickups"):
		var pickup: Pickup = node as Pickup
		if pickup != null and pickup.required:
			_required.append(pickup)
			pickup.picked.connect(func(_p: Pickup) -> void: _check())
	_check()


## 撿了幾個
func picked_count() -> int:
	return _required.filter(func(p: Pickup) -> bool: return p.is_picked).size()


func total_count() -> int:
	return _required.size()


func _check() -> void:
	progress_changed.emit(picked_count(), total_count())
	if is_open or picked_count() < total_count():
		return
	is_open = true
	collision_layer = 0                                           # 打開：不擋路、不擋視線
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
		draw_line(Vector2(-5, -5), Vector2(5, 5), color.darkened(0.5), 2.0)
		draw_line(Vector2(5, -5), Vector2(-5, 5), color.darkened(0.5), 2.0)
