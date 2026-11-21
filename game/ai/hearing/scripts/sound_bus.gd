extends Node
## 聲音系統（autoload，名稱是 SoundBus）：遊戲裡「發出聲音」都經過這裡。
## 跑步、修理、開關門時呼叫 SoundBus.emit_sound(位置, 範圍)，
## 它會用 signal 廣播出去，殺手身上的「聽覺」（HearingSensor）收到後自己判斷聽不聽得到。
##
## 這裡只管「哪裡發出多大的聲音」，不管誰聽到：發出聲音的人不用知道場上有幾隻殺手。

## 有東西發出聲音。position 是全局座標，radius 是聲音傳多遠（像素）
signal sound_emitted(position: Vector2, radius: float)


## 在某個位置發出聲音
func emit_sound(position: Vector2, radius: float) -> void:
	sound_emitted.emit(position, radius)
