extends Label
## 畫面上的「瓶子 2（按 1 丟）」：跟著玩家身上的瓶子數更新，沒有瓶子就不顯示。放在 CanvasLayer 底下就好。


func _ready() -> void:
	visible = false
	_connect.call_deferred()


func _connect() -> void:
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	player.bottles_changed.connect(_refresh)
	_refresh(player.bottles)


func _refresh(count: int) -> void:
	visible = count > 0
	text = "瓶子 %d（按 1 丟）" % count
