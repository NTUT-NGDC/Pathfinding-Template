extends Label
## 畫面上的「寶物 1/3　發電機 0/1」：跟著出口（Exit）的進度更新。放在 CanvasLayer 底下就好。
## 出口的開門條件是「數量」時顯示「目標 1/2」。


func _ready() -> void:
	_connect.call_deferred()


func _connect() -> void:
	var exit: Exit = get_tree().get_first_node_in_group("exits") as Exit
	if exit == null:
		text = ""
		return
	exit.progress_changed.connect(func(_done: int, _needed: int) -> void: _refresh(exit))
	_refresh.call_deferred(exit)                                  # 出口也是延後一幀才數目標


func _refresh(exit: Exit) -> void:
	var parts: PackedStringArray = []
	if exit.open_when == 2:
		parts.append("目標 %d/%d" % [exit.done_count(), exit.needed_count()])
	else:
		var progress: Dictionary[String, Vector2i] = exit.progress_by_category()
		for category: String in progress:
			parts.append("%s %d/%d" % [category, progress[category].x, progress[category].y])
	text = "　".join(parts)
	if exit.is_open:
		text += ("　" if not parts.is_empty() else "") + "出口打開了！"
