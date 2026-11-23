extends SceneTree
## 產生尋路積木的 tile 圖（addons/ngdc_pathfinding/grid/tileset/tiles.png）。美術全部用程式畫，不需要素材。
## 想改顏色：改下面的常數，再執行一次：
##   godot --headless --path . -s res://_dev/tools/make_tiles.gd
##
## 圖的排法（每格 32×32，由左到右）：
##   0 木頭地板　1 磁磚地板　2 牆　3 玻璃　4 草叢　5 沼澤（走起來比較慢）

const TILE: int = 32
const OUTPUT: String = "res://addons/ngdc_pathfinding/grid/tileset/tiles.png"

const WOOD: Color = Color("6b5440")
const WOOD_LINE: Color = Color("5c4736")
const TILE_A: Color = Color("4a5058")
const TILE_B: Color = Color("434950")
const WALL: Color = Color("1e1f24")
const WALL_TOP: Color = Color("3a3c44")
const GLASS: Color = Color("7fc4d8", 0.55)
const GLASS_EDGE: Color = Color("b8e6f2")
const BUSH: Color = Color("2f6b3a")
const BUSH_DARK: Color = Color("245530")
const BUSH_LIGHT: Color = Color("3f8a4b")
const SWAMP: Color = Color("4a4f2e")
const SWAMP_WATER: Color = Color("5d6b45")
const SWAMP_DARK: Color = Color("363a20")


func _init() -> void:
	var image: Image = Image.create(TILE * 6, TILE, false, Image.FORMAT_RGBA8)
	_draw_wood(image, 0)
	_draw_floor_tile(image, 1)
	_draw_wall(image, 2)
	_draw_glass(image, 3)
	_draw_bush(image, 4)
	_draw_swamp(image, 5)
	var error: Error = image.save_png(OUTPUT)
	print("存檔 %s：%s" % [OUTPUT, error_string(error)])
	quit(0 if error == OK else 1)


func _fill(image: Image, index: int, rect: Rect2i, color: Color) -> void:
	image.fill_rect(Rect2i(rect.position + Vector2i(index * TILE, 0), rect.size), color)


## 木頭地板：橫條木紋
func _draw_wood(image: Image, index: int) -> void:
	_fill(image, index, Rect2i(0, 0, TILE, TILE), WOOD)
	for y: int in [7, 15, 23, 31]:
		_fill(image, index, Rect2i(0, y, TILE, 1), WOOD_LINE)
	_fill(image, index, Rect2i(10, 0, 1, 7), WOOD_LINE)
	_fill(image, index, Rect2i(24, 8, 1, 7), WOOD_LINE)
	_fill(image, index, Rect2i(5, 16, 1, 7), WOOD_LINE)
	_fill(image, index, Rect2i(19, 24, 1, 7), WOOD_LINE)


## 磁磚地板：四格棋盤
func _draw_floor_tile(image: Image, index: int) -> void:
	_fill(image, index, Rect2i(0, 0, TILE, TILE), TILE_A)
	_fill(image, index, Rect2i(0, 0, 16, 16), TILE_B)
	_fill(image, index, Rect2i(16, 16, 16, 16), TILE_B)


## 牆：深色方塊，上緣亮一點看得出立體
func _draw_wall(image: Image, index: int) -> void:
	_fill(image, index, Rect2i(0, 0, TILE, TILE), WALL)
	_fill(image, index, Rect2i(0, 0, TILE, 4), WALL_TOP)


## 玻璃：半透明淺藍，外框和兩道反光
func _draw_glass(image: Image, index: int) -> void:
	_fill(image, index, Rect2i(0, 0, TILE, TILE), GLASS)
	_fill(image, index, Rect2i(0, 0, TILE, 2), GLASS_EDGE)
	_fill(image, index, Rect2i(0, TILE - 2, TILE, 2), GLASS_EDGE)
	_fill(image, index, Rect2i(0, 0, 2, TILE), GLASS_EDGE)
	_fill(image, index, Rect2i(TILE - 2, 0, 2, TILE), GLASS_EDGE)
	for i: int in 10:
		_fill(image, index, Rect2i(8 + i, 20 - i, 1, 1), GLASS_EDGE)
		_fill(image, index, Rect2i(14 + i, 24 - i, 1, 1), GLASS_EDGE)


## 草叢：綠底加深淺斑點
func _draw_bush(image: Image, index: int) -> void:
	_fill(image, index, Rect2i(0, 0, TILE, TILE), BUSH)
	for spot: Vector2i in [Vector2i(3, 4), Vector2i(18, 2), Vector2i(10, 14), Vector2i(24, 18), Vector2i(4, 24), Vector2i(17, 26)]:
		_fill(image, index, Rect2i(spot, Vector2i(6, 5)), BUSH_DARK)
	for spot: Vector2i in [Vector2i(12, 6), Vector2i(26, 9), Vector2i(2, 15), Vector2i(20, 12), Vector2i(10, 24), Vector2i(26, 27)]:
		_fill(image, index, Rect2i(spot, Vector2i(3, 3)), BUSH_LIGHT)


## 沼澤：暗綠色泥巴＋水窪
func _draw_swamp(image: Image, index: int) -> void:
	_fill(image, index, Rect2i(0, 0, TILE, TILE), SWAMP)
	for spot: Vector2i in [Vector2i(4, 5), Vector2i(18, 3), Vector2i(9, 17), Vector2i(22, 20)]:
		_fill(image, index, Rect2i(spot, Vector2i(8, 4)), SWAMP_WATER)
	for spot: Vector2i in [Vector2i(14, 11), Vector2i(3, 26), Vector2i(26, 12), Vector2i(17, 27)]:
		_fill(image, index, Rect2i(spot, Vector2i(3, 2)), SWAMP_DARK)
