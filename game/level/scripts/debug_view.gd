extends Node
## 除錯顯示的開關（autoload，名稱是 DebugView）。遊戲中按數字鍵切換：
##   1 殺手視野錐　2 追擊路徑　3 殺手狀態文字　4 聲音圈圈　5 格子線
## 殺手、除錯圖層讀這裡的值決定要不要畫。
## 視野錐一開始開不開，由關卡（EscapeLevel）的「顯示殺手視野錐」決定。

## 有開關被切換了
signal changed()

var show_cones: bool = true
var show_paths: bool = false
var show_states: bool = false
var show_sounds: bool = false
var show_grid: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_vision"):
		show_cones = not show_cones
	elif event.is_action_pressed("debug_path"):
		show_paths = not show_paths
	elif event.is_action_pressed("debug_state"):
		show_states = not show_states
	elif event.is_action_pressed("debug_sound"):
		show_sounds = not show_sounds
	elif event.is_action_pressed("debug_grid"):
		show_grid = not show_grid
	else:
		return
	changed.emit()


## 回到預設（每次開始一個關卡時呼叫）
func reset(cones: bool) -> void:
	show_cones = cones
	show_paths = false
	show_states = false
	show_sounds = false
	show_grid = false
	changed.emit()
