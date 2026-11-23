@tool
class_name Exit
extends StaticBody2D
## 出口：達成「開門條件」才會打開；玩家走進打開的出口就贏了。
## 關著的時候跟牆一樣擋路、擋視線。
##
## 用法：把 exit.tscn 拖進關卡，放在外牆的缺口上，在檢查器選「開門條件」：
##   ・全部：關卡裡「算進出口條件」打勾的目標（寶物、任務點……）全部完成
##   ・指定：只看「指定目標」清單，把寶物、任務點節點拖進清單
##   ・數量：「算進出口條件」打勾的目標裡，完成任意幾個就好（調「需要幾個」）
##   ・一開始就開：沒有條件
##
## 「目標」是什麼：在 objectives 群組裡、有 required（算不算）、is_done（完成了沒）、
## category（分類名稱，例如「寶物」）三個屬性、完成時發出 completed signal 的節點。
## 寶物（Pickup）和任務點（TaskPoint）都是；自己寫新的目標照這個做，出口就會自動算到它。

## 出口打開了
signal opened()
## 進度變了（完成了幾個、需要幾個）
signal progress_changed(done: int, needed: int)

## 什麼時候開門
@export_enum("全部", "指定", "數量", "一開始就開") var open_when: int = 0
## 開門條件選「指定」時：只看這些目標（把寶物、任務點節點拖進來）
@export var targets: Array[Node] = []
## 開門條件選「數量」時：完成幾個就開
@export_range(1, 50) var needed: int = 1
## 門板的方向：牆是橫的就選「橫」，牆是直的就選「直」
@export_enum("橫", "直") var orientation: int = 0:
	set(value):
		orientation = value
		queue_redraw()

const CLOSED_LAYERS: int = 1 | 2
const CLOSED_COLOR: Color = Color("6a6f78")
const OPEN_COLOR: Color = Color("3fd17a")

var is_open: bool = false
## 出口在看的目標
var tracked: Array[Node] = []

@onready var _goal: Area2D = $Goal


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group("exits")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_goal.body_entered.connect(_on_goal_body_entered)
	_collect.call_deferred()                                      # 等關卡裡的東西都準備好再數


func _collect() -> void:
	tracked.clear()
	match open_when:
		0, 2:
			for node: Node in get_tree().get_nodes_in_group("objectives"):
				if node.get("required") == true:
					tracked.append(node)
		1:
			for node: Node in targets:
				if node != null and node.has_signal("completed"):
					tracked.append(node)
	for node: Node in tracked:
		node.connect("completed", func(_o: Node) -> void: _check())
	_check()


## 完成了幾個
func done_count() -> int:
	return tracked.filter(func(n: Node) -> bool: return is_instance_valid(n) and n.get("is_done") == true).size()


## 需要完成幾個才開門
func needed_count() -> int:
	match open_when:
		2: return mini(needed, tracked.size())
		3: return 0
		_: return tracked.size()


## 照分類算進度：{"寶物": [完成幾個, 總共幾個], ...}，順序照關卡裡的順序
func progress_by_category() -> Dictionary[String, Vector2i]:
	var result: Dictionary[String, Vector2i] = {}
	for node: Node in tracked:
		if not is_instance_valid(node):
			continue
		var category: String = str(node.get("category"))
		var count: Vector2i = result.get(category, Vector2i.ZERO)
		result[category] = count + Vector2i(1 if node.get("is_done") == true else 0, 1)
	return result


func _check() -> void:
	progress_changed.emit(done_count(), needed_count())
	if is_open or done_count() < needed_count():
		return
	is_open = true
	collision_layer = 0                                           # 打開：不擋路、不擋視線
	queue_redraw()
	opened.emit()


func _on_goal_body_entered(body: Node2D) -> void:
	if is_open and body is Player:
		(body as Player).escape()


func _draw() -> void:
	var color: Color = OPEN_COLOR if is_open else CLOSED_COLOR
	var panel: Rect2 = Rect2(-16, -8, 32, 16) if orientation == 0 else Rect2(-8, -16, 16, 32)
	draw_rect(panel, color)
	draw_rect(panel, color.darkened(0.5), false, 2.0)
	if is_open:
		draw_rect(panel.grow(3), Color(OPEN_COLOR, 0.35), false, 3.0)
	else:
		draw_line(Vector2(-5, -5), Vector2(5, 5), color.darkened(0.5), 2.0)
		draw_line(Vector2(5, -5), Vector2(-5, 5), color.darkened(0.5), 2.0)
