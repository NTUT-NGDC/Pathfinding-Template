class_name Player
extends CharacterBody2D
## 玩家：WASD 走路（安靜）、按住 Shift 跑步（快，但會發出聲音）、E 互動（開門、躲藏、撿東西）、
## 1 丟瓶子（落地的聲音會把追逐 AI 引過去）。踩到捕獸夾會被夾住幾秒不能動。
## 追逐 AI 碰到就被抓（追逐 AI 會呼叫 get_caught()）；躲在櫃子裡看不到、抓不到，
## 但被追逐 AI 親眼看到躲進去的話會被拖出來（追逐 AI 會聽 hid signal）。
## 從打開的出口出去就贏了（呼叫起手包的 GameFlow.win()，顯示通關時間）。
##
## 用法：把 player.tscn 拖進關卡，放在起點。整個關卡只放一個。

## 被追逐 AI 抓到了
signal caught()
## 從出口逃出去了
signal escaped()
## 身上的瓶子數變了
signal bottles_changed(count: int)
## 被夾住（捕獸夾）
signal stunned(seconds: float)
## 躲進躲藏點
signal hid(spot: Node2D)
## 從躲藏點出來
signal unhid(spot: Node2D)

@export_group("移動")
## 走路速度（像素／秒），走路不會發出聲音
@export_range(20, 400, 5, "suffix:px/s") var walk_speed: float = 110.0
## 跑步速度（像素／秒）
@export_range(20, 600, 5, "suffix:px/s") var run_speed: float = 190.0

@export_group("聲音")
## 跑步的聲音傳多遠（像素）。0＝跑步也不會發出聲音
@export_range(0, 800, 10, "suffix:px") var run_sound_radius: float = 260.0
## 跑步時每隔幾秒發出一次腳步聲
@export_range(0.1, 2.0, 0.05, "suffix:秒") var run_sound_interval: float = 0.35

@export_group("瓶子")
## 一開始身上有幾個瓶子
@export_range(0, 20) var start_bottles: int = 0
## 瓶子丟多遠（像素），撞到牆會停在牆前面
@export_range(40, 600, 10, "suffix:px") var throw_distance: float = 220.0
## 瓶子碎掉的聲音傳多遠（像素）
@export_range(0, 800, 10, "suffix:px") var bottle_sound_radius: float = 350.0

## 從開始到現在幾秒（逃出去時顯示通關時間）
var elapsed: float = 0.0

const BODY_COLOR: Color = Color("f2e6c9")
const OUTLINE_COLOR: Color = Color("2a2a30")
## 玩家碰撞用的物理層：第 3 層（玩家），撞第 1 層（擋路）
const PLAYER_LAYER: int = 1 << 2
const PATH_LAYER: int = 1

## 正在躲（躲著的時候殺手看不到、也碰不到）
var is_hidden: bool = false
## 被抓了或逃出去了：不能再動
var is_finished: bool = false
## 撿到的鑰匙顏色
var keys: Array[String] = []
## 面向（走路時跟著改）
var facing: Vector2 = Vector2.DOWN
## 現在是不是在跑（有在移動而且按著 Shift）
var is_running: bool = false
## 身上有幾個瓶子
var bottles: int = 0
## 被夾住還剩幾秒（0＝沒被夾住）
var stun_time: float = 0.0

var _hiding_spot: Node2D
## 躲進去之前站的位置，出來時回到這裡
var _position_before_hiding: Vector2
var _sound_timer: float = 0.0
## 現在最近的互動範圍、正在按住的互動範圍
var _focus: Interactable
var _holding: Interactable

@onready var _interact_area: Area2D = $InteractArea
@onready var _prompt: Label = $Prompt


func _enter_tree() -> void:
	add_to_group("player")


func _ready() -> void:
	collision_layer = PLAYER_LAYER
	collision_mask = PATH_LAYER
	bottles = start_bottles


func _physics_process(delta: float) -> void:
	if is_finished:
		return
	elapsed += delta
	if stun_time > 0.0:
		stun_time = maxf(stun_time - delta, 0.0)                  # 被夾住：不能動、不能互動
		_prompt.visible = false
		queue_redraw()
		return
	_update_interaction(delta)
	if is_hidden:
		return
	_move(delta)
	if Input.is_action_just_pressed("skill_1"):
		throw_bottle()
	queue_redraw()


## 走路／跑步，跑步時發出腳步聲
func _move(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	is_running = Input.is_action_pressed("run") and input != Vector2.ZERO
	velocity = input * (run_speed if is_running else walk_speed)
	move_and_slide()
	if input != Vector2.ZERO:
		facing = input.normalized()
	_sound_timer -= delta
	if is_running and run_sound_radius > 0.0 and _sound_timer <= 0.0:
		SoundBus.emit_sound(global_position, run_sound_radius)    # 跑步：發出腳步聲
		_sound_timer = run_sound_interval


## 找最近的互動範圍；按 E 互動、按住 E 持續互動
func _update_interaction(delta: float) -> void:
	_focus = _nearest_interactable()
	_prompt.visible = _focus != null
	if _focus != null:
		_prompt.text = "E 出來" if is_hidden else "E " + _focus.prompt
	# 按住的東西走遠了或放開 E：通知它放開
	if _holding != null and (not Input.is_action_pressed("interact") or _holding != _focus):
		_holding.released.emit(self)
		_holding = null
	if _focus == null:
		return
	if Input.is_action_just_pressed("interact"):
		_holding = _focus
		_focus.interacted.emit(self)
	elif _holding != null:
		_holding.held.emit(self, delta)


func _nearest_interactable() -> Interactable:
	if is_hidden:
		return _hiding_spot_interactable()
	var best: Interactable = null
	var best_distance: float = INF
	for area: Area2D in _interact_area.get_overlapping_areas():
		var interactable: Interactable = area as Interactable
		if interactable == null or not interactable.enabled:
			continue
		var distance: float = global_position.distance_to(interactable.global_position)
		if distance < best_distance:
			best = interactable
			best_distance = distance
	return best


## 躲著的時候只能跟自己躲的地方互動（出來）
func _hiding_spot_interactable() -> Interactable:
	if _hiding_spot == null:
		return null
	for child: Node in _hiding_spot.get_children():
		if child is Interactable:
			return child
	return null


## 躲進躲藏點（由躲藏點呼叫）
func hide_in(spot: Node2D) -> void:
	if is_hidden or is_finished:
		return
	is_hidden = true
	_hiding_spot = spot
	_position_before_hiding = global_position
	global_position = spot.global_position
	velocity = Vector2.ZERO
	collision_layer = 0                                           # 追的人碰不到、看不到
	queue_redraw()
	hid.emit(spot)


## 從躲藏點出來，回到躲進去之前的位置（由躲藏點呼叫）
func leave_hiding() -> void:
	if not is_hidden:
		return
	var spot: Node2D = _hiding_spot
	is_hidden = false
	_hiding_spot = null
	global_position = _position_before_hiding
	collision_layer = PLAYER_LAYER
	queue_redraw()
	unhid.emit(spot)


## 被抓到（追逐 AI 碰到、或是被從躲藏點拖出來時，追逐 AI 會呼叫）
func get_caught() -> void:
	if is_finished:
		return
	if is_hidden:
		leave_hiding()
	is_finished = true
	velocity = Vector2.ZERO
	_prompt.visible = false
	caught.emit()


## 逃出去了（由出口呼叫）
func escape() -> void:
	if is_finished:
		return
	is_finished = true
	velocity = Vector2.ZERO
	_prompt.visible = false
	escaped.emit()
	GameFlow.win("逃出去了！通關時間 %s" % TimerDisplay.format(elapsed))


## 撿到鑰匙
func add_key(color: String) -> void:
	if not keys.has(color):
		keys.append(color)


func has_key(color: String) -> bool:
	return keys.has(color)


## 撿到瓶子
func add_bottles(count: int) -> void:
	bottles += count
	bottles_changed.emit(bottles)


## 往面向的方向丟一個瓶子（按 1）。回傳有沒有丟出去
func throw_bottle() -> bool:
	if bottles <= 0 or is_hidden or is_finished or stun_time > 0.0:
		return false
	bottles -= 1
	bottles_changed.emit(bottles)
	ThrownBottle.throw(self, facing, throw_distance, bottle_sound_radius)
	return true


## 被夾住幾秒不能動（捕獸夾呼叫）
func stun(seconds: float) -> void:
	if is_finished or seconds <= 0.0:
		return
	stun_time = maxf(stun_time, seconds)
	velocity = Vector2.ZERO
	is_running = false
	if _holding != null:
		_holding.released.emit(self)
		_holding = null
	stunned.emit(seconds)


func _draw() -> void:
	if is_hidden:
		return                                                    # 躲起來：不畫身體（頭上的提示還在）
	draw_circle(Vector2.ZERO, 11.0, OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, 9.0, BODY_COLOR)
	draw_circle(facing * 5.0, 3.0, OUTLINE_COLOR)                 # 看的方向
	if stun_time > 0.0:
		# 被夾住：頭上轉圈的星星
		for i: int in 3:
			var at: Vector2 = Vector2(0, -18) + Vector2.from_angle(elapsed * 6.0 + TAU * i / 3.0) * Vector2(9, 3)
			draw_circle(at, 2.0, Color("ffd75e"))
