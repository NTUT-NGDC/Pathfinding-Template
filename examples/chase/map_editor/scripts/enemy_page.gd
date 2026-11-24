class_name ChaseEnemyPage
extends ChaseKindPage
## 編輯器的「敵人」頁：改視野、速度、聽力、開關，勾特性，存成 features/enemies/ 裡的一般場景。


func _classes() -> Array[Dictionary]:
	return [ChaseKinds.with_base(ChaseMap.ENEMY)]


func _setup() -> void:
	super()
	form_columns = 2                                              # 欄位很多，特性才不會被擠到下面


## 視野自己畫：它的視野錐會畫在整個畫面的最上層，換頁、試玩時還在
func _preview_made(preview: Node2D) -> void:
	preview.set("show_cone", false)


func _preview_added(preview: Node2D) -> void:
	super(preview)
	var ai: ChaseAI = preview as ChaseAI
	if ai == null:
		return
	var wide: bool = ai.view_angle > 180.0 or not ai.check_angle
	preview_at = Vector2(140, 120) if wide or ai.view_distance <= 0.0 else Vector2(40, 120)
	preview_scale = minf((110.0 if wide else 225.0) / maxf(ai.view_distance, 1.0), 1.6)
	var cone: Node2D = Node2D.new()
	cone.show_behind_parent = true
	cone.draw.connect(func() -> void:
		var half: float = PI if not ai.check_angle else deg_to_rad(ai.view_angle) / 2.0
		var edge: PackedVector2Array = PackedVector2Array()
		for i: int in 33:
			edge.append(Vector2.from_angle(-half + half * 2.0 * i / 32.0) * ai.view_distance)
		VisionSensor.draw_fan(cone, Vector2.ZERO, edge, Color(1, 1, 1, 0.25)))
	preview.add_child(cone)


func _preview_text(preview: Node2D) -> String:
	var ai: ChaseAI = preview as ChaseAI
	if ai == null:
		return ""
	var player: Dictionary = ChaseMap.defaults_of(ChaseMap.PLAYER)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("看不到（%s）" % ("只靠聽的" if ai.has_hearing else "也聽不到，碰到才抓") if ai.view_distance <= 0.0 else "看 %d 格遠、%s" % [roundi(ai.view_distance / ChaseMap.CELL), "背後也看得到" if not ai.check_angle or ai.view_angle >= 360.0 else "左右各 %d 度" % int(ai.view_angle / 2.0)])
	lines.append("聽力　%s" % ("聽不到" if not ai.has_hearing else "%s 倍" % str(snappedf(ai.hearing_multiplier, 0.1))))
	lines.append("追擊　%d（玩家走 %d、跑 %d）" % [int(ai.chase_speed), int(player["walk_speed"]), int(player["run_speed"])])
	if ai.chase_speed >= float(player["run_speed"]):
		lines.append("比玩家跑步快：被看到只能躲")
	elif ai.chase_speed <= float(player["walk_speed"]):
		lines.append("比玩家走路慢：用走的就甩得掉")
	if ai.has_hearing and ai.chase_on_sound:
		lines.append("聽到就衝過來")
	lines.append("看到 %s 秒後開始追" % str(snappedf(ai.reaction_time, 0.1)).trim_suffix(".0"))
	return "\n".join(lines) + "\n\n存檔後，地圖上這一種全部跟著改"
