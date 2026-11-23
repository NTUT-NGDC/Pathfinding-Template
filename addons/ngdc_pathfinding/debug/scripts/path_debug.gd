class_name PathDebug
extends Node2D
## 除錯顯示：遊戲中按 F1～F5 切換。不用放進場景，尋路地圖建好時會自動出現。
##   F1 視野錐　F2 路徑　F3 追逐 AI 的狀態文字　F4 聲音圈圈　F5 格子線（擋路紅色、成本高黃色）
## 程式裡也可以直接改：PathDebug.show_paths = true
## 視野錐要不要一開始就顯示，看 VisionSensor 的「顯示視野錐」。

## F1：視野錐（VisionSensor 讀這個）
static var show_cones: bool = true
## F2：路徑
static var show_paths: bool = false
## F3：追逐 AI 的狀態文字
static var show_states: bool = false
## F4：聲音圈圈
static var show_sounds: bool = false
## F5：格子線
static var show_grid: bool = false

## 聲音圈圈擴散多久（秒）
const SOUND_LIFETIME: float = 0.6
const KEYS: Array[int] = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5]

static var _instance: PathDebug

var _grid: PathGrid
## [位置, 半徑, 已經過幾秒]
var _sounds: Array[Array] = []


## 尋路地圖建好時呼叫：之後按 F5 會畫這張地圖的格子
static func watch_grid(grid: PathGrid) -> void:
	instance()._grid = grid


## 全場共用的那一個（第一次用到時自動建立，畫在最上層，暗的地方也看得到）
static func instance() -> PathDebug:
	if _instance == null or not is_instance_valid(_instance):
		var layer: CanvasLayer = CanvasLayer.new()
		layer.name = "PathDebugLayer"
		layer.layer = 12
		layer.follow_viewport_enabled = true
		_instance = PathDebug.new()
		layer.add_child(_instance)
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		tree.root.add_child.call_deferred(layer)
	return _instance


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SoundBus.instance().sound_emitted.connect(func(at: Vector2, radius: float) -> void: _sounds.append([at, radius, 0.0]))


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match KEYS.find(key.physical_keycode):
		0: show_cones = not show_cones
		1: show_paths = not show_paths
		2: show_states = not show_states
		3: show_sounds = not show_sounds
		4: show_grid = not show_grid
		_: return
	queue_redraw()


func _process(delta: float) -> void:
	for sound: Array in _sounds:
		sound[2] += delta
	_sounds = _sounds.filter(func(sound: Array) -> bool: return sound[2] < SOUND_LIFETIME)
	queue_redraw()


func _draw() -> void:
	if show_grid and _grid != null and is_instance_valid(_grid):
		_draw_grid()
	if show_sounds:
		for sound: Array in _sounds:
			var t: float = sound[2] / SOUND_LIFETIME
			draw_arc(sound[0], sound[1] * t, 0.0, TAU, 64, Color(1, 1, 0.4, 1.0 - t), 2.0)


## 格子線：不能走的格子塗紅，成本高的塗黃（越貴越黃）
func _draw_grid() -> void:
	var region: Rect2i = _grid.astar.region
	var size: Vector2 = _grid.cell_size()
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var cell: Vector2i = Vector2i(x, y)
			var rect: Rect2 = Rect2(_grid.cell_center(cell) - size / 2.0, size)
			if _grid.astar.is_point_solid(cell):
				draw_rect(rect, Color(1, 0.2, 0.2, 0.25))
			elif _grid.astar.get_point_weight_scale(cell) > 1.0:
				draw_rect(rect, Color(1, 0.85, 0.2, minf(0.12 * _grid.astar.get_point_weight_scale(cell), 0.5)))
			draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)
