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
const DOOR: String = "res://examples/chase/features/door/door.tscn"
const DARKNESS: String = "res://examples/chase/features/darkness/darkness.tscn"
## 每個物件自己的（不是種類的）：方向、巡邏、出口的目標
const PER_OBJECT: Array[String] = ["orientation", "start_angle", "patrol_mode", "patrol_wait", "targets"]
## 註解第一句不適合當名字的，在這裡改（其他的自動用 @export 上面的 ## 註解）
const LABELS: Dictionary[String, String] = {
	"needed": "需要幾個", "patrol_speed": "巡邏速度", "chase_speed": "追擊速度", "search_time": "追丟後找幾秒",
	"remember_last_position": "記住最後看到的", "catch_distance": "多近算抓到", "caught_message": "抓到時的文字", "patrol_mode": "走完巡邏點之後",
	"run_sound_interval": "腳步聲隔幾秒", "bottle_sound_radius": "瓶子聲音多遠", "run_sound_radius": "跑步聲音多遠", "start_bottles": "一開始幾個瓶子",
	"kind": "種類", "required": "算進出口條件", "action": "提示的動詞", "sound_interval": "聲音隔幾秒", "start_open": "一開始開著",
	"sound_radius": "聲音傳多遠", "locked": "上鎖", "key_color": "鑰匙顏色", "cooldown": "冷卻",
	"one_shot": "只用一次", "ai_avoids": "AI 會繞開", "visible_to_player": "看得見", "amount": "一次幾個", "task_name": "遊戲裡叫什麼",
}
const DARKNESS_FIELDS: Array[String] = ["radius", "softness", "darkness"]

static var _defaults: Dictionary[String, Dictionary] = {}
static var _traits: Dictionary[String, PackedStringArray] = {}

var map_name: String = "新關卡"
## 地圖大小（格數）
var size: Vector2i = Vector2i(36, 18)
## 格子 → 圖塊
var floors: Dictionary[Vector2i, int] = {}
var walls: Dictionary[Vector2i, int] = {}
## 物件：{"name", "scene"（哪一種）, "position", "values": {欄位: 值，只記跟種類不一樣的}, "points": 巡邏點（關卡裡的位置）,
## "traits": {特性: {欄位: 值}}，只記這一個自己多的}。看某個欄位現在多少用 value()，改用 set_value()
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


## 有幾個（各種種類都算）
func count_of(base: String) -> int:
	return objects.filter(func(o: Dictionary) -> bool: return is_a(o, base)).size()


## 這個物件是 base 或 base 的種類嗎
static func is_a(object: Dictionary, base: String) -> bool:
	return not object.is_empty() and ChaseKinds.base_of(object["scene"]) == base


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
	if objects.any(func(o: Dictionary) -> bool: return is_a(o, EXIT) and value(o, "open_when") == 1 and (value(o, "targets") as Array).is_empty()):
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


## 門、出口開在這一格：把牆拿掉、補地板。回傳方向（0 橫、1 直），照旁邊的牆
func open_doorway(cell: Vector2i) -> int:
	walls.erase(cell)
	if not floors.has(cell):
		floors[cell] = Tile.WOOD
	return 0 if walls.has(cell + Vector2i.LEFT) and walls.has(cell + Vector2i.RIGHT) else 1


static func is_door(scene: String) -> bool:
	return scene == DOOR or scene == EXIT


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
	var object: Dictionary = {"name": _free_name(base_name), "scene": scene, "position": at, "values": {}, "points": [], "traits": {}}
	for key: String in values:
		set_value(object, key, values[key])
	objects.append(object)
	return objects.size() - 1


## 一個物件的欄位現在是多少（沒有自己改過＝種類的）
static func value(object: Dictionary, field: String) -> Variant:
	return object["values"][field] if (object["values"] as Dictionary).has(field) else defaults_of(object["scene"]).get(field)


## 改一個物件的欄位（改成跟種類一樣就不用記）
static func set_value(object: Dictionary, field: String, to: Variant) -> void:
	if defaults_of(object["scene"]).get(field) == to:
		(object["values"] as Dictionary).erase(field)
	else:
		object["values"][field] = to


## 一個物件全部的欄位
static func all_values(object: Dictionary) -> Dictionary:
	return (object["values"] as Dictionary).merged(defaults_of(object["scene"]))


## 自己改過、跟種類不一樣的欄位（方向、巡邏這種本來就是每個自己的不算）
static func changed_fields(object: Dictionary) -> Array:
	return (object["values"] as Dictionary).keys().filter(func(key: String) -> bool: return not PER_OBJECT.has(key))


## 出口「指定」：要不要算這個目標
static func set_target(object: Dictionary, target: String, on: bool) -> void:
	var targets: Array = (value(object, "targets") as Array).duplicate()
	targets.erase(target)
	if on:
		targets.append(target)
	set_value(object, "targets", targets)


## 換成另一種（自己改過的留著，跟新的種類一樣的就不用記）
static func set_kind(object: Dictionary, scene: String) -> void:
	var own: Dictionary = object["values"]
	object["scene"] = scene
	object["values"] = {}
	for key: String in own:
		if defaults_of(scene).has(key):
			set_value(object, key, own[key])
	for path: String in kind_traits(scene):
		(object["traits"] as Dictionary).erase(path)


## 拿掉一個物件（出口「指定」它的話也拿掉）
func remove_object(index: int) -> void:
	for object: Dictionary in objects:
		if object["values"].has("targets"):
			set_target(object, objects[index]["name"], false)
	objects.remove_at(index)


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


## 一種場景的預設值（讀過的記起來；不要直接改它）
static func defaults_of(scene: String) -> Dictionary:
	if not _defaults.has(scene):
		var node: Node = (load(scene) as PackedScene).instantiate()
		_defaults[scene] = values_of(node)
		node.free()
	return _defaults[scene]


## 這一種本來就有的特性
static func kind_traits(scene: String) -> PackedStringArray:
	if not _traits.has(scene):
		var node: Node = (load(scene) as PackedScene).instantiate()
		var found: PackedStringArray = PackedStringArray()
		for child: Node in node.get_children():
			if ChaseKinds.traits_of(scene).has(child.scene_file_path):
				found.append(child.scene_file_path)
		_traits[scene] = found
		node.free()
	return _traits[scene]


## 種類改了：下次重讀
static func forget() -> void:
	_defaults.clear()
	_traits.clear()


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


# ---- 轉成文字（core/level_editor 的 MapText；物件在 chase_text.gd） ----

func text_letters() -> Dictionary:
	return ChaseText.LETTERS


func text_kind(cell: Vector2i) -> int:
	return tile_at(cell)


func set_text_kind(cell: Vector2i, kind: int) -> void:
	paint(cell, Tile.WOOD if kind < 0 else kind, kind < 0)


func text_help() -> PackedStringArray:
	return ChaseText.HELP


func text_fields() -> PackedStringArray:
	return ChaseText.fields(self)


func text_cells(field: String) -> Array:
	return ChaseText.cells(self, field)


func set_text_cells(field: String, cells: Array) -> void:
	ChaseText.set_cells(self, field, cells)


func text_problem(points: Dictionary) -> String:
	return ChaseText.problem(self, points)


func text_warning() -> String:
	return ChaseText.warning(self)


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
		var scene: String = child.scene_file_path
		var object: Dictionary = {"name": String(child.name), "scene": scene, "position": (child as Node2D).position, "values": {}, "points": [], "traits": {}}
		for key: String in values:
			set_value(object, key, values[key])
		for part: Node in child.get_children():
			if part is Marker2D:
				object["points"].append((child as Node2D).position + (part as Marker2D).position)
			elif ChaseKinds.traits_of(scene).has(part.scene_file_path) and not kind_traits(scene).has(part.scene_file_path):
				object["traits"][part.scene_file_path] = values_of(part)
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
		_write_values(node, all_values(object))
		_write_points(node, object["points"], root)
		_write_traits(node, object, root, state)
	for object: Dictionary in objects:
		if defaults_of(object["scene"]).has("targets"):           # 出口「指定」的目標：物件都放好才連得到
			var targets: Array[Node] = []
			for target: String in value(object, "targets"):
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


## 這一個自己多的特性（種類本來就有的不動）
func _write_traits(node: Node, object: Dictionary, root: Node, state: PackedScene.GenEditState) -> void:
	var wanted: Dictionary = object["traits"]
	for path: String in ChaseKinds.traits_of(object["scene"]):
		if kind_traits(object["scene"]).has(path):
			continue
		var part: Node = null
		for child: Node in node.get_children():
			if child.scene_file_path == path:
				part = child
		if part != null and not wanted.has(path):
			node.remove_child(part)
			part.free()
		elif wanted.has(path):
			if part == null:
				part = (load(path) as PackedScene).instantiate(_part(state))
				node.add_child(part)
				part.owner = root
			_write_values(part, wanted[path])


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
