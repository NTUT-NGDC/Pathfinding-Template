extends Node2D
## 塔防地圖編輯器（開發者用）：打開 map_editor.tscn 按 F6。
##   ・下面第一排選要畫什麼：岩石（怪不能走、不能蓋）、沼澤（怪走得慢）、高地（怪不能走、可以蓋塔）、
##     出怪口、基地（出怪口、基地可以放好幾個）
##   ・畫地形可以選工具：畫筆、矩形、圓形（拖曳畫出形狀）、油漆桶（把相連的一整塊換掉）
##   ・左鍵畫（放）、右鍵擦（拿掉）；滾輪調筆刷大小
##   ・鏡頭：WASD／方向鍵、滑鼠到畫面邊緣、中鍵拖曳移動；Ctrl＋滾輪縮放
##   ・寬、高：改地圖大小（格數）
##   ・最下面一排：哪種地面可以蓋塔、可以蓋牆（迷宮型：空地、沼澤；固定路線型：塔只蓋高地、沒有牆）
##   ・Ctrl＋Z 上一步、Ctrl＋Y（或 Ctrl＋Shift＋Z）下一步
##   ・存檔：存成 maps/名稱.tres；讀檔：從清單選一張
##   ・試玩：就在編輯器裡直接玩這張地圖（不換場景），按「■ 停止試玩」（或暫停選單的「回地圖編輯器」）回來繼續畫
## 存檔是寫進專案資料夾，只有在 Godot 編輯器裡按 F6 才能存（匯出的遊戲不能存）。

## 地圖存在這個資料夾
const MAPS_DIR: String = "res://examples/tower_defense/maps/"
## 試玩用的關卡（波次、塔、規則都照這個關卡）
const LEVEL: PackedScene = preload("res://examples/tower_defense/levels/tower_defense.tscn")
## 地圖放在畫面的哪裡（跟關卡一樣）
const OFFSET: Vector2 = Vector2(64, 48)
const MIN_BRUSH: float = 8.0
const MAX_BRUSH: float = 120.0
## 上一步最多記幾步
const MAX_HISTORY: int = 50

enum Tool { ROCK, SWAMP, HIGH, SPAWN, BASE }
const TOOL_NAMES: Array[String] = ["岩石", "沼澤", "高地", "出怪口", "基地"]
## 畫地形的方式
enum Shape { BRUSH, RECT, ELLIPSE, FILL }
const SHAPE_NAMES: Array[String] = ["畫筆", "矩形", "圓形", "油漆桶"]

## 正在編輯的地圖（暫停選單按「重來」時場景會重新載入，地圖留著）
static var editing: TDMap
## 重新載入時要不要接著試玩（試玩中按了暫停選單的「重來」）
static var resume_test: bool = false

var map: TDMap
var tool: Tool = Tool.ROCK
var shape: Shape = Shape.BRUSH
var brush: float = 28.0

var _view: TerrainView
var _camera: PanCamera
## 試玩中的關卡（沒在試玩＝null）
var _play: Node
var _painting: bool = false
var _erasing: bool = false
var _last_paint: Vector2
## 矩形、圓形：拖曳的起點（沒在拖＝null）
var _drag_from: Variant = null
var _tool_buttons: Array[Button] = []
var _shape_buttons: Array[Button] = []
var _name_edit: LineEdit
var _load_list: OptionButton
var _width: SpinBox
var _height: SpinBox
## 哪種地面可以蓋塔、蓋牆的勾選（照 TDMap.Ground 的順序）
var _tower_checks: Array[CheckBox] = []
var _wall_checks: Array[CheckBox] = []
## 上一步、下一步：每一步之前地圖的樣子（TDMap.snapshot()）
var _history: Array[Dictionary] = []
var _future: Array[Dictionary] = []
var _status: Label
var _ui: CanvasLayer
var _stop_button: Button
var _status_text: String = ""


func _ready() -> void:
	Engine.time_scale = 1.0
	map = editing if editing != null else _new_map()
	map.ensure()
	editing = map
	_view = TerrainView.new()
	_view.name = "Terrain"
	_view.draw_floor = true
	_view.position = OFFSET
	_view.show_behind_parent = true                               # 地形畫在下面，出怪口、基地、筆刷畫在上面
	_view.map = map
	add_child(_view)
	_camera = (load("res://core/camera/pan_camera.tscn") as PackedScene).instantiate()
	_camera.zoom_modifier = 1                                     # Ctrl＋滾輪縮放；滾輪留給筆刷
	add_child(_camera)
	_build_ui()
	_refresh_maps()
	_show_map()
	_set_tool(Tool.ROCK)
	_set_shape(Shape.BRUSH)
	_say("左鍵畫、右鍵擦、滾輪調筆刷大小、Ctrl＋滾輪縮放")
	GameFlow.set_pause_enabled(false)                             # 編輯時不要暫停選單（試玩時才有）
	if resume_test:
		start_test.call_deferred()


func _exit_tree() -> void:
	GameFlow.set_pause_enabled(true)
	GameFlow.reset_title_button()


func _new_map() -> TDMap:
	var fresh: TDMap = TDMap.new()
	fresh.ensure()
	return fresh


## 換了地圖（讀檔、新地圖、改大小）：更新名稱、寬高、鏡頭邊界
func _show_map() -> void:
	_view.map = map
	_name_edit.text = map.map_name
	_width.set_value_no_signal(map.size.x)
	_height.set_value_no_signal(map.size.y)
	for i: int in TDMap.GROUND_NAMES.size():
		_tower_checks[i].set_pressed_no_signal(TDMap.has_ground(map.tower_ground, i as TDMap.Ground))
		_wall_checks[i].set_pressed_no_signal(TDMap.has_ground(map.wall_ground, i as TDMap.Ground))
	var area: Rect2 = Rect2(OFFSET, Vector2(map.size * TDMap.CELL)).grow_individual(64, 48, 64, 128)
	_camera.set_limit_rect(area)
	queue_redraw()


# ---- 滑鼠 ----

func _unhandled_input(event: InputEvent) -> void:
	if is_testing():
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.is_command_or_control_pressed():
		if key.keycode == KEY_Z and not key.shift_pressed:
			undo()
		elif key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed):
			redo()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		if button.ctrl_pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			return                                                # Ctrl＋滾輪是鏡頭縮放
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush = minf(brush + 4.0, MAX_BRUSH)
			_say()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush = maxf(brush - 4.0, MIN_BRUSH)
			_say()
		elif button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT:
			var at: Vector2 = map_position(button.position)
			if button.pressed:
				_press(at, button.button_index == MOUSE_BUTTON_RIGHT)
			else:
				_release(at)
		queue_redraw()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if _painting:
			_stroke(map_position(motion.position))
		queue_redraw()


## 螢幕座標 → 地圖裡的座標
func map_position(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen - OFFSET


func _is_terrain_tool() -> bool:
	return tool == Tool.ROCK or tool == Tool.SWAMP or tool == Tool.HIGH


func _kind() -> TDMap.Kind:
	match tool:
		Tool.SWAMP: return TDMap.Kind.SWAMP
		Tool.HIGH: return TDMap.Kind.HIGH
	return TDMap.Kind.ROCK


func _press(at: Vector2, erase: bool) -> void:
	if not _is_terrain_tool():
		if erase:
			unplace(tool, map.cell_at(at))
		else:
			place(tool, map.cell_at(at))
		return
	_erasing = erase
	match shape:
		Shape.BRUSH:
			remember()                                            # 一筆＝一步
			_painting = true
			_last_paint = at
			paint_at(at, erase)
		Shape.RECT, Shape.ELLIPSE:
			_drag_from = at
		Shape.FILL:
			fill_at(at, erase)


func _release(at: Vector2) -> void:
	_painting = false
	if _drag_from == null:
		return
	var rect: Rect2 = Rect2(_drag_from, at - (_drag_from as Vector2)).abs()
	_drag_from = null
	remember()
	if shape == Shape.RECT:
		map.paint_rect(_kind(), rect, _erasing)
	else:
		map.paint_ellipse(_kind(), rect, _erasing)


## 拖曳：每隔一小段蓋一個圓，線才會連續
func _stroke(at: Vector2) -> void:
	var distance: float = _last_paint.distance_to(at)
	var spacing: float = maxf(brush * 0.3, 2.0)
	var steps: int = ceili(distance / spacing)
	for i: int in range(1, steps + 1):
		paint_at(_last_paint.lerp(at, float(i) / steps), _erasing)
	if steps > 0:
		_last_paint = at


## 在 at 畫（或擦）一筆
func paint_at(at: Vector2, erase: bool = false) -> void:
	map.paint(_kind(), at, brush, erase)


## 油漆桶：把 at 那一整塊相連的地形換掉（erase：那一塊是現在選的地形才擦掉）
func fill_at(at: Vector2, erase: bool = false) -> int:
	remember()
	var count: int = map.fill(_kind(), at, erase)
	if count == 0:
		_history.pop_back()                                       # 什麼都沒塗：這一步不算
		_say("那一塊已經是%s了" % TOOL_NAMES[tool] if not erase else "那裡不是%s" % TOOL_NAMES[tool])
	return count


## 在某一格多放一個出怪口或基地（那一格已經有就不放）
func place(what: Tool, cell: Vector2i) -> bool:
	if not map.has_cell(cell) or map.spawn_cells.has(cell) or map.base_cells.has(cell):
		return false
	remember()
	if what == Tool.SPAWN:
		map.spawn_cells.append(cell)
	else:
		map.base_cells.append(cell)
	queue_redraw()
	return true


## 拿掉某一格的出怪口或基地
func unplace(what: Tool, cell: Vector2i) -> bool:
	var list: Array[Vector2i] = map.spawn_cells if what == Tool.SPAWN else map.base_cells
	if not list.has(cell):
		return false
	remember()
	list.erase(cell)
	queue_redraw()
	return true


## 改地圖大小（格數）
func resize_map(new_size: Vector2i) -> void:
	if new_size.max(Vector2i(4, 4)) == map.size:
		return
	remember()
	map.resize(new_size)
	_show_map()
	_say("地圖大小 %d×%d 格" % [map.size.x, map.size.y])


## 清空地形
func clear_terrain() -> void:
	remember()
	map.clear()


## 改「哪種地面可以蓋塔／蓋牆」（walls＝改牆的；on＝勾起來）
func set_ground_rule(walls: bool, which: TDMap.Ground, on: bool) -> void:
	remember()
	var bit: int = 1 << which
	if walls:
		map.wall_ground = (map.wall_ground | bit) if on else (map.wall_ground & ~bit)
	else:
		map.tower_ground = (map.tower_ground | bit) if on else (map.tower_ground & ~bit)
	_show_map()


# ---- 上一步、下一步 ----

## 改地圖之前呼叫：記住現在的樣子（下一步的紀錄清掉）
func remember() -> void:
	_history.append(map.snapshot())
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_future.clear()


## 上一步（Ctrl＋Z）
func undo() -> bool:
	if _history.is_empty():
		_say("沒有上一步了")
		return false
	_future.append(map.snapshot())
	map.restore(_history.pop_back())
	_show_map()
	_say("上一步（還可以退 %d 步）" % _history.size())
	return true


## 下一步（Ctrl＋Y）
func redo() -> bool:
	if _future.is_empty():
		_say("沒有下一步了")
		return false
	_history.append(map.snapshot())
	map.restore(_future.pop_back())
	_show_map()
	_say("下一步")
	return true


## 換了一張地圖（讀檔、新地圖）：上一步的紀錄清掉
func _forget() -> void:
	_history.clear()
	_future.clear()


## 少了出怪口或基地就不能玩（回傳問題，沒問題＝空字串）
func check_map() -> String:
	if map.spawn_cells.is_empty():
		return "至少要放一個出怪口"
	if map.base_cells.is_empty():
		return "至少要放一個基地"
	return ""


func _process(_delta: float) -> void:
	if not is_testing():
		queue_redraw()                                            # 筆刷圓跟著滑鼠


func _draw() -> void:
	if is_testing():
		return
	# 出怪口、基地（好幾個的話標上號碼）
	for i: int in map.spawn_cells.size():
		_draw_marker(map.spawn_cells[i], Color(0.9, 0.3, 0.3), "出怪口" if map.spawn_cells.size() == 1 else "出怪口%d" % (i + 1))
	for i: int in map.base_cells.size():
		_draw_marker(map.base_cells[i], Color("4ab86a"), "基地" if map.base_cells.size() == 1 else "基地%d" % (i + 1))
	# 滑鼠：筆刷的圓、拖曳中的形狀、要放的格子
	var at: Vector2 = map_position(get_viewport().get_mouse_position())
	var white: Color = Color(1, 1, 1, 0.8)
	if not _is_terrain_tool():
		if map.has_cell(map.cell_at(at)):
			draw_rect(Rect2(OFFSET + Vector2(map.cell_at(at) * TDMap.CELL), Vector2(TDMap.CELL, TDMap.CELL)), Color(1, 1, 1, 0.3))
		return
	match shape:
		Shape.BRUSH:
			draw_arc(OFFSET + at, brush, 0.0, TAU, 48, white, 2.0)
		Shape.RECT, Shape.ELLIPSE:
			if _drag_from == null:
				draw_line(OFFSET + at - Vector2(8, 0), OFFSET + at + Vector2(8, 0), white, 2.0)
				draw_line(OFFSET + at - Vector2(0, 8), OFFSET + at + Vector2(0, 8), white, 2.0)
				return
			var rect: Rect2 = Rect2(_drag_from, at - (_drag_from as Vector2)).abs()
			rect.position += OFFSET
			if shape == Shape.RECT:
				draw_rect(rect, white, false, 2.0)
			else:
				_draw_ellipse(rect, white)
		Shape.FILL:
			draw_rect(Rect2(OFFSET + at - Vector2(6, 2), Vector2(12, 10)), white, false, 2.0)   # 小桶子
			draw_line(OFFSET + at + Vector2(-6, 2), OFFSET + at + Vector2(-10, -4), white, 2.0)


func _draw_ellipse(rect: Rect2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 49:
		points.append(rect.get_center() + Vector2.from_angle(TAU * i / 48.0) * rect.size / 2.0)
	draw_polyline(points, color, 2.0)


func _draw_marker(cell: Vector2i, color: Color, text: String) -> void:
	var center: Vector2 = OFFSET + map.cell_center(cell)
	draw_rect(Rect2(center - Vector2(14, 14), Vector2(28, 28)), color, false, 3.0)
	draw_circle(center, 5.0, color)
	draw_string(get_window().get_theme_default_font(), center + Vector2(-24, -20), text, HORIZONTAL_ALIGNMENT_CENTER, 48, 12, color)


# ---- 試玩 ----

## 正在試玩嗎
func is_testing() -> bool:
	return _play != null and is_instance_valid(_play)


## 開始試玩：在編輯器裡放一個塔防關卡，用這張地圖
func start_test() -> bool:
	if is_testing():
		return false
	if not check_map().is_empty():
		_say(check_map() + "才能試玩")
		resume_test = false
		return false
	map.map_name = _name_edit.text.strip_edges()                  # 還沒存檔也記住名字
	MapLoader.test_map = map.duplicate(true) as TDMap
	_play = LEVEL.instantiate()
	add_child(_play)
	resume_test = true                                            # 暫停選單按「重來」：重新載入後接著試玩
	GameFlow.set_title_button("回地圖編輯器", stop_test)           # 暫停選單、勝敗畫面的「回標題」換成回來編輯
	_set_editing(false)
	return true


## 停止試玩：拿掉關卡，回到編輯
func stop_test() -> void:
	resume_test = false
	GameFlow.reset_title_button()
	if is_testing():
		_play.queue_free()
	_play = null
	Engine.time_scale = 1.0
	get_tree().paused = false
	for child: Node in GameFlow.get_children():
		if child.scene_file_path.ends_with("result_screen.tscn"):
			child.queue_free()                                    # 試玩中贏了或輸了：關掉勝敗畫面
	_camera.make_current()
	_set_editing(true)


func _set_editing(on: bool) -> void:
	GameFlow.set_pause_enabled(not on)                            # 編輯時不要暫停選單（試玩時才有）
	_view.visible = on
	_ui.visible = on
	_camera.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	_stop_button.visible = not on
	queue_redraw()


# ---- 存檔、讀檔 ----

## 存成 maps/名稱.tres。回傳存到哪裡（失敗＝空字串）
func save_map() -> String:
	var map_name: String = _name_edit.text.strip_edges()
	if map_name.is_empty():
		_say("先打地圖名稱")
		return ""
	if not check_map().is_empty():
		_say(check_map() + "才能存檔")
		return ""
	map.map_name = map_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAPS_DIR))
	var path: String = MAPS_DIR + map_name.validate_filename() + ".tres"
	var error: Error = ResourceSaver.save(map, path)
	if error != OK:
		_say("存檔失敗：%s（匯出的遊戲不能存，要在 Godot 編輯器裡按 F6）" % error_string(error))
		return ""
	map.take_over_path(path)
	_refresh_maps()
	_say("存好了：%s" % path)
	return path


## 讀 maps/ 裡的一張地圖
func load_map(path: String) -> bool:
	var loaded: TDMap = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TDMap
	if loaded == null:
		_say("讀不到：%s" % path)
		return false
	map = loaded
	map.ensure()
	editing = map
	_forget()
	_show_map()
	_load_list.select(0)                                          # 清單回到「讀檔…」，同一張也能再讀一次
	_say("讀進來了：%s" % path)
	return true


## maps/ 裡有哪些地圖
func map_files() -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		return files
	for file: String in DirAccess.get_files_at(MAPS_DIR):
		if file.ends_with(".tres"):
			files.append(MAPS_DIR + file)
	return files


func _new() -> void:
	map = _new_map()
	editing = map
	_forget()
	_show_map()
	_say("新地圖")


# ---- 介面 ----

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)
	var row: HBoxContainer = _row(Vector2(64, 594))
	for i: int in TOOL_NAMES.size():
		_tool_buttons.append(_toggle(row, TOOL_NAMES[i], _set_tool.bind(i)))
	row.add_child(VSeparator.new())
	for i: int in SHAPE_NAMES.size():
		_shape_buttons.append(_toggle(row, SHAPE_NAMES[i], _set_shape.bind(i)))
	row.add_child(VSeparator.new())
	_width = _size_box(row, "寬")
	_height = _size_box(row, "高")
	row = _row(Vector2(64, 628))                                  # 第二排：上一步、檔案、試玩
	_button(row, "↶", undo).tooltip_text = "上一步（Ctrl＋Z）"
	_button(row, "↷", redo).tooltip_text = "下一步（Ctrl＋Y）"
	row.add_child(VSeparator.new())
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "地圖名稱"
	_name_edit.custom_minimum_size = Vector2(160, 0)
	row.add_child(_name_edit)
	_button(row, "存檔", save_map)
	_load_list = OptionButton.new()
	_load_list.custom_minimum_size = Vector2(160, 0)
	_load_list.item_selected.connect(func(index: int) -> void: load_map(_load_list.get_item_metadata(index)))
	row.add_child(_load_list)
	_button(row, "新地圖", _new)
	_button(row, "清空地形", clear_terrain)
	row.add_child(VSeparator.new())
	_button(row, "▶ 試玩", start_test)
	row = _row(Vector2(64, 662))                                  # 第三排：哪種地面可以蓋塔、蓋牆
	_tower_checks = _ground_checks(row, "塔可以蓋在：", false)
	row.add_child(VSeparator.new())
	_wall_checks = _ground_checks(row, "牆可以蓋在：", true)
	_status = Label.new()
	_status.position = Vector2(64, 697)
	_status.add_theme_font_size_override("font_size", 14)
	_ui.add_child(_status)
	var title: Label = Label.new()
	title.text = "塔防地圖編輯器"
	title.position = Vector2(64, 10)
	title.add_theme_font_size_override("font_size", 22)
	_ui.add_child(title)
	# 試玩時才出現的「停止試玩」（另一層，編輯的介面藏起來時它還在）
	var top: CanvasLayer = CanvasLayer.new()
	top.layer = 25                                                # 在 HUD（20）上面、暫停選單（30）下面
	add_child(top)
	_stop_button = Button.new()
	_stop_button.name = "StopTest"
	_stop_button.text = "■ 停止試玩"
	_stop_button.focus_mode = Control.FOCUS_NONE
	_stop_button.position = Vector2(940, 22)
	_stop_button.visible = false
	_stop_button.pressed.connect(stop_test)
	top.add_child(_stop_button)


func _row(at: Vector2) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.position = at
	row.add_theme_constant_override("separation", 6)
	_ui.add_child(row)
	return row


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE                        # 不要搶鍵盤（打地圖名稱時才不會亂）
	button.pressed.connect(func() -> void: action.call())
	parent.add_child(button)
	return button


func _toggle(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = _button(parent, text, action)
	button.toggle_mode = true
	return button


## 一排地面勾選：空地、沼澤、高地、岩石（walls＝牆的，否則是塔的）
func _ground_checks(parent: Control, text: String, walls: bool) -> Array[CheckBox]:
	var label: Label = Label.new()
	label.text = text
	parent.add_child(label)
	var checks: Array[CheckBox] = []
	for i: int in TDMap.GROUND_NAMES.size():
		var check: CheckBox = CheckBox.new()
		check.text = TDMap.GROUND_NAMES[i]
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(func(on: bool) -> void: set_ground_rule(walls, i as TDMap.Ground, on))
		parent.add_child(check)
		checks.append(check)
	return checks


## 寬、高的數字框
func _size_box(parent: Control, text: String) -> SpinBox:
	var label: Label = Label.new()
	label.text = text
	parent.add_child(label)
	var box: SpinBox = SpinBox.new()
	box.min_value = 4
	box.max_value = 200
	box.suffix = "格"
	box.custom_minimum_size = Vector2(96, 0)
	box.value_changed.connect(func(_value: float) -> void: resize_map(Vector2i(int(_width.value), int(_height.value))))
	parent.add_child(box)
	return box


func _set_tool(value: int) -> void:
	tool = value as Tool
	for i: int in _tool_buttons.size():
		_tool_buttons[i].button_pressed = i == value
	for button: Button in _shape_buttons:
		button.disabled = not _is_terrain_tool()                  # 出怪口、基地不用選形狀
	_say()


func _set_shape(value: int) -> void:
	shape = value as Shape
	for i: int in _shape_buttons.size():
		_shape_buttons[i].button_pressed = i == value
	_say()


func _refresh_maps() -> void:
	_load_list.clear()
	_load_list.add_item("讀檔…")
	_load_list.set_item_disabled(0, true)
	for path: String in map_files():
		_load_list.add_item(path.get_file().get_basename())
		_load_list.set_item_metadata(_load_list.item_count - 1, path)
	_load_list.select(0)


## 下面那行狀態：現在的工具、筆刷大小、最後一個訊息
func _say(text: String = "") -> void:
	if not text.is_empty():
		_status_text = text
	if _status == null:
		return
	var what: String = TOOL_NAMES[tool] + ("（%s）" % SHAPE_NAMES[shape] if _is_terrain_tool() else "")
	_status.text = "%s　｜　筆刷 %d px　｜　%s" % [what, int(brush), _status_text]
