extends LevelEditor
## 追逐編輯器（開發者用）：打開 map_editor.tscn 按 F6。上面兩頁：
##   ・地圖：畫牆、玻璃、草叢、地板、沼澤；放玩家、出口、敵人、巡邏點、寶物、門……點一下物件，右邊改它的數值
##   ・關卡：黑暗、鏡頭（setting_page.gd）
## 直接存成關卡場景 levels/名稱.tscn，在 Godot 裡也可以改（手動加的節點不會不見），拖進 game_config.tres 的 Levels 就能串關。
## 自己做的物件：放在 features/名字/名字.tscn，會出現在「其他」的清單裡。
## 分頁、上一步、存檔、試玩這些共用的在 core/level_editor/，這裡只有追逐自己的。

const FEATURES: String = "res://examples/chase/features/"
## 畫的：名字、圖塊
const TILES: Array[Array] = [["地板", ChaseMap.Tile.WOOD], ["磁磚", ChaseMap.Tile.TILES], ["沼澤", ChaseMap.Tile.SWAMP], ["牆", ChaseMap.Tile.WALL], ["玻璃", ChaseMap.Tile.GLASS], ["草叢", ChaseMap.Tile.BUSH]]
## 放的：名字、場景、存檔裡的名字、跟預設不一樣的數值
const THINGS: Array[Array] = [
	["玩家", ChaseMap.PLAYER, "Player", {}],
	["出口", ChaseMap.EXIT, "Exit", {}],
	["敵人", ChaseMap.ENEMY, "Enemy", {}],
	["寶物", FEATURES + "pickup/pickup.tscn", "Treasure", {}],
	["鑰匙", FEATURES + "pickup/pickup.tscn", "Key", {"kind": "紅", "required": false}],
	["任務點", FEATURES + "task_point/task_point.tscn", "TaskPoint", {}],
	["門", FEATURES + "door/door.tscn", "Door", {}],
	["躲藏點", FEATURES + "hiding_spot/hiding_spot.tscn", "HidingSpot", {}],
	["捕獸夾", FEATURES + "trap/trap.tscn", "Trap", {}],
	["警報", FEATURES + "alarm/alarm.tscn", "Alarm", {}],
	["瓶子", FEATURES + "throwable/bottle.tscn", "Bottle", {}],
]
const DOOR: String = FEATURES + "door/door.tscn"

## 現在的關卡（跟 map 是同一個，型別清楚一點）
var chase: ChaseMap:
	get: return map as ChaseMap
## 選取、巡邏點、其他：第幾個工具
var select_tool: int = 0
var patrol_tool: int = 0
var other_tool: int = 0
## 「其他」放哪一種
var other_scene: String = ""

var _panel: ChaseObjectPanel
var _setting_page: ChaseSettingPage
var _other_list: OptionButton
var _others: PackedStringArray = PackedStringArray()
## 正在拖第幾個物件（沒在拖＝-1）
var _dragging: int = -1


func _setup() -> void:
	title = "追逐編輯器"
	back_text = "回追逐編輯器"
	maps_dir = "res://examples/chase/levels/"
	grid_only = true
	brush = 16.0
	min_brush = 16.0
	max_brush = 80.0
	brush_step = 16.0
	min_size = Vector2i(8, 6)
	max_size = Vector2i(100, 100)
	for item: Array in TILES:
		add_tool(item[0], true)
	select_tool = tools.size()
	add_tool("選取")
	for item: Array in THINGS:
		add_tool(item[0])
	other_tool = tools.size()
	add_tool("其他")
	patrol_tool = tools.size()
	add_tool("巡邏點")
	tool = 3


## 新關卡：一間空房子，有玩家和出口
func _new_map() -> Resource:
	var fresh: ChaseMap = ChaseMap.new()
	for x: int in fresh.size.x:
		for y: int in fresh.size.y:
			var edge: bool = x == 0 or y == 0 or x == fresh.size.x - 1 or y == fresh.size.y - 1
			fresh.paint(Vector2i(x, y), ChaseMap.Tile.WALL if edge else ChaseMap.Tile.WOOD, false)
	fresh.add_object(ChaseMap.PLAYER, fresh.center_of(Vector2i(4, 9)), "Player")
	var door: Vector2i = Vector2i(18, fresh.size.y - 1)
	fresh.walls.erase(door)
	fresh.add_object(ChaseMap.EXIT, fresh.center_of(door), "Exit")
	return fresh


func _make_view() -> Node2D:
	return ChaseView.new()


func _map_shown() -> void:
	_panel.map = chase
	_setting_page.map = chase
	if _panel.index >= chase.objects.size():
		_panel.index = -1
	_panel.refresh()
	_setting_page.refresh()


func check_map() -> String:
	return chase.problem()


# ---- 畫格子 ----

func _paint_cells(cells: Rect2i, inside: Callable = func(_cell: Vector2i) -> bool: return true) -> void:
	for x: int in range(cells.position.x, cells.end.x):
		for y: int in range(cells.position.y, cells.end.y):
			if inside.call(Vector2i(x, y)):
				chase.paint(Vector2i(x, y), TILES[tool][1], _erasing)
	chase.emit_changed()


func _paint_dab(at: Vector2) -> void:
	_paint_cells(brush_cells(at))


func _paint_rect(from: Vector2, to: Vector2) -> void:
	_paint_cells(cells_between(from, to))


func _paint_ellipse(from: Vector2, to: Vector2) -> void:
	var cells: Rect2i = cells_between(from, to)
	var center: Vector2 = Vector2(cells.position) + Vector2(cells.size) / 2.0
	_paint_cells(cells, func(cell: Vector2i) -> bool:
		return ((Vector2(cell) + Vector2(0.5, 0.5) - center) / (Vector2(cells.size) / 2.0)).length() <= 1.0)


func _paint_fill(at: Vector2) -> int:
	var count: int = chase.fill(cell_at(at), TILES[tool][1], _erasing)
	chase.emit_changed()
	return count


## 清空：裡面都變成地板（外面一圈牆和物件留著）
func _clear() -> void:
	for cell: Vector2i in chase.walls.keys():
		if cell.x > 0 and cell.y > 0 and cell.x < chase.size.x - 1 and cell.y < chase.size.y - 1:
			chase.walls.erase(cell)
	for cell: Vector2i in chase.floors.keys():
		chase.floors[cell] = ChaseMap.Tile.WOOD
	chase.emit_changed()


# ---- 放東西 ----

## 點已經有東西的格子＝選它；空的＝放一個
func place(cell: Vector2i) -> bool:
	if not has_cell(cell):
		return false
	if tool == patrol_tool:
		return _place_patrol(cell)
	var found: int = chase.object_at(cell)
	if found >= 0 or tool == select_tool:
		select(found)
		return false
	var item: Array = thing()
	if item.is_empty():
		say("先在「其他」選一種物件")
		return false
	var scene: String = item[1]
	if scene == ChaseMap.PLAYER and chase.count_of(scene) > 0:
		say("已經有玩家了（用「選取」拖著移動）")
		return false
	var is_door: bool = scene == DOOR or scene == ChaseMap.EXIT
	if chase.walls.get(cell, -1) in [ChaseMap.Tile.WALL, ChaseMap.Tile.GLASS] and not is_door:
		say("牆上不能放（門和出口可以）")
		return false
	remember()
	var values: Dictionary = (item[3] as Dictionary).duplicate()
	if is_door:
		chase.walls.erase(cell)                                   # 門開在牆上：把那格牆拿掉，方向照旁邊的牆
		values["orientation"] = 0 if chase.walls.has(cell + Vector2i.LEFT) and chase.walls.has(cell + Vector2i.RIGHT) else 1
		if not chase.floors.has(cell):
			chase.floors[cell] = ChaseMap.Tile.WOOD
	var made: int = chase.add_object(scene, chase.center_of(cell), item[2], values)
	chase.emit_changed()
	select(made)
	return true


func _place_patrol(cell: Vector2i) -> bool:
	var now: Dictionary = _panel.object()
	if now.is_empty() or now["scene"] != ChaseMap.ENEMY:
		var found: int = chase.object_at(cell)
		if found >= 0 and chase.objects[found]["scene"] == ChaseMap.ENEMY:
			select(found)
			say("選了 %s，點地圖放它的巡邏點" % chase.objects[found]["name"])
		else:
			say("先點一隻敵人，再放它的巡邏點")
		return false
	remember()
	now["points"].append(chase.center_of(cell))
	_panel.refresh()
	return true


## 右鍵：拿掉物件（巡邏點工具：拿掉選的敵人的巡邏點）
func unplace(cell: Vector2i) -> bool:
	if tool == patrol_tool:
		var points: Array = _panel.object().get("points", [])
		for i: int in range(points.size() - 1, -1, -1):
			if cell_at(points[i]) == cell:
				remember()
				points.remove_at(i)
				_panel.refresh()
				return true
		return false
	var found: int = chase.object_at(cell)
	if found < 0:
		return false
	delete_object(found)
	return true


func delete_object(index: int) -> void:
	remember()
	for object: Dictionary in chase.objects:                      # 出口「指定」的目標也拿掉
		if object["values"].has("targets"):
			(object["values"]["targets"] as Array).erase(chase.objects[index]["name"])
	chase.objects.remove_at(index)
	chase.emit_changed()
	select(-1)


## 選第幾個物件（-1＝不選），右邊面板改它
func select(index: int) -> void:
	_panel.commit()
	_panel.index = index
	_panel.refresh()


## 現在的工具放什麼：THINGS 的一項（「其他」＝自己做的）
func thing() -> Array:
	if tool == other_tool:
		return [] if other_scene.is_empty() else ["其他", other_scene, other_scene.get_file().get_basename().to_pascal_case(), {}]
	return THINGS[tool - select_tool - 1]


## 一個物件是哪一種（鑰匙、寶物是同一個場景，看數值）
func kind_name(object: Dictionary) -> String:
	for item: Array in THINGS:
		if item[1] == object["scene"] and (item[2] != "Treasure" or object["values"]["kind"] == "寶物"):
			return item[0]
	return String(object["scene"]).get_file().get_basename()


## 用「選取」拖著物件走
func press(at: Vector2, erase: bool) -> void:
	super(at, erase)
	if tool == select_tool and not erase and _panel.index >= 0:
		_dragging = _panel.index
		remember()


func _mouse_moved(at: Vector2) -> void:
	if _dragging >= 0:
		move_object(_dragging, cell_at(at))


func release(at: Vector2) -> void:
	super(at)
	if _dragging >= 0 and _history.back() == chase.snapshot():
		_history.pop_back()                                       # 沒有移動：這一步不算
	_dragging = -1


## 移到某一格（有別的東西、牆上就不動）
func move_object(index: int, cell: Vector2i) -> bool:
	var other: int = chase.object_at(cell)
	if not has_cell(cell) or other >= 0 or chase.walls.get(cell, -1) in [ChaseMap.Tile.WALL, ChaseMap.Tile.GLASS]:
		return false
	chase.objects[index]["position"] = chase.center_of(cell)
	chase.emit_changed()
	return true


# ---- 畫在上面 ----

func _draw_map(canvas: Node2D) -> void:
	for i: int in chase.objects.size():
		var object: Dictionary = chase.objects[i]
		if object["scene"] == ChaseMap.ENEMY:
			_draw_enemy(canvas, object, i == _panel.index)
	var now: Dictionary = _panel.object()
	if not now.is_empty():
		canvas.draw_rect(cells_rect(Rect2i(cell_at(now["position"]), Vector2i.ONE)).grow(2), Color("ffd447"), false, 2.0)


## 敵人：視野和巡邏路線（選的那隻畫清楚一點）
func _draw_enemy(canvas: Node2D, object: Dictionary, selected: bool) -> void:
	var at: Vector2 = object["position"]
	var values: Dictionary = object["values"]
	var color: Color = values["body_color"]
	var half: float = deg_to_rad(values["view_angle"]) / 2.0
	var cone: PackedVector2Array = PackedVector2Array([at])
	for i: int in 25:
		cone.append(at + Vector2.from_angle(deg_to_rad(values["start_angle"]) - half + half * 2.0 * i / 24.0) * float(values["view_distance"]))
	canvas.draw_colored_polygon(cone, Color(color, 0.25 if selected else 0.1))
	var points: Array = object["points"]
	var line: Color = Color(color.lightened(0.3), 0.95 if selected else 0.45)
	var from: Vector2 = at
	for i: int in points.size():
		canvas.draw_line(from, points[i], line, 2.0)
		canvas.draw_circle(points[i], 6.0, line)
		canvas.draw_string(get_window().get_theme_default_font(), (points[i] as Vector2) + Vector2(8, -4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, line)
		from = points[i]
	if values["patrol_mode"] == 1 and points.size() > 1:
		canvas.draw_line(from, points[0], line, 1.0)


# ---- 存檔、試玩 ----

func _path_of(text: String) -> String:
	return maps_dir + text.validate_filename() + ".tscn"


func _write(path: String) -> Error:
	return chase.write(path)


func _read(path: String) -> Resource:
	return ChaseMap.read(path)


func _before_test() -> void:
	play_scene = chase.packed()
	(_view as ChaseView).show_objects(false)


func _after_test() -> void:
	(_view as ChaseView).refresh()


func resize_map(to: Vector2i) -> void:
	super(to)
	if chase.size.x > 38 or chase.size.y > 20:
		chase.settings["follow"] = true                           # 比畫面大：鏡頭要跟著玩家
		_setting_page.refresh()


# ---- 介面 ----

func _build_rows() -> void:
	var row: HBoxContainer = add_row(592)
	add_tool_buttons(row, 0, TILES.size())
	add_shape_buttons(row)
	row.add_child(VSeparator.new())
	add_tool_buttons(row, patrol_tool, 1)
	row = add_row(626)
	add_tool_buttons(row, select_tool, other_tool - select_tool + 1)
	_other_list = OptionButton.new()
	_other_list.focus_mode = Control.FOCUS_NONE
	_other_list.custom_minimum_size = Vector2(140, 0)
	_other_list.tooltip_text = "自己做的物件：features/名字/名字.tscn"
	_other_list.item_selected.connect(func(index: int) -> void:
		other_scene = _others[index]
		set_tool(other_tool))
	row.add_child(_other_list)
	row = add_row(660)
	add_file_controls(row)
	add_size_boxes(row)
	_refresh_others()


## features/ 裡自己做的物件（名字跟資料夾一樣、最上面是 Node2D，扣掉已經有按鈕的）
func _refresh_others() -> void:
	_others.clear()
	_other_list.clear()
	for dir: String in DirAccess.get_directories_at(FEATURES):
		var path: String = "%s%s/%s.tscn" % [FEATURES, dir, dir]
		if not ResourceLoader.exists(path) or THINGS.any(func(t: Array) -> bool: return t[1] == path):
			continue
		var node: Node = (load(path) as PackedScene).instantiate()
		if node is Node2D:
			_others.append(path)
			_other_list.add_item(dir)
		node.free()
	_other_list.disabled = _others.is_empty()
	if _others.is_empty():
		_other_list.add_item("（還沒有）")
	else:
		other_scene = _others[0]
	_other_list.select(0)


func _build_pages() -> void:
	add_page("地圖", null, Rect2(), "左鍵畫或放、右鍵擦掉；「選取」可以拖著移動；點物件在右邊改數值")
	_panel = ChaseObjectPanel.new()
	_panel.name = "ObjectPanel"
	_panel.will_change.connect(remember)
	_panel.delete_pressed.connect(func() -> void: delete_object(_panel.index))
	_panel.kind_name = kind_name
	add_panel(_panel, Rect2(900, 52, 370, 526), _map_tools)
	_panel.visible = false
	_setting_page = ChaseSettingPage.new()
	_setting_page.name = "SettingPage"
	_setting_page.will_change.connect(remember)
	add_page("關卡", _setting_page, Rect2(64, 48, 700, 560), "跟關卡一起存")


func _page_shown(index: int) -> void:
	if index == 1:
		_setting_page.refresh()


## 存的就是關卡，不用「做成關卡」
func _build_top(_row_box: Control) -> void:
	pass
