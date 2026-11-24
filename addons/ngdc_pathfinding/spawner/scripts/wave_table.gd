class_name WaveTable
extends Resource
## 波次檔：一整份波次表，存成一個檔案，可以給不同的關卡、地圖用。拖進生怪器（Spawner）的 Wave Table。
## 塔防範例用編輯器的「波次」頁做（examples/tower_defense/map_editor），存在 waves/ 資料夾。
##
## waves 一列是一種怪。「With Previous」打勾的列跟上一列算同一波、同時出，所以一波可以混好幾種怪。

## 名稱
@export var table_name: String = "新波次"
## 第一波之前等幾秒
@export_range(0.0, 60.0, 0.5, "suffix:秒") var start_delay: float = 5.0
## 每一波之間休息幾秒
@export_range(0.0, 60.0, 0.5, "suffix:秒") var time_between_waves: float = 6.0
## 波次（一列一種怪）
@export var waves: Array[Wave] = []


## 一波一波分好：每一項是那一波的所有列（Array[Wave]）
func groups() -> Array[Array]:
	return WaveTable.group(waves)


## 複製一份（改複製的不會動到原本的）
func copy() -> WaveTable:
	var fresh: WaveTable = WaveTable.new()
	fresh.table_name = table_name
	fresh.start_delay = start_delay
	fresh.time_between_waves = time_between_waves
	for wave: Wave in waves:
		if wave != null:
			fresh.waves.append(wave.duplicate())
	return fresh


## 把波次表一波一波分好（With Previous 打勾的列併進上一波；空的列跳過）
static func group(list: Array[Wave]) -> Array[Array]:
	var result: Array[Array] = []
	for wave: Wave in list:
		if wave == null:
			continue
		if wave.with_previous and not result.is_empty():
			result[result.size() - 1].append(wave)
		else:
			result.append([wave])
	return result


## group() 的反過來：一波一波 → 波次表（順便把 With Previous 設對）
static func flatten(list: Array[Array]) -> Array[Wave]:
	var result: Array[Wave] = []
	for rows: Array in list:
		for i: int in rows.size():
			var wave: Wave = rows[i]
			wave.with_previous = i > 0
			result.append(wave)
	return result
