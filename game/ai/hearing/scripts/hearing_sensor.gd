class_name HearingSensor
extends Node2D
## 聽覺元件：放在角色底下。有東西發出聲音（SoundBus）時，
## 如果自己在聲音的範圍內，就發出 sound_heard(位置)。
##
## 聲音不會被牆擋住、也不會越遠越小（想做的話可以認領研究題目）。

## 聽到聲音了（聲音的全局座標）
signal sound_heard(position: Vector2)

## 關掉＝沒有耳朵
var enabled: bool = true
## 聽力範圍倍率：2＝聲音傳兩倍遠也聽得到，0.5＝要很近才聽得到
var range_multiplier: float = 1.0


func _ready() -> void:
	SoundBus.sound_emitted.connect(_on_sound_emitted)


## 聽不聽得到：在聲音範圍（× 倍率）裡面就聽得到
func can_hear(sound_position: Vector2, radius: float) -> bool:
	if not enabled:
		return false
	return global_position.distance_to(sound_position) <= radius * range_multiplier


func _on_sound_emitted(sound_position: Vector2, radius: float) -> void:
	if can_hear(sound_position, radius):
		sound_heard.emit(sound_position)
