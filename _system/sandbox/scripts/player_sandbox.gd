extends Node2D
## 開發用沙盒：試玩家（匯出時排除）。
## F6 執行：WASD 走、Shift 跑（畫面上會畫出腳步聲的圈）、E 開門／躲藏。按 K 拿到紅色鑰匙。
## 加上 `-- shot` 執行：自動走到門前截圖，存到 user://player_sandbox.png 然後關掉。

const TILESET: TileSet = preload("res://game/level/tileset/tileset.tres")
const DOOR_SCENE: PackedScene = preload("res://game/level/door.tscn")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const HIDING_SCENE: PackedScene = preload("res://game/level/hiding_spot.tscn")
## 地圖：# 牆、G 玻璃、B 草叢、D 門、L 紅色上鎖的門、C 櫃子、E 床、. 木頭、, 磁磚
const MAP: PackedStringArray = [
	"####################",
	"#.......#,,,,,,,,,,#",
	"#..C....D,,,,,,,,,,#",
	"#.......#,,,BBB,,,,#",
	"###GGG###,,,BBB,,,,#",
	"#.......#,,,,,,,,,,#",
	"#..E....L,,,,,,,C,,#",
	"#.......#,,,,,,,,,,#",
	"####################",
]

## 畫在畫面上的聲音圈：[位置, 半徑, 剩幾秒]
var _sounds: Array[Array] = []
var _player: Player
var _label: Label


func _ready() -> void:
	_build_map()
	SoundBus.sound_emitted.connect(func(at: Vector2, radius: float) -> void: _sounds.append([at, radius, 0.5]))
	_label = Label.new()
	_label.position = Vector2(680, 16)
	_label.add_theme_font_size_override("font_size", 22)
	add_child(_label)
	if OS.get_cmdline_user_args().has("shot"):
		_player.global_position = Vector2(220, 80)
		Input.action_press("run")
		Input.action_press("move_right")
		await get_tree().create_timer(0.2).timeout
		Input.action_release("move_right")
		Input.action_release("run")
		await get_tree().create_timer(0.1).timeout
		get_viewport().get_texture().get_image().save_png("user://player_sandbox.png")
		print("截圖：", ProjectSettings.globalize_path("user://player_sandbox.png"))
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
			var at: Vector2 = Vector2(cell) * 32.0 + Vector2(16, 16)
			var c: String = MAP[y][x]
			floor_layer.set_cell(cell, 0, Vector2i(1, 0) if c == "," else Vector2i(0, 0))
			match c:
				"#": walls.set_cell(cell, 0, Vector2i(2, 0))
				"G": walls.set_cell(cell, 0, Vector2i(3, 0))
				"B": walls.set_cell(cell, 0, Vector2i(4, 0))
				"D", "L":
					var door: Door = DOOR_SCENE.instantiate()
					door.orientation = 1
					door.locked = c == "L"
					door.position = at
					add_child(door)
				"C", "E":
					var spot: HidingSpot = HIDING_SCENE.instantiate()
					spot.style = 0 if c == "C" else 1
					spot.position = at
					add_child(spot)
	var grid: LevelGrid = LevelGrid.new()
	add_child(grid)
	grid.setup(walls, floor_layer)
	_player = PLAYER_SCENE.instantiate()
	_player.position = Vector2(80, 80)
	_player.camera_follow = false
	add_child(_player)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_K:
		_player.add_key("紅")


func _process(delta: float) -> void:
	for sound: Array in _sounds:
		sound[2] -= delta
	_sounds = _sounds.filter(func(sound: Array) -> bool: return sound[2] > 0.0)
	_label.text = "WASD 走、Shift 跑、E 互動\nK：拿到紅色鑰匙\n\n鑰匙：%s\n躲著：%s" % [", ".join(_player.keys) if not _player.keys.is_empty() else "沒有", "是" if _player.is_hidden else "否"]
	queue_redraw()


func _draw() -> void:
	for sound: Array in _sounds:
		var t: float = 1.0 - sound[2] / 0.5
		draw_arc(sound[0], sound[1] * t, 0.0, TAU, 48, Color(1, 1, 0.4, 1.0 - t), 2.0)
