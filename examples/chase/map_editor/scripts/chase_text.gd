class_name ChaseText
extends RefCounted
## 追逐關卡 ↔ 文字（給 AI 看、畫草稿；轉換在 core/level_editor 的 MapText）。
## 上面是地形，一格一個字；下面一行一種物件：「treasure: 5,3 12,8」＝兩個寶物，在 (5,3) 和 (12,8)。
## 「patrol 10,5: 3,5 12,5」＝站在 (10,5) 的敵人照順序走這些巡邏點。
## 沒移動的物件，自己改過的數值都留著。數值、出口的條件、黑暗不在這裡，用編輯器或直接改關卡 .tscn。

const LETTERS: Dictionary = {"_": -1, ".": ChaseMap.Tile.WOOD, "t": ChaseMap.Tile.TILES, "~": ChaseMap.Tile.SWAMP, "#": ChaseMap.Tile.WALL, "G": ChaseMap.Tile.GLASS, "B": ChaseMap.Tile.BUSH}
const HELP: PackedStringArray = [
	"_ 房子外面　. 地板　t 磁磚　~ 沼澤（走得慢）　# 牆　G 玻璃（看得穿）　B 草叢（走得過、看不穿）",
	"下面一行一種物件，寫 x,y（左上角是 0,0），空的＝沒有。門和出口寫在牆上的格子，會自己開一個缺口",
	"patrol x,y: 那一格的敵人的巡邏點，照順序；敵人移動了，這裡的 x,y 也要改",
]
const PATROL: String = "patrol "
## 編輯器本來就有的：名字、場景、怎麼認、放新的時候還要設什麼
const THINGS: Array[Array] = [
	["player", ChaseMap.PLAYER, {}, {}],
	["exit", ChaseMap.EXIT, {}, {}],
	["treasure", ChaseKinds.FEATURES + "pickup/pickup.tscn", {"kind": "寶物"}, {}],
	["key_red", ChaseKinds.FEATURES + "pickup/pickup.tscn", {"kind": "紅"}, {"required": false}],
	["key_blue", ChaseKinds.FEATURES + "pickup/pickup.tscn", {"kind": "藍"}, {"required": false}],
	["key_yellow", ChaseKinds.FEATURES + "pickup/pickup.tscn", {"kind": "黃"}, {"required": false}],
	["key_green", ChaseKinds.FEATURES + "pickup/pickup.tscn", {"kind": "綠"}, {"required": false}],
	["door", ChaseMap.DOOR, {"locked": false}, {}],
	["door_red", ChaseMap.DOOR, {"locked": true, "key_color": "紅"}, {}],
	["door_blue", ChaseMap.DOOR, {"locked": true, "key_color": "藍"}, {}],
	["door_yellow", ChaseMap.DOOR, {"locked": true, "key_color": "黃"}, {}],
	["door_green", ChaseMap.DOOR, {"locked": true, "key_color": "綠"}, {}],
	["bottle", ChaseKinds.FEATURES + "throwable/bottle.tscn", {}, {}],
]


## 全部可以放的：{名字: THINGS 的一項}。種類的名字＝場景的檔名（killer、generator……），底的名字：敵人是 enemy，其他是檔名
static func things() -> Dictionary[String, Array]:
	var result: Dictionary[String, Array] = {}
	for item: Array in THINGS:
		result[item[0]] = item
	for item: Dictionary in ChaseKinds.classes():
		for path: String in ChaseKinds.paths(item):
			var text: String = "enemy" if path == ChaseMap.ENEMY else path.get_file().get_basename()
			if not result.has(text):
				result[text] = [text, path, {}, {}]
	return result


## 這個物件是哪一種（沒有＝空字串，文字裡不會出現、也不會動到）
static func field_of(object: Dictionary) -> String:
	for item: Array in things().values():
		var same: bool = item[1] == object["scene"]
		for key: String in item[2]:
			same = same and ChaseMap.value(object, key) == item[2][key]
		if same:
			return item[0]
	return ""


static func fields(map: ChaseMap) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray(things().keys())
	for object: Dictionary in map.objects:
		if ChaseMap.is_a(object, ChaseMap.ENEMY):
			result.append(patrol_field(map, object))
	return result


static func patrol_field(map: ChaseMap, enemy: Dictionary) -> String:
	var cell: Vector2i = map.cell_of(enemy["position"])
	return "%s%d,%d" % [PATROL, cell.x, cell.y]


static func cells(map: ChaseMap, field: String) -> Array:
	var found: Array = _objects(map, field)
	if field.begins_with(PATROL):
		return [] if found.is_empty() else (found[0]["points"] as Array).map(map.cell_of)
	return found.map(func(o: Dictionary) -> Vector2i: return map.cell_of(o["position"]))


## 這個欄位說的是哪些物件（patrol＝那一格的敵人）
static func _objects(map: ChaseMap, field: String) -> Array:
	if field.begins_with(PATROL):
		return map.objects.filter(func(o: Dictionary) -> bool: return ChaseMap.is_a(o, ChaseMap.ENEMY) and patrol_field(map, o) == field)
	return map.objects.filter(func(o: Dictionary) -> bool: return field_of(o) == field)


## 同一格的留著，其他的搬過去；不夠就加、太多就拿掉
static func set_cells(map: ChaseMap, field: String, to: Array) -> void:
	if field.begins_with(PATROL):
		if cells(map, field) != to:
			_objects(map, field)[0]["points"] = to.map(map.center_of)
		return
	var left: Array = to.duplicate()
	var moving: Array = []
	for object: Dictionary in _objects(map, field):
		if left.has(map.cell_of(object["position"])):
			left.erase(map.cell_of(object["position"]))
		else:
			moving.append(object)
	var item: Array = things()[field]
	for object: Dictionary in moving:
		if left.is_empty():
			map.remove_object(map.objects.find(object))
			continue
		var cell: Vector2i = left.pop_front()
		object["position"] = map.center_of(cell)
		if ChaseMap.is_door(object["scene"]):
			ChaseMap.set_value(object, "orientation", map.open_doorway(cell))
	for cell: Vector2i in left:
		var values: Dictionary = (item[2] as Dictionary).merged(item[3])
		if ChaseMap.is_door(item[1]):
			values["orientation"] = map.open_doorway(cell)
		map.add_object(item[1], map.center_of(cell), field.to_pascal_case().validate_node_name(), values)


## 文字哪裡寫錯（地圖還沒動之前檢查）
static func problem(map: ChaseMap, points: Dictionary) -> String:
	var known: Dictionary[String, Array] = things()
	var enemies: Array[String] = []
	for field: String in known:
		if ChaseKinds.base_of(known[field][1]) == ChaseMap.ENEMY:
			for cell: Vector2i in points.get(field, cells(map, field)):
				enemies.append("%s%d,%d" % [PATROL, cell.x, cell.y])
	for field: String in points:
		if field.begins_with(PATROL):
			if not enemies.has(field):
				return "%s：那一格沒有敵人" % field
		elif not known.has(field):
			return "沒有「%s」這種東西，可以用：%s" % [field, " ".join(known.keys())]
	if points.has("player") and (points["player"] as Array).size() != 1:
		return "player 要剛好一格"
	return ""


## 還不能玩的地方：少了什麼、放在牆裡、玩家走不到（上鎖的門當作打得開）
static func warning(map: ChaseMap) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if not map.problem().is_empty():
		lines.append(map.problem())
	if map.count_of(ChaseMap.PLAYER) == 1:
		var reached: Dictionary[Vector2i, bool] = {}
		var queue: Array[Vector2i] = []
		for object: Dictionary in map.objects:
			if ChaseMap.is_a(object, ChaseMap.PLAYER):
				queue.append(map.cell_of(object["position"]))
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			if reached.has(cell) or not _walkable(map, cell):
				continue
			reached[cell] = true
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				queue.append(cell + step)
		for object: Dictionary in map.objects:
			var at: Vector2i = map.cell_of(object["position"])
			if not reached.has(at):
				lines.append("%s（%d,%d）%s" % [object["name"], at.x, at.y, "玩家走不到" if _walkable(map, at) else "在牆裡或房子外面"])
	return "、".join(lines)


static func _walkable(map: ChaseMap, cell: Vector2i) -> bool:
	return map.floors.has(cell) and not map.walls.get(cell, -1) in [ChaseMap.Tile.WALL, ChaseMap.Tile.GLASS]
