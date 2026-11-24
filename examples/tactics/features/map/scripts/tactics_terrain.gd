@tool
class_name TacticsTerrain
extends Node2D
## 把戰棋地圖（TacticsMap）畫出來：地形（邊緣圓滑，用程式畫，不用找素材）、目標格、物資、寶箱。編輯器和關卡（TacticsLevel）都用它畫。

## 要畫的地圖
@export var map: TacticsMap:
	set(value):
		if map != null and map.changed.is_connected(queue_redraw):
			map.changed.disconnect(queue_redraw)
		map = value
		if map != null:
			map.ensure()
			map.changed.connect(queue_redraw)
		queue_redraw()

const PLAIN_COLOR: Color = Color("cdb48a")
const PLAIN_COLOR_2: Color = Color("c8af84")
## 順序跟 TacticsMap.Kind 一樣
const COLORS: Array[Color] = [Color("cdb48a"), Color("6e6259"), Color("587a5c"), Color("7f9c5a"), Color("b8a06a")]
const EDGES: Array[Color] = [Color("cdb48a"), Color("3e3631"), Color("2f4a38"), Color("566f3a"), Color("7a6238")]


func _draw() -> void:
	if map == null:
		return
	map.ensure()
	var area: Rect2 = Rect2(Vector2.ZERO, Vector2(map.size * TacticsMap.CELL))
	draw_rect(area, PLAIN_COLOR)
	for y: int in map.size.y:                                     # 淡淡的棋盤格，看得出一格多大
		for x: int in range(y % 2, map.size.x, 2):
			draw_rect(Rect2(Vector2(x, y) * TacticsMap.CELL, Vector2(TacticsMap.CELL, TacticsMap.CELL)), PLAIN_COLOR_2)
	for i: int in range(TacticsMap.LAYERS.size() - 1, -1, -1):    # 優先的最後畫，蓋在上面
		_draw_layer(TacticsMap.LAYERS[i])
	for cell: Vector2i in map.goal_cells:
		var rect: Rect2 = Rect2(Vector2(cell * TacticsMap.CELL), Vector2(TacticsMap.CELL, TacticsMap.CELL))
		draw_rect(rect, Color(1, 0.85, 0.2, 0.35))
		draw_rect(rect.grow(-2), Color(1, 0.85, 0.2), false, 2.0)
	if _draws_supplies():
		for cell: Vector2i in map.supply_cells:
			draw_supply(self, map.cell_center(cell))
		for cell: Vector2i in map.chests:
			draw_chest(self, map.cell_center(cell))
			draw_string(Unit.font(), map.cell_center(cell) + Vector2(8, -6), "×%d" % map.chests[cell], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
	draw_rect(area, Color("3a3028"), false, 4.0)


## 物資要不要由這裡畫（關卡裡是可以撿的東西，自己會畫）
func _draws_supplies() -> bool:
	return true


## Marching squares：每個小方塊看四個角在不在裡面，切出要填的形狀；邊緣的點照數值內插，所以是圓滑的
func _draw_layer(kind: TacticsMap.Kind) -> void:
	var data: PackedByteArray = map.layer(kind)
	if data.count(0) == data.size():
		return                                                    # 這張地圖沒有這種地形
	var p: Vector2i = map.points()
	var step: float = TacticsMap.STEP
	for y: int in p.y - 1:
		var top: int = y * p.x
		if data.slice(top, top + p.x * 2).count(0) == p.x * 2:
			continue                                              # 這一排沒有
		var run: int = -1                                         # 連續的整塊合起來畫一條（比較省）
		var left: int = (1 if data[top] >= 128 else 0) + (1 if data[top + p.x] >= 128 else 0)   # 左邊兩個角有幾個在裡面
		for x: int in p.x - 1:
			var right: int = (1 if data[top + x + 1] >= 128 else 0) + (1 if data[top + p.x + x + 1] >= 128 else 0)
			var inside: int = left + right
			left = right
			if inside == 4:
				if run < 0:
					run = x
				continue
			if run >= 0:
				draw_rect(Rect2(run * step, y * step, (x - run) * step, step), COLORS[kind])
				run = -1
			if inside > 0:
				_draw_edge(kind, Vector2(x, y) * step, PackedByteArray([data[top + x], data[top + x + 1], data[top + p.x + x + 1], data[top + p.x + x]]))
		if run >= 0:
			draw_rect(Rect2(run * step, y * step, (p.x - 1 - run) * step, step), COLORS[kind])
	_draw_details(kind)


## 邊緣的一小塊
func _draw_edge(kind: TacticsMap.Kind, origin: Vector2, corners: PackedByteArray) -> void:
	var step: float = TacticsMap.STEP
	var square: Array[Vector2] = [Vector2.ZERO, Vector2(step, 0), Vector2(step, step), Vector2(0, step)]
	var shape: PackedVector2Array = PackedVector2Array()
	var cut: Array[Vector2] = []                                  # 邊緣經過的點（畫邊線用）
	var deepest: float = 0.0
	var outside: Array[int] = []
	for i: int in 4:
		var j: int = (i + 1) % 4
		var a: float = corners[i]
		var b: float = corners[j]
		if a >= 128.0:
			deepest = maxf(deepest, a)
			shape.append(origin + square[i])
		else:
			outside.append(i)
		if (a >= 128.0) != (b >= 128.0):
			var t: float = clampf((127.5 - a) / (b - a), 0.02, 0.98)   # 不要跟角落重疊（重疊的點畫多邊形會出錯）
			var point: Vector2 = origin + square[i].lerp(square[j], t)
			shape.append(point)
			cut.append(point)
	if deepest < 140.0:                                           # 剛好在格子線上（照格子畫的）：不用填，轉角畫成直角
		if outside.size() == 1:
			var inner: Vector2 = origin + square[(outside[0] + 2) % 4]
			for side: int in [1, 3]:
				draw_line(inner, origin + square[(outside[0] + side) % 4], EDGES[kind], 2.0)
			return
		if outside.size() == 2 and (outside[1] - outside[0]) % 2 == 1:
			draw_line(origin + square[(outside[0] + 2) % 4], origin + square[(outside[1] + 2) % 4], EDGES[kind], 2.0)
			return
	elif shape.size() >= 3:
		draw_colored_polygon(shape, COLORS[kind])
	for i: int in range(0, cut.size() - 1, 2):
		draw_line(cut[i], cut[i + 1], EDGES[kind], 2.0)


## 每一格的小裝飾（草、樹、山紋）：整個在地形裡才畫
func _draw_details(kind: TacticsMap.Kind) -> void:
	if kind == TacticsMap.Kind.WALL:
		return
	var spots: Array[Vector2] = [Vector2(10, 12), Vector2(22, 11), Vector2(16, 23)]
	for y: int in map.size.y:
		for x: int in map.size.x:
			if map.kind_at(Vector2i(x, y)) != kind:
				continue
			for spot: Vector2 in spots:
				var at: Vector2 = Vector2(x, y) * TacticsMap.CELL + spot
				if map.sample(kind, at) < 0.8:
					continue
				match kind:
					TacticsMap.Kind.SWAMP:
						draw_arc(at, 3.5, PI, TAU, 8, EDGES[kind], 2.0)
					TacticsMap.Kind.FOREST:
						draw_circle(at, 7.0, Color("4d6b38"))
						draw_circle(at - Vector2(1, 2), 5.0, Color("5f8246"))
					TacticsMap.Kind.HIGH:
						draw_polyline(PackedVector2Array([at + Vector2(-4, 2), at + Vector2(0, -3), at + Vector2(4, 2)]), EDGES[kind], 1.5)


## 一袋物資
static func draw_supply(on: CanvasItem, at: Vector2) -> void:
	on.draw_circle(at + Vector2(0, 2), 9.0, Color("5a3d22"))
	on.draw_circle(at + Vector2(0, 2), 7.5, Color("b07a42"))
	on.draw_rect(Rect2(at + Vector2(-4, -10), Vector2(8, 5)), Color("8a5a2e"))
	on.draw_line(at + Vector2(-5, -5), at + Vector2(5, -5), Color("f0d9a0"), 2.0)


## 寶箱（opened＝打開過了）
static func draw_chest(on: CanvasItem, at: Vector2, opened: bool = false) -> void:
	on.draw_rect(Rect2(at + Vector2(-11, -2), Vector2(22, 12)), Color("7a4a22"))
	on.draw_rect(Rect2(at + Vector2(-9, 0), Vector2(18, 8)), Color("2b1c10") if opened else Color("9a6330"))
	on.draw_rect(Rect2(at + Vector2(-11, -13 if opened else -9), Vector2(22, 7)), Color("a8702f"))
	on.draw_rect(Rect2(at + Vector2(-11, -2), Vector2(22, 12)), Color("3e2712"), false, 1.5)
	if not opened:
		on.draw_rect(Rect2(at + Vector2(-3, -4), Vector2(6, 7)), Color("f0d060"))
