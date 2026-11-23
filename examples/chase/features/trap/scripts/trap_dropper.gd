class_name TrapDropper
extends Node
## 放陷阱的人：放在追逐 AI 底下，追逐 AI 進入某個狀態時（預設「搜尋」＝追丟了），在腳下放一個捕獸夾。
## 最多放幾個可以調，超過的話最舊的會消失。
##
## 用法：把 trap_dropper.tscn 拖到追逐 AI（ChaseAI）底下，當它的子節點。
## 想放別的東西：把「要放的東西」換成別的場景（例如警報壓力板）。

## 放下東西了
signal dropped(trap: Node2D)

## 要放的東西
@export var trap_scene: PackedScene = preload("res://examples/chase/features/trap/trap.tscn")
## 追逐 AI 進入哪個狀態時放
@export_enum("巡邏", "查看", "懷疑", "追擊", "搜尋") var drop_on: int = ChaseAI.State.SEARCH
## 最多同時有幾個（超過的話最舊的消失）
@export_range(1, 20) var max_traps: int = 3
## 打勾：放下的夾子踩過就消失。不打勾：玩家走開之後又會張開（跟關卡裡手動擺的夾子分開設定）
@export var dropped_one_shot: bool = true

## 放下的東西（最舊的在前面）
var traps: Array[Node2D] = []

var _ai: ChaseAI


func _ready() -> void:
	_ai = get_parent() as ChaseAI
	if _ai == null:
		push_warning("TrapDropper 要放在追逐 AI（ChaseAI）底下。")
		return
	_ai.state_changed.connect(_on_state_changed)


func _on_state_changed(state: ChaseAI.State) -> void:
	if state == drop_on:
		drop()


## 在追逐 AI 腳下放一個（那一格已經有門、陷阱就不放）
func drop() -> Node2D:
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	if grid == null or grid.obstacle_at(grid.cell_of(_ai.global_position)) != null:
		return null
	# 拿掉已經消失的（被踩掉的夾子已經刪掉了；不能用 filter＋型別 lambda，刪掉的東西傳進去會出錯）
	var alive: Array[Node2D] = []
	for item: Variant in traps:
		if is_instance_valid(item) and not (item as Node2D).is_queued_for_deletion():
			alive.append(item)
	traps = alive
	while traps.size() >= max_traps:
		var oldest: Node2D = traps.pop_front()
		if oldest.has_method("remove"):
			oldest.call("remove")
		else:
			oldest.queue_free()
	var trap: Node2D = trap_scene.instantiate()
	if "one_shot" in trap:
		trap.set("one_shot", dropped_one_shot)
	var at: Vector2 = grid.cell_center(grid.cell_of(_ai.global_position))
	_ai.get_parent().add_child(trap)                              # 放在關卡裡，不是 AI 身上（才不會跟著 AI 走）
	trap.global_position = at
	traps.append(trap)
	dropped.emit(trap)
	return trap
