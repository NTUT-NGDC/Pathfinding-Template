class_name VisionSensor
extends Node2D
## 視野：放在角色底下，每一幀檢查看不看得到目標。
## 看得到的那一幀發出 target_seen，看不到的那一幀發出 target_lost；現在的結果在 sees_target。
##
## 看得到要過三關，便宜的先算，前面沒過就不用算後面的：
##   ① 夠近嗎？（距離）
##   ② 在前面嗎？（向量內積）
##   ③ 中間有東西擋嗎？（射線，只檢查「擋視線」的物理層 2）
##
## 面向：主人每一幀設定 facing；或打勾「跟著旋轉」，直接用這個節點的旋轉當面向。
## 目標有 is_hidden 屬性而且是 true（躲起來了）的話，看不到。
## 視野錐畫在最上層（玩家視野圈、黑暗都蓋不掉），遊戲中按 F1 可以開關。

## 開始看得到目標
signal target_seen(target: Node2D)
## 看不到目標了
signal target_lost(target: Node2D)

## 「擋視線」是第 2 個物理層
const SIGHT_LAYER: int = 1 << 1

@export_group("視野")
## 看多遠（像素）。0＝完全看不到
@export_range(0, 1000, 10, "suffix:px") var view_distance: float = 260.0
## 視野角度（度）。90＝左右各 45 度；360＝背後也看得到
@export_range(10, 360, 5, "suffix:°") var view_angle: float = 90.0
## 牆會擋視線。關掉 → 隔著牆也看得到
@export var walls_block_sight: bool = true
## 檢查角度。關掉 → 背後也長眼睛
@export var check_angle: bool = true
## 要看的目標在哪個 group（預設看玩家）
@export var target_group: String = "player"
## 打勾：用這個節點的旋轉當面向（角色會轉身的話）；不打勾：主人自己設定 facing
@export var follow_rotation: bool = false

@export_group("視野錐")
## 顯示視野錐（遊戲中按 F1 可以全部關掉）
@export var show_cone: bool = true
## 視野錐的顏色
@export var cone_color: Color = Color(1, 1, 1, 0.16)
## 視野錐用幾條射線畫（越多越圓滑、越吃效能）
@export_range(6, 64, 1) var cone_rays: int = 24

## 面向（單位向量）
var facing: Vector2 = Vector2.RIGHT
## 要看的目標（沒設定的話自動找 target_group 裡的第一個）
var target: Node2D
## 現在看不看得到目標
var sees_target: bool = false

var _exclude: Array[RID] = []
## 剛載入的前兩幀先不看：牆的碰撞還沒準備好，會隔牆看到
var _frames_to_wait: int = 2
var _drawer: Node2D


func _ready() -> void:
	process_physics_priority = -1                                 # 比主人先算，主人拿到的才是這一幀的結果
	var body: CollisionObject2D = get_parent() as CollisionObject2D
	if body != null:
		_exclude.append(body.get_rid())
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 11
	layer.follow_viewport_enabled = true
	add_child(layer)
	_drawer = Node2D.new()
	_drawer.draw.connect(_draw_cone)
	layer.add_child(_drawer)


func _physics_process(_delta: float) -> void:
	if follow_rotation:
		facing = Vector2.from_angle(global_rotation)
	_drawer.queue_redraw()
	if _frames_to_wait > 0:
		_frames_to_wait -= 1
		return
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group(target_group) as Node2D
		if target == null:
			return
	var now: bool = can_see(target)
	if now != sees_target:
		sees_target = now
		if now:
			target_seen.emit(target)
		else:
			target_lost.emit(target)


## 視野三關：距離 → 角度 → 射線
func can_see(who: Node2D) -> bool:
	if view_distance <= 0.0 or who.get("is_hidden") == true:
		return false                                              # 看不到東西，或目標躲起來了
	var to_target: Vector2 = who.global_position - global_position
	if to_target.length() > view_distance:
		return false                                              # ① 太遠
	if check_angle and facing.dot(to_target.normalized()) < cos(deg_to_rad(view_angle / 2.0)):
		return false                                              # ② 不在前面（內積＝兩個方向有多接近）
	if walls_block_sight and not _cast(global_position, who.global_position).is_empty():
		return false                                              # ③ 被擋住
	return true


func _cast(from: Vector2, to: Vector2) -> Dictionary:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, SIGHT_LAYER, _exclude)
	return get_world_2d().direct_space_state.intersect_ray(query)


## 視野錐的形狀（相對於自己的位置）：往外射 cone_rays 條線，撞到牆就停在牆上
func get_cone_polygon() -> PackedVector2Array:
	var angle: float = deg_to_rad(view_angle) if check_angle else TAU
	var rays: int = cone_rays if check_angle else cone_rays * 2
	var points: PackedVector2Array = PackedVector2Array()
	if check_angle:
		points.append(Vector2.ZERO)
	var start: float = facing.angle() - angle / 2.0
	for i: int in rays + 1:
		var direction: Vector2 = Vector2.from_angle(start + angle * i / rays)
		var end: Vector2 = global_position + direction * view_distance
		if walls_block_sight:
			var hit: Dictionary = _cast(global_position, end)
			if not hit.is_empty():
				end = hit["position"]
		points.append(end - global_position)
	return points


func _draw_cone() -> void:
	if not show_cone or not PathDebug.show_cones or not is_visible_in_tree() or view_distance <= 0.0:
		return
	var edge: PackedVector2Array = get_cone_polygon()
	for i: int in edge.size():
		edge[i] += global_position
	draw_fan(_drawer, global_position, edge, cone_color)


## 畫扇形：從 center 到邊緣 edge，一片一片的三角形。
## 不用 draw_colored_polygon()：一整圈、貼著牆的時候頂點會重疊，切不出三角形就會出錯
static func draw_fan(canvas: CanvasItem, center: Vector2, edge: PackedVector2Array, color: Color) -> void:
	if edge.size() < 2:
		return
	var points: PackedVector2Array = PackedVector2Array([center])
	points.append_array(edge)
	var triangles: PackedInt32Array = PackedInt32Array()
	for i: int in range(1, edge.size()):
		triangles.append_array([0, i, i + 1])
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), triangles, points, PackedColorArray([color]))
