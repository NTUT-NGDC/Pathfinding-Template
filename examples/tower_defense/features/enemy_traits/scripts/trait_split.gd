@tool
class_name TraitSplit
extends EnemyTrait
## 分裂：死掉的時候分成幾隻小的（小的不會再分裂），一樣走向基地、算進這一波。

## 分成幾隻
@export_range(1, 8) var count: int = 2
## 小的血量是原本的幾倍
@export_range(0.1, 1.0, 0.05) var health_ratio: float = 0.4
## 小的速度是原本的幾倍
@export_range(0.5, 3.0, 0.1) var speed_ratio: float = 1.3

const SMALL: PackedScene = preload("res://addons/ngdc_pathfinding/spawner/walker.tscn")


func trait_name() -> String:
	return "分裂"


func labels() -> Dictionary:
	return {"count": "分成幾隻", "health_ratio": "小的血量 ×", "speed_ratio": "小的速度 ×"}


func apply() -> void:
	walker.died.connect(_on_died)


func _on_died(dead: Walker) -> void:
	var spawner: Spawner = dead.get_meta("spawner", null) as Spawner
	for i: int in count:
		var small: Walker = SMALL.instantiate()
		small.max_health = maxf(dead.max_health * health_ratio, 1.0)
		small.speed = dead.speed * speed_ratio
		small.radius = maxf(dead.radius * 0.65, 5.0)
		small.color = dead.color.lightened(0.2)
		small.score = 0                                           # 小的不給錢，不然分裂怪太好賺
		var at: Vector2 = dead.global_position + Vector2.from_angle(TAU * i / count) * 8.0
		if spawner != null and is_instance_valid(spawner):
			spawner.adopt(small, at)                              # 交給生怪器：走向基地、算進勝負
		else:
			dead.get_parent().add_child(small)
			small.global_position = at


func _draw() -> void:
	# 身上兩個小點：表示會分裂
	draw_circle(Vector2(-3, 0), 2.0, Color(1, 1, 1, 0.8))
	draw_circle(Vector2(3, 0), 2.0, Color(1, 1, 1, 0.8))
