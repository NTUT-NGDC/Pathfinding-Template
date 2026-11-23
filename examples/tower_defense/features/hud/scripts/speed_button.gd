extends Button
## 倍速按鈕：按一下在 1×、2×、3× 之間切換（改 Engine.time_scale）。離開這一關會自動變回 1×。

## 可以切換的速度
@export var speeds: Array[float] = [1.0, 2.0, 3.0]

var _index: int = 0


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	pressed.connect(next_speed)
	_apply()


## 換下一個速度
func next_speed() -> void:
	_index = (_index + 1) % speeds.size()
	_apply()


func _apply() -> void:
	Engine.time_scale = speeds[_index]
	text = "▶ %s×" % str(speeds[_index]).trim_suffix(".0")


func _exit_tree() -> void:
	Engine.time_scale = 1.0
