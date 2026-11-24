extends LevelEditor
## 戰棋編輯器（開發者用）：打開 map_editor.tscn 按 F6。上面五頁：
##   ・地圖：畫地形（圓滑的或對齊格子）、放起點／目標／物資／寶箱／同伴／敵人／巡邏點
##   ・小隊：每一隊的視野、反應時間、巡邏、支援、掉落物資、首領（squad_page.gd）
##   ・棋子：改數值、個性，勾特性（unit_page.gd），存成 features/units/ 的場景
##   ・隊伍：玩家的起始隊伍（pool_page.gd），存成 party_pool.tres，每一關共用
##   ・規則：這一關固定的隊伍、過關獎勵、勝利條件、自動或回合制、陣形、分開走、骰子、營地物資（rule_page.gd）
## 地圖、小隊、規則存在同一個檔案 maps/名稱.tres；棋子各自一個場景。
## 「做成關卡」：把存好的地圖做成一個關卡場景，再拖進 game_config.tres 的 Levels 就能串關。
##
## 地圖頁：畫筆、矩形、圓形、油漆桶，打開「對齊格子」就一格一格畫（兩種可以混用）。規則看格子中心在哪種地形裡。
## 左鍵畫（放）、右鍵擦（拿掉）、滾輪調筆刷；WASD／滑鼠到邊緣／中鍵移動畫面、Ctrl＋滾輪縮放；
## Ctrl＋Z 上一步、Ctrl＋Y 下一步。
## 分頁、上一步、存檔、試玩這些共用的在 core/level_editor/，這裡只有戰棋自己的。

enum Page { MAP, SQUADS, UNITS, RULES, POOL }
## 前面是地形（順序跟 TacticsMap.Kind 一樣）
enum Tool { PLAIN, WALL, SWAMP, FOREST, HIGH, START, GOAL, SUPPLY, CHEST, ALLY, ENEMY, PATROL }
## 放東西的工具（接在地形後面）
const THING_NAMES: Array[String] = ["起點", "目標", "物資", "寶箱", "同伴", "敵人", "巡邏點"]
## 小隊的顏色（輪流用）
const SQUAD_COLORS: Array[Color] = [Color("e0574a"), Color("e09a3a"), Color("b05ad0"), Color("3aa0b0"), Color("d05a90"), Color("8a8a3a")]

## 現在的地圖（跟 map 是同一個，型別清楚一點）
var tac: TacticsMap:
	get: return map as TacticsMap
## 寶箱裡放幾份物資
var chest_amount: int = 1
## 敵人、同伴工具放哪一種棋子
var unit_path: String = ""

var _chest_box: SpinBox
var _squad_list: OptionButton
var _unit_list: OptionButton
var _unit_paths: PackedStringArray = PackedStringArray()
var _squad_page: TacticsSquadPage
var _unit_page: TacticsUnitPage
var _rule_page: TacticsRulePage
var _pool_page: TacticsPoolPage


func _setup() -> void:
	title = "戰棋編輯器"
	back_text = "回戰棋編輯器"
	maps_dir = "res://examples/tactics/maps/"
	play_scene = load("res://examples/tactics/levels/tactics.tscn")
	min_size = Vector2i(8, 6)
	max_size = Vector2i(100, 100)
	max_brush = 144.0
	for i: int in TacticsMap.KIND_NAMES.size():
		add_tool(TacticsMap.KIND_NAMES[i], true, i == TacticsMap.KIND_NAMES.size() - 1)
	for text: String in THING_NAMES:
		add_tool(text, false, text == "同伴")
	tool = Tool.WALL


func _exit_tree() -> void:
	super()
	TacticsPool.end_test()


## 新地圖：外面一圈牆（隊伍用玩家的隊伍池）
func _new_map() -> Resource:
	var fresh: TacticsMap = TacticsMap.new()
	fresh.ensure()
	fresh.paint_cells(TacticsMap.Kind.WALL, Rect2i(Vector2i.ZERO, fresh.size))
	fresh.paint_cells(TacticsMap.Kind.PLAIN, Rect2i(Vector2i.ONE, fresh.size - Vector2i(2, 2)))
	return fresh


func _make_view() -> Node2D:
	var view: TacticsTerrain = TacticsTerrain.new()
	view.map = tac
	return view


func _use_map() -> void:
	_squad_page.index = 0
	super()


func _map_shown() -> void:
	_squad_page.map = tac
	_rule_page.map = tac
	_refresh_pages()
	if page == Page.SQUADS:
		look_at_squad()


func _refresh_pages() -> void:
	_pool_page.refresh()
	_squad_page.refresh()
	_rule_page.refresh()
	_refresh_squads()
	_view.queue_redraw()


# ---- 畫、放 ----

## 現在畫的地形（右鍵＝擦成空地）
func _kind() -> TacticsMap.Kind:
	return TacticsMap.Kind.PLAIN if _erasing else tool as TacticsMap.Kind


func _paint_dab(at: Vector2) -> void:
	if snap:
		tac.paint_cells(_kind(), brush_cells(at))
	else:
		tac.paint(_kind(), at, brush)


func _paint_rect(from: Vector2, to: Vector2) -> void:
	if snap:
		tac.paint_cells(_kind(), cells_between(from, to))
	else:
		tac.paint_rect(_kind(), Rect2(from, to - from))


func _paint_ellipse(from: Vector2, to: Vector2) -> void:
	if snap:
		tac.paint_cell_ellipse(_kind(), cells_between(from, to))
	else:
		tac.paint_ellipse(_kind(), Rect2(from, to - from))


func _paint_fill(at: Vector2) -> int:
	return tac.fill(_kind(), at)


## 清空地形（外面一圈牆留著）
func _clear() -> void:
	tac.paint_cells(TacticsMap.Kind.PLAIN, Rect2i(Vector2i.ONE, tac.size - Vector2i(2, 2)))


func check_map() -> String:
	return tac.problem()


## 放東西（起點、目標、物資、敵人、巡邏點）
func place(cell: Vector2i) -> bool:
	if not has_cell(cell):
		return false
	if tac.kind_at(cell) == TacticsMap.Kind.WALL:
		say("牆上不能放")
		return false
	match tool:
		Tool.START:
			if tac.start_cell == cell:
				return false
			remember()
			tac.start_cell = cell
		Tool.GOAL, Tool.SUPPLY:
			var list: Array[Vector2i] = tac.goal_cells if tool == Tool.GOAL else tac.supply_cells
			if list.has(cell):
				return false
			remember()
			list.append(cell)
		Tool.CHEST:
			if tac.chests.get(cell, -1) == chest_amount:
				return false
			remember()
			tac.chests[cell] = chest_amount                       # 點已經有的寶箱＝改成現在的份數
		Tool.ALLY:
			if tac.allies.get(cell, "") == unit_path:
				return false
			remember()
			tac.allies[cell] = unit_path                          # 點已經有的同伴＝換成現在選的棋子
		Tool.ENEMY:
			if tac.enemy_at(cell).x >= 0:
				say("那一格已經有敵人了（右鍵拿掉）")
				return false
			remember()
			_ensure_squad().add(unit_path, cell)
		Tool.PATROL:
			var squad: TacticsSquad = _squad_page.squad()
			if squad == null or squad.members.is_empty():
				say("先用「敵人」放這一隊的隊員，再放巡邏點")
				return false
			remember()
			squad.patrol.append(cell)
	tac.emit_changed()
	_refresh_pages()
	return true


## 拿掉 cell 上的東西（看現在的工具）
func unplace(cell: Vector2i) -> bool:
	match tool:
		Tool.GOAL, Tool.SUPPLY:
			var list: Array[Vector2i] = tac.goal_cells if tool == Tool.GOAL else tac.supply_cells
			if not list.has(cell):
				return false
			remember()
			list.erase(cell)
		Tool.CHEST:
			if not tac.chests.has(cell):
				return false
			remember()
			tac.chests.erase(cell)
		Tool.ALLY:
			if not tac.allies.has(cell):
				return false
			remember()
			tac.allies.erase(cell)
		Tool.ENEMY:
			var found: Vector2i = tac.enemy_at(cell)
			if found.x < 0:
				return false
			remember()
			tac.squads[found.x].remove_at(found.y)
		Tool.PATROL:
			var squad: TacticsSquad = _squad_page.squad()
			if squad == null or not squad.patrol.has(cell):
				return false
			remember()
			squad.patrol.remove_at(squad.patrol.rfind(cell))
		_:
			return false
	tac.emit_changed()
	_refresh_pages()
	return true


## 現在選的小隊（一隊都沒有就新增一隊）
func _ensure_squad() -> TacticsSquad:
	if _squad_page.squad() == null:
		var fresh: TacticsSquad = TacticsSquad.new()
		fresh.squad_name = "小隊1"
		tac.squads.append(fresh)
		_squad_page.index = tac.squads.size() - 1
	return _squad_page.squad()


# ---- 畫在地形上面 ----

func _draw_map(canvas: Node2D) -> void:
	var selected: int = _squad_page.index
	for i: int in tac.squads.size():
		_draw_squad(canvas, tac.squads[i], i, i == selected)
	for cell: Vector2i in tac.allies:
		var look: Dictionary = TacticsUnitInfo.look(tac.allies[cell])
		Unit.draw_token(canvas, cell_center(cell), Unit.RADIUS, look["color"], Color("4ab86a"), look["mark"])
		canvas.draw_string(Unit.font(), cell_center(cell) + Vector2(-30, -16), "同伴", HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color("1e5a2e"))
	var start: Vector2 = cell_center(tac.start_cell)
	canvas.draw_circle(start, 13.0, Unit.TEAM_COLORS[0])
	canvas.draw_string(Unit.font(), start + Vector2(-16, 5), "起點", HORIZONTAL_ALIGNMENT_CENTER, 32, 11, Color.WHITE)


## 一隊：隊員、巡邏路線、視野（選中的那隊畫清楚一點）
func _draw_squad(canvas: Node2D, squad: TacticsSquad, number: int, selected: bool) -> void:
	if squad.members.is_empty():
		return
	var color: Color = SQUAD_COLORS[number % SQUAD_COLORS.size()]
	var soft: Color = Color(color, 0.9 if selected else 0.4)
	var leader: Vector2 = cell_center(squad.cells[0])
	var half: float = deg_to_rad(squad.view_angle) / 2.0
	for k: int in squad.members.size():
		if squad.view_of(k) <= 0.0:
			continue
		var at: Vector2 = cell_center(squad.cells[k])
		var cone: PackedVector2Array = PackedVector2Array([at])
		for i: int in 17:
			cone.append(at + Vector2.from_angle(squad.look_angle(k) - half + half * 2.0 * i / 16.0) * squad.view_of(k))
		canvas.draw_colored_polygon(cone, Color(color, (0.22 if selected else 0.1) * (1.0 if k == 0 else 0.5)))
	var from: Vector2 = leader
	for i: int in squad.patrol.size():
		var to: Vector2 = cell_center(squad.patrol[i])
		canvas.draw_line(from, to, soft, 2.0)
		canvas.draw_circle(to, 5.0, soft)
		canvas.draw_string(Unit.font(), to + Vector2(6, -4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, soft)
		from = to
	if squad.patrol_mode == 1 and squad.patrol.size() > 1:
		canvas.draw_line(from, cell_center(squad.patrol[0]), soft, 1.0)
	for i: int in squad.members.size():
		var look: Dictionary = TacticsUnitInfo.look(squad.members[i])
		var at: Vector2 = cell_center(squad.cells[i])
		Unit.draw_token(canvas, at, Unit.RADIUS, look["color"], color, look["mark"])
		if selected:
			canvas.draw_arc(at, 15.0, 0, TAU, 24, Color.WHITE, 2.0)
	canvas.draw_string(Unit.font(), leader + Vector2(-60, -18), "%d %s%s" % [number + 1, squad.squad_name, "（首領）" if squad.boss else ""], HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color.WHITE if selected else color.lightened(0.4))


# ---- 換頁 ----

func _page_shown(index: int) -> void:
	_refresh_pages()
	if index == Page.SQUADS:
		look_at_squad()


## 把畫面移到現在選的小隊（小隊頁放在面板右邊；太散就縮小到看得完）
func look_at_squad() -> void:
	var squad: TacticsSquad = _squad_page.squad()
	if squad == null or squad.members.is_empty() or is_testing():
		return
	var rect: Rect2 = Rect2(cell_center(squad.cells[0]), Vector2.ZERO)
	for cell: Vector2i in squad.cells:
		rect = rect.expand(cell_center(cell))
	var on_page: bool = page == Page.SQUADS
	look_at_rect(rect.grow(64.0), Rect2(836, 56, 432, 626) if on_page else Rect2(16, 56, 1248, 520), 1.0 if on_page else _camera.zoom.x)


# ---- 試玩、做成關卡 ----

func _before_test() -> void:
	if _pool_page.is_dirty():
		say("提醒：起始隊伍改了還沒存檔，試玩用的是存過的")
	if _unit_page.dirty:
		say("提醒：棋子「%s」改了還沒存檔，試玩用的是存過的" % _unit_page.data.get("display_name", ""))
	TacticsPool.begin_test()                                      # 試玩只有起始隊伍，不動玩家的存檔
	TacticsLevel.test_map = tac.copy()


func _after_test() -> void:
	TacticsPool.end_test()


func _level_request(map_path: String) -> Dictionary:
	if not tac.problem().is_empty():
		say(tac.problem())
		return {}
	return {"path": "res://examples/tactics/levels/%s.tscn" % map_path.get_file().get_basename(),
		"base": play_scene.resource_path, "values": {"TacticsLevel": {"map": map_path}}}


# ---- 介面 ----

func _build_rows() -> void:
	var row: HBoxContainer = add_row(592)
	add_tool_buttons(row)
	add_shape_buttons(row, true)
	row = add_row(626)                                            # 第二排：檔案、地圖大小
	add_file_controls(row)
	add_size_boxes(row)
	row.add_child(VSeparator.new())
	add_label(row, "寶箱裡有")
	_chest_box = SpinBox.new()
	_chest_box.min_value = 0
	_chest_box.max_value = 10
	_chest_box.value = chest_amount
	_chest_box.suffix = "份"
	_chest_box.tooltip_text = "新放的寶箱裡有幾份營地物資；點已經放的寶箱可以改"
	_chest_box.value_changed.connect(func(value: float) -> void:
		chest_amount = int(value)
		set_tool(Tool.CHEST))
	row.add_child(_chest_box)
	row = add_row(660)                                            # 第三排：敵人
	add_label(row, "敵人、巡邏點：")
	_squad_list = _options(row, 180)
	_squad_list.item_selected.connect(_on_squad_selected)
	add_label(row, "放哪一種（敵人、同伴）：")
	_unit_list = _options(row, 160)
	_unit_list.item_selected.connect(func(index: int) -> void:
		unit_path = _unit_paths[index]
		if tool != Tool.ALLY:
			set_tool(Tool.ENEMY))
	_refresh_units()


func _options(row: Control, width: float) -> OptionButton:
	var list: OptionButton = OptionButton.new()
	list.focus_mode = Control.FOCUS_NONE
	list.custom_minimum_size = Vector2(width, 0)
	row.add_child(list)
	return list


func _build_pages() -> void:
	add_page("地圖")
	_squad_page = TacticsSquadPage.new()
	_squad_page.name = "SquadPage"
	_squad_page.will_change.connect(remember)
	_squad_page.changed.connect(_refresh_squads)
	_squad_page.selected.connect(look_at_squad)
	add_page("小隊", _squad_page, Rect2(64, 48, 760, 640), "隊員和巡邏點在「地圖」頁放；小隊跟地圖一起存")
	_unit_page = TacticsUnitPage.new()
	_unit_page.name = "UnitPage"
	_unit_page.saved.connect(func(_path: String) -> void:
		_refresh_units()
		_refresh_pages())
	add_page("棋子", _unit_page, Rect2(64, 48, 1196, 640), "改好按「存檔」，地圖和試玩就會用新的", true)
	_rule_page = TacticsRulePage.new()
	_rule_page.name = "RulePage"
	_rule_page.will_change.connect(remember)
	add_page("規則", _rule_page, Rect2(64, 48, 1196, 640), "規則跟地圖一起存")
	_pool_page = TacticsPoolPage.new()
	_pool_page.name = "PoolPage"
	add_page("隊伍", _pool_page, Rect2(64, 48, 1196, 640), "起始隊伍每一關共用，改好按「存檔」", true)


## 小隊的下拉選單（最後一個是「＋ 新小隊」）
func _refresh_squads() -> void:
	_squad_list.clear()
	for i: int in tac.squads.size():
		_squad_list.add_item("%d %s" % [i + 1, tac.squads[i].squad_name])
	_squad_list.add_item("＋ 新小隊")
	_squad_list.select(_squad_page.index if not tac.squads.is_empty() else 0)


func _on_squad_selected(index: int) -> void:
	if index >= tac.squads.size():
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
	var index: int = maxi(_unit_paths.find(unit_path), 0)
	unit_path = _unit_paths[index]
	_unit_list.select(index)
