class_name TDEnemyInfo
extends RefCounted
## 編輯器用：有哪些怪、一隻怪實際的血量和速度。讀寫怪物場景是 core/level_editor 的 LevelEditorScenes。
## 怪物存成一般的 .tscn（繼承 walker.tscn＋掛件），跟在 Godot 裡手動做的一樣，兩邊都可以改。

const ENEMIES_DIR: String = "res://examples/tower_defense/features/enemies/"
const TRAITS_DIR: String = "res://examples/tower_defense/features/enemy_traits/"
## 普通怪（尋路積木的小怪，不能在編輯器裡改）
const DEFAULT_PATH: String = "res://addons/ngdc_pathfinding/spawner/walker.tscn"

static var scenes: LevelEditorScenes = LevelEditorScenes.new(ENEMIES_DIR, TRAITS_DIR, DEFAULT_PATH,
	["display_name", "color", "speed", "max_health", "score", "wall_damage", "radius"])


## 所有怪物場景的路徑（第一個是普通怪）
static func paths() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray([DEFAULT_PATH])
	result.append_array(scenes.paths())
	return result


## 怪物頁可以改的（最上面的節點是 Walker 的）
static func walker_paths() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for path: String in paths():
		var node: Node = (load(path) as PackedScene).instantiate()
		if node is Walker:
			result.append(path)
		node.free()
	return result


## 怪的名字（Walker 的 Display Name；不是 Walker 的話用檔名）
static func name_of(path: String) -> String:
	return LevelEditorScenes.name_of(path)


## 掛件作用之後實際的數值。health、speed 是波次填的（0＝用怪自己的）。
## 要真的放進場景，掛件才會生效，所以要給一個在場景裡的節點 host
static func stats(host: Node, scene: PackedScene, health: float = 0.0, speed: float = 0.0) -> Dictionary:
	var enemy: Node = (scene if scene != null else load(DEFAULT_PATH) as PackedScene).instantiate()
	if health > 0.0:
		enemy.set("max_health", health)
	if speed > 0.0:
		enemy.set("speed", speed)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	host.add_child(enemy)
	var result: Dictionary = stats_of(enemy)
	enemy.free()
	return result


## 已經在場景裡的怪的實際數值
static func stats_of(enemy: Node) -> Dictionary:
	return {
		"health": _number(enemy.get("max_health"), 0.0),
		"speed": _number(enemy.get("speed"), 0.0),
		"damage_multiplier": _number(enemy.get("damage_taken_multiplier"), 1.0),
		"score": int(_number(enemy.get("score"), 0.0)),
	}


static func _number(value: Variant, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback
