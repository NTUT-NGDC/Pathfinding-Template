# 範例：塔防

怪從左邊的出怪口出來，走向右邊的基地。用牆和塔排出迷宮，怪會即時改路；基地被摸 10 次就輸，撐過 3 波就贏。

- 打開 `levels/tower_defense.tscn` 按 `F6`
- 操作：`1` 選牆（1 元）、`2` 選塔（4 元）、滑鼠左鍵蓋、右鍵拆（退一半）；打死怪加錢
- 不能把路完全堵死：會堵死的格子會變紅、蓋不下去
- 除錯：`F2` 路徑、`F5` 格子線

## 用到的積木

尋路地圖（PathGrid：`set_blocked`、`would_block`）、生怪器（Spawner）、小怪（Walker）、跟著路徑走（地圖變了自動改路）

範例自己的小腳本在 `features/`：蓋東西（builder）、塔（tower）、基地（base）、波數文字（hud）。

## 不寫程式可以改什麼

| 想改 | 怎麼改 |
| --- | --- |
| 地圖 | 點 `Walls` 畫牆、`Floor` 畫沼澤（怪走起來慢，會繞路） |
| 波次 | 點 `Spawner`，在「Waves」改每一波出幾隻、間隔、速度、血量；按「＋」多一波 |
| 怪長什麼樣 | 複製 `addons/ngdc_pathfinding/spawner/walker.tscn` 改顏色、大小、血量、分數，再拖進波次的「Enemy Scene」 |
| 塔 | 點 `features/tower/tower.tscn`，改射程、傷害、攻速、顏色 |
| 價錢、起始金錢 | `Builder` 的 Wall Cost／Tower Cost；`HUD/Info/Money` 的 Score |
| 基地血量 | `Base` 的 Max Health |
| 勝負 | `Spawner` 的「打完就贏」；`Base` 扣光就輸 |

## 可以改成

- **塔防，但塔本身就是牆**：拿掉牆，只能蓋塔
- **殭屍圍城**：基地換成房子，用 `PathGrid.set_cost()` 讓堅固的門很貴，殭屍會挑弱的門
- **路網規劃**：牆換成「路」（反過來：只有路可以走）
