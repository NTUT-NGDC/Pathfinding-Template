class_name BaseGroup
extends Node
## 基地規則：有好幾個基地時，怪走到基地要怎麼扣血、什麼時候輸。關卡裡放一個就好。
## 它會自己接所有生怪器的 reached_goal（怪身上記著它要去哪個基地）。
##   ・共用一條血：所有基地扣同一條血，扣光就輸（畫面上只有一個血量）
##   ・各自的血：一個被打爆就輸
##   ・各自的血：全部被打爆才輸（被打爆的基地消失，怪改去別的基地）
## 各自的血時，每個基地的血量看基地自己的 Max Health。

## 血量變了、基地少了
signal changed()

## 規則
@export_enum("共用一條血", "各自的血：一個被打爆就輸", "各自的血：全部被打爆才輸") var mode: int = 0
## 共用一條血時，總共幾滴血
@export_range(1, 100, 1) var shared_max_health: int = 10

## 共用的血量
var shared_health: int = 0


func _enter_tree() -> void:
	add_to_group("base_group")


func _ready() -> void:
	shared_health = shared_max_health
	_connect.call_deferred()


func _connect() -> void:
	for node: Node in get_tree().get_nodes_in_group("spawners"):
		var spawner: Spawner = node as Spawner
		if not spawner.reached_goal.is_connected(_on_reached):
			spawner.reached_goal.connect(_on_reached)
	refresh()


## 還在的基地
func bases() -> Array[Base]:
	var result: Array[Base] = []
	for node: Node in get_tree().get_nodes_in_group("bases"):
		if node is Base and not (node as Base).is_destroyed:
			result.append(node)
	return result


func _on_reached(enemy: Node2D) -> void:
	var base: Base = enemy.get_meta("target", null) as Base
	if base == null or not is_instance_valid(base):
		var all: Array[Base] = bases()
		if all.is_empty():
			return
		base = all[0]
	on_base_hit(base)


## 某個基地被怪摸到了
func on_base_hit(base: Base) -> void:
	if GameFlow.is_finished():
		return
	match mode:
		0:
			shared_health -= 1
			refresh()
			if shared_health <= 0:
				GameFlow.lose("基地被攻破了！")
		1:
			base.set_health(base.health - 1)
			if base.health <= 0:
				GameFlow.lose("有一個基地被攻破了！")
		2:
			base.set_health(base.health - 1)
			if base.health <= 0:
				base.destroy()
				for node: Node in get_tree().get_nodes_in_group("spawners"):
					(node as Spawner).retarget_all()               # 怪改去別的基地
				if bases().is_empty():
					GameFlow.lose("基地全部被攻破了！")
	changed.emit()


## 共用一條血：每個基地的血條都顯示共用的血量
func refresh() -> void:
	if mode == 0:
		for base: Base in bases():
			base.max_health = shared_max_health
			base.set_health(shared_health)
	changed.emit()


## 畫面上的文字，例如「基地 8/10」「基地 2 個（最少的 3/10）」
func status_text() -> String:
	if mode == 0:
		return "基地 %d/%d" % [shared_health, shared_max_health]
	var all: Array[Base] = bases()
	if all.is_empty():
		return "基地 0 個"
	var weakest: Base = all[0]
	for base: Base in all:
		if base.health < weakest.health:
			weakest = base
	return "基地 %d 個（最少的 %d/%d）" % [all.size(), weakest.health, weakest.max_health]
