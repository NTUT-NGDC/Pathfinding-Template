class_name TacticsSquadPage
extends PanelContainer
## 編輯器的「小隊」頁：每一隊的名字、視野、反應時間、巡邏、支援、掉落物資、首領。
## 隊員和巡邏點在「地圖」頁放。

## 要改地圖了（編輯器先記住上一步）
signal will_change()
## 改好了
signal changed()
## 選了另一隊（編輯器把畫面移過去）
signal selected()

## 可以改的數字：欄位、名字、最小、最大、一格、單位、說明
const NUMBERS: Array[Array] = [
	["view_distance", "看多遠", 40, 800, 10, "px", "一格是 32"],
	["view_angle", "視野角度", 10, 360, 5, "度", "360＝背後也看得到"],
	["member_view", "隊友看多遠", 0.1, 2.0, 0.05, "倍", "隊友看的距離是帶頭的幾倍"],
	["reaction_time", "反應時間", 0.0, 5.0, 0.1, "秒", "看到隊長幾秒之後開打（?→!）。0＝一看到就開打"],
	["start_angle", "一開始面向", -180, 180, 5, "度", "0＝右、90＝下、180＝左、-90＝上"],
	["patrol_speed", "巡邏速度", 10, 300, 5, "px/秒", ""],
	["support", "支援距離", 0, 40, 1, "格", "別隊開打時，離這麼近就會加入。0＝不會去"],
	["drop_supplies", "掉落物資", 0, 10, 1, "份", "打倒這一隊之後掉在地上，走過去撿"],
]

var map: TacticsMap
## 正在改第幾隊
var index: int = 0
var say: Callable = func(_text: String) -> void: pass

var _list: ItemList
var _form: VBoxContainer


func _ready() -> void:
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	columns.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(func(i: int) -> void:
		commit()
		index = i
		refresh()
		changed.emit()
		selected.emit())
	left.add_child(_list)
	_button(left, "＋ 新小隊", add_squad)
	TacticsEditorStyle.paint(_button(left, "刪掉這一隊", remove_squad), TacticsEditorStyle.DANGER)
	var scroll: ScrollContainer = ScrollContainer.new()           # 隊員很多的時候可以捲
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)


func squad() -> TacticsSquad:
	return map.squads[index] if map != null and index >= 0 and index < map.squads.size() else null


# ---- 改 ----

func add_squad() -> void:
	commit()
	will_change.emit()
	var fresh: TacticsSquad = TacticsSquad.new()
	fresh.squad_name = "小隊%d" % (map.squads.size() + 1)
	map.squads.append(fresh)
	index = map.squads.size() - 1
	refresh()
	changed.emit()
	say.call("新小隊：到「地圖」頁選「敵人」放隊員、選「巡邏點」畫路線")


func remove_squad() -> void:
	if squad() == null:
		return
	will_change.emit()
	map.squads.remove_at(index)
	index = maxi(index - 1, 0)
	refresh()
	changed.emit()
	selected.emit()


func set_value(field: String, value: Variant) -> void:
	if squad() == null or squad().get(field) == value:
		return
	will_change.emit()
	squad().set(field, value)
	if field == "squad_name":
		_list.set_item_text(index, _title(index))
	changed.emit()


func remove_member(i: int) -> void:
	will_change.emit()
	squad().remove_at(i)
	refresh()
	changed.emit()


## 帶頭的換成第 i 隻
func make_leader(i: int) -> void:
	will_change.emit()
	var path: String = squad().members[i]
	var cell: Vector2i = squad().cells[i]
	squad().remove_at(i)
	squad().members.insert(0, path)
	squad().cells.insert(0, cell)
	refresh()
	changed.emit()


# ---- 介面 ----

## 打到一半的字先算數
func commit() -> void:
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus):
		if focus.get_parent() is SpinBox:
			(focus.get_parent() as SpinBox).apply()
		focus.release_focus()


func _title(i: int) -> String:
	var s: TacticsSquad = map.squads[i]
	return "%d　%s（%d 隻）%s%s" % [i + 1, s.squad_name, s.members.size(), "　首領" if s.boss else "", "　一開始就打" if s.instant else ""]


func refresh() -> void:
	if _list == null or map == null:
		return
	index = clampi(index, 0, maxi(map.squads.size() - 1, 0))
	_list.clear()
	for i: int in map.squads.size():
		_list.add_item(_title(i))
	for child: Node in _form.get_children():
		_form.remove_child(child)
		child.queue_free()
	if squad() == null:
		_label(_form, "還沒有小隊，按「＋ 新小隊」")
		return
	_list.select(index)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_form.add_child(grid)
	_label(grid, "名字", 120)
	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = squad().squad_name
	name_edit.custom_minimum_size = Vector2(180, 0)
	name_edit.focus_exited.connect(func() -> void: set_value("squad_name", name_edit.text))
	name_edit.text_submitted.connect(func(_t: String) -> void: name_edit.release_focus())
	grid.add_child(name_edit)
	for number: Array in NUMBERS:
		_label(grid, number[1], 120).tooltip_text = number[6]
		var box: SpinBox = SpinBox.new()
		box.min_value = number[2]
		box.max_value = number[3]
		box.step = number[4]
		box.suffix = number[5]
		box.custom_minimum_size = Vector2(180, 0)
		box.set_value_no_signal(squad().get(number[0]))
		var is_int: bool = squad().get(number[0]) is int
		box.value_changed.connect(func(value: float) -> void: set_value(number[0], int(value) if is_int else value))
		grid.add_child(box)
	_label(grid, "巡邏方式", 120)
	var mode: OptionButton = OptionButton.new()
	mode.add_item("來回")
	mode.add_item("繞圈")
	mode.select(squad().patrol_mode)
	mode.focus_mode = Control.FOCUS_NONE
	mode.item_selected.connect(func(i: int) -> void: set_value("patrol_mode", i))
	grid.add_child(mode)
	_check("只有帶頭的有視野（隊友不會發現你）", "leader_only")
	_check("首領（勝利條件選「打倒首領小隊」時要打倒的）", "boss")
	_check("一開始就開打（不用探索，做純戰棋）", "instant")
	_form.add_child(HSeparator.new())
	_label(_form, "隊員（照地圖上擺的位置排成隊形；在「地圖」頁放）")
	for i: int in squad().members.size():
		var line: HBoxContainer = HBoxContainer.new()
		_form.add_child(line)
		_label(line, "%s%s" % [TacticsUnitInfo.look(squad().members[i])["name"], "　★帶頭" if i == 0 else ""], 160)
		if i > 0:
			_button(line, "改成帶頭", make_leader.bind(i))
		TacticsEditorStyle.paint_text(_button(line, "✕", remove_member.bind(i)), TacticsEditorStyle.DANGER)


func _check(text: String, field: String) -> void:
	var check: CheckBox = CheckBox.new()
	check.text = text
	check.button_pressed = squad().get(field)
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void:
		commit()
		set_value(field, on)
		_list.set_item_text(index, _title(index)))
	_form.add_child(check)


func _label(parent: Control, text: String, width: int = 0) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: action.call())
	parent.add_child(button)
	return button
