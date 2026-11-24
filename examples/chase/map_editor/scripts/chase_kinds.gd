class_name ChaseKinds
extends RefCounted
## 編輯器用：哪些東西可以有好幾種（敵人：殺手、守衛……；任務點：發電機、電腦……），每一種是一個場景，繼承同一個底。
## 敵人放在 features/enemies/，其他放在 features/名字/kinds/；自己做的物件（features/名字/名字.tscn）也一樣。
## 存成一般的 .tscn，跟在 Godot 裡手動做的一樣，兩邊都可以改。

const FEATURES: String = "res://examples/chase/features/"
## 編輯器本來就有工具的（不算自己做的物件）
const BUILT_IN: Array[String] = ["player", "exit", "pickup", "task_point", "door", "hiding_spot", "trap", "alarm"]

## 有種類的東西：{"name": 中文, "base": 底的場景, "scenes": 讀寫種類的}
static var _classes: Array[Dictionary] = []
static var _bases: Dictionary[String, String] = {}


static func classes() -> Array[Dictionary]:
	if _classes.is_empty():
		_add("敵人", ChaseMap.ENEMY, FEATURES + "enemies/", FEATURES + "enemy_traits/", "基本敵人")
		for item: Array in [["任務點", "task_point"], ["捕獸夾", "trap"], ["警報", "alarm"], ["躲藏點", "hiding_spot"]]:
			_add(item[0], "%s%s/%s.tscn" % [FEATURES, item[1], item[1]], "%s%s/kinds/" % [FEATURES, item[1]], "", "基本" + String(item[0]))
		for path: String in custom_paths():
			_add(LevelEditorScenes.name_of(path), path, path.get_base_dir() + "/kinds/", "", "基本" + LevelEditorScenes.name_of(path))
	return _classes


static func _add(text: String, base: String, dir: String, traits: String, base_name: String) -> void:
	var fields: Array[String] = []
	for field: Dictionary in ChaseMap.fields_of(base):
		if not ChaseMap.PER_OBJECT.has(field["name"]):
			fields.append(field["name"])
	var scenes: LevelEditorScenes = LevelEditorScenes.new(dir, traits, base, fields)
	scenes.base_name = base_name
	_classes.append({"name": text, "base": base, "scenes": scenes})


## 自己做的物件：features/名字/名字.tscn，最上面是 Node2D
static func custom_paths() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for dir: String in DirAccess.get_directories_at(FEATURES):
		var path: String = "%s%s/%s.tscn" % [FEATURES, dir, dir]
		if BUILT_IN.has(dir) or not ResourceLoader.exists(path):
			continue
		var node: Node = (load(path) as PackedScene).instantiate()
		if node is Node2D:
			result.append(path)
		node.free()
	return result


## 底是 base 的那一類（沒有種類＝空的）
static func with_base(base: String) -> Dictionary:
	for item: Dictionary in classes():
		if item["base"] == base:
			return item
	return {}


## 這個場景屬於哪一類（沒有種類＝空的）
static func class_of(scene: String) -> Dictionary:
	for item: Dictionary in classes():
		if item["base"] == scene or (item["scenes"] as LevelEditorScenes).paths().has(scene):
			return item
	return with_base(base_of(scene))


## 這一類有哪些種類（底放最後）
static func paths(item: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = (item["scenes"] as LevelEditorScenes).paths()
	result.append(item["base"])
	return result


## 這個場景可以掛哪些特性
static func traits_of(scene: String) -> PackedStringArray:
	var item: Dictionary = class_of(scene)
	return PackedStringArray() if item.is_empty() else (item["scenes"] as LevelEditorScenes).trait_paths()


## 場景最底下繼承的是哪一個（沒有繼承＝自己）
static func base_of(scene: String) -> String:
	if not _bases.has(scene):
		var parent: PackedScene = (load(scene) as PackedScene).get_state().get_node_instance(0)
		_bases[scene] = scene if parent == null else base_of(parent.resource_path)
	return _bases[scene]


## 種類的名字
static func name_of(scene: String) -> String:
	var item: Dictionary = class_of(scene)
	return LevelEditorScenes.name_of(scene) if item.is_empty() else (item["scenes"] as LevelEditorScenes).label_of(scene)
