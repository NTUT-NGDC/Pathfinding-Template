class_name ThrownBottle
extends Node2D
## 丟出去的瓶子：飛到落點（撞到牆就停在牆前面），碎掉、發出聲音，過一下就消失。
## 不用放進關卡：玩家按 1 時呼叫 ThrownBottle.throw()。

## 落地了（追逐 AI 會聽到 position 的聲音）
signal landed(position: Vector2)

## 飛多久（秒）
const FLIGHT_TIME: float = 0.35
## 碎片留多久（秒）
const SHARDS_TIME: float = 1.5
## 飛的時候拋多高（像素，只是畫面效果）
const ARC_HEIGHT: float = 18.0
## 撞牆用的物理層：擋路（1）
const WALL_LAYER: int = 1

var sound_radius: float = 350.0
var _from: Vector2
var _to: Vector2
var _time: float = 0.0
var _broken: bool = false


## 從 thrower 的位置往 direction 丟出去，最遠 distance 像素；回傳落點
static func throw(thrower: Node2D, direction: Vector2, distance: float, radius: float) -> Vector2:
	var bottle: ThrownBottle = ThrownBottle.new()
	bottle.sound_radius = radius
	bottle._from = thrower.global_position
	bottle._to = landing_point(thrower, direction, distance)
	bottle.z_index = 2
	thrower.get_parent().add_child(bottle)
	bottle.global_position = bottle._from
	return bottle._to


## 落點：往 direction 飛 distance，中間撞到牆就停在牆前面
static func landing_point(thrower: Node2D, direction: Vector2, distance: float) -> Vector2:
	var from: Vector2 = thrower.global_position
	var to: Vector2 = from + direction.normalized() * distance
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, WALL_LAYER)
	var body: CollisionObject2D = thrower as CollisionObject2D
	if body != null:
		query.exclude = [body.get_rid()]
	var hit: Dictionary = thrower.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return (hit["position"] as Vector2) - direction.normalized() * 10.0


func _process(delta: float) -> void:
	_time += delta
	if not _broken:
		var t: float = minf(_time / FLIGHT_TIME, 1.0)
		global_position = _from.lerp(_to, t)
		if t >= 1.0:
			_land()
	elif _time >= SHARDS_TIME:
		queue_free()
	queue_redraw()


func _land() -> void:
	_broken = true
	_time = 0.0
	SoundBus.emit_sound(global_position, sound_radius)
	landed.emit(global_position)


func _draw() -> void:
	if not _broken:
		var t: float = minf(_time / FLIGHT_TIME, 1.0)
		var lift: Vector2 = Vector2(0, -sin(t * PI) * ARC_HEIGHT)
		draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.3))      # 影子
		draw_set_transform(lift, t * TAU * 2.0)                   # 一邊飛一邊轉
		draw_rect(Rect2(-3, -5, 6, 10), Bottle.GLASS)
		draw_set_transform(Vector2.ZERO)
		return
	# 碎片：慢慢淡掉
	var alpha: float = 1.0 - _time / SHARDS_TIME
	for i: int in 6:
		var at: Vector2 = Vector2.from_angle(TAU * i / 6.0 + 0.4) * (4.0 + (i % 3) * 3.0)
		draw_rect(Rect2(at - Vector2(1.5, 1.5), Vector2(3, 3)), Color(Bottle.GLASS, alpha))
	if _time < 0.4:
		draw_arc(Vector2.ZERO, 6.0 + _time * 60.0, 0.0, TAU, 24, Color(1, 1, 1, 0.6 * (1.0 - _time / 0.4)), 2.0)
