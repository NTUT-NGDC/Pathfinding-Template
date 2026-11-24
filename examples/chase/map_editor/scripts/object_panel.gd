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
## 欄位 → 名字的字（自己改過的標成黃色）
var _labels: Dictionary[String, Label] = {}
var _reset: Button


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
	if object().is_empty() or ChaseMap.value(object(), field) == value:
		return
	will_change.emit()
	ChaseMap.set_value(object(), field, value)
	map.emit_changed()
	changed.emit()
	_mark()
	if field == "open_when":
		refresh.call_deferred()                                   # 「指定」才有目標清單


## 換成另一種
func set_kind(scene: String) -> void:
	if object()["scene"] == scene:
		return
	will_change.emit()
	ChaseMap.set_kind(object(), scene)
	map.emit_changed()
	changed.emit()
	refresh.call_deferred()


## 自己改過的都變回跟種類一樣
func reset_to_kind() -> void:
	will_change.emit()
	for field: String in ChaseMap.changed_fields(object()):
		(object()["values"] as Dictionary).erase(field)
	map.emit_changed()
	changed.emit()
	refresh.call_deferred()


## 這一個自己多的特性
func set_trait(path: String, on: bool) -> void:
	will_change.emit()
	if on:
		object()["traits"][path] = ChaseMap.defaults_of(path).duplicate()
	else:
		(object()["traits"] as Dictionary).erase(path)
	map.emit_changed()
	changed.emit()
	refresh.call_deferred()


func set_trait_value(path: String, field: String, value: Variant) -> void:
	if object()["traits"][path].get(field) == value:
		return
	will_change.emit()
	object()["traits"][path][field] = value
	changed.emit()


## 出口「指定」：要不要算這個目標
func set_target(target: String, on: bool) -> void:
	will_change.emit()
	ChaseMap.set_target(object(), target, on)
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
	_reset = null
	_labels.clear()
	_add_kind(now)
	_labels = _add_fields(ChaseMap.fields_of(now["scene"]), ChaseMap.all_values(now), set_value)
	_mark()
	if ChaseMap.is_a(now, ChaseMap.ENEMY):
		_add_note("巡邏點 %d 個（用「巡邏點」工具放，沒有就站著張望）" % (now["points"] as Array).size())
	for path: String in ChaseKinds.traits_of(now["scene"]):
		var part: Node = (load(path) as PackedScene).instantiate()
		var text: String = part.call("trait_name") if part.has_method("trait_name") else String(part.name)
		if ChaseMap.kind_traits(now["scene"]).has(path):
			_add_note("特性：%s（這種本來就有，到「敵人」頁改）" % text)
		else:
			_add_check(text, (now["traits"] as Dictionary).has(path), func(on: bool) -> void: set_trait(path, on))
			if (now["traits"] as Dictionary).has(path):
				_add_fields(LevelEditorForm.fields_of(part), now["traits"][path], func(field: String, value: Variant) -> void: set_trait_value(path, field, value))
		part.free()
	if ChaseMap.is_a(now, ChaseMap.EXIT) and ChaseMap.value(now, "open_when") == 1:
		_add_note("指定的目標：")
		for target: String in map.objective_names():
			_add_check("%s　%s" % [kind_name.call(map.object_named(target)), target], (ChaseMap.value(now, "targets") as Array).has(target), func(on: bool) -> void: set_target(target, on))


## 哪一種（可以換），自己改過的可以變回跟種類一樣
func _add_kind(now: Dictionary) -> void:
	var item: Dictionary = ChaseKinds.class_of(now["scene"])
	if item.is_empty():
		return
	var line: HBoxContainer = HBoxContainer.new()
	_box.add_child(line)
	var list: OptionButton = OptionButton.new()
	list.focus_mode = Control.FOCUS_NONE
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.tooltip_text = "這一個是哪一種；每一種的數值到「敵人」「物件」頁改"
	var paths: PackedStringArray = ChaseKinds.paths(item)
	if not paths.has(now["scene"]):
		paths.append(now["scene"])
	for path: String in paths:
		list.add_item(ChaseKinds.name_of(path))
	list.select(paths.find(now["scene"]))
	list.item_selected.connect(func(to: int) -> void: set_kind(paths[to]))
	line.add_child(list)
	_reset = Button.new()
	_reset.text = "跟種類一樣"
	_reset.tooltip_text = "黃色的是這一個自己改過的；按了全部變回種類的數值"
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.pressed.connect(reset_to_kind)
	line.add_child(_reset)


## 有種類的東西：自己改過的欄位標成黃色
func _mark() -> void:
	if _reset == null:
		return
	var mine: Array = ChaseMap.changed_fields(object())
	_reset.disabled = mine.is_empty()
	for field: String in _labels:
		_labels[field].modulate = Color("ffd447") if mine.has(field) else Color.WHITE


## 回傳 欄位 → 名字的字
func _add_fields(fields: Array[Dictionary], values: Dictionary, action: Callable) -> Dictionary[String, Label]:
	var labels: Dictionary[String, Label] = {}
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_box.add_child(grid)
	for field: Dictionary in fields:
		var control: Control = LevelEditorForm.add(grid, field, values[field["name"]], action, 120, 14)
		labels[field["name"]] = grid.get_child(control.get_index() - 1) as Label
	return labels


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
