extends Node
## 專案設定的自動測試：
## 1. 輸入對應：WASD／方向鍵、Shift、E、1～5 都有設定
## 2. 物理層名稱：1 擋路、2 擋視線
## 3. 字型讀得到、音量設定（SoundSettings）有載入
## 4. 暫停選單：打開會暫停、關掉會繼續
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/project_test.tscn

const PAUSE_MENU_SCENE: PackedScene = preload("res://game/pause_menu/pause_menu.tscn")

## 每個動作應該對應到哪些按鍵（physical_keycode）
const EXPECTED_KEYS: Dictionary[String, Array] = {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"interact": [KEY_E],
	"debug_vision": [KEY_1],
	"debug_path": [KEY_2],
	"debug_state": [KEY_3],
	"debug_sound": [KEY_4],
	"debug_grid": [KEY_5],
}

var _failures: int = 0


func _ready() -> void:
	_test_input_map()
	_test_layer_names()
	_test_font_and_autoload()
	await _test_pause_menu()

	if _failures == 0:
		print("[專案設定測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[專案設定測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_input_map() -> void:
	print("--- 輸入對應 ---")
	for action: String in EXPECTED_KEYS:
		if not InputMap.has_action(action):
			_expect(false, "有動作「%s」" % action)
			continue
		var keys: Array[int] = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append((event as InputEventKey).physical_keycode)
		var missing: Array = EXPECTED_KEYS[action].filter(func(key: int) -> bool: return not keys.has(key))
		_expect(missing.is_empty(), "「%s」的按鍵都在（目前 %s）" % [action, keys])


func _test_layer_names() -> void:
	print("--- 物理層名稱 ---")
	_expect(ProjectSettings.get_setting("layer_names/2d_physics/layer_1") == "擋路", "第 1 層＝擋路")
	_expect(ProjectSettings.get_setting("layer_names/2d_physics/layer_2") == "擋視線", "第 2 層＝擋視線")


func _test_font_and_autoload() -> void:
	print("--- 字型、全域腳本 ---")
	var font_path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	_expect(font_path != "" and load(font_path) is Font, "全專案字型讀得到（%s）" % font_path)
	_expect(get_node_or_null("/root/SoundSettings") != null, "SoundSettings 有載入")
	_expect(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "有 Music、SFX 兩條匯流排")


func _test_pause_menu() -> void:
	print("--- 暫停選單 ---")
	var menu: CanvasLayer = PAUSE_MENU_SCENE.instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.call("open_menu")
	_expect(get_tree().paused, "打開選單 → 遊戲暫停")
	menu.call("close_menu")
	_expect(not get_tree().paused, "關掉選單 → 遊戲繼續")
	menu.call("open_menu")
	menu.queue_free()
	await get_tree().process_frame
	_expect(not get_tree().paused, "選單開著就被刪掉 → 自動解除暫停")


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
