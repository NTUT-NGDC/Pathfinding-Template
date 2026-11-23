extends Control
## A* 實驗室：在格子地圖上看 BFS／A* 一步一步怎麼找路。
## 左鍵畫牆或沼澤（右邊選筆刷）、右鍵擦掉、拖曳綠色起點和紅色終點；右邊調演算法、估計權重、斜走、播放速度。
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

## 演算法的狀態（測試會讀）
var search: GridSearch = GridSearch.new()

## 拖曳中：0 沒有、1 畫牆、2 擦牆、3 拖起點、4 拖終點
var _drag: int = 0
## 自動播放：累積到 1 就走一步
var _step_budget: float = 0.0

@onready var _grid_view: Control = %GridView
@onready var _algorithm: OptionButton = %AlgorithmOption
@onready var _weight: HSlider = %WeightSlider
@onready var _weight_label: Label = %WeightLabel
@onready var _diagonal: CheckBox = %DiagonalCheck
@onready var _corner: CheckBox = %CornerCheck
@onready var _scores: CheckBox = %ScoresCheck
@onready var _play: Button = %PlayButton
@onready var _speed: HSlider = %SpeedSlider
@onready var _speed_label: Label = %SpeedLabel
@onready var _stats: Label = %Stats
@onready var _preset: OptionButton = %PresetOption
@onready var _slot: OptionButton = %SlotOption
@onready var _brush: OptionButton = %BrushOption


func _enter_tree() -> void:
	add_to_group("no_pause")                                      # 起手包的暫停選單不要出現在實驗室


func _ready() -> void:
	_algorithm.add_item("BFS（水往外擴散）")
	_algorithm.add_item("A*（走了多少＋還剩多少）")
	_algorithm.select(1)
	for map_name: String in AStarPresets.MAPS:
		_preset.add_item(map_name)
	_brush.add_item("牆")
	_brush.add_item("沼澤（成本 %d）" % roundi(AStarPresets.SWAMP_COST))
	for i: int in SLOT_COUNT:
		_slot.add_item("存檔 %d" % (i + 1))

	_grid_view.custom_minimum_size = Vector2(search.size * CELL)
	_grid_view.draw.connect(_draw_grid)
	_grid_view.gui_input.connect(_on_grid_input)
	_algorithm.item_selected.connect(func(_i: int) -> void: _restart())
	_weight.value_changed.connect(func(_v: float) -> void: _restart())
	_diagonal.toggled.connect(func(_on: bool) -> void: _restart())
	_corner.toggled.connect(func(_on: bool) -> void: _restart())
	_scores.toggled.connect(func(_on: bool) -> void: _grid_view.queue_redraw())
	_speed.value_changed.connect(func(_v: float) -> void: _update_labels())
	_preset.item_selected.connect(_on_preset_selected)
	(%StepButton as Button).pressed.connect(_on_step_pressed)
	(%ResetButton as Button).pressed.connect(_restart)
	(%ClearButton as Button).pressed.connect(_on_clear_pressed)
	(%SaveButton as Button).pressed.connect(_on_save_pressed)
	(%LoadButton as Button).pressed.connect(_on_load_pressed)

	_preset.select(1)                                             # 預設打開 U 形牆
	_on_preset_selected(1)


func _process(delta: float) -> void:
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
	_refresh()


func _refresh() -> void:
	_update_labels()
	_grid_view.queue_redraw()


func _update_labels() -> void:
	_weight.editable = search.algorithm == GridSearch.Algorithm.ASTAR
	_corner.disabled = not _diagonal.button_pressed
	var hint: String = "（BFS 不用）" if search.algorithm == GridSearch.Algorithm.BFS else ""
	_weight_label.text = "估計權重：%.1f %s" % [_weight.value, hint]
	_speed_label.text = "速度：每秒 %d 步" % roundi(_speed.value)
	var state: String = "找路中……"
	if search.finished:
		state = "找到了！" if search.found else "走不到！"
	var length: String = "%.1f" % search.path_length() if search.found else "－"
	_stats.text = "探索了 %d 格\n待探索 %d 格\n路徑長度 %s\n%s" % [search.closed.size(), _count_open(), length, state]


func _count_open() -> int:
	var unique: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in search.open:
		if not search.closed.has(cell):
			unique[cell] = true
	return unique.size()


func _on_step_pressed() -> void:
	_play.button_pressed = false
	search.step()
	_refresh()


func _on_preset_selected(index: int) -> void:
	AStarPresets.apply(AStarPresets.MAPS[_preset.get_item_text(index)], search)
	_restart()


func _on_clear_pressed() -> void:
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
	elif event is InputEventMouseMotion and _drag != 0:
		_apply_drag(_cell_at((event as InputEventMouseMotion).position))


func _apply_drag(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= search.size.x or cell.y >= search.size.y:
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
				search.costs[cell] = AStarPresets.SWAMP_COST
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
	_restart()


func _cell_at(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))


# ---- 存讀自己畫的地圖 ----

func _on_save_pressed() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("slot%d" % _slot.selected, "rows", AStarPresets.to_rows(search))
	config.save(SAVE_PATH)


func _on_load_pressed() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var rows: Variant = config.get_value("slot%d" % _slot.selected, "rows", null)
	if rows is PackedStringArray and (rows as PackedStringArray).size() == search.size.y:
		AStarPresets.apply(Array(rows as PackedStringArray), search)
		_restart()


# ---- 畫格子 ----

func _draw_grid() -> void:
	var on_path: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in search.path:
		on_path[cell] = true
	var font: Font = get_theme_default_font()
	for y: int in search.size.y:
		for x: int in search.size.x:
			var cell: Vector2i = Vector2i(x, y)
			var rect: Rect2 = Rect2(Vector2(cell * CELL), Vector2(CELL, CELL))
			_grid_view.draw_rect(rect, SWAMP_COLOR if search.costs.has(cell) else FLOOR_COLOR)
			var overlay: Color = _cell_color(cell)
			if overlay.a > 0.0:
				_grid_view.draw_rect(rect, overlay)
			_grid_view.draw_rect(rect, LINE_COLOR, false, 1.0)
			if _scores.button_pressed and search.g.has(cell) and not search.walls.has(cell):
				var value: float = search.g[cell] if search.algorithm == GridSearch.Algorithm.BFS else search.score(cell)
				_grid_view.draw_string(font, rect.position + Vector2(0, 23), str(roundi(value)), HORIZONTAL_ALIGNMENT_CENTER, CELL, 11, TEXT_COLOR)
	# 最終路徑畫成一條線
	if search.path.size() >= 2:
		var points: PackedVector2Array = PackedVector2Array()
		for cell: Vector2i in search.path:
			points.append(Vector2(cell * CELL) + Vector2(CELL, CELL) / 2.0)
		_grid_view.draw_polyline(points, PATH_COLOR, 5.0)
	_draw_endpoint(search.start_cell, START_COLOR)
	_draw_endpoint(search.goal_cell, GOAL_COLOR)


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
