extends Node
## A* 實驗室的自動測試：
## 1. 每張內建地圖都找得到路，BFS／權重 0／權重 1 找到的路一樣短
## 2. U 形牆（手冊的實驗）：權重 1 探索的格子比權重 0 少，路一樣長
## 3. 投影片 7：權重 5 探索最少，但路比較長
## 4. 斜走：路比較短；不能穿牆角時不會貼著牆角斜切
## 5. 走不到的地圖：結束、沒有路
## 6. 沼澤：BFS 只算步數、直直穿過沼澤；A* 算成本、繞開沼澤，總成本比較低
## 7. 陷阱：權重 5 探索最少、路比權重 0 和 1 長；沼澤：權重 5 直穿沼澤、總成本比較高
## 8. 平手先挑 h 小的、待探索不重複、下一格跟 step() 真的探索的一樣
## 9. 實驗室場景打得開、按鈕按了不會當掉；沼澤成本、每格的算式、存讀地圖
## 10. 走走看：秒數＝總成本 × 0.15；比賽：陷阱、沼澤的權重 5 最慢，0 和 1 並列；紀錄表、清空
##
## 在命令列執行：
##   godot --headless --path . res://addons/ngdc_pathfinding/tests/astar_lab_test.tscn

const ScriptErrors = preload("res://core/tests/scripts/script_error_counter.gd")
const LAB_SCENE: PackedScene = preload("res://addons/ngdc_pathfinding/demo/astar_lab/astar_lab.tscn")

var _failures: int = 0
## 腳本錯誤也算失敗（會讓測試函式中斷、跑不到 _expect）
var _script_errors: ScriptErrors = ScriptErrors.new()


func _ready() -> void:
	_print_table()
	_test_presets()
	_test_u_wall()
	_test_slide_7()
	_test_diagonal()
	_test_no_path()
	_test_swamp()
	_test_trap()
	_test_order()
	await _test_scene()

	_failures += _script_errors.report()
	if _failures == 0:
		print("[A* 實驗室測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[A* 實驗室測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


## 印出每張地圖、每種設定的探索格數和路徑長度（調地圖時參考）
func _print_table() -> void:
	print("--- 探索格數／路徑長度 ---")
	for map_name: String in AStarPresets.MAPS:
		for diagonal: bool in [false, true]:
			var line: String = "  %s%s：" % [map_name, "（斜走）" if diagonal else ""]
			line += "BFS %s　" % _describe(_run(map_name, GridSearch.Algorithm.BFS, 1.0, diagonal))
			for w: float in [0.0, 1.0, 5.0]:
				line += "w%s %s　" % [w, _describe(_run(map_name, GridSearch.Algorithm.ASTAR, w, diagonal))]
			print(line)


func _test_presets() -> void:
	print("--- 每張地圖都找得到最短路 ---")
	for map_name: String in AStarPresets.MAPS:
		var bfs: GridSearch = _run(map_name, GridSearch.Algorithm.BFS, 1.0, false)
		var w0: GridSearch = _run(map_name, GridSearch.Algorithm.ASTAR, 0.0, false)
		var w1: GridSearch = _run(map_name, GridSearch.Algorithm.ASTAR, 1.0, false)
		_expect(bfs.found and w0.found and w1.found, "%s：找得到路" % map_name)
		if bfs.costs.is_empty():
			_expect(is_equal_approx(bfs.path_length(), w1.path_length()) and is_equal_approx(w0.path_length(), w1.path_length()), "%s：BFS、權重 0、權重 1 的路一樣短" % map_name)
		else:
			_expect(is_equal_approx(w0.path_length(), w1.path_length()), "%s：權重 0、權重 1 的成本一樣（BFS 不管成本，另外測）" % map_name)
		_expect(bfs.path[0] == bfs.start_cell and bfs.path[bfs.path.size() - 1] == bfs.goal_cell, "%s：路從起點到終點" % map_name)


func _test_u_wall() -> void:
	print("--- U 形牆 ---")
	var w0: GridSearch = _run("U 形牆", GridSearch.Algorithm.ASTAR, 0.0, false)
	var w1: GridSearch = _run("U 形牆", GridSearch.Algorithm.ASTAR, 1.0, false)
	var w5: GridSearch = _run("U 形牆", GridSearch.Algorithm.ASTAR, 5.0, false)
	_expect(w1.closed.size() < w0.closed.size(), "權重 1 探索比權重 0 少（%d < %d）" % [w1.closed.size(), w0.closed.size()])
	_expect(w5.closed.size() <= w1.closed.size(), "權重 5 探索最少（%d）" % w5.closed.size())


func _test_slide_7() -> void:
	print("--- 投影片 7 ---")
	var w0: GridSearch = _run("投影片 7", GridSearch.Algorithm.ASTAR, 0.0, false)
	var w1: GridSearch = _run("投影片 7", GridSearch.Algorithm.ASTAR, 1.0, false)
	var w5: GridSearch = _run("投影片 7", GridSearch.Algorithm.ASTAR, 5.0, false)
	_expect(w0.closed.size() > w1.closed.size() and w1.closed.size() > w5.closed.size(), "探索格數：權重 0 ＞ 1 ＞ 5（%d、%d、%d）" % [w0.closed.size(), w1.closed.size(), w5.closed.size()])
	_expect(is_equal_approx(w0.path_length(), w1.path_length()), "權重 0、1 的路一樣短（%.0f）" % w1.path_length())
	_expect(w5.path_length() > w1.path_length(), "權重 5 的路比較長（%.0f ＞ %.0f）" % [w5.path_length(), w1.path_length()])


func _test_diagonal() -> void:
	print("--- 斜走 ---")
	var straight: GridSearch = _run("U 形牆", GridSearch.Algorithm.ASTAR, 1.0, false)
	var diagonal: GridSearch = _run("U 形牆", GridSearch.Algorithm.ASTAR, 1.0, true)
	_expect(diagonal.path_length() < straight.path_length(), "可以斜走：路比較短（%.1f ＜ %.0f）" % [diagonal.path_length(), straight.path_length()])
	var search: GridSearch = GridSearch.new()
	AStarPresets.apply(["S#..", ".#..", "...G"], search)
	search.allow_diagonal = true
	_expect(not search.neighbors(Vector2i(0, 0)).has(Vector2i(1, 1)), "斜走的目標是牆：不能走")
	_expect(not search.neighbors(Vector2i(0, 2)).has(Vector2i(1, 1)), "斜走的目標是牆：不能走（往上）")
	AStarPresets.apply(["S...", "##.#", "...G"], search)
	search.allow_diagonal = true
	search.cut_corners = false
	_expect(not search.neighbors(Vector2i(3, 0)).has(Vector2i(2, 1)), "不能穿牆角：(3,0) 不能斜到 (2,1)")
	search.cut_corners = true
	_expect(search.neighbors(Vector2i(3, 0)).has(Vector2i(2, 1)), "可以穿牆角：(3,0) 可以斜到 (2,1)")


func _test_no_path() -> void:
	print("--- 走不到 ---")
	var search: GridSearch = GridSearch.new()
	AStarPresets.apply(["S.#..", "..#.G", "..#.."], search)
	for algorithm: GridSearch.Algorithm in [GridSearch.Algorithm.BFS, GridSearch.Algorithm.ASTAR]:
		search.algorithm = algorithm
		search.start()
		var steps: int = 0
		while not search.finished and steps < 1000:
			search.step()
			steps += 1
		_expect(search.finished and not search.found and search.path.is_empty(), "%s：找完了、沒有路" % ["BFS", "A*"][algorithm])


func _test_swamp() -> void:
	print("--- 沼澤 ---")
	var bfs: GridSearch = _run("沼澤", GridSearch.Algorithm.BFS, 1.0, false)
	var astar: GridSearch = _run("沼澤", GridSearch.Algorithm.ASTAR, 1.0, false)
	var dijkstra: GridSearch = _run("沼澤", GridSearch.Algorithm.ASTAR, 0.0, false)
	var bfs_swamp: int = bfs.path.filter(func(c: Vector2i) -> bool: return bfs.costs.has(c)).size()
	var astar_swamp: int = astar.path.filter(func(c: Vector2i) -> bool: return astar.costs.has(c)).size()
	_expect(bfs_swamp > 0, "BFS 不管成本：直直穿過沼澤（踩了 %d 格）" % bfs_swamp)
	_expect(astar_swamp == 0, "A* 算成本：繞開沼澤")
	_expect(astar.path_length() < bfs.path_length(), "A* 的總成本比較低（%.0f ＜ %.0f）" % [astar.path_length(), bfs.path_length()])
	_expect(is_equal_approx(astar.path_length(), dijkstra.path_length()), "權重 0（Dijkstra）和 A* 成本一樣")
	var greedy: GridSearch = _run("沼澤", GridSearch.Algorithm.ASTAR, 5.0, false)
	_expect(greedy.path.any(func(c: Vector2i) -> bool: return greedy.costs.has(c)), "權重 5 直直穿過沼澤")
	_expect(greedy.path_steps() < astar.path_steps() and greedy.path_length() > astar.path_length(), "權重 5 走的格子少（%d ＜ %d）、總成本高（%.0f ＞ %.0f）" % [greedy.path_steps(), astar.path_steps(), greedy.path_length(), astar.path_length()])


func _test_trap() -> void:
	print("--- 陷阱 ---")
	var w0: GridSearch = _run("陷阱", GridSearch.Algorithm.ASTAR, 0.0, false)
	var w1: GridSearch = _run("陷阱", GridSearch.Algorithm.ASTAR, 1.0, false)
	var w5: GridSearch = _run("陷阱", GridSearch.Algorithm.ASTAR, 5.0, false)
	_expect(w5.closed.size() < w1.closed.size() and w1.closed.size() < w0.closed.size(), "探索格數：權重 0 ＞ 1 ＞ 5（%d、%d、%d）" % [w0.closed.size(), w1.closed.size(), w5.closed.size()])
	_expect(w5.path_steps() > w1.path_steps() and w0.path_steps() == w1.path_steps(), "權重 5 的路比較長（%d ＞ %d）" % [w5.path_steps(), w1.path_steps()])


func _test_order() -> void:
	print("--- 先挑哪一格 ---")
	var search: GridSearch = GridSearch.new()
	AStarPresets.apply(["S....", ".....", "....G"], search)
	search.start()
	search.step()
	search.step()
	_expect(search.estimate(search.peek_next()) == 4.0, "平手（總分都是 6）：先挑 h 小的（h＝%.0f）" % search.estimate(search.peek_next()))
	var same: bool = true
	var unique: bool = true
	for map_name: String in AStarPresets.MAPS:
		for w: float in [0.0, 1.0, 5.0]:
			AStarPresets.apply(AStarPresets.MAPS[map_name], search)
			search.weight = w
			search.start()
			while not search.finished:
				var next: Vector2i = search.peek_next()
				search.step()
				same = same and search.closed.has(next)
				for cell: Vector2i in search.open:
					unique = unique and search.open.count(cell) == 1 and not search.closed.has(cell)
			same = same and search.closed.size() > 0 and search.peek_next() == Vector2i(-1, -1)
	_expect(same, "peek_next() 就是下一步探索的格子，找完是 (-1, -1)")
	_expect(unique, "待探索的格子不重複，也不會有已探索的")


func _test_scene() -> void:
	print("--- 實驗室場景 ---")
	var lab: Control = LAB_SCENE.instantiate()
	add_child(lab)
	await get_tree().process_frame
	var presets: OptionButton = lab.get_node("%PresetOption")
	_expect(presets.item_count == AStarPresets.MAPS.size(), "預設地圖選單有 %d 張" % presets.item_count)
	presets.select(1)
	presets.item_selected.emit(1)
	(lab.get_node("%AlgorithmOption") as OptionButton).select(1)
	(lab.get_node("%AlgorithmOption") as OptionButton).item_selected.emit(1)
	for i: int in 400:
		(lab.get_node("%StepButton") as Button).pressed.emit()
	await _test_walk(lab)
	presets.select(1)
	presets.item_selected.emit(1)
	for i: int in 400:
		(lab.get_node("%StepButton") as Button).pressed.emit()
	var stats: Label = lab.get_node("%Stats")
	_expect(stats.text.contains("探索了") and stats.text.contains("路徑長度"), "顯示探索格數和路徑長度（%s）" % stats.text.replace("\n", "／"))
	await _test_cell_info(lab)
	(lab.get_node("%ScoresOption") as OptionButton).select(2)
	(lab.get_node("%ArrowsCheck") as CheckBox).button_pressed = true
	(lab.get_node("%DiagonalCheck") as CheckBox).button_pressed = true
	(lab.get_node("%WeightSlider") as HSlider).value = 5.0
	(lab.get_node("%ResetButton") as Button).pressed.emit()
	(lab.get_node("%PlayButton") as Button).button_pressed = true
	await get_tree().create_timer(0.3).timeout
	_expect(true, "改設定、自動播放不會當掉")

	var search: GridSearch = lab.get("search")
	search.walls[Vector2i(5, 5)] = true
	search.costs[Vector2i(6, 6)] = 3.0
	(lab.get_node("%SwampSlider") as HSlider).value = 7.0
	_expect(search.costs[Vector2i(6, 6)] == 7.0, "沼澤成本滑桿：地圖上的沼澤跟著變")
	(lab.get_node("%SaveButton") as Button).pressed.emit()
	search.walls.clear()
	(lab.get_node("%SwampSlider") as HSlider).value = 2.0
	(lab.get_node("%LoadButton") as Button).pressed.emit()
	search = lab.get("search")
	_expect(search.walls.has(Vector2i(5, 5)) and search.costs.has(Vector2i(6, 6)), "存檔再讀檔：牆和沼澤都還在")
	_expect(search.costs[Vector2i(6, 6)] == 7.0 and (lab.get_node("%SwampSlider") as HSlider).value == 7.0, "存檔再讀檔：沼澤成本也還在")
	lab.queue_free()


func _test_walk(lab: Control) -> void:
	var walkers: Control = lab.get_node("%Walkers")
	var label: Label = lab.get_node("%WalkLabel")
	var presets: OptionButton = lab.get_node("%PresetOption")
	var weight: HSlider = lab.get_node("%WeightSlider")
	var records: Array = lab.get("_records")
	_expect(records.size() == 1 and records[0][0] == "U 形牆" and records[0][7] == "－", "找完自動記一列，秒數先空著")
	(lab.get_node("%WalkButton") as Button).pressed.emit()
	await get_tree().create_timer(1.0).timeout
	_expect(walkers.running and label.text.contains("走路中"), "走走看：出發、計時（%s）" % label.text)
	await walkers.all_arrived
	_expect(label.text.contains("花了 3.75 秒") and absf(walkers.elapsed - 3.75) < 0.1, "U 形牆：花 3.75 秒（25 × 0.15，實際 %.2f）" % walkers.elapsed)
	_expect(records.size() == 1 and records[0][7] == "3.75", "走完把秒數填進同一列")

	for map_name: String in ["陷阱", "沼澤"]:
		var index: int = AStarPresets.MAPS.keys().find(map_name)
		presets.select(index)
		presets.item_selected.emit(index)
		(lab.get_node("%RaceButton") as Button).pressed.emit()
		await walkers.all_arrived
		_expect(is_equal_approx(walkers.time_of(0), walkers.time_of(1)) and walkers.time_of(2) > walkers.time_of(1), "比賽「%s」：權重 5 最慢（%.2f、%.2f、%.2f 秒）" % [map_name, walkers.time_of(0), walkers.time_of(1), walkers.time_of(2)])
		var cells: PackedStringArray = []
		for child: Label in (lab.get_node("%Ranking") as GridContainer).get_children():
			cells.append(child.text)
		_expect(cells.size() == 24 and cells[6] == "1" and cells[12] == "1" and cells[18] == "3" and cells[19] == "5", "排行：0 和 1 並列第 1、5 第 3（%s）" % " ".join(cells.slice(6)))
	_expect(records.size() == 7 and records[6][0] == "沼澤" and records[6][3] == "3", "比賽的三隻都記下來（共 %d 列）" % records.size())

	weight.value = 2.0
	_expect(walkers.searches.is_empty() and label.text == "", "改設定：NPC 收起來")
	weight.value = 1.0
	var search: GridSearch = lab.get("search")
	for y: int in search.size.y:
		search.walls[Vector2i(12, y)] = true
	(lab.get_node("%WalkButton") as Button).pressed.emit()
	_expect(not walkers.running and label.text.contains("走不到"), "走不到：NPC 不出發")
	(lab.get_node("%RaceButton") as Button).pressed.emit()
	_expect(not walkers.running and label.text.contains("走不到"), "走不到：比賽不開始")
	(lab.get_node("%RecordButton") as Button).pressed.emit()
	_expect((lab.get_node("%RecordPanel") as Control).visible, "打得開紀錄表")
	(lab.get_node("%RecordClearButton") as Button).pressed.emit()
	(lab.get_node("%RecordCloseButton") as Button).pressed.emit()
	_expect(records.is_empty() and not (lab.get_node("%RecordPanel") as Control).visible, "清空、關閉紀錄表")


## 滑鼠停在格子上：算式對得起來
func _test_cell_info(lab: Control) -> void:
	var search: GridSearch = lab.get("search")
	var view: Control = lab.get_node("%GridView")
	var info: Label = lab.get_node("%CellInfo")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	var cell: Vector2i = search.path[3]
	motion.position = Vector2(cell * 36) + Vector2(18, 18)
	view.gui_input.emit(motion)
	_expect(info.text.contains("總分 17＝3＋1×14") and info.text.contains("路徑") and info.text.contains("從 (%d, %d) 走過來" % [search.path[2].x, search.path[2].y]), "路徑上的格子：算式、狀態、從哪來（%s）" % info.text.replace("\n", "／"))
	motion.position = Vector2(14 * 36 + 18, 7 * 36 + 18)
	view.gui_input.emit(motion)
	_expect(info.text.contains("牆"), "牆：寫不能走")
	var algorithm: OptionButton = lab.get_node("%AlgorithmOption")
	algorithm.select(0)
	algorithm.item_selected.emit(0)
	motion.position = Vector2(search.start_cell * 36) + Vector2(18, 18)
	view.gui_input.emit(motion)
	_expect(info.text.contains("BFS 不算分數"), "BFS：不寫算式")
	algorithm.select(1)
	algorithm.item_selected.emit(1)
	view.mouse_exited.emit()
	_expect(info.text.contains("滑鼠停在格子上"), "滑鼠離開：回到說明")
	await get_tree().process_frame


func _run(map_name: String, algorithm: GridSearch.Algorithm, weight: float, diagonal: bool) -> GridSearch:
	var search: GridSearch = GridSearch.new()
	AStarPresets.apply(AStarPresets.MAPS[map_name], search)
	search.algorithm = algorithm
	search.weight = weight
	search.allow_diagonal = diagonal
	search.start()
	var steps: int = 0
	while not search.finished and steps < 10000:
		search.step()
		steps += 1
	return search


func _describe(search: GridSearch) -> String:
	return "%d格/%.1f" % [search.closed.size(), search.path_length()] if search.found else "%d格/走不到" % search.closed.size()


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
