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

1. 先看 `docs/game_overview.md` 的**分工表**，找到現在這個人負責的功能和資料夾（還沒填的話，先請使用者說他負責哪裡，幫他填好再開始；名字不知道就問，不要自己編）
2. **只修改分工表上屬於這個人的資料夾**（通常是 `features/<功能名稱>/`）
3. 要動下面這些，**先停下來問使用者**，不要直接改：
   - 別人的資料夾
   - `core/`（起手包）、`addons/`（技術積木）：更新時會整包換掉，改了會不見
   - 主場景（專案最上層的 `levels/`）：由一個人負責組裝。範例自己的關卡 `examples/<範例>/levels/` 不算，照分工表改就好
   - `project.godot`（按鍵、Autoload、開始場景都在裡面，最容易衝突）
   - `shared/`：大家共用的東西
4. 新功能做成**獨立場景**，放在 `features/<功能名稱>/`，附一個 `test.tscn` 可以單獨測試；要放進遊戲時，交給主場景負責人在 `levels/` 放一個實例

## 資料夾

```
core/          起手包（不要改）
addons/        技術積木（不要改），每週一包，例如 addons/ngdc_pathfinding/
examples/      範例遊戲，從範例改的話直接在裡面改（資料夾填進分工表）
features/      每個功能一個資料夾，一個人負責
  <功能名稱>/
	<功能名稱>.tscn   場景直接放
	scripts/          腳本
	data/             資料（.tres）
	test.tscn         自己測試用
levels/        主場景，指定一個人負責組裝
shared/        大家都會用的東西（共用素材、常數），改之前先在組裡講
docs/          遊戲概要、分工表、這份說明
game_config.tres   遊戲名稱、關卡（Levels）、Credits 名單
```

## 已經有的功能（不要重寫）

| 功能 | 怎麼用 | 在哪 |
| --- | --- | --- |
| 標題畫面 | 開始遊戲／設定／製作名單／離開。遊戲名稱、關卡讀 `game_config.tres` | `core/screens/title_screen.tscn`（專案主場景） |
| 暫停選單 | **自動加進每個遊戲場景**，按 Esc 開關：繼續／重來／設定／回標題 | `core/screens/pause_menu.tscn` |
| 設定 | 音樂、音效音量（會記住）、全螢幕 | `core/screens/settings_panel.tscn` |
| 勝利／失敗畫面 | `GameFlow.win("訊息")`、`GameFlow.lose("訊息")`，會暫停遊戲、顯示再玩一次／回標題；「回標題」可以換成別的：`GameFlow.set_title_button("回編輯器", 要做的事)`、`GameFlow.reset_title_button()`；暫時不要暫停選單（藏起「選單」、Esc 沒反應）：`GameFlow.set_pause_enabled(false)`，換場景就恢復 | `core/screens/` |
| 關卡 | 把關卡場景拖進 `game_config.tres` 的 Levels。一關：開始遊戲直接進去；兩關以上：先到**關卡選擇**，勝利畫面有**下一關**，過關自動記住（`LevelProgress`）。換關卡不要自己寫 | `core/screens/level_select_screen.tscn` |
| 製作名單 | 名單寫在 `game_config.tres` 的 Credits（一行一個「職位：名字」） | `core/screens/credits_screen.tscn` |
| 換場景（有轉場） | `SceneManager.change_scene("res://...")`、`SceneManager.reload()`。**不要直接用 `get_tree().change_scene_to_file()`** | `core/scene_manager/` |
| BGM／音效 | 場景裡放 `SoundBank` 節點登記名字，`AudioManager.play_bgm("名字")`、`AudioManager.play_sfx("名字")` | `core/audio_manager/` |
| 存讀檔 | `SaveManager.save({...})`、`SaveManager.load_data()`；`GameSession.game_data` | `core/save_system/` |
| 分數 | `score_display.tscn` 拖進 CanvasLayer，`add(10)` 加分；group `score` | `core/hud/` |
| 計時 | `timer_display.tscn`，正數或倒數，倒數到 0 發 `time_up`（可設定時間到就輸／贏） | `core/hud/` |
| 血條 | `health_bar.tscn`，`damage(10)`、`heal(10)`，到 0 發 `died`（可設定死掉就輸） | `core/hud/` |
| 鏡頭 | `follow_camera.tscn` 拖進關卡：跟隨玩家（group `player`）或固定位置；可設長方形邊界（大小、偏移），編輯器裡會畫框。**不要在角色身上另外放 Camera2D**。策略、塔防用 `pan_camera.tscn`：WASD／方向鍵、滑鼠到邊緣、中鍵拖曳移動，滾輪縮放（可設要按 Ctrl），可設邊界（`set_limit_rect()`） | `core/camera/` |
| 關卡編輯器的底 | 要讓人「在遊戲裡畫關卡、放東西」就 `extends LevelEditor`：分頁、畫筆、上一步、存讀檔、試玩、做成關卡都有了，只寫自己的工具。從 `core/level_editor/sample/` 抄，步驟看 [README](../core/level_editor/README.md)。自動表單 `LevelEditorForm`、怪物／棋子這種場景頁 `LevelEditorScenePage` 也在裡面，**不要自己重寫編輯器** | `core/level_editor/` |
| 遊戲設定 | `GameConfig.current().game_name`、`.level_paths()`、`.credits` | `game_config.tres` |

### 技術積木：尋路（`addons/ngdc_pathfinding/`，說明在 [它的 README](../addons/ngdc_pathfinding/README.md)）

| 積木 | 怎麼用 |
| --- | --- |
| 尋路地圖 `PathGrid` | 場景裡放一個，指定牆／地板的 TileMapLayer；`find_path()`、`set_blocked()`、`would_block()`、`set_cost()`、`register_obstacle()`（門、打得壞的牆）；group `path_grid` |
| 跟著路徑走 `PathFollower` | 放在角色底下，`go_to(位置)`、`follow(節點)`、`walk(路)`（照指定的路走）、`stop()`、`remaining_distance()`（還有多遠到終點）；地圖變了自動改路 |
| 視野 `VisionSensor` | 距離 → 角度 → 射線；`target_seen`／`target_lost`、`sees_target` |
| 聲音 `SoundBus`＋耳朵 `Ear` | `SoundBus.emit_sound(位置, 範圍)`；Ear 發 `heard(position)` |
| 追逐 AI `ChaseAI` | 巡邏、查看、懷疑、追擊、搜尋；Marker2D 子節點當巡邏點；`caught(target)` |
| 移動範圍 `MoveRange` | `show_from(位置, 移動力)`、`reachable_cells()`、`path_to(cell)`、`tile_selected(cell)`；每個角色的規則不一樣用 `cost_rule`、`stop_rule` |
| 點擊移動 `ClickMover` | 點選／框選 group「units」的角色，點地圖就走 |
| 生怪器 `Spawner`＋小怪 `Walker` | 波次表（`Wave` 資源）、目標；`reached_goal`、`all_cleared` |
| 除錯顯示 `PathDebug` | 遊戲中按 F1～F5 |

**要做敵人走路、找路、追人、出怪、移動範圍：用上面的積木，不要自己寫 A\*。** 想看 A\* 怎麼運作：`addons/ngdc_pathfinding/demo/astar_lab/`。

### 範例（`examples/`）

| 範例 | 用到的積木 | 可以改成 |
| --- | --- | --- |
| `examples/chase/`：在房子裡拿東西、修發電機逃出去，兩隻追逐 AI 會看、會聽；有門、躲藏點、捕獸夾、警報、瓶子（[README](../examples/chase/README.md)） | 尋路地圖、追逐 AI、視野、聲音 | 潛行、恐怖逃脫、小精靈、外送 |
| `examples/tower_defense/`：蓋牆和塔排出迷宮，怪即時改路、繞太遠就拆牆；塔可以升級；怪物、砲塔都用掛件組；地圖、波次、怪物用編輯器做（[README](../examples/tower_defense/README.md)） | 尋路地圖、生怪器、跟著路徑走 | 塔防、殭屍圍城、路網規劃 |
| `examples/tactics/`：帶隊探索（小隊巡邏、視野、偷襲、紮營、招募）→ 布陣 → 照速度輪流打（自動／回合制）；棋子用特性組；地圖、小隊、棋子、規則、隊伍用編輯器做（[README](../examples/tactics/README.md)） | 尋路地圖、移動範圍、跟著路徑走、視野 | 戰棋、自走棋、潛行、小隊指揮 |

**從範例改之前，先讀那個範例的 README**，再看下面這張表找檔案：

| 想改 | 看哪裡 |
| --- | --- |
| 追逐：新的目標、新的互動物件 | 照 `examples/chase/features/task_point/`（「目標」接口寫在 README 最下面），放在自己的資料夾 `examples/chase/features/名字/名字.tscn`；按 E 的東西掛 `examples/chase/features/interact/scripts/interactable.gd` |
| 追逐：新的敵人、任務點……的種類 | 用編輯器的「敵人」「物件」頁，或寫一個繼承底的場景：敵人放 `examples/chase/features/enemies/`（繼承 `chase_ai.tscn`），其他放 `examples/chase/features/名字/kinds/`；名字寫 `metadata/display_name`，只寫跟底不一樣的欄位（照 `examples/chase/features/enemies/hound.tscn`）。敵人的欄位和範圍看 `chase_ai.gd` 的 `@export`：例如看不到 `view_distance = 0`、聽力 `hearing_multiplier` 0～3 |
| 追逐：新的敵人特性 | 照 `examples/chase/features/enemy_traits/trap_dropper.tscn`，一個特性＝一個場景＋一支腳本（`trait_name()`、`description()`、`labels()`），敵人頁會自動列出來。腳本放在敵人底下：`get_parent() as ChaseAI`，接 `state_changed(state)` 知道牠在做什麼（`ChaseAI.State.CHASE`＝開始追、`SEARCH`＝追丟了……），`caught(target)`＝抓到；發出聲音用 `SoundBus.emit_sound(位置, 範圍)` |
| 追逐：關卡 | 最好請使用者用編輯器（`examples/chase/map_editor/`，按「新地圖」就有一間能玩的房子）。你要自己做：**複製 `examples/chase/levels/chase.tscn` 再改**（PathGrid、Floor、Walls、Player、Exit、Darkness、FollowCamera、HUD 都要有）；`tile_map_data` 不能手寫，寫一個臨時場景用腳本 `set_cell()` 再存（圖塊 atlas x：0 木頭、1 磁磚、2 牆、3 玻璃、4 草叢、5 沼澤；0、1、5 畫在 Floor，其他畫在 Walls）。兩邊可以輪流改。自己的物件放 `examples/chase/features/名字/名字.tscn`，編輯器的「自製」會列出來 |
| 塔防：新的怪物掛件、砲塔掛件 | 照 `examples/tower_defense/features/enemy_traits/`、`examples/tower_defense/features/tower_traits/` 裡現成的，一個掛件＝一個場景＋一支腳本，編輯器會自動列出來 |
| 塔防：蓋東西、升級的規則 | `examples/tower_defense/features/builder/scripts/builder.gd`、`examples/tower_defense/features/tower/scripts/` |
| 戰棋：新的特性 | 照 `examples/tactics/features/unit_traits/`，繼承 `UnitTrait`，覆寫需要的函式（`modify_attack()`、`turn_started()`、`after_attack()`……），編輯器會自動列出來。中毒、燃燒這種掛在對方身上的狀態看戰棋 README 最下面 |
| 戰棋：新的職業 | 複製 `examples/tactics/features/units/` 裡的一個場景，改數值、掛特性 |
| 戰棋：電腦怎麼決定 | `examples/tactics/features/battle/scripts/battle_ai.gd` |
| 戰棋：輪流、扣血、勝負 | `examples/tactics/features/battle/scripts/tactics_battle.gd`（很長，先搜尋函式名稱）；動畫在 `battle_effects.gd`、箭頭和記號在 `battle_marks.gd` |
| 戰棋：新的地形 | `examples/tactics/features/map/scripts/tactics_map.gd` 最上面的註解寫了要改哪幾個地方 |
| 編輯器多一個欄位 | 戰棋小隊、規則：資料的腳本加 `@export`，再加到那一頁最上面的 `NUMBERS`。怪物、棋子：加到 `enemy_page.gd`／`unit_page.gd` 的 `fields` 和 `enemy_info.gd`／`unit_info.gd` 的欄位清單。追逐的敵人、物件、掛件、特性的欄位自動讀 `@export`，不用加 |

怪物、掛件、職業、特性的資料夾（`enemies/`、`enemy_traits/`、`tower_traits/`、`units/`、`unit_traits/`、`kinds/`）**第一層的 `.tscn` 都會被編輯器列出來**，測試場景放子資料夾。

**塔防、戰棋的地圖（`maps/*.tres`）不要用文字編輯，也不要整份讀**：地形存成編碼過的資料，一張幾十 KB。要看、要改地形先轉成文字：`godot --headless --path . res://core/level_editor/map_text.tscn -- export res://examples/tactics/maps/default.tres 檔案.txt`，改完把 `export` 換成 `import` 寫回去（圓滑的邊緣、小隊、規則都會留著；新地圖用 `new`，看 [關卡編輯器的 README](../core/level_editor/README.md)）。想畫得漂亮請使用者開 `map_editor/`。一張地圖同一時間只有一個人改，衝突時選一邊，不能合併。

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
- **改檔案前先關 Godot**：Godot 編輯器開著的時候改了磁碟上的檔案，Godot 會跳出「要不要重新載入」，使用者按錯就會用舊版蓋掉你的修改。所以改任何檔案（`.gd`／`.tscn`／`.tres`／`project.godot`）前，Godot 開著的話先正常關閉（不要強制結束，有沒存的修改 Godot 會先問），改完再用編輯器打開專案；你沒辦法自己關、開 Godot 的話，請使用者先關掉，改完再開。GDScript 不用編譯，重開很快。使用者說可以、或說他開的是別的專案，就直接做，不用一直停下來等。`--headless` 的驗證在編輯器開著時也可以跑

## 改完怎麼驗證

改完**一定要跑過**再說做好了。`godot` 換成這台電腦上 Godot 4.7.2 的執行檔路徑；`--headless` 不會開視窗，`--fixed-fps 60` 讓它不等時間、跑得快：

1. 新增了檔案或 `class_name`：先讓 Godot 認得（也會產生 `.uid`；第一次跑會有幾行字型的 `ERROR`，再跑一次就沒有）
   `godot --headless --path . --import`
2. 跑你改的場景約 5 秒，**看輸出有沒有 `ERROR`、`WARNING`**（有錯誤 exit code 也會是 0，一定要看文字）
   `godot --headless --fixed-fps 60 --path . res://features/<功能名稱>/test.tscn --quit-after 300`
3. 改了範例：跑那個範例的測試，每份幾秒，全部過會印「全部 PASS」，失敗時 exit code 是 1
   `godot --headless --fixed-fps 60 --path . res://examples/_tests/chase_test.tscn`（還有 `tower_defense_test`、`tactics_test`）
   測試檢查的是範例**原本**的規則。你故意改了規則（例如起始金錢）而失敗是正常的，告訴使用者是哪幾項；其他的失敗要修

- 不要用 `--check-only` 檢查腳本，`--script` 也一樣：不會載入 Autoload（GameFlow……），會報假的錯誤。要臨時試東西就做一個場景掛腳本，跑那個場景，試完刪掉
- 一次只跑一個 Godot，不要同時開好幾個
- headless 看不到畫面：跟畫面、手感有關的，請使用者按 F6 試玩


## 給使用者的建議

- 回答時說清楚**改了哪些檔案**，方便他們合併
- 使用者只說「做一個塔防」時，先問清楚：要用哪個現成的積木、有幾種塔、能不能把路堵死……再動手
- 做完一個功能，提醒使用者 commit、合併（每 20～30 分鐘合併一次）
