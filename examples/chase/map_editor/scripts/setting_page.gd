class_name ChaseSettingPage
extends PanelContainer
## 編輯器的「關卡」頁：黑暗、鏡頭，還有這一關有什麼。

signal will_change()

var map: ChaseMap
var say: Callable = func(_text: String) -> void: pass

var _box: VBoxContainer


func _ready() -> void:
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)


func set_value(field: String, value: Variant) -> void:
	if map.settings.get(field) == value:
		return
	will_change.emit()
	map.settings[field] = value
	if field == "dark":
		refresh.call_deferred()


func commit() -> void:
	LevelEditorForm.commit(self)


func refresh() -> void:
	if _box == null or map == null:
		return
	for child: Node in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_title("黑暗")
	var fields: Array[Dictionary] = [LevelEditorForm.check("dark", "有黑暗", "關掉就整張地圖都看得到")]
	if map.settings["dark"]:
		var dark: Node = (load(ChaseMap.DARKNESS) as PackedScene).instantiate()
		fields.append_array(LevelEditorForm.fields_of(dark))
		dark.free()
	_form(fields)
	_box.add_child(HSeparator.new())
	_title("鏡頭")
	_form([
		LevelEditorForm.check("follow", "跟著玩家", "地圖比畫面大的時候要打勾"),
		LevelEditorForm.number("zoom", "放大", 0.5, 4.0, 0.1, "倍", "跟著玩家的話，調成 2 比較看得出來"),
	])
	_box.add_child(HSeparator.new())
	_title("這一關")
	var label: Label = Label.new()
	label.text = "敵人 %d 隻　目標 %d 個\n玩家、出口、敵人、物件：在「地圖」頁點它，右邊就能改" % [map.count_of(ChaseMap.ENEMY), map.objective_names().size()]
	_box.add_child(label)


func _form(fields: Array[Dictionary]) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_box.add_child(grid)
	for field: Dictionary in fields:
		LevelEditorForm.add(grid, field, map.settings[field["name"]], set_value, 160)


func _title(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	_box.add_child(label)
