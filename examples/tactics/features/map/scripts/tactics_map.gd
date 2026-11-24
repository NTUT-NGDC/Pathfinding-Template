@tool
class_name TacticsMap
extends Resource
## 戰棋的一張地圖：地形、我方起點、目標格、物資、敵人小隊，還有這一關的規則（隊伍、勝利條件……）。
## 用 map_editor/map_editor.tscn 畫（打開按 F6），存成 maps/名稱.tres。
##
## 地形跟塔防一樣不是一格一格的：每一格再切成 4×4 個小點記「這裡有多少牆（沼澤、森林、高地）」，畫的時候邊緣是圓滑的；
## 照格子畫（paint_cells）邊緣就剛好在格子線上，兩種可以混用。
## 規則還是看格子：格子中心在哪種地形裡，那一格就算哪種。

# 加一種地形：Kind 最後面加一個，下面到 KIND_DEFENSE 每一張表都加一項，加一個同名的 @export_storage 欄位；
# 長相在 tactics_terrain.gd 的 COLORS、EDGES、_draw_details()；擋路、擋視線在 tactics_level.gd 的 _build_grid()；
# 編輯器的工具在 map_editor/scripts/tactics_editor.gd 的 Tool（照順序插在 HIGH 後面）
enum Kind { PLAIN, WALL, SWAMP, FOREST, HIGH }
enum Win { ALL, BOSS, GOAL }

const CELL: int = 32
## 每一格切成幾×幾個小點
const SUB: int = 4
## 兩個小點差幾像素
const STEP: float = float(CELL) / SUB
## 筆刷邊緣的柔和度（像素）
const FEATHER: float = 6.0
## 同一個小點有好幾種地形時誰優先（畫的時候反過來，優先的蓋在上面）
const LAYERS: Array[Kind] = [Kind.WALL, Kind.HIGH, Kind.FOREST, Kind.SWAMP]
## 存檔的欄位名字（順序跟 Kind 一樣，空地不用存）
const LAYER_FIELDS: Array[String] = ["", "wall", "swamp", "forest", "high"]
const KIND_NAMES: Array[String] = ["空地", "牆", "沼澤", "森林", "高地"]
## 轉成文字時的字（MapText）
const KIND_LETTERS: Array[String] = [".", "#", "~", "f", "^"]
## 走進去花多少移動力（牆不能走，會飛的不管地形）
const KIND_COSTS: Array[float] = [1.0, 1.0, 3.0, 2.0, 2.0]
## 站在上面多多少防禦
const KIND_DEFENSE: Array[int] = [0, 0, 0, 1, 0]
const WIN_NAMES: Array[String] = ["打倒全部小隊", "打倒首領小隊", "隊長走到目標格"]

## 地圖名稱
@export var map_name: String = "新地圖"
## 地圖大小（格數）
@export var size: Vector2i = Vector2i(40, 22)
## 地形：每個小點 0～255（多少牆、沼澤、森林、高地）
@export_storage var wall: PackedByteArray = PackedByteArray()
@export_storage var swamp: PackedByteArray = PackedByteArray()
@export_storage var forest: PackedByteArray = PackedByteArray()
@export_storage var high: PackedByteArray = PackedByteArray()
## 我方隊伍從哪裡開始
@export var start_cell: Vector2i = Vector2i(2, 10)
## 目標格（勝利條件選「走到目標格」時用）
@export var goal_cells: Array[Vector2i] = []
## 地上的營地物資
@export var supply_cells: Array[Vector2i] = []
## 寶箱：格子 → 裡面有幾份營地物資
@export var chests: Dictionary[Vector2i, int] = {}
## 可以招募的同伴：格子 → 棋子場景
@export var allies: Dictionary[Vector2i, String] = {}
## 敵人小隊
@export var squads: Array[TacticsSquad] = []

@export_group("規則")
## 這一關固定的隊伍（棋子場景，可以重複）。空的＝用玩家的隊伍池（TacticsPool）
@export var party: Array[String] = []
## 過關後加入隊伍池的人（每一關只給一次）
@export var rewards: Array[String] = []
## 出發前讓玩家編隊（選誰、排順序、選陣形）
@export var choose_party: bool = true
## 編隊時最多帶幾人（0＝全部都能帶）
@export_range(0, 30, 1) var party_max: int = 0
## 一場戰鬥最多上場幾隻（0＝不限）
@export_range(0, 30, 1) var party_size: int = 0
## 整隊走時的陣形
@export_enum("一列", "橫排", "箭頭", "圍一圈") var formation: int = 0
## 可以分開走（按 Tab 切換，一次控制一個人）
@export var allow_split: bool = true
## 一開始就是分開走
@export var start_split: bool = false
## 分開走時，離被發現的人幾格以內（走路距離）一起布陣；更遠的會趕來支援
@export_range(1, 60, 1, "suffix:格") var join_range: int = 10
## 怎樣算贏
@export_enum("打倒全部小隊", "打倒首領小隊", "隊長走到目標格") var win: int = 0
## 戰鬥一開始是自動（取消打勾＝回合制）。戰鬥中隨時可以切換
@export var auto_battle: bool = true
## 擲骰子：每次攻擊擲一顆六面骰，1 失手、6 傷害加倍（像 TRPG；預設關）
@export var dice: bool = false
## 一開始有幾份營地物資
@export_range(0, 20, 1) var supplies: int = 1
## 紮營一次回復幾成血
@export_range(0.1, 1.0, 0.05) var camp_heal: float = 0.5
## 倒下的人打贏之後用 1 滴血站起來（取消打勾＝倒下就離隊）
@export var revive: bool = true


## 每一格算哪種地形（查表用，畫過就重算）
var _kinds: PackedByteArray = PackedByteArray()


## 小點有幾×幾個（比格子多一排，因為邊緣兩邊都要有點）
func points() -> Vector2i:
	return size * SUB + Vector2i.ONE


## 補齊地形資料（新地圖、改大小）
func ensure() -> void:
	var count: int = points().x * points().y
	for kind: Kind in LAYERS:
		if layer(kind).size() != count:
			var fresh: PackedByteArray = layer(kind).duplicate()
			fresh.resize(count)
			_set_layer(kind, fresh)


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## 這一格是什麼地形（地圖外面當作牆）：看格子中心
func kind_at(cell: Vector2i) -> Kind:
	if not has_cell(cell):
		return Kind.WALL
	if _kinds.size() != size.x * size.y:
		_update_kinds()
	return _kinds[cell.y * size.x + cell.x] as Kind


func _update_kinds() -> void:
	ensure()
	var width: int = points().x
	var kinds: PackedByteArray = PackedByteArray()
	kinds.resize(size.x * size.y)
	for y: int in size.y:
		for x: int in size.x:
			kinds[y * size.x + x] = _kind_of_point((y * SUB + SUB / 2) * width + x * SUB + SUB / 2)
	_kinds = kinds


func cell_at(at: Vector2) -> Vector2i:
	return Vector2i((at / CELL).floor())


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL) + Vector2(CELL, CELL) / 2.0


## 某種地形的資料
func layer(kind: Kind) -> PackedByteArray:
	return get(LAYER_FIELDS[kind])


func _set_layer(kind: Kind, data: PackedByteArray) -> void:
	set(LAYER_FIELDS[kind], data)
	_kinds = PackedByteArray()


## 某個位置（地圖裡的像素座標）有多少這種地形（0～1），在小點之間取平均。0.5 以上＝在裡面
func sample(kind: Kind, at: Vector2) -> float:
	var f: Vector2 = at / STEP
	var i: Vector2i = Vector2i(f.floor())
	var t: Vector2 = f - Vector2(i)
	var top: float = lerpf(_value(kind, i), _value(kind, i + Vector2i(1, 0)), t.x)
	var bottom: float = lerpf(_value(kind, i + Vector2i(0, 1)), _value(kind, i + Vector2i(1, 1)), t.x)
	return lerpf(top, bottom, t.y)


func _value(kind: Kind, point: Vector2i) -> float:
	var p: Vector2i = points()
	if point.x < 0 or point.y < 0 or point.x >= p.x or point.y >= p.y:
		return 1.0 if kind == Kind.WALL else 0.0                  # 地圖外面當作牆
	return layer(kind)[point.y * p.x + point.x] / 255.0


## 這個小點算哪種地形
func _kind_of_point(index: int) -> Kind:
	for kind: Kind in LAYERS:
		if layer(kind)[index] >= 128:
			return kind
	return Kind.PLAIN


# ---- 畫（畫一種地形會擦掉那裡的其他地形，畫「空地」就是擦掉） ----

## 圓形筆刷（像素座標）
func paint(kind: Kind, center: Vector2, radius: float) -> void:
	_apply(kind, Rect2(center, Vector2.ZERO).grow(radius), func(at: Vector2) -> float: return radius - at.distance_to(center))


## 矩形（像素座標）
func paint_rect(kind: Kind, rect: Rect2) -> void:
	rect = rect.abs()
	_apply(kind, rect, func(at: Vector2) -> float:
		return minf(minf(at.x - rect.position.x, rect.end.x - at.x), minf(at.y - rect.position.y, rect.end.y - at.y)))


## 橢圓（剛好塞進 rect，像素座標）
func paint_ellipse(kind: Kind, rect: Rect2) -> void:
	rect = rect.abs()
	var center: Vector2 = rect.get_center()
	var radii: Vector2 = (rect.size / 2.0).max(Vector2.ONE)
	_apply(kind, rect, func(at: Vector2) -> float:
		return (1.0 - ((at - center) / radii).length()) * minf(radii.x, radii.y))   # 1＝剛好在邊上


## 對齊格子的矩形（格子座標）：邊緣剛好在格子線上
func paint_cells(kind: Kind, cells: Rect2i) -> void:
	paint_rect(kind, Rect2(cells.position * CELL, cells.size * CELL))


## 對齊格子的橢圓：中心在橢圓裡的格子才畫
func paint_cell_ellipse(kind: Kind, cells: Rect2i) -> void:
	var radii: Vector2 = Vector2(cells.size) / 2.0
	var center: Vector2 = Vector2(cells.position) + radii
	for y: int in range(cells.position.y, cells.end.y):
		for x: int in range(cells.position.x, cells.end.x):
			if ((Vector2(x, y) + Vector2(0.5, 0.5) - center) / radii).length() <= 1.0:
				paint_cells(kind, Rect2i(x, y, 1, 1))


## 油漆桶：把 at（像素座標）那一整塊相連、一樣的地形換成 kind。回傳換了幾個小點
func fill(kind: Kind, at: Vector2) -> int:
	ensure()
	var p: Vector2i = points()
	var start: Vector2i = Vector2i((at / STEP).round())
	if start.x < 0 or start.y < 0 or start.x >= p.x or start.y >= p.y:
		return 0
	var from: Kind = _kind_of_point(start.y * p.x + start.x)
	if from == kind:
		return 0
	var data: Array[PackedByteArray] = _copy_layers()
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(p.x * p.y)
	seen[start.y * p.x + start.x] = 1
	var todo: Array[Vector2i] = [start]
	var edge: PackedInt32Array = PackedInt32Array()               # 旁邊別的地形：底下也墊一點，中間才不會有縫
	var count: int = 0
	while not todo.is_empty():
		var point: Vector2i = todo.pop_back()
		var index: int = point.y * p.x + point.x
		for i: int in LAYERS.size():
			data[i][index] = 255 if LAYERS[i] == kind else 0
		count += 1
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = point + d
			if next.x < 0 or next.y < 0 or next.x >= p.x or next.y >= p.y:
				continue
			var next_index: int = next.y * p.x + next.x
			if seen[next_index] == 1:
				continue
			if _kind_of_point(next_index) == from:
				seen[next_index] = 1
				todo.append(next)
			else:
				edge.append(next_index)
	if kind != Kind.PLAIN:
		var mine: int = LAYERS.find(kind)
		for index: int in edge:
			data[mine][index] = maxi(data[mine][index], 127)
	_put_layers(data)
	return count


## 在 bounds 範圍裡，每個小點問 depth（離形狀邊緣多深，正的＝在裡面），邊緣柔和地畫上去
func _apply(kind: Kind, bounds: Rect2, depth: Callable) -> void:
	ensure()
	var p: Vector2i = points()
	var grown: Rect2 = bounds.grow(FEATHER)
	var from: Vector2i = Vector2i((grown.position / STEP).floor()).max(Vector2i.ZERO)
	var to: Vector2i = Vector2i((grown.end / STEP).ceil()).min(p - Vector2i.ONE)
	var data: Array[PackedByteArray] = _copy_layers()
	for y: int in range(from.y, to.y + 1):
		for x: int in range(from.x, to.x + 1):
			var amount: int = roundi(clampf(float(depth.call(Vector2(x, y) * STEP)) / FEATHER + 0.5, 0.0, 1.0) * 255.0)
			if amount <= 0:
				continue
			var index: int = y * p.x + x
			for i: int in LAYERS.size():
				if LAYERS[i] == kind:
					data[i][index] = maxi(data[i][index], amount)
				else:
					data[i][index] = mini(data[i][index], 255 - amount)
	_put_layers(data)


func _copy_layers() -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	for kind: Kind in LAYERS:
		result.append(layer(kind).duplicate())
	return result


func _put_layers(data: Array[PackedByteArray]) -> void:
	for i: int in LAYERS.size():
		_set_layer(LAYERS[i], data[i])
	emit_changed()


## 改大小（左上角不動，畫好的保留；跑到外面的東西拿掉）
func resize(to: Vector2i) -> void:
	ensure()
	var old: Array[PackedByteArray] = _copy_layers()
	var before: Vector2i = points()
	size = to.max(Vector2i(8, 6))
	var p: Vector2i = points()
	for i: int in LAYERS.size():
		var data: PackedByteArray = PackedByteArray()
		data.resize(p.x * p.y)
		for y: int in mini(p.y, before.y):
			for x: int in mini(p.x, before.x):
				data[y * p.x + x] = old[i][y * before.x + x]
		_set_layer(LAYERS[i], data)
	start_cell = start_cell.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	goal_cells = goal_cells.filter(has_cell)
	supply_cells = supply_cells.filter(has_cell)
	for cell: Vector2i in chests.keys():
		if not has_cell(cell):
			chests.erase(cell)
	for cell: Vector2i in allies.keys():
		if not has_cell(cell):
			allies.erase(cell)
	for squad: TacticsSquad in squads:
		squad.patrol = squad.patrol.filter(has_cell)
		for i: int in range(squad.members.size() - 1, -1, -1):
			if not has_cell(squad.cells[i]):
				squad.remove_at(i)
	emit_changed()


## 這一格站著哪一隻敵人：[小隊編號, 第幾隻]，沒有＝[-1, -1]
func enemy_at(cell: Vector2i) -> Vector2i:
	for i: int in squads.size():
		var index: int = squads[i].cells.find(cell)
		if index >= 0:
			return Vector2i(i, index)
	return Vector2i(-1, -1)


## 這一關可以用的人：固定的隊伍，沒有就是玩家的隊伍池
func roster() -> Array[String]:
	return party if not party.is_empty() else TacticsPool.units()


## 有什麼問題不能玩（沒問題＝空字串）
func problem() -> String:
	if roster().is_empty():
		return "沒有隊伍：規則頁放固定的隊伍，或「隊伍」頁放起始隊伍"
	if kind_at(start_cell) == Kind.WALL:
		return "我方起點不能在牆上"
	if win == Win.GOAL and goal_cells.is_empty():
		return "勝利條件是走到目標格，要先放目標格"
	if win == Win.BOSS and not squads.any(func(s: TacticsSquad) -> bool: return s.boss and not s.members.is_empty()):
		return "勝利條件是打倒首領，要有一隊勾「首領」"
	if win == Win.ALL and not squads.any(func(s: TacticsSquad) -> bool: return not s.members.is_empty()):
		return "至少要放一隻敵人"
	return ""


# ---- 上一步、下一步 ----

## 現在的樣子（編輯器的上一步、有沒有改過都看這個）
func snapshot() -> Dictionary:
	var state: Dictionary = {
		"size": size,
		"start": start_cell, "goals": goal_cells.duplicate(),
		"supply_cells": supply_cells.duplicate(), "chests": chests.duplicate(), "allies": allies.duplicate(), "squads": squads.map(func(s: TacticsSquad) -> Dictionary: return s.to_data()),
		"party": party.duplicate(), "rewards": rewards.duplicate(), "choose_party": choose_party, "party_max": party_max, "party_size": party_size, "formation": formation, "allow_split": allow_split, "start_split": start_split, "join_range": join_range, "win": win, "auto": auto_battle, "dice": dice,
		"supplies": supplies, "camp_heal": camp_heal, "revive": revive,
	}
	for kind: Kind in LAYERS:
		state[LAYER_FIELDS[kind]] = layer(kind).duplicate()
	return state


func restore(data: Dictionary) -> void:
	size = data["size"]
	for kind: Kind in LAYERS:
		_set_layer(kind, (data[LAYER_FIELDS[kind]] as PackedByteArray).duplicate())
	start_cell = data["start"]
	goal_cells.assign(data["goals"])
	supply_cells.assign(data["supply_cells"])
	chests.assign(data["chests"])
	allies.assign(data["allies"])
	squads.clear()
	for squad: Dictionary in data["squads"]:
		squads.append(TacticsSquad.from_data(squad))
	party.assign(data["party"])
	rewards.assign(data["rewards"])
	for field: String in ["choose_party", "party_max", "party_size", "formation", "allow_split", "start_split", "join_range"]:
		set(field, data[field])
	win = data["win"]
	auto_battle = data["auto"]
	dice = data["dice"]
	supplies = data["supplies"]
	camp_heal = data["camp_heal"]
	revive = data["revive"]
	emit_changed()


## 複製一份（試玩用，不會改到原本的）
func copy() -> TacticsMap:
	var other: TacticsMap = TacticsMap.new()
	other.map_name = map_name
	other.restore(snapshot())
	return other


# ---- 轉成文字（core/level_editor 的 MapText；小隊、規則不在裡面） ----

func text_letters() -> Dictionary:
	var result: Dictionary = {}
	for kind: int in KIND_LETTERS.size():
		result[KIND_LETTERS[kind]] = kind
	return result


func text_kind(cell: Vector2i) -> int:
	return kind_at(cell)


func set_text_kind(cell: Vector2i, kind: int) -> void:
	paint_cells(kind as Kind, Rect2i(cell, Vector2i.ONE))


func text_fields() -> Array[String]:
	return ["start_cell", "goal_cells", "supply_cells"]
