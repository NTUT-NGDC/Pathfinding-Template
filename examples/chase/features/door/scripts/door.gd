@tool
class_name Door
extends StaticBody2D
## 門：玩家和殺手都能開。關著的時候擋路也擋視線，開著就都不擋。開關門會發出聲音。
## 上鎖的門要用同顏色的鑰匙打開；上鎖時殺手也過不去。
##
## 用法：把 door.tscn 拖進關卡，放在牆的缺口上（遊戲開始時會自動對齊格子）。
## 想讓門變成「要鑰匙」：勾選「上鎖」，選一個顏色，再放一把同顏色的鑰匙（pickup.tscn）。
##
## 這是尋路積木的「會變的障礙物」：加進 group「path_obstacles」，有 blocks_path、path_cost、is_open、open()，
## 尋路地圖會自動登記；追逐 AI 走到關著的門前會停下來開門，上鎖的門過不去。

## 門開了、關了、上鎖、解鎖時發出（尋路地圖會跟著更新）
signal obstacle_changed()

## 鑰匙和門用顏色配對
const KEY_COLORS: Dictionary[String, Color] = {
	"紅": Color("d94a4a"),
	"藍": Color("4a7bd9"),
	"黃": Color("e0c040"),
	"綠": Color("4ab86a"),
}
## 門關著時佔的物理層：擋路（1）＋擋視線（2）
const CLOSED_LAYERS: int = 1 | 2
## 關著的門走起來比較貴（尋路時算幾格），追的人沒必要時不會專門去開門
const CLOSED_COST: float = 4.0
const DOOR_COLOR: Color = Color("8a6340")
const DOOR_DARK: Color = Color("5a3f28")
## 玩家在門口關門時，被推到門外多遠（門半格 16＋玩家半徑 10＋1）
const STEP_OUT_DISTANCE: float = 27.0

@export_group("門")
## 門板的方向：牆是橫的就選「橫」，牆是直的就選「直」
@export_enum("橫", "直") var orientation: int = 0:
	set(value):
		orientation = value
		queue_redraw()
## 遊戲開始時是不是開著
@export var start_open: bool = false
## 開關門的聲音傳多遠（像素）。0＝不發出聲音
@export_range(0, 800, 10, "suffix:px") var sound_radius: float = 220.0

@export_group("鑰匙")
## 上鎖的門要用同顏色的鑰匙才打得開；殺手也過不去
@export var locked: bool = false:
	set(value):
		locked = value
		queue_redraw()
## 要哪個顏色的鑰匙
@export_enum("紅", "藍", "黃", "綠") var key_color: String = "紅":
	set(value):
		key_color = value
		queue_redraw()

## 現在是不是開著
var is_open: bool = false
## 給尋路地圖看：上鎖＝擋路
var blocks_path: bool:
	get:
		return locked
## 給尋路地圖看：關著的門比較貴
var path_cost: float:
	get:
		return 1.0 if is_open else CLOSED_COST

@onready var _doorway: Area2D = $Doorway
@onready var _interact: Interactable = $Interactable


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("path_obstacles")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_interact.interacted.connect(_on_interacted)
	_set_open(start_open and not locked)


## 玩家按 E：上鎖的話有鑰匙就解鎖並打開；沒鎖就開關門
## 玩家自己站在門口關門：先把玩家推到比較近的那一側再關（門口還有別人就關不起來）
func _on_interacted(player: Player) -> void:
	if locked and player.has_key(key_color):
		unlock(key_color)
		open()
	elif not locked:
		var bodies: Array[Node2D] = _doorway.get_overlapping_bodies()
		if is_open and bodies.size() == 1 and bodies[0] == player:
			_step_out(player)
			_close_now()
		else:
			toggle()


## 開門（上鎖的打不開）。回傳有沒有開成功
func open() -> bool:
	if locked or is_open:
		return false
	_set_open(true)
	_make_sound()
	obstacle_changed.emit()
	return true


## 關門（有人站在門口就關不起來）。回傳有沒有關成功
func close() -> bool:
	if not is_open or is_blocked():
		return false
	_close_now()
	return true


func _close_now() -> void:
	_set_open(false)
	_make_sound()
	obstacle_changed.emit()


## 把站在門口的玩家推到門外：橫的門推到上或下，直的門推到左或右（看玩家比較靠哪邊，剛好在正中間就看面向）
func _step_out(player: Player) -> void:
	var axis: Vector2 = Vector2.DOWN if orientation == 0 else Vector2.RIGHT
	var side: float = signf((player.global_position - global_position).dot(axis))
	if side == 0.0:
		side = 1.0 if player.facing.dot(axis) >= 0.0 else -1.0
	player.global_position = global_position + axis * side * STEP_OUT_DISTANCE


## 開著就關、關著就開
func toggle() -> bool:
	return close() if is_open else open()


## 用鑰匙解鎖（顏色要對）。解鎖後變成一般的門，還沒打開
func unlock(color: String) -> bool:
	if not locked or color != key_color:
		return false
	locked = false
	_update_prompt()
	obstacle_changed.emit()
	return true


## 門口有沒有站人（有的話不能關門，不然會把人卡在門裡）
func is_blocked() -> bool:
	return not _doorway.get_overlapping_bodies().is_empty()


func _set_open(value: bool) -> void:
	is_open = value
	collision_layer = 0 if is_open else CLOSED_LAYERS
	_update_prompt()
	queue_redraw()


## 玩家頭上的提示：開門／關門／需要鑰匙
func _update_prompt() -> void:
	if locked:
		_interact.prompt = "開鎖（需要%s色鑰匙）" % key_color
	else:
		_interact.prompt = "關門" if is_open else "開門"


func _make_sound() -> void:
	if sound_radius > 0.0:
		SoundBus.emit_sound(global_position, sound_radius)


func _draw() -> void:
	var color: Color = KEY_COLORS.get(key_color, DOOR_COLOR) if locked else DOOR_COLOR
	# 門板：關著時橫跨整格，開著時收到一邊
	var panel: Rect2 = Rect2(-16, -5, 32, 10) if orientation == 0 else Rect2(-5, -16, 10, 32)
	if is_open:
		panel = Rect2(-16, -16, 6, 32) if orientation == 0 else Rect2(-16, -16, 32, 6)
	draw_rect(panel, color)
	draw_rect(panel, DOOR_DARK, false, 2.0)
	if locked:
		# 鎖頭：小方塊＋圓弧
		draw_rect(Rect2(-5, -3, 10, 8), DOOR_DARK)
		draw_arc(Vector2(0, -3), 3.5, PI, TAU, 8, DOOR_DARK, 2.0)
