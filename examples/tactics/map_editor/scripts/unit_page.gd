class_name TacticsUnitPage
extends LevelEditorScenePage
## 編輯器的「棋子」頁：改棋子的數值、個性，勾特性，存成 features/units/ 裡的一般場景。
## 我方和敵方用同一種棋子。


func _setup() -> void:
	scenes = TacticsUnitInfo.scenes
	thing = "棋子"
	trait_title = "特性"
	fields = [
		LevelEditorForm.color("color", "顏色"),
		LevelEditorForm.text("mark", "身上的字", 1),
		LevelEditorForm.options("mind", "個性", Unit.MIND_NAMES, "電腦怎麼決定：衝鋒＝打最近的；守衛＝有人走進打得到的範圍才動；\n挑最弱的＝打血最少的；保持距離＝打得到就站最遠"),
		LevelEditorForm.number("max_health", "血量", 1, 200, 1, "滴"),
		LevelEditorForm.number("attack", "攻擊", 0, 50, 1, "", "扣血＝攻擊 － 對方的防禦，最少 1"),
		LevelEditorForm.number("defense", "防禦", 0, 50, 1),
		LevelEditorForm.number("move_points", "移動力", 0, 20, 1, "格", "沼澤一格算 3，森林、高地算 2"),
		LevelEditorForm.number("min_range", "最近射程", 1, 10, 1, "格", "2＝旁邊的打不到"),
		LevelEditorForm.number("max_range", "最遠射程", 1, 10, 1, "格"),
		LevelEditorForm.number("speed", "速度", 1, 30, 1, "", "每一輪從快到慢輪流動"),
	]


func _scene_saved(to: String) -> void:
	TacticsUnitInfo.forget_look(to)


func _preview_added(preview: Node2D) -> void:
	preview.remove_from_group("tactics_units")                    # 只是預覽，不要被當成場上的棋子
	preview.set("team", 0)


func _preview_text(preview: Node2D) -> String:
	return (preview as Unit).info_text() + "\n個性：" + Unit.MIND_NAMES[data["mind"]]
