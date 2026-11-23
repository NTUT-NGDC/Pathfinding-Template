extends Node2D
## 測試用的目標（被追的人）：示範追逐 AI 會用到目標的哪些東西（都可以沒有）。
##   is_hidden：true 的時候看不到、抓不到
##   hid(spot)：躲進去的時候發出（被親眼看到會被拖出來）
##   get_caught()：被抓到時追逐 AI 會呼叫

signal hid(spot: Node2D)

var is_hidden: bool = false
var caught_count: int = 0


func _enter_tree() -> void:
	add_to_group("player")


func hide_in(spot: Node2D) -> void:
	is_hidden = true
	global_position = spot.global_position
	hid.emit(spot)


func get_caught() -> void:
	is_hidden = false
	caught_count += 1
