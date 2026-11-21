extends Node
## 標題畫面的自動測試：
## 1. 標題畫面打得開，有開始遊戲、設定按鈕；Level Scene 預設是學員的關卡
## 2. 按「開始遊戲」會換到關卡
## 3. 沒設定關卡時顯示提示、不會當掉
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/title_screen_test.tscn

const TITLE_SCENE: PackedScene = preload("res://game/title_screen/title_screen.tscn")

var _failures: int = 0


func _ready() -> void:
	var title: Control = TITLE_SCENE.instantiate()
	_expect(title.get("level_scene") is PackedScene and (title.get("level_scene") as PackedScene).resource_path == "res://my_level/my_level.tscn", "Level Scene 預設是 my_level.tscn")
	title.set("level_scene", null)
	add_child(title)
	await get_tree().process_frame
	(title.get_node("%StartButton") as Button).pressed.emit()
	var message: Label = title.get_node("%MessageLabel")
	_expect(message.visible and message.text.contains("Level Scene"), "沒設定關卡：顯示提示")
	(title.get_node("%SettingsButton") as Button).pressed.emit()
	_expect((title.get_node("%SettingsPanel") as Control).visible, "按設定：打開音量面板")
	title.queue_free()
	await get_tree().process_frame

	# 真的換場景：把標題畫面設成目前的場景（測試自己不是，才不會被換掉），按開始遊戲
	var real_title: Control = TITLE_SCENE.instantiate()
	get_tree().root.add_child(real_title)
	get_tree().current_scene = real_title
	await get_tree().process_frame
	(real_title.get_node("%StartButton") as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(get_tree().current_scene is EscapeLevel, "按開始遊戲：換到關卡（%s）" % get_tree().current_scene.name)

	if _failures == 0:
		print("[標題畫面測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[標題畫面測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
