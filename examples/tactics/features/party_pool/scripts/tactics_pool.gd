@tool
class_name TacticsPool
extends Resource
## 玩家的隊伍池：我有哪些人，每一關都從這裡挑。
##   起始隊伍（start）：剛開始玩就有的人，存在 party_pool.tres，用編輯器的「隊伍」頁改
##   加入的人：過關獎勵、地圖上招募到的，存在玩家的電腦（user://，關掉重開還在，網頁版也是）
##
##   TacticsPool.units()            現在有誰（起始隊伍＋加入的人）
##   TacticsPool.add("哪裡來的", 棋子)  加一個人；同一個「哪裡來的」只會加一次
##   TacticsPool.clear()            清掉加入的人

const PATH: String = "res://examples/tactics/party_pool.tres"

## 起始隊伍（棋子場景）
@export var start: Array[String] = []

## 存在哪（測試會換掉）
static var save_path: String = "user://tactics_party.json"
## 試玩：只有起始隊伍，加入的人不會存起來
static var testing: bool = false

## 哪裡來的 → 棋子場景
static var _joined: Dictionary[String, String] = {}
static var _test_joined: Dictionary[String, String] = {}
## 讀過的是哪一個檔案（換了檔案就重讀）
static var _loaded_path: String = ""


## 起始隊伍
static func start_units() -> Array[String]:
	var pool: TacticsPool = load(PATH) as TacticsPool if ResourceLoader.exists(PATH) else null
	var result: Array[String] = []
	if pool != null:
		result.assign(pool.start.filter(func(path: String) -> bool: return ResourceLoader.exists(path)))
	return result


## 現在有誰
static func units() -> Array[String]:
	var result: Array[String] = start_units()
	for path: String in _all().values():
		if ResourceLoader.exists(path):                           # 棋子被刪掉的話就當作沒有
			result.append(path)
	return result


## 這個人加入過了嗎
static func has(key: String) -> bool:
	return _all().has(key)


## 加一個人。回傳有沒有加（已經加過＝false）
static func add(key: String, unit_path: String) -> bool:
	if has(key):
		return false
	_all()[key] = unit_path
	if not testing:
		_save()
	return true


## 清掉加入的人（只剩起始隊伍）
static func clear() -> void:
	_loaded_path = save_path
	_joined.clear()
	_save()


## 開始試玩：從起始隊伍開始，不動真正的存檔
static func begin_test() -> void:
	testing = true
	_test_joined.clear()


static func end_test() -> void:
	testing = false


static func _all() -> Dictionary[String, String]:
	if testing:
		return _test_joined
	if _loaded_path != save_path:
		_load()
	return _joined


static func _load() -> void:
	_loaded_path = save_path
	_joined.clear()
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary:                                        # 檔案壞了就當作沒有，不會當掉
		for key: Variant in data:
			_joined[str(key)] = str(data[key])


static func _save() -> void:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("[TacticsPool] 隊伍存不了：%s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_joined))
