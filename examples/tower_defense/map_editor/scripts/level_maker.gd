class_name TDLevelMaker
extends RefCounted
## 把一張地圖＋一份波次做成關卡：繼承 tower_defense.tscn 的場景，只換地圖和波次。
## 改 tower_defense.tscn（例如起始金錢、畫面），繼承的關卡也會跟著改；
## 地圖、波次是用檔案連過去的，之後再改那兩個檔案，關卡也會跟著變，不用重做。

const LEVELS_DIR: String = "res://examples/tower_defense/levels/"
const BASE_LEVEL: String = "res://examples/tower_defense/levels/tower_defense.tscn"


## 關卡要叫什麼檔名：地圖名；波次不是 default 的話再加波次名
static func path_for(map_path: String, waves_path: String) -> String:
	var map_name: String = map_path.get_file().get_basename()
	var waves_name: String = waves_path.get_file().get_basename()
	var level_name: String = map_name if waves_name == "default" else "%s_%s" % [map_name, waves_name]
	return LEVELS_DIR + level_name.validate_filename() + ".tscn"


## 做成關卡。已經有同名的檔案就不動它（回傳 ERR_ALREADY_EXISTS）
static func make(map_path: String, waves_path: String) -> Error:
	var path: String = path_for(map_path, waves_path)
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var lines: PackedStringArray = PackedStringArray([
		"[gd_scene format=3]",
		"",
		"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_base\"]" % BASE_LEVEL,
		"[ext_resource type=\"Resource\" path=\"%s\" id=\"2_waves\"]" % waves_path,
		"[ext_resource type=\"Resource\" path=\"%s\" id=\"3_map\"]" % map_path,
		"",
		"[node name=\"%s\" instance=ExtResource(\"1_base\")]" % path.get_file().get_basename().validate_node_name(),
		"",
		"[node name=\"Spawner\" parent=\".\"]",
		"wave_table = ExtResource(\"2_waves\")",
		"",
		"[node name=\"MapLoader\" parent=\".\"]",
		"map = ExtResource(\"3_map\")",
		"",
	])
	file.store_string("\n".join(lines))
	file.close()
	return OK
