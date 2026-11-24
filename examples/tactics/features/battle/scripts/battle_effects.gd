class_name BattleEffects
extends Node2D
## 戰鬥的動畫（只管好看，不影響規則）：撲過去、飛過去的線、跳數字、倒下淡出。

var battle: TacticsBattle


func _init(of: TacticsBattle) -> void:
	battle = of


func fall(unit: Unit) -> void:
	unit.create_tween().tween_property(unit, "modulate:a", 0.0, 0.3)


func lunge(unit: Unit, target: Unit) -> void:
	var home: Vector2 = unit.global_position
	var toward: Vector2 = home + home.direction_to(target.global_position) * 10.0
	if battle.distance(battle.cell_of(unit), battle.cell_of(target)) > 1:
		shot(home, target.global_position, Color("7ee08a") if target.team == unit.team else Color("ffe066"))
	var tween: Tween = create_tween()
	tween.tween_property(unit, "global_position", toward, 0.08)
	tween.tween_property(unit, "global_position", home, 0.12)
	await tween.finished


## 遠程：畫一條飛過去的線
func shot(from: Vector2, to: Vector2, color: Color) -> void:
	var line: Line2D = Line2D.new()
	line.width = 3.0
	line.default_color = color
	line.z_index = 5
	add_child(line)
	line.points = PackedVector2Array([to_local(from), to_local(to)])
	var tween: Tween = create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.25)
	tween.tween_callback(line.queue_free)


func pop(unit: Unit, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.z_index = 20
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	label.global_position = unit.global_position + Vector2(-16, -44)
	var tween: Tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 18.0, 0.5)
	tween.tween_callback(label.queue_free)
