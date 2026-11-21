class_name GridSearch
extends RefCounted
## 自己寫的 BFS／A*，一次只往外找一步，A* 實驗室才能一格一格播出來。
##
## 為什麼不用 Godot 內建的 AStarGrid2D？因為它一次就把整條路算完，
## 看不到中間「先找哪一格、找了哪些格」的過程。殺手在遊戲裡用的是內建的（比較快）。
##
## 用法：設定好地圖和選項 → start() → 一直呼叫 step() 直到 finished → 讀 path

enum Algorithm { BFS, ASTAR }

const DIAGONAL_COST: float = 1.41421356
const STRAIGHT: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAGONAL: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

# ---- 設定 ----
var size: Vector2i = Vector2i(24, 16)
## 牆：Dictionary 當集合用，有這個 key 就是牆
var walls: Dictionary[Vector2i, bool] = {}
var start_cell: Vector2i
var goal_cell: Vector2i
var algorithm: Algorithm = Algorithm.ASTAR
## 估計權重：0＝只看走了多少（像 Dijkstra）、1＝標準 A*、越大越只看「估計還剩多少」（接近 Greedy）
var weight: float = 1.0
var allow_diagonal: bool = false
## 斜走時可以貼著牆角切過去
var cut_corners: bool = false

# ---- 過程 ----
## 待探索的格子（BFS 是排隊，A* 每次挑分數最低的）
var open: Array[Vector2i] = []
## 已探索的格子
var closed: Dictionary[Vector2i, bool] = {}
## 從起點走到這格的距離（走了多少）
var g: Dictionary[Vector2i, float] = {}
## 這格是從哪一格走過來的（找到終點後沿著它倒回去就是路）
var came_from: Dictionary[Vector2i, Vector2i] = {}
var finished: bool = false
var found: bool = false
var path: Array[Vector2i] = []


## 從頭開始：起點放進待探索
func start() -> void:
	open = [start_cell]
	closed.clear()
	g = {start_cell: 0.0}
	came_from.clear()
	finished = false
	found = false
	path.clear()


## 往外找一步：拿出一格 → 是終點就結束 → 不是就把旁邊的格子加進待探索
func step() -> void:
	if finished:
		return
	if open.is_empty():
		finished = true                                           # 沒有格子可以找了：走不到
		return
	var current: Vector2i = _take_next()                          # BFS 拿最早排隊的；A* 拿分數最低的
	if closed.has(current):
		return                                                    # 已經找過了（A* 可能重複加進來）
	closed[current] = true
	if current == goal_cell:
		finished = true                                           # 找到終點了！
		found = true
		path = _trace_back(current)
		return
	for next: Vector2i in neighbors(current):
		var new_g: float = g[current] + _step_cost(current, next)
		if algorithm == Algorithm.BFS:
			if g.has(next):
				continue                                          # BFS：水已經流過的格子不再流
		elif g.has(next) and new_g >= g[next]:
			continue                                              # A*：這條路沒有比較近，不用更新
		g[next] = new_g
		came_from[next] = current                                 # 記住是從哪一格走過來的
		open.append(next)


## 每一格的分數＝走了多少＋估計還剩多少 × 權重（BFS 不用分數）
func score(cell: Vector2i) -> float:
	return g.get(cell, 0.0) + weight * estimate(cell)


## 估計離終點還有多遠：不管牆，直接量距離
func estimate(cell: Vector2i) -> float:
	var d: Vector2i = (goal_cell - cell).abs()
	if not allow_diagonal:
		return d.x + d.y                                          # 只能直走：橫的＋直的
	return maxi(d.x, d.y) - mini(d.x, d.y) + DIAGONAL_COST * mini(d.x, d.y)   # 能斜走：先斜再直


func _take_next() -> Vector2i:
	if algorithm == Algorithm.BFS:
		return open.pop_front()                                   # BFS：先來先找（水一圈一圈擴散）
	var best: int = 0
	for i: int in range(1, open.size()):
		if score(open[i]) < score(open[best]):
			best = i
	var cell: Vector2i = open[best]
	open.remove_at(best)
	return cell


## 旁邊可以走的格子
func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d: Vector2i in STRAIGHT:
		if is_free(cell + d):
			result.append(cell + d)
	if allow_diagonal:
		for d: Vector2i in DIAGONAL:
			if not is_free(cell + d):
				continue
			var corner_free: bool = is_free(cell + Vector2i(d.x, 0)) and is_free(cell + Vector2i(0, d.y))
			if cut_corners or corner_free:
				result.append(cell + d)
	return result


func is_free(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y and not walls.has(cell)


## 路徑長度（斜走一步算 1.41）
func path_length() -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += _step_cost(path[i - 1], path[i])
	return total


func _step_cost(a: Vector2i, b: Vector2i) -> float:
	return DIAGONAL_COST if a.x != b.x and a.y != b.y else 1.0


func _trace_back(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [cell]
	while came_from.has(cell):
		cell = came_from[cell]
		result.push_front(cell)
	return result
