class_name Builder
extends Node2D
## 蓋東西：下面的按鈕（或按數字鍵 1～9）選要蓋什麼，滑鼠左鍵點格子蓋下去，右鍵拆掉（退一半的錢）。
## 左鍵點蓋好的塔＝升級。
## 蓋在空地、沼澤上的塔會擋路，怪物會即時改路；但塔不能把路完全堵死。
## 牆（block.tscn）可以被怪打破：怪會比較要繞路還是拆牆，所以可以用牆把路堵死。
## 高地、岩石本來就不能走，蓋在上面不影響怪的路。
## 蓋不了的格子會變紅，旁邊寫原因（會把路堵死、錢不夠……）。選塔的時候會先畫出射程。
##
## 哪種地面能蓋塔、能蓋牆，寫在地圖裡（地圖編輯器下面的勾選），MapLoader 讀地圖時告訴 Builder：
##   ・迷宮型：空地、沼澤可以蓋塔和牆，自己排迷宮讓怪繞路
##   ・固定路線型：只有高地可以蓋塔、沒有牆，怪走固定的路，塔蓋在路旁的高地
## 錢就是畫面上的分數（起手包的 ScoreDisplay），打死怪會加錢。
##
## 用法：拖進場景就好（出怪口、基地自己找：生怪器和它的 More Spawn Points、group「bases」）；
## 想多一種塔就把塔的場景加進 Tower Scenes。
## 不能堵死的規則：每個出怪口都要還走得到至少一個基地。

## 塔升級了
signal tower_upgraded(tower: Tower)
## 蓋了一個東西（what：0＝牆，1 以後＝Tower Scenes 的第幾種塔＋1）
signal built(cell: Vector2i, what: int)
## 選的東西變了
signal selection_changed(what: int)
## 規則變了（能不能蓋牆……）：下面的按鈕要重做
signal rules_changed()

## 前幾種可以用數字鍵選
const MAX_KEYS: int = 9

## 牆（血量、拆牆等於多走幾格、可不可以被破壞，在牆自己的檢查器改）
@export var wall_scene: PackedScene = preload("res://examples/tower_defense/features/builder/block.tscn")
## 牆多少錢
@export_range(0, 100, 1) var wall_cost: int = 1
## 可以蓋的塔（價錢、射程在塔自己的檢查器改）
@export var tower_scenes: Array[PackedScene] = [
	preload("res://examples/tower_defense/features/tower/tower.tscn"),
	preload("res://examples/tower_defense/features/tower/slow_tower.tscn"),
	preload("res://examples/tower_defense/features/tower/splash_tower.tscn"),
	preload("res://examples/tower_defense/features/tower/multi_tower.tscn"),
]

## 哪些地面可以蓋塔：TDMap.Ground 的 flags（地圖決定，用 set_rules() 改）
var tower_ground: int = 0b0111
## 哪些地面可以蓋牆（0＝沒有牆）
var wall_ground: int = 0b0011
## 現在要蓋什麼：0 牆、1 以後是塔（沒有牆的話不會是 0）
var selected: int = 0:
	set(value):
		selected = clampi(value, 0 if has_walls() else 1, tower_scenes.size())
		selection_changed.emit(selected)
## 蓋好的東西：格子 → 節點
var buildings: Dictionary[Vector2i, Node2D] = {}

var _grid: PathGrid
var _money: ScoreDisplay
## 「蓋在這格會不會堵死」很貴（要算好幾次 A*），滑鼠停在同一格時記住結果；地圖變了就重算
var _block_cache: Dictionary[Vector2i, bool] = {}
## 每種塔的樣本（讀價錢、射程、名字用，不放進場景）
var _samples: Array[Tower] = []
## 牆的樣本（看牆可不可以被破壞）
var _wall_sample: TDWall
## 剛剛點了蓋不了的地方：在那裡顯示原因
var _message: String = ""
var _message_at: Vector2
var _message_time: float = 0.0


func _enter_tree() -> void:
	add_to_group("builder")


func _ready() -> void:
	z_index = 3
	for scene: PackedScene in tower_scenes:
		_samples.append(scene.instantiate() as Tower)
	_wall_sample = wall_scene.instantiate() as TDWall


func _exit_tree() -> void:
	for sample: Tower in _samples:
		if is_instance_valid(sample):
			sample.free()
	if is_instance_valid(_wall_sample):
		_wall_sample.free()


func _unhandled_input(event: InputEvent) -> void:
	var choices: Array[int] = options()
	var key: InputEventKey = event as InputEventKey
	for i: int in mini(MAX_KEYS, choices.size()):
		var action: String = "skill_%d" % (i + 1)                 # 1～3 用起手包的按鍵，4～9 直接看數字鍵
		var pressed: bool = event.is_action_pressed(action) if InputMap.has_action(action) \
				else key != null and key.pressed and not key.echo and key.physical_keycode == KEY_1 + i
		if pressed:
			selected = choices[i]
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or not _ready_to_build():
		return
	var cell: Vector2i = _grid.cell_of(to_global((make_input_local(button) as InputEventMouseButton).position))
	if button.button_index == MOUSE_BUTTON_LEFT:
		var tower: Tower = tower_at(cell)
		if tower != null:
			_say(cell, "升到 Lv%d" % tower.level if upgrade(cell) else why_not_upgrade(cell))
		elif not build(cell):
			_say(cell, why_not(cell))                             # 蓋不了：在那裡顯示原因
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		remove(cell)
	else:
		return
	get_viewport().set_input_as_handled()


## 在 cell 上面顯示一下文字
func _say(cell: Vector2i, text: String) -> void:
	_message = text
	_message_at = _grid.cell_center(cell)
	_message_time = 1.5


## cell 上的塔（沒有就是 null）
func tower_at(cell: Vector2i) -> Tower:
	return buildings.get(cell) as Tower


## 把 cell 上的塔升一級；不能升回傳 false
func upgrade(cell: Vector2i) -> bool:
	if not _ready_to_build() or not why_not_upgrade(cell).is_empty():
		return false
	var tower: Tower = tower_at(cell)
	_money.add(-tower.upgrade_cost())
	tower.upgrade()
	tower_upgraded.emit(tower)
	return true


## 為什麼不能升級（可以升＝空字串）
func why_not_upgrade(cell: Vector2i) -> String:
	var tower: Tower = tower_at(cell)
	if tower == null:
		return "這裡沒有塔"
	if tower.max_level <= 1:
		return "這種塔不能升級"
	if not tower.can_upgrade():
		return "已經滿級（Lv%d）" % tower.level
	if _money.score < tower.upgrade_cost():
		return "錢不夠（升級要 %d 元）" % tower.upgrade_cost()
	return ""


## 滑鼠移到蓋好的東西上：等級、升級價格；受傷的牆顯示血量
func building_text(cell: Vector2i) -> String:
	var wall: TDWall = buildings.get(cell) as TDWall
	if wall != null:
		return "牆 %d/%d" % [ceili(wall.health), ceili(wall.max_health)] if wall.breakable else "牆（打不壞）"
	var tower: Tower = tower_at(cell)
	if tower == null:
		return ""
	if not tower.can_upgrade():
		return why_not_upgrade(cell)
	var text: String = "Lv%d → Lv%d　%d 元" % [tower.level, tower.level + 1, tower.upgrade_cost()]
	return text if why_not_upgrade(cell).is_empty() else text + "（錢不夠）"


## 換規則（MapLoader 讀地圖時呼叫）
func set_rules(tower_flags: int, wall_flags: int) -> void:
	tower_ground = tower_flags
	wall_ground = wall_flags
	selected = selected                                           # 沒有牆的話，從牆換成第一種塔
	_block_cache.clear()
	rules_changed.emit()


## 這一關有沒有牆（有任何地面能蓋牆）
func has_walls() -> bool:
	return wall_ground != 0


## 可以選的東西（0＝牆，沒有牆就沒有；1 以後＝塔）
func options() -> Array[int]:
	var result: Array[int] = []
	if has_walls():
		result.append(0)
	for i: int in tower_scenes.size():
		result.append(i + 1)
	return result


## 可以選的東西有幾種
func option_count() -> int:
	return options().size()


## 第幾種的名字和價錢，例如「牆 1 元」
func option_label(what: int) -> String:
	if what == 0:
		return "牆 %d 元" % wall_cost
	var sample: Tower = _samples[what - 1]
	return "%s %d 元" % [_tower_name(what), sample.cost]


## 塔的名字（塔自己的 Display Name；跟前面的塔同名就加號碼，才分得出來）
func _tower_name(what: int) -> String:
	var text: String = _samples[what - 1].display_name
	var same: int = 1
	for i: int in what - 1:
		if _samples[i].display_name == text:
			same += 1
	return text if same == 1 else "%s%d" % [text, same]


## 第幾種的價錢
func cost_of(what: int) -> int:
	return wall_cost if what == 0 else _samples[what - 1].cost


## 在 cell 蓋現在選的東西；蓋不了回傳 false
func build(cell: Vector2i) -> bool:
	if not _ready_to_build() or not can_build(cell):
		return false
	var node: Node2D = (wall_scene if selected == 0 else tower_scenes[selected - 1]).instantiate()
	get_parent().add_child(node)
	node.global_position = _grid.cell_center(cell)                # 先加進場景再設位置（反過來會多算關卡的偏移）
	buildings[cell] = node
	_money.add(-cost_of(selected))
	node.add_to_group("buildings")
	if node is TDWall:
		(node as TDWall).broken.connect(_on_wall_broken.bind(cell))
	if TDMap.is_walkable_ground(ground_at(cell)):                 # 空地、沼澤：怪會即時改路（高地、岩石本來就擋路）
		if node is TDWall:
			_grid.register_obstacle(node)                         # 牆：登記成障礙物（打得壞的話走得過去但很貴）
			_grid.map_changed.emit()
		else:
			_grid.set_blocked(cell, true)                         # 塔：不能走
	built.emit(cell, selected)
	return true


## 拆掉 cell 上的東西，退一半的錢（塔：蓋和升級花的都算；牆：照剩下的血量）
func remove(cell: Vector2i) -> bool:
	if not buildings.has(cell):
		return false
	var node: Node2D = buildings[cell]
	var wall: TDWall = node as TDWall
	_money.add(int((node as Tower).spent / 2.0 if node is Tower else wall_cost * wall.health_ratio() / 2.0))
	_take_away(cell)
	return true


## 把 cell 上的東西拿掉，尋路地圖變回原本的樣子（高地、岩石維持不能走）
func _take_away(cell: Vector2i) -> void:
	var node: Node2D = buildings[cell]
	var walkable: bool = TDMap.is_walkable_ground(ground_at(cell))
	buildings.erase(cell)
	if walkable and node is TDWall:
		_grid.unregister_obstacle(node)
	elif walkable:
		_grid.clear_blocked(cell)
	node.queue_free()


## 牆被怪打破了（不退錢）
func _on_wall_broken(cell: Vector2i) -> void:
	if buildings.has(cell) and _ready_grid():
		_take_away(cell)


## 這一格能不能蓋現在選的東西
func can_build(cell: Vector2i) -> bool:
	return why_not(cell).is_empty()


## 為什麼不能蓋（可以蓋＝空字串）
func why_not(cell: Vector2i) -> String:
	if not _ready_to_build() or not _grid.astar.is_in_boundsv(cell):
		return "不能蓋在地圖外面"
	if buildings.has(cell):
		return "這裡已經蓋了東西"
	var is_wall: bool = selected == 0
	var flags: int = wall_ground if is_wall else tower_ground
	var here: TDMap.Ground = ground_at(cell)
	if not TDMap.has_ground(flags, here):
		return "%s只能蓋在%s上" % ["牆" if is_wall else "塔", _ground_list(flags)]
	if _money.score < cost_of(selected):
		return "錢不夠（要 %d 元）" % cost_of(selected)
	if not TDMap.is_walkable_ground(here):
		return ""                                                 # 高地、岩石本來就擋路：蓋了也不會堵死
	var starts: Array[Node2D] = spawn_points()
	var goals: Array[Node2D] = goal_points()
	for node: Node2D in starts + goals:
		if _grid.cell_of(node.global_position) == cell:
			return "出怪口、基地上不能蓋"
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if _grid.cell_of((enemy as Node2D).global_position) == cell:
			return "有怪站在上面"
	if is_wall and _wall_sample.breakable:
		return ""                                                 # 打得壞的牆：堵死也沒關係，怪會拆
	if not _block_cache.has(cell):
		_block_cache[cell] = would_block(cell, starts, goals)
	if _block_cache[cell]:
		return "會把路堵死：怪會走不到基地"
	return ""


## 這一格是哪種地面（問 MapLoader；沒有 MapLoader：能走＝空地、不能走＝岩石）
func ground_at(cell: Vector2i) -> TDMap.Ground:
	var loader: MapLoader = get_tree().get_first_node_in_group("map_loader") as MapLoader
	if loader != null and loader.map != null:
		var map_cell: Vector2i = loader.map.cell_at(loader.to_local(_grid.cell_center(cell)))
		if loader.map.has_cell(map_cell):
			return loader.map.ground(map_cell)
	var walkable: bool = _grid.is_cell_walkable(cell) or buildings.has(cell)
	return TDMap.Ground.FLOOR if walkable else TDMap.Ground.ROCK


## 例如「空地、沼澤」
func _ground_list(flags: int) -> String:
	var names: PackedStringArray = PackedStringArray()
	for i: int in TDMap.GROUND_NAMES.size():
		if TDMap.has_ground(flags, i as TDMap.Ground):
			names.append(TDMap.GROUND_NAMES[i])
	return "、".join(names) if not names.is_empty() else "（哪裡都不行）"


## 蓋在 cell 會不會讓某個出怪口走不到任何基地
func would_block(cell: Vector2i, starts: Array[Node2D], goals: Array[Node2D]) -> bool:
	if goals.is_empty():
		return false
	for start: Node2D in starts:
		var reachable: bool = false
		for goal: Node2D in goals:
			if not _grid.would_block(cell, start.global_position, goal.global_position):
				reachable = true
				break
		if not reachable:
			return true
	return false


## 所有出怪口（每個生怪器和它的 More Spawn Points）
func spawn_points() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("spawners"):
		result.append_array((node as Spawner).spawn_points())
	return result


## 所有基地
func goal_points() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("bases"):
		result.append(node as Node2D)
	return result


func _ready_to_build() -> bool:
	if _money == null or not is_instance_valid(_money):
		_money = get_tree().get_first_node_in_group("score") as ScoreDisplay
	return _ready_grid() and _money != null and not GameFlow.is_finished()


func _ready_grid() -> bool:
	if _grid == null or not is_instance_valid(_grid):
		_grid = get_tree().get_first_node_in_group("path_grid") as PathGrid
		if _grid != null:
			_grid.map_changed.connect(func() -> void: _block_cache.clear())   # 地圖變了：堵不堵死要重算
	return _grid != null


func _process(delta: float) -> void:
	_message_time = maxf(_message_time - delta, 0.0)
	queue_redraw()


## 滑鼠指著的格子：綠色＝可以蓋、紅色＝不行；選塔的時候畫出射程
func _draw() -> void:
	if not _ready_to_build():
		return
	if _message_time > 0.0:
		_draw_text(to_local(_message_at) + Vector2(-60, -24), _message, Color(1, 0.75, 0.6, minf(_message_time, 1.0)))
	var cell: Vector2i = _grid.cell_of(get_global_mouse_position())
	if not _grid.astar.is_in_boundsv(cell):
		return
	var center: Vector2 = to_local(_grid.cell_center(cell))
	if buildings.has(cell):
		if _message_time <= 0.0:
			_draw_text(center + Vector2(20, -20), building_text(cell), Color(1, 0.9, 0.6))   # 等級、升級價格、牆的血量
		return
	var rect: Rect2 = Rect2(center - _grid.cell_size() / 2.0, _grid.cell_size())
	var reason: String = why_not(cell)
	var ok: bool = reason.is_empty()
	draw_rect(rect, Color(0.3, 1, 0.4, 0.3) if ok else Color(1, 0.3, 0.3, 0.3))
	draw_rect(rect, Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3), false, 2.0)
	if not ok and _message_time <= 0.0:
		_draw_text(center + Vector2(20, -20), reason, Color(1, 0.75, 0.6))    # 紅格子旁邊寫原因
	if selected > 0:
		var sample: Tower = _samples[selected - 1]
		draw_circle(center, sample.attack_range, Color(sample.color, 0.1))
		draw_arc(center, sample.attack_range, 0.0, TAU, 48, Color(sample.color, 0.7), 2.0)


func _draw_text(at: Vector2, text: String, color: Color) -> void:
	var font: Font = get_window().get_theme_default_font()
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, color.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
