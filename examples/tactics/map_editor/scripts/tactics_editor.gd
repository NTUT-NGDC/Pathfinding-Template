extends Node2D
## 戰棋編輯器（開發者用）：打開 map_editor.tscn 按 F6。上面五頁：
##   ・地圖：畫地形（圓滑的或對齊格子）、放起點／目標／物資／寶箱／同伴／敵人／巡邏點
##   ・小隊：每一隊的視野、反應時間、巡邏、支援、掉落物資、首領（squad_page.gd）
##   ・棋子：改數值、個性，勾特性（unit_page.gd），存成 features/units/ 的場景
##   ・隊伍：玩家的起始隊伍（pool_page.gd），存成 party_pool.tres，每一關共用
##   ・規則：這一關固定的隊伍、過關獎勵、勝利條件、自動或回合制、陣形、分開走、骰子、營地物資（rule_page.gd）
## 地圖、小隊、規則存在同一個檔案 maps/名稱.tres；棋子各自一個場景。
## 「做成關卡」：把存好的地圖做成一個關卡場景（level_maker.gd），再拖進 game_config.tres 的 Levels 就能串關。
##
## 地圖頁：畫筆、矩形、圓形、油漆桶，打開「對齊格子」就一格一格畫（兩種可以混用）。規則看格子中心在哪種地形裡。
## 左鍵畫（放）、右鍵擦（拿掉）、滾輪調筆刷；WASD／滑鼠到邊緣／中鍵移動畫面、Ctrl＋滾輪縮放；
## Ctrl＋Z 上一步、Ctrl＋Y 下一步。
## 存檔是寫進專案資料夾，只有在 Godot 編輯器裡按 F6 才能存（匯出的遊戲不能存）。

## 地圖存在這個資料夾
const MAPS_DIR: String = "res://examples/tactics/maps/"
## 試玩用的關卡
const LEVEL: PackedScene = preload("res://examples/tactics/levels/tactics.tscn")
## 地圖放在畫面的哪裡
const OFFSET: Vector2 = Vector2(64, 48)
const MIN_BRUSH: float = 8.0
const MAX_BRUSH: float = 144.0
## 上一步最多記幾步
const MAX_HISTORY: int = 60

enum Page { MAP, SQUADS, UNITS, RULES, POOL }
const PAGE_NAMES: Array[String] = ["地圖", "小隊", "棋子", "規則", "隊伍"]
## 前五個是地形（順序跟 TacticsMap.Kind 一樣）
enum Tool { PLAIN, WALL, SWAMP, FOREST, HIGH, START, GOAL, SUPPLY, CHEST, ALLY, ENEMY, PATROL }
const TOOL_NAMES: Array[String] = ["空地", "牆", "沼澤", "森林", "高地", "起點", "目標", "物資", "寶箱", "同伴", "敵人", "巡邏點"]
enum Shape { BRUSH, RECT, ELLIPSE, FILL }
const SHAPE_NAMES: Array[String] = ["畫筆", "矩形", "圓形", "油漆桶"]
## 小隊的顏色（輪流用）
const SQUAD_COLORS: Array[Color] = [Color("e0574a"), Color("e09a3a"), Color("b05ad0"), Color("3aa0b0"), Color("d05a90"), Color("8a8a3a")]

## 正在編輯的地圖（暫停選單按「重來」時場景會重新載入，地圖留著）
static var editing: TacticsMap
## 重新載入時要不要接著試玩
static var resume_test: bool = false
## 上次存檔（讀檔、新地圖）時的樣子
static var saved_state: Dictionary = {}
static var saved_name: String = ""
static var page: Page = Page.MAP
## 對齊格子畫（關掉＝圓滑的）
static var snap: bool = false

var map: TacticsMap
var tool: Tool = Tool.WALL
var shape: Shape = Shape.BRUSH
## 筆刷半徑（像素）
var brush: float = 28.0
## 寶箱裡放幾份物資
var chest_amount: int = 1
## 敵人工具放哪一種棋子
var unit_path: String = ""

var _view: TacticsTerrain
var _overlay: Node2D
var _camera: PanCamera
var _play: Node
var _painting: bool = false
var _erasing: bool = false
var _last_paint: Vector2
## 矩形、圓形：拖曳的起點（沒在拖＝null）
var _drag_from: Variant = null
var _history: Array[Dictionary] = []
var _future: Array[Dictionary] = []
var _tool_buttons: Array[Button] = []
var _shape_buttons: Array[Button] = []
var _page_buttons: Array[Button] = []
var _name_edit: LineEdit
var _load_list: OptionButton
var _width: SpinBox
var _height: SpinBox
var _snap_button: Button
var _chest_box: SpinBox
var _squad_list: OptionButton
var _unit_list: OptionButton
var _unit_paths: PackedStringArray = PackedStringArray()
var _status: Label
var _status_text: String = ""
var _ui: CanvasLayer
var _map_tools: Control
var _squad_page: TacticsSquadPage
var _unit_page: TacticsUnitPage
var _rule_page: TacticsRulePage
var _pool_page: TacticsPoolPage
var _top_save: Button
var _stop_button: Button
var _check_time: float = 0.0
var _camera_tween: Tween


func _ready() -> void:
	Engine.time_scale = 1.0
	map = editing if editing != null else _new_map()
	map.ensure()
	if editing == null:
		_mark_saved()
	editing = map
	_view = TacticsTerrain.new()
	_view.name = "Terrain"
	_view.position = OFFSET
	_view.map = map
	add_child(_view)
	_overlay = Node2D.new()                                       # 棋子、路線、筆刷畫在地形上面
	_overlay.position = OFFSET
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_camera = (load("res://core/camera/pan_camera.tscn") as PackedScene).instantiate()
	_camera.zoom_modifier = 1                                     # Ctrl＋滾輪縮放；滾輪留給筆刷
	add_child(_camera)
	_build_ui()
	_refresh_maps()
	_show_map()
	_set_tool(Tool.WALL)
	_set_shape(Shape.BRUSH)
	GameFlow.set_pause_enabled(false)                             # 編輯時不要暫停選單（試玩時才有）
	set_page(page)
	if resume_test:
		start_test.call_deferred()


func _exit_tree() -> void:
	TacticsPool.end_test()
	GameFlow.set_pause_enabled(true)
	GameFlow.reset_title_button()


## 新地圖：外面一圈牆（隊伍用玩家的隊伍池）
func _new_map() -> TacticsMap:
	var fresh: TacticsMap = TacticsMap.new()
	fresh.ensure()
	fresh.paint_cells(TacticsMap.Kind.WALL, Rect2i(Vector2i.ZERO, fresh.size))
	fresh.paint_cells(TacticsMap.Kind.PLAIN, Rect2i(Vector2i.ONE, fresh.size - Vector2i(2, 2)))
	return fresh


## 換了地圖（讀檔、新地圖、上一步……）：更新所有畫面
func _show_map() -> void:
	_view.map = map
	_name_edit.text = map.map_name
	_width.set_value_no_signal(map.size.x)
	_height.set_value_no_signal(map.size.y)
	var area: Rect2 = Rect2(OFFSET, Vector2(map.size * TacticsMap.CELL)).grow_individual(64, 48, 64, 160)
	_camera.set_limit_rect(area)
	_squad_page.map = map
	_rule_page.map = map
	_refresh_pages()
	if page == Page.SQUADS:
		look_at_squad()


func _refresh_pages() -> void:
	_pool_page.refresh()
	_squad_page.refresh()
	_rule_page.refresh()
	_refresh_squads()
	_view.queue_redraw()


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
	if page != Page.MAP:
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
			if button.pressed:
				press(_mouse(), button.button_index == MOUSE_BUTTON_RIGHT)
			else:
				release(_mouse())
		return
	if event is InputEventMouseMotion and _painting:
		_stroke(_mouse())


## 滑鼠在地圖裡的哪裡（像素座標）
func _mouse() -> Vector2:
	return _overlay.get_local_mouse_position()


func _is_terrain_tool() -> bool:
	return tool <= Tool.HIGH


## 現在畫的地形（右鍵＝擦成空地）
func _kind() -> TacticsMap.Kind:
	return TacticsMap.Kind.PLAIN if _erasing else tool as TacticsMap.Kind


## 按下去（at＝地圖裡的像素座標）
func press(at: Vector2, erase: bool) -> void:
	_erasing = erase
	if not _is_terrain_tool():
		if erase:
			unplace(map.cell_at(at))
		else:
			place(map.cell_at(at))
		return
	match shape:
		Shape.BRUSH:
			remember()                                            # 一筆＝一步
			_painting = true
			_last_paint = at
			_dab(at)
		Shape.RECT, Shape.ELLIPSE:
			_drag_from = at
		Shape.FILL:
			remember()
			if map.fill(_kind(), at) == 0:
				_history.pop_back()                               # 什麼都沒換：這一步不算


## 放開
func release(at: Vector2) -> void:
	_painting = false
	if _drag_from == null:
		return
	var from: Vector2 = _drag_from
	_drag_from = null
	remember()
	if snap and shape == Shape.RECT:
		map.paint_cells(_kind(), _cells_of(from, at))
	elif snap:
		map.paint_cell_ellipse(_kind(), _cells_of(from, at))
	elif shape == Shape.RECT:
		map.paint_rect(_kind(), Rect2(from, at - from))
	else:
		map.paint_ellipse(_kind(), Rect2(from, at - from))


## 兩個位置圍起來的格子
func _cells_of(a: Vector2, b: Vector2) -> Rect2i:
	var from: Vector2i = map.cell_at(a)
	var to: Vector2i = map.cell_at(b)
	return Rect2i(from.min(to), (from - to).abs() + Vector2i.ONE)


## 筆刷蓋到的格子（對齊格子時）
func _brush_cells(at: Vector2) -> Rect2i:
	var count: int = maxi(roundi(brush * 2.0 / TacticsMap.CELL), 1)
	var corner: Vector2i = map.cell_at(at - Vector2.ONE * (count - 1) * TacticsMap.CELL / 2.0)
	return Rect2i(corner, Vector2i(count, count))


## 畫一下
func _dab(at: Vector2) -> void:
	if snap:
		map.paint_cells(_kind(), _brush_cells(at))
	else:
		map.paint(_kind(), at, brush)


## 拖曳：每隔一小段畫一下，線才會連續
func _stroke(at: Vector2) -> void:
	var spacing: float = TacticsMap.CELL / 2.0 if snap else maxf(brush * 0.3, 2.0)
	var steps: int = ceili(_last_paint.distance_to(at) / spacing)
	for i: int in range(1, steps + 1):
		_dab(_last_paint.lerp(at, float(i) / steps))
	if steps > 0:
		_last_paint = at


## 放東西（起點、目標、物資、敵人、巡邏點）。回傳有沒有放成功
func place(cell: Vector2i) -> bool:
	if not map.has_cell(cell):
		return false
	if map.kind_at(cell) == TacticsMap.Kind.WALL:
		_say("牆上不能放")
		return false
	match tool:
		Tool.START:
			if map.start_cell == cell:
				return false
			remember()
			map.start_cell = cell
		Tool.GOAL, Tool.SUPPLY:
			var list: Array[Vector2i] = map.goal_cells if tool == Tool.GOAL else map.supply_cells
			if list.has(cell):
				return false
			remember()
			list.append(cell)
		Tool.CHEST:
			if map.chests.get(cell, -1) == chest_amount:
				return false
			remember()
			map.chests[cell] = chest_amount                       # 點已經有的寶箱＝改成現在的份數
		Tool.ALLY:
			if map.allies.get(cell, "") == unit_path:
				return false
			remember()
			map.allies[cell] = unit_path                          # 點已經有的同伴＝換成現在選的棋子
		Tool.ENEMY:
			if map.enemy_at(cell).x >= 0:
				_say("那一格已經有敵人了（右鍵拿掉）")
				return false
			remember()
			_ensure_squad().add(unit_path, cell)
		Tool.PATROL:
			var squad: TacticsSquad = _squad_page.squad()
			if squad == null or squad.members.is_empty():
				_say("先用「敵人」放這一隊的隊員，再放巡邏點")
				return false
			remember()
			squad.patrol.append(cell)
	map.emit_changed()
	_refresh_pages()
	return true


## 拿掉 cell 上的東西（看現在的工具）
func unplace(cell: Vector2i) -> bool:
	match tool:
		Tool.GOAL, Tool.SUPPLY:
			var list: Array[Vector2i] = map.goal_cells if tool == Tool.GOAL else map.supply_cells
			if not list.has(cell):
				return false
			remember()
			list.erase(cell)
		Tool.CHEST:
			if not map.chests.has(cell):
				return false
			remember()
			map.chests.erase(cell)
		Tool.ALLY:
			if not map.allies.has(cell):
				return false
			remember()
			map.allies.erase(cell)
		Tool.ENEMY:
			var found: Vector2i = map.enemy_at(cell)
			if found.x < 0:
				return false
			remember()
			map.squads[found.x].remove_at(found.y)
		Tool.PATROL:
			var squad: TacticsSquad = _squad_page.squad()
			if squad == null or not squad.patrol.has(cell):
				return false
			remember()
			squad.patrol.remove_at(squad.patrol.rfind(cell))
		_:
			return false
	map.emit_changed()
	_refresh_pages()
	return true


## 現在選的小隊（一隊都沒有就新增一隊）
func _ensure_squad() -> TacticsSquad:
	if _squad_page.squad() == null:
		var fresh: TacticsSquad = TacticsSquad.new()
		fresh.squad_name = "小隊1"
		map.squads.append(fresh)
		_squad_page.index = map.squads.size() - 1
	return _squad_page.squad()


## 改地圖大小（格數）
func resize_map(to: Vector2i) -> void:
	if to.max(Vector2i(8, 6)) == map.size:
		return
	remember()
	map.resize(to)
	_show_map()
	_say("地圖大小 %d×%d 格" % [map.size.x, map.size.y])


# ---- 上一步、下一步 ----

## 改地圖之前呼叫：記住現在的樣子（下一步的紀錄清掉）
func remember() -> void:
	_history.append(map.snapshot())
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_future.clear()


func undo() -> bool:
	if page == Page.UNITS:
		return _unit_page.undo()
	if _history.is_empty():
		_say("沒有上一步了")
		return false
	_future.append(map.snapshot())
	map.restore(_history.pop_back())
	_show_map()
	_say("上一步（還可以退 %d 步）" % _history.size())
	return true


func redo() -> bool:
	if page == Page.UNITS:
		return _unit_page.redo()
	if _future.is_empty():
		_say("沒有下一步了")
		return false
	_history.append(map.snapshot())
	map.restore(_future.pop_back())
	_show_map()
	_say("下一步")
	return true


func _forget() -> void:
	_history.clear()
	_future.clear()


func _process(delta: float) -> void:
	if is_testing():
		return
	_overlay.queue_redraw()                                       # 筆刷跟著滑鼠
	_check_time -= delta
	if _check_time <= 0.0:
		_check_time = 0.25
		update_save_buttons()


## 地圖有沒有東西還沒存
func is_dirty() -> bool:
	return _name_edit.text.strip_edges() != saved_name or map.snapshot() != saved_state


func _mark_saved() -> void:
	saved_state = map.snapshot()
	saved_name = map.map_name


func update_save_buttons() -> void:
	TacticsEditorStyle.paint_save(_top_save, is_dirty())
	_unit_page.update_save_button()


# ---- 畫 ----

func _draw_overlay() -> void:
	if is_testing():
		return
	if snap and page == Page.MAP and _is_terrain_tool():          # 對齊格子：畫出格子線
		for x: int in map.size.x + 1:
			_overlay.draw_line(Vector2(x, 0) * TacticsMap.CELL, Vector2(x, map.size.y) * TacticsMap.CELL, Color(0, 0, 0, 0.18))
		for y: int in map.size.y + 1:
			_overlay.draw_line(Vector2(0, y) * TacticsMap.CELL, Vector2(map.size.x, y) * TacticsMap.CELL, Color(0, 0, 0, 0.18))
	var selected: int = _squad_page.index
	for i: int in map.squads.size():
		_draw_squad(map.squads[i], i, i == selected)
	for cell: Vector2i in map.allies:
		var look: Dictionary = TacticsUnitInfo.look(map.allies[cell])
		Unit.draw_token(_overlay, map.cell_center(cell), Unit.RADIUS, look["color"], Color("4ab86a"), look["mark"])
		_overlay.draw_string(Unit.font(), map.cell_center(cell) + Vector2(-30, -16), "同伴", HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color("1e5a2e"))
	var start: Vector2 = map.cell_center(map.start_cell)
	_overlay.draw_circle(start, 13.0, Unit.TEAM_COLORS[0])
	_overlay.draw_string(Unit.font(), start + Vector2(-16, 5), "起點", HORIZONTAL_ALIGNMENT_CENTER, 32, 11, Color.WHITE)
	if page != Page.MAP:
		return
	var at: Vector2 = _mouse()
	var white: Color = Color(1, 1, 1, 0.8)
	if not _is_terrain_tool():
		if map.has_cell(map.cell_at(at)):
			_draw_rect(Rect2i(map.cell_at(at), Vector2i.ONE), white)
	elif shape == Shape.BRUSH:
		if snap:
			_draw_rect(_brush_cells(at), white)
		else:
			_overlay.draw_arc(at, brush, 0.0, TAU, 48, white, 2.0)
	elif shape == Shape.FILL or _drag_from == null:
		_overlay.draw_line(at - Vector2(8, 0), at + Vector2(8, 0), white, 2.0)
		_overlay.draw_line(at - Vector2(0, 8), at + Vector2(0, 8), white, 2.0)
	else:
		var rect: Rect2 = Rect2(_drag_from, at - (_drag_from as Vector2)).abs()
		if snap:
			var cells: Rect2i = _cells_of(_drag_from, at)
			rect = Rect2(cells.position * TacticsMap.CELL, cells.size * TacticsMap.CELL)
		if shape == Shape.RECT:
			_overlay.draw_rect(rect, white, false, 2.0)
		else:
			var line: PackedVector2Array = PackedVector2Array()
			for i: int in 49:
				line.append(rect.get_center() + Vector2.from_angle(TAU * i / 48.0) * rect.size / 2.0)
			_overlay.draw_polyline(line, white, 2.0)


func _draw_rect(cells: Rect2i, color: Color) -> void:
	_overlay.draw_rect(Rect2(cells.position * TacticsMap.CELL, cells.size * TacticsMap.CELL), color, false, 2.0)


## 一隊：隊員、巡邏路線、視野（選中的那隊畫清楚一點）
func _draw_squad(squad: TacticsSquad, number: int, selected: bool) -> void:
	if squad.members.is_empty():
		return
	var color: Color = SQUAD_COLORS[number % SQUAD_COLORS.size()]
	var soft: Color = Color(color, 0.9 if selected else 0.4)
	var leader: Vector2 = map.cell_center(squad.cells[0])
	var half: float = deg_to_rad(squad.view_angle) / 2.0
	for k: int in squad.members.size():
		if squad.view_of(k) <= 0.0:
			continue
		var at: Vector2 = map.cell_center(squad.cells[k])
		var cone: PackedVector2Array = PackedVector2Array([at])
		for i: int in 17:
			cone.append(at + Vector2.from_angle(squad.look_angle(k) - half + half * 2.0 * i / 16.0) * squad.view_of(k))
		_overlay.draw_colored_polygon(cone, Color(color, (0.22 if selected else 0.1) * (1.0 if k == 0 else 0.5)))
	var from: Vector2 = leader
	for i: int in squad.patrol.size():
		var to: Vector2 = map.cell_center(squad.patrol[i])
		_overlay.draw_line(from, to, soft, 2.0)
		_overlay.draw_circle(to, 5.0, soft)
		_overlay.draw_string(Unit.font(), to + Vector2(6, -4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, soft)
		from = to
	if squad.patrol_mode == 1 and squad.patrol.size() > 1:
		_overlay.draw_line(from, map.cell_center(squad.patrol[0]), soft, 1.0)
	for i: int in squad.members.size():
		var look: Dictionary = TacticsUnitInfo.look(squad.members[i])
		var at: Vector2 = map.cell_center(squad.cells[i])
		Unit.draw_token(_overlay, at, Unit.RADIUS, look["color"], color, look["mark"])
		if selected:
			_overlay.draw_arc(at, 15.0, 0, TAU, 24, Color.WHITE, 2.0)
	_overlay.draw_string(Unit.font(), leader + Vector2(-60, -18), "%d %s%s" % [number + 1, squad.squad_name, "（首領）" if squad.boss else ""], HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color.WHITE if selected else color.lightened(0.4))


# ---- 換頁 ----

func set_page(to: int) -> void:
	_commit_pages()
	page = to as Page
	_painting = false
	_drag_from = null
	_map_tools.visible = page == Page.MAP
	_squad_page.visible = page == Page.SQUADS
	_unit_page.visible = page == Page.UNITS
	_rule_page.visible = page == Page.RULES
	_pool_page.visible = page == Page.POOL
	_top_save.visible = page != Page.UNITS and page != Page.POOL   # 這兩頁有自己的存檔
	for i: int in _page_buttons.size():
		_page_buttons[i].button_pressed = i == page
	_camera.process_mode = Node.PROCESS_MODE_INHERIT if page == Page.MAP and not is_testing() else Node.PROCESS_MODE_DISABLED
	_refresh_pages()
	if page == Page.SQUADS:
		look_at_squad()
	elif page == Page.MAP:
		if _camera_tween != null:
			_camera_tween.kill()
		_camera.clamp_to_limits()
	_say(["左鍵畫、右鍵擦、滾輪調筆刷大小、Ctrl＋滾輪縮放",
		"隊員和巡邏點在「地圖」頁放；小隊跟地圖一起存",
		"改好按「存檔」，地圖和試玩就會用新的",
		"規則跟地圖一起存",
		"起始隊伍每一關共用，改好按「存檔」"][page])


## 把畫面移到現在選的小隊（小隊頁放在面板右邊；太散就縮小到看得完）
func look_at_squad() -> void:
	var squad: TacticsSquad = _squad_page.squad()
	if squad == null or squad.members.is_empty() or is_testing():
		return
	var rect: Rect2 = Rect2(map.cell_center(squad.cells[0]), Vector2.ZERO)
	for cell: Vector2i in squad.cells:
		rect = rect.expand(map.cell_center(cell))
	rect = rect.grow(64.0)
	var free: Rect2 = Rect2(836, 56, 432, 626) if page == Page.SQUADS else Rect2(16, 56, 1248, 520)   # 沒被面板擋住的地方
	var fit: float = minf(free.size.x / rect.size.x, free.size.y / rect.size.y)
	var value: float = clampf(minf(1.0 if page == Page.SQUADS else _camera.zoom.x, fit), 0.2, 3.0)
	var to: Vector2 = OFFSET + rect.get_center() - (free.get_center() - get_viewport_rect().size / 2.0) / value
	if _camera_tween != null:
		_camera_tween.kill()
	_camera_tween = create_tween().set_parallel()
	_camera_tween.tween_property(_camera, "global_position", to, 0.2).set_trans(Tween.TRANS_SINE)
	_camera_tween.tween_property(_camera, "zoom", Vector2(value, value), 0.2)


func _commit_pages() -> void:
	_squad_page.commit()
	_unit_page.commit()
	_rule_page.commit()


# ---- 試玩 ----

func is_testing() -> bool:
	return _play != null and is_instance_valid(_play)


## 開始試玩：在編輯器裡放一個戰棋關卡，用這張地圖
func start_test() -> bool:
	if is_testing():
		return false
	_commit_pages()
	if not map.problem().is_empty():
		_say(map.problem())
		resume_test = false
		return false
	map.map_name = _name_edit.text.strip_edges()                  # 還沒存檔也記住名字
	if _pool_page.is_dirty():
		_say("提醒：起始隊伍改了還沒存檔，試玩用的是存過的")
	TacticsPool.begin_test()                                      # 試玩只有起始隊伍，不動玩家的存檔
	TacticsLevel.test_map = map.copy()
	if TacticsUnitPage.dirty:
		_say("提醒：棋子「%s」改了還沒存檔，試玩用的是存過的" % TacticsUnitPage.editing.get("display_name", ""))
	_play = LEVEL.instantiate()
	add_child(_play)
	resume_test = true                                            # 暫停選單按「重來」：重新載入後接著試玩
	GameFlow.set_title_button("回戰棋編輯器", stop_test)           # 暫停選單、勝敗畫面的「回標題」換成回來編輯
	_set_editing(false)
	return true


## 停止試玩：拿掉關卡，回到編輯
func stop_test() -> void:
	resume_test = false
	TacticsPool.end_test()
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
	_overlay.visible = on
	_ui.visible = on
	_camera.process_mode = Node.PROCESS_MODE_INHERIT if on and page == Page.MAP else Node.PROCESS_MODE_DISABLED
	_stop_button.visible = not on


# ---- 存檔、讀檔 ----

## 存成 maps/名稱.tres。回傳存到哪裡（失敗＝空字串）
func save_map() -> String:
	_commit_pages()
	var map_name: String = _name_edit.text.strip_edges()
	if map_name.is_empty():
		_say("先打地圖名稱")
		return ""
	map.map_name = map_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAPS_DIR))
	var path: String = MAPS_DIR + map_name.validate_filename() + ".tres"
	var error: Error = ResourceSaver.save(map, path)
	if error != OK:
		_say("存檔失敗：%s（匯出的遊戲不能存，要在 Godot 編輯器裡按 F6）" % error_string(error))
		return ""
	map.take_over_path(path)
	_mark_saved()
	update_save_buttons()
	_refresh_maps()
	_say("存好了：%s%s" % [path, "" if map.problem().is_empty() else "（提醒：%s）" % map.problem()])
	return path


## 讀 maps/ 裡的一張地圖
func load_map(path: String) -> bool:
	var loaded: TacticsMap = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as TacticsMap
	if loaded == null:
		_say("讀不到：%s" % path)
		return false
	map = loaded
	_use_map()
	_load_list.select(0)                                          # 清單回到「讀檔…」，同一張也能再讀一次
	_say("讀進來了：%s" % path)
	return true


func _use_map() -> void:
	map.ensure()
	editing = map
	_squad_page.index = 0
	_mark_saved()
	_forget()
	_show_map()


## 把現在的地圖做成關卡場景。回傳存到哪裡（失敗＝空字串）
func make_level() -> String:
	_commit_pages()
	var map_path: String = MAPS_DIR + saved_name.validate_filename() + ".tres"
	if is_dirty() or not ResourceLoader.exists(map_path):
		_say("地圖還沒存檔，先到「地圖」頁按存檔")
		return ""
	if not map.problem().is_empty():
		_say(map.problem())
		return ""
	var path: String = TacticsLevelMaker.path_for(map_path)
	var error: Error = TacticsLevelMaker.make(map_path)
	if error == ERR_ALREADY_EXISTS:
		_say("已經有這一關了：%s（它會自動用最新存檔的地圖，不用重做）" % path)
		return ""
	if error != OK:
		_say("做不了：%s（匯出的遊戲不能存，要在 Godot 編輯器裡按 F6）" % error_string(error))
		return ""
	_say("做好了：%s，拖進 game_config.tres 的 Levels 就能串關" % path.get_file())
	return path


func map_files() -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		return files
	for file: String in DirAccess.get_files_at(MAPS_DIR):
		if file.ends_with(".tres"):
			files.append(MAPS_DIR + file)
	return files


func new_map() -> void:
	map = _new_map()
	_use_map()
	_say("新地圖")


## 清空地形（外面一圈牆留著）
func clear_terrain() -> void:
	remember()
	map.paint_cells(TacticsMap.Kind.PLAIN, Rect2i(Vector2i.ONE, map.size - Vector2i(2, 2)))


# ---- 介面 ----

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)
	_strip(Rect2(0, 0, 1280, 46))                                 # 最上面、最下面兩條底色，字才看得清楚
	_strip(Rect2(0, 692, 1280, 28))
	_build_pages()
	_map_tools = Control.new()
	_map_tools.name = "MapTools"
	_map_tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_map_tools)
	_strip(Rect2(0, 586, 1280, 106), _map_tools)
	var row: HBoxContainer = _row(Vector2(16, 592), _map_tools)
	for i: int in TOOL_NAMES.size():
		_tool_buttons.append(_toggle(row, TOOL_NAMES[i], _set_tool.bind(i)))
		if i == Tool.HIGH or i == Tool.ALLY:
			row.add_child(VSeparator.new())
	row.add_child(VSeparator.new())
	for i: int in SHAPE_NAMES.size():
		_shape_buttons.append(_toggle(row, SHAPE_NAMES[i], _set_shape.bind(i)))
	_snap_button = _toggle(row, "對齊格子", func() -> void:
		snap = _snap_button.button_pressed
		_say("對齊格子：一格一格畫" if snap else "圓滑地畫"))
	_snap_button.button_pressed = snap
	_snap_button.tooltip_text = "打開：照格子畫，邊緣是直的。關掉：圓滑的。兩種可以畫在同一張地圖"
	row = _row(Vector2(16, 626), _map_tools)                      # 第二排：檔案、地圖大小
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "地圖名稱"
	_name_edit.custom_minimum_size = Vector2(160, 0)
	row.add_child(_name_edit)
	_load_list = OptionButton.new()
	_load_list.custom_minimum_size = Vector2(160, 0)
	_load_list.item_selected.connect(func(index: int) -> void: load_map(_load_list.get_item_metadata(index)))
	row.add_child(_load_list)
	_button(row, "新地圖", new_map)
	TacticsEditorStyle.paint(_button(row, "清空地形", clear_terrain), TacticsEditorStyle.DANGER)
	row.add_child(VSeparator.new())
	_width = _size_box(row, "寬")
	_height = _size_box(row, "高")
	row.add_child(VSeparator.new())
	_label(row, "寶箱裡有")
	_chest_box = SpinBox.new()
	_chest_box.min_value = 0
	_chest_box.max_value = 10
	_chest_box.value = chest_amount
	_chest_box.suffix = "份"
	_chest_box.tooltip_text = "新放的寶箱裡有幾份營地物資；點已經放的寶箱可以改"
	_chest_box.value_changed.connect(func(value: float) -> void:
		chest_amount = int(value)
		_set_tool(Tool.CHEST))
	row.add_child(_chest_box)
	row = _row(Vector2(16, 660), _map_tools)                      # 第三排：敵人
	_label(row, "敵人、巡邏點：")
	_squad_list = OptionButton.new()
	_squad_list.focus_mode = Control.FOCUS_NONE
	_squad_list.custom_minimum_size = Vector2(180, 0)
	_squad_list.item_selected.connect(_on_squad_selected)
	row.add_child(_squad_list)
	_label(row, "放哪一種（敵人、同伴）：")
	_unit_list = OptionButton.new()
	_unit_list.focus_mode = Control.FOCUS_NONE
	_unit_list.custom_minimum_size = Vector2(160, 0)
	_unit_list.item_selected.connect(func(index: int) -> void:
		unit_path = _unit_paths[index]
		if tool != Tool.ALLY:
			_set_tool(Tool.ENEMY))
	row.add_child(_unit_list)
	_status = Label.new()
	_status.position = Vector2(16, 697)
	_status.add_theme_font_size_override("font_size", 14)
	_ui.add_child(_status)
	var title: Label = Label.new()
	title.text = "戰棋編輯器"
	title.position = Vector2(64, 10)
	title.add_theme_font_size_override("font_size", 22)
	_ui.add_child(title)
	row = _row(Vector2(200, 8), _ui)                              # 最上面：換頁、上一步、試玩
	for i: int in PAGE_NAMES.size():
		_page_buttons.append(_toggle(row, PAGE_NAMES[i], set_page.bind(i)))
	row.add_child(VSeparator.new())
	_button(row, "↶", undo).tooltip_text = "上一步（Ctrl＋Z）"
	_button(row, "↷", redo).tooltip_text = "下一步（Ctrl＋Y）"
	row.add_child(VSeparator.new())
	_top_save = _button(row, "存檔", save_map)                    # 小隊、規則跟地圖一起存，這三頁都看得到
	TacticsEditorStyle.paint_save(_top_save, false)
	TacticsEditorStyle.paint(_button(row, "▶ 試玩", start_test), TacticsEditorStyle.PLAY)
	row.add_child(VSeparator.new())
	_button(row, "做成關卡", make_level).tooltip_text = "把現在的地圖（要先存檔）做成一個關卡場景"
	var top: CanvasLayer = CanvasLayer.new()                      # 試玩時才出現的「停止試玩」（另一層，編輯的介面藏起來時它還在）
	top.layer = 25                                                # 在 HUD（20）上面、暫停選單（30）下面
	add_child(top)
	_stop_button = Button.new()
	_stop_button.name = "StopTest"
	_stop_button.text = "■ 停止試玩"
	_stop_button.focus_mode = Control.FOCUS_NONE
	_stop_button.position = Vector2(1020, 22)
	_stop_button.visible = false
	_stop_button.pressed.connect(stop_test)
	TacticsEditorStyle.paint(_stop_button, TacticsEditorStyle.DANGER)
	top.add_child(_stop_button)
	_refresh_units()


func _build_pages() -> void:
	_squad_page = TacticsSquadPage.new()
	_squad_page.name = "SquadPage"
	_squad_page.say = _say
	_squad_page.will_change.connect(remember)
	_squad_page.changed.connect(_refresh_squads)
	_squad_page.selected.connect(look_at_squad)
	_add_page(_squad_page, Rect2(64, 48, 760, 640))
	_unit_page = TacticsUnitPage.new()
	_unit_page.name = "UnitPage"
	_unit_page.say = _say
	_unit_page.saved.connect(func(_path: String) -> void:
		_refresh_units()
		_refresh_pages())
	_add_page(_unit_page, Rect2(64, 48, 1196, 640))
	_rule_page = TacticsRulePage.new()
	_rule_page.name = "RulePage"
	_rule_page.say = _say
	_rule_page.will_change.connect(remember)
	_add_page(_rule_page, Rect2(64, 48, 1196, 640))
	_pool_page = TacticsPoolPage.new()
	_pool_page.name = "PoolPage"
	_pool_page.say = _say
	_add_page(_pool_page, Rect2(64, 48, 1196, 640))


func _add_page(panel: PanelContainer, area: Rect2) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.16, 0.18)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	_ui.add_child(panel)
	panel.position = area.position
	panel.size = area.size


## 小隊的下拉選單（最後一個是「＋ 新小隊」）
func _refresh_squads() -> void:
	if _squad_list == null:
		return
	_squad_list.clear()
	for i: int in map.squads.size():
		_squad_list.add_item("%d %s" % [i + 1, map.squads[i].squad_name])
	_squad_list.add_item("＋ 新小隊")
	_squad_list.select(_squad_page.index if not map.squads.is_empty() else 0)


func _on_squad_selected(index: int) -> void:
	if index >= map.squads.size():
		_squad_page.add_squad()
	else:
		_squad_page.index = index
		_squad_page.refresh()
	_refresh_squads()
	look_at_squad()


func _refresh_units() -> void:
	_unit_paths = TacticsUnitInfo.paths()
	_unit_list.clear()
	for path: String in _unit_paths:
		_unit_list.add_item(TacticsUnitInfo.look(path)["name"])
	var index: int = _unit_paths.find(unit_path)
	unit_path = _unit_paths[maxi(index, 0)]
	_unit_list.select(maxi(index, 0))


func _strip(area: Rect2, parent: Node = _ui) -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.13, 0.13, 0.15, 0.96)
	background.position = area.position
	background.size = area.size
	parent.add_child(background)


func _row(at: Vector2, parent: Node) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.position = at
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


func _label(parent: Control, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	parent.add_child(label)


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
	TacticsEditorStyle.paint_toggle(button)
	return button


func _size_box(parent: Control, text: String) -> SpinBox:
	_label(parent, text)
	var box: SpinBox = SpinBox.new()
	box.min_value = 8
	box.max_value = 100
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
		button.disabled = not _is_terrain_tool()                  # 放東西不用選形狀
	_snap_button.disabled = not _is_terrain_tool()
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
	if page != Page.MAP:
		_status.text = _status_text
		return
	var what: String = TOOL_NAMES[tool] + ("（%s）" % SHAPE_NAMES[shape] if _is_terrain_tool() else "")
	_status.text = "%s　｜　筆刷 %d px%s　｜　%s" % [what, int(brush), "（對齊格子）" if snap else "", _status_text]
