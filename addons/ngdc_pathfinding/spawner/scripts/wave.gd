class_name Wave
extends Resource
## 一波敵人：出什麼、出幾隻、隔多久出一隻。給生怪器（Spawner）的「波次表」用。

## 出什麼敵人（空著＝用生怪器預設的 Walker）
@export var enemy_scene: PackedScene
## 這一波出幾隻
@export_range(1, 200, 1) var count: int = 5
## 隔幾秒出一隻
@export_range(0.1, 10.0, 0.1, "suffix:秒") var interval: float = 1.0
## 敵人走路速度（像素／秒）；0＝用敵人場景自己的速度
@export_range(0, 500, 5, "suffix:px/s") var speed: float = 0.0
## 敵人血量；0＝用敵人場景自己的血量
@export_range(0, 1000, 1) var health: float = 0.0
