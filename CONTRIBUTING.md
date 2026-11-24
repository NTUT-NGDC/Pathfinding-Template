# 貢獻指南

這份文件給想要幫忙開發、擴充尋路積木的人看。如果你只是想「拿工具來用」，請看 [README.md](README.md)。

## 開發環境

- 引擎版本：**Godot 4.7.2 (stable)**
- 下載連結：https://godotengine.org/download/archive/4.7.2-stable/
- ⚠️ 請大家統一使用同一個版本，避免場景檔案版本不相容

## 開發流程

1. 建立自己的分支：`git checkout -b feature/工具名稱`
2. 開發完成後 push，並開 Pull Request 到 main
3. 小改動可自行 merge；新增功能建議找人 review 一下

不熟 Git？看這裡：[Git 教學影片連結](https://youtu.be/9HyXQdwecOM)

## PR 標題格式

```
[工具名稱] 做了什麼事
```

範例：
- `[存檔系統] 新增基本存讀檔功能`
- `[UI Kit] 新增按鈕與對話框元件`
- `[場景管理] 修正切換時重複觸發的問題`

## PR 描述請包含

- **做了什麼**：簡單描述完成的功能
- **怎麼測試**：說明如何確認功能正常運作
- **需要注意的地方**：沒有就填「無」

（開 PR 時 GitHub 會自動帶出範本，照著填就好）

## 合併方式

本 repo 統一使用 **Squash and merge**，PR 合併後 main 上只會留下一條乾淨的紀錄，不用擔心開發過程 commit 訊息寫得亂。

> 因為 squash merge 會把 PR 標題變成 main 上的 commit 訊息，記得標題要照上面的格式寫清楚。

## 專案結構

這個 repo 是 W3 的**尋路積木**（GitHub Template repository）＝起手包＋積木＋範例，各組可以按 Use this template 開自己的 repo，或只把 `addons/ngdc_pathfinding/` 複製進用起手包開的專案。

- `core/`：起手包。**不要在這裡改**：先改 [Godot-GameJam-Tools](https://github.com/NTUT-NGDC/Godot-GameJam-Tools)，合併到它的 main 後，在這裡同步：

  ```
  git remote add upstream https://github.com/NTUT-NGDC/Godot-GameJam-Tools.git   # 第一次才要
  git pull upstream main
  ```

  README、`docs/ai_guide.md`、`CONTRIBUTING.md`、`game_config.tres`、`project.godot` 兩邊內容不一樣，衝突時保留這裡的版本，再把起手包新增的部分補進來
- `core/level_editor/`：關卡編輯器的底（也是起手包的一部分），三個範例的編輯器都繼承它。改它要三份範例測試＋`core_test` 都跑
- `addons/ngdc_pathfinding/`：尋路積木，**整包複製到別的專案也要能用**（不用 Autoload、不依賴 `examples/`；用到起手包的 GameFlow 時用 `get_node_or_null("/root/GameFlow")`，沒有就跳過）
- `examples/`：用積木組成的範例遊戲（追逐、塔防、戰棋），範例自己的小腳本放在範例的 `features/`
- `features/`、`levels/`、`shared/`：留給各組，保持空的
- `docs/`：給組員和 AI 讀的說明（`ai_guide.md` 要跟著積木更新）
- `_dev/`：開發用的工具（產生關卡、產生 tileset、截圖），不會匯出

## 新增積木時

- 放 `addons/ngdc_pathfinding/<積木>/`；資料夾、檔名一律 `snake_case`，場景直接放、腳本放 `scripts/`
- GDScript 一律**靜態型別**，不要有編輯器警告；`@export` 加 `##` 中文說明
- 積木要跟玩法無關：用 `@export` 調參數、用 signal 通知事件，彼此不寫死
- 附自動測試，用 headless 跑，失敗時 exit code 非 0：
  - `godot --headless --fixed-fps 60 --path . res://core/tests/core_test.tscn`
  - `godot --headless --fixed-fps 60 --path . res://addons/ngdc_pathfinding/tests/pathfinding_test.tscn`（還有 `chase_ai_test`、`astar_lab_test`）
  - `godot --headless --fixed-fps 60 --path . res://examples/_tests/chase_test.tscn`（還有 `tower_defense_test`、`tactics_test`）
  - `--fixed-fps 60` 一定要加：比較快，結果也不會受電腦忙不忙影響
- 範例的關卡用 `_dev/tools/make_examples.tscn` 從文字地圖產生，改地圖改那裡
- 更新 `addons/ngdc_pathfinding/README.md` 和 `docs/ai_guide.md`：有什麼、怎麼用、不要重寫什麼

## 需求規格

想知道每個工具該做到什麼程度？看這份文件：[工具需求規格連結](https://www.notion.so/3931803c84a480cc826de559676d9597?source=copy_link)
