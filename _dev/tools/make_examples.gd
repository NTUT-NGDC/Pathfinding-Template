extends Node
## 產生三個範例關卡（examples/*/levels/*.tscn）。用文字地圖畫，比手動在編輯器畫快；改了地圖再執行一次：
##   godot --headless --path . res://_dev/tools/make_examples.tscn
## 加上 `-- chase`／`-- tower_defense`／`-- tactics` 只產生其中一個。
##
## 追逐：P 玩家　M 巡邏的追逐 AI（1～4 巡邏點）　N 守衛　T 寶物　K 紅鑰匙　L 紅色上鎖的門　D／d 門　R 任務點（發電機）　C／E 躲藏點　X 出口
## 共用符號：# 牆　G 玻璃　b 草叢　~ 沼澤　. 木頭地板　, 磁磚地板　空白＝房子外面

const TILE: int = 32
const TILESET: String = "res://addons/ngdc_pathfinding/grid/tileset/tileset.tres"
## 整個關卡往右下移一點，放在 1280×720 的畫面中間
const OFFSET: Vector2 = Vector2(64, 48)

const CHASE_MAP: PackedStringArray = [
	"####################################",
	"#........#,,,,,,,,,,,,,,#..........#",
	"#..E..K..#,,,,,,,,,,,,,,#....T.....#",
	"#........#,,,,,,,,,,,,,,#..........#",
	"#....T...D,,,,,,,,,,,,,,D.......N..#",
	"#........#,,,,,,,,,,,,,,#.....C....#",
	"###GGG####,,,,,bbb,,,,,,###GGG######",
	"#........#,,,,,bbb,,,,,,,,,,,,,,,,,#",
	"#........#,,,,,,,,,,,,,,,,,,,,R,,,,#",
	"#..P.....D,,1M,,,,,,,,,2,,,,,,,,,,,#",
	"#........#,,,,,,,,,,,,,,,,,,,,,,,,,#",
	"#...C....#,,,,,,,,,,,,,,#####L######",
	"#........G,,,,,,,,,,,,,,#..........#",
	"#........G,,,,,,,,bbb,,,#....T.....#",
	"#........#,,,,,,,,bbb,,,#..........#",
	"#........#,,,,,,,,,,,,,,#....E.....#",
	"#........#,,4,,,,,,,,,3,#..........#",
	"################X###################",
]

const TD_MAP: PackedStringArray = [
	"####################################",
	"#..................................#",
	"#..................................#",
	"#.......#..............~~~.........#",
	"#.......#..............~~~.........#",
	"#.......#.........#....~~~.........#",
	"#.......#.........#................#",
	"#.................#................#",
	"#S................#...............H#",
	"#.................#................#",
	"#.......#.........#................#",
	"#.......#.........#....~~~.........#",
	"#.......#..............~~~.........#",
	"#.......#..............~~~.........#",
	"#..................................#",
	"#..................................#",
	"####################################",
]

const TACTICS_MAP: PackedStringArray = [
	"##########################",
	"#........................#",
	"#..A.......~~~......Z....#",
	"#..........~~~...........#",
	"#....###...~~~...###.....#",
	"#..A.###.........###..Z..#",
	"#....###...~~~...###.....#",
	"#..........~~~...........#",
	"#..A.......~~~......Z....#",
	"#........................#",
	"##########################",
]

var _root: Node2D


func _ready() -> void:
	var only: PackedStringArray = OS.get_cmdline_user_args()
	var ok: bool = true
	if only.is_empty() or only.has("chase"):
		ok = _save(_build_chase(), "res://examples/chase/levels/chase.tscn") and ok
	if only.is_empty() or only.has("tower_defense"):
		ok = _save(_build_tower_defense(), "res://examples/tower_defense/levels/tower_defense.tscn") and ok
	if only.is_empty() or only.has("tactics"):
		ok = _save(_build_tactics(), "res://examples/tactics/levels/tactics.tscn") and ok
	get_tree().quit(0 if ok else 1)


func _save(root: Node2D, path: String) -> bool:
	var scene: PackedScene = PackedScene.new()
	var error: Error = scene.pack(root)
	if error == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		error = ResourceSaver.save(scene, path)
	print("存檔 %s：%s" % [path, error_string(error)])
	root.free()
	return error == OK


# ---- 追逐 ----

func _build_chase() -> Node2D:
	_new_root("Chase")
	var layers: Array[TileMapLayer] = _paint(CHASE_MAP)
	var counts: Dictionary[String, int] = {}
	var markers: Dictionary[String, Vector2] = {}
	var killer_at: Vector2
	var guard_at: Vector2
	for y: int in CHASE_MAP.size():
		for x: int in CHASE_MAP[y].length():
			var at: Vector2 = _at(Vector2i(x, y))
			match CHASE_MAP[y][x]:
				"D", "d", "L":
					var door: Node2D = _instance("res://examples/chase/features/door/door.tscn", "Door", at, counts)
					door.set("orientation", 1 if CHASE_MAP[y][x] == "D" else 0)
					door.set("locked", CHASE_MAP[y][x] == "L")
				"X":
					_instance("res://examples/chase/features/exit/exit.tscn", "Exit", at, counts)
				"P":
					_instance("res://examples/chase/features/player/player.tscn", "Player", at, counts)
				"M": killer_at = at
				"N": guard_at = at
				"1", "2", "3", "4": markers[CHASE_MAP[y][x]] = at
				"T":
					_instance("res://examples/chase/features/pickup/pickup.tscn", "Treasure", at, counts)
				"K":
					var key: Node2D = _instance("res://examples/chase/features/pickup/pickup.tscn", "Key", at, counts)
					key.set("kind", "紅")
					key.set("required", false)
				"R":
					_instance("res://examples/chase/features/task_point/task_point.tscn", "Generator", at, counts)
				"C", "E":
					var spot: Node2D = _instance("res://examples/chase/features/hiding_spot/hiding_spot.tscn", "HidingSpot", at, counts)
					spot.set("style", 0 if CHASE_MAP[y][x] == "C" else 1)
	_add_grid(layers, 1)

	# 大廳繞圈巡邏的那一隻
	var killer: ChaseAI = _instance("res://addons/ngdc_pathfinding/chase_ai/chase_ai.tscn", "ChaseAI", killer_at, counts)
	killer.patrol_mode = 1
	var keys: Array[String] = markers.keys()
	keys.sort()
	for i: int in keys.size():
		var marker: Marker2D = Marker2D.new()
		marker.name = "PatrolPoint%d" % (i + 1)
		marker.position = markers[keys[i]] - killer_at
		killer.add_child(marker)
		marker.owner = _root
	# 守在工作室的那一隻：沒有巡邏點，站著張望；比較慢反應
	var guard: ChaseAI = _instance("res://addons/ngdc_pathfinding/chase_ai/chase_ai.tscn", "Guard", guard_at, counts)
	guard.start_angle = 180.0
	guard.reaction_time = 1.5
	guard.body_color = Color("8a3ab0")

	_instance("res://examples/chase/features/darkness/darkness.tscn", "Darkness", Vector2.ZERO, counts)
	# 鏡頭：預設固定在畫面中間；邊界＝整個畫面（勾「跟隨」再把 Zoom 調成 2 就會跟著玩家）
	var camera: FollowCamera = _instance("res://core/camera/follow_camera.tscn", "FollowCamera", Vector2(640, 360) - OFFSET, counts)
	camera.follow = false
	camera.use_limits = true
	camera.limit_size = Vector2(1280, 720)
	var hud: CanvasLayer = _add(CanvasLayer.new(), "HUD", _root)
	var box: VBoxContainer = _add(VBoxContainer.new(), "Info", hud)
	box.position = Vector2(22, 12)
	_instance_ui("res://examples/chase/features/exit/objective_counter.tscn", "ObjectiveCounter", box)
	_hint(box, "WASD 移動　Shift 跑（會發出聲音）　E 互動　F1～F5 除錯")
	return _root


# ---- 塔防 ----

func _build_tower_defense() -> Node2D:
	_new_root("TowerDefense")
	var layers: Array[TileMapLayer] = _paint(TD_MAP)
	var counts: Dictionary[String, int] = {}
	var spawner_at: Vector2
	var base_at: Vector2
	for y: int in TD_MAP.size():
		for x: int in TD_MAP[y].length():
			match TD_MAP[y][x]:
				"S": spawner_at = _at(Vector2i(x, y))
				"H": base_at = _at(Vector2i(x, y))
	_add_grid(layers, 1)
	var base: Node2D = _instance("res://examples/tower_defense/features/base/base.tscn", "Base", base_at, counts)
	var spawner: Spawner = _instance("res://addons/ngdc_pathfinding/spawner/spawner.tscn", "Spawner", spawner_at, counts)
	spawner.target = base
	spawner.lose_when_reached = false                             # 基地有血量，扣光才輸
	spawner.start_delay = 5.0
	spawner.time_between_waves = 6.0
	spawner.waves = [_wave(5, 1.2, 50, 3), _wave(8, 0.9, 60, 5), _wave(12, 0.7, 70, 8)]
	var builder: Node2D = _instance("res://examples/tower_defense/features/builder/builder.tscn", "Builder", Vector2.ZERO, counts)
	builder.set("spawner", spawner)
	builder.set("base", base)

	var hud: CanvasLayer = _add(CanvasLayer.new(), "HUD", _root)
	var box: VBoxContainer = _add(VBoxContainer.new(), "Info", hud)
	box.position = Vector2(22, 12)
	var money: Node = _instance_ui("res://core/hud/score_display.tscn", "Money", box)
	money.set("prefix", "金錢 ")
	money.set("score", 12)
	var wave_label: Node = _instance_ui("res://examples/tower_defense/features/hud/wave_label.tscn", "WaveLabel", box)
	_hint(box, "1 牆（1 元）　2 塔（4 元）　左鍵蓋、右鍵拆　打死怪加錢")
	spawner.reached_goal.connect(Callable(base, "take_hit"), CONNECT_PERSIST)
	spawner.wave_started.connect(Callable(wave_label, "show_wave"), CONNECT_PERSIST)
	return _root


func _wave(count: int, interval: float, speed: float, health: float) -> Wave:
	var wave: Wave = Wave.new()
	wave.count = count
	wave.interval = interval
	wave.speed = speed
	wave.health = health
	return wave


# ---- 戰棋 ----

func _build_tactics() -> Node2D:
	_new_root("Tactics")
	_root.position = Vector2(224, 184)                            # 地圖比較小，放在畫面中間
	var layers: Array[TileMapLayer] = _paint(TACTICS_MAP)
	var counts: Dictionary[String, int] = {}
	_add_grid(layers, 0)                                          # 戰棋：不斜走
	for y: int in TACTICS_MAP.size():
		for x: int in TACTICS_MAP[y].length():
			var c: String = TACTICS_MAP[y][x]
			if c == "A" or c == "Z":
				var unit: Node2D = _instance("res://examples/tactics/features/unit/unit.tscn", "Ally" if c == "A" else "Enemy", _at(Vector2i(x, y)), counts)
				unit.set("team", 0 if c == "A" else 1)
				unit.set("move_points", 4 if c == "A" else 3)
	var move_range: Node2D = _instance("res://addons/ngdc_pathfinding/move_range/move_range.tscn", "MoveRange", Vector2.ZERO, counts)
	var hud: CanvasLayer = _add(CanvasLayer.new(), "HUD", _root)
	var box: VBoxContainer = _add(VBoxContainer.new(), "Info", hud)
	box.position = Vector2(22, 12)
	var turn_label: Label = _add(Label.new(), "TurnLabel", box)
	turn_label.text = "我方回合"
	turn_label.add_theme_font_size_override("font_size", 33)
	_hint(box, "點藍色棋子 → 點亮起來的格子移動　走到敵人旁邊會攻擊　沼澤很難走　右鍵取消")
	var end_turn: Button = _add(Button.new(), "EndTurnButton", hud)
	end_turn.text = "結束回合"
	end_turn.add_theme_font_size_override("font_size", 22)
	end_turn.position = Vector2(1080, 640)
	end_turn.size = Vector2(176, 44)
	var manager: Node = _instance("res://examples/tactics/features/turn/turn_manager.tscn", "TurnManager", Vector2.ZERO, counts)
	manager.set("move_range", move_range)
	manager.set("turn_label", turn_label)
	manager.set("end_turn_button", end_turn)
	return _root


# ---- 共用 ----

func _new_root(root_name: String) -> void:
	_root = Node2D.new()
	_root.name = root_name
	_root.position = OFFSET


## 畫地板和牆兩張 TileMapLayer
func _paint(map: PackedStringArray) -> Array[TileMapLayer]:
	var tileset: TileSet = load(TILESET)
	var floor_layer: TileMapLayer = _add(TileMapLayer.new(), "Floor", _root)
	floor_layer.tile_set = tileset
	var walls: TileMapLayer = _add(TileMapLayer.new(), "Walls", _root)
	walls.tile_set = tileset
	for y: int in map.size():
		for x: int in map[y].length():
			var c: String = map[y][x]
			var cell: Vector2i = Vector2i(x, y)
			if c == " ":
				continue
			if c == "~":
				floor_layer.set_cell(cell, 0, Vector2i(5, 0))
			else:
				floor_layer.set_cell(cell, 0, Vector2i(1, 0) if c == "," or _near_tile(map, x, y) else Vector2i(0, 0))
			match c:
				"#": walls.set_cell(cell, 0, Vector2i(2, 0))
				"G": walls.set_cell(cell, 0, Vector2i(3, 0))
				"b": walls.set_cell(cell, 0, Vector2i(4, 0))
	return [floor_layer, walls]


## 角色、門這些符號底下鋪什麼地板：旁邊是磁磚就鋪磁磚
func _near_tile(map: PackedStringArray, x: int, y: int) -> bool:
	if not "123456789MNXR".contains(map[y][x]):
		return false
	return (x > 0 and map[y][x - 1] == ",") or (x < map[y].length() - 1 and map[y][x + 1] == ",") or map[y][x] == "X"


func _add_grid(layers: Array[TileMapLayer], diagonal: int) -> void:
	var grid: PathGrid = (load("res://addons/ngdc_pathfinding/grid/path_grid.tscn") as PackedScene).instantiate()
	_add(grid, "PathGrid", _root)
	grid.floor_layer = layers[0]
	grid.walls = layers[1]
	grid.diagonal = diagonal


func _at(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) / 2.0


func _instance(path: String, base_name: String, at: Vector2, counts: Dictionary[String, int]) -> Node:
	var node: Node = (load(path) as PackedScene).instantiate()
	counts[base_name] = counts.get(base_name, 0) + 1
	_add(node, base_name if counts[base_name] == 1 else "%s%d" % [base_name, counts[base_name]], _root)
	if node is Node2D:
		(node as Node2D).position = at
	return node


func _instance_ui(path: String, node_name: String, parent: Node) -> Node:
	return _add((load(path) as PackedScene).instantiate(), node_name, parent)


func _hint(parent: Node, text: String) -> void:
	var label: Label = _add(Label.new(), "Hint", parent)
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)


func _add(node: Node, node_name: String, parent: Node) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = _root
	return node
