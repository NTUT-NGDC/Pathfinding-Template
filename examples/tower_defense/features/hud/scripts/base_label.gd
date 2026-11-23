extends Label
## 畫面上的「基地 8/10」：跟著基地規則（BaseGroup）更新。


func _ready() -> void:
	_connect.call_deferred()


func _connect() -> void:
	var group: BaseGroup = get_tree().get_first_node_in_group("base_group") as BaseGroup
	if group == null:
		text = ""
		return
	group.changed.connect(func() -> void: text = group.status_text())
	text = group.status_text()
