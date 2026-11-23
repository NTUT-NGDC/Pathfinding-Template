@tool
class_name TerrainView
extends Node2D
## 把塔防地圖（TDMap）的地形畫出來：岩石、沼澤、高地，邊緣是圓滑的（不是一格一格的方塊）。
## 地圖編輯器和關卡（MapLoader）都用它畫。

## 要畫的地圖
@export var map: TDMap:
	set(value):
		if map != null and map.changed.is_connected(queue_redraw):
			map.changed.disconnect(queue_redraw)
		map = value
		if map != null:
			map.ensure()
			map.changed.connect(queue_redraw)
		queue_redraw()
## 畫地板（關卡裡地板是 TileMapLayer 畫的，就不用；地圖編輯器要）
@export var draw_floor: bool = false:
	set(value):
		draw_floor = value
		queue_redraw()

const FLOOR_COLOR: Color = Color("cdb48a")
const ROCK_COLOR: Color = Color("6e6259")
const ROCK_EDGE: Color = Color("3e3631")
const SWAMP_COLOR: Color = Color(0.25, 0.42, 0.3, 0.85)
const SWAMP_EDGE: Color = Color("24402c")
const HIGH_COLOR: Color = Color("a3b27a")
const HIGH_EDGE: Color = Color("5d6a3c")
const BORDER_COLOR: Color = Color("3a3028")


func _draw() -> void:
	if map == null:
		return
	var area: Rect2 = Rect2(Vector2.ZERO, Vector2(map.size * TDMap.CELL))
	if _should_draw_floor():
		draw_rect(area, FLOOR_COLOR)
	_draw_layer(map.swamp, SWAMP_COLOR, SWAMP_EDGE)
	_draw_layer(map.high, HIGH_COLOR, HIGH_EDGE)
	_draw_layer(map.rock, ROCK_COLOR, ROCK_EDGE)
	draw_rect(area, BORDER_COLOR, false, 4.0)


func _should_draw_floor() -> bool:
	return draw_floor


## Marching squares：每個小方塊看四個角在不在裡面，切出要填的形狀；邊緣的點照數值內插，所以是圓滑的
func _draw_layer(data: PackedByteArray, fill: Color, edge: Color) -> void:
	var p: Vector2i = map.points()
	if data.size() != p.x * p.y:
		return
	var step: float = float(TDMap.CELL) / TDMap.SUB
	var square: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(step, 0), Vector2(step, step), Vector2(0, step)])
	var offsets: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	var full: PackedColorArray = PackedColorArray([fill])
	for y: int in p.y - 1:
		for x: int in p.x - 1:
			var values: PackedFloat32Array = PackedFloat32Array()
			var inside: int = 0
			for o: Vector2i in offsets:
				var v: float = data[(y + o.y) * p.x + x + o.x] / 255.0
				values.append(v)
				if v >= 0.5:
					inside += 1
			if inside == 0:
				continue
			var origin: Vector2 = Vector2(x, y) * step
			if inside == 4:
				draw_rect(Rect2(origin, Vector2(step, step)), fill)
				continue
			var shape: PackedVector2Array = PackedVector2Array()
			var cut: Array[Vector2] = []                          # 邊緣經過的點（畫邊線用）
			for i: int in 4:
				var j: int = (i + 1) % 4
				var a: float = values[i]
				var b: float = values[j]
				if a >= 0.5:
					shape.append(origin + square[i])
				if (a >= 0.5) != (b >= 0.5):
					var t: float = clampf((0.5 - a) / (b - a), 0.02, 0.98)   # 不要跟角落重疊（重疊的點畫多邊形會出錯）
					var point: Vector2 = origin + square[i].lerp(square[j], t)
					shape.append(point)
					cut.append(point)
			if shape.size() >= 3:
				draw_colored_polygon(shape, fill)
			if cut.size() == 2:
				draw_line(cut[0], cut[1], edge, 2.0)
			elif cut.size() == 4:
				draw_line(cut[0], cut[1], edge, 2.0)
				draw_line(cut[2], cut[3], edge, 2.0)
