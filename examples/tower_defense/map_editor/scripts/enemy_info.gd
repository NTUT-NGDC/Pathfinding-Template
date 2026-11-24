class_name TDEnemyInfo
extends RefCounted
## 編輯器用：有哪些怪、有哪些怪物掛件、一隻怪實際的血量和速度、讀寫怪物場景。
## 怪物存成一般的 .tscn（繼承 walker.tscn＋掛件），跟在 Godot 裡手動做的一樣，兩邊都可以改。

const ENEMIES_DIR: String = "res://examples/tower_defense/features/enemies/"
const TRAITS_DIR: String = "res://examples/tower_defense/features/enemy_traits/"
## 普通怪（尋路積木的小怪，不能在編輯器裡改）
const DEFAULT_PATH: String = "res://addons/ngdc_pathfinding/spawner/walker.tscn"
## 怪物場景存哪些欄位
const FIELDS: Array[String] = ["display_name", "color", "speed", "max_health", "score", "wall_damage", "radius"]


## 所有怪物場景的路徑（第一個是普通怪）
static func paths() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray([DEFAULT_PATH])
	result.append_array(_scenes_in(ENEMIES_DIR))
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


## 所有怪物掛件的路徑
static func trait_paths() -> PackedStringArray:
	return _scenes_in(TRAITS_DIR)


static func _scenes_in(dir: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			if file.ends_with(".tscn"):
				result.append(dir + file)
	return result


## 怪的名字（Walker 的 Display Name；不是 Walker 的話用檔名）
static func name_of(path: String) -> String:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return path.get_file().get_basename()
	var node: Node = scene.instantiate()
	var text: Variant = node.get("display_name")
	node.free()
	return String(text) if text != null and not String(text).is_empty() else path.get_file().get_basename()


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


## 掛件可以改的欄位：[{name, type, min, max, step, suffix, label}]
static func trait_fields(node: Node) -> Array[Dictionary]:
	var labels: Dictionary = node.call("labels") if node.has_method("labels") else {}
	var result: Array[Dictionary] = []
	for property: Dictionary in node.get_property_list():
		if not (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and property["usage"] & PROPERTY_USAGE_EDITOR):
			continue
		if not [TYPE_FLOAT, TYPE_INT, TYPE_BOOL].has(property["type"]):
			continue
		var field: Dictionary = {"name": property["name"], "type": property["type"], "label": labels.get(property["name"], property["name"]),
			"min": 0.0, "max": 1000.0, "step": 0.1 if property["type"] == TYPE_FLOAT else 1.0, "suffix": ""}
		if property["hint"] == PROPERTY_HINT_RANGE:
			var parts: PackedStringArray = String(property["hint_string"]).split(",")
			if parts.size() >= 2:
				field["min"] = parts[0].to_float()
				field["max"] = parts[1].to_float()
			if parts.size() >= 3 and parts[2].is_valid_float():
				field["step"] = parts[2].to_float()
			for part: String in parts:
				if part.begins_with("suffix:"):
					field["suffix"] = part.trim_prefix("suffix:")
		result.append(field)
	return result


## 讀一個怪物場景：{欄位…, "traits": {掛件路徑: {欄位: 值}}}
static func read(path: String) -> Dictionary:
	var root: Node = (load(path) as PackedScene).instantiate()
	var data: Dictionary = {"traits": {}}
	for field: String in FIELDS:
		data[field] = root.get(field)
	for child: Node in root.get_children():
		if trait_paths().has(child.scene_file_path) and not data["traits"].has(child.scene_file_path):
			data["traits"][child.scene_file_path] = read_trait(child)
	root.free()
	return data


## 一個掛件現在的欄位值
static func read_trait(node: Node) -> Dictionary:
	var values: Dictionary = {}
	for field: Dictionary in trait_fields(node):
		values[field["name"]] = node.get(field["name"])
	return values


## 掛件的預設值
static func trait_defaults(path: String) -> Dictionary:
	var node: Node = (load(path) as PackedScene).instantiate()
	var values: Dictionary = read_trait(node)
	node.free()
	return values


## 把 data 寫進怪物場景（沒有這個檔案就先做一個繼承 walker.tscn 的）。其他手動加的節點不會動到
static func write(path: String, data: Dictionary) -> Error:
	if not ResourceLoader.exists(path):
		var made: Error = _make_scene(path)
		if made != OK:
			return made
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return ERR_CANT_OPEN
	if not OS.has_feature("editor"):
		return ERR_UNAVAILABLE                                    # 匯出的遊戲不能存
	var root: Node = scene.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	for field: String in FIELDS:
		root.set(field, data[field])
	var wanted: Dictionary = data["traits"]
	var have: Dictionary = {}
	for child: Node in root.get_children():
		var trait_path: String = child.scene_file_path
		if not trait_paths().has(trait_path) or have.has(trait_path):
			continue
		if wanted.has(trait_path):
			have[trait_path] = child
		else:
			root.remove_child(child)
			child.free()
	for trait_path: String in wanted:
		var node: Node = have.get(trait_path)
		if node == null:
			node = (load(trait_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			root.add_child(node)
			node.owner = root
		for key: String in wanted[trait_path]:
			node.set(key, wanted[trait_path][key])
	var error: Error = scene.pack(root)                           # 改同一份場景：波次、試玩馬上用到新的
	root.free()
	return ResourceSaver.save(scene, path) if error == OK else error


## 新的怪：寫一個繼承 walker.tscn 的空場景
static func _make_scene(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var node_name: String = path.get_file().get_basename().validate_node_name()
	file.store_string("[gd_scene format=3]\n\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_walker\"]\n\n[node name=\"%s\" instance=ExtResource(\"1_walker\")]\n" % [DEFAULT_PATH, node_name])
	file.close()
	return OK
