@tool
class_name ChaseAI
extends CharacterBody2D
## 追逐 AI：照巡邏點走，聽到聲音過去查看，看到目標頭上出現 ?（懷疑），警戒值滿了變成 ! 追過來，
## 追丟了去最後看到的地方找一找，找不到再回去巡邏。碰到目標就發出 caught。
##
## 用法：
##   1. 把 chase_ai.tscn 拖進場景（放幾隻都可以，場景裡要有尋路地圖 PathGrid）
##   2. 在它底下加幾個 Marker2D 當巡邏點，拖到你要它走的地方（沒有巡邏點就站著左右張望）
##   3. 調這個節點檢查器的「個性」「開關」（底下的 VisionSensor、Ear、PathFollower 不用調，會被這裡蓋過去）
##
## 看、聽、走路分別交給底下的 VisionSensor、Ear、PathFollower，這個腳本只負責「決定要做什麼」。
## 狀態用簡單的 enum＋if 寫；狀態再多下去會亂成一團，那時候要用狀態機或行為樹。
##
## 目標有 is_hidden 屬性（躲起來）的話看不到、抓不到；目標有 hid(spot) signal 的話，
## 被親眼看到躲進去會走過去把它抓出來。

## 抓到目標了
signal caught(target: Node2D)
## 狀態變了（例如可以用來播音效）
signal state_changed(state: State)

enum State { PATROL, INVESTIGATE, SUSPICIOUS, CHASE, SEARCH }

## 狀態的中文名稱（按 F3 顯示）
const STATE_NAMES: Array[String] = ["巡邏", "查看", "懷疑", "追擊", "搜尋"]
## 到了聲音的位置，原地張望幾秒（搜尋時間的幾倍）
const INVESTIGATE_LOOK_RATIO: float = 0.5
## 張望時左右轉多少度
const LOOK_AROUND_ANGLE: float = 70.0
## 視野錐顏色：巡邏白、查看／懷疑黃、追擊紅
const CONE_COLORS: Array[Color] = [
	Color(1, 1, 1, 0.16), Color(1, 0.85, 0.2, 0.22), Color(1, 0.85, 0.2, 0.22),
	Color(1, 0.2, 0.2, 0.28), Color(1, 0.85, 0.2, 0.22)]

@export_group("個性")
## 看多遠（像素）
@export_range(40, 800, 10, "suffix:px") var view_distance: float = 260.0:
	set(value):
		view_distance = value
		queue_redraw()
## 視野角度（度）。90＝左右各 45 度；360＝背後也看得到
@export_range(10, 360, 5, "suffix:°") var view_angle: float = 90.0:
	set(value):
		view_angle = value
		queue_redraw()
## 巡邏、查看時走路的速度（像素／秒）
@export_range(10, 400, 5, "suffix:px/s") var patrol_speed: float = 70.0
## 追擊、搜尋時的速度（像素／秒）
@export_range(10, 400, 5, "suffix:px/s") var chase_speed: float = 150.0
## 反應時間：看到目標後，警戒值從 0 到滿（開始追）要幾秒。0＝一看到就追
@export_range(0.0, 5.0, 0.1, "suffix:秒") var reaction_time: float = 1.0
## 追丟之後，在最後看到的地方找幾秒才放棄
@export_range(0.0, 15.0, 0.5, "suffix:秒") var search_time: float = 4.0
## 轉頭速度（度／秒）。越慢越容易從旁邊溜過去
@export_range(30, 1080, 10, "suffix:°/s") var turn_speed: float = 300.0
## 聽力範圍倍率：2＝聲音傳兩倍遠也聽得到
@export_range(0.0, 3.0, 0.1) var hearing_multiplier: float = 1.0
## 開一扇門要幾秒
@export_range(0.0, 5.0, 0.1, "suffix:秒") var door_open_time: float = 1.2

@export_group("開關")
## 有耳朵：聽到聲音會過去查看
@export var has_hearing: bool = true
## 牆會擋視線。關掉 → 隔著牆也看得到
@export var walls_block_sight: bool = true
## 檢查角度。關掉 → 背後也長眼睛
@export var check_angle: bool = true
## 記住最後看到的位置。關掉 → 一看不到就馬上回去巡邏
@export var remember_last_position: bool = true
## 使用尋路。關掉 → 直線衝向目標，會卡在牆上
@export var use_pathfinding: bool = true
## 顯示視野錐
@export var show_cone: bool = true

@export_group("目標")
## 要追誰（group 名稱）
@export var target_group: String = "player"
## 離目標多近算抓到（像素）
@export_range(4, 64, 1, "suffix:px") var catch_distance: float = 22.0
## 抓到目標就輸（呼叫起手包的 GameFlow.lose()）
@export var lose_when_caught: bool = true
## 抓到時失敗畫面顯示的文字
@export var caught_message: String = "被抓到了！"

@export_group("巡邏")
## 走到最後一個巡邏點之後：來回（原路走回去）或繞圈（回到第一個）
@export_enum("來回", "繞圈") var patrol_mode: int = 0
## 每個巡邏點停幾秒
@export_range(0.0, 10.0, 0.5, "suffix:秒") var patrol_wait: float = 1.0
## 一開始面向哪裡（度，0＝右、90＝下）
@export_range(-180, 180, 5, "suffix:°") var start_angle: float = 0.0:
	set(value):
		start_angle = value
		queue_redraw()

@export_group("外觀")
## 身體的顏色
@export var body_color: Color = Color("b02a2a"):
	set(value):
		body_color = value
		queue_redraw()

var state: State = State.PATROL
## 警戒值 0～1，滿了就追
var alert: float = 0.0
## 面向（單位向量）
var facing: Vector2 = Vector2.RIGHT

var _target: Node2D
var _patrol_points: PackedVector2Array = PackedVector2Array()
var _patrol_index: int = 0
var _patrol_step: int = 1
var _wait_timer: float = 0.0
var _last_seen: Vector2
## 張望：正在張望嗎、剩幾秒、張望的中心方向、已經張望多久
var _looking: bool = false
var _look_timer: float = 0.0
var _look_center: Vector2 = Vector2.RIGHT
var _look_time: float = 0.0
## 親眼看到目標躲進去的地方
var _grab_spot: Node2D
var _has_caught: bool = false
var _overlay: Node2D
var _mark_label: Label
var _state_label: Label

@onready var _vision: VisionSensor = $VisionSensor
@onready var _ear: Ear = $Ear
@onready var _mover: PathFollower = $PathFollower


func _ready() -> void:
	facing = Vector2.from_angle(deg_to_rad(start_angle))
	if Engine.is_editor_hint():
		return
	add_to_group("chase_ai")
	for child: Node in get_children():
		if child is Marker2D:
			_patrol_points.append((child as Marker2D).global_position)  # 巡邏點跟著主人動，所以一開始先記下位置
	_ear.heard.connect(_on_heard)
	_apply_settings()
	_build_overlay()
	_look_center = facing
	_enter_patrol()


## 把檢查器的數字交給底下的元件（遊戲中改檢查器也會立刻生效）
func _apply_settings() -> void:
	_vision.view_distance = view_distance
	_vision.view_angle = view_angle
	_vision.walls_block_sight = walls_block_sight
	_vision.check_angle = check_angle
	_vision.target_group = target_group
	_vision.show_cone = show_cone
	_vision.cone_color = CONE_COLORS[state]
	_vision.facing = facing
	_ear.enabled = has_hearing
	_ear.range_multiplier = hearing_multiplier
	_mover.use_pathfinding = use_pathfinding
	_mover.door_open_time = door_open_time
	_mover.speed = chase_speed if state == State.CHASE or state == State.SEARCH else patrol_speed


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_find_target()
	_apply_settings()
	update_state(delta)
	_update_facing(delta)
	_check_catch()
	_update_overlay()


## 決定現在要做什麼：看到目標就提高警戒、滿了就追；追丟了就去找
func update_state(delta: float) -> void:
	var sees: bool = _vision.sees_target
	if sees:
		_last_seen = _target.global_position                      # 記住最後看到的位置
	if _grab_spot != null:
		_update_grab()                                            # 看到目標躲進去：去抓
		return
	if state == State.CHASE:
		if sees:
			pass                                                  # 追擊中：PathFollower 會一直跟著目標
		elif remember_last_position:
			_enter_search()                                       # 追丟了：去最後看到的地方找
		else:
			_enter_patrol()                                       # 不記得：馬上回去巡邏
		return
	if sees:
		_set_state(State.SUSPICIOUS)
		alert += delta / maxf(reaction_time, 0.001)               # 看得到：警戒值上升
		_mover.stop()
		if alert >= 1.0:
			_enter_chase()
		return
	if state == State.SUSPICIOUS:
		alert -= delta / maxf(reaction_time, 0.001) * 0.5         # 看不到：警戒值慢慢降
		if alert <= 0.0:
			_enter_patrol()
		return
	match state:
		State.PATROL: _patrol(delta)
		State.INVESTIGATE: _wander(search_time * INVESTIGATE_LOOK_RATIO, delta)
		State.SEARCH: _wander(search_time, delta)


func _patrol(delta: float) -> void:
	if _patrol_points.is_empty():
		_look_around(delta)                                       # 沒有巡邏點：站著左右張望
		return
	if _mover.is_moving():
		return
	if _wait_timer > 0.0:
		_wait_timer -= delta
		return
	_mover.go_to(_patrol_points[_patrol_index])
	_wait_timer = patrol_wait
	_next_patrol_index()


func _next_patrol_index() -> void:
	var count: int = _patrol_points.size()
	if count <= 1:
		return
	if patrol_mode == 1:
		_patrol_index = (_patrol_index + 1) % count               # 繞圈
		return
	if _patrol_index + _patrol_step < 0 or _patrol_index + _patrol_step >= count:
		_patrol_step = -_patrol_step                              # 來回：走到底就掉頭
	_patrol_index += _patrol_step


## 走到目的地，到了（或走不到）就原地張望 look_seconds 秒，然後回去巡邏
func _wander(look_seconds: float, delta: float) -> void:
	if not _looking:
		if _mover.is_moving():
			return                                                # 還在路上
		_looking = true                                           # 到了：開始張望
		_look_timer = look_seconds
		_look_center = facing
	_look_around(delta)
	_look_timer -= delta
	if _look_timer <= 0.0:
		_enter_patrol()                                           # 找不到：回去巡邏


func _look_around(delta: float) -> void:
	_look_time += delta
	var offset: float = sin(_look_time * 1.8) * deg_to_rad(LOOK_AROUND_ANGLE)
	_turn_toward(_look_center.rotated(offset), delta)


func _update_grab() -> void:
	if _target == null or _target.get("is_hidden") != true:
		_grab_spot = null                                         # 目標自己出來了：照一般規則
		_enter_chase()
		return
	if global_position.distance_to(_grab_spot.global_position) <= catch_distance + 8.0:
		_grab_spot = null
		_mover.stop()
		_catch()                                                  # 把目標拖出來
	elif not _mover.is_moving():
		_mover.go_to(_grab_spot.global_position)


## 碰到目標（沒躲起來）就抓到
func _check_catch() -> void:
	if _target == null or _has_caught or _target.get("is_hidden") == true:
		return
	if global_position.distance_to(_target.global_position) <= catch_distance:
		_catch()


func _catch() -> void:
	if _has_caught:
		return
	_has_caught = true
	caught.emit(_target)
	if _target.has_method("get_caught"):
		_target.call("get_caught")
	if lose_when_caught:
		var flow: Node = get_node_or_null("/root/GameFlow")
		if flow != null:
			flow.call("lose", caught_message)


func _on_target_hid(spot: Node2D) -> void:
	# 躲進去的前一刻還看得到 → 親眼看到了
	if _vision.sees_target:
		_grab_spot = spot
		_set_state(State.CHASE)
		alert = 1.0
		_mover.go_to(spot.global_position)


func _on_heard(sound_position: Vector2) -> void:
	if state == State.CHASE or state == State.SUSPICIOUS or _grab_spot != null:
		return                                                    # 正在追、正在盯著看：不理聲音
	_set_state(State.INVESTIGATE)
	_reset_look()
	_mover.go_to(sound_position)


func _enter_patrol() -> void:
	_set_state(State.PATROL)
	alert = 0.0
	_wait_timer = 0.0
	_reset_look()
	_mover.stop()


func _enter_chase() -> void:
	_set_state(State.CHASE)
	alert = 1.0
	_mover.follow(_target)                                        # 一直追著目標（每 0.2 秒重算一次路）


func _enter_search() -> void:
	_set_state(State.SEARCH)
	_reset_look()
	_mover.go_to(_last_seen)


func _reset_look() -> void:
	_looking = false
	_look_timer = 0.0
	_look_time = 0.0
	_look_center = facing


func _set_state(new_state: State) -> void:
	if state != new_state:
		state = new_state
		state_changed.emit(state)


## 面向：走路時轉向前進方向；追擊、懷疑時轉向目標
func _update_facing(delta: float) -> void:
	if (state == State.SUSPICIOUS or state == State.CHASE) and _vision.sees_target:
		_turn_toward(global_position.direction_to(_target.global_position), delta)
	elif _mover.move_direction != Vector2.ZERO:
		_turn_toward(_mover.move_direction, delta)
	_vision.facing = facing


func _turn_toward(direction: Vector2, delta: float) -> void:
	if direction == Vector2.ZERO:
		return
	var step: float = deg_to_rad(turn_speed) * delta
	facing = facing.rotated(clampf(facing.angle_to(direction), -step, step)).normalized()


func _find_target() -> void:
	if _target != null and is_instance_valid(_target):
		return
	_target = get_tree().get_first_node_in_group(target_group) as Node2D
	_vision.target = _target
	if _target != null and _target.has_signal("hid"):
		_target.connect("hid", _on_target_hid)


# ---- 畫圖 ----

## ?、!、狀態文字畫在另一個圖層，才不會被黑暗蓋掉
func _build_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 11
	layer.follow_viewport_enabled = true
	add_child(layer)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	layer.add_child(_overlay)
	_mark_label = _make_label(33, Vector2(-20, -58))
	_state_label = _make_label(11, Vector2(-40, 16))


func _make_label(font_size: int, offset: Vector2) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = offset
	label.size = Vector2(-offset.x * 2.0, 0)
	_overlay.add_child(label)
	return label


func _update_overlay() -> void:
	_overlay.global_position = global_position
	_mark_label.visible = state == State.SUSPICIOUS or state == State.CHASE or state == State.INVESTIGATE
	_mark_label.text = "!" if state == State.CHASE else "?"
	_mark_label.modulate = Color(1, 0.3, 0.3) if state == State.CHASE else Color(1, 0.9, 0.3)
	_state_label.visible = PathDebug.show_states
	_state_label.text = "%s %d%%" % [STATE_NAMES[state], roundi(alert * 100.0)]
	_overlay.queue_redraw()
	queue_redraw()


func _draw_overlay() -> void:
	if PathDebug.show_states and state == State.SUSPICIOUS:
		_overlay.draw_rect(Rect2(-16, -26, 32, 4), Color(0, 0, 0, 0.6))
		_overlay.draw_rect(Rect2(-16, -26, 32 * clampf(alert, 0.0, 1.0), 4), Color(1, 0.85, 0.2))


func _draw() -> void:
	draw_circle(Vector2.ZERO, 12.0, body_color.darkened(0.6))
	draw_circle(Vector2.ZERO, 10.0, body_color)
	draw_circle(facing * 6.0, 3.0, Color.WHITE)
	if Engine.is_editor_hint():
		_draw_editor_preview()


## 編輯器裡：畫出視野範圍和巡邏路線，方便擺放
func _draw_editor_preview() -> void:
	var angle: float = deg_to_rad(view_angle)
	var center: float = facing.angle()
	draw_arc(Vector2.ZERO, view_distance, center - angle / 2.0, center + angle / 2.0, 32, Color(1, 1, 1, 0.4), 2.0)
	if view_angle < 360.0:
		draw_line(Vector2.ZERO, Vector2.from_angle(center - angle / 2.0) * view_distance, Color(1, 1, 1, 0.4), 2.0)
		draw_line(Vector2.ZERO, Vector2.from_angle(center + angle / 2.0) * view_distance, Color(1, 1, 1, 0.4), 2.0)
	var previous: Vector2 = Vector2.ZERO
	var first: Vector2 = Vector2.ZERO
	var count: int = 0
	for child: Node in get_children():
		if child is Marker2D:
			var point: Vector2 = (child as Marker2D).position
			draw_line(previous, point, Color(1, 0.5, 0.2, 0.8), 2.0)
			draw_circle(point, 5.0, Color(1, 0.5, 0.2))
			if count == 0:
				first = point
			previous = point
			count += 1
	if patrol_mode == 1 and count >= 2:
		draw_line(previous, first, Color(1, 0.5, 0.2, 0.5), 2.0)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		facing = Vector2.from_angle(deg_to_rad(start_angle))
		queue_redraw()                                            # 拖巡邏點時即時更新路線
