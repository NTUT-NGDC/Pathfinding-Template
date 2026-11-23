class_name SoundBus
extends Node
## 聲音廣播：遊戲裡「發出聲音」都經過這裡。不用放進場景，直接呼叫：
##   SoundBus.emit_sound(位置, 範圍)
## 有掛「耳朵」（Ear）的角色在範圍內就會聽到（Ear 的 heard signal）。
## 想自己接收：SoundBus.instance().sound_emitted.connect(...)
##
## 這裡只管「哪裡發出多大的聲音」，不管誰聽到：發出聲音的人不用知道場上有幾個耳朵。

## 有東西發出聲音。position 是全局座標，radius 是聲音傳多遠（像素）
signal sound_emitted(position: Vector2, radius: float)

static var _instance: SoundBus


## 在某個位置發出聲音
static func emit_sound(position: Vector2, radius: float) -> void:
	instance().sound_emitted.emit(position, radius)


## 全場共用的那一個（第一次用到時自動建立）
static func instance() -> SoundBus:
	if _instance == null or not is_instance_valid(_instance):
		_instance = SoundBus.new()
		_instance.name = "SoundBus"
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		tree.root.add_child.call_deferred(_instance)
	return _instance
