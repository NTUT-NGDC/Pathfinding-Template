class_name ChaseObjectPanel
extends PanelContainer
## 編輯器右邊的面板：現在選的物件可以改什麼（欄位從它的 @export 自動讀，自己加的物件也會有）。

## 要改了（編輯器先記住上一步）
signal will_change()
## 改好了
signal changed()
## 按了刪掉
signal delete_pressed()

var map: ChaseMap
## 物件 → 中文種類（編輯器給的）
var kind_name: Callable = func(_object: Dictionary) -> String: return ""
## 選的是第幾個物件（-1＝沒選）
var index: int = -1

var _box: VBoxContainer


func _ready() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)


func object() -> Dictionary:
	return map.objects[index] if map != null and index >= 0 and index < map.objects.size() else {}


func set_value(field: String, value: Variant) -> void:
	if object().is_empty() or object()["values"].get(field) == value:
		return
	will_change.emit()
	object()["values"][field] = value
	map.emit_changed()
	changed.emit()
	if field == "open_when":
		refresh.call_deferred()                                   # 「指定」才有目標清單


func set_dropper(on: bool) -> void:
	will_change.emit()
	object()["dropper"] = ChaseMap.defaults_of(ChaseMap.DROPPER) if on else {}
	map.emit_changed()
	changed.emit()
	refresh.call_deferred()


func set_dropper_value(field: String, value: Variant) -> void:
	if object()["dropper"].get(field) == value:
		return
	will_change.emit()
	object()["dropper"][field] = value
	changed.emit()


## 出口「指定」：要不要算這個目標
func set_target(target: String, on: bool) -> void:
	will_change.emit()
	var targets: Array = object()["values"]["targets"]
	targets.erase(target)
	if on:
		targets.append(target)
	changed.emit()


func commit() -> void:
	LevelEditorForm.commit(self)


func refresh() -> void:
	if _box == null:
		return
	for child: Node in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	visible = not object().is_empty()
	if not visible:
		return
	var now: Dictionary = object()
	var top: HBoxContainer = HBoxContainer.new()
	_box.add_child(top)
	var title: Label = Label.new()
	title.text = "%s　%s" % [kind_name.call(now), now["name"]]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	top.add_child(title)
	var delete: Button = Button.new()
	delete.text = "刪掉"
	delete.focus_mode = Control.FOCUS_NONE
	delete.pressed.connect(func() -> void: delete_pressed.emit())
	LevelEditorStyle.paint(delete, LevelEditorStyle.DANGER)
	top.add_child(delete)
	_add_fields(ChaseMap.fields_of(now["scene"]), now["values"], set_value)
	if now["scene"] == ChaseMap.ENEMY:
		_add_note("巡邏點 %d 個（用「巡邏點」工具放，沒有就站著張望）" % (now["points"] as Array).size())
		_add_check("追丟時放捕獸夾", not (now["dropper"] as Dictionary).is_empty(), set_dropper)
		if not (now["dropper"] as Dictionary).is_empty():
			_add_fields(ChaseMap.fields_of(ChaseMap.DROPPER), now["dropper"], set_dropper_value)
	if now["values"].has("targets") and now["values"]["open_when"] == 1:
		_add_note("指定的目標：")
		for target: String in map.objective_names():
			_add_check("%s　%s" % [kind_name.call(map.object_named(target)), target], (now["values"]["targets"] as Array).has(target), func(on: bool) -> void: set_target(target, on))


func _add_fields(fields: Array[Dictionary], values: Dictionary, action: Callable) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_box.add_child(grid)
	for field: Dictionary in fields:
		LevelEditorForm.add(grid, field, values[field["name"]], action, 120, 14)


func _add_check(text: String, on: bool, action: Callable) -> void:
	var box: CheckBox = CheckBox.new()
	box.text = text
	box.button_pressed = on
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(pressed: bool) -> void: action.call(pressed))
	_box.add_child(box)


func _add_note(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.add_theme_font_size_override("font_size", 13)
	_box.add_child(label)
