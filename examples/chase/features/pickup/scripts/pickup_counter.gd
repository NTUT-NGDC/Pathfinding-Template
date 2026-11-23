extends Label
## 畫面上的「寶物 1/3」：跟著出口（Exit）的進度更新。放在 CanvasLayer 底下就好。

## 文字前面的字
@export var prefix: String = "寶物 "


func _ready() -> void:
	_connect.call_deferred()


func _connect() -> void:
	for node: Node in get_tree().get_nodes_in_group("exits"):
		(node as Exit).progress_changed.connect(_on_progress)
		_on_progress((node as Exit).picked_count(), (node as Exit).total_count())
		return


func _on_progress(picked: int, total: int) -> void:
	text = "%s%d/%d" % [prefix, picked, total]
	if total > 0 and picked >= total:
		text += "　出口打開了！"
