class_name TDWavePage
extends PanelContainer
## 編輯器的「波次」頁：一波一波排要出什麼怪，存成 waves/名稱.tres（WaveTable）。
## 存好之後，把檔案拖進關卡裡 Spawner 的 Wave Table。

## 按了「從這波試玩」
signal test_requested(wave_number: int)

## 波次檔存在這個資料夾
const WAVES_DIR: String = "res://examples/tower_defense/waves/"
const DEFAULT_TABLE: String = "res://examples/tower_defense/waves/default.tres"
const MAX_HISTORY: int = 50

## 正在編輯的波次（試玩按「重來」時場景會重新載入，波次留著）
static var editing: WaveTable
## 上次存檔（讀檔）時的樣子，用來看有沒有東西還沒存
static var saved_state: Array = []

var table: WaveTable
## 地圖上有幾個出怪口（編輯器換頁時更新）
var spawn_count: int = 1
## 顯示訊息用（編輯器給的）
var say: Callable = func(_text: String) -> void: pass

var _history: Array[WaveTable] = []
var _future: Array[WaveTable] = []
var _enemy_paths: PackedStringArray = PackedStringArray()
var _enemy_names: PackedStringArray = PackedStringArray()
var _name_edit: LineEdit
var _save_button: Button
var _load_list: OptionButton
var _start_delay: SpinBox
var _between: SpinBox
var _list: VBoxContainer
var _total: Label
## 每一列的「實際」文字、每一波的標題：改數字時只更新這些，不用整頁重做
var _row_labels: Dictionary[Wave, Array] = {}
var _titles: Array[Label] = []


func _ready() -> void:
	_build_ui()
	if editing != null:
		table = editing
	elif ResourceLoader.exists(DEFAULT_TABLE):
		table = (ResourceLoader.load(DEFAULT_TABLE) as WaveTable).copy()
	else:
		table = _new_table()
	if editing == null:
		saved_state = _state(table, table.table_name)
	editing = table
	_refresh_files()
	refresh()


func _new_table() -> WaveTable:
	var fresh: WaveTable = WaveTable.new()
	fresh.waves = [Wave.new()]
	return fresh


## 一份波次的內容（比較有沒有改過用）
func _state(which: WaveTable, table_name: String) -> Array:
	var result: Array = [table_name, which.start_delay, which.time_between_waves]
	for row: Wave in which.waves:
		result.append([row.enemy_scene.resource_path if row.enemy_scene != null else "", row.count, row.interval, row.speed, row.health, row.spawn_point, row.with_previous])
	return result


## 有沒有東西還沒存
func is_dirty() -> bool:
	return _state(table, _name_edit.text.strip_edges()) != saved_state


func update_save_button() -> void:
	LevelEditorStyle.paint_save(_save_button, is_dirty())


# ---- 改波次 ----

## 一波一波分好（每一項是那一波的所有列）
func groups() -> Array[Array]:
	return table.groups()


func _set_groups(list: Array[Array]) -> void:
	table.waves = WaveTable.flatten(list)
	refresh()


## 最後面多一波（複製上一波的怪，比較好接著改）
func add_wave() -> void:
	commit()
	remember()
	var list: Array[Array] = groups()
	list.append([list[list.size() - 1][0].duplicate() if not list.is_empty() else Wave.new()])
	_set_groups(list)


## 這一波多一種怪（同時出）
func add_row(wave: int) -> void:
	commit()
	remember()
	var list: Array[Array] = groups()
	list[wave].append(Wave.new())
	_set_groups(list)


## 拿掉一種怪（那一波空了就整波拿掉；最後一列不能拿）
func delete_row(wave: int, row: int) -> bool:
	commit()
	if table.waves.size() <= 1:
		say.call("至少要有一種怪")
		return false
	remember()
	var list: Array[Array] = groups()
	list[wave].remove_at(row)
	if list[wave].is_empty():
		list.remove_at(wave)
	_set_groups(list)
	return true


## 整波往前（-1）或往後（1）移
func move_wave(wave: int, step: int) -> bool:
	commit()
	var list: Array[Array] = groups()
	var to: int = wave + step
	if to < 0 or to >= list.size():
		return false
	remember()
	var moved: Array = list[wave]
	list.remove_at(wave)
	list.insert(to, moved)
	_set_groups(list)
	return true


## 複製一整波，放在後面
func copy_wave(wave: int) -> void:
	commit()
	remember()
	var list: Array[Array] = groups()
	var rows: Array = []
	for row: Wave in list[wave]:
		rows.append(row.duplicate())
	list.insert(wave + 1, rows)
	_set_groups(list)


## 改一列的一個欄位
func set_value(row: Wave, field: String, value: Variant) -> void:
	if row.get(field) == value:
		return
	remember()
	row.set(field, value)
	_update_labels()


## 改整份的等待時間
func set_table_value(field: String, value: float) -> void:
	if is_equal_approx(table.get(field), value):
		return
	remember()
	table.set(field, value)


# ---- 上一步、下一步 ----

func remember() -> void:
	_history.append(table.copy())
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_future.clear()


## 有沒有用到這種怪
func uses(path: String) -> bool:
	return table.waves.any(func(row: Wave) -> bool: return row.enemy_scene != null and row.enemy_scene.resource_path == path)


## 上一步都不要了（有怪被刪掉，退回去會用到不在的怪）
func forget_history() -> void:
	_history.clear()
	_future.clear()


func undo() -> bool:
	if _history.is_empty():
		say.call("沒有上一步了")
		return false
	_future.append(table)
	_use(_history.pop_back())
	say.call("上一步（還可以退 %d 步）" % _history.size())
	return true


func redo() -> bool:
	if _future.is_empty():
		say.call("沒有下一步了")
		return false
	_history.append(table)
	_use(_future.pop_back())
	say.call("下一步")
	return true


func _use(other: WaveTable) -> void:
	table = other
	editing = table
	refresh()


# ---- 存檔、讀檔 ----

## 存成 waves/名稱.tres。回傳存到哪裡（失敗＝空字串）
func save() -> String:
	commit()
	var table_name: String = _name_edit.text.strip_edges()
	if table_name.is_empty():
		say.call("先打波次名稱")
		return ""
	table.table_name = table_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WAVES_DIR))
	var path: String = WAVES_DIR + table_name.validate_filename() + ".tres"
	var fresh: WaveTable = table.copy()                           # 存複製的：之後在編輯器裡繼續改，不會動到關卡正在用的
	var error: Error = ResourceSaver.save(fresh, path)
	if error != OK:
		say.call("存檔失敗：%s（匯出的遊戲不能存，要在 Godot 編輯器裡按 F6）" % error_string(error))
		return ""
	fresh.take_over_path(path)
	saved_state = _state(table, table_name)
	update_save_button()
	_refresh_files()
	say.call("存好了：%s（拖進關卡 Spawner 的 Wave Table 就會用這份）" % path)
	return path


## 現在這份波次存在哪個檔案（還沒存過＝空字串）
func saved_path() -> String:
	var path: String = WAVES_DIR + table.table_name.validate_filename() + ".tres"
	return path if ResourceLoader.exists(path) else ""


func load_table(path: String) -> bool:
	var loaded: WaveTable = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as WaveTable
	if loaded == null:
		say.call("讀不到：%s" % path)
		return false
	remember()                                                    # 沒存檔的按上一步拿得回來
	_use(loaded.copy())
	saved_state = _state(table, table.table_name)
	_load_list.select(0)
	say.call("讀進來了：%s" % path)
	return true


func new_table() -> void:
	remember()
	_use(_new_table())
	say.call("新的波次")


## waves/ 裡有哪些波次檔
func files() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if DirAccess.dir_exists_absolute(WAVES_DIR):
		for file: String in DirAccess.get_files_at(WAVES_DIR):
			if file.ends_with(".tres"):
				result.append(WAVES_DIR + file)
	return result


func _refresh_files() -> void:
	_load_list.clear()
	_load_list.add_item("讀檔…")
	_load_list.set_item_disabled(0, true)
	for path: String in files():
		_load_list.add_item(path.get_file().get_basename())
		_load_list.set_item_metadata(_load_list.item_count - 1, path)
	_load_list.select(0)


# ---- 數字 ----

## 一波的總和：幾隻、全部打死給多少錢、總共要打掉多少血（掛件、減傷都算）
func summary(rows: Array) -> Dictionary:
	var result: Dictionary = {"count": 0, "money": 0, "health": 0.0}
	for row: Wave in rows:
		var info: Dictionary = TDEnemyInfo.stats(self, row.enemy_scene, row.health, row.speed)
		result["count"] += row.count
		result["money"] += row.count * int(info["score"])
		result["health"] += row.count * float(info["health"]) / float(info["damage_multiplier"])
	return result


## 第 wave_number 波之前全部打死會賺多少錢（從中間試玩時補給玩家）
func money_before(wave_number: int) -> int:
	var total: int = 0
	var list: Array[Array] = groups()
	for i: int in mini(wave_number - 1, list.size()):
		total += int(summary(list[i])["money"])
	return total


func _row_text(row: Wave) -> Array[String]:
	var info: Dictionary = TDEnemyInfo.stats(self, row.enemy_scene, row.health, row.speed)
	var health: String = "→ %s" % _short(info["health"])
	if float(info["damage_multiplier"]) != 1.0:
		health += "（要打 %s）" % _short(float(info["health"]) / float(info["damage_multiplier"]))
	return [health, "→ %s" % _short(info["speed"])]


func _short(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0")


# ---- 介面 ----

## 打到一半的數字先算數（按按鈕、存檔、試玩、換頁之前）
func commit() -> void:
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus):
		if focus.get_parent() is SpinBox:
			(focus.get_parent() as SpinBox).apply()
		focus.release_focus()


func _build_ui() -> void:
	custom_minimum_size = Vector2(1000, 0)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var top: HBoxContainer = HBoxContainer.new()
	box.add_child(top)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "波次名稱"
	_name_edit.custom_minimum_size = Vector2(150, 0)
	top.add_child(_name_edit)
	_save_button = _button(top, "存檔", save)
	LevelEditorStyle.paint_save(_save_button, false)
	_load_list = OptionButton.new()
	_load_list.custom_minimum_size = Vector2(150, 0)
	_load_list.focus_mode = Control.FOCUS_NONE
	_load_list.item_selected.connect(func(index: int) -> void: load_table(_load_list.get_item_metadata(index)))
	top.add_child(_load_list)
	_button(top, "新的", new_table)
	top.add_child(VSeparator.new())
	_start_delay = _spin(top, "開場等", 0.0, 60.0, 0.5, "秒", 92)
	_start_delay.value_changed.connect(func(value: float) -> void: set_table_value("start_delay", value))
	_between = _spin(top, "兩波之間等", 0.0, 60.0, 0.5, "秒", 92)
	_between.value_changed.connect(func(value: float) -> void: set_table_value("time_between_waves", value))
	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	for column: Array in [["", 60], ["怪", 130], ["幾隻", 80], ["間隔", 92], ["出怪口", 110], ["血量（0＝怪自己的）", 226], ["速度（0＝怪自己的）", 176]]:
		_label(head, column[0], column[1], 13)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var bottom: HBoxContainer = HBoxContainer.new()
	box.add_child(bottom)
	_button(bottom, "＋ 新的一波", add_wave)
	_total = _label(bottom, "", 0, 14)


## 整頁重做（多一波、少一列、讀檔、上一步、換了怪物）
func refresh() -> void:
	if _list == null or table == null:
		return
	_enemy_paths = TDEnemyInfo.paths()
	_enemy_names.clear()
	for path: String in _enemy_paths:
		_enemy_names.append(TDEnemyInfo.name_of(path))
	_name_edit.text = table.table_name
	_start_delay.set_value_no_signal(table.start_delay)
	_between.set_value_no_signal(table.time_between_waves)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_row_labels.clear()
	_titles.clear()
	var list: Array[Array] = groups()
	for i: int in list.size():
		_add_wave_title(i, list.size())
		for k: int in list[i].size():
			_add_row(i, k, list[i][k])
		_list.add_child(HSeparator.new())
	_update_labels()


func _add_wave_title(wave: int, count: int) -> void:
	var line: HBoxContainer = HBoxContainer.new()
	_list.add_child(line)
	_titles.append(_label(line, "", 560, 16))
	_button(line, "＋ 同時出", add_row.bind(wave))
	_button(line, "複製", copy_wave.bind(wave))
	_button(line, "▲", move_wave.bind(wave, -1)).disabled = wave == 0
	_button(line, "▼", move_wave.bind(wave, 1)).disabled = wave == count - 1
	var play: Button = _button(line, "▶ 從這波試玩", func() -> void:
		commit()
		test_requested.emit(wave + 1))
	LevelEditorStyle.paint(play, LevelEditorStyle.PLAY)


func _add_row(wave: int, index: int, row: Wave) -> void:
	var line: HBoxContainer = HBoxContainer.new()
	_list.add_child(line)
	_label(line, "　" if index == 0 else "　＋同時", 60, 13)
	var enemy: OptionButton = _option(line, 130)
	var current: String = row.enemy_scene.resource_path if row.enemy_scene != null else TDEnemyInfo.DEFAULT_PATH
	for i: int in _enemy_paths.size():
		enemy.add_item(_enemy_names[i])
		enemy.set_item_metadata(i, _enemy_paths[i])
		if _enemy_paths[i] == current:
			enemy.select(i)
	if not _enemy_paths.has(current):                             # 別的資料夾的怪：也放進清單
		enemy.add_item(TDEnemyInfo.name_of(current))
		enemy.set_item_metadata(enemy.item_count - 1, current)
		enemy.select(enemy.item_count - 1)
	enemy.item_selected.connect(func(i: int) -> void:
		var path: String = enemy.get_item_metadata(i)
		set_value(row, "enemy_scene", null if path == TDEnemyInfo.DEFAULT_PATH else load(path)))
	_row_spin(line, row, "count", 1, 200, 1, "隻", 80)
	_row_spin(line, row, "interval", 0.1, 10.0, 0.1, "秒", 92)
	var point: OptionButton = _option(line, 110)
	point.add_item("輪流")
	for i: int in maxi(spawn_count, row.spawn_point):
		point.add_item("出怪口%d" % (i + 1) + ("（沒有）" if i >= spawn_count else ""))
	point.select(row.spawn_point)
	point.item_selected.connect(func(i: int) -> void: set_value(row, "spawn_point", i))
	_row_spin(line, row, "health", 0, 1000, 1, "", 80)
	var health: Label = _label(line, "", 140, 13)
	_row_spin(line, row, "speed", 0, 500, 5, "", 80)
	var speed: Label = _label(line, "", 60, 13)
	_row_labels[row] = [health, speed]
	LevelEditorStyle.paint_text(_button(line, "✕", delete_row.bind(wave, index)), LevelEditorStyle.DANGER)


func _update_labels() -> void:
	for row: Wave in _row_labels:
		var texts: Array[String] = _row_text(row)
		(_row_labels[row][0] as Label).text = texts[0]
		(_row_labels[row][1] as Label).text = texts[1]
	var money: int = 0
	var count: int = 0
	var list: Array[Array] = groups()
	for i: int in mini(list.size(), _titles.size()):
		var info: Dictionary = summary(list[i])
		money += int(info["money"])
		count += int(info["count"])
		_titles[i].text = "第 %d 波　共 %d 隻　全部打死給 %d 元　總共要打 %s 滴血" % [i + 1, info["count"], info["money"], _short(info["health"])]
	_total.text = "　全部 %d 波、%d 隻，打死共給 %d 元" % [list.size(), count, money]


func _row_spin(parent: Control, row: Wave, field: String, from: float, to: float, step: float, suffix: String, width: int) -> void:
	var box: SpinBox = _spin(parent, "", from, to, step, suffix, width)
	box.set_value_no_signal(row.get(field))
	box.value_changed.connect(func(value: float) -> void: set_value(row, field, int(value) if row.get(field) is int else value))


func _spin(parent: Control, text: String, from: float, to: float, step: float, suffix: String, width: int) -> SpinBox:
	if not text.is_empty():
		_label(parent, text, 0, 14)
	var box: SpinBox = SpinBox.new()
	box.min_value = from
	box.max_value = to
	box.step = step
	box.suffix = suffix
	box.custom_minimum_size = Vector2(width, 0)
	parent.add_child(box)
	return box


func _option(parent: Control, width: int) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.custom_minimum_size = Vector2(width, 0)
	option.clip_text = true
	option.focus_mode = Control.FOCUS_NONE
	parent.add_child(option)
	return option


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
