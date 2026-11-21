@tool
class_name RepairPoint
extends Task
## 修理點：玩家按住 E 修理，修滿就完成。修的時候每隔一段時間發出聲音（殺手可能會聽到）。
## 中途離開會保留進度。
##
## 用法：把 repair_point.tscn 拖進關卡，在檢查器調要修幾秒、聲音多大。

@export_group("修理")
## 要按住幾秒才修得好
@export_range(0.5, 30.0, 0.5, "suffix:秒") var repair_time: float = 6.0
## 修理時每隔幾秒發出一次聲音
@export_range(0.2, 5.0, 0.1, "suffix:秒") var sound_interval: float = 1.0
## 修理聲傳多遠（像素）。0＝不會發出聲音
@export_range(0, 800, 10, "suffix:px") var sound_radius: float = 300.0

const BOX: Color = Color("5d646e")
const BOX_DARK: Color = Color("2c3036")
const SPARK: Color = Color("ffcc33")
const DONE: Color = Color("4ab86a")

## 修了幾秒
var progress: float = 0.0
var _sound_timer: float = 0.0

@onready var _interact: Interactable = $Interactable


func _init() -> void:
	category = "修理"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_interact.held.connect(_on_held)
	_interact.interacted.connect(func(player: Player) -> void: _on_held(player, 0.0))


func _on_held(_player: Player, delta: float) -> void:
	if is_done:
		return
	progress = minf(progress + delta, repair_time)
	_sound_timer -= delta
	if _sound_timer <= 0.0 and sound_radius > 0.0:
		SoundBus.emit_sound(global_position, sound_radius)        # 修理的聲音
		_sound_timer = sound_interval
	if progress >= repair_time:
		_interact.enabled = false
		complete()
	queue_redraw()


func _draw() -> void:
	# 機器：方塊＋齒輪
	draw_rect(Rect2(-14, -12, 28, 24), BOX_DARK)
	draw_rect(Rect2(-12, -10, 24, 20), DONE if is_done else BOX)
	draw_circle(Vector2.ZERO, 6.0, BOX_DARK)
	for i: int in 6:
		draw_line(Vector2.ZERO, Vector2.from_angle(TAU * i / 6.0) * 8.0, BOX_DARK, 3.0)
	draw_circle(Vector2.ZERO, 2.5, SPARK if not is_done else Color.WHITE)
	# 進度條（開始修了才顯示）
	if progress > 0.0 and not is_done:
		draw_rect(Rect2(-16, -22, 32, 5), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-16, -22, 32 * progress / repair_time, 5), SPARK)
