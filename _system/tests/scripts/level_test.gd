extends Node
## 關卡的自動測試（用範例關卡和學員的關卡）：
## 1. 關卡載入沒有錯：有玩家、殺手、出口、任務；自動加了格子、HUD、視野圈、暫停選單
## 2. 任務：修理點按住 E 修好（會發出聲音）、鑰匙撿起來；HUD 進度跟著變
## 3. 出口：任務沒做完是關的（擋路）、全部做完才打開；走進去 → 逃出去、顯示通關時間
## 4. 只指定部分任務的出口
## 5. 被抓到 → 失敗
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/level_test.tscn

const LEVELS: Array[String] = ["res://example/levels/small_house.tscn", "res://my_level/my_level.tscn"]
const TIME_SCALE: float = 4.0

var _failures: int = 0
var _level: EscapeLevel


func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	for path: String in LEVELS:
		await _test_structure(path)
	await _test_tasks_and_exit()
	await _test_partial_exit()
	await _test_caught()
	Engine.time_scale = 1.0

	if _failures == 0:
		print("[關卡測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[關卡測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _test_structure(path: String) -> void:
	print("--- 關卡結構：%s ---" % path)
	await _load(path)
	_expect(_level != null, "關卡讀得到")
	_expect(get_tree().get_nodes_in_group("player").size() == 1, "有一個玩家")
	_expect(get_tree().get_nodes_in_group("killer").size() >= 1, "有殺手")
	_expect(get_tree().get_nodes_in_group("tasks").size() == 3, "有 3 個任務（2 修理＋1 鑰匙）")
	_expect(_find(Exit) != null, "有出口")
	_expect(get_tree().get_first_node_in_group("level_grid") != null, "自動建立尋路格子")
	_expect(_find(PlayerLight) != null, "自動建立玩家視野圈")
	_expect(_level.get_node_or_null("HUD") != null and _level.get_node_or_null("PauseMenu") != null, "自動建立 HUD、暫停選單")
	var killer: Killer = get_tree().get_first_node_in_group("killer")
	var patrol_count: int = killer.get_children().filter(func(n: Node) -> bool: return n is Marker2D).size()
	_expect(patrol_count >= 2, "殺手有巡邏點（%d 個）" % patrol_count)
	var grid: LevelGrid = get_tree().get_first_node_in_group("level_grid")
	var player: Player = get_tree().get_first_node_in_group("player")
	var exit: Exit = _find(Exit)
	for door: Node in get_tree().get_nodes_in_group("doors"):
		(door as Door).unlock((door as Door).key_color)          # 先當作鑰匙都拿到了
	var every_task_reachable: bool = true
	for task: Node in get_tree().get_nodes_in_group("tasks"):
		if not _ends_near(grid.find_path(player.global_position, (task as Node2D).global_position), (task as Node2D).global_position):
			every_task_reachable = false
	_expect(every_task_reachable, "從起點走得到每個任務（門都解鎖的話）")
	_expect(_ends_near(grid.find_path(player.global_position, exit.global_position - Vector2(0, 32)), exit.global_position - Vector2(0, 32)), "從起點走得到出口前面")
	await _frames(30)
	_expect(not _level.is_finished, "一開始不會馬上被抓")


func _test_tasks_and_exit() -> void:
	print("--- 任務與出口 ---")
	await _load(LEVELS[0])
	_disable_killers()
	var player: Player = get_tree().get_first_node_in_group("player")
	var exit: Exit = _find(Exit)
	var tasks_label: Label = _level.get_node("HUD").get_node("%Tasks")
	_expect(tasks_label.text.contains("修理 0/2") and tasks_label.text.contains("鑰匙 0/1"), "HUD：修理 0/2、鑰匙 0/1")
	_expect(not exit.is_open and exit.collision_layer != 0, "任務沒做完：出口關著、擋路")

	var sounds: Array[int] = [0]
	SoundBus.sound_emitted.connect(func(_p: Vector2, _r: float) -> void: sounds[0] += 1)
	var repairs: Array[RepairPoint] = []
	for node: Node in get_tree().get_nodes_in_group("tasks"):
		if node is RepairPoint:
			repairs.append(node)
	# 修理點：站在旁邊按住 E
	var repair: RepairPoint = repairs[0]
	player.global_position = repair.global_position + Vector2(0, 28)
	await _frames(3)
	Input.action_press("interact")
	await _frames(20)
	Input.action_release("interact")
	await _frames(2)
	_expect(repair.progress > 0.5 and not repair.is_done, "按住 E：修理有進度（%.1f 秒）" % repair.progress)
	_expect(sounds[0] > 0, "修理時發出聲音")
	var kept: float = repair.progress
	player.global_position = repair.global_position + Vector2(0, 200)
	await _frames(5)
	_expect(repair.progress == kept, "離開：保留進度")
	player.global_position = repair.global_position + Vector2(0, 28)
	await _frames(3)
	Input.action_press("interact")
	await _wait_until(func() -> bool: return repair.is_done, 200)
	Input.action_release("interact")
	_expect(repair.is_done, "修好了")
	await _frames(2)
	_expect(tasks_label.text.contains("修理 1/2"), "HUD：修理 1/2")

	repairs[1].complete()
	var key: KeyPickup = _find(KeyPickup)
	player.global_position = key.global_position + Vector2(20, 0)
	await _frames(3)
	await _press_interact()
	_expect(key.is_done and player.has_key("紅"), "撿起紅色鑰匙")
	await _frames(2)
	_expect(tasks_label.text.contains("鑰匙 1/1") and tasks_label.text.contains("出口打開了"), "HUD：全部完成、出口打開了")
	_expect(exit.is_open and exit.collision_layer == 0, "全部做完：出口打開")

	var cleared: Array[float] = [-1.0]
	_level.cleared.connect(func(seconds: float) -> void: cleared[0] = seconds)
	player.global_position = exit.global_position + Vector2(0, -20)
	Input.action_press("move_down")
	await _wait_until(func() -> bool: return cleared[0] >= 0.0, 120)
	Input.action_release("move_down")
	_expect(cleared[0] > 0.0, "走進出口：逃出去（%.1f 秒）" % cleared[0])
	var message: Control = _level.get_node("HUD").get_node("%Message")
	var detail: Label = _level.get_node("HUD").get_node("%MessageDetail")
	_expect(message.visible and detail.text.contains("通關時間"), "顯示通關時間（%s）" % detail.text)


func _test_partial_exit() -> void:
	print("--- 只指定部分任務的出口 ---")
	await _load(LEVELS[0], func(level: Node) -> void:
		var exit: Exit = level.get_node("Exit")
		exit.require_all_tasks = false
		exit.required_tasks = [level.get_node("Key") as Task])
	_disable_killers()
	var exit: Exit = _find(Exit)
	_expect(not exit.is_open, "鑰匙還沒撿：關著")
	(_find(KeyPickup) as Task).complete()
	_expect(exit.is_open, "只要求鑰匙：撿到就打開（修理點不用修）")


func _test_caught() -> void:
	print("--- 被抓 ---")
	await _load(LEVELS[0])
	var failed: Array[bool] = [false]
	_level.failed.connect(func() -> void: failed[0] = true)
	var player: Player = get_tree().get_first_node_in_group("player")
	var killer: Killer = get_tree().get_first_node_in_group("killer")
	player.global_position = killer.global_position + Vector2(8, 0)
	await _wait_until(func() -> bool: return failed[0], 30)
	_expect(failed[0] and player.is_finished, "碰到殺手：被抓、關卡失敗")
	var title: Label = _level.get_node("HUD").get_node("%MessageTitle")
	_expect(title.text.contains("被抓"), "顯示「被抓到了」")


# ---- 工具 ----

func _load(path: String, before_ready: Callable = Callable()) -> void:
	if _level != null:
		_level.queue_free()
		await _frames(2)
	_level = (load(path) as PackedScene).instantiate()
	if before_ready.is_valid():
		before_ready.call(_level)
	add_child(_level)
	await _frames(3)


func _disable_killers() -> void:
	for node: Node in get_tree().get_nodes_in_group("killer"):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		(node as Node2D).global_position = Vector2(-1000, -1000)


func _find(type: Variant) -> Node:
	for node: Node in _level.find_children("*", "", true, false):
		if is_instance_of(node, type):
			return node
	return null


func _ends_near(path: PackedVector2Array, target: Vector2) -> bool:
	return not path.is_empty() and path[path.size() - 1].distance_to(target) < 24.0


func _press_interact() -> void:
	await get_tree().physics_frame
	Input.action_press("interact")
	await get_tree().physics_frame
	Input.action_release("interact")
	await get_tree().physics_frame


func _wait_until(condition: Callable, max_frames: int) -> void:
	for i: int in max_frames:
		if condition.call():
			return
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
