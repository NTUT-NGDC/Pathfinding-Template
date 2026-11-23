# 給 AI 的說明（AI Guide）

這份文件給 AI 助手（Claude Code、Codex、Gemini CLI……）讀。`CLAUDE.md`、`AGENTS.md`、`GEMINI.md` 都指向這裡。
人也可以讀：想知道專案裡「已經有什麼、不要重寫什麼」，看這份就對了。

## 這是什麼專案

北科遊戲研究社「每週協作專案」的 Godot 起手包。2～3 人一組，一個晚上做出一款小遊戲。

- 引擎：**Godot 4.7.2**，只用 **GDScript**，2D，要能匯出 **Web**（Compatibility 渲染、畫面 1280×720）
- 美術用簡單幾何圖形；介面文字、註解用**繁體中文**
- 字型：`core/fonts/Cubic_11.woff2`（俐方體，像素字），字的大小用 11 的倍數；**不要用 emoji**（Web 版會變方框）

## ⚠️ 最重要的規則：只改自己的資料夾

這是多人協作的專案，**一次改一堆檔案最容易造成衝突**。

1. 先看 `docs/game_overview.md` 的**分工表**，找到現在這個人負責的功能和資料夾
2. **只修改分工表上屬於這個人的資料夾**（通常是 `features/<功能名稱>/`）
3. 要動下面這些，**先停下來問使用者**，不要直接改：
   - 別人的資料夾
   - `core/`（起手包）、`addons/`（技術積木）：更新時會整包換掉，改了會不見
   - 主場景（`levels/` 裡的場景）：由一個人負責組裝
   - `project.godot`（按鍵、Autoload、開始場景都在裡面，最容易衝突）
   - `shared/`：大家共用的東西
4. 新功能做成**獨立場景**，放在 `features/<功能名稱>/`，附一個 `test.tscn` 可以單獨測試；要放進遊戲時，交給主場景負責人在 `levels/` 放一個實例

## 資料夾

```
core/          起手包（不要改）
addons/        技術積木（不要改），每週一包，例如 addons/ngdc_pathfinding/
examples/      範例遊戲，可以從這裡複製來改
features/      每個功能一個資料夾，一個人負責
  <功能名稱>/
	<功能名稱>.tscn   場景直接放
	scripts/          腳本
	data/             資料（.tres）
	test.tscn         自己測試用
levels/        主場景，指定一個人負責組裝
shared/        大家都會用的東西（共用素材、常數），改之前先在組裡講
docs/          遊戲概要、分工表、這份說明
game_config.tres   遊戲名稱、開始場景、Credits 名單
```

## 已經有的功能（不要重寫）

| 功能 | 怎麼用 | 在哪 |
| --- | --- | --- |
| 標題畫面 | 開始遊戲／設定／製作名單／離開。遊戲名稱、開始場景讀 `game_config.tres` | `core/screens/title_screen.tscn`（專案主場景） |
| 暫停選單 | **自動加進每個遊戲場景**，按 Esc 開關：繼續／重來／設定／回標題 | `core/screens/pause_menu.tscn` |
| 設定 | 音樂、音效音量（會記住）、全螢幕 | `core/screens/settings_panel.tscn` |
| 勝利／失敗畫面 | `GameFlow.win("訊息")`、`GameFlow.lose("訊息")`，會暫停遊戲、顯示再玩一次／回標題；「回標題」可以換成別的：`GameFlow.set_title_button("回編輯器", 要做的事)`、`GameFlow.reset_title_button()`；暫時不要暫停選單（藏起「選單」、Esc 沒反應）：`GameFlow.set_pause_enabled(false)`，換場景就恢復 | `core/screens/` |
| 製作名單 | 名單寫在 `game_config.tres` 的 Credits（一行一個「職位：名字」） | `core/screens/credits_screen.tscn` |
| 換場景（有轉場） | `SceneManager.change_scene("res://...")`、`SceneManager.reload()`。**不要直接用 `get_tree().change_scene_to_file()`** | `core/scene_manager/` |
| BGM／音效 | 場景裡放 `SoundBank` 節點登記名字，`AudioManager.play_bgm("名字")`、`AudioManager.play_sfx("名字")` | `core/audio_manager/` |
| 存讀檔 | `SaveManager.save({...})`、`SaveManager.load_data()`；`GameSession.game_data` | `core/save_system/` |
| 分數 | `score_display.tscn` 拖進 CanvasLayer，`add(10)` 加分；group `score` | `core/hud/` |
| 計時 | `timer_display.tscn`，正數或倒數，倒數到 0 發 `time_up`（可設定時間到就輸／贏） | `core/hud/` |
| 血條 | `health_bar.tscn`，`damage(10)`、`heal(10)`，到 0 發 `died`（可設定死掉就輸） | `core/hud/` |
| 鏡頭 | `follow_camera.tscn` 拖進關卡：跟隨玩家（group `player`）或固定位置；可設長方形邊界（大小、偏移），編輯器裡會畫框。**不要在角色身上另外放 Camera2D**。策略、塔防用 `pan_camera.tscn`：WASD／方向鍵、滑鼠到邊緣、中鍵拖曳移動，滾輪縮放（可設要按 Ctrl），可設邊界（`set_limit_rect()`） | `core/camera/` |
| 遊戲設定 | `GameConfig.current().game_name`、`.start_scene`、`.credits` | `game_config.tres` |

### 技術積木：尋路（`addons/ngdc_pathfinding/`，說明在 [它的 README](../addons/ngdc_pathfinding/README.md)）

| 積木 | 怎麼用 |
| --- | --- |
| 尋路地圖 `PathGrid` | 場景裡放一個，指定牆／地板的 TileMapLayer；`find_path()`、`set_blocked()`、`would_block()`、`set_cost()`；group `path_grid` |
| 跟著路徑走 `PathFollower` | 放在角色底下，`go_to(位置)`、`follow(節點)`、`stop()`；地圖變了自動改路 |
| 視野 `VisionSensor` | 距離 → 角度 → 射線；`target_seen`／`target_lost`、`sees_target` |
| 聲音 `SoundBus`＋耳朵 `Ear` | `SoundBus.emit_sound(位置, 範圍)`；Ear 發 `heard(position)` |
| 追逐 AI `ChaseAI` | 巡邏、查看、懷疑、追擊、搜尋；Marker2D 子節點當巡邏點；`caught(target)` |
| 移動範圍 `MoveRange` | `show_from(位置, 移動力)`、`tile_selected(cell)` |
| 點擊移動 `ClickMover` | 點選／框選 group「units」的角色，點地圖就走 |
| 生怪器 `Spawner`＋小怪 `Walker` | 波次表（`Wave` 資源）、目標；`reached_goal`、`all_cleared` |
| 除錯顯示 `PathDebug` | 遊戲中按 F1～F5 |

**要做敵人走路、找路、追人、出怪、移動範圍：用上面的積木，不要自己寫 A\*。** 想看 A\* 怎麼運作：`addons/ngdc_pathfinding/demo/astar_lab/`。

### 範例（`examples/`）

| 範例 | 用到的積木 | 可以改成 |
| --- | --- | --- |
| `examples/chase/`：在房子裡拿東西、修發電機逃出去，被追逐 AI 追；有捕獸夾（AI 追丟會放）、警報、可以丟的瓶子（出口條件看「目標」接口：group `objectives`＋`required`／`is_done`／`category`＋`completed`，說明在範例 README） | 尋路地圖、追逐 AI、視野、聲音 | 潛行、恐怖逃脫、小精靈、外送 |
| `examples/tower_defense/`：點格子放牆／塔，怪即時改路；地圖用地圖編輯器畫（`map_editor/`，存在 `maps/`，出怪口、基地可以好幾個，基地規則看 `BaseGroup`；地形有岩石、沼澤、高地，地圖裡勾哪種地面可以蓋塔、蓋牆（`TDMap.tower_ground`、`wall_ground`：迷宮型蓋空地、固定路線型只蓋高地）；試玩在編輯器裡直接玩）；怪物掛件（`enemy_traits/`：加速、厚血、裝甲、會飛、分裂、治療）、砲塔掛件（`tower_traits/`：緩速、範圍、多重射擊）拖到怪或塔底下就生效 | 尋路地圖、生怪器、跟著路徑走 | 塔防、殭屍圍城、路網規劃 |
| `examples/tactics/`：點角色看移動範圍、點格子走過去 | 尋路地圖、移動範圍、跟著路徑走 | 戰棋、自走棋、小隊指揮、經營 |

### 已經設定好的按鍵（`project.godot`，不用再加）

| 動作名稱 | 按鍵 |
| --- | --- |
| `move_up`／`move_down`／`move_left`／`move_right` | WASD、方向鍵 |
| `run` | Shift（跑步） |
| `interact` | E |
| `attack` | J、空白鍵 |
| `pause` | Esc（暫停選單已經在用） |
| `skill_1`／`skill_2`／`skill_3` | 1、2、3 |
| `mouse_left`／`mouse_right` | 滑鼠左鍵、右鍵 |
| `debug_1`～`debug_5` | F1～F5（尋路積木的除錯顯示用 F1～F5） |

讀移動：`Input.get_vector("move_left", "move_right", "move_up", "move_down")`

### 物理層（已經命名好）

| 層 | 名稱 | 用途 |
| --- | --- | --- |
| 1 | 擋路 | 牆、障礙物；角色身體撞這層 |
| 2 | 擋視線 | 視線射線只檢查這層 |
| 3 | 玩家 | |
| 4 | 敵人 | |
| 5 | 互動 | 可以按 E 互動的範圍 |

## 寫程式的規則

- GDScript 一律寫**靜態型別**（`var hp: int = 10`、`func hit() -> void:`），不要有編輯器警告
- 檔案、資料夾、變數 `snake_case`，類別 `PascalCase`，場景和腳本同名
- 場景之間用 **signal** 溝通，不要用很長的節點路徑去抓別人的節點；要找全場唯一的東西用 group
- 給人調的數字用 `@export`，加 `##` 中文說明（會顯示在檢查器），數值用 `@export_range`
- 移動、計時都乘 `delta`
- 要讓人改的資料用 `.tres`（不要用 `.json`／`.txt`，Web 匯出不會帶上）
- `.uid` 檔要 commit（Godot 4.4 之後腳本旁邊都有），`.godot/` 不要
- **改檔案前先關 Godot**：Godot 編輯器開著的時候改了磁碟上的檔案，Godot 會跳出「要不要重新載入」，使用者按錯就會用舊版蓋掉你的修改。所以改任何檔案（`.gd`／`.tscn`／`.tres`／`project.godot`）前，Godot 開著的話先正常關閉（不要強制結束，有沒存的修改 Godot 會先問），改完再用編輯器打開專案；你沒辦法自己關、開 Godot 的話，請使用者先關掉，改完再開。GDScript 不用編譯，重開很快

## 給使用者的建議

- 回答時說清楚**改了哪些檔案**，方便他們合併
- 使用者只說「做一個塔防」時，先問清楚：要用哪個現成的積木、有幾種塔、能不能把路堵死……再動手
- 做完一個功能，提醒使用者 commit、合併（每 20～30 分鐘合併一次）
