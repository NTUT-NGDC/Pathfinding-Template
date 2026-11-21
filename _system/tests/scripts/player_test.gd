extends Node
## 玩家的自動測試：
## 1. 走路安靜、跑步比較快而且會發出聲音
## 2. E 開關門；上鎖的門要有同顏色的鑰匙
## 3. E 躲進躲藏點：看不到、不能動、碰撞關掉；再按 E 出來回到原位
## 4. 碰到殺手就被抓；躲著的時候碰不到；被拖出來也算被抓
##
## 測試地圖（12×7 格）：第 7 行是一整排牆，(7,1) 一般的門、(7,5) 藍色上鎖的門；(3,5) 躲藏點
##
## 在命令列執行：
##   godot --headless --path . res://_system/tests/player_test.tscn

const TILESET: TileSet = preload("res://game/level/tileset/tileset.tres")
const DOOR_SCENE: PackedScene = preload("res://game/level/door.tscn")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const HIDING_SCENE: PackedScene = preload("res://game/level/hiding_spot.tscn")

var _failures: int = 0
var _player: Player
var _door: Door
var _locked_door: Door
var _spot: HidingSpot
var _sounds: int = 0
var _events: Array[String] = []


func _ready() -> void:
	_build_level()
	SoundBus.sound_emitted.connect(func(_p: Vector2, _r: float) -> void: _sounds += 1)
	_player.caught.connect(func() -> void: _events.append("caught"))
	_player.hid.connect(func(_s: Node2D) -> void: _events.append("hid"))
	_player.unhid.connect(func(_s: Node2D) -> void: _events.append("unhid"))
	await _frames(2)

	await _test_walk_and_run()
	await _test_doors()
	await _test_hiding()
	await _test_caught()

	if _failures == 0:
		print("[玩家測試] 全部 PASS")
		get_tree().quit(0)
	else:
		print("[玩家測試] FAIL：%d 項失敗" % _failures)
		get_tree().quit(1)


func _build_level() -> void:
	var floor_layer: TileMapLayer = TileMapLayer.new()
	floor_layer.tile_set = TILESET
	add_child(floor_layer)
	var walls: TileMapLayer = TileMapLayer.new()
	walls.tile_set = TILESET
	add_child(walls)
	for x: int in 12:
		for y: int in 7:
			floor_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	for y: int in 7:
		if y != 1 and y != 5:
			walls.set_cell(Vector2i(7, y), 0, Vector2i(2, 0))

	_door = DOOR_SCENE.instantiate()
	_door.orientation = 1
	_door.position = _center(Vector2i(7, 1))
	add_child(_door)
	_locked_door = DOOR_SCENE.instantiate()
	_locked_door.orientation = 1
	_locked_door.locked = true
	_locked_door.key_color = "藍"
	_locked_door.position = _center(Vector2i(7, 5))
	add_child(_locked_door)
	_spot = HIDING_SCENE.instantiate()
	_spot.position = _center(Vector2i(3, 5))
	add_child(_spot)

	_player = PLAYER_SCENE.instantiate()
	_player.position = _center(Vector2i(2, 3))
	add_child(_player)


func _test_walk_and_run() -> void:
	print("--- 走路、跑步 ---")
	var sounds_before: int = _sounds
	var start: Vector2 = _player.global_position
	Input.action_press("move_right")
	await _frames(30)
	var walked: float = _player.global_position.x - start.x
	Input.action_release("move_right")
	_expect(walked > 40.0 and walked < 70.0, "走路半秒移動約 55 px（實際 %.0f）" % walked)
	_expect(_sounds == sounds_before, "走路不會發出聲音")

	start = _player.global_position
	Input.action_press("move_left")
	Input.action_press("run")
	await _frames(30)
	var ran: float = start.x - _player.global_position.x
	Input.action_release("move_left")
	Input.action_release("run")
	_expect(ran > walked * 1.4, "跑步比較快（%.0f px）" % ran)
	_expect(_sounds > sounds_before, "跑步會發出聲音（%d 次）" % (_sounds - sounds_before))

	await _frames(5)
	start = _player.global_position
	Input.action_press("run")
	await _frames(20)
	Input.action_release("run")
	_expect(_player.global_position == start, "只按 Shift 不會動")


func _test_doors() -> void:
	print("--- 門 ---")
	await _teleport(_center(Vector2i(6, 1)))
	var prompt: Label = _player.get_node("Prompt")
	_expect(prompt.visible and prompt.text == "E 開門", "靠近門：頭上出現「E 開門」（%s）" % prompt.text)
	await _press_interact()
	_expect(_door.is_open, "按 E 開門")
	await _frames(1)
	_expect(prompt.text == "E 關門", "門開了：提示變成「E 關門」")
	await _press_interact()
	_expect(not _door.is_open, "再按 E 關門")

	await _teleport(_center(Vector2i(6, 5)))
	_expect(prompt.text.contains("藍"), "上鎖的門：提示需要藍色鑰匙（%s）" % prompt.text)
	await _press_interact()
	_expect(_locked_door.locked and not _locked_door.is_open, "沒有鑰匙：打不開")
	_player.add_key("紅")
	await _press_interact()
	_expect(_locked_door.locked, "顏色不對的鑰匙：打不開")
	_player.add_key("藍")
	await _press_interact()
	_expect(not _locked_door.locked and _locked_door.is_open, "有藍色鑰匙：解鎖並打開")

	await _teleport(_center(Vector2i(2, 1)))
	_expect(not prompt.visible, "旁邊沒東西：沒有提示")


func _test_hiding() -> void:
	print("--- 躲藏 ---")
	var outside: Vector2 = _center(Vector2i(3, 4))
	await _teleport(outside)
	_events.clear()
	await _press_interact()
	_expect(_player.is_hidden and _events.has("hid"), "按 E 躲進去")
	_expect(_player.global_position == _spot.global_position, "躲在躲藏點的位置")
	_expect(_player.collision_layer == 0, "躲著：碰撞關掉（殺手碰不到）")
	var prompt: Label = _player.get_node("Prompt")
	await _frames(1)
	_expect(prompt.visible and prompt.text == "E 出來", "躲著：提示「E 出來」")

	Input.action_press("move_right")
	await _frames(20)
	Input.action_release("move_right")
	_expect(_player.global_position == _spot.global_position, "躲著不能動")

	await _press_interact()
	_expect(not _player.is_hidden and _events.has("unhid"), "再按 E 出來")
	_expect(_player.global_position == outside, "出來回到躲進去之前的位置")
	_expect(_player.collision_layer != 0, "出來：碰撞恢復")


func _test_caught() -> void:
	print("--- 被抓 ---")
	_events.clear()
	# 躲著的時候殺手走過來：碰不到
	await _teleport(_center(Vector2i(3, 4)))
	await _press_interact()
	var killer: CharacterBody2D = _make_killer(_spot.global_position)
	await _frames(5)
	_expect(not _events.has("caught"), "躲著：殺手站在旁邊也抓不到")
	# 殺手把玩家拖出來
	_player.get_caught()
	_expect(_events.has("caught") and not _player.is_hidden, "被拖出來＝被抓")
	_expect(_player.is_finished, "被抓之後不能再動")

	# 重新做一個玩家：殺手碰到就被抓
	_player.queue_free()
	killer.queue_free()
	await _frames(1)
	_player = PLAYER_SCENE.instantiate()
	_player.position = _center(Vector2i(2, 3))
	var caught: Array[bool] = [false]
	_player.caught.connect(func() -> void: caught[0] = true)
	add_child(_player)
	await _frames(2)
	killer = _make_killer(_center(Vector2i(4, 3)))
	await _frames(2)
	_expect(not caught[0], "殺手還沒碰到：沒事")
	killer.global_position = _player.global_position + Vector2(10, 0)
	await _frames(3)
	_expect(caught[0], "殺手碰到：被抓")


func _make_killer(at: Vector2) -> CharacterBody2D:
	var body: CharacterBody2D = CharacterBody2D.new()
	body.add_to_group("killer")
	body.collision_layer = 8
	body.collision_mask = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


func _press_interact() -> void:
	await get_tree().physics_frame
	Input.action_press("interact")
	await get_tree().physics_frame
	Input.action_release("interact")
	await get_tree().physics_frame


func _teleport(at: Vector2) -> void:
	_player.global_position = at
	await _frames(3)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * 32.0 + Vector2(16, 16)


func _expect(ok: bool, description: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
