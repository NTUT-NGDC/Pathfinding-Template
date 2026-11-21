extends CanvasLayer
## 畫面上的資訊：左上角任務進度和時間、被抓／逃出去時中間的訊息和按鈕。
## 關卡（EscapeLevel）會自動加進去，不用自己放。
##
## 想改文字、字的大小、顏色：打開 hud.tscn，點節點在右邊的檢查器改。

## 按了「再玩一次」
signal retry_pressed()
## 按了「回到標題」
signal title_pressed()

@onready var _level_name: Label = %LevelName
@onready var _tasks: Label = %Tasks
@onready var _time: Label = %Time
@onready var _message: Control = %Message
@onready var _title: Label = %MessageTitle
@onready var _detail: Label = %MessageDetail
@onready var _buttons: Control = %Buttons
@onready var _warning: ColorRect = %Warning


func _ready() -> void:
	_message.hide()
	_warning.hide()
	(%RetryButton as Button).pressed.connect(retry_pressed.emit)
	(%TitleButton as Button).pressed.connect(title_pressed.emit)


func set_level_name(text: String) -> void:
	_level_name.text = text
	_level_name.visible = text != ""


## 任務進度，例如「修理 1/2　鑰匙 0/1」
func set_tasks(text: String) -> void:
	_tasks.text = text


## 經過時間（秒）
func set_time(seconds: float) -> void:
	_time.text = "時間 " + format_time(seconds)


## 被抓了：顯示訊息（關卡會自動重來，不顯示按鈕）
func show_caught() -> void:
	_title.text = "被抓到了！"
	_detail.text = "重新開始……"
	_buttons.hide()
	_message.show()


## 逃出去了：顯示通關時間和按鈕
func show_escaped(seconds: float) -> void:
	_title.text = "逃出去了！"
	_detail.text = "通關時間 " + format_time(seconds)
	_buttons.show()
	_message.show()
	(%RetryButton as Button).grab_focus()


## 接近警告：殺手越近，畫面邊緣越紅（0＝沒有，1＝最紅）
func set_warning(strength: float) -> void:
	_warning.visible = strength > 0.0
	(_warning.material as ShaderMaterial).set_shader_parameter("strength", strength)


## 秒數 → 「1:23.4」
static func format_time(seconds: float) -> String:
	var minutes: int = floori(seconds / 60.0)
	return "%d:%04.1f" % [minutes, seconds - minutes * 60.0]
