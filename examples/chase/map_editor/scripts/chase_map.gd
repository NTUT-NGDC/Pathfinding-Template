class_name ChaseMap
extends Resource
## 追逐關卡在編輯器裡的樣子：從關卡場景（levels/*.tscn）讀出來，改完寫回同一個場景。
## 只管地板、牆、直接放在關卡底下的物件、黑暗和鏡頭；其他手動加的節點（HUD、自己的東西）不會動到，
## 所以同一個關卡可以在編輯器和 Godot 裡輪流改。

## 新關卡從這個場景開始
const TEMPLATE: String = "res://examples/chase/levels/chase.tscn"
const CELL: int = 32
## 圖塊（tileset 的第幾格）
enum Tile { WOOD, TILES, WALL, GLASS, BUSH, SWAMP }
## 這些不是物件（尋路地圖、黑暗、鏡頭）
const NOT_OBJECTS: Array[String] = ["res://addons/ngdc_pathfinding/grid/path_grid.tscn", "res://examples/chase/features/darkness/darkness.tscn", "res://core/camera/follow_camera.tscn"]
const ENEMY: String = "res://addons/ngdc_pathfinding/chase_ai/chase_ai.tscn"
const EXIT: String = "res://examples/chase/features/exit/exit.tscn"
const PLAYER: String = "res://examples/chase/features/player/player.tscn"
const DARKNESS: String = "res://examples/chase/features/darkness/darkness.tscn"
## 可以掛在敵人底下的
const DROPPER: String = "res://examples/chase/features/trap/trap_dropper.tscn"
## 註解第一句不適合當名字的，在這裡改（其他的自動用 @export 上面的 ## 註解）
const LABELS: Dictionary[String, String] = {
	"needed": "需要幾個", "patrol_speed": "巡邏速度", "chase_speed": "追擊速度", "search_time": "追丟後找幾秒",
	"remember_last_position": "記住最後看到的", "catch_distance": "多近算抓到", "caught_message": "抓到時的文字", "patrol_mode": "走完巡邏點之後",
	"run_sound_interval": "腳步聲隔幾秒", "bottle_sound_radius": "瓶子聲音多遠", "run_sound_radius": "跑步聲音多遠", "start_bottles": "一開始幾個瓶子",
	"kind": "種類", "required": "算進出口條件", "action": "提示的動詞", "sound_interval": "聲音隔幾秒", "start_open": "一開始開著",
	"sound_radius": "聲音傳多遠", "locked": "上鎖", "key_color": "鑰匙顏色", "cooldown": "冷卻", "drop_on": "什麼時候放", "max_traps": "最多幾個",
	"one_shot": "只用一次", "dropped_one_shot": "夾子只用一次", "ai_avoids": "AI 會繞開", "visible_to_player": "看得見", "amount": "一次幾個",
}
const DARKNESS_FIELDS: Array[String] = ["radius", "softness", "darkness"]

var map_name: String = "新關卡"
## 地圖大小（格數）
var size: Vector2i = Vector2i(36, 18)
## 格子 → 圖塊
var floors: Dictionary[Vector2i, int] = {}
var walls: Dictionary[Vector2i, int] = {}
## 物件：{"name", "scene", "position", "values": {欄位: 值}, "points": 巡邏點（關卡裡的位置）, "dropper": 放捕獸夾的設定（沒有＝空的）}
var objects: Array[Dictionary] = []
## 黑暗、鏡頭：{"dark": 有沒有黑暗, "radius", "softness", "darkness", "follow": 鏡頭跟著玩家, "zoom"}
var settings: Dictionary = {"dark": true, "radius": 240.0, "softness": 100.0, "darkness": 0.9, "follow": false, "zoom": 1.0}


# ---- 編輯器要用的 ----

func ensure() -> void:
	pass


func snapshot() -> Dictionary:
	return {"size": size, "floors": floors.duplicate(), "walls": walls.duplicate(), "objects": objects.duplicate(true), "settings": settings.duplicate()}


func restore(state: Dictionary) -> void:
	size = state["size"]
	floors.assign(state["floors"])
	walls.assign(state["walls"])
	objects.assign((state["objects"] as Array).duplicate(true))
	settings = (state["settings"] as Dictionary).duplicate()
	emit_changed()


func resize(to: Vector2i) -> void:
	size = to
	var area: Rect2i = Rect2i(Vector2i.ZERO, to)
	for cell: Vector2i in floors.keys():
		if not area.has_point(cell):
			floors.erase(cell)
	for cell: Vector2i in walls.keys():
		if not area.has_point(cell):
			walls.erase(cell)
	objects = objects.filter(func(o: Dictionary) -> bool: return area.has_point(cell_of(o["position"])))
	for object: Dictionary in objects:
		object["points"] = (object["points"] as Array).filter(func(p: Vector2) -> bool: return area.has_point(cell_of(p)))
	emit_changed()


func cell_of(at: Vector2) -> Vector2i:
	return Vector2i((at / CELL).floor())


func center_of(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## 這一格的物件是第幾個（沒有＝-1）
func object_at(cell: Vector2i) -> int:
	for i: int in objects.size():
		if cell_of(objects[i]["position"]) == cell:
			return i
	return -1


func count_of(scene: String) -> int:
	return objects.filter(func(o: Dictionary) -> bool: return o["scene"] == scene).size()


## 腳本有錯（不能用）的物件場景（沒有＝空字串）
func broken_scene() -> String:
	for object: Dictionary in objects:
		var node: Node = (load(object["scene"]) as PackedScene).instantiate()
		var script: Script = node.get_script()
		var bad: bool = script != null and not script.can_instantiate()
		node.free()
		if bad:
			return object["scene"]
	return ""


## 少了什麼不能玩
func problem() -> String:
	if count_of(PLAYER) != 1:
		return "要放一個玩家"
	if count_of(EXIT) == 0:
		return "至少要放一個出口"
	if objects.any(func(o: Dictionary) -> bool: return o["scene"] == EXIT and o["values"]["open_when"] == 1 and (o["values"]["targets"] as Array).is_empty()):
		return "出口選「指定」，要勾至少一個目標"
	if walls.is_empty():
		return "要畫牆（外面要圍起來）"
	return ""


# ---- 畫格子 ----

## 畫一格（tile）。erase＝擦掉：牆類只擦牆；地板類連牆一起擦（變成房子外面）
func paint(cell: Vector2i, tile: int, erase: bool) -> void:
	if not Rect2i(Vector2i.ZERO, size).has_point(cell):
		return
	if is_floor(tile):
		walls.erase(cell)
		if erase:
			floors.erase(cell)
		else:
			floors[cell] = tile
	elif erase:
		walls.erase(cell)
	else:
		walls[cell] = tile
		if not floors.has(cell):
			floors[cell] = Tile.WOOD


static func is_floor(tile: int) -> bool:
	return tile == Tile.WOOD or tile == Tile.TILES or tile == Tile.SWAMP


## 這一格看起來是什麼（油漆桶用）
func tile_at(cell: Vector2i) -> int:
	return walls.get(cell, floors.get(cell, -1))


## 油漆桶：把 from 相連、看起來一樣的一整塊換成 tile。回傳換了幾格
func fill(from: Vector2i, tile: int, erase: bool) -> int:
	var area: Rect2i = Rect2i(Vector2i.ZERO, size)
	var target: int = tile_at(from)
	if not area.has_point(from) or (target == tile and not erase) or (erase and target != tile):
		return 0
	var cells: Dictionary[Vector2i, bool] = {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if area.has_point(cell + step) and not cells.has(cell + step) and tile_at(cell + step) == target:
				cells[cell + step] = true
				queue.append(cell + step)
	for cell: Vector2i in cells:
		paint(cell, tile, erase)
	return cells.size()


# ---- 物件 ----

## 加一個物件（預設值＋values）。回傳第幾個
func add_object(scene: String, at: Vector2, base_name: String, values: Dictionary = {}) -> int:
	var object: Dictionary = {"name": _free_name(base_name), "scene": scene, "position": at, "values": defaults_of(scene), "points": [], "dropper": {}}
	for key: String in values:
		object["values"][key] = values[key]
	objects.append(object)
	return objects.size() - 1


func _free_name(text: String) -> String:
	var result: String = text
	var n: int = 2
	while objects.any(func(o: Dictionary) -> bool: return o["name"] == result):
		result = "%s%d" % [text, n]
		n += 1
	return result


## 叫這個名字的物件（沒有＝空的）
func object_named(text: String) -> Dictionary:
	for object: Dictionary in objects:
		if object["name"] == text:
			return object
	return {}


## 一種場景可以改的欄位
static func fields_of(scene: String) -> Array[Dictionary]:
	var node: Node = (load(scene) as PackedScene).instantiate()
	var result: Array[Dictionary] = LevelEditorForm.fields_of(node, [], ["target_group"])
	node.free()
	for field: Dictionary in result:
		field["label"] = LABELS.get(field["name"], field["label"])
	return result


static func defaults_of(scene: String) -> Dictionary:
	var node: Node = (load(scene) as PackedScene).instantiate()
	var result: Dictionary = values_of(node)
	node.free()
	return result


static func values_of(node: Node) -> Dictionary:
	var result: Dictionary = {}
	for field: Dictionary in LevelEditorForm.fields_of(node, [], ["target_group"]):
		result[field["name"]] = node.get(field["name"])
	if node is Exit:
		result["targets"] = []
	return result


## 目標（寶物、任務點……）的名字：場景在 objectives 群組裡，或腳本有 completed signal
func objective_names() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for object: Dictionary in objects:
		var node: Node = (load(object["scene"]) as PackedScene).instantiate()
		if node.has_signal("completed"):
			result.append(object["name"])
		node.free()
	return result


# ---- 讀寫關卡場景 ----

## 讀關卡。不是追逐關卡（沒有 Floor、Walls）＝null
static func read(path: String) -> ChaseMap:
	if not ResourceLoader.exists(path):
		return null
	var root: Node = (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene).instantiate()
	var map: ChaseMap = null
	if root.get_node_or_null("Floor") is TileMapLayer and root.get_node_or_null("Walls") is TileMapLayer:
		map = ChaseMap.new()
		map.map_name = path.get_file().get_basename()
		map._read(root)
	root.free()
	return map


func _read(root: Node) -> void:
	var floor_layer: TileMapLayer = root.get_node("Floor")
	var wall_layer: TileMapLayer = root.get_node("Walls")
	for cell: Vector2i in floor_layer.get_used_cells():
		floors[cell] = floor_layer.get_cell_atlas_coords(cell).x
	for cell: Vector2i in wall_layer.get_used_cells():
		walls[cell] = wall_layer.get_cell_atlas_coords(cell).x
	size = floor_layer.get_used_rect().merge(wall_layer.get_used_rect()).end.max(Vector2i(4, 4))
	for child: Node in root.get_children():
		if not is_object(child):
			continue
		var values: Dictionary = values_of(child)
		if child is Exit:
			for target: Node in (child as Exit).targets:
				if target != null:
					values["targets"].append(String(target.name))
		var object: Dictionary = {"name": String(child.name), "scene": child.scene_file_path, "position": (child as Node2D).position, "values": values, "points": [], "dropper": {}}
		for part: Node in child.get_children():
			if part is Marker2D:
				object["points"].append((child as Node2D).position + (part as Marker2D).position)
			elif part.scene_file_path == DROPPER:
				object["dropper"] = values_of(part)
		objects.append(object)
	var dark: Node = root.get_node_or_null("Darkness")
	settings["dark"] = dark != null
	if dark != null:
		for field: String in DARKNESS_FIELDS:
			settings[field] = dark.get(field)
	var camera: FollowCamera = root.get_node_or_null("FollowCamera") as FollowCamera
	if camera != null:
		settings["follow"] = camera.follow
		settings["zoom"] = camera.zoom.x


## 直接放在關卡底下的物件（尋路地圖、黑暗、鏡頭不算）
static func is_object(node: Node) -> bool:
	return node is Node2D and not node.scene_file_path.is_empty() and not NOT_OBJECTS.has(node.scene_file_path)


## 做出關卡（不放進場景樹）。base＝從哪個場景改（其他節點照它的）
func build(base: String, state: PackedScene.GenEditState = PackedScene.GEN_EDIT_STATE_DISABLED) -> Node:
	var root: Node = (load(base) as PackedScene).instantiate(state)
	var fresh: bool = base == TEMPLATE and map_name != TEMPLATE.get_file().get_basename()   # 新關卡：範例的物件都不要
	_write_layer(root.get_node("Floor"), floors)
	_write_layer(root.get_node("Walls"), walls)
	var wanted: Dictionary[String, Dictionary] = {}
	for object: Dictionary in objects:
		wanted[object["name"]] = object
	for child: Node in root.get_children():
		if is_object(child) and (fresh or not wanted.has(String(child.name)) or wanted[String(child.name)]["scene"] != child.scene_file_path):
			root.remove_child(child)
			child.free()
	for object: Dictionary in objects:
		var node: Node2D = root.get_node_or_null(String(object["name"])) as Node2D
		if node == null:
			node = (load(object["scene"]) as PackedScene).instantiate(_part(state))
			root.add_child(node)
			node.name = object["name"]
			node.owner = root
		node.position = object["position"]
		_write_values(node, object["values"])
		_write_points(node, object["points"], root)
		_write_dropper(node, object["dropper"], root, state)
	for object: Dictionary in objects:
		if object["values"].has("targets"):                       # 出口「指定」的目標：物件都放好才連得到
			var targets: Array[Node] = []
			for target: String in object["values"]["targets"]:
				if root.has_node(target):
					targets.append(root.get_node(target))
			root.get_node(String(object["name"])).set("targets", targets)
	_write_settings(root, state)
	return root


## 存成關卡場景
func write(path: String) -> Error:
	if not OS.has_feature("editor"):
		return ERR_UNAVAILABLE                                    # 匯出的遊戲不能存
	if not broken_scene().is_empty():
		return ERR_SCRIPT_FAILED                                  # 腳本有錯的物件讀不到數值，存了會弄丟
	var root: Node = build(path if ResourceLoader.exists(path) else TEMPLATE, PackedScene.GEN_EDIT_STATE_MAIN)
	if not ResourceLoader.exists(path):
		root.name = path.get_file().get_basename().to_pascal_case().validate_node_name()
	var scene: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else PackedScene.new()
	var error: Error = scene.pack(root)
	root.free()
	return LevelMaker.save_scene(scene, path) if error == OK else error


## 試玩用（不存檔）
func packed() -> PackedScene:
	var base: String = "res://examples/chase/levels/%s.tscn" % map_name.validate_filename()
	var root: Node = build(base if ResourceLoader.exists(base) else TEMPLATE)
	var scene: PackedScene = PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


static func _part(state: PackedScene.GenEditState) -> PackedScene.GenEditState:
	return PackedScene.GEN_EDIT_STATE_INSTANCE if state != PackedScene.GEN_EDIT_STATE_DISABLED else state


func _write_layer(layer: TileMapLayer, tiles: Dictionary[Vector2i, int]) -> void:
	for cell: Vector2i in layer.get_used_cells():
		if not tiles.has(cell):
			layer.erase_cell(cell)
	for cell: Vector2i in tiles:
		if layer.get_cell_source_id(cell) < 0 or layer.get_cell_atlas_coords(cell).x != tiles[cell]:
			layer.set_cell(cell, 0, Vector2i(tiles[cell], 0))


func _write_values(node: Node, values: Dictionary) -> void:
	for key: String in values:
		if key != "targets" and node.get(key) != values[key]:
			node.set(key, values[key])


func _write_points(node: Node2D, points: Array, root: Node) -> void:
	var markers: Array[Marker2D] = []
	for child: Node in node.get_children():
		if child is Marker2D:
			markers.append(child)
	while markers.size() > points.size():
		var extra: Marker2D = markers.pop_back()
		node.remove_child(extra)
		extra.free()
	while markers.size() < points.size():
		var marker: Marker2D = Marker2D.new()
		node.add_child(marker)
		marker.name = "PatrolPoint%d" % (markers.size() + 1)
		marker.owner = root
		markers.append(marker)
	for i: int in points.size():
		markers[i].position = (points[i] as Vector2) - node.position


func _write_dropper(node: Node, values: Dictionary, root: Node, state: PackedScene.GenEditState) -> void:
	var dropper: Node = null
	for child: Node in node.get_children():
		if child.scene_file_path == DROPPER:
			dropper = child
	if values.is_empty():
		if dropper != null:
			node.remove_child(dropper)
			dropper.free()
		return
	if dropper == null:
		dropper = (load(DROPPER) as PackedScene).instantiate(_part(state))
		node.add_child(dropper)
		dropper.owner = root
	_write_values(dropper, values)


func _write_settings(root: Node, state: PackedScene.GenEditState) -> void:
	var dark: Node = root.get_node_or_null("Darkness")
	if dark != null and not settings["dark"]:
		root.remove_child(dark)
		dark.free()
	elif settings["dark"]:
		if dark == null:
			dark = (load(DARKNESS) as PackedScene).instantiate(_part(state))
			root.add_child(dark)
			dark.owner = root
		for field: String in DARKNESS_FIELDS:
			if dark.get(field) != settings[field]:
				dark.set(field, settings[field])
	var camera: FollowCamera = root.get_node_or_null("FollowCamera") as FollowCamera
	if camera == null:
		return
	camera.follow = settings["follow"]
	camera.zoom = Vector2.ONE * float(settings["zoom"])
	var pixels: Vector2 = Vector2(size * CELL)
	camera.limit_size = (pixels + Vector2(128, 96)).max(Vector2(1280, 720))   # 邊界：整張地圖，至少一個畫面
	if not camera.follow:
		camera.position = pixels / 2.0 + (Vector2(0, 24) if size == Vector2i(36, 18) else Vector2.ZERO)
	else:
		camera.position = pixels / 2.0
