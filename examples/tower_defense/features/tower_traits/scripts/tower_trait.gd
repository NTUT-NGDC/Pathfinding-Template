@tool
class_name TowerTrait
extends Node2D
## 砲塔掛件的共同部分：拖到塔（Tower）底下當子節點就生效，可以掛好幾個。
## 沒放在塔底下的話，場景樹上會有黃色驚嘆號。
##
## 自己做新的掛件：extends TowerTrait，覆寫 apply()（掛上去時改塔的數值）或 on_hit()（每打到一隻怪做什麼）。

## 掛在哪一座塔上
var tower: Tower


func _ready() -> void:
	tower = get_parent() as Tower
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	if tower == null:
		push_warning("%s 要拖到塔（Tower）底下才會生效。" % name)
		return
	tower.hit.connect(on_hit)
	apply()


## 掛上去的時候做什麼
func apply() -> void:
	pass


## 塔每打到一隻怪做什麼
func on_hit(_enemy: Node2D, _damage: float) -> void:
	pass


func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is Tower:
		return PackedStringArray()
	return PackedStringArray(["要拖到塔（Tower）底下才會生效。"])
