@tool
class_name TraitFlying
extends EnemyTrait
## 會飛：不尋路，直線飛向基地，牆和塔都擋不住。拿來對比「會尋路的怪」。


func apply() -> void:
	var follower: PathFollower = walker.get_node_or_null("PathFollower") as PathFollower
	if follower != null:
		follower.use_pathfinding = false
	walker.z_index += 2                                           # 飛在牆和塔上面


func _draw() -> void:
	# 兩片翅膀
	var r: float = walker.radius if walker != null else 10.0
	for side: float in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, side * (r - 2.0)), Vector2(-6, side * (r + 8.0)), Vector2(6, side * (r + 6.0))]),
			Color(1, 1, 1, 0.75))
