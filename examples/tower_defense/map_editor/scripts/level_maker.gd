class_name TDLevelMaker
extends RefCounted
## 把一張地圖＋一份波次做成關卡：繼承 tower_defense.tscn 的場景，只換地圖和波次（寫檔的是 core/level_editor 的 LevelMaker）。
## 改 tower_defense.tscn（例如起始金錢、畫面），繼承的關卡也會跟著改。

const LEVELS_DIR: String = "res://examples/tower_defense/levels/"
const BASE_LEVEL: String = "res://examples/tower_defense/levels/tower_defense.tscn"


## 關卡要叫什麼檔名：地圖名；波次不是 default 的話再加波次名
static func path_for(map_path: String, waves_path: String) -> String:
	var map_name: String = map_path.get_file().get_basename()
	var waves_name: String = waves_path.get_file().get_basename()
	var level_name: String = map_name if waves_name == "default" else "%s_%s" % [map_name, waves_name]
	return LEVELS_DIR + level_name.validate_filename() + ".tscn"


## 做這一關要的東西（給 LevelMaker）
static func request(map_path: String, waves_path: String) -> Dictionary:
	return {"path": path_for(map_path, waves_path), "base": BASE_LEVEL,
		"values": {"Spawner": {"wave_table": waves_path}, "MapLoader": {"map": map_path}}}


## 做成關卡。已經有同名的檔案就不動它（回傳 ERR_ALREADY_EXISTS）
static func make(map_path: String, waves_path: String) -> Error:
	var data: Dictionary = request(map_path, waves_path)
	return LevelMaker.make(data["path"], data["base"], data["values"])
