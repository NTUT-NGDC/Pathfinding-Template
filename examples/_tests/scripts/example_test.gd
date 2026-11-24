extends Node
## 範例測試共用的底：每個範例一份測試（chase_test、tower_defense_test、tactics_test），各自繼承、覆寫 _run()。
## 在命令列執行（失敗時 exit code 是 1）：
##   godot --headless --fixed-fps 60 --path . res://examples/_tests/chase_test.tscn

const ScriptErrors = preload("res://core/tests/scripts/script_error_counter.gd")
const TIME_SCALE: float = 3.0

var _failures: int = 0
## 失敗的項目（最後再印一次，不用往上找）
var _failed: PackedStringArray = PackedStringArray()
## 腳本錯誤也算失敗（會讓測試函式中斷、跑不到 _expect）
var _script_errors: ScriptErrors = ScriptErrors.new()
var _level: Node


func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	Engine.max_physics_steps_per_frame = 1                        # 電腦忙的時候變慢就好，不要一個畫面塞好幾個物理影格（_process 會來不及跑，測試偶爾失敗）
	await _run()
	Engine.time_scale = 1.0
	get_tree().paused = false
	_failures += _script_errors.report()
	for item: String in _failed:
		print("  失敗：" + item)
	print("[%s] 全部 PASS" % name if _failures == 0 else "[%s] FAIL：%d 項失敗" % [name, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## 要測什麼（各範例覆寫）
func _run() -> void:
	await get_tree().process_frame


# ---- 工具 ----

func _load(path: String) -> void:
	get_tree().paused = false
	if _level != null:
		_level.queue_free()
		await _frames(1)
	for child: Node in GameFlow.get_children():
		child.queue_free()                                        # 清掉上一個的勝敗畫面
	await _frames(1)
	_level = (load(path) as PackedScene).instantiate()
	add_child(_level)
	await _frames(3)


func _freeze_group(group: String) -> void:
	for node: Node in get_tree().get_nodes_in_group(group):
		node.process_mode = Node.PROCESS_MODE_DISABLED


func _result_title() -> String:
	for child: Node in GameFlow.get_children():
		if child.name == "ResultScreen":
			return (child.get_node("%ResultTitle") as Label).text
	return ""


func _wait_until(condition: Callable, max_frames: int) -> void:
	for i: int in max_frames:
		if condition.call():
			return
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
		_failed.append(description)


func _press(key: int) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key as Key
	event.keycode = key as Key
	event.pressed = true
	get_viewport().push_input(event)
