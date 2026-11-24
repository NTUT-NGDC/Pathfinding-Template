class_name TDEnemyPage
extends PanelContainer
## 編輯器的「怪物」頁：改怪的數值、勾掛件，存成 features/enemies/ 裡的一般場景。
## 普通怪是尋路積木本身，不能改；按「複製成新怪」拿來改。

## 存了一隻怪（波次頁要更新）
signal saved(path: String)

const MAX_HISTORY: int = 50
## 可以改的數字：欄位、名字、最小、最大、一格、單位
const NUMBERS: Array[Array] = [
	["speed", "速度", 10, 500, 5, "px/秒"],
	["max_health", "血量", 1, 1000, 1, "滴"],
	["score", "打死給", 0, 1000, 1, "元"],
	["wall_damage", "打牆", 0.1, 100, 0.1, "滴/秒"],
	["radius", "大小", 4, 32, 1, "px"],
]

## 正在改的怪（試玩按「重來」時場景會重新載入，改到一半的留著）
static var editing: Dictionary = {}
static var editing_path: String = ""
## 改了還沒存
static var dirty: bool = false

var data: Dictionary:
	get: return editing
	set(value): editing = value
## 現在改的檔案（空的＝還沒存過的新怪）
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
		var first: PackedStringArray = TDEnemyInfo.walker_paths()
		open(first[1] if first.size() > 1 else first[0])
	refresh()


# ---- 選怪 ----

## 打開一隻怪
func open(to: String) -> void:
	remember()                                                    # 沒存檔的按上一步拿得回來
	path = to
	data = TDEnemyInfo.read(to)
	dirty = false
	refresh()


## 新的怪（還沒存檔，從普通怪的數值開始）
func new_enemy() -> void:
	commit()
	remember()
	data = TDEnemyInfo.read(TDEnemyInfo.DEFAULT_PATH)
	data["display_name"] = _free_name("新怪")
	path = ""
	dirty = true
	refresh()
	say.call("新怪：改好名字和數值，按「存檔」")


## 把現在這隻複製成新的
func copy_enemy() -> void:
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
	return TDEnemyInfo.ENEMIES_DIR + text.strip_edges().validate_filename() + ".tscn"


## 普通怪不能改
func is_locked() -> bool:
	return path == TDEnemyInfo.DEFAULT_PATH


# ---- 改 ----

func set_value(field: String, value: Variant) -> void:
	if is_locked() or data[field] == value:
		return
	remember()
	data[field] = value
	_changed()


func set_trait(trait_path: String, on: bool) -> void:
	if is_locked() or data["traits"].has(trait_path) == on:
		return
	remember()
	if on:
		data["traits"][trait_path] = TDEnemyInfo.trait_defaults(trait_path)
	else:
		data["traits"].erase(trait_path)
	_changed()
	_rebuild_form.call_deferred()                                 # 掛件的欄位要多出來／收起來


func set_trait_value(trait_path: String, field: String, value: Variant) -> void:
	if is_locked() or not data["traits"].has(trait_path) or data["traits"][trait_path][field] == value:
		return
	remember()
	data["traits"][trait_path][field] = value
	_changed()


func _changed() -> void:
	dirty = path.is_empty() or data != TDEnemyInfo.read(path)      # 改回原本的樣子就不算沒存
	_update_preview()
	_update_title()


## 存檔（新怪：用名字當檔名）。回傳存到哪裡（失敗＝空字串）
func save() -> String:
	commit()
	if is_locked():
		say.call("普通怪是尋路積木本身，不能改。按「複製成新怪」拿來改")
		return ""
	var text: String = String(data["display_name"]).strip_edges()
	if text.is_empty():
		say.call("先打怪的名字")
		return ""
	var to: String = path
	if to.is_empty():
		to = _path_for(text)
		if ResourceLoader.exists(to):
			say.call("已經有叫「%s」的怪了，換個名字" % text)
			return ""
	var error: Error = TDEnemyInfo.write(to, data)
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
	dirty = true if path.is_empty() else data != TDEnemyInfo.read(path)
	refresh()


# ---- 介面 ----

## 打到一半的字先算數（存檔、試玩、換怪、換頁之前）
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
	_button(left, "＋ 新怪", new_enemy)
	_button(left, "複製成新怪", copy_enemy)

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


## 整頁重做（換了怪、存檔）
func refresh() -> void:
	if _list == null or data.is_empty():
		return
	_paths = TDEnemyInfo.walker_paths()
	_list.clear()
	for i: int in _paths.size():
		_list.add_item(TDEnemyInfo.name_of(_paths[i]) + ("（不能改）" if i == 0 else ""))
		if _paths[i] == path:
			_list.select(i)
	_rebuild_form()
	_update_preview()
	_update_title()


func _update_title() -> void:
	if is_locked():
		_title.text = "　普通怪是尋路積木本身，不能改；按「複製成新怪」拿來改"
	elif path.is_empty():
		_title.text = "　還沒存檔的新怪"
	else:
		_title.text = "　%s%s" % [path.get_file(), "　＊改了還沒存檔" if dirty else ""]
	_save_button.disabled = is_locked()
	update_save_button()


func update_save_button() -> void:
	TDEditorStyle.paint_save(_save_button, dirty and not is_locked())


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
	name_edit.editable = not is_locked()
	name_edit.focus_exited.connect(func() -> void: set_value("display_name", name_edit.text))
	name_edit.text_submitted.connect(func(_text: String) -> void: name_edit.release_focus())
	grid.add_child(name_edit)
	_label(grid, "顏色", 110, 15)
	var color: ColorPickerButton = ColorPickerButton.new()
	color.color = data["color"]
	color.edit_alpha = false
	color.custom_minimum_size = Vector2(160, 30)
	color.focus_mode = Control.FOCUS_NONE
	color.disabled = is_locked()
	color.popup_closed.connect(func() -> void: set_value("color", color.color))
	grid.add_child(color)
	for number: Array in NUMBERS:
		_label(grid, number[1], 110, 15)
		var box: SpinBox = _spin(grid, number[2], number[3], number[4], number[5])
		box.set_value_no_signal(data[number[0]])
		box.value_changed.connect(func(value: float) -> void: set_value(number[0], int(value) if data[number[0]] is int else value))
	_form.add_child(HSeparator.new())
	_label(_form, "掛件（勾起來就有）", 0, 15)
	for trait_path: String in TDEnemyInfo.trait_paths():
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
	check.disabled = is_locked()
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(pressed: bool) -> void:
		commit()
		set_trait(trait_path, pressed))
	line.add_child(check)
	if on:
		var grid: GridContainer = GridContainer.new()
		grid.columns = 4
		line.add_child(grid)
		for field: Dictionary in TDEnemyInfo.trait_fields(sample):
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
	var base: String = path if not path.is_empty() else TDEnemyInfo.DEFAULT_PATH
	_preview = (load(base) as PackedScene).instantiate() as Node2D
	for child: Node in _preview.get_children():
		if TDEnemyInfo.trait_paths().has(child.scene_file_path):
			_preview.remove_child(child)
			child.free()
	for field: String in TDEnemyInfo.FIELDS:
		_preview.set(field, data[field])
	for trait_path: String in data["traits"]:
		var node: Node = (load(trait_path) as PackedScene).instantiate()
		for key: String in data["traits"][trait_path]:
			node.set(key, data["traits"][trait_path][key])
		_preview.add_child(node)
	_preview.process_mode = Node.PROCESS_MODE_DISABLED
	_preview_box.add_child(_preview)
	_preview.remove_from_group("enemies")                         # 只是預覽，不要被當成場上的怪
	_preview.position = Vector2(140, 120)
	_preview.scale = Vector2(4, 4)
	var info: Dictionary = TDEnemyInfo.stats_of(_preview)
	_stats.text = "實際血量　%s%s\n實際速度　%s px/秒\n打死給　%d 元" % [_short(info["health"]),
		"（減傷：要打 %s）" % _short(float(info["health"]) / float(info["damage_multiplier"])) if float(info["damage_multiplier"]) != 1.0 else "",
		_short(info["speed"]), info["score"]]
	_stats.text += "\n\n波次有填血量、速度的話，\n會先換成波次的再算掛件"


func _short(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0")


func _spin(parent: Control, from: float, to: float, step: float, suffix: String) -> SpinBox:
	var box: SpinBox = SpinBox.new()
	box.min_value = from
	box.max_value = to
	box.step = step
	box.suffix = suffix
	box.editable = not is_locked()
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
