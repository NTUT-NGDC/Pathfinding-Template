class_name ClickMover
extends Node2D
## 點擊移動：滑鼠點選角色（可以拖曳框選好幾個），再點地圖，選到的角色就繞路走過去。
## （RTS、Pikmin、經營遊戲的操作）
##
## 用法：把 click_mover.tscn 拖進場景，把要能被點的角色加進 group（預設「units」）。
## 每個角色底下要有一個 PathFollower（走路用）。場景裡要有尋路地圖 PathGrid。
##   左鍵點角色：選它　左鍵拖曳：框選　左鍵點地圖：選到的走過去　右鍵：取消選取

## 選到的角色變了
signal selection_changed(units: Array[Node2D])
## 下了移動指令（目的地）
signal commanded(target: Vector2)

## 哪個 group 的角色可以被點
@export var unit_group: String = "units"
## 可以框選好幾個
@export var allow_multi_select: bool = true
## 離角色多近算點到它（像素）
@export_range(4, 64, 1, "suffix:px") var pick_radius: float = 18.0
## 好幾個角色一起走時，彼此在目的地散開多遠（像素），避免疊在一起
@export_range(0, 64, 1, "suffix:px") var spread: float = 20.0
## 選到的角色腳下圈圈的顏色
@export var select_color: Color = Color(0.4, 1.0, 0.5, 0.9)

## 現在選到的角色
var selected: Array[Node2D] = []

var _drag_start: Vector2
var _dragging: bool = false


func _ready() -> void:
	z_index = 4


func _unhandled_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_drag_start = get_global_mouse_position()
				_dragging = true
			elif _dragging:
				_dragging = false
				_on_left_release(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			select([])
	elif event is InputEventMouseMotion and _dragging:
		queue_redraw()


func _on_left_release(at: Vector2) -> void:
	if allow_multi_select and _drag_start.distance_to(at) > 8.0:
		select(units_in_rect(Rect2(_drag_start, at - _drag_start).abs()))   # 框選
		return
	var unit: Node2D = unit_at(at)
	if unit != null:
		select([unit])                                            # 點到角色：選它
	elif not selected.is_empty():
		command(at)                                               # 點到地圖：走過去


## 選這些角色
func select(units: Array[Node2D]) -> void:
	selected = units.duplicate()
	if not allow_multi_select and selected.size() > 1:
		selected.resize(1)
	selection_changed.emit(selected)
	queue_redraw()


## 叫選到的角色走到 target（全局座標），好幾個的話在目的地附近排開
func command(target: Vector2) -> void:
	for i: int in selected.size():
		var unit: Node2D = selected[i]
		if not is_instance_valid(unit):
			continue
		var follower: PathFollower = _follower_of(unit)
		if follower != null:
			follower.go_to(target + _offset(i, selected.size()))
	commanded.emit(target)


## 滑鼠位置上的角色（沒有就是 null）
func unit_at(at: Vector2) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group(unit_group):
		var unit: Node2D = node as Node2D
		if unit != null and unit.global_position.distance_to(at) <= pick_radius:
			return unit
	return null


## 框框裡的角色
func units_in_rect(rect: Rect2) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group(unit_group):
		var unit: Node2D = node as Node2D
		if unit != null and rect.has_point(unit.global_position):
			result.append(unit)
	return result


## 第 i 個角色在目的地的位置偏移：排成一個小圓
func _offset(i: int, count: int) -> Vector2:
	if count <= 1 or i == 0:
		return Vector2.ZERO
	return Vector2.from_angle(TAU * i / (count - 1)) * spread


func _follower_of(unit: Node2D) -> PathFollower:
	for child: Node in unit.get_children():
		if child is PathFollower:
			return child
	return null


func _process(_delta: float) -> void:
	if not selected.is_empty() or _dragging:
		queue_redraw()


func _draw() -> void:
	selected = selected.filter(func(unit: Node2D) -> bool: return is_instance_valid(unit))
	for unit: Node2D in selected:
		draw_arc(to_local(unit.global_position), pick_radius, 0.0, TAU, 24, select_color, 2.0)
	if _dragging and allow_multi_select:
		var rect: Rect2 = Rect2(to_local(_drag_start), get_global_mouse_position() - _drag_start).abs()
		draw_rect(rect, Color(select_color, 0.15))
		draw_rect(rect, select_color, false, 1.0)
