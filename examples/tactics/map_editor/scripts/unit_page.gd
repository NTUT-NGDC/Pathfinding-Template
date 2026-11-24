class_name TacticsUnitPage
extends PanelContainer
## 編輯器的「棋子」頁：改棋子的數值、個性，勾特性，存成 features/units/ 裡的一般場景。
## 我方和敵方用同一種棋子。

## 存了一隻棋子（地圖、規則頁要更新）
signal saved(path: String)

const MAX_HISTORY: int = 50
## 可以改的數字：欄位、名字、最小、最大、一格、單位、說明
const NUMBERS: Array[Array] = [
	["max_health", "血量", 1, 200, 1, "滴", ""],
	["attack", "攻擊", 0, 50, 1, "", "扣血＝攻擊 － 對方的防禦，最少 1"],
	["defense", "防禦", 0, 50, 1, "", ""],
	["move_points", "移動力", 0, 20, 1, "格", "沼澤一格算 3，森林、高地算 2"],
	["min_range", "最近射程", 1, 10, 1, "格", "2＝旁邊的打不到"],
	["max_range", "最遠射程", 1, 10, 1, "格", ""],
	["speed", "速度", 1, 30, 1, "", "每一輪從快到慢輪流動"],
]

## 正在改的棋子（試玩按「重來」時場景會重新載入，改到一半的留著）
static var editing: Dictionary = {}
static var editing_path: String = ""
## 改了還沒存
static var dirty: bool = false

var data: Dictionary:
	get: return editing
	set(value): editing = value
## 現在改的檔案（空的＝還沒存過的新棋子）
var path: String:
	get: return editing_path
	set(value): editing_path = value
var say: Callable = func(_text: String) -> void: pass

var _history: Array[Dictionary] = []
var _future: Array[Dictionary] = []
var _list: ItemList
var _paths: PackedStringArray = PackedStringArray()
var _form: VBoxContainer
var _preview_box: Control
var _preview: Node2D
var _stats: Label
var _save_button: Button
var _title: Label


func _ready() -> void:
	_build_ui()
	if editing.is_empty():
		open(TacticsUnitInfo.paths()[0])
	refresh()


# ---- 選棋子 ----

## 打開一隻棋子
func open(to: String) -> void:
	remember()                                                    # 沒存檔的按上一步拿得回來
	path = to
	data = TacticsUnitInfo.read(to)
	dirty = false
	refresh()


## 新的棋子（還沒存檔）
func new_unit() -> void:
	commit()
	remember()
	data = TacticsUnitInfo.read(TacticsUnitInfo.DEFAULT_PATH)
	data["display_name"] = _free_name("新棋子")
	path = ""
	dirty = true
	refresh()
	say.call("新棋子：改好名字和數值，按「存檔」")


## 把現在這隻複製成新的
func copy_unit() -> void:
	commit()
	remember()
	data = data.duplicate(true)
	data["display_name"] = _free_name(String(data["display_name"]) + "2")
	path = ""
	dirty = true
	refresh()
	say.call("複製了一隻：改好名字和數值，按「存檔」")


## 還沒有同名檔案的名字
func _free_name(text: String) -> String:
	var result: String = text
	var n: int = 2
	while ResourceLoader.exists(_path_for(result)):
		result = "%s%d" % [text, n]
		n += 1
	return result


func _path_for(text: String) -> String:
	return TacticsUnitInfo.UNITS_DIR + text.strip_edges().validate_filename() + ".tscn"


# ---- 改 ----

func set_value(field: String, value: Variant) -> void:
	if data[field] == value:
		return
	remember()
	data[field] = value
	_changed()


func set_trait(trait_path: String, on: bool) -> void:
	if data["traits"].has(trait_path) == on:
		return
	remember()
	if on:
		data["traits"][trait_path] = TacticsUnitInfo.trait_defaults(trait_path)
	else:
		data["traits"].erase(trait_path)
	_changed()
	_rebuild_form.call_deferred()                                 # 特性的欄位要多出來／收起來


func set_trait_value(trait_path: String, field: String, value: Variant) -> void:
	if not data["traits"].has(trait_path) or data["traits"][trait_path][field] == value:
		return
	remember()
	data["traits"][trait_path][field] = value
	_changed()


func _changed() -> void:
	dirty = path.is_empty() or data != TacticsUnitInfo.read(path)      # 改回原本的樣子就不算沒存
	_update_preview()
	_update_title()


## 存檔（新棋子：用名字當檔名）。回傳存到哪裡（失敗＝空字串）
func save() -> String:
	commit()
	var text: String = String(data["display_name"]).strip_edges()
	if text.is_empty():
		say.call("先打棋子的名字")
		return ""
	var to: String = path
	if to.is_empty():
		to = _path_for(text)
		if ResourceLoader.exists(to):
			say.call("已經有叫「%s」的棋子了，換個名字" % text)
			return ""
	var error: Error = TacticsUnitInfo.write(to, data)
	if error != OK:
		say.call("存檔失敗：%s（匯出的遊戲不能存，要在 Godot 編輯器裡按 F6）" % error_string(error))
		return ""
	path = to
	dirty = false
	refresh()
	saved.emit(to)
	say.call("存好了：%s" % to)
	return to


# ---- 上一步、下一步 ----

func remember() -> void:
	if data.is_empty():
		return
	_history.append(_state())
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_future.clear()


func undo() -> bool:
	if _history.is_empty():
		say.call("沒有上一步了")
		return false
	_future.append(_state())
	_use(_history.pop_back())
	say.call("上一步（還可以退 %d 步）" % _history.size())
	return true


func redo() -> bool:
	if _future.is_empty():
		say.call("沒有下一步了")
		return false
	_history.append(_state())
	_use(_future.pop_back())
	say.call("下一步")
	return true


## 現在改的是哪一隻、改成什麼樣子（上一步用）
func _state() -> Dictionary:
	return {"data": data.duplicate(true), "path": path, "dirty": dirty}


func _use(state: Dictionary) -> void:
	data = state["data"]
	path = state["path"]
	dirty = true if path.is_empty() else data != TacticsUnitInfo.read(path)
	refresh()


# ---- 介面 ----

## 打到一半的字先算數（存檔、試玩、換棋子、換頁之前）
func commit() -> void:
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus):
		if focus.get_parent() is SpinBox:
			(focus.get_parent() as SpinBox).apply()
		focus.release_focus()


func _build_ui() -> void:
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)

	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	columns.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)
	_button(left, "＋ 新棋子", new_unit)
	_button(left, "複製成新棋子", copy_unit)

	var middle: VBoxContainer = VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(middle)
	var top: HBoxContainer = HBoxContainer.new()
	middle.add_child(top)
	_save_button = _button(top, "存檔", save)
	_title = _label(top, "", 0, 14)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)

	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size = Vector2(280, 0)
	columns.add_child(right)
	_label(right, "預覽", 0, 14)
	_preview_box = Control.new()
	_preview_box.custom_minimum_size = Vector2(280, 240)
	_preview_box.clip_contents = true
	right.add_child(_preview_box)
	var background: ColorRect = ColorRect.new()
	background.color = Color("6b5340")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_box.add_child(background)
	_stats = _label(right, "", 0, 14)


func _on_selected(index: int) -> void:
	commit()
	if dirty and _paths[index] != path:
		say.call("剛剛改的「%s」沒有存檔（按上一步拿得回來）" % data["display_name"])
	open(_paths[index])


## 整頁重做（換了棋子、存檔）
func refresh() -> void:
	if _list == null or data.is_empty():
		return
	_paths = TacticsUnitInfo.paths()
	_list.clear()
	for i: int in _paths.size():
		_list.add_item(TacticsUnitInfo.name_of(_paths[i]))
		if _paths[i] == path:
			_list.select(i)
	_rebuild_form()
	_update_preview()
	_update_title()


func _update_title() -> void:
	if path.is_empty():
		_title.text = "　還沒存檔的新棋子"
	else:
		_title.text = "　%s%s" % [path.get_file(), "　＊改了還沒存檔" if dirty else ""]
	update_save_button()


func update_save_button() -> void:
	TacticsEditorStyle.paint_save(_save_button, dirty)


func _rebuild_form() -> void:
	if data.is_empty():
		return
	for child: Node in _form.get_children():
		_form.remove_child(child)
		child.queue_free()
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_form.add_child(grid)
	_label(grid, "名字", 110, 15)
	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = data["display_name"]
	name_edit.custom_minimum_size = Vector2(160, 0)
	name_edit.focus_exited.connect(func() -> void: set_value("display_name", name_edit.text))
	name_edit.text_submitted.connect(func(_text: String) -> void: name_edit.release_focus())
	grid.add_child(name_edit)
	_label(grid, "顏色", 110, 15)
	var color: ColorPickerButton = ColorPickerButton.new()
	color.color = data["color"]
	color.edit_alpha = false
	color.custom_minimum_size = Vector2(160, 30)
	color.focus_mode = Control.FOCUS_NONE
	color.popup_closed.connect(func() -> void: set_value("color", color.color))
	grid.add_child(color)
	_label(grid, "身上的字", 110, 15)
	var mark: LineEdit = LineEdit.new()
	mark.text = data["mark"]
	mark.max_length = 1
	mark.custom_minimum_size = Vector2(160, 0)
	mark.focus_exited.connect(func() -> void: set_value("mark", mark.text))
	mark.text_submitted.connect(func(_text: String) -> void: mark.release_focus())
	grid.add_child(mark)
	_label(grid, "個性", 110, 15)
	var mind: OptionButton = OptionButton.new()
	for text: String in Unit.MIND_NAMES:
		mind.add_item(text)
	mind.select(data["mind"])
	mind.focus_mode = Control.FOCUS_NONE
	mind.tooltip_text = "電腦怎麼決定：衝鋒＝打最近的；守衛＝有人走進打得到的範圍才動；\n挑最弱的＝打血最少的；保持距離＝打得到就站最遠"
	mind.item_selected.connect(func(index: int) -> void: set_value("mind", index))
	grid.add_child(mind)
	for number: Array in NUMBERS:
		_label(grid, number[1], 110, 15).tooltip_text = number[6]
		var box: SpinBox = _spin(grid, number[2], number[3], number[4], number[5])
		box.set_value_no_signal(data[number[0]])
		box.value_changed.connect(func(value: float) -> void: set_value(number[0], int(value) if data[number[0]] is int else value))
	_form.add_child(HSeparator.new())
	_label(_form, "特性（勾起來就有）", 0, 15)
	for trait_path: String in TacticsUnitInfo.trait_paths():
		_add_trait(trait_path)


func _add_trait(trait_path: String) -> void:
	var sample: Node = (load(trait_path) as PackedScene).instantiate()
	var on: bool = data["traits"].has(trait_path)
	var line: HBoxContainer = HBoxContainer.new()
	_form.add_child(line)
	var check: CheckBox = CheckBox.new()
	check.text = sample.call("trait_name") if sample.has_method("trait_name") else String(sample.name)
	check.custom_minimum_size = Vector2(100, 0)
	check.button_pressed = on
	check.tooltip_text = sample.call("description")
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(pressed: bool) -> void:
		commit()
		set_trait(trait_path, pressed))
	line.add_child(check)
	if on:
		var grid: GridContainer = GridContainer.new()
		grid.columns = 4
		line.add_child(grid)
		for field: Dictionary in TacticsUnitInfo.trait_fields(sample):
			_label(grid, field["label"], 0, 13)
			var value: Variant = data["traits"][trait_path][field["name"]]
			if field["type"] == TYPE_BOOL:
				var toggle: CheckBox = CheckBox.new()
				toggle.button_pressed = value
				toggle.focus_mode = Control.FOCUS_NONE
				toggle.toggled.connect(func(pressed: bool) -> void: set_trait_value(trait_path, field["name"], pressed))
				grid.add_child(toggle)
				continue
			var box: SpinBox = _spin(grid, field["min"], field["max"], field["step"], field["suffix"])
			box.set_value_no_signal(value)
			box.value_changed.connect(func(v: float) -> void: set_trait_value(trait_path, field["name"], int(v) if field["type"] == TYPE_INT else v))
	sample.free()


## 預覽：照現在改的數值做一隻，放大給你看
func _update_preview() -> void:
	if _preview != null:
		_preview.free()
	var base: String = path if not path.is_empty() else TacticsUnitInfo.DEFAULT_PATH
	_preview = (load(base) as PackedScene).instantiate() as Node2D
	for child: Node in _preview.get_children():
		if TacticsUnitInfo.trait_paths().has(child.scene_file_path):
			_preview.remove_child(child)
			child.free()
	for field: String in TacticsUnitInfo.FIELDS:
		_preview.set(field, data[field])
	for trait_path: String in data["traits"]:
		var node: Node = (load(trait_path) as PackedScene).instantiate()
		for key: String in data["traits"][trait_path]:
			node.set(key, data["traits"][trait_path][key])
		_preview.add_child(node)
	_preview.process_mode = Node.PROCESS_MODE_DISABLED
	_preview_box.add_child(_preview)
	_preview.remove_from_group("tactics_units")                   # 只是預覽，不要被當成場上的棋子
	_preview.set("team", 0)
	_preview.position = Vector2(140, 120)
	_preview.scale = Vector2(4, 4)
	_stats.text = (_preview as Unit).info_text() + "\n個性：" + Unit.MIND_NAMES[data["mind"]]


func _spin(parent: Control, from: float, to: float, step: float, suffix: String) -> SpinBox:
	var box: SpinBox = SpinBox.new()
	box.min_value = from
	box.max_value = to
	box.step = step
	box.suffix = suffix
	box.custom_minimum_size = Vector2(110, 0)
	parent.add_child(box)
	return box


func _label(parent: Control, text: String, width: int, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: action.call())
	parent.add_child(button)
	return button
