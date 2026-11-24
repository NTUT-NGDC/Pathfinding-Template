class_name TacticsUnitInfo
extends RefCounted
## 編輯器用：有哪些棋子、一隻棋子長怎樣。讀寫棋子場景是 core/level_editor 的 LevelEditorScenes。
## 棋子存成一般的 .tscn（繼承 unit.tscn＋特性），跟在 Godot 裡手動做的一樣，兩邊都可以改。

const UNITS_DIR: String = "res://examples/tactics/features/units/"
const TRAITS_DIR: String = "res://examples/tactics/features/unit_traits/"
## 新棋子從這個場景繼承（不列在清單裡）
const DEFAULT_PATH: String = "res://examples/tactics/features/unit/unit.tscn"

static var scenes: LevelEditorScenes = LevelEditorScenes.new(UNITS_DIR, TRAITS_DIR, DEFAULT_PATH,
	["display_name", "mark", "color", "max_health", "attack", "defense", "move_points", "min_range", "max_range", "speed", "mind"])
## 畫棋子要用的（字、顏色、名字），讀過的記起來
static var _looks: Dictionary = {}


## 所有棋子場景的路徑
static func paths() -> PackedStringArray:
	return scenes.paths()


## 一隻棋子長怎樣：{"name", "mark", "color"}
static func look(path: String) -> Dictionary:
	if not _looks.has(path):
		var unit: Unit = (load(path) as PackedScene).instantiate() as Unit if ResourceLoader.exists(path) else null
		if unit == null:
			return {"name": path.get_file(), "mark": "？", "color": Color.MAGENTA}
		_looks[path] = {"name": unit.display_name, "mark": unit.mark, "color": unit.color}
		unit.free()
	return _looks[path]


## 棋子改了，下次重讀
static func forget_look(path: String) -> void:
	_looks.erase(path)
