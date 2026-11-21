extends Control
## 標題畫面：開始遊戲／設定（音量）／離開遊戲。這是專案的主場景，按 F5 會先看到它。
##
## 想改文字、字的大小、顏色、字型、背景圖：直接點場景裡的節點，在右邊的檢查器改，程式不會蓋掉。
##   ・遊戲名稱：GameName 的 Text
##   ・小字：Hook 的 Text（寫上作者、通關時間）
##   ・按鈕文字：StartButton、LabButton（A* 實驗室，社課用）、SettingsButton、QuitButton 的 Text
##   ・背景圖：把圖片拖進 BackgroundImage 的 Texture
##
## 點最上層的 TitleScreen 節點，在檢查器設定：
##   ・Level Scene：按「開始遊戲」要玩的關卡（預設是 my_level/my_level.tscn）
##   ・Title Music：標題畫面的背景音樂（空著就沒有音樂）

## 按「開始遊戲」要玩的關卡
@export var level_scene: PackedScene
## 按「A* 實驗室」要打開的場景（社課用，網頁版沒有這個按鈕）
@export_file("*.tscn") var lab_scene: String = "res://lesson/astar_lab/astar_lab.tscn"
## 標題畫面的背景音樂（.mp3、.ogg、.wav），空著就沒有音樂
@export var title_music: AudioStream

@onready var _start_button: Button = %StartButton
@onready var _lab_button: Button = %LabButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _message_label: Label = %MessageLabel
@onready var _settings_panel: Control = %SettingsPanel
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_message_label.hide()
	_settings_panel.hide()
	# Web 版沒辦法用程式關掉瀏覽器分頁，按了不會有反應，所以藏起來
	_quit_button.visible = not OS.has_feature("web")
	# A* 實驗室是社課工具，匯出時排除：網頁版、匯出的版本沒有，藏起來
	_lab_button.visible = not OS.has_feature("web") and lab_scene != "" and ResourceLoader.exists(lab_scene)

	_start_button.pressed.connect(_on_start_pressed)
	_lab_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(lab_scene))
	_settings_button.pressed.connect(_settings_panel.show)
	_back_button.pressed.connect(_settings_panel.hide)
	_quit_button.pressed.connect(get_tree().quit)
	_play_title_music()
	_start_button.grab_focus()


## 有設定標題音樂就播放：接到 Music 匯流排（設定裡的「音樂」滑桿管得到）
func _play_title_music() -> void:
	if title_music == null:
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = "TitleMusicPlayer"
	player.stream = title_music
	player.bus = &"Music"
	player.finished.connect(player.play)                          # 播完從頭再播
	add_child(player)
	player.play()


func _unhandled_input(event: InputEvent) -> void:
	# 設定面板打開時，按 Esc 也可以關掉
	if _settings_panel.visible and event.is_action_pressed("ui_cancel"):
		_settings_panel.hide()
		get_viewport().set_input_as_handled()


## 開始遊戲：換到關卡
func _on_start_pressed() -> void:
	if level_scene == null:
		_message_label.text = "還沒有設定關卡。\n請點選 TitleScreen 節點，把 my_level.tscn 拖進檢查器的「Level Scene」。"
		_message_label.show()
		return
	get_tree().change_scene_to_packed(level_scene)
