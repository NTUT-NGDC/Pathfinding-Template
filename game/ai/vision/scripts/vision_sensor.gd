class_name VisionSensor
extends Node2D
## 視野元件：放在角色底下，每一幀檢查看不看得到目標（玩家）。
## 看得到的那一幀發出 target_seen，看不到的那一幀發出 target_lost；現在的結果在 sees_target。
##
## 看得到要過三關，便宜的先算，前面沒過就不用算後面的：
##   ① 夠近嗎？（距離）
##   ② 在前面嗎？（向量內積）
##   ③ 中間有東西擋嗎？（射線，只檢查「擋視線」的物理層）
##
## 也會算出視野錐的形狀（get_cone_polygon()），被牆切掉的部分會缺一塊，畫圖交給主人。

## 開始看得到目標
signal target_seen(target: Node2D)
## 看不到目標了
signal target_lost(target: Node2D)

## 「擋視線」是第 2 個物理層
const SIGHT_LAYER: int = 1 << 1
## 視野錐用幾條射線畫（越多越圓滑、越吃效能）
const CONE_RAY_COUNT: int = 24

## 看多遠（像素）
var view_distance: float = 260.0
## 視野角度（度），90＝左右各 45 度
var view_angle: float = 90.0
## 面向（單位向量），由主人每一幀設定
var facing: Vector2 = Vector2.RIGHT
## 關掉 → 隔著牆也看得到
var walls_block_sight: bool = true
## 關掉 → 不檢查角度，背後也長眼睛
var check_angle: bool = true
## 要看的目標（沒設定的話自動找 group「player」）
var target: Node2D
## 現在看不看得到目標
var sees_target: bool = false

var _exclude: Array[RID] = []


func _ready() -> void:
	process_physics_priority = -1                                 # 比主人先算，主人拿到的才是這一幀的結果
	var body: CollisionObject2D = get_parent() as CollisionObject2D
	if body != null:
		_exclude.append(body.get_rid())


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node2D
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
	if who.get("is_hidden") == true:
		return false                                              # 躲起來了
	var to_target: Vector2 = who.global_position - global_position
	if to_target.length() > view_distance:
		return false                                              # ① 太遠
	if check_angle and facing.dot(to_target.normalized()) < cos(deg_to_rad(view_angle / 2.0)):
		return false                                              # ② 不在前面（內積＝兩個方向有多接近）
	if walls_block_sight and _ray_hits_wall(global_position, who.global_position):
		return false                                              # ③ 被擋住
	return true


## 從 from 射一條線到 to，中間有沒有撞到「擋視線」的東西
func _ray_hits_wall(from: Vector2, to: Vector2) -> bool:
	return not _cast(from, to).is_empty()


func _cast(from: Vector2, to: Vector2) -> Dictionary:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, SIGHT_LAYER, _exclude)
	return get_world_2d().direct_space_state.intersect_ray(query)


## 視野錐的形狀（區域座標）：從自己往外射 CONE_RAY_COUNT 條線，撞到牆就停在牆上
func get_cone_polygon() -> PackedVector2Array:
	var angle: float = deg_to_rad(view_angle) if check_angle else TAU
	var rays: int = CONE_RAY_COUNT if check_angle else CONE_RAY_COUNT * 2
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
