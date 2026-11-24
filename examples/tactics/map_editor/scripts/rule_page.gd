class_name TacticsRulePage
extends PanelContainer
## 編輯器的「規則」頁：固定的隊伍、過關獎勵、編隊、上場人數、勝利條件、自動或回合制、陣形、分開走、骰子、營地物資。跟地圖存在一起。

## 要改地圖了（編輯器先記住上一步）
signal will_change()
## 改好了
signal changed()

## 可以改的數字：欄位、名字、最小、最大、一格、單位、說明
const NUMBERS: Array[Array] = [
	["party_max", "最多帶幾人", 0, 30, 1, "人", "編隊時最多選幾個，0＝全部都能帶"],
	["party_size", "最多上場", 0, 30, 1, "隻", "布陣時最多擺幾隻，0＝不限"],
	["join_range", "一起布陣", 1, 60, 1, "格", "分開走時，離被發現的人幾格以內（走路距離）一起布陣，更遠的會趕來支援"],
	["supplies", "一開始的營地物資", 0, 20, 1, "份", "地上的物資在「地圖」頁放"],
	["camp_heal", "紮營回復", 0.1, 1.0, 0.05, "", "0.5＝回復一半的血"],
]

var map: TacticsMap
var say: Callable = func(_text: String) -> void: pass

var _party_box: VBoxContainer
var _form: VBoxContainer


func _ready() -> void:
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	add_child(columns)
	_party_box = VBoxContainer.new()
	_party_box.custom_minimum_size = Vector2(420, 0)
	columns.add_child(_party_box)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_form)


# ---- 改 ----

func add_member(path: String) -> void:
	will_change.emit()
	map.party.append(path)
	refresh()
	changed.emit()


func remove_member(i: int) -> void:
	will_change.emit()
	map.party.remove_at(i)
	refresh()
	changed.emit()


func add_reward(path: String) -> void:
	will_change.emit()
	map.rewards.append(path)
	refresh()
	changed.emit()


func remove_reward(i: int) -> void:
	will_change.emit()
	map.rewards.remove_at(i)
	refresh()
	changed.emit()


## 往上移一位（第一位是隊長）
func move_up(i: int) -> void:
	if i <= 0:
		return
	will_change.emit()
	var path: String = map.party[i]
	map.party.remove_at(i)
	map.party.insert(i - 1, path)
	refresh()
	changed.emit()


func set_value(field: String, value: Variant) -> void:
	if map.get(field) == value:
		return
	will_change.emit()
	map.set(field, value)
	changed.emit()


# ---- 介面 ----

## 打到一半的字先算數
func commit() -> void:
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus):
		if focus.get_parent() is SpinBox:
			(focus.get_parent() as SpinBox).apply()
		focus.release_focus()


func refresh() -> void:
	if _form == null or map == null:
		return
	for box: Control in [_party_box, _form]:
		for child: Node in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_label(_party_box, "這一關固定的隊伍（空的＝用玩家的隊伍池）", 0, 18)
	for i: int in map.party.size():
		var line: HBoxContainer = HBoxContainer.new()
		_party_box.add_child(line)
		_label(line, "%d　%s%s" % [i + 1, TacticsUnitInfo.look(map.party[i])["name"], "　★隊長" if i == 0 else ""], 220)
		_button(line, "▲", move_up.bind(i)).disabled = i == 0
		LevelEditorStyle.paint_text(_button(line, "✕", remove_member.bind(i)), LevelEditorStyle.DANGER)
	_party_box.add_child(HSeparator.new())
	_label(_party_box, "加一隻：", 0, 15)
	var choices: HFlowContainer = HFlowContainer.new()
	_party_box.add_child(choices)
	for path: String in TacticsUnitInfo.paths():
		_button(choices, "＋ " + String(TacticsUnitInfo.look(path)["name"]), add_member.bind(path))

	_party_box.add_child(HSeparator.new())
	_label(_party_box, "過關後加入隊伍池（只給一次）", 0, 18)
	for i: int in map.rewards.size():
		var row: HBoxContainer = HBoxContainer.new()
		_party_box.add_child(row)
		_label(row, TacticsUnitInfo.look(map.rewards[i])["name"], 220)
		LevelEditorStyle.paint_text(_button(row, "✕", remove_reward.bind(i)), LevelEditorStyle.DANGER)
	var gifts: HFlowContainer = HFlowContainer.new()
	_party_box.add_child(gifts)
	for path: String in TacticsUnitInfo.paths():
		_button(gifts, "＋ " + String(TacticsUnitInfo.look(path)["name"]), add_reward.bind(path))

	_label(_form, "這一關的規則", 0, 18)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_form.add_child(grid)
	_label(grid, "怎樣算贏", 160)
	var win: OptionButton = OptionButton.new()
	for text: String in TacticsMap.WIN_NAMES:
		win.add_item(text)
	win.select(map.win)
	win.focus_mode = Control.FOCUS_NONE
	win.item_selected.connect(func(i: int) -> void: set_value("win", i))
	grid.add_child(win)
	_label(grid, "戰鬥一開始", 160).tooltip_text = "戰鬥中隨時可以切換"
	var mode: OptionButton = OptionButton.new()
	mode.add_item("自動")
	mode.add_item("回合制")
	mode.select(0 if map.auto_battle else 1)
	mode.focus_mode = Control.FOCUS_NONE
	mode.item_selected.connect(func(i: int) -> void: set_value("auto_battle", i == 0))
	grid.add_child(mode)
	_label(grid, "陣形", 160).tooltip_text = "整隊走時怎麼排，遊玩時按 1～4 可以換"
	var shape: OptionButton = OptionButton.new()
	for text: String in TacticsFormation.NAMES:
		shape.add_item(text)
	shape.select(map.formation)
	shape.focus_mode = Control.FOCUS_NONE
	shape.item_selected.connect(func(i: int) -> void: set_value("formation", i))
	grid.add_child(shape)
	for number: Array in NUMBERS:
		_label(grid, number[1], 160).tooltip_text = number[6]
		var box: SpinBox = SpinBox.new()
		box.min_value = number[2]
		box.max_value = number[3]
		box.step = number[4]
		box.suffix = number[5]
		box.custom_minimum_size = Vector2(160, 0)
		box.set_value_no_signal(map.get(number[0]))
		var is_int: bool = map.get(number[0]) is int
		box.value_changed.connect(func(value: float) -> void: set_value(number[0], int(value) if is_int else value))
		grid.add_child(box)
	_check("出發前讓玩家編隊（選誰、排順序、選陣形）", "choose_party")
	_check("倒下的人打贏之後用 1 滴血站起來（取消＝離隊）", "revive")
	_check("可以分開走（遊玩時按 Tab，一次控制一個人）", "allow_split")
	_check("一開始就是分開走", "start_split")
	_check("擲骰子：每次攻擊擲一顆，1 失手、6 傷害加倍", "dice")


func _check(text: String, field: String) -> void:
	var check: CheckBox = CheckBox.new()
	check.text = text
	check.button_pressed = map.get(field)
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void: set_value(field, on))
	_form.add_child(check)


func _label(parent: Control, text: String, width: int = 0, font_size: int = 15) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
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
