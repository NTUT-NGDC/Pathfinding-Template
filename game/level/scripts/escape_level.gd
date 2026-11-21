class_name EscapeLevel
extends Node2D
## 逃脫關卡的最上層節點。「害怕 vs 公平」的設定都在這裡的檢查器。
##
## 遊戲開始時會自動加進去（不會存進你的場景）：
##   尋路格子（LevelGrid）、畫面資訊（HUD）、玩家視野圈、除錯圖層、暫停選單
##
## 關卡裡要有：
##   ・Floor（地板）和 Walls（牆、玻璃、草叢）兩張 TileMapLayer
##   ・一個 Player、至少一個 Exit
##   ・殺手、修理點、鑰匙、門、躲藏點：要幾個放幾個
##
## 被抓到會自動重來這一關；逃出去會顯示通關時間。

## 被抓到了
signal failed()
## 逃出去了（通關秒數）
signal cleared(seconds: float)

const HUD_SCENE: PackedScene = preload("res://game/level/hud.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://game/pause_menu/pause_menu.tscn")
const TITLE_SCENE: String = "res://game/title_screen/title_screen.tscn"
const DebugOverlayScript: GDScript = preload("res://game/level/scripts/debug_overlay.gd")
## 被抓到後幾秒重來
const RESTART_DELAY: float = 1.5

@export_group("關卡")
## 顯示在左上角的名字（空白＝不顯示）
@export var level_name: String = "我的逃脫遊戲"

@export_group("害怕 vs 公平")
## 顯示殺手的視野錐：開＝公平（知道哪裡安全），關＝恐怖。遊戲中按 1 也可以切換
@export var show_killer_cones: bool = true
## 玩家視野圈：只看得到玩家周圍，外面變暗
@export var player_light: bool = true
## 視野圈半徑（像素）
@export_range(60, 800, 10, "suffix:px") var player_light_radius: float = 240.0
## 視野圈邊緣漸層的寬度（像素）
@export_range(0, 300, 10, "suffix:px") var player_light_softness: float = 100.0
## 視野圈外面有多暗：1＝全黑
@export_range(0.0, 1.0, 0.05) var player_light_darkness: float = 0.9
## 接近警告：殺手靠近時畫面邊緣變紅、一閃一閃
@export var proximity_warning: bool = false
## 殺手多近開始警告（像素）
@export_range(50, 800, 10, "suffix:px") var warning_distance: float = 220.0

@export_group("圖層")
## 畫地板的 TileMapLayer（空白＝自動找名字叫 Floor 的）
@export var floor_layer: TileMapLayer
## 畫牆、玻璃、草叢的 TileMapLayer（空白＝自動找名字叫 Walls 的）
@export var walls_layer: TileMapLayer

## 從開始到現在幾秒
var elapsed: float = 0.0
var is_finished: bool = false

var _grid: LevelGrid
var _hud: CanvasLayer
var _player: Player
var _tasks: Array[Task] = []


func _ready() -> void:
	if floor_layer == null:
		floor_layer = get_node_or_null("Floor") as TileMapLayer
	if walls_layer == null:
		walls_layer = get_node_or_null("Walls") as TileMapLayer
	if walls_layer == null:
		push_error("關卡裡找不到 Walls（畫牆的 TileMapLayer）。")
		return
	DebugView.reset(show_killer_cones)

	_grid = LevelGrid.new()
	_grid.name = "LevelGrid"
	add_child(_grid)
	_grid.setup(walls_layer, floor_layer)

	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		push_error("關卡裡沒有玩家（player.tscn）。")
	else:
		_player.caught.connect(_on_player_caught)
		_player.escaped.connect(_on_player_escaped)
		_setup_camera()

	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.call("set_level_name", level_name)
	_hud.retry_pressed.connect(_restart)
	_hud.title_pressed.connect(_go_to_title)
	for node: Node in get_tree().get_nodes_in_group("tasks"):
		var task: Task = node as Task
		_tasks.append(task)
		task.completed.connect(func(_t: Task) -> void: _update_tasks())
	_update_tasks()

	if player_light and _player != null:
		var light: PlayerLight = PlayerLight.new()
		light.radius = player_light_radius
		light.softness = player_light_softness
		light.darkness = player_light_darkness
		light.player = _player
		add_child(light)

	var debug_layer: CanvasLayer = CanvasLayer.new()
	debug_layer.layer = 12
	debug_layer.follow_viewport_enabled = true
	add_child(debug_layer)
	var overlay: Node2D = DebugOverlayScript.new()
	overlay.set("grid", _grid)
	debug_layer.add_child(overlay)

	add_child(PAUSE_MENU_SCENE.instantiate())


func _process(delta: float) -> void:
	if is_finished or _hud == null:
		return
	elapsed += delta
	_hud.call("set_time", elapsed)
	if proximity_warning and _player != null:
		_hud.call("set_warning", _warning_strength())


## 畫面上的任務進度：依種類數，例如「修理 1/2　鑰匙 0/1」
func _update_tasks() -> void:
	var order: Array[String] = []
	var done: Dictionary[String, int] = {}
	var total: Dictionary[String, int] = {}
	for task: Task in _tasks:
		if not total.has(task.category):
			order.append(task.category)
			total[task.category] = 0
			done[task.category] = 0
		total[task.category] += 1
		if task.is_done:
			done[task.category] += 1
	var parts: PackedStringArray = []
	for category: String in order:
		parts.append("%s %d/%d" % [category, done[category], total[category]])
	var text: String = "　".join(parts) if not parts.is_empty() else "沒有任務"
	if _tasks.all(func(task: Task) -> bool: return task.is_done):
		text += "\n出口打開了！"
	_hud.call("set_tasks", text)


## 最近的殺手越近，警告越強（0～1）
func _warning_strength() -> float:
	var nearest: float = INF
	for node: Node in get_tree().get_nodes_in_group("killer"):
		nearest = minf(nearest, (node as Node2D).global_position.distance_to(_player.global_position))
	return clampf(1.0 - nearest / warning_distance, 0.0, 1.0)


## 關卡比畫面小：鏡頭固定在關卡中間；比畫面大：鏡頭跟著玩家，但不會超出關卡
func _setup_camera() -> void:
	var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	var cells: Rect2i = walls_layer.get_used_rect()
	if floor_layer != null:
		cells = cells.merge(floor_layer.get_used_rect())
	var top_left: Vector2 = walls_layer.to_global(walls_layer.map_to_local(cells.position)) - Vector2(walls_layer.tile_set.tile_size) / 2.0
	var bounds: Rect2 = Rect2(top_left, Vector2(cells.size * walls_layer.tile_set.tile_size))
	var screen: Vector2 = get_viewport_rect().size
	if bounds.size.x <= screen.x and bounds.size.y <= screen.y:
		camera.enabled = false
		var fixed: Camera2D = Camera2D.new()
		fixed.position = bounds.get_center()
		add_child(fixed)
		fixed.make_current()
		return
	camera.enabled = true
	camera.limit_left = floori(bounds.position.x)
	camera.limit_top = floori(bounds.position.y)
	camera.limit_right = ceili(bounds.end.x)
	camera.limit_bottom = ceili(bounds.end.y)
	camera.make_current()


func _on_player_caught() -> void:
	is_finished = true
	_hud.call("show_caught")
	failed.emit()
	get_tree().create_timer(RESTART_DELAY).timeout.connect(_restart)


func _on_player_escaped() -> void:
	is_finished = true
	_hud.call("set_warning", 0.0)
	_hud.call("show_escaped", elapsed)
	cleared.emit(elapsed)


## 重來這一關（關卡是被別的場景包著時，交給外面處理）
func _restart() -> void:
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()


func _go_to_title() -> void:
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file(TITLE_SCENE)
