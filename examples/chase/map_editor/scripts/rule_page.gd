class_name ChaseRulePage
extends PanelContainer
## 編輯器的「規則」頁：出口什麼時候開、玩家、黑暗、鏡頭。跟關卡一起存。
## 出口、玩家改的就是地圖上的那個（在地圖頁點它也能改，是同一份）。

signal will_change()

var map: ChaseMap
var say: Callable = func(_text: String) -> void: pass
## 物件 → 中文種類（編輯器給的）
var kind_name: Callable = func(_object: Dictionary) -> String: return ""

var _columns: HBoxContainer


func _ready() -> void:
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 24)
	add_child(_columns)


## 黑暗、鏡頭
func set_setting(field: String, value: Variant) -> void:
	if map.settings.get(field) == value:
		return
	will_change.emit()
	map.settings[field] = value
	if field == "dark":
		refresh.call_deferred()


## 出口、玩家
func set_value(object: Dictionary, field: String, value: Variant) -> void:
	if ChaseMap.value(object, field) == value:
		return
	will_change.emit()
	ChaseMap.set_value(object, field, value)
	map.emit_changed()
	if field == "open_when":
		refresh.call_deferred()                                   # 「指定」「數量」要多出欄位


## 出口「指定」：要不要算這個目標
func set_target(object: Dictionary, target: String, on: bool) -> void:
	will_change.emit()
	ChaseMap.set_target(object, target, on)
	refresh.call_deferred()


func commit() -> void:
	LevelEditorForm.commit(self)


func refresh() -> void:
	if _columns == null or map == null:
		return
	for child: Node in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	var box: VBoxContainer = _column()
	for object: Dictionary in map.objects:
		if ChaseMap.is_a(object, ChaseMap.EXIT):
			_build_exit(box, object)
	box = _column()
	for object: Dictionary in map.objects:
		if ChaseMap.is_a(object, ChaseMap.PLAYER):
			_title(box, "玩家")
			_object_form(box, object, ChaseMap.fields_of(object["scene"]))
	_build_settings(_column())


func _build_exit(box: Control, object: Dictionary) -> void:
	_title(box, "%s什麼時候開" % ("出口" if map.count_of(ChaseMap.EXIT) == 1 else String(object["name"])))
	var when: int = ChaseMap.value(object, "open_when")
	var names: Array = ["open_when", "needed"] if when == 2 else ["open_when"]
	_object_form(box, object, ChaseMap.fields_of(object["scene"]).filter(func(field: Dictionary) -> bool: return names.has(field["name"])))
	var required: int = 0
	for target: String in map.objective_names():
		var goal: Dictionary = map.object_named(target)
		if ChaseMap.value(goal, "required") == true:
			required += 1
		if when == 1:
			var check: CheckBox = CheckBox.new()
			check.text = "%s　%s" % [kind_name.call(goal), target]
			check.button_pressed = (ChaseMap.value(object, "targets") as Array).has(target)
			check.focus_mode = Control.FOCUS_NONE
			check.toggled.connect(func(on: bool) -> void: set_target(object, target, on))
			box.add_child(check)
	match when:
		0:
			_note(box, "算進出口條件的目標（現在 %d 個）全部完成才開" % required)
		1:
			_note(box, "勾起來的都完成才開" if not map.objective_names().is_empty() else "還沒有目標，先到「地圖」頁的「目標」放")
		2:
			_note(box, "算進出口條件的目標（現在 %d 個）完成這麼多個就開" % required)
	box.add_child(HSeparator.new())


func _build_settings(box: Control) -> void:
	_title(box, "黑暗")
	var fields: Array[Dictionary] = [LevelEditorForm.check("dark", "有黑暗", "關掉就整張地圖都看得到")]
	if map.settings["dark"]:
		var dark: Node = (load(ChaseMap.DARKNESS) as PackedScene).instantiate()
		fields.append_array(LevelEditorForm.fields_of(dark))
		dark.free()
	_form(box, fields)
	box.add_child(HSeparator.new())
	_title(box, "鏡頭")
	_form(box, [
		LevelEditorForm.check("follow", "跟著玩家", "地圖比畫面大的時候要打勾"),
		LevelEditorForm.number("zoom", "放大", 0.5, 4.0, 0.1, "倍", "跟著玩家的話，調成 2 比較看得出來"),
	])
	box.add_child(HSeparator.new())
	_title(box, "這一關")
	_note(box, "敵人 %d 隻　目標 %d 個" % [map.count_of(ChaseMap.ENEMY), map.objective_names().size()])


func _column() -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _object_form(box: Control, object: Dictionary, fields: Array) -> void:
	var grid: GridContainer = _grid(box)
	for field: Dictionary in fields:
		LevelEditorForm.add(grid, field, ChaseMap.value(object, field["name"]), func(key: String, value: Variant) -> void: set_value(object, key, value), 130)


func _form(box: Control, fields: Array[Dictionary]) -> void:
	var grid: GridContainer = _grid(box)
	for field: Dictionary in fields:
		LevelEditorForm.add(grid, field, map.settings[field["name"]], set_setting, 130)


func _grid(box: Control) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	return grid


func _title(box: Control, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	box.add_child(label)


func _note(box: Control, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.add_theme_font_size_override("font_size", 13)
	box.add_child(label)
