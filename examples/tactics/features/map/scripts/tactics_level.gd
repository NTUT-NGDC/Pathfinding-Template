@tool
class_name TacticsLevel
extends TacticsTerrain
## 讀戰棋地圖：鋪尋路地圖、放隊伍和敵人小隊、判斷輸贏。編輯器裡打開關卡就看得到地形和位置。
##
## 用法：在檢查器把 maps/ 資料夾裡的地圖（.tres）拖進 Map 就換地圖。
## 地圖用 map_editor/map_editor.tscn 畫（打開按 F6）。

## 地圖準備好了
signal map_ready()

## 地板、牆兩張 TileMapLayer（給尋路地圖和視野用，遊戲中看不到，畫面由這個節點畫）
@export var floor_layer: TileMapLayer
@export var walls_layer: TileMapLayer
## 戰鬥、隊伍、鏡頭
@export var battle: TacticsBattle
@export var party: TacticsParty
@export var camera: FollowCamera
## 探索時鏡頭放大幾倍
@export_range(0.5, 3.0, 0.1) var camera_zoom: float = 1.4

## 編輯器按「試玩」時放在這裡，關卡就用這張
static var test_map: TacticsMap
## 上次編隊選了誰（照地圖記，按「重來」不用重選）：地圖名字 → {"chosen", "formation", "roster"}
static var last_choice: Dictionary[String, Dictionary] = {}
## 出發前的編隊畫面（沒有＝null）
var setup_screen: TacticsPartySetup
## 這一關招募到的人：哪裡來的 → 棋子場景（過關才會進隊伍池）
var recruited: Dictionary[String, String] = {}
## 是不是編輯器裡的試玩
var is_test_play: bool = false
var squads: Array[EnemySquad] = []

## TileSet 裡的哪一格
const TILE_FLOOR: Vector2i = Vector2i(0, 0)
const TILE_WALL: Vector2i = Vector2i(2, 0)
const TILE_FOREST: Vector2i = Vector2i(4, 0)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("tactics_level")
	if test_map != null:
		map = test_map
		test_map = null
		is_test_play = true
	_apply.call_deferred()


func _apply() -> void:
	if map == null:
		return
	map.ensure()
	_build_grid()
	battle.setup(map, camera)
	battle.ended.connect(_on_battle_ended)
	party.control_changed.connect(func(unit: Unit) -> void: camera.target = unit)
	if camera != null:
		camera.zoom = Vector2(camera_zoom, camera_zoom)
		camera.limit_rect = Rect2(global_position, Vector2(map.size * TacticsMap.CELL)).grow_individual(64, 80, 64, 96)
		camera.use_limits = true
		camera.apply_limits()
		camera.global_position = to_global(map.cell_center(map.start_cell))
		camera.reset_smoothing()
	if map.choose_party and not map.roster().is_empty():
		_open_setup()
	else:
		depart(map.roster(), map.formation)


## 編隊畫面：選好按「出發」才開始
func _open_setup() -> void:
	setup_screen = TacticsPartySetup.new()
	setup_screen.roster = map.roster()
	setup_screen.limit = map.party_max
	setup_screen.formation = map.formation as TacticsFormation.Kind
	var last: Dictionary = last_choice.get(map.map_name, {})
	if not last.is_empty() and last["roster"] == setup_screen.roster and last["chosen"].size() <= setup_screen.max_count():
		setup_screen.chosen.assign(last["chosen"])
		setup_screen.formation = last["formation"]
	else:
		setup_screen.choose_default()
	setup_screen.confirmed.connect(_on_setup_confirmed)
	add_child(setup_screen)


func _on_setup_confirmed(units: Array[String], formation: int) -> void:
	last_choice[map.map_name] = {"chosen": setup_screen.chosen.duplicate(), "formation": formation, "roster": setup_screen.roster.duplicate()}
	setup_screen.queue_free()
	setup_screen = null
	depart(units, formation)


## 帶著這些人出發：放隊伍、敵人、物資，開始玩
func depart(units: Array[String], formation: int) -> void:
	party.setup(map, to_global(map.cell_center(map.start_cell)), battle, units, formation)
	_place_squads()
	_place_supplies()
	map_ready.emit()
	for squad: EnemySquad in squads:
		if squad.data.instant:
			battle.start(squad)                                   # 純戰棋：一開始就開打
			break


## 地形 → TileMapLayer（牆擋路也擋視線、森林擋視線）＋尋路地圖的移動成本
func _build_grid() -> void:
	floor_layer.clear()
	walls_layer.clear()
	floor_layer.visible = false
	walls_layer.visible = false
	for y: int in map.size.y:
		for x: int in map.size.x:
			var cell: Vector2i = Vector2i(x, y)
			floor_layer.set_cell(cell, 0, TILE_FLOOR)
			match map.kind_at(cell):
				TacticsMap.Kind.WALL: walls_layer.set_cell(cell, 0, TILE_WALL)
				TacticsMap.Kind.FOREST: walls_layer.set_cell(cell, 0, TILE_FOREST)
	var grid: PathGrid = get_tree().get_first_node_in_group("path_grid") as PathGrid
	grid.setup(walls_layer, floor_layer)
	for y: int in map.size.y:
		for x: int in map.size.x:
			var cost: float = TacticsMap.KIND_COSTS[map.kind_at(Vector2i(x, y))]
			if cost > 1.0:
				grid.set_cost(Vector2i(x, y), cost)


func _place_squads() -> void:
	for data: TacticsSquad in map.squads:
		if data.members.is_empty():
			continue
		var squad: EnemySquad = EnemySquad.new()
		squad.name = "Squad%d" % (squads.size() + 1)
		get_parent().add_child(squad)
		squad.setup(data, map, global_position, battle)
		squad.spotted.connect(_on_spotted)
		squads.append(squad)


func _place_supplies() -> void:
	for cell: Vector2i in map.supply_cells:
		var supply: TacticsSupply = TacticsSupply.new()
		get_parent().add_child(supply)
		supply.global_position = to_global(map.cell_center(cell))
	for cell: Vector2i in map.chests:
		var chest: TacticsChest = TacticsChest.new()
		chest.amount = map.chests[cell]
		get_parent().add_child(chest)
		chest.global_position = to_global(map.cell_center(cell))
	for cell: Vector2i in map.allies:
		var key: String = "%s:同伴:%d,%d" % [map_key(), cell.x, cell.y]
		if TacticsPool.has(key):
			continue                                              # 之前招募過了
		var ally: TacticsAlly = TacticsAlly.new()
		ally.unit_path = map.allies[cell]
		ally.key = key
		get_parent().add_child(ally)
		ally.global_position = to_global(map.cell_center(cell))


func _on_spotted(squad: EnemySquad, ambush: bool, who: Unit) -> void:
	party.interrupt("被發現了，中斷！")
	battle.start(squad, ambush, who)


# ---- 輸贏 ----

func _on_battle_ended(won: bool) -> void:
	if not won:
		return
	squads = squads.filter(func(s: EnemySquad) -> bool: return is_instance_valid(s) and not s.is_queued_for_deletion())
	if map.win == TacticsMap.Win.ALL and squads.is_empty():
		_win("所有小隊都打倒了！")
	elif map.win == TacticsMap.Win.BOSS and not squads.any(func(s: EnemySquad) -> bool: return s.data.boss):
		_win("打倒首領了！")
	else:
		for squad: EnemySquad in squads:
			if squad.data.instant:
				battle.start.call_deferred(squad)                 # 純戰棋有好幾隊：一隊接一隊
				return


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or map == null or map.win != TacticsMap.Win.GOAL or not party.is_exploring():
		return
	if map.goal_cells.has(map.cell_at(to_local(party.captain().global_position))):
		_win("抵達目標！")


## 這張地圖的名字（隊伍池記「哪裡來的」用）
func map_key() -> String:
	return map.resource_path.get_file().get_basename() if not map.resource_path.is_empty() else map.map_name


## 過關：招募到的人、過關獎勵進隊伍池
func _win(message: String) -> void:
	if GameFlow.is_finished():
		return
	var names: PackedStringArray = PackedStringArray()
	for key: String in recruited:
		if TacticsPool.add(key, recruited[key]):
			names.append(_name_of(recruited[key]))
	for i: int in map.rewards.size():
		if TacticsPool.add("%s:獎勵:%d" % [map_key(), i], map.rewards[i]):
			names.append(_name_of(map.rewards[i]))
	if not names.is_empty():
		message += "\n%s 加入隊伍了！" % "、".join(names)
	GameFlow.win(message)


func _name_of(path: String) -> String:
	var unit: Unit = (load(path) as PackedScene).instantiate() as Unit
	var text: String = unit.display_name
	unit.free()
	return text


func _draws_supplies() -> bool:
	return Engine.is_editor_hint()


func _draw() -> void:
	super._draw()
	if not Engine.is_editor_hint() or map == null:
		return
	for cell: Vector2i in map.allies:
		draw_circle(map.cell_center(cell), 11.0, Color("4ab86a"))
	draw_arc(map.cell_center(map.start_cell), 13.0, 0, TAU, 24, Unit.TEAM_COLORS[0], 3.0)
	for squad: TacticsSquad in map.squads:
		for cell: Vector2i in squad.cells:
			draw_circle(map.cell_center(cell), 11.0, Unit.TEAM_COLORS[1])
