extends Label
## 畫面上的「第 1 波」：生怪器的 wave_started 已經在關卡裡連到 show_wave。

## 第幾波的文字格式
@export var format: String = "第 %d 波"


func show_wave(wave_number: int) -> void:
	text = format % wave_number
