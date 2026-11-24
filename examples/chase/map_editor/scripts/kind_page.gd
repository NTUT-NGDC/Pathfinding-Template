class_name ChaseKindPage
extends LevelEditorScenePage
## 編輯器的「物件」頁：任務點、捕獸夾、警報、躲藏點和自己做的物件，各有好幾種（上面選哪一類）。
## 改一種，地圖上這一種全部跟著改（在地圖上自己改過的數值留著）。

## 現在是哪一類（重新載入時留著）
var which: int:
	get: return _session.get("which", 0)
	set(value): _session["which"] = value

var _class_list: OptionButton


## 這一頁有哪幾類（「敵人」頁覆寫成只有敵人）
func _classes() -> Array[Dictionary]:
	return ChaseKinds.classes().filter(func(item: Dictionary) -> bool: return item["base"] != ChaseMap.ENEMY)


func _setup() -> void:
	var item: Dictionary = _classes()[which]
	scenes = item["scenes"]
	thing = item["name"]
	trait_title = "特性"
	preview_color = Color("6a5d4d")
	fields = ChaseMap.fields_of(item["base"]).filter(func(field: Dictionary) -> bool: return scenes.fields.has(field["name"]))


func _list_paths() -> PackedStringArray:
	return ChaseKinds.paths(_classes()[which])


## 底本身不能改（按「複製成新的」拿來改）
func is_locked() -> bool:
	return path == scenes.base_path


## 換一類
func set_class(to: int) -> void:
	if to == which:
		return
	commit()
	if dirty:
		say.call("剛剛改的「%s」沒有存檔（按上一步拿得回來）" % data["display_name"])
	remember()
	_use_class(to)
	path = _first_path()
	data = scenes.read(path)
	dirty = false
	refresh()


func _use_class(to: int) -> void:
	which = to
	_setup()
	if _class_list != null:
		_class_list.select(which)
		_new_button.text = "＋ 新" + thing
		_copy_button.text = "複製成新" + thing


## 打開某一種（不在這一頁的類別就不管）
func show_kind(scene: String) -> void:
	for i: int in _classes().size():
		if _classes()[i] == ChaseKinds.class_of(scene):
			set_class(i)
			if path != scene:
				if dirty:
					say.call("剛剛改的「%s」沒有存檔（按上一步拿得回來）" % data["display_name"])
				open(scene)


func _state() -> Dictionary:
	return {"data": data.duplicate(true), "path": path, "which": which}


func _use(state: Dictionary) -> void:
	_use_class(state["which"])
	super(state)


func _build_ui() -> void:
	super()
	if _classes().size() < 2:
		return
	_class_list = OptionButton.new()
	_class_list.focus_mode = Control.FOCUS_NONE
	for item: Dictionary in _classes():
		_class_list.add_item(item["name"])
	_class_list.select(which)
	_class_list.item_selected.connect(set_class)
	_list.get_parent().add_child(_class_list)
	_list.get_parent().move_child(_class_list, 0)


## 只是預覽，不要被當成場上的
func _preview_added(preview: Node2D) -> void:
	for group: StringName in preview.get_groups():
		if not String(group).begins_with("_"):
			preview.remove_from_group(group)


func _preview_text(_preview_node: Node2D) -> String:
	var text: String = ""
	var sound: Variant = data.get("sound_radius")
	if sound != null:
		text = "聲音　%s" % ("不出聲" if float(sound) <= 0.0 else "傳 %d px（約 %d 格）" % [int(sound), roundi(float(sound) / ChaseMap.CELL)])
	return text + "\n\n存檔後，地圖上這一種全部跟著改"
