extends Node
## 開發用：打開一個關卡，過幾秒自動截圖（看整體畫面用，匯出時排除）。
##   godot --path . res://_system/sandbox/level_preview.tscn -- level=res://my_level/my_level.tscn wait=3 debug=2345 out=level.png nolight killers=3
## debug 是要打開的除錯顯示（數字鍵）；nolight 關掉玩家視野圈；killers=3 把殺手複製成 3 隻（量效能）。
## 截圖存在 user://，結束前印出平均 fps。

func _ready() -> void:
	var args: Dictionary[String, String] = {}
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	var level: Node = (load(args.get("level", "res://example/levels/small_house.tscn")) as PackedScene).instantiate()
	if args.has("nolight"):
		level.set("player_light", false)
	var killer: Node2D = level.get_node_or_null("Killer")
	if killer != null:
		for i: int in int(args.get("killers", "1")) - 1:
			var copy: Node2D = killer.duplicate()
			copy.position += Vector2(64 * (i + 1), 0)
			level.add_child(copy)
	add_child(level)
	await get_tree().process_frame
	var flags: String = args.get("debug", "")
	DebugView.show_paths = flags.contains("2")
	DebugView.show_states = flags.contains("3")
	DebugView.show_sounds = flags.contains("4")
	DebugView.show_grid = flags.contains("5")
	if flags.contains("1"):
		DebugView.show_cones = not DebugView.show_cones
	DebugView.changed.emit()
	var frames_before: int = Engine.get_frames_drawn()
	var time_before: int = Time.get_ticks_msec()
	await get_tree().create_timer(float(args.get("wait", "3"))).timeout
	print("平均 fps：%.0f（殺手 %d 隻）" % [(Engine.get_frames_drawn() - frames_before) * 1000.0 / (Time.get_ticks_msec() - time_before), get_tree().get_nodes_in_group("killer").size()])
	var out: String = "user://" + args.get("out", "level_preview.png")
	get_viewport().get_texture().get_image().save_png(out)
	print("截圖：", ProjectSettings.globalize_path(out))
	get_tree().quit()
