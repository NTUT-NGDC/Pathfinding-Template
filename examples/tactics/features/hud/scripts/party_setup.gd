class_name TacticsPartySetup
extends CanvasLayer
## 出發前的編隊畫面：從可以選的人裡面挑隊伍、排順序、選一開始的陣形，按「出發」才開始玩。
## 規則頁取消「出發前讓玩家編隊」就不會出現。

## 按了出發
signal confirmed(units: Array[String], formation: int)

## 可以選的人（棋子場景，可以重複）
var roster: Array[String] = []
## 最多帶幾人（0＝全部都能帶）
var limit: int = 0
## 選了哪幾個（roster 的第幾個），順序＝隊伍順序
var chosen: Array[int] = []
var formation: TacticsFormation.Kind = TacticsFormation.Kind.COLUMN

var _units: Array[Unit] = []
var _roster_box: VBoxContainer
var _team_box: VBoxContainer
var _count: Label
var _preview: Control
var _formation_buttons: Array[Button] = []
var _go: Button


func _ready() -> void:
	layer = 22                                                    # 在 HUD（20）上面、暫停選單（30）下面
	for path: String in roster:
		_units.append((load(path) as PackedScene).instantiate() as Unit)
	_build()
	refresh()


func _exit_tree() -> void:
	for unit: Unit in _units:
		unit.free()
	_units.clear()


## 最多可以選幾個
func max_count() -> int:
	return mini(limit, roster.size()) if limit > 0 else roster.size()


## 先選好前面幾個
func choose_default() -> void:
	chosen.clear()
	for i: int in max_count():
		chosen.append(i)


## 選、取消選第 index 個
func toggle(index: int) -> void:
	if chosen.has(index):
		chosen.erase(index)
	elif chosen.size() < max_count():
		chosen.append(index)
	refresh()


## 隊伍裡的第 at 個往前（-1）或往後（1）移
func move(at: int, by: int) -> void:
	var to: int = at + by
	if to < 0 or to >= chosen.size():
		return
	var index: int = chosen[at]
	chosen.remove_at(at)
	chosen.insert(to, index)
	refresh()


func set_formation(kind: int) -> void:
	formation = kind as TacticsFormation.Kind
	refresh()


func go() -> void:
	if chosen.is_empty():
		return
	var result: Array[String] = []
	for index: int in chosen:
		result.append(roster[index])
	confirmed.emit(result, int(formation))


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode >= KEY_1 and key.physical_keycode < KEY_1 + TacticsFormation.NAMES.size():
		set_formation(key.physical_keycode - KEY_1)
		get_viewport().set_input_as_handled()


# ---- 介面 ----

func refresh() -> void:
	if _roster_box == null:
		return
	for box: Control in [_roster_box, _team_box]:
		for child: Node in box.get_children():
			box.remove_child(child)
			child.queue_free()
	for i: int in roster.size():
		_add_card(i)
	for i: int in chosen.size():
		_add_member(i)
	_count.text = "我的隊伍　%d／%d 人" % [chosen.size(), max_count()]
	for i: int in _formation_buttons.size():
		_formation_buttons[i].button_pressed = i == formation
	_go.disabled = chosen.is_empty()
	_preview.queue_redraw()


## 左邊：可以選的人
func _add_card(index: int) -> void:
	var unit: Unit = _units[index]
	var picked: bool = chosen.has(index)
	var card: Button = Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, 64)
	card.disabled = not picked and chosen.size() >= max_count()
	for state: Array in [["normal", Color("24508a") if picked else Color("2d2d32")], ["hover", Color("2f66b0") if picked else Color("3d3d44")], ["pressed", Color("1d4070")], ["disabled", Color("212125")]]:
		card.add_theme_stylebox_override(state[0], _box(state[1]))
	card.pressed.connect(toggle.bind(index))
	_roster_box.add_child(card)
	var token: Control = _token(unit, 22.0)
	token.position = Vector2(8, 8)
	card.add_child(token)
	var reach: String = str(unit.max_range) if unit.min_range == unit.max_range else "%d～%d" % [unit.min_range, unit.max_range]
	var names: PackedStringArray = PackedStringArray()
	for t: UnitTrait in unit.traits():
		names.append(t.trait_name())
	var dim: Color = Color(1, 1, 1, 0.45) if card.disabled else Color.WHITE
	_text(card, Vector2(68, 8), unit.display_name, 20, dim)
	_text(card, Vector2(180, 10), "血 %d　攻 %d　防 %d　移 %d　射程 %s　速度 %d" % [unit.max_health, unit.attack, unit.defense, unit.move_points, reach, unit.speed], 14, dim)
	_text(card, Vector2(180, 34), "特性：" + ("、".join(names) if not names.is_empty() else "無"), 14, dim * Color("f0d9a0"))
	if picked:
		_text(card, Vector2(68, 36), "第 %d 個" % (chosen.find(index) + 1), 14, Color("8ec0ff"))


## 右邊：已經選的
func _add_member(at: int) -> void:
	var unit: Unit = _units[chosen[at]]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_team_box.add_child(row)
	row.add_child(_token(unit, 16.0))
	var label: Label = Label.new()
	label.text = "%d　%s%s" % [at + 1, unit.display_name, "　★隊長（帶頭）" if at == 0 else ""]
	label.add_theme_font_size_override("font_size", 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_button(row, "▲", move.bind(at, -1)).disabled = at == 0
	_button(row, "▼", move.bind(at, 1)).disabled = at == chosen.size() - 1
	_button(row, "✕", toggle.bind(chosen[at]))


func _token(unit: Unit, radius: float) -> Control:
	var token: Control = Control.new()
	token.custom_minimum_size = Vector2(radius * 2.0 + 8.0, radius * 2.0 + 4.0)
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	token.draw.connect(func() -> void: Unit.draw_token(token, Vector2(radius + 3.0, radius + 1.0), radius, unit.color, Unit.TEAM_COLORS[0], unit.mark))
	return token


## 陣形預覽：往上是前進的方向
func _draw_preview() -> void:
	var size: Vector2 = _preview.size
	_preview.draw_rect(Rect2(Vector2.ZERO, size), Color("1b1b20"))
	var offsets: Array[Vector2] = []
	var bounds: Rect2 = Rect2()
	for i: int in chosen.size():
		offsets.append(TacticsFormation.offset(formation, i, chosen.size(), Vector2.UP, 40.0))
		bounds = bounds.expand(offsets[i])
	var fit: float = minf(minf((size.x - 60.0) / maxf(bounds.size.x, 1.0), (size.y - 80.0) / maxf(bounds.size.y, 1.0)), 1.0)
	var shift: Vector2 = size / 2.0 + Vector2(0, 10) - bounds.get_center() * fit
	var tip: Vector2 = Vector2(size.x / 2.0, 8)
	_preview.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(10, 14), tip + Vector2(-10, 14)]), Color(1, 1, 1, 0.5))
	for i: int in offsets.size():
		var unit: Unit = _units[chosen[i]]
		if i == 0:
			_preview.draw_circle(shift, 19.0, Color(1, 1, 0.5))
		Unit.draw_token(_preview, shift + offsets[i] * fit, 16.0 if fit > 0.8 else 12.0, unit.color, Unit.TEAM_COLORS[0], unit.mark)


func _build() -> void:
	var dark: ColorRect = ColorRect.new()
	dark.color = Color(0.06, 0.06, 0.08, 0.9)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE               # 右上角的「選單」還是可以按
	add_child(dark)
	_text(dark, Vector2(40, 20), "編隊", 33, Color.WHITE)
	_text(dark, Vector2(40, 70), "可以選的人（點一下加入，再點一次拿掉）", 18, Color("f0d9a0"))
	_roster_box = _scroll(dark, Rect2(40, 100, 620, 590))
	_count = _text(dark, Vector2(700, 70), "", 18, Color("f0d9a0"))
	_team_box = _scroll(dark, Rect2(700, 100, 540, 250))
	_text(dark, Vector2(700, 362), "陣形（1～4，玩的時候也可以換）", 18, Color("f0d9a0"))
	var row: HBoxContainer = HBoxContainer.new()
	row.position = Vector2(700, 392)
	dark.add_child(row)
	for i: int in TacticsFormation.NAMES.size():
		var button: Button = _button(row, "%d %s" % [i + 1, TacticsFormation.NAMES[i]], set_formation.bind(i))
		button.toggle_mode = true
		for state: Array in [["normal", Color("2d2d32")], ["hover", Color("3d3d44")], ["pressed", Color("2f6fc4")], ["hover_pressed", Color("4a86d8")]]:
			button.add_theme_stylebox_override(state[0], _box(state[1]))
		_formation_buttons.append(button)
	_preview = Control.new()
	_preview.position = Vector2(700, 436)
	_preview.size = Vector2(540, 190)
	_preview.draw.connect(_draw_preview)
	dark.add_child(_preview)
	_go = _button(dark, "出發", go)
	_go.position = Vector2(700, 640)
	_go.size = Vector2(540, 50)
	_go.add_theme_font_size_override("font_size", 24)
	for state: Array in [["normal", Color("2f6fc4")], ["hover", Color("4a86d8")], ["pressed", Color("24508a")], ["disabled", Color("2d2d32")]]:
		_go.add_theme_stylebox_override(state[0], _box(state[1]))


func _scroll(parent: Control, area: Rect2) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = area.position
	scroll.size = area.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func _text(parent: Control, at: Vector2, text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.position = at
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(func() -> void: action.call())
	parent.add_child(button)
	return button


func _box(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(5)
	box.set_content_margin_all(8)
	return box
