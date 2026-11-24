@tool
class_name TacticsSquad
extends Resource
## 一隊敵人的資料：有哪幾隻、站在哪、怎麼巡邏、看多遠。在編輯器的「地圖」「小隊」頁設定。

## 小隊的名字
@export var squad_name: String = "小隊"
## 有哪些棋子（場景），第一隻是帶頭的，其他的照擺的位置排成隊形一起走
@export var members: Array[String] = []
## 每一隻站在哪一格（跟上面的順序一樣）
@export var cells: Array[Vector2i] = []
## 巡邏點（沒有＝每一隻站在原地左右張望）
@export var patrol: Array[Vector2i] = []
## 走到最後一個巡邏點之後：來回或繞圈
@export_enum("來回", "繞圈") var patrol_mode: int = 0
## 巡邏的速度（像素／秒）
@export_range(10, 300, 5, "suffix:px/s") var patrol_speed: float = 50.0
## 一開始面向哪裡（度，0＝右、90＝下）
@export_range(-180, 180, 5, "suffix:°") var start_angle: float = 180.0
## 看多遠（像素）
@export_range(40, 800, 10, "suffix:px") var view_distance: float = 180.0
## 視野角度（度）
@export_range(10, 360, 5, "suffix:°") var view_angle: float = 90.0
## 隊友看的距離是帶頭的幾倍
@export_range(0.1, 2.0, 0.05) var member_view: float = 0.7
## 只有帶頭的有視野（隊友不會發現你）
@export var leader_only: bool = false
## 反應時間：看到隊長幾秒之後開打。0＝一看到就開打
@export_range(0.0, 5.0, 0.1, "suffix:秒") var reaction_time: float = 1.0
## 支援距離：開打時，離戰場這麼近（格）的其他小隊也會加入。0＝不會有人來
@export_range(0, 40, 1, "suffix:格") var support: int = 0
## 打倒之後掉幾份營地物資在地上
@export_range(0, 10, 1, "suffix:份") var drop_supplies: int = 0
## 首領小隊（勝利條件選「打倒首領小隊」時用）
@export var boss: bool = false
## 一開始就開打（不用探索，做純戰棋用）
@export var instant: bool = false


func add(scene_path: String, cell: Vector2i) -> void:
	members.append(scene_path)
	cells.append(cell)


func remove_at(index: int) -> void:
	members.remove_at(index)
	cells.remove_at(index)


## 第幾隻看多遠（0＝沒有視野）
func view_of(index: int) -> float:
	if index == 0:
		return view_distance
	return 0.0 if leader_only else view_distance * member_view


## 第幾隻一開始面向哪裡（弧度）：隊友輪流偏左、偏右，看不同的方向
func look_angle(index: int) -> float:
	return deg_to_rad(start_angle + (0.0 if index == 0 else 35.0 if index % 2 == 1 else -35.0))


func to_data() -> Dictionary:
	return {
		"name": squad_name, "members": members.duplicate(), "cells": cells.duplicate(), "patrol": patrol.duplicate(),
		"patrol_mode": patrol_mode, "patrol_speed": patrol_speed, "start_angle": start_angle,
		"view_distance": view_distance, "view_angle": view_angle, "member_view": member_view, "leader_only": leader_only, "reaction_time": reaction_time,
		"support": support, "drop_supplies": drop_supplies, "boss": boss, "instant": instant,
	}


static func from_data(data: Dictionary) -> TacticsSquad:
	var squad: TacticsSquad = TacticsSquad.new()
	squad.squad_name = data["name"]
	squad.members.assign(data["members"])
	squad.cells.assign(data["cells"])
	squad.patrol.assign(data["patrol"])
	for field: String in ["patrol_mode", "patrol_speed", "start_angle", "view_distance", "view_angle", "member_view", "leader_only", "reaction_time", "support", "drop_supplies", "boss", "instant"]:
		squad.set(field, data[field])
	return squad
