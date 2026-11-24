class_name TacticsHud
extends CanvasLayer
## 戰棋的畫面：左上現在在做什麼、上面行動順序、右邊布陣和日誌、左下棋子數值、下面按鈕（自動、倍速、暫停、意圖、待命、反悔）。

@export var battle: TacticsBattle
@export var party: TacticsParty
## 可以切換的倍速
@export var speeds: Array[float] = [1.0, 2.0, 3.0]

var _title: Label
var _hint: Label
var _supply: Label
var _info: PanelContainer
var _info_text: Label
var _order: TacticsOrderBar
var _deploy: PanelContainer
var _deploy_rows: VBoxContainer
var _deploy_title: Label
var _mode_buttons: Array[Button] = []
var _bar: HBoxContainer
var _auto_button: Button
var _speed_button: Button
var _pause_button: Button
var _wait_button: Button
var _undo_button: Button
var _intent_button: Button
var _log: PanelContainer
var _log_text: RichTextLabel
var _log_button: Button
var _explore_bar: HBoxContainer
var _party_bar: TacticsPartyBar
var _split_button: Button
var _formation_button: Button
## 玩家自己把日誌關掉了（開打時就不會再自動打開）
var _log_closed: bool = false
var _message: Label
var _message_time: float = 0.0


func _ready() -> void:
	_build()
	battle.updated.connect(refresh)
	battle.ended.connect(func(_won: bool) -> void: refresh())
	battle.deploy_started.connect(_on_deploy_started)
	battle.noted.connect(_on_noted)
	battle.fight_started.connect(func() -> void: _log_button.button_pressed = not _log_closed)
	party.changed.connect(_on_party_changed)
	refresh.call_deferred()


func _process(delta: float) -> void:
	_message_time -= delta / maxf(Engine.time_scale, 0.01)
	_message.visible = _message_time > 0.0


func _on_deploy_started() -> void:
	_say("偷襲成功！第一輪我方先動" if battle.is_ambush else "被發現了！")
	_rebuild_deploy()


func _on_party_changed() -> void:
	_say(party.message)
	refresh()


## 日誌多一行（太長就從最舊的丟掉）
func _on_noted(text: String) -> void:
	_log_text.append_text(text + "\n")
	while _log_text.get_paragraph_count() > 200:
		_log_text.remove_paragraph(0)


func _say(text: String) -> void:
	_message.text = text
	_message_time = 2.0


## 照現在的狀態更新畫面
func refresh() -> void:
	visible = not party.members.is_empty()                        # 編隊的時候先不顯示
	if not is_inside_tree() or not visible:
		return
	var state: TacticsBattle.State = battle.state
	_deploy.visible = state == TacticsBattle.State.DEPLOY
	_order.visible = state == TacticsBattle.State.FIGHT
	_bar.visible = state == TacticsBattle.State.FIGHT
	_log_button.visible = state != TacticsBattle.State.DEPLOY      # 布陣時那裡是上場名單
	_log.visible = _log_button.visible and _log_button.button_pressed
	_order.show_order(battle.order, battle.late, battle.round_number)
	_explore_bar.visible = state == TacticsBattle.State.NONE
	_party_bar.refresh()
	_split_button.text = "分開走（Tab）" if party.split else "整隊走（Tab）"
	_split_button.button_pressed = party.split
	_split_button.visible = party.can_split()
	_formation_button.text = "陣形：%s（1～4）" % TacticsFormation.NAMES[party.formation]
	_formation_button.visible = not party.split
	_supply.text = "營地物資 %d" % party.supplies
	_supply.visible = state == TacticsBattle.State.NONE
	match state:
		TacticsBattle.State.NONE:
			_title.text = "探索"
			_hint.text = "WASD 或點地上走　繞到敵人背後碰他＝偷襲　E 紮營休息（寶箱旁邊＝搜括）\nQ 或點隊友＝換人控制　Tab 整隊／分開　1～4 換陣形"
		TacticsBattle.State.DEPLOY:
			_title.text = "布陣"
			_hint.text = "點我方棋子 → 點藍色的格子擺放（點自己人＝交換）\n點敵人＝指定目標（自動時優先打它）　箭頭＝誰打算打誰"
			_update_deploy()
		TacticsBattle.State.FIGHT:
			var who: String = battle.current.display_name if battle.current != null else ""
			_title.text = "第 %d 輪" % battle.round_number
			_hint.text = "輪到%s：藍色可以走、紅框可以打（綠框可以補）　點自己＝不走\n空白鍵待命　右鍵反悔" % who if battle.is_waiting else "輪到%s　　點敵人＝指定目標（再點一次取消）" % who
	_auto_button.text = "自動：開" if battle.auto else "自動：關"
	_auto_button.button_pressed = battle.auto
	_speed_button.text = "▶ %s×" % str(battle.game_speed).trim_suffix(".0")
	_pause_button.text = "繼續" if battle.paused else "暫停"
	_pause_button.button_pressed = battle.paused
	_intent_button.text = "意圖：開" if battle.show_intents else "意圖：關"
	_intent_button.button_pressed = battle.show_intents
	_wait_button.disabled = not battle.is_waiting
	_undo_button.disabled = not (battle.is_waiting and battle.has_moved)
	for i: int in _mode_buttons.size():
		_mode_buttons[i].button_pressed = (i == 0) == battle.auto
	_update_info()


## 滑鼠指著的棋子（沒有就顯示輪到的那隻）；回合制時順便預覽扣多少血
func _update_info() -> void:
	var unit: Unit = battle.hovered
	if unit == null or not is_instance_valid(unit):
		unit = battle.picked if battle.state == TacticsBattle.State.DEPLOY else battle.current
	_info.visible = battle.is_active() and unit != null and is_instance_valid(unit)
	if not _info.visible:
		return
	var text: String = unit.info_text()
	var kind: TacticsMap.Kind = battle.kind_at(battle.cell_of(unit))
	if kind != TacticsMap.Kind.PLAIN:
		text += "\n站在：%s" % TacticsMap.KIND_NAMES[kind]
	if unit == battle.focus:
		text += "\n★ 指定目標"
	if not battle.intent_text(unit).is_empty() and (unit != battle.current or not battle.is_waiting):
		text += "\n打算：" + battle.intent_text(unit)
	if battle.is_waiting and battle.target_units.has(unit):
		if unit.team == battle.current.team:
			text += "\n── 補血 +%d" % mini(battle.current.heal_power, unit.max_health - unit.health)
		else:
			var damage: int = battle.damage_of(battle.current, unit)
			text += "\n── 打下去 -%d%s" % [damage, "（打得倒）" if damage >= unit.health else ""]
			if battle.dice:
				text += "\n　骰 1 失手、骰 6 → -%d" % (damage * 2)
	_info_text.text = text


# ---- 布陣 ----

func _rebuild_deploy() -> void:
	for child: Node in _deploy_rows.get_children():
		_deploy_rows.remove_child(child)
		child.queue_free()
	for unit: Unit in battle.available:
		var check: CheckBox = CheckBox.new()
		check.focus_mode = Control.FOCUS_NONE
		check.add_theme_font_size_override("font_size", 18)
		check.set_meta("unit", unit)
		check.toggled.connect(func(on: bool) -> void:
			battle.set_deployed(unit, on)
			_update_deploy())
		check.mouse_entered.connect(func() -> void:
			battle.picked = unit if battle.fighters.has(unit) else null
			battle.hovered = null
			refresh()
			battle.queue_redraw())
		_deploy_rows.add_child(check)
	_update_deploy()


func _update_deploy() -> void:
	_deploy_title.text = "上場 %d／%d" % [battle.deployed().size(), battle.limit()]
	for unit: Unit in battle.late:
		_deploy_title.text += "\n%s %d 輪後趕到" % [unit.display_name, battle.late[unit] - 1]
	for child: Node in _deploy_rows.get_children():
		var check: CheckBox = child as CheckBox
		var unit: Unit = check.get_meta("unit")
		check.text = "%s　%d/%d%s" % [unit.display_name, unit.health, unit.max_health, "（被發現）" if unit == battle.anchor else ""]
		check.set_pressed_no_signal(battle.fighters.has(unit))
		check.disabled = unit == battle.anchor or (not battle.fighters.has(unit) and battle.deployed().size() >= battle.limit())


# ---- 按鈕 ----

func next_speed() -> void:
	var index: int = speeds.find(battle.game_speed)
	battle.game_speed = speeds[(index + 1) % speeds.size()]


# ---- 介面 ----

func _build() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.position = Vector2(22, 12)
	add_child(box)
	_title = _label(box, 33)
	_hint = _label(box, 14)
	_supply = _label(box, 18)
	_supply.add_theme_color_override("font_color", Color("f0d9a0"))

	_order = TacticsOrderBar.new()
	_order.position = Vector2(300, 0)
	add_child(_order)

	_message = _label(self, 33)
	_message.position = Vector2(0, 150)
	_message.size = Vector2(1280, 44)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_info = _panel(Vector2(22, 480), Vector2(250, 0))
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.anchor_top = 1.0
	_info.anchor_bottom = 1.0
	_info.offset_top = -22.0
	_info.offset_bottom = -22.0
	_info_text = Label.new()
	_info_text.add_theme_font_size_override("font_size", 16)
	_info.add_child(_info_text)

	_bar = HBoxContainer.new()
	_bar.position = Vector2(500, 664)
	_bar.add_theme_constant_override("separation", 8)
	add_child(_bar)
	_wait_button = _button(_bar, "待命", battle.choose_wait)
	_undo_button = _button(_bar, "反悔", battle.choose_undo)
	_auto_button = _button(_bar, "自動：開", func() -> void: battle.auto = not battle.auto)
	_auto_button.toggle_mode = true
	_paint_toggle(_auto_button)
	_speed_button = _button(_bar, "▶ 1×", next_speed)
	_pause_button = _button(_bar, "暫停", func() -> void: battle.paused = not battle.paused)
	_pause_button.toggle_mode = true
	_paint_toggle(_pause_button)

	_intent_button = _button(_bar, "意圖：開", func() -> void: battle.show_intents = not battle.show_intents)
	_intent_button.toggle_mode = true
	_paint_toggle(_intent_button)

	_log = _panel(Vector2(1000, 110), Vector2(258, 320))
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true                             # 有新的就捲到最下面；往上捲可以看舊的
	_log_text.focus_mode = Control.FOCUS_NONE
	_log_text.add_theme_font_size_override("normal_font_size", 14)
	_log_text.add_theme_font_size_override("bold_font_size", 14)
	_log.add_child(_log_text)
	_log_button = _button(self, "日誌", func() -> void: pass)
	_log_button.position = Vector2(1194, 72)
	_log_button.toggle_mode = true
	_log_button.toggled.connect(func(_on: bool) -> void: refresh())
	_log_button.pressed.connect(func() -> void: _log_closed = not _log_button.button_pressed)
	_paint_toggle(_log_button)

	_explore_bar = HBoxContainer.new()                            # 探索時左下角：隊員列、整隊／分開、陣形
	_explore_bar.position = Vector2(22, 648)
	_explore_bar.add_theme_constant_override("separation", 10)
	add_child(_explore_bar)
	_party_bar = TacticsPartyBar.new()
	_party_bar.party = party
	_explore_bar.add_child(_party_bar)
	_split_button = _button(_explore_bar, "", func() -> void:
		party.set_split(not party.split)
		refresh())
	_split_button.toggle_mode = true
	_split_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_paint_toggle(_split_button)
	_formation_button = _button(_explore_bar, "", func() -> void: party.set_formation((party.formation + 1) % TacticsFormation.NAMES.size()))
	_formation_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_deploy = _panel(Vector2(1000, 90), Vector2(258, 0))
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_deploy.add_child(rows)
	_deploy_title = _label(rows, 22)
	_deploy_rows = VBoxContainer.new()
	rows.add_child(_deploy_rows)
	rows.add_child(HSeparator.new())
	var modes: HBoxContainer = HBoxContainer.new()
	rows.add_child(modes)
	for text: String in ["自動", "回合制"]:
		var button: Button = _button(modes, text, func() -> void: battle.auto = text == "自動")
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_paint_toggle(button)
		_mode_buttons.append(button)
	_paint(_button(rows, "開始戰鬥", battle.begin_fight), Color("2f6fc4"))


## 整顆按鈕上色
func _paint(button: Button, color: Color) -> void:
	for state: Array in [["normal", color], ["hover", color.lightened(0.15)], ["pressed", color.darkened(0.2)], ["hover_pressed", color]]:
		button.add_theme_stylebox_override(state[0], _box(state[1]))


## 開關按鈕：開著的時候是藍色
func _paint_toggle(button: Button) -> void:
	for state: Array in [["normal", Color("2d2d2d")], ["hover", Color("444444")], ["pressed", Color("2f6fc4")], ["hover_pressed", Color("4a86d8")]]:
		button.add_theme_stylebox_override(state[0], _box(state[1]))


func _box(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


func _panel(at: Vector2, minimum: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.88)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = at
	panel.custom_minimum_size = minimum
	add_child(panel)
	return panel


func _label(parent: Node, font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(func() -> void: action.call())
	parent.add_child(button)
	return button
