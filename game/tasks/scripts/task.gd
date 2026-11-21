@tool
class_name Task
extends Node2D
## 任務積木的共同部分：修理點、鑰匙（之後的拉桿）都繼承它。
## 做完時呼叫 complete()，發出 completed；出口、畫面上的任務進度都聽這個 signal。

## 任務做完了
signal completed(task: Task)

## 畫面上任務進度的分類名稱（例如「修理 1/2」的「修理」）
var category: String = "任務"
## 做完了沒
var is_done: bool = false


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("tasks")


## 任務完成（只算一次）
func complete() -> void:
	if is_done:
		return
	is_done = true
	queue_redraw()
	completed.emit(self)
