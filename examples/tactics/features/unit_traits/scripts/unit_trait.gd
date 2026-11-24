@tool
class_name UnitTrait
extends Node2D
## 棋子特性的共同部分：拖到棋子（Unit）底下當子節點就生效，可以掛好幾個。
## 沒放在棋子底下的話，場景樹上會有黃色驚嘆號。
##
## 自己做新的特性：extends UnitTrait，覆寫下面需要的函式就好（其他的不用寫）。

## 掛在哪一隻棋子上
var unit: Unit


func _ready() -> void:
	unit = get_parent() as Unit
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	if unit == null:
		push_warning("%s 要拖到棋子（Unit）底下才會生效。" % name)
		return
	apply()


# ---- 給各個特性覆寫 ----

## 編輯器的「棋子」頁顯示的名字
func trait_name() -> String:
	return String(name)


## 一句話說明（編輯器裡滑鼠停著會看到）
func description() -> String:
	return ""


## 編輯器的「棋子」頁顯示的欄位名字：欄位 → 中文
func labels() -> Dictionary:
	return {}


## 一開始改數值（血量、攻擊、移動力……）
func apply() -> void:
	pass


## 走進一格要花多少移動力：cost 是目前算出來的（負數＝不能走）、base 是地形的、blocked＝是牆
func step_cost(cost: float, _base: float, _blocked: bool) -> float:
	return cost


## 會飛（可以越過牆和敵人、不吃地形防禦）
func is_flying() -> bool:
	return false


## 走進這隻旁邊的敵人要停下來
func intercepts() -> bool:
	return false


## 打人時改攻擊力
func modify_attack(power: float, _target: Unit, _battle: TacticsBattle) -> float:
	return power


## 被打時改扣的血
func modify_taken(damage: float, _attacker: Unit, _battle: TacticsBattle) -> float:
	return damage


## 旁邊的自己人被打時改扣的血
func protect(damage: float, _ally: Unit) -> float:
	return damage


## 輪到自己、還沒動之前
func turn_started(_battle: TacticsBattle) -> void:
	pass


## 打完之後（damage 是真的扣掉的血）
func after_attack(_target: Unit, _damage: int, _battle: TacticsBattle) -> void:
	pass


## 被打之後（還活著才會叫）。is_counter＝對方這一下是還手
func after_hit(_attacker: Unit, _damage: int, _is_counter: bool, _battle: TacticsBattle) -> void:
	pass


## 畫在棋子身上的裝飾
func draw_on(_on: Unit) -> void:
	pass


func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is Unit:
		return PackedStringArray()
	return PackedStringArray(["要拖到棋子（Unit）底下才會生效。"])
