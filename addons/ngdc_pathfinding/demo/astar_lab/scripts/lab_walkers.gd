extends Control
## A* 實驗室：讓 NPC（小圓點）照找到的路走一次，看實際要花幾秒。可以同時放好幾隻比賽。
## 一般的格子走 0.15 秒，沼澤再乘上沼澤的成本（斜走 1.41 倍），所以時間＝總成本 × 0.15 秒。

## 有一隻到終點了
signal arrived(index: int)
## 全部都到了
signal all_arrived

const SECONDS_PER_CELL: float = 0.15
const RADIUS: float = 9.0
const COLORS: Array[Color] = [Color("2a7fd4"), Color("9a3fd1"), Color("e8720c")]

var cell_size: float = 36.0
## 每隻 NPC 照哪一次找路的結果走（走不到的不會出發）
var searches: Array[GridSearch] = []
## 出發到現在幾秒
var elapsed: float = 0.0
var running: bool = false

var _arrived: Array[bool] = []


func start(new_searches: Array[GridSearch]) -> void:
	searches = new_searches
	elapsed = 0.0
	running = true
	_arrived.clear()
	for search: GridSearch in searches:
		_arrived.append(not search.found)
	queue_redraw()


func stop() -> void:
	searches = []
	running = false
	queue_redraw()


## 走完要幾秒
func time_of(index: int) -> float:
	return searches[index].path_length() * SECONDS_PER_CELL


func has_arrived(index: int) -> bool:
	return searches[index].found and _arrived[index]


func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	for i: int in searches.size():
		if not _arrived[i] and elapsed >= time_of(i):
			_arrived[i] = true
			arrived.emit(i)
	if not _arrived.has(false):
		running = false
		all_arrived.emit()
	queue_redraw()


func _draw() -> void:
	for i: int in searches.size():
		if not searches[i].found:
			continue
		if searches.size() > 1:
			var points: PackedVector2Array = PackedVector2Array()
			for cell: Vector2i in searches[i].path:
				points.append(_center(cell, i))
			if points.size() >= 2:
				draw_polyline(points, Color(COLORS[i], 0.6), 4.0)
	for i: int in searches.size():
		if searches[i].found:
			var at: Vector2 = _walker_position(i)
			draw_circle(at, RADIUS + 2.0, Color.WHITE)
			draw_circle(at, RADIUS, COLORS[i])


## 現在走到哪裡：照每一步要花的時間往前推
func _walker_position(index: int) -> Vector2:
	var search: GridSearch = searches[index]
	var left: float = elapsed
	for i: int in range(1, search.path.size()):
		var seconds: float = search.step_cost(search.path[i - 1], search.path[i]) * SECONDS_PER_CELL
		if left < seconds:
			return _center(search.path[i - 1], index).lerp(_center(search.path[i], index), left / seconds)
		left -= seconds
	return _center(search.path[search.path.size() - 1], index)


## 格子中心；好幾隻的時候錯開一點，走同一條路才看得到每一隻
func _center(cell: Vector2i, index: int) -> Vector2:
	var offset: float = (index - (searches.size() - 1) / 2.0) * 7.0
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size + Vector2(offset, offset)
