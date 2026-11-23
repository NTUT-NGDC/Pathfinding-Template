# 尋路積木（ngdc_pathfinding）

W3「尋路」的技術積木。每個積木都是一個場景，**拖進場景、改檢查器就能用**，彼此用 signal 溝通，跟玩法無關。

想做的玩法不在範例裡也沒關係：潛行、恐怖逃脫、小精靈、塔防、殭屍、戰棋、小隊指揮、經營……都是這幾個積木的組合。

## 先放這兩個

1. **地圖**：場景裡放兩張 TileMapLayer（地板、牆），TileSet 用 `grid/tileset/tileset.tres`
2. **尋路地圖** `grid/path_grid.tscn`：拖進場景，在檢查器把牆那張拖進 Walls、地板那張拖進 Floor Layer

| tile | 擋視線 | 擋路 | 移動成本 |
| --- | --- | --- | --- |
| 木頭地板、磁磚地板 | | | 1 |
| 牆（深灰） | ✅ | ✅ | |
| 玻璃（淺藍）：看得到但過不來 | | ✅ | |
| 草叢（綠）：可以穿過去躲 | ✅ | | 1 |
| 沼澤（暗綠）：畫在地板那層 | | | 3（走一格等於走三格） |

- 沒畫地板的地方（房子外面）不能走
- 想讓某種 tile 更慢：打開 TileSet，在那個 tile 的自訂資料「移動成本」填數字
- 一格 32 像素；物理層 1 是「擋路」、2 是「擋視線」

## 積木

| 積木 | 做什麼 | 主要設定 | Signal |
| --- | --- | --- | --- |
| **尋路地圖** `grid/path_grid.tscn` | 從 TileMapLayer 建 A* 格子；地圖變了通知大家 | 斜走模式 | `map_changed` |
| **跟著路徑走** `follower/path_follower.tscn` | 放在角色底下；`go_to(位置)` 或 `follow(節點)` 就會繞路走過去 | 速度、重算間隔（預設 0.2 秒）、使用尋路、開門要幾秒 | `arrived`、`path_blocked` |
| **視野** `vision/vision_sensor.tscn` | 距離 → 角度 → 射線三關，畫出被牆切掉的視野錐 | 距離、角度、牆會擋視線、檢查角度、目標 group、顯示視野錐 | `target_seen`、`target_lost` |
| **耳朵** `hearing/ear.tscn` | 有人 `SoundBus.emit_sound(位置, 範圍)`，在範圍內就聽到 | 有沒有開、聽力倍率 | `heard(position)` |
| **追逐 AI** `chase_ai/chase_ai.tscn` | 巡邏 → 查看聲音 → 懷疑 ? → 追擊 ! → 搜尋最後位置；底下加 Marker2D 當巡邏點 | 個性（視野、速度、反應時間、搜尋時間……）、開關（牆擋視線、檢查角度、記住最後位置、使用尋路）、抓到就輸 | `caught(target)`、`state_changed` |
| **移動範圍** `move_range/move_range.tscn` | `show_from(位置, 移動力)` 亮出走得到的格子（吃移動成本） | 顏色、能不能點 | `tile_selected(cell)`、`cancelled` |
| **點擊移動** `click_move/click_mover.tscn` | 點選／框選角色（group「units」，底下要有 PathFollower），點地圖就走過去 | 可否多選、散開距離 | `selection_changed`、`commanded` |
| **生怪器** `spawner/spawner.tscn` | 照波次表出怪，怪自動走向目標 | 目標、波次表（出幾隻、間隔、速度、血量）、走到就輸、打完就贏 | `wave_started`、`spawned`、`reached_goal`、`all_cleared` |
| **小怪** `spawner/walker.tscn` | 生怪器預設出的怪，`damage(n)` 扣血 | 速度、血量、分數、顏色 | `died` |

### 除錯顯示（遊戲中按）

F1 視野錐　F2 路徑　F3 追逐 AI 狀態　F4 聲音圈圈　F5 格子線（紅＝擋路、黃＝成本高）

### 會變的地圖

- 塔防放牆：`grid.set_blocked(格子, true)`；放之前先問 `grid.would_block(格子, 出怪口, 基地)`，會把路堵死就不要放
- 殭屍挑弱的門：`grid.set_cost(格子, 10)` 讓堅固的門很貴
- 門這種會開關的東西：做成 obstacle（加進 group「path_obstacles」，有 `blocks_path`、`path_cost`、`is_open`、`open()`、signal `obstacle_changed`），尋路地圖會自動登記；PathFollower 遇到關著的門會停下來開。範例：`examples/chase/features/door/`
- 地圖一變，所有正在走路的角色會自動重算路徑

### 被追的目標可以有（都可以沒有）

- `is_hidden`：true 時看不到、抓不到
- signal `hid(spot)`：躲進去時發出；被追逐 AI 親眼看到會走過去把它拖出來
- `get_caught()`：被抓到時呼叫

## A* 實驗室

`demo/astar_lab/astar_lab.tscn`（按 F6）：主題課示範用。自己寫的 BFS／A*（`grid_search.gd`），可以一步一步看、調估計權重、畫牆和沼澤。積木實際用的是 Godot 內建的 AStarGrid2D（比較快，但看不到中間過程）。

## 給下週

整個 `addons/ngdc_pathfinding/` 資料夾複製進自己的專案就能用，不需要設定 Autoload（SoundBus、除錯顯示會自己建立）。

## 測試

```
godot --headless --path . res://addons/ngdc_pathfinding/tests/pathfinding_test.tscn
godot --headless --path . res://addons/ngdc_pathfinding/tests/chase_ai_test.tscn
godot --headless --path . res://addons/ngdc_pathfinding/tests/astar_lab_test.tscn
```
