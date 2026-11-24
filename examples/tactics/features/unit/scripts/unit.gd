@tool
class_name Unit
extends Node2D
## 棋子：我方和敵方都用這個。底下有 PathFollower 負責走路，可以再掛特性（features/unit_traits/）。
## 戰鬥怎麼輪由 TacticsBattle 決定；這裡只管自己的數值、受傷、怎麼畫。
##
## 做新的棋子：用 map_editor 的「棋子」頁，或在 Godot 裡「新增繼承場景」選 unit.tscn，改數值、把特性拖到底下。

## 血量變了
signal health_changed()
## 倒下了
signal died(unit: Unit)

enum Mind { CHARGE, GUARD, WEAKEST, DISTANCE }
const MIND_NAMES: Array[String] = ["衝鋒", "守衛", "挑最弱的", "保持距離"]
const TEAM_COLORS: Array[Color] = [Color("3f78e0"), Color("d94a4a")]

## 名字
@export var display_name: String = "棋子"
## 畫在身上的字（一個字）
@export var mark: String = "兵":
	set(value):
		mark = value
		queue_redraw()
## 身體的顏色（外圈是隊伍的顏色）
@export var color: Color = Color("e6d3a8"):
	set(value):
		color = value
		queue_redraw()

@export_group("數值")
## 血量
@export_range(1, 200, 1) var max_health: int = 20
## 攻擊（扣血＝攻擊 － 對方的防禦，最少 1）
@export_range(0, 50, 1) var attack: int = 6
## 防禦
@export_range(0, 50, 1) var defense: int = 1
## 一回合可以走多遠（沼澤一格算 3，森林、高地算 2）
@export_range(0, 20, 1) var move_points: int = 4
## 最近打得到幾格（弓箭手 2＝旁邊的打不到）
@export_range(1, 10, 1) var min_range: int = 1
## 最遠打得到幾格
@export_range(1, 10, 1) var max_range: int = 1
## 速度：每一輪從快到慢輪流動
@export_range(1, 30, 1) var speed: int = 5

@export_group("電腦")
## 個性：衝鋒＝打最近的；守衛＝有人走進打得到的範圍才動；挑最弱的＝打血最少的；保持距離＝打得到就站最遠
@export_enum("衝鋒", "守衛", "挑最弱的", "保持距離") var mind: int = 0

## 0 我方、1 敵方
var team: int = 0:
	set(value):
		team = value
		queue_redraw()
var health: int = 0
## 倒下了
var is_down: bool = false
## 補血的量（「治療」特性會給；0＝不會補血）
var heal_power: int = 0
## 這一輪走了幾格（突擊用）
var steps_taken: int = 0
## 被打過了（守衛會醒過來）
var provoked: bool = false
## 面向（探索時畫眼睛）
var facing: Vector2 = Vector2.RIGHT
## 輪到它了（外圈會亮）
var is_active: bool = false:
	set(value):
		is_active = value
		queue_redraw()
## 頭上的記號（? 或 !），空的＝沒有
var alert_mark: String = "":
	set(value):
		if alert_mark != value:
			alert_mark = value
			queue_redraw()
## 離地多高（飛行用，畫的時候往上移，影子留在地上）
var lift: float = 0.0:
	set(value):
		if not is_equal_approx(lift, value):
			lift = value
			queue_redraw()
## 要不要畫血條
var show_health: bool = true:
	set(value):
		show_health = value
		queue_redraw()

const RADIUS: float = 12.0

var _traits: Array[UnitTrait] = []


func _ready() -> void:
	if not Engine.is_editor_hint():
		_traits = _find_traits()                                  # 算移動範圍時會一直問，先記起來
	health = max_health                                           # 特性（子節點）先準備好了，這時已經改過數值
	if not Engine.is_editor_hint():
		add_to_group("tactics_units")


func follower() -> PathFollower:
	return $PathFollower as PathFollower


## 掛在身上的特性
func traits() -> Array[UnitTrait]:
	return _find_traits() if Engine.is_editor_hint() or not is_node_ready() else _traits


func _find_traits() -> Array[UnitTrait]:
	var result: Array[UnitTrait] = []
	for child: Node in get_children():
		if child is UnitTrait:
			result.append(child as UnitTrait)
	return result


# ---- 走路 ----

## 走進一格要花多少移動力（負數＝不能走）。blocked＝那格是牆
func step_cost(base: float, blocked: bool) -> float:
	var cost: float = -1.0 if blocked else base
	for t: UnitTrait in traits():
		cost = t.step_cost(cost, base, blocked)
	return cost


## 會飛（可以越過牆和敵人、不吃地形防禦）
func is_flying() -> bool:
	return traits().any(func(t: UnitTrait) -> bool: return t.is_flying())


# ---- 血 ----

func take_damage(amount: int) -> void:
	if is_down:
		return
	health = maxi(health - amount, 0)
	provoked = true
	_changed()
	if health == 0:
		is_down = true
		died.emit(self)


func heal(amount: int) -> int:
	if is_down:
		return 0
	var before: int = health
	health = mini(health + amount, max_health)
	_changed()
	return health - before


## 倒下之後站起來
func revive(amount: int) -> void:
	is_down = false
	health = clampi(amount, 1, max_health)
	_changed()


func _changed() -> void:
	health_changed.emit()
	queue_redraw()


## 滑鼠指到時顯示的說明
func info_text() -> String:
	var reach: String = str(max_range) if min_range == max_range else "%d～%d" % [min_range, max_range]
	var text: String = "%s　血 %d/%d\n攻 %d　防 %d　移 %d\n射程 %s　速度 %d" % [display_name, health, max_health, attack, defense, move_points, reach, speed]
	var names: PackedStringArray = PackedStringArray()
	for t: UnitTrait in traits():
		names.append(t.trait_name())
	if not names.is_empty():
		text += "\n特性：" + "、".join(names)
	if team == 1:
		text += "\n個性：" + MIND_NAMES[mind]
	return text


# ---- 畫 ----

func _draw() -> void:
	if lift > 0.0:
		draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, RADIUS * 0.85, Color(0, 0, 0, 0.4))   # 地上的影子
		draw_set_transform(Vector2(0, -lift))
	draw_token(self, Vector2.ZERO, RADIUS, color, TEAM_COLORS[team], mark)
	if is_active:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0, TAU, 32, Color(1, 1, 0.5), 2.0)
	for t: UnitTrait in traits():
		t.draw_on(self)
	if show_health and not Engine.is_editor_hint():
		var width: float = 24.0
		draw_rect(Rect2(-width / 2 - 1, -23, width + 2, 6), Color(0, 0, 0, 0.75))
		var ratio: float = float(health) / max_health
		draw_rect(Rect2(-width / 2, -22, width * ratio, 4), Color("4ab86a") if ratio > 0.5 else Color("e0a526") if ratio > 0.25 else Color("d94a4a"))
	if not alert_mark.is_empty():
		draw_string(font(), Vector2(-11, -26), alert_mark, HORIZONTAL_ALIGNMENT_CENTER, 22, 22, Color("ffe066") if alert_mark == "?" else Color("ff5a4a"))


## 一顆棋子（編輯器、行動順序也用這個畫）
static func draw_token(on: CanvasItem, at: Vector2, radius: float, body: Color, ring: Color, text: String) -> void:
	on.draw_circle(at + Vector2(0, 2), radius + 1.0, Color(0, 0, 0, 0.35))
	on.draw_circle(at, radius, ring)
	on.draw_circle(at, radius - 2.5, body)
	var font_size: int = 11 if radius < 16.0 else 22
	var ink: Color = Color("2a2a30") if body.get_luminance() > 0.45 else Color.WHITE
	on.draw_string(font(), at + Vector2(-radius, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, ink)


static func font() -> Font:
	return ThemeDB.fallback_font
