class_name BattleAI
extends RefCounted
## 戰鬥的電腦：幫一隻棋子決定「走到哪一格、打誰」。敵人、自動戰鬥的我方都用這個。
## 把每個「走得到的格子 × 打得到的對象」都打一個分數，挑分數最高的；
## 誰都打不到，就沿著最省移動力的路往敵人靠近（尋路）。
##
## 個性（Unit.mind）只是算分數的方式不一樣：
## 玩家指定了目標（TacticsBattle.focus）的話，我方打得到就一定打它，誰都打不到就往它走。
##
##   衝鋒＝打最近的　守衛＝有人走進打得到的範圍才動　挑最弱的＝打血最少的　保持距離＝打得到就站最遠

var _battle: TacticsBattle
## 打不到的時候正往誰靠近
var _toward: Unit


func _init(battle: TacticsBattle) -> void:
	_battle = battle


## 回傳 {"cell": 走到哪, "target": 打誰（null＝不打）, "toward": 打不到、正往誰靠近（null＝不動）}。can_move＝還能不能走
func plan(unit: Unit, can_move: bool = true) -> Dictionary:
	var here: Vector2i = _battle.cell_of(unit)
	var moves: Dictionary[Vector2i, float] = {here: 0.0}
	if can_move:
		moves = _battle.legal_moves(unit)
	var best: Dictionary = {"cell": here, "target": null, "toward": null}
	var best_score: float = -INF
	for target: Unit in _battle.alive(-1):
		if not _battle.can_target(unit, target):
			continue
		for cell: Vector2i in moves:
			if not _battle.in_range(unit, cell, _battle.cell_of(target)):
				continue
			var score: float = _score(unit, target, cell, moves[cell])
			if score > best_score:
				best_score = score
				best = {"cell": cell, "target": target, "toward": null}
	if best["target"] != null or not can_move or _stays(unit):
		return best
	_toward = null
	var closer: Vector2i = _step_closer(unit, moves)
	return {"cell": closer, "target": null, "toward": _toward}


## 玩家指定要打的（只有我方會聽）
func _focus_of(unit: Unit) -> Unit:
	return _battle.focus if unit.team == 0 and is_instance_valid(_battle.focus) and not _battle.focus.is_down else null


## 站在 cell 打 target 有多好
func _score(unit: Unit, target: Unit, cell: Vector2i, spent: float) -> float:
	var score: float = -spent * 0.1                               # 少走一點比較好
	score += TacticsMap.KIND_DEFENSE[_battle.kind_at(cell)] * 1.5  # 站在森林裡比較安全
	if target.team == unit.team:                                  # 補血：缺越多越值得；快倒了最優先（比指定的目標還急）
		return score + minf(unit.heal_power, target.max_health - target.health) * 1.5 + ((200.0 if _focus_of(unit) != null else 8.0) if target.health * 3 < target.max_health else 0.0)
	if target == _focus_of(unit):
		score += 100.0                                            # 玩家指定的：打得到就一定打它
	var damage: int = mini(_battle.damage_of(unit, target, int(spent)), target.health)
	score += damage * 2.0
	if damage >= target.health:
		score += 12.0                                             # 打得倒
	match unit.mind:
		Unit.Mind.CHARGE:
			score -= _battle.distance(_battle.cell_of(unit), _battle.cell_of(target)) * 0.8
		Unit.Mind.WEAKEST:
			score -= target.health * 1.5
		Unit.Mind.DISTANCE:
			score += _nearest_foe(unit, cell) * 2.0
	if unit.max_range > 1 and unit.mind != Unit.Mind.CHARGE:
		score += _nearest_foe(unit, cell) * 0.5
	return score


## 守衛：沒有人來、也沒被打過，就站在原地（我方自動戰鬥時不會發呆）
func _stays(unit: Unit) -> bool:
	return unit.mind == Unit.Mind.GUARD and unit.team == 1 and not unit.provoked


## 誰都打不到：找「打得到某個敵人的格子」裡最省移動力的，往那邊走到這一輪走得到的地方
func _step_closer(unit: Unit, moves: Dictionary[Vector2i, float]) -> Vector2i:
	var here: Vector2i = _battle.cell_of(unit)
	var foes: Array[Unit] = _battle.alive(1 - unit.team)
	var groups: Array[Array] = [foes]
	if _focus_of(unit) != null:
		groups.push_front([_focus_of(unit)])                      # 先試著往指定的目標走
	for group: Array in groups:
		for ignore_units: bool in [false, true]:                  # 路被自己人堵住的話，當作沒有人再找一次
			_battle._use_rules(unit, not ignore_units)
			var all: Dictionary[Vector2i, float] = _battle.move_range.reachable_cells(here, 9999.0)
			var goal: Vector2i = here
			var cost: float = INF
			for cell: Vector2i in all:
				if all[cell] >= cost or not _battle.grid.is_cell_walkable(cell):
					continue
				if not ignore_units and cell != here and _battle.unit_at(cell) != null:
					continue
				for foe: Unit in group:
					if _battle.in_range(unit, cell, _battle.cell_of(foe)):
						goal = cell
						cost = all[cell]
						_toward = foe
						break
			if cost == INF:
				continue
			var path: Array[Vector2i] = _battle.move_range.path_to(goal)
			for i: int in range(path.size() - 1, -1, -1):         # 從終點往回找，這一輪走得到的最遠一格
				if moves.has(path[i]):
					return path[i]
	return _closest_cell(unit, moves)


## 真的沒有路：站到離敵人最近的地方
func _closest_cell(unit: Unit, moves: Dictionary[Vector2i, float]) -> Vector2i:
	var best: Vector2i = _battle.cell_of(unit)
	for cell: Vector2i in moves:
		if _nearest_foe(unit, cell) < _nearest_foe(unit, best):
			best = cell
	return best


## 最近的敵人離 cell 幾格
func _nearest_foe(unit: Unit, cell: Vector2i) -> float:
	var best: float = 99.0
	for foe: Unit in _battle.alive(1 - unit.team):
		best = minf(best, _battle.distance(cell, _battle.cell_of(foe)))
	return best
