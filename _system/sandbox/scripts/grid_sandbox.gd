extends Node2D
## 開發用沙盒：看格子、門、PathFollower 有沒有正常運作（匯出時排除）。
## F6 執行：左鍵點地圖，方塊會找路走過去（遇到門會停下來開）；右鍵點門開關門；空白鍵切換「使用尋路」。
## 加上 `-- shot` 執行：等一下自動截圖存到 user://grid_sandbox.png 然後關掉。

const TILESET: TileSet = preload("res://game/level/tileset/tileset.tres")
const DOOR_SCENE: PackedScene = preload("res://game/level/door.tscn")
## 地圖：# 牆、G 玻璃、B 草叢、D 門、L 上鎖的門、. 木頭地板、, 磁磚地板、空白＝房子外面
const MAP: PackedStringArray = [
	"##########################",
	"#.........#,,,,,,,,,,,,,,#",
	"#.........#,,,,,,,,,,,,,,#",
	"#...BBB...D,,,,####,,,,,,#",
	"#...BBB...#,,,,#..#,,,,,,#",
	"#.........#,,,,#..L,,,,,,#",
	"####GGG####,,,,####,,,,,,#",
	"#.........#,,,,,,,,,,,,,,#",
	"#.........D,,,,,,,,BBB,,,#",
	"#.........#,,,,,,,,BBB,,,#",
	"##########################",
]

var _grid: LevelGrid
var _body: CharacterBody2D
var _follower: PathFollower
var _label: Label


func _ready() -> void:
	_build_map()
	_body = _make_body(Vector2(80, 80))
	_follower = _body.get_node("PathFollower")
	_follower.speed = 160.0
	_label = Label.new()
	_label.position = Vector2(860, 16)
	_label.add_theme_font_size_override("font_size", 22)
	add_child(_label)
	if OS.get_cmdline_user_args().has("shot"):
		_follower.go_to(Vector2(600, 280))
		await get_tree().create_timer(1.2).timeout
		get_viewport().get_texture().get_image().save_png("user://grid_sandbox_mid.png")
		await get_tree().create_timer(2.5).timeout
		get_viewport().get_texture().get_image().save_png("user://grid_sandbox.png")
		print("截圖：", ProjectSettings.globalize_path("user://grid_sandbox.png"))
		get_tree().quit()


func _build_map() -> void:
	var floor_layer: TileMapLayer = TileMapLayer.new()
	floor_layer.tile_set = TILESET
	floor_layer.z_index = -2
	add_child(floor_layer)
	var walls: TileMapLayer = TileMapLayer.new()
	walls.tile_set = TILESET
	walls.z_index = -1
	add_child(walls)
	for y: int in MAP.size():
		for x: int in MAP[y].length():
			var cell: Vector2i = Vector2i(x, y)
			var c: String = MAP[y][x]
			if c != " ":
				floor_layer.set_cell(cell, 0, Vector2i(1, 0) if c == "," else Vector2i(0, 0))
			match c:
				"#": walls.set_cell(cell, 0, Vector2i(2, 0))
				"G": walls.set_cell(cell, 0, Vector2i(3, 0))
				"B": walls.set_cell(cell, 0, Vector2i(4, 0))
				"D", "L":
					var door: Door = DOOR_SCENE.instantiate()
					door.orientation = 1 if MAP[y - 1][x] == "#" else 0
					door.locked = c == "L"
					door.position = Vector2(cell) * 32.0 + Vector2(16, 16)
					add_child(door)
	_grid = LevelGrid.new()
	add_child(_grid)
	_grid.setup(walls, floor_layer)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse: InputEventMouseButton = event
		var at: Vector2 = get_global_mouse_position()
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_follower.go_to(at)
		elif mouse.button_index == MOUSE_BUTTON_RIGHT:
			var door: Door = _grid.door_at(_grid.cell_of(at))
			if door != null:
				door.toggle()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_SPACE:
		_follower.use_pathfinding = not _follower.use_pathfinding


func _process(_delta: float) -> void:
	_label.text = "使用尋路：%s\n左鍵：走過去\n右鍵：開關門\n空白鍵：切換尋路" % ("開" if _follower.use_pathfinding else "關")
	queue_redraw()


func _draw() -> void:
	# 路徑：從方塊到每個路徑點連線
	var points: PackedVector2Array = PackedVector2Array([_body.global_position])
	points.append_array(_follower.path)
	if points.size() >= 2:
		draw_polyline(points, Color(1, 0.3, 0.3), 3.0)
	draw_rect(Rect2(_body.global_position - Vector2(12, 12), Vector2(24, 24)), Color("e04040") if _follower.is_opening_door() else Color("f0f0f0"))


func _make_body(at: Vector2) -> CharacterBody2D:
	var body: CharacterBody2D = CharacterBody2D.new()
	body.collision_layer = 8
	body.collision_mask = 1
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	body.add_child(shape)
	var follower: PathFollower = PathFollower.new()
	follower.name = "PathFollower"
	body.add_child(follower)
	body.position = at
	add_child(body)
	return body
