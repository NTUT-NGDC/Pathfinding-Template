class_name ChaseView
extends Node2D
## 編輯器裡看到的關卡：地板、牆（真的 TileMapLayer）和物件（真的場景，不會動）。

const TILESET: TileSet = preload("res://addons/ngdc_pathfinding/grid/tileset/tileset.tres")

var map: ChaseMap:
	set(value):
		if map != null and map.changed.is_connected(refresh):
			map.changed.disconnect(refresh)
		map = value
		if map != null:
			map.changed.connect(refresh)
		refresh()

var _floor: TileMapLayer
var _walls: TileMapLayer
var _objects: Node2D
## 上次畫的樣子（一樣就不用重做）
var _drawn_floors: Dictionary = {}
var _drawn_walls: Dictionary = {}
var _drawn_objects: Array = []


func _ready() -> void:
	_floor = _layer()
	_walls = _layer()
	_objects = Node2D.new()
	_objects.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_objects)
	refresh()


func _layer() -> TileMapLayer:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = TILESET
	layer.collision_enabled = false
	add_child(layer)
	return layer


func refresh() -> void:
	if map == null or _floor == null:
		return
	if _drawn_floors != map.floors:
		_fill(_floor, map.floors)
		_drawn_floors = map.floors.duplicate()
	if _drawn_walls != map.walls:
		_fill(_walls, map.walls)
		_drawn_walls = map.walls.duplicate()
	if _drawn_objects != map.objects:
		_drawn_objects = map.objects.duplicate(true)
		show_objects(true)
	queue_redraw()


func _fill(layer: TileMapLayer, tiles: Dictionary[Vector2i, int]) -> void:
	layer.clear()
	for cell: Vector2i in tiles:
		layer.set_cell(cell, 0, Vector2i(tiles[cell], 0))


## 擺出物件；on＝false 全部拿掉（試玩時，才不會被當成關卡裡的東西）
func show_objects(on: bool) -> void:
	for child: Node in _objects.get_children():
		(child as Node2D).hide()
		child.queue_free()                                        # 不能馬上拿掉：它的 _ready 可能還有延後執行的
	if not on:
		_drawn_objects = []
		return
	for object: Dictionary in map.objects:
		var node: Node2D = (load(object["scene"]) as PackedScene).instantiate()
		for key: String in object["values"]:
			if key != "targets":
				node.set(key, object["values"][key])
		node.position = object["position"]
		if node is ChaseAI:
			(node as ChaseAI).show_cone = false                   # 視野由編輯器畫
		_objects.add_child(node)
		if node is Exit:
			node.set_deferred("is_open", false)                  # 沒有目標會自己打開，編輯器裡看關著的樣子
			node.queue_redraw.call_deferred()
		for group: StringName in node.get_groups():
			if not String(group).begins_with("_"):
				node.remove_from_group(group)                     # 只是看的，不要被當成場上的


func _draw() -> void:
	if map == null:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(map.size * ChaseMap.CELL)), Color("26262b"))
	draw_rect(Rect2(Vector2.ZERO, Vector2(map.size * ChaseMap.CELL)), Color(1, 1, 1, 0.2), false, 2.0)
