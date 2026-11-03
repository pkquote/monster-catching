class_name Underdog
extends RefCounted
## Compensation for the outnumbered side. Pure function of the active counts.


## Returns { ratio, bonus_actions, stat_bonus, spread_reduction, xp_bonus }.
## Everything is zero unless `enemy_active > ally_active`.
static func compute(balance: BalanceDef, ally_active: int, enemy_active: int) -> Dictionary:
	var out := {"ratio": 1.0, "bonus_actions": 0, "stat_bonus": 0.0, "spread_reduction": 0.0, "xp_bonus": 0.0}
	if ally_active <= 0 or enemy_active <= ally_active:
		return out
	var u := balance.underdog
	var r := float(enemy_active) / float(ally_active)
	var step := r - 1.0
	out.ratio = r
	out.bonus_actions = int(floor(step * float(u.bonus_actions_per_ratio) + 0.0001))
	out.stat_bonus = minf(float(u.stat_bonus_cap), float(u.stat_bonus_per_ratio) * step)
	out.spread_reduction = minf(float(u.spread_reduction_cap), float(u.spread_reduction_per_ratio) * step)
	out.xp_bonus = float(u.xp_bonus_per_ratio) * step
	return out
