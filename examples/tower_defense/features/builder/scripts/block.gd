@tool
class_name TDWall
extends Node2D
## 牆：Builder 蓋的牆，登記成尋路地圖的障礙物（PathGrid.register_obstacle）。
##   ・Breakable 打勾：怪走得過去，但要先打破。Break Cost 是「拆牆等於多走幾格」，A* 會比較要繞路還是拆牆
##   ・Breakable 不勾：怪打不壞，一定要繞路（不能把路堵死）

## 被打破了
signal broken()
## 擋不擋路、成本變了（尋路地圖會重看）
signal obstacle_changed()

## 可以被破壞
@export var breakable: bool = true
## 血量
@export_range(1, 1000, 1) var max_health: float = 6.0
## 拆牆等於多走幾格：越大怪越願意繞路
@export_range(1, 100, 1) var break_cost: float = 12.0
## 顏色
@export var color: Color = Color("6b7080"):
	set(value):
		color = value
		queue_redraw()

## 尋路地圖讀的：擋不擋路、成本
var blocks_path: bool:
	get: return not breakable
var path_cost: float:
	get: return break_cost
## 已經破了（PathFollower 看這個知道不用再打）
var is_broken: bool = false
var health: float = 0.0


func _ready() -> void:
	health = max_health


## 被打：血扣光就破
func damage(amount: float) -> void:
	if is_broken or not breakable:
		return
	health = maxf(health - amount, 0.0)
	queue_redraw()
	if health <= 0.0:
		is_broken = true
		broken.emit()


## 血剩幾成（0～1）
func health_ratio() -> float:
	return clampf(health / max_health, 0.0, 1.0)


func _draw() -> void:
	draw_rect(Rect2(-15, -15, 30, 30), color.darkened(0.4))
	draw_rect(Rect2(-13, -13, 26, 26), color)
	draw_rect(Rect2(-13, -13, 26, 5), color.lightened(0.2))
	if Engine.is_editor_hint() or health >= max_health:
		return
	# 受傷：裂痕越來越多、下面一條血條
	var crack: Color = color.darkened(0.7)
	draw_polyline(PackedVector2Array([Vector2(-10, -8), Vector2(-3, -2), Vector2(-6, 6)]), crack, 2.0)
	if health_ratio() < 0.66:
		draw_polyline(PackedVector2Array([Vector2(9, -9), Vector2(3, -1), Vector2(8, 5)]), crack, 2.0)
	if health_ratio() < 0.33:
		draw_polyline(PackedVector2Array([Vector2(-11, 3), Vector2(0, 2), Vector2(4, 9)]), crack, 2.0)
	draw_rect(Rect2(-13, 10, 26, 3), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-13, 10, 26 * health_ratio(), 3), Color("4ab86a").lerp(Color("d94a4a"), 1.0 - health_ratio()))
