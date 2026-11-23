@tool
class_name Pickup
extends Node2D
## 撿得起來的東西：寶物或鑰匙。玩家按 E 撿起來。
## 「算進出口條件」打勾的，出口會算它（畫面左上角會顯示「寶物 1/3」，看出口的「開門條件」）。
## 鑰匙可以打開同顏色的上鎖的門。
##
## 用法：把 pickup.tscn 拖進關卡，在檢查器選它是什麼。
##
## 它是一個「目標」：在 objectives 群組、有 required／is_done／category、完成時發出 completed。

## 被撿起來了
signal picked(pickup: Pickup)
## 完成了（＝被撿起來了；目標的共同 signal）
signal completed(objective: Node)

const KEY_COLORS: Dictionary[String, Color] = {
	"紅": Color("d94a4a"), "藍": Color("4a7bd9"), "黃": Color("e0c040"), "綠": Color("4ab86a")}
const TREASURE_COLOR: Color = Color("ffd75e")

## 寶物，或是哪個顏色的鑰匙
@export_enum("寶物", "紅", "藍", "黃", "綠") var kind: String = "寶物":
	set(value):
		kind = value
		queue_redraw()
## 打勾：算進出口的開門條件
@export var required: bool = true
## 撿起來時發出的聲音傳多遠（像素）。0＝不出聲
@export_range(0, 800, 10, "suffix:px") var sound_radius: float = 0.0

var is_picked: bool = false
## 完成了沒（＝撿起來了沒）
var is_done: bool:
	get:
		return is_picked
## 分類：寶物或鑰匙（給出口和畫面左上角的計數用）
var category: String:
	get:
		return "寶物" if kind == "寶物" else "鑰匙"

@onready var _interact: Interactable = $Interactable


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("pickups")
		add_to_group("objectives")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_interact.prompt = "撿起寶物" if kind == "寶物" else "撿起%s色鑰匙" % kind
	_interact.interacted.connect(_on_interacted)


func _on_interacted(player: Player) -> void:
	if is_picked:
		return
	is_picked = true
	if kind != "寶物":
		player.add_key(kind)
	if sound_radius > 0.0:
		SoundBus.emit_sound(global_position, sound_radius)
	_interact.enabled = false
	visible = false
	picked.emit(self)
	completed.emit(self)


func _draw() -> void:
	if kind == "寶物":
		# 寶物：菱形寶石
		var gem: PackedVector2Array = [Vector2(0, -9), Vector2(8, 0), Vector2(0, 9), Vector2(-8, 0)]
		draw_colored_polygon(gem, TREASURE_COLOR)
		draw_polyline(gem + PackedVector2Array([gem[0]]), TREASURE_COLOR.darkened(0.5), 2.0)
		return
	var color: Color = KEY_COLORS.get(kind, Color.WHITE)
	var dark: Color = color.darkened(0.5)
	# 鑰匙：圓頭＋桿子＋兩個齒
	draw_circle(Vector2(-6, 0), 6.0, dark)
	draw_circle(Vector2(-6, 0), 4.5, color)
	draw_circle(Vector2(-6, 0), 1.8, dark)
	draw_rect(Rect2(-1, -1.5, 12, 3), color)
	draw_rect(Rect2(7, 1, 2, 4), color)
	draw_rect(Rect2(3, 1, 2, 3), color)
