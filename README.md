# NGDC 尋路積木（Pathfinding-Template）

北科遊戲研究社「每週協作專案」第 3 週：**尋路**。

這個 repo ＝ [起手包 Godot-GameJam-Tools](https://github.com/NTUT-NGDC/Godot-GameJam-Tools) ＋ 尋路積木（`addons/ngdc_pathfinding/`）＋ 3 個範例遊戲（`examples/`）。積木拖進場景、改檢查器就能用，沒有 AI 也能組出遊戲。

## 需要準備

| 項目 | 版本 | 說明 |
| --- | --- | --- |
| Godot | **4.7.2**（標準版，非 .NET） | [下載頁面](https://godotengine.org/download/archive/4.7.2-stable/)。請用這個版本，其他版本可能打不開專案 |
| Godot 匯出模板 | 4.7.2 | 匯出網頁版需要，在 Godot 裡「編輯器 → 管理匯出模板」下載 |
| GitHub 帳號 | | 組隊協作用 |

> 上課時教室網路慢，Godot 和匯出模板會放在社課的 USB 裡。

## 開始

**還沒開組的 repo**：

1. **一組一個人**按上方綠色的 **Use this template → Create a new repository**，開你們組的 repo，再把組員加成 Collaborator
2. 每個人 clone 下來，用 Godot 匯入 `project.godot`
3. 按 `F5`：標題 → 開始遊戲會進**追逐範例**，按 Esc 暫停
4. 三個範例都玩一下，全組一起填 **[docs/game_overview.md](docs/game_overview.md)**：一句話（經典玩法＋變化）、從哪個範例改、分工表
5. 把 `game_config.tres` 的 Levels 換成你們的主場景，開工！

**已經用起手包開好 repo 了**：把這裡的 `addons/ngdc_pathfinding/` 整個資料夾複製到你們專案的 `addons/` 就能用（不用改 `project.godot`）。想參考範例的話，`examples/` 也可以一起複製。

## 三個範例

| 範例 | 玩法 | 可以改成 |
| --- | --- | --- |
| [追逐](examples/chase/README.md) | 在房子裡撿齊寶物逃出去，追逐 AI 會看、會聽、會繞路追你 | 潛行、恐怖逃脫、小精靈、外送 |
| [塔防](examples/tower_defense/README.md) | 用牆和塔排迷宮，怪即時改路，繞太遠就拆牆 | 殭屍圍城、路網規劃 |
| [戰棋](examples/tactics/README.md) | 點棋子看移動範圍、點格子走過去，輪流行動 | 自走棋、小隊指揮、經營 |

每個範例的 README 都寫了「**不寫程式可以改什麼**」。

## 尋路積木

說明在 **[addons/ngdc_pathfinding/README.md](addons/ngdc_pathfinding/README.md)**：尋路地圖、跟著路徑走、視野、聲音和耳朵、追逐 AI、移動範圍、點擊移動、生怪器、除錯顯示（F1～F5）。

想看 A\* 怎麼找路：打開 `addons/ngdc_pathfinding/demo/astar_lab/astar_lab.tscn` 按 `F6`。

## 要改的地方

| 想改什麼 | 改哪裡 |
| --- | --- |
| 遊戲名稱、標語、關卡、製作名單 | 雙擊 **`game_config.tres`**，在檢查器改 |
| 你負責的功能 | `features/<功能名稱>/`（只改你自己的資料夾） |
| 主場景 | `levels/`（指定一個人負責）；從範例改的話，把範例的場景複製到 `levels/` |
| 關卡：按「開始遊戲」要進去的場景 | 雙擊 **`game_config.tres`**，把關卡場景依序拖進 Levels。一關就直接進去；兩關以上會有關卡選擇、下一關、過關解鎖 |
| 標題畫面的背景圖、字的顏色 | `core/screens/title_screen.tscn` 的檢查器（只改外觀） |

贏了、輸了：程式裡呼叫 `GameFlow.win("訊息")`、`GameFlow.lose("訊息")`，或在檢查器把 signal 連過去。

## 資料夾

| 資料夾 | 內容 |
| --- | --- |
| `core/` | 起手包，**不要改**（更新時整包換） |
| `addons/` | 技術積木，**不要改**（更新時整包換） |
| `examples/` | 範例遊戲，可以複製出來改 |
| `features/` | 每個功能一個資料夾、一個人負責 |
| `levels/` | 主場景，一個人負責組裝 |
| `shared/` | 大家都會用的東西，改之前先在組裡講 |
| `docs/` | 遊戲概要、分工表、協作規則、給 AI 的說明 |

## ⚠️ 協作規則（一定要看）

詳細在 **[docs/collaboration.md](docs/collaboration.md)**，重點：

- **每個人只動自己的資料夾**；主場景、`project.godot`、`game_config.tres` 由一個人改
- **每 20～30 分鐘合併一次**，開工前先 `git pull`
- `.tscn`、`.tres` 衝突了不要手動合併：選一邊保留，再把另一邊的小改動重做
- `.uid` 檔要 commit

## 用 AI 的話

`CLAUDE.md`、`AGENTS.md`、`GEMINI.md` 會讓 Claude Code、Codex、Gemini CLI 自動讀到 **[docs/ai_guide.md](docs/ai_guide.md)**：已經有哪些功能和積木、怎麼用、只能改哪些資料夾。

下指令時講清楚：用哪個現成的東西、要做什麼、**不要重寫什麼**。例如：

> 專案裡已經有 `addons/ngdc_pathfinding` 的生怪器和尋路地圖（說明在它的 README）。幫我在 `features/slow_tower/` 加一種緩速塔：範圍內的敵人速度減半，持續 2 秒。不要重寫生怪器。

## 上傳作品

1. 「專案 → 匯出」，選 **Web**，按「匯出專案」，存到 `build/index.html`
2. 把 `build` 資料夾裡的檔案全部壓成一個 zip
3. 上傳到 itch.io（Kind of project 選 HTML），再提交到社團的 Jam：

**🎮 [115-1 北科遊戲研究社交流會作品集](https://itch.io/jam/ntut-ngdc-meetup-115-1)**

想幫忙開發：看 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 授權

- 字型：俐方體 11 號（Cubic 11），SIL Open Font License 1.1，授權全文在 `core/fonts/Cubic_11_OFL.txt`
