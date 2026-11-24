@tool
class_name TDMap
extends Resource
## 塔防地圖：地形（岩石、沼澤、高地）、出怪口、基地的位置。用地圖編輯器（map_editor.tscn）畫，存在 maps/ 資料夾。
## 關卡裡的 MapLoader 讀它：畫出地形，再告訴尋路地圖哪些格子不能走、哪些走起來慢。
##
## 地形不是一格一格的：每一格再切成 4×4 個小點記「這裡有多少岩石」，畫的時候邊緣會是圓滑的。
## 尋路還是用格子：格子中心在岩石、高地裡＝不能走、在沼澤裡＝走起來慢。
##   ・岩石：怪不能走、不能蓋
##   ・沼澤：怪走得慢、可以蓋
##   ・高地：怪不能走
## 哪種地形上可以蓋塔、蓋牆，每張地圖自己勾（Tower Ground、Wall Ground）：
##   ・迷宮型：空地、沼澤可以蓋塔和牆（會擋路，怪即時繞路）
##   ・固定路線型：只有高地可以蓋塔、哪裡都不能蓋牆（怪走固定的路）
## 蓋在空地、沼澤上會擋路（不能堵死）；高地、岩石本來就不能走，蓋了也不影響怪的路。

## 地形種類（畫的時候用）
enum Kind { ROCK, SWAMP, HIGH }
## 一格算哪種地面（蓋東西的規則用）：空地、沼澤、高地、岩石
enum Ground { FLOOR, SWAMP, HIGH, ROCK }
const GROUND_NAMES: Array[String] = ["空地", "沼澤", "高地", "岩石"]

## 一格幾像素（跟尋路地圖一樣）
const CELL: int = 32
## 每一格切成幾×幾個小點
const SUB: int = 4
## 筆刷邊緣的柔和度（像素）
const FEATHER: float = 6.0
## 同一個小點有好幾種地形時，誰優先（岩石 > 高地 > 沼澤）
const PRIORITY: Array[Kind] = [Kind.ROCK, Kind.HIGH, Kind.SWAMP]

## 地圖名稱
@export var map_name: String = "新地圖"
## 地圖大小（格數）
@export var size: Vector2i = Vector2i(36, 17)
## 出怪口在哪幾格（可以好幾個）
@export var spawn_cells: Array[Vector2i] = [Vector2i(1, 8)]
## 基地在哪幾格（可以好幾個）
@export var base_cells: Array[Vector2i] = [Vector2i(34, 8)]
## 哪些地面上可以蓋塔（勾起來的可以）
@export_flags("空地", "沼澤", "高地", "岩石") var tower_ground: int = 0b0111
## 哪些地面上可以蓋牆（都不勾＝這張地圖沒有牆）
@export_flags("空地", "沼澤", "高地", "岩石") var wall_ground: int = 0b0011
## 岩石：每個小點 0～255（多少岩石）
@export var rock: PackedByteArray = PackedByteArray()
## 沼澤：每個小點 0～255
@export var swamp: PackedByteArray = PackedByteArray()
## 高地：每個小點 0～255
@export var high: PackedByteArray = PackedByteArray()


## 小點有幾×幾個（比格子多一排，因為邊緣兩邊都要有點）
func points() -> Vector2i:
	return size * SUB + Vector2i.ONE


## 確保陣列大小對（新地圖、改了大小、舊地圖沒有高地時）
func ensure() -> void:
	var count: int = points().x * points().y
	if rock.size() != count:
		rock.resize(count)
	if swamp.size() != count:
		swamp.resize(count)
	if high.size() != count:
		high.resize(count)


## 某種地形的資料
func data(kind: Kind) -> PackedByteArray:
	match kind:
		Kind.ROCK: return rock
		Kind.SWAMP: return swamp
	return high


## 某個小點的值（0～1）
func value(kind: Kind, point: Vector2i) -> float:
	var p: Vector2i = points()
	if point.x < 0 or point.y < 0 or point.x >= p.x or point.y >= p.y:
		return 0.0
	var layer: PackedByteArray = data(kind)
	if layer.size() != p.x * p.y:
		return 0.0
	return layer[point.y * p.x + point.x] / 255.0


## 某個位置（地圖裡的像素座標）的值（0～1），在小點之間取平均
func sample(kind: Kind, at: Vector2) -> float:
	var step: float = float(CELL) / SUB
	var f: Vector2 = at / step
	var i: Vector2i = Vector2i(floori(f.x), floori(f.y))
	var t: Vector2 = f - Vector2(i)
	var top: float = lerpf(value(kind, i), value(kind, i + Vector2i(1, 0)), t.x)
	var bottom: float = lerpf(value(kind, i + Vector2i(0, 1)), value(kind, i + Vector2i(1, 1)), t.x)
	return lerpf(top, bottom, t.y)


# ---- 畫 ----

## 圓形筆刷（erase＝擦掉）。畫一種地形會順便擦掉那裡的其他地形
func paint(kind: Kind, center: Vector2, radius: float, erase: bool = false) -> void:
	var bounds: Rect2 = Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	_apply(kind, bounds, func(at: Vector2) -> float: return radius - at.distance_to(center), erase)


## 矩形（rect 是地圖裡的像素座標）
func paint_rect(kind: Kind, rect: Rect2, erase: bool = false) -> void:
	rect = rect.abs()
	_apply(kind, rect, func(at: Vector2) -> float:
		return minf(minf(at.x - rect.position.x, rect.end.x - at.x), minf(at.y - rect.position.y, rect.end.y - at.y)), erase)


## 橢圓（剛好塞進 rect）
func paint_ellipse(kind: Kind, rect: Rect2, erase: bool = false) -> void:
	rect = rect.abs()
	var center: Vector2 = rect.get_center()
	var radii: Vector2 = (rect.size / 2.0).max(Vector2(1, 1))
	_apply(kind, rect, func(at: Vector2) -> float:
		var n: float = ((at - center) / radii).length()            # 1＝剛好在邊上
		return (1.0 - n) * minf(radii.x, radii.y), erase)


## 油漆桶：從 at 開始，把相連、地形一樣的一整塊換成 kind（erase：那一塊是 kind 的話擦掉）。回傳塗了幾個小點
func fill(kind: Kind, at: Vector2, erase: bool = false) -> int:
	ensure()
	var p: Vector2i = points()
	var step: float = float(CELL) / SUB
	var start: Vector2i = Vector2i(roundi(at.x / step), roundi(at.y / step))
	if start.x < 0 or start.y < 0 or start.x >= p.x or start.y >= p.y:
		return 0
	var target: int = _class_at(start.y * p.x + start.x)
	if erase and target != kind:
		return 0                                                  # 擦的時候只擦點到的那種地形
	if not erase and target == kind:
		return 0                                                  # 已經是這種地形
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(p.x * p.y)
	var queue: Array[Vector2i] = [start]
	visited[start.y * p.x + start.x] = 1
	var count: int = 0
	while not queue.is_empty():
		var point: Vector2i = queue.pop_back()
		var index: int = point.y * p.x + point.x
		for k: Kind in PRIORITY:
			if erase:
				if k == kind:
					_set_value(k, index, 0)
			else:
				_set_value(k, index, 255 if k == kind else 0)
		count += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = point + d
			if next.x < 0 or next.y < 0 or next.x >= p.x or next.y >= p.y:
				continue
			var next_index: int = next.y * p.x + next.x
			if visited[next_index] == 0 and _class_at(next_index) == target:
				visited[next_index] = 1
				queue.append(next)
	emit_changed()
	return count


## 這個小點算哪種地形（-1＝空地）
func _class_at(index: int) -> int:
	for k: Kind in PRIORITY:
		if _get_value(k, index) >= 128:
			return k
	return -1


## 在 bounds 範圍裡，每個小點問 depth（離形狀邊緣多深，正的＝在裡面），邊緣柔和地畫上去
func _apply(kind: Kind, bounds: Rect2, depth: Callable, erase: bool) -> void:
	ensure()
	var step: float = float(CELL) / SUB
	var p: Vector2i = points()
	var grown: Rect2 = bounds.grow(FEATHER)
	var from: Vector2i = Vector2i(floori(grown.position.x / step), floori(grown.position.y / step))
	var to: Vector2i = Vector2i(ceili(grown.end.x / step), ceili(grown.end.y / step))
	for y: int in range(maxi(from.y, 0), mini(to.y + 1, p.y)):
		for x: int in range(maxi(from.x, 0), mini(to.x + 1, p.x)):
			var amount: int = int(clampf(float(depth.call(Vector2(x, y) * step)) / FEATHER + 0.5, 0.0, 1.0) * 255.0)
			if amount <= 0:
				continue
			var index: int = y * p.x + x
			if erase:
				_set_value(kind, index, mini(_get_value(kind, index), 255 - amount))
				continue
			for k: Kind in PRIORITY:
				if k == kind:
					_set_value(k, index, maxi(_get_value(k, index), amount))
				else:
					_set_value(k, index, mini(_get_value(k, index), 255 - amount))
	emit_changed()


## 改地圖大小（格數）：左上角不動，原本畫的保留，超出去的剪掉；出怪口、基地在外面的拿掉
func resize(new_size: Vector2i) -> void:
	new_size = new_size.max(Vector2i(4, 4))
	if new_size == size:
		return
	ensure()
	var old_points: Vector2i = points()
	var old: Array[PackedByteArray] = [rock, swamp, high]
	size = new_size
	rock = PackedByteArray()
	swamp = PackedByteArray()
	high = PackedByteArray()
	ensure()
	var p: Vector2i = points()
	for y: int in mini(p.y, old_points.y):
		for x: int in mini(p.x, old_points.x):
			rock[y * p.x + x] = old[0][y * old_points.x + x]
			swamp[y * p.x + x] = old[1][y * old_points.x + x]
			high[y * p.x + x] = old[2][y * old_points.x + x]
	spawn_cells = spawn_cells.filter(has_cell)
	base_cells = base_cells.filter(has_cell)
	emit_changed()


## 存一份現在的樣子（地圖編輯器的「上一步」用）
func snapshot() -> Dictionary:
	return {
		"size": size, "spawn_cells": spawn_cells.duplicate(), "base_cells": base_cells.duplicate(),
		"tower_ground": tower_ground, "wall_ground": wall_ground,
		"rock": rock.duplicate(), "swamp": swamp.duplicate(), "high": high.duplicate(),
	}


## 變回 snapshot() 存的樣子
func restore(state: Dictionary) -> void:
	size = state["size"]
	spawn_cells = (state["spawn_cells"] as Array[Vector2i]).duplicate()
	base_cells = (state["base_cells"] as Array[Vector2i]).duplicate()
	tower_ground = state["tower_ground"]
	wall_ground = state["wall_ground"]
	rock = (state["rock"] as PackedByteArray).duplicate()
	swamp = (state["swamp"] as PackedByteArray).duplicate()
	high = (state["high"] as PackedByteArray).duplicate()
	emit_changed()


## 全部擦掉
func clear() -> void:
	rock = PackedByteArray()
	swamp = PackedByteArray()
	high = PackedByteArray()
	ensure()
	emit_changed()


# ---- 查 ----

## 這一格是不是岩石（格子中心在岩石裡）
func is_rock(cell: Vector2i) -> bool:
	return sample(Kind.ROCK, cell_center(cell)) >= 0.5


## 這一格是不是高地
func is_high(cell: Vector2i) -> bool:
	return not is_rock(cell) and sample(Kind.HIGH, cell_center(cell)) >= 0.5


## 這一格是不是沼澤
func is_swamp(cell: Vector2i) -> bool:
	return not is_rock(cell) and not is_high(cell) and sample(Kind.SWAMP, cell_center(cell)) >= 0.5


## 這一格算哪種地面（Ground）
func ground(cell: Vector2i) -> Ground:
	if is_rock(cell):
		return Ground.ROCK
	if is_high(cell):
		return Ground.HIGH
	if is_swamp(cell):
		return Ground.SWAMP
	return Ground.FLOOR


## 某種地面在 flags（tower_ground、wall_ground）裡有沒有勾
static func has_ground(flags: int, which: Ground) -> bool:
	return flags & (1 << which) != 0


## 這種地面能不能走（空地、沼澤可以；蓋在上面就會擋路）
static func is_walkable_ground(which: Ground) -> bool:
	return which == Ground.FLOOR or which == Ground.SWAMP


## 格子中心（地圖裡的像素座標）
func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2(CELL, CELL) / 2.0


## 像素座標在哪一格
func cell_at(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _get_value(kind: Kind, index: int) -> int:
	match kind:
		Kind.ROCK: return rock[index]
		Kind.SWAMP: return swamp[index]
	return high[index]


func _set_value(kind: Kind, index: int, v: int) -> void:
	match kind:
		Kind.ROCK: rock[index] = v
		Kind.SWAMP: swamp[index] = v
		Kind.HIGH: high[index] = v


# ---- 轉成文字（core/level_editor 的 MapText） ----

func text_letters() -> Dictionary:
	return {".": Ground.FLOOR, "~": Ground.SWAMP, "^": Ground.HIGH, "#": Ground.ROCK}


func text_kind(cell: Vector2i) -> int:
	return ground(cell)


func set_text_kind(cell: Vector2i, which: int) -> void:
	var rect: Rect2 = Rect2(cell * CELL, Vector2(CELL, CELL))
	match which:
		Ground.SWAMP: paint_rect(Kind.SWAMP, rect)
		Ground.HIGH: paint_rect(Kind.HIGH, rect)
		Ground.ROCK: paint_rect(Kind.ROCK, rect)
		_:
			for kind: Kind in PRIORITY:
				paint_rect(kind, rect, true)


func text_fields() -> Array[String]:
	return ["spawn_cells", "base_cells"]
