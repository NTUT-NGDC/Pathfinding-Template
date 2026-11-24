class_name TacticsFormation
extends RefCounted
## 隊形：算出每一隻跟帶頭的差多遠、實際可以站在哪一格。我方（TacticsParty）和敵人小隊（EnemySquad）都用。

## 一列＝一個跟一個；橫排＝左右排開；箭頭＝往兩邊斜後；圍一圈＝圍著帶頭的
enum Kind { COLUMN, ROW, ARROW, CIRCLE }
const NAMES: Array[String] = ["一列", "橫排", "箭頭", "圍一圈"]


## 第 index 隻（0＝帶頭的）跟帶頭的差多遠。count＝總共幾隻，heading＝面向哪裡，spacing＝間隔
static func offset(kind: Kind, index: int, count: int, heading: Vector2, spacing: float) -> Vector2:
	if index == 0:
		return Vector2.ZERO
	var side: Vector2 = heading.orthogonal() * (1.0 if index % 2 == 1 else -1.0)   # 輪流站右邊、左邊
	var rank: int = (index + 1) / 2
	match kind:
		Kind.ROW:
			return side * rank * spacing
		Kind.ARROW:
			return (side - heading) * rank * spacing * 0.8
		Kind.CIRCLE:
			var radius: float = maxf(spacing, (count - 1) * spacing / TAU)
			return heading.rotated(TAU * (index - 1) / (count - 1)) * radius
	return -heading * index * spacing


## 想站在 want，實際可以站哪一格：從 goal 像水一樣往外找，挑離 want 最近的空格（牆的另一邊不會被挑到）
static func slot(grid: PathGrid, goal: Vector2i, want: Vector2, taken: Dictionary[Vector2i, bool]) -> Vector2i:
	var limit: int = ceili(grid.cell_center(goal).distance_to(want) / grid.cell_size().x) + 3
	var steps: Dictionary[Vector2i, int] = {goal: 0}
	var todo: Array[Vector2i] = [goal]
	var best: Vector2i = goal
	var best_distance: float = INF
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_front()
		var far: float = grid.cell_center(cell).distance_to(want)
		if far < best_distance and not taken.has(cell):
			best = cell
			best_distance = far
		if steps[cell] >= limit:
			continue
		for next: Vector2i in grid.neighbors(cell):
			if not steps.has(next):
				steps[next] = steps[cell] + 1
				todo.append(next)
	return best
