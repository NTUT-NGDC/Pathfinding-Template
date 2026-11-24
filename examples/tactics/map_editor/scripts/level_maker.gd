class_name TacticsLevelMaker
extends RefCounted
## 把一張戰棋地圖做成關卡：繼承 tactics.tscn 的場景，只換地圖。
## 改 tactics.tscn（例如畫面、戰鬥的設定），繼承的關卡也會跟著改；之後再改地圖檔，關卡也會跟著變，不用重做。

const LEVELS_DIR: String = "res://examples/tactics/levels/"
const BASE_LEVEL: String = "res://examples/tactics/levels/tactics.tscn"


## 關卡要叫什麼檔名
static func path_for(map_path: String) -> String:
	return LEVELS_DIR + map_path.get_file().get_basename().validate_filename() + ".tscn"


## 做成關卡。已經有同名的檔案就不動它（回傳 ERR_ALREADY_EXISTS）
static func make(map_path: String) -> Error:
	var path: String = path_for(map_path)
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var lines: PackedStringArray = PackedStringArray([
		"[gd_scene format=3]",
		"",
		"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_base\"]" % BASE_LEVEL,
		"[ext_resource type=\"Resource\" path=\"%s\" id=\"2_map\"]" % map_path,
		"",
		"[node name=\"%s\" instance=ExtResource(\"1_base\")]" % path.get_file().get_basename().validate_node_name(),
		"",
		"[node name=\"TacticsLevel\" parent=\".\"]",
		"map = ExtResource(\"2_map\")",
		"",
	])
	file.store_string("\n".join(lines))
	file.close()
	return OK
