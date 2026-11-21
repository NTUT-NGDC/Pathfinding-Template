extends Node
## 產生範例關卡（example/levels/small_house.tscn）和學員的關卡（my_level/my_level.tscn）。
## 用文字地圖畫房子，比手動在編輯器畫快，改了地圖再執行一次就好：
##   godot --headless --path . res://_system/tools/make_example_level.tscn
## 加上 `-- example-only` 只產生範例關卡（不會覆蓋學員的關卡）。
##
## 地圖符號：
##   # 牆　G 玻璃　B 草叢　. 木頭地板　, 磁磚地板
##   D 門（直）　d 門（橫）　L 紅色上鎖的門（橫）　X 出口（橫）
##   P 玩家　M 殺手　1～4 殺手的巡邏點（照順序）
##   R 修理點　K 紅色鑰匙　C 櫃子　E 床

const OUTPUT_EXAMPLE: String = "res://example/levels/small_house.tscn"
const OUTPUT_MY_LEVEL: String = "res://my_level/my_level.tscn"
const MAP: PackedStringArray = [
	"####################################",
	"#........#,,,,,,,,,,,,,,#..........#",
	"#..E..K..#,,,,,,,,,,,,,,#....R.....#",
	"#........#,,,,,,,,,,,,,,#..........#",
	"#........D,,,,,,,,,,,,,,D..........#",
	"#........#,,,,,,,,,,,,,,#.....C....#",
	"###GGG####,,,,,BBB,,,,,,###GGG######",
	"#........#,,,,,BBB,,,,,,,,,,,,,,,,,#",
	"#........#,,,,,,,,,,,,,,,,,,,,,,,,,#",
	"#..P.....D,,1M,,,,,,,,,2,,,,,,,,,,,#",
	"#........#,,,,,,,,,,,,,,,,,,,,,,,,,#",
	"#...C....#,,,,,,,,,,,,,,#####L######",
	"#........G,,,,,,,,,,,,,,#..........#",
	"#........G,,,,,,,,BBB,,,#....R.....#",
	"#........#,,,,,,,,BBB,,,#..........#",
	"#........#,,,,,,,,,,,,,,#....E.....#",
	"#........#,,4,,,,,,,,,3,#..........#",
	"################X###################",
]
const TILE: int = 32

var _root: EscapeLevel


func _ready() -> void:
	var example_only: bool = OS.get_cmdline_user_args().has("example-only")
	var ok: bool = _save(OUTPUT_EXAMPLE, "範例：小房子")
	if not example_only:
		ok = _save(OUTPUT_MY_LEVEL, "我的逃脫遊戲") and ok
	get_tree().quit(0 if ok else 1)


func _save(path: String, level_name: String) -> bool:
	_build(level_name)
	var scene: PackedScene = PackedScene.new()
	var error: Error = scene.pack(_root)
	if error == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		error = ResourceSaver.save(scene, path)
	print("存檔 %s：%s" % [path, error_string(error)])
	_root.free()
	return error == OK


func _build(level_name: String) -> void:
	_root = EscapeLevel.new()
	_root.name = "Level"
	_root.level_name = level_name
	var tileset: TileSet = load("res://game/level/tileset/tileset.tres")
	var floor_layer: TileMapLayer = _add(TileMapLayer.new(), "Floor", _root)
	floor_layer.tile_set = tileset
	var walls: TileMapLayer = _add(TileMapLayer.new(), "Walls", _root)
	walls.tile_set = tileset
	_root.floor_layer = floor_layer
	_root.walls_layer = walls

	var markers: Dictionary[String, Vector2] = {}
	var killer_at: Vector2 = Vector2.ZERO
	var counts: Dictionary[String, int] = {}
	for y: int in MAP.size():
		for x: int in MAP[y].length():
			var c: String = MAP[y][x]
			var cell: Vector2i = Vector2i(x, y)
			var at: Vector2 = Vector2(cell) * TILE + Vector2(TILE, TILE) / 2.0
			floor_layer.set_cell(cell, 0, Vector2i(1, 0) if c == "," or _hall_neighbor(x, y) else Vector2i(0, 0))
			match c:
				"#": walls.set_cell(cell, 0, Vector2i(2, 0))
				"G": walls.set_cell(cell, 0, Vector2i(3, 0))
				"B": walls.set_cell(cell, 0, Vector2i(4, 0))
				"D", "d", "L":
					var door: Door = _instance("res://game/level/door.tscn", "Door", at, counts)
					door.orientation = 1 if c == "D" else 0
					door.locked = c == "L"
					door.key_color = "紅"
				"X":
					var exit: Exit = _instance("res://game/tasks/exit.tscn", "Exit", at, counts)
					exit.orientation = 0
				"P": _instance("res://game/player/player.tscn", "Player", at, counts)
				"M": killer_at = at
				"1", "2", "3", "4": markers[c] = at
				"R": _instance("res://game/tasks/repair_point.tscn", "RepairPoint", at, counts)
				"K":
					var key: KeyPickup = _instance("res://game/tasks/key.tscn", "Key", at, counts)
					key.key_color = "紅"
				"C", "E":
					var spot: HidingSpot = _instance("res://game/level/hiding_spot.tscn", "HidingSpot", at, counts)
					spot.style = 0 if c == "C" else 1

	var killer: Killer = _instance("res://game/killer/killer.tscn", "Killer", killer_at, counts)
	killer.patrol_mode = 1                                        # 繞圈
	var keys: Array[String] = markers.keys()
	keys.sort()
	for i: int in keys.size():
		var marker: Marker2D = Marker2D.new()
		marker.name = "PatrolPoint%d" % (i + 1)
		marker.position = markers[keys[i]] - killer_at
		killer.add_child(marker)
		marker.owner = _root


## 地圖上的角色符號底下也要鋪地板：旁邊是磁磚就鋪磁磚
func _hall_neighbor(x: int, y: int) -> bool:
	if "1234M".contains(MAP[y][x]):
		return MAP[y][x - 1] == "," or MAP[y][x + 1] == ","
	if MAP[y][x] == "X":
		return true
	return false


func _instance(path: String, base_name: String, at: Vector2, counts: Dictionary[String, int]) -> Node2D:
	var node: Node2D = (load(path) as PackedScene).instantiate()
	counts[base_name] = counts.get(base_name, 0) + 1
	var node_name: String = base_name if counts[base_name] == 1 else "%s%d" % [base_name, counts[base_name]]
	_add(node, node_name, _root)
	node.position = at
	return node


func _add(node: Node, node_name: String, parent: Node) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = _root
	return node
