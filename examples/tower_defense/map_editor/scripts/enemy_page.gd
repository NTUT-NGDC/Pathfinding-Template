class_name TDEnemyPage
extends LevelEditorScenePage
## 編輯器的「怪物」頁：改怪的數值、勾掛件，存成 features/enemies/ 裡的一般場景。
## 普通怪是尋路積木本身，不能改；按「複製成新怪」拿來改。


func _setup() -> void:
	scenes = TDEnemyInfo.scenes
	thing = "怪"
	trait_title = "掛件"
	fields = [
		LevelEditorForm.color("color", "顏色"),
		LevelEditorForm.number("speed", "速度", 10, 500, 5, "px/秒"),
		LevelEditorForm.number("max_health", "血量", 1, 1000, 1, "滴"),
		LevelEditorForm.number("score", "打死給", 0, 1000, 1, "元"),
		LevelEditorForm.number("wall_damage", "打牆", 0.1, 100, 0.1, "滴/秒"),
		LevelEditorForm.number("radius", "大小", 4, 32, 1, "px"),
	]


func _list_paths() -> PackedStringArray:
	return TDEnemyInfo.walker_paths()


## 普通怪不能改，所以先開第二隻
func _first_path() -> String:
	var found: PackedStringArray = _list_paths()
	return found[1] if found.size() > 1 else found[0]


func is_locked() -> bool:
	return path == TDEnemyInfo.DEFAULT_PATH


func _preview_added(preview: Node2D) -> void:
	preview.remove_from_group("enemies")                          # 只是預覽，不要被當成場上的怪


func _preview_text(preview: Node2D) -> String:
	var info: Dictionary = TDEnemyInfo.stats_of(preview)
	var text: String = "實際血量　%s%s\n實際速度　%s px/秒\n打死給　%d 元" % [_short(info["health"]),
		"（減傷：要打 %s）" % _short(float(info["health"]) / float(info["damage_multiplier"])) if float(info["damage_multiplier"]) != 1.0 else "",
		_short(info["speed"]), info["score"]]
	return text + "\n\n波次有填血量、速度的話，\n會先換成波次的再算掛件"


func _short(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0")
