extends LevelEditor
## 塔防編輯器（開發者用）：打開 map_editor.tscn 按 F6。上面三頁：
##   ・地圖：下面說的這些
##   ・波次：一波一波出什麼怪（wave_page.gd），存成 waves/名稱.tres，拖進關卡 Spawner 的 Wave Table
##   ・怪物：改怪的數值、掛件（enemy_page.gd），存成 features/enemies/ 的場景
## 三頁共用上一步／下一步和試玩（試玩用現在畫的地圖＋現在排的波次）。
## 「做成關卡」：把存好的地圖＋波次做成一個關卡場景（level_maker.gd），再拖進 game_config.tres 的 Levels 就能串關。
##
## 地圖頁：
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
## 分頁、上一步、存檔、試玩這些共用的在 core/level_editor/，這裡只有塔防自己的。

enum Page { MAP, WAVES, ENEMIES }
enum Tool { ROCK, SWAMP, HIGH, SPAWN, BASE }

## 現在的地圖（跟 map 是同一個，型別清楚一點）
var td: TDMap:
	get: return map as TDMap
## 試玩從第幾波開始（重來的時候用一樣的）
var resume_wave: int:
	get: return _session.get("resume_wave", 1)
	set(value): _session["resume_wave"] = value

## 哪種地面可以蓋塔、蓋牆的勾選（照 TDMap.Ground 的順序）
var _tower_checks: Array[CheckBox] = []
var _wall_checks: Array[CheckBox] = []
var _wave_page: TDWavePage
var _enemy_page: TDEnemyPage


func _setup() -> void:
	title = "塔防編輯器"
	back_text = "回地圖編輯器"
	maps_dir = "res://examples/tower_defense/maps/"
	play_scene = load("res://examples/tower_defense/levels/tower_defense.tscn")
	save_needs_ok = true
	camera_margin = Vector4(64, 48, 64, 128)
	ui_left = 64.0
	stop_position = Vector2(940, 22)
	for text: String in ["岩石", "沼澤", "高地"]:
		add_tool(text, true)
	add_tool("出怪口")
	add_tool("基地")


func _new_map() -> Resource:
	return TDMap.new()


func _make_view() -> Node2D:
	var view: TerrainView = TerrainView.new()
	view.draw_floor = true
	view.map = td
	return view


func _map_shown() -> void:
	for i: int in TDMap.GROUND_NAMES.size():
		_tower_checks[i].set_pressed_no_signal(TDMap.has_ground(td.tower_ground, i as TDMap.Ground))
		_wall_checks[i].set_pressed_no_signal(TDMap.has_ground(td.wall_ground, i as TDMap.Ground))


# ---- 畫 ----

func _kind() -> TDMap.Kind:
	match tool:
		Tool.SWAMP: return TDMap.Kind.SWAMP
		Tool.HIGH: return TDMap.Kind.HIGH
	return TDMap.Kind.ROCK


func _paint_dab(at: Vector2) -> void:
	td.paint(_kind(), at, brush, _erasing)


func _paint_rect(from: Vector2, to: Vector2) -> void:
	td.paint_rect(_kind(), Rect2(from, to - from), _erasing)


func _paint_ellipse(from: Vector2, to: Vector2) -> void:
	td.paint_ellipse(_kind(), Rect2(from, to - from), _erasing)


func _paint_fill(at: Vector2) -> int:
	return td.fill(_kind(), at, _erasing)


func _clear() -> void:
	td.clear()


## 多放一個出怪口或基地（那一格已經有就不放）
func place(cell: Vector2i) -> bool:
	if not has_cell(cell) or td.spawn_cells.has(cell) or td.base_cells.has(cell):
		return false
	remember()
	_cells().append(cell)
	return true


func unplace(cell: Vector2i) -> bool:
	if not _cells().has(cell):
		return false
	remember()
	_cells().erase(cell)
	return true


## 現在的工具放的是哪一種
func _cells() -> Array[Vector2i]:
	return td.spawn_cells if tool == Tool.SPAWN else td.base_cells


## 改「哪種地面可以蓋塔／蓋牆」（walls＝改牆的；on＝勾起來）
func set_ground_rule(walls: bool, which: TDMap.Ground, on: bool) -> void:
	remember()
	var bit: int = 1 << which
	if walls:
		td.wall_ground = (td.wall_ground | bit) if on else (td.wall_ground & ~bit)
	else:
		td.tower_ground = (td.tower_ground | bit) if on else (td.tower_ground & ~bit)
	show_map()


## 少了出怪口或基地就不能玩
func check_map() -> String:
	if td.spawn_cells.is_empty():
		return "至少要放一個出怪口"
	if td.base_cells.is_empty():
		return "至少要放一個基地"
	return ""


## 出怪口、基地（好幾個的話標上號碼）
func _draw_map(canvas: Node2D) -> void:
	for i: int in td.spawn_cells.size():
		_draw_marker(canvas, td.spawn_cells[i], Color(0.9, 0.3, 0.3), "出怪口" if td.spawn_cells.size() == 1 else "出怪口%d" % (i + 1))
	for i: int in td.base_cells.size():
		_draw_marker(canvas, td.base_cells[i], Color("4ab86a"), "基地" if td.base_cells.size() == 1 else "基地%d" % (i + 1))


func _draw_marker(canvas: Node2D, cell: Vector2i, color: Color, text: String) -> void:
	var center: Vector2 = cell_center(cell)
	canvas.draw_rect(Rect2(center - Vector2(14, 14), Vector2(28, 28)), color, false, 3.0)
	canvas.draw_circle(center, 5.0, color)
	canvas.draw_string(get_window().get_theme_default_font(), center + Vector2(-24, -20), text, HORIZONTAL_ALIGNMENT_CENTER, 48, 12, color)


# ---- 試玩、做成關卡 ----

## 開始試玩（from_wave：從第幾波開始，前面幾波的錢先給）
func start_test(from_wave: int = 1) -> bool:
	if not is_testing():
		resume_wave = from_wave
	return super()


func _resume() -> void:
	start_test(resume_wave)


func _before_test() -> void:
	MapLoader.test_map = td.duplicate(true) as TDMap
	MapLoader.test_waves = _wave_page.table.copy()
	MapLoader.test_start_wave = resume_wave
	MapLoader.test_money = _wave_page.money_before(resume_wave)
	if _enemy_page.dirty:
		say("提醒：怪物「%s」改了還沒存檔，試玩用的是存過的" % _enemy_page.data.get("display_name", ""))


func _level_request(map_path: String) -> Dictionary:
	var waves_path: String = _wave_page.saved_path()
	if _wave_page.is_dirty() or waves_path.is_empty():
		say("波次還沒存檔，先到「波次」頁按存檔")
		return {}
	return TDLevelMaker.request(map_path, waves_path)


# ---- 介面 ----

func _build_rows() -> void:
	var row: HBoxContainer = add_row(594)
	add_tool_buttons(row)
	add_shape_buttons(row)
	add_size_boxes(row)
	row = add_row(628)                                            # 第二排：檔案
	add_file_controls(row, true)
	row = add_row(662)                                            # 第三排：哪種地面可以蓋塔、蓋牆
	_tower_checks = _ground_checks(row, "塔可以蓋在：", false)
	row.add_child(VSeparator.new())
	_wall_checks = _ground_checks(row, "牆可以蓋在：", true)


## 波次頁（右邊，左邊看得到地圖上的出怪口）、怪物頁（整個畫面）
func _build_pages() -> void:
	add_page("地圖")
	_wave_page = TDWavePage.new()
	_wave_page.name = "WavePage"
	_wave_page.test_requested.connect(func(wave_number: int) -> void: start_test(wave_number))
	add_page("波次", _wave_page, Rect2(220, 48, 1040, 640), "排好按「存檔」，再把 waves/ 裡的檔案拖進關卡 Spawner 的 Wave Table", true)
	_enemy_page = TDEnemyPage.new()
	_enemy_page.name = "EnemyPage"
	_enemy_page.saved.connect(func(_path: String) -> void: _wave_page.refresh())
	add_page("怪物", _enemy_page, Rect2(64, 48, 1196, 640), "改好按「存檔」，波次頁和試玩就會用新的", true)


func _page_shown(index: int) -> void:
	if index == Page.WAVES:
		_wave_page.spawn_count = td.spawn_cells.size()            # 出怪口的號碼跟地圖上的一樣
		_wave_page.refresh()


## 一排地面勾選：空地、沼澤、高地、岩石（walls＝牆的，否則是塔的）
func _ground_checks(parent: Control, text: String, walls: bool) -> Array[CheckBox]:
	add_label(parent, text)
	var checks: Array[CheckBox] = []
	for i: int in TDMap.GROUND_NAMES.size():
		var check: CheckBox = CheckBox.new()
		check.text = TDMap.GROUND_NAMES[i]
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(func(on: bool) -> void: set_ground_rule(walls, i as TDMap.Ground, on))
		parent.add_child(check)
		checks.append(check)
	return checks
