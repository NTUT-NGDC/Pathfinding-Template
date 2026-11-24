extends HBoxContainer
## 畫面下方的「要蓋什麼」按鈕：牆、塔、緩速塔……（跟著 Builder 的設定自動產生；不能蓋牆就沒有牆）。
## 前九個也可以按數字鍵 1～9 選。


var _buttons: Dictionary[int, Button] = {}
var _builder: Builder


func _ready() -> void:
	_connect.call_deferred()


func _connect() -> void:
	_builder = get_tree().get_first_node_in_group("builder") as Builder
	if _builder == null:
		return
	_builder.selection_changed.connect(_refresh)
	_builder.rules_changed.connect(_rebuild)
	_rebuild()


## 照 Builder 現在的規則重做按鈕（例如這張地圖不能蓋牆）
func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	_buttons.clear()
	var choices: Array[int] = _builder.options()
	for i: int in choices.size():
		var what: int = choices[i]
		var button: Button = Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.text = ("%d " % (i + 1) if i < Builder.MAX_KEYS else "") + _builder.option_label(what)
		button.pressed.connect(func() -> void: _builder.selected = what)
		add_child(button)
		_buttons[what] = button
	_refresh(_builder.selected)


func _refresh(what: int) -> void:
	for key: int in _buttons:
		_buttons[key].button_pressed = key == what
