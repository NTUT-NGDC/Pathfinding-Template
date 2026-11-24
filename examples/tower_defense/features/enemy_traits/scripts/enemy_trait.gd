@tool
class_name EnemyTrait
extends Node2D
## 怪物掛件的共同部分：拖到怪物（Walker）底下當子節點就生效，可以掛好幾個。
## 沒放在怪物底下的話，場景樹上會有黃色驚嘆號。
##
## 自己做新的掛件：extends EnemyTrait，在 apply() 裡改 walker 的數值（速度、血量……）。
## apply() 在怪物自己準備好「之前」呼叫，所以改 max_health、speed 都會生效。

## 掛在哪一隻怪物上
var walker: Walker


func _ready() -> void:
	walker = get_parent() as Walker
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	if walker == null:
		push_warning("%s 要拖到怪物（Walker）底下才會生效。" % name)
		return
	apply()


## 編輯器的「怪物」頁顯示的名字（給各個掛件覆寫）
func trait_name() -> String:
	return String(name)


## 編輯器的「怪物」頁顯示的欄位名字：欄位 → 中文（沒寫的就顯示欄位原本的名字）
func labels() -> Dictionary:
	return {}


## 掛上去的時候做什麼（給各個掛件覆寫）
func apply() -> void:
	pass


func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is Walker:
		return PackedStringArray()
	return PackedStringArray(["要拖到怪物（Walker）底下才會生效。"])
