extends Node2D
## 除錯圖層：畫聲音圈圈（按 4）和格子線（按 5）。殺手的視野錐、路徑、狀態由殺手自己畫。
## 關卡（EscapeLevel）會自動建立，放在玩家視野圈的上面，暗的地方也看得到。

## 聲音圈圈擴散多久（秒）
const SOUND_LIFETIME: float = 0.6

var grid: LevelGrid
## [位置, 半徑, 已經過幾秒]
var _sounds: Array[Array] = []


func _ready() -> void:
	SoundBus.sound_emitted.connect(func(at: Vector2, radius: float) -> void: _sounds.append([at, radius, 0.0]))
	DebugView.changed.connect(queue_redraw)


func _process(delta: float) -> void:
	for sound: Array in _sounds:
		sound[2] += delta
	_sounds = _sounds.filter(func(sound: Array) -> bool: return sound[2] < SOUND_LIFETIME)
	if DebugView.show_sounds or DebugView.show_grid:
		queue_redraw()


func _draw() -> void:
	if DebugView.show_grid and grid != null:
		_draw_grid()
	if DebugView.show_sounds:
		for sound: Array in _sounds:
			var t: float = sound[2] / SOUND_LIFETIME
			draw_arc(sound[0], sound[1] * t, 0.0, TAU, 64, Color(1, 1, 0.4, 1.0 - t), 2.0)


## 格子線：不能走的格子塗紅，關著的門塗黃
func _draw_grid() -> void:
	var region: Rect2i = grid.astar.region
	var size: Vector2 = grid.astar.cell_size
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var cell: Vector2i = Vector2i(x, y)
			var rect: Rect2 = Rect2(grid.cell_center(cell) - size / 2.0, size)
			if grid.astar.is_point_solid(cell):
				draw_rect(rect, Color(1, 0.2, 0.2, 0.25))
			elif grid.astar.get_point_weight_scale(cell) > 1.0:
				draw_rect(rect, Color(1, 0.85, 0.2, 0.3))
			draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)
