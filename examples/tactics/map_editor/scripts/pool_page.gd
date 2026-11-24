class_name TacticsPoolPage
extends PanelContainer
## 編輯器的「隊伍」頁：玩家的起始隊伍（存成 party_pool.tres，每一關共用），還有清掉玩家存檔。

var say: Callable = func(_text: String) -> void: pass
## 正在改的起始隊伍
var start: Array[String] = []

var _box: VBoxContainer
var _info: VBoxContainer
var _save_button: Button


func _ready() -> void:
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	add_child(columns)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(460, 0)
	columns.add_child(_box)
	_info = VBoxContainer.new()
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_info)
	start = TacticsPool.start_units()
	refresh()


# ---- 改 ----

func is_dirty() -> bool:
	return start != TacticsPool.start_units()


func add_member(path: String) -> void:
	start.append(path)
	refresh()


func remove_member(i: int) -> void:
	start.remove_at(i)
	refresh()


func move_up(i: int) -> void:
	if i <= 0:
		return
	var path: String = start[i]
	start.remove_at(i)
	start.insert(i - 1, path)
	refresh()


## 存成 party_pool.tres。回傳有沒有成功
func save() -> bool:
	if start.is_empty():
		say.call("起始隊伍至少要有一個人")
		return false
	var pool: TacticsPool = load(TacticsPool.PATH) as TacticsPool if ResourceLoader.exists(TacticsPool.PATH) else TacticsPool.new()
	pool.start = start.duplicate()
	var error: Error = ResourceSaver.save(pool, TacticsPool.PATH)
	if error != OK:
		say.call("存檔失敗：%s（匯出的遊戲不能存，要在 Godot 編輯器裡按 F6）" % error_string(error))
		return false
	pool.take_over_path(TacticsPool.PATH)
	say.call("存好了：%s" % TacticsPool.PATH)
	refresh()
	return true


func clear_joined() -> void:
	TacticsPool.clear()
	say.call("清掉了：這台電腦的玩家只剩起始隊伍")
	refresh()


# ---- 介面 ----

func refresh() -> void:
	if _box == null:
		return
	for box: Control in [_box, _info]:
		for child: Node in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_label(_box, "起始隊伍（剛開始玩就有的人，每一關共用）", 18)
	for i: int in start.size():
		var line: HBoxContainer = HBoxContainer.new()
		_box.add_child(line)
		_label(line, "%d　%s" % [i + 1, TacticsUnitInfo.look(start[i])["name"]]).custom_minimum_size = Vector2(220, 0)
		_button(line, "▲", move_up.bind(i)).disabled = i == 0
		TacticsEditorStyle.paint_text(_button(line, "✕", remove_member.bind(i)), TacticsEditorStyle.DANGER)
	_box.add_child(HSeparator.new())
	_label(_box, "加一個：")
	var choices: HFlowContainer = HFlowContainer.new()
	_box.add_child(choices)
	for path: String in TacticsUnitInfo.paths():
		_button(choices, "＋ " + String(TacticsUnitInfo.look(path)["name"]), add_member.bind(path))
	_box.add_child(HSeparator.new())
	_save_button = _button(_box, "存檔", save)
	TacticsEditorStyle.paint_save(_save_button, is_dirty())

	_label(_info, "隊伍怎麼變多", 18)
	_label(_info, "・過關獎勵：「規則」頁設定這一關過了加入誰\n・招募：「地圖」頁用「同伴」放在路上，走過去按 E 加入\n・試玩時只有起始隊伍，加入的人不會存起來")
	_info.add_child(HSeparator.new())
	_label(_info, "這台電腦的玩家存檔", 18)
	var joined: Array[String] = TacticsPool.units().slice(TacticsPool.start_units().size())
	_label(_info, "加入過的人：" + ("、".join(joined.map(func(p: String) -> String: return TacticsUnitInfo.look(p)["name"])) if not joined.is_empty() else "還沒有"))
	TacticsEditorStyle.paint(_button(_info, "清掉玩家存檔（測試招募用）", clear_joined), TacticsEditorStyle.DANGER)


func _label(parent: Control, text: String, font_size: int = 15) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(func() -> void: action.call())
	parent.add_child(button)
	return button
