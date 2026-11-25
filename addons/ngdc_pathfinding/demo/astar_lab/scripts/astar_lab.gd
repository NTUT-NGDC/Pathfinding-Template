extends Control
## A* 實驗室：在格子地圖上看 BFS／A* 一步一步怎麼找路。
## 左鍵畫牆或沼澤（上面選畫筆）、右鍵擦掉、拖曳綠色起點和紅色終點；右邊調演算法、估計權重、斜走、播放速度。
## 「顯示」選「分數的組成」：每格左上是走了多少 g、右上是還剩多少 h、下面大字是總分；滑鼠停在格子上看完整算式。
## 「走走看」讓 NPC 照路走一次、計時；「比賽」讓權重 0、1、5 三隻一起走；每次的結果都記在紀錄表。
##
## 演算法本體在 grid_search.gd（GridSearch），這個腳本只負責畫圖和按鈕。
## 主題課示範用，匯出時排除；在編輯器裡打開 astar_lab.tscn 按 F6。

const CELL: int = 36
const SAVE_PATH: String = "user://astar_lab_maps.cfg"
const SLOT_COUNT: int = 3

const FLOOR_COLOR: Color = Color("e8e4da")
const WALL_COLOR: Color = Color("3a3d46")
const SWAMP_COLOR: Color = Color("8a8f55")
const OPEN_COLOR: Color = Color(0.45, 0.7, 1.0, 0.75)
const CLOSED_COLOR: Color = Color(1.0, 0.8, 0.35, 0.75)
const PATH_COLOR: Color = Color("ff5a4a")
const START_COLOR: Color = Color("3fbf6a")
const GOAL_COLOR: Color = Color("e04848")
const LINE_COLOR: Color = Color(0, 0, 0, 0.1)
const TEXT_COLOR: Color = Color(0.15, 0.15, 0.2)
const ARROW_COLOR: Color = Color(0.1, 0.15, 0.45, 0.6)
const NEXT_COLOR: Color = Color("b030d0")
const HOVER_COLOR: Color = Color(0.1, 0.1, 0.12)
const NO_CELL: Vector2i = Vector2i(-1, -1)
## 比賽的三隻
const RACE_WEIGHTS: Array[float] = [0.0, 1.0, 5.0]
const RECORD_LIMIT: int = 30
const RECORD_HEADERS: Array[String] = ["地圖", "演算法", "權重", "沼澤", "探索格數", "路徑格數", "總成本", "NPC 秒數"]
const RACE_HEADERS: Array[String] = ["名次", "權重", "探索", "格數", "成本", "秒"]

## 格子裡要寫什麼（「顯示」選單的順序）
enum Scores { NONE, TOTAL, PARTS }

## 演算法的狀態（測試會讀）
var search: GridSearch = GridSearch.new()

## 拖曳中：0 沒有、1 畫牆、2 擦牆、3 拖起點、4 拖終點
var _drag: int = 0
## 自動播放：累積到 1 就走一步
var _step_budget: float = 0.0
## 滑鼠停在哪一格（不在地圖上是 NO_CELL）
var _hover: Vector2i = NO_CELL
## 現在的地圖叫什麼（改過就是「自己畫的」），寫在紀錄表
var _map_name: String = ""
## 紀錄表：每一列是 RECORD_HEADERS 的順序
var _records: Array[PackedStringArray] = []
## 這次找路的紀錄在第幾列（還沒找完是 -1）
var _record_index: int = -1

@onready var _grid_view: Control = %GridView
@onready var _algorithm: OptionButton = %AlgorithmOption
@onready var _weight: HSlider = %WeightSlider
@onready var _weight_label: Label = %WeightLabel
@onready var _diagonal: CheckBox = %DiagonalCheck
@onready var _corner: CheckBox = %CornerCheck
@onready var _scores: OptionButton = %ScoresOption
@onready var _arrows: CheckBox = %ArrowsCheck
@onready var _play: Button = %PlayButton
@onready var _speed: HSlider = %SpeedSlider
@onready var _speed_label: Label = %SpeedLabel
@onready var _stats: Label = %Stats
@onready var _cell_info: Label = %CellInfo
@onready var _walkers: Control = %Walkers
@onready var _walk_label: Label = %WalkLabel
@onready var _ranking: GridContainer = %Ranking
@onready var _record_panel: Control = %RecordPanel
@onready var _record_grid: GridContainer = %RecordGrid
@onready var _tabs: TabContainer = %Tabs
@onready var _preset: OptionButton = %PresetOption
@onready var _slot: OptionButton = %SlotOption
@onready var _brush: OptionButton = %BrushOption
@onready var _swamp: HSlider = %SwampSlider
@onready var _swamp_label: Label = %SwampLabel


func _enter_tree() -> void:
	add_to_group("no_pause")                                      # 起手包的暫停選單不要出現在實驗室


func _ready() -> void:
	_algorithm.add_item("BFS（水往外擴散）")
	_algorithm.add_item("A*（走了多少＋還剩多少）")
	_algorithm.select(1)
	for map_name: String in AStarPresets.MAPS:
		_preset.add_item(map_name)
	_brush.add_item("牆")
	_brush.add_item("沼澤")
	_scores.add_item("不顯示分數")
	_scores.add_item("只顯示總分")
	_scores.add_item("分數的組成")
	_swamp.value = AStarPresets.SWAMP_COST
	for i: int in SLOT_COUNT:
		_slot.add_item("存檔 %d" % (i + 1))

	_grid_view.custom_minimum_size = Vector2(search.size * CELL)
	_grid_view.draw.connect(_draw_grid)
	_grid_view.gui_input.connect(_on_grid_input)
	_grid_view.mouse_exited.connect(func() -> void: _set_hover(NO_CELL))
	_algorithm.item_selected.connect(func(_i: int) -> void: _restart())
	_weight.value_changed.connect(func(_v: float) -> void: _restart())
	_diagonal.toggled.connect(func(_on: bool) -> void: _restart())
	_corner.toggled.connect(func(_on: bool) -> void: _restart())
	_scores.item_selected.connect(func(_i: int) -> void: _grid_view.queue_redraw())
	_arrows.toggled.connect(func(_on: bool) -> void: _grid_view.queue_redraw())
	_swamp.value_changed.connect(_on_swamp_changed)
	_play.toggled.connect(_on_play_toggled)
	_speed.value_changed.connect(func(_v: float) -> void: _update_labels())
	_preset.item_selected.connect(_on_preset_selected)
	_tabs.set_tab_title(0, "這一格")
	_tabs.set_tab_title(1, "走走看")
	_walkers.cell_size = CELL
	_walkers.arrived.connect(func(_i: int) -> void: _update_ranking())
	_walkers.all_arrived.connect(_on_all_arrived)
	(%WalkButton as Button).pressed.connect(_on_walk_pressed)
	(%RaceButton as Button).pressed.connect(_on_race_pressed)
	(%RecordButton as Button).pressed.connect(func() -> void: _record_panel.visible = not _record_panel.visible)
	(%RecordCloseButton as Button).pressed.connect(func() -> void: _record_panel.hide())
	(%RecordClearButton as Button).pressed.connect(_on_record_clear_pressed)
	_update_records()
	(%StepButton as Button).pressed.connect(_on_step_pressed)
	(%ResetButton as Button).pressed.connect(_restart)
	(%ClearButton as Button).pressed.connect(_on_clear_pressed)
	(%SaveButton as Button).pressed.connect(_on_save_pressed)
	(%LoadButton as Button).pressed.connect(_on_load_pressed)

	_preset.select(1)                                             # 預設打開 U 形牆
	_on_preset_selected(1)


func _process(delta: float) -> void:
	if _walkers.running:
		_update_walk_label()
	if not _play.button_pressed or search.finished:
		_step_budget = 0.0
		return
	_step_budget += delta * _speed.value
	while _step_budget >= 1.0 and not search.finished:
		search.step()
		_step_budget -= 1.0
	_refresh()


## 設定改了：照新設定從頭找（地圖不變）
func _restart() -> void:
	search.algorithm = _algorithm.selected as GridSearch.Algorithm
	search.weight = _weight.value
	search.allow_diagonal = _diagonal.button_pressed
	search.cut_corners = _corner.button_pressed
	search.start()
	_record_index = -1
	_stop_walkers()
	_refresh()


func _refresh() -> void:
	if search.finished and _record_index == -1:
		_record_index = _add_record(search)
	_update_labels()
	_grid_view.queue_redraw()


func _update_labels() -> void:
	_weight.editable = search.algorithm == GridSearch.Algorithm.ASTAR
	_corner.disabled = not _diagonal.button_pressed
	var hint: String = "（BFS 不用）" if search.algorithm == GridSearch.Algorithm.BFS else ""
	_weight_label.text = "估計權重 w：%.1f %s" % [_weight.value, hint]
	_swamp_label.text = "沼澤成本 %d" % roundi(_swamp.value)
	_speed_label.text = "速度：每秒 %d 步" % roundi(_speed.value)
	var state: String = "找路中……"
	if search.finished:
		state = "找到了！" if search.found else "走不到！"
	var length: String = "－"
	if search.found:
		length = "%d 格，總成本 %s" % [search.path_steps(), _number(search.path_length())]
	if search.algorithm == GridSearch.Algorithm.BFS and not search.costs.is_empty():
		state += "（BFS 不看沼澤）"
	_stats.text = "探索了 %d 格（待探索 %d）\n路徑長度 %s\n%s" % [search.closed.size(), search.open.size(), length, state]
	if _is_racing():
		_stats.text = "比賽：A* 權重 0、1、5
各找一條路，一起出發"
	_cell_info.text = _describe_cell(_hover)


func _on_play_toggled(_on: bool) -> void:
	if _is_racing():
		_stop_walkers()
	_refresh()


func _on_step_pressed() -> void:
	_play.button_pressed = false
	if _is_racing():
		_stop_walkers()
	search.step()
	_refresh()


func _on_preset_selected(index: int) -> void:
	_map_name = _preset.get_item_text(index)
	AStarPresets.apply(AStarPresets.MAPS[_map_name], search, _swamp.value)
	_restart()


## 沼澤成本改了：地圖上的沼澤全部換成新的，從頭找
func _on_swamp_changed(value: float) -> void:
	for cell: Vector2i in search.costs:
		search.costs[cell] = value
	_restart()


func _on_clear_pressed() -> void:
	_map_name = "自己畫的"
	search.walls.clear()
	search.costs.clear()
	_restart()


# ---- 滑鼠：畫牆、拖起點終點 ----

func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if not button.pressed:
			_drag = 0
			return
		var cell: Vector2i = _cell_at(button.position)
		if button.button_index == MOUSE_BUTTON_LEFT:
			_drag = 3 if cell == search.start_cell else 4 if cell == search.goal_cell else 1
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_drag = 2
		_apply_drag(cell)
	elif event is InputEventMouseMotion:
		var cell: Vector2i = _cell_at((event as InputEventMouseMotion).position)
		_set_hover(cell if _in_map(cell) else NO_CELL)
		if _drag != 0:
			_apply_drag(cell)


func _set_hover(cell: Vector2i) -> void:
	if cell == _hover:
		return
	_hover = cell
	_refresh()


func _apply_drag(cell: Vector2i) -> void:
	if not _in_map(cell):
		return
	var is_endpoint: bool = cell == search.start_cell or cell == search.goal_cell
	match _drag:
		1:
			if is_endpoint:
				return
			if _brush.selected == 0:
				if search.walls.has(cell):
					return
				search.costs.erase(cell)
				search.walls[cell] = true
			else:
				if search.costs.has(cell):
					return
				search.walls.erase(cell)
				search.costs[cell] = _swamp.value
		2:
			var erased_wall: bool = search.walls.erase(cell)
			var erased_swamp: bool = search.costs.erase(cell)
			if not erased_wall and not erased_swamp:
				return
		3:
			if is_endpoint or search.walls.has(cell):
				return
			search.start_cell = cell
		4:
			if is_endpoint or search.walls.has(cell):
				return
			search.goal_cell = cell
	_map_name = "自己畫的"
	_restart()


func _cell_at(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))


func _in_map(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, search.size).has_point(cell)


# ---- 滑鼠停著的那一格 ----

func _describe_cell(cell: Vector2i) -> String:
	if cell == NO_CELL:
		return "滑鼠停在格子上，\n看它的分數怎麼算"
	if search.walls.has(cell):
		return "%s　牆：不能走" % _cell_name(cell)
	var lines: PackedStringArray = ["%s　%s" % [_cell_name(cell), _cell_state(cell)]]
	if search.algorithm == GridSearch.Algorithm.BFS:
		lines.append("BFS 不算分數，先來的先找")
		if search.g.has(cell):
			lines.append("走了多少 g＝%s" % _number(search.g[cell]))
	else:
		var h: String = _number(search.estimate(cell))
		lines.append("走了多少 g＝%s" % (_number(search.g[cell]) if search.g.has(cell) else "還不知道"))
		lines.append("還剩多少 h＝%s" % h)
		lines.append("權重 w＝%s" % _number(search.weight))
		if search.g.has(cell):
			lines.append("總分 %s＝%s＋%s×%s" % [_number(search.score(cell)), _number(search.g[cell]), _number(search.weight), h])
	lines.append("地形：%s" % ("沼澤（成本 %s）" % _number(search.costs[cell]) if search.costs.has(cell) else "一般（成本 1）"))
	if search.came_from.has(cell):
		lines.append("從 %s 走過來" % _cell_name(search.came_from[cell]))
	return "\n".join(lines)


func _cell_name(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]


func _cell_state(cell: Vector2i) -> String:
	var state: String = "還沒碰到"
	if search.path.has(cell):
		state = "路徑"
	elif search.closed.has(cell):
		state = "已探索"
	elif search.g.has(cell):
		state = "下一個要探索" if cell == search.peek_next() else "待探索"
	if cell == search.start_cell:
		return "起點・" + state
	return "終點・" + state if cell == search.goal_cell else state


## 整數就不寫小數點，斜走才有一位小數
func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


# ---- NPC 走走看、比賽 ----

## 還沒找完就先找完，再讓 NPC 照路走一次
func _on_walk_pressed() -> void:
	_play.button_pressed = false
	_stop_walkers()
	search.run_to_end()
	_record_index = maxi(_record_index, -1)                       # 紀錄被清掉過：重新記一列
	_refresh()
	if not search.found:
		_walk_label.text = "走不到，NPC 不能出發"
		return
	_walkers.start([search] as Array[GridSearch])


## 權重 0、1、5 各找一次（都用 A*），三隻一起出發
func _on_race_pressed() -> void:
	_play.button_pressed = false
	_restart()
	var racers: Array[GridSearch] = []
	for w: float in RACE_WEIGHTS:
		var racer: GridSearch = search.copy_map()
		racer.weight = w
		racer.start()
		racer.run_to_end()
		racers.append(racer)
	if not racers[0].found:
		_walk_label.text = "走不到，NPC 不能出發"
		return
	_walkers.start(racers)
	_update_ranking()
	_refresh()


func _is_racing() -> bool:
	return _walkers.searches.size() > 1


func _stop_walkers() -> void:
	_walkers.stop()
	_walk_label.text = ""
	_fill_grid(_ranking, [], [], [])


func _update_walk_label() -> void:
	_walk_label.text = "%s：%.1f 秒" % ["比賽中" if _is_racing() else "走路中", _walkers.elapsed]


func _on_all_arrived() -> void:
	if _is_racing():
		_walk_label.text = "比賽結束"
		_update_ranking()
		for i: int in _walkers.searches.size():
			_set_record_time(_add_record(_walkers.searches[i]), _walkers.time_of(i))
		return
	_walk_label.text = "花了 %s 秒\n＝總成本 %s × %s 秒" % [_seconds(_walkers.time_of(0)), _number(search.path_length()), str(_walkers.SECONDS_PER_CELL)]
	_set_record_time(_record_index, _walkers.time_of(0))


## 比賽的排行：先到的在上面，時間一樣就並列；還沒到的先不寫名次
func _update_ranking() -> void:
	if not _is_racing():
		return
	var order: Array = range(_walkers.searches.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(_walkers.time_of(a), _walkers.time_of(b)):
			return a < b
		return _walkers.time_of(a) < _walkers.time_of(b))
	var rows: Array[PackedStringArray] = []
	var colors: Array[Color] = []
	for i: int in order:
		var racer: GridSearch = _walkers.searches[i]
		var faster: int = order.filter(func(j: int) -> bool: return _walkers.time_of(j) < _walkers.time_of(i) and not is_equal_approx(_walkers.time_of(i), _walkers.time_of(j))).size()
		var here: bool = _walkers.has_arrived(i)
		rows.append(PackedStringArray([str(faster + 1) if here else "－", _number(racer.weight), str(racer.closed.size()), str(racer.path_steps()), _number(racer.path_length()), _seconds(_walkers.time_of(i)) if here else "－"]))
		colors.append(_walkers.COLORS[i].lightened(0.35))
	_fill_grid(_ranking, RACE_HEADERS, rows, colors)


## 秒數寫到小數第二位（0.15 秒一格），後面的 0 不寫
func _seconds(value: float) -> String:
	return str(snappedf(value, 0.01))


# ---- 紀錄表 ----

## 加一列，回傳是第幾列（NPC 還沒走，秒數先空著）
func _add_record(run: GridSearch) -> int:
	if _records.size() >= RECORD_LIMIT:
		_records.pop_front()
	var astar: bool = run.algorithm == GridSearch.Algorithm.ASTAR
	_records.append(PackedStringArray([
		_map_name, "A*" if astar else "BFS", _number(run.weight) if astar else "－",
		"－" if run.costs.is_empty() else _number(_swamp.value),
		str(run.closed.size()), str(run.path_steps()) if run.found else "走不到", _number(run.path_length()) if run.found else "－", "－"]))
	_update_records()
	return _records.size() - 1


func _set_record_time(index: int, seconds: float) -> void:
	if index >= 0 and index < _records.size():
		_records[index][RECORD_HEADERS.size() - 1] = _seconds(seconds)
		_update_records()


func _on_record_clear_pressed() -> void:
	_records.clear()
	_record_index = -2 if search.finished else -1                 # -2：這次的紀錄被清掉了，不要再記一次
	_update_records()


func _update_records() -> void:
	(%RecordButton as Button).text = "紀錄 %d" % _records.size()
	_fill_grid(_record_grid, RECORD_HEADERS, _records, [])


## 把表格重填一次：第一列是標題
func _fill_grid(grid: GridContainer, headers: Array, rows: Array, colors: Array) -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for header: String in headers:
		_add_grid_text(grid, header, Color(0.65, 0.65, 0.7))
	for i: int in rows.size():
		for text: String in rows[i]:
			_add_grid_text(grid, text, colors[i] if i < colors.size() else Color.WHITE)


func _add_grid_text(grid: GridContainer, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	grid.add_child(label)


# ---- 存讀自己畫的地圖 ----

func _on_save_pressed() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("slot%d" % _slot.selected, "rows", AStarPresets.to_rows(search))
	config.set_value("slot%d" % _slot.selected, "swamp_cost", _swamp.value)
	config.save(SAVE_PATH)


func _on_load_pressed() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var rows: Variant = config.get_value("slot%d" % _slot.selected, "rows", null)
	if rows is PackedStringArray and (rows as PackedStringArray).size() == search.size.y:
		_swamp.set_value_no_signal(float(config.get_value("slot%d" % _slot.selected, "swamp_cost", AStarPresets.SWAMP_COST)))
		AStarPresets.apply(Array(rows as PackedStringArray), search, _swamp.value)
		_map_name = _slot.get_item_text(_slot.selected)
		_restart()


# ---- 畫格子 ----

func _draw_grid() -> void:
	for y: int in search.size.y:
		for x: int in search.size.x:
			var cell: Vector2i = Vector2i(x, y)
			var rect: Rect2 = Rect2(Vector2(cell * CELL), Vector2(CELL, CELL))
			_grid_view.draw_rect(rect, SWAMP_COLOR if search.costs.has(cell) else FLOOR_COLOR)
			var overlay: Color = _cell_color(cell)
			if overlay.a > 0.0:
				_grid_view.draw_rect(rect, overlay)
			_grid_view.draw_rect(rect, LINE_COLOR, false, 1.0)
			if _arrows.button_pressed and search.came_from.has(cell):
				_draw_arrow(cell, search.came_from[cell])
	# 最終路徑畫成一條線
	if search.path.size() >= 2:
		var points: PackedVector2Array = PackedVector2Array()
		for cell: Vector2i in search.path:
			points.append(Vector2(cell * CELL) + Vector2(CELL, CELL) / 2.0)
		var line_color: Color = PATH_COLOR if _scores.selected == Scores.NONE else Color(PATH_COLOR, 0.5)
		_grid_view.draw_polyline(points, line_color, 5.0)
	_draw_endpoint(search.start_cell, START_COLOR)
	_draw_endpoint(search.goal_cell, GOAL_COLOR)
	if _scores.selected != Scores.NONE:
		for cell: Vector2i in search.g:
			_draw_scores(cell)
	if not _play.button_pressed and not _is_racing() and _in_map(search.peek_next()):    # 逐步：下一個要探索的格子
		_grid_view.draw_rect(_cell_rect(search.peek_next()).grow(-2), NEXT_COLOR, false, 4.0)
	if _hover != NO_CELL:
		_grid_view.draw_rect(_cell_rect(_hover), HOVER_COLOR, false, 2.0)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell * CELL), Vector2(CELL, CELL))


## 左上 g、右上 h、下面大字總分（BFS 沒有分數，只寫走了多少）。格子裡放不下小數，完整的數字看右邊
func _draw_scores(cell: Vector2i) -> void:
	var at: Vector2 = _cell_rect(cell).position
	var font: Font = get_theme_default_font()
	if search.algorithm == GridSearch.Algorithm.BFS or _scores.selected == Scores.TOTAL:
		var value: float = search.g[cell] if search.algorithm == GridSearch.Algorithm.BFS else search.score(cell)
		_draw_total(at + Vector2(0, 26), value)
		return
	_grid_view.draw_string(font, at + Vector2(2, 12), str(roundi(search.g[cell])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
	_grid_view.draw_string(font, at + Vector2(0, 12), str(roundi(search.estimate(cell))), HORIZONTAL_ALIGNMENT_RIGHT, CELL - 2, 11, TEXT_COLOR)
	_draw_total(at + Vector2(0, 33), search.score(cell))


func _draw_total(at: Vector2, value: float) -> void:
	_grid_view.draw_string(get_theme_default_font(), at, str(roundi(value)), HORIZONTAL_ALIGNMENT_CENTER, CELL, 22, TEXT_COLOR)


## 這格是從哪一格走過來的：箭頭指向那一格
func _draw_arrow(cell: Vector2i, from: Vector2i) -> void:
	var direction: Vector2 = Vector2(from - cell).normalized()
	var center: Vector2 = _cell_rect(cell).get_center()
	var tip: Vector2 = center + Vector2(from - cell) * CELL * 0.48
	var side: Vector2 = direction.orthogonal() * CELL * 0.14
	if _scores.selected == Scores.NONE:                             # 有數字的時候只畫箭頭的尖端，不要擋到字
		_grid_view.draw_line(center - direction * CELL * 0.3, tip, ARROW_COLOR, 3.0)
	_grid_view.draw_colored_polygon(PackedVector2Array([tip, tip - direction * CELL * 0.18 + side, tip - direction * CELL * 0.18 - side]), ARROW_COLOR)


func _cell_color(cell: Vector2i) -> Color:
	if search.walls.has(cell):
		return WALL_COLOR
	if search.closed.has(cell):
		return CLOSED_COLOR                                       # 已探索
	if search.g.has(cell):
		return OPEN_COLOR                                         # 待探索
	return Color(0, 0, 0, 0)


func _draw_endpoint(cell: Vector2i, color: Color) -> void:
	var center: Vector2 = Vector2(cell * CELL) + Vector2(CELL, CELL) / 2.0
	_grid_view.draw_circle(center, CELL * 0.38, color.darkened(0.4))
	_grid_view.draw_circle(center, CELL * 0.3, color)
