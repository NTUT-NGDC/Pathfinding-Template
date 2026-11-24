@tool
class_name UnitTraitKnockback
extends UnitTrait
## 擊退：把打到的敵人推開一格；後面是牆或有人的話推不動，多扣血。

## 撞到東西多扣多少
@export_range(0, 20, 1) var bump: int = 3



func trait_name() -> String:
	return "擊退"


func description() -> String:
	return "把敵人推開，撞到東西多扣血"


func labels() -> Dictionary:
	return {"bump": "撞到多扣"}


func after_attack(target: Unit, _damage: int, battle: TacticsBattle) -> void:
	if target.is_down:
		return
	var away: Vector2i = battle.cell_of(target) - battle.cell_of(unit)
	var push: Vector2i = Vector2i(signi(away.x), 0) if absi(away.x) >= absi(away.y) else Vector2i(0, signi(away.y))
	var to: Vector2i = battle.cell_of(target) + push
	if battle.can_stand(to):
		battle.note("　擊退：%s 被推開" % battle.name_of(target))
		await battle.slide(target, to)
	else:
		battle.hurt(target, bump, "撞到東西")
