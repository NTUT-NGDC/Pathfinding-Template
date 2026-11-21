extends Node
## A* 實驗室的自動測試：
## 1. 每張內建地圖都找得到路，BFS／權重 0／權重 1 找到的路一樣短
## 2. U 形牆（手冊的實驗）：權重 1 探索的格子比權重 0 少，路一樣長
## 3. 投影片 7：權重 5 探索最少，但路比較長
## 4. 斜走：路比較短；不能穿牆角時不會貼著牆角斜切
## 5. 走不到的地圖：結束、沒有路
## 6. 實驗室場景打得開、按鈕按了不會當掉；存讀地圖
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/astar_lab_test.tscn

const LAB_SCENE: PackedScene = preload("res://lesson/astar_lab/astar_lab.tscn")

var _failures: int = 0


func _ready() -> void:
	_print_table()
	_test_presets()
	_test_u_wall()
	_test_slide_7()
	_test_diagonal()
	_test_no_path()
	await _test_scene()

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
		_expect(is_equal_approx(bfs.path_length(), w1.path_length()) and is_equal_approx(w0.path_length(), w1.path_length()), "%s：BFS、權重 0、權重 1 的路一樣短" % map_name)
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
	var stats: Label = lab.get_node("%Stats")
	_expect(stats.text.contains("探索了") and stats.text.contains("路徑長度"), "顯示探索格數和路徑長度（%s）" % stats.text.replace("\n", "／"))
	(lab.get_node("%ScoresCheck") as CheckBox).button_pressed = true
	(lab.get_node("%DiagonalCheck") as CheckBox).button_pressed = true
	(lab.get_node("%WeightSlider") as HSlider).value = 5.0
	(lab.get_node("%ResetButton") as Button).pressed.emit()
	(lab.get_node("%PlayButton") as Button).button_pressed = true
	await get_tree().create_timer(0.3).timeout
	_expect(true, "改設定、自動播放不會當掉")

	var search: GridSearch = lab.get("search")
	search.walls[Vector2i(5, 5)] = true
	(lab.get_node("%SaveButton") as Button).pressed.emit()
	search.walls.clear()
	(lab.get_node("%LoadButton") as Button).pressed.emit()
	search = lab.get("search")
	_expect(search.walls.has(Vector2i(5, 5)), "存檔再讀檔：牆還在")
	lab.queue_free()


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
