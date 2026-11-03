class_name Stats
extends RefCounted
## Stat and experience formulas. All pure functions.


## HP at a level: 2*base*level/100 + level + 10
static func hp_at(base: int, level: int) -> int:
	return (2 * base * level) / 100 + level + 10


## Physical/Special Atk/Def, Spd, Luck, Resolve at a level: 2*base*level/100 + 5
static func stat_at(base: int, level: int) -> int:
	return (2 * base * level) / 100 + 5


## Max energy from base Stamina: 2*base*level/100 + flat
static func energy_at(base_stamina: int, level: int, flat: int) -> int:
	return (2 * base_stamina * level) / 100 + flat


## Total XP needed to reach `level` (level 1 = 0).
static func xp_for_level(level: int) -> int:
	return 0 if level <= 1 else level * level * level


## Multiplier for a stat stage in -6..6. Accuracy uses a gentler curve.
static func stage_mult(stat: String, stage: int) -> float:
	var base := 3.0 if stat == "acc" else 2.0
	if stage >= 0:
		return (base + stage) / base
	return base / (base - stage)


## XP a defeated creature gives one participant (before Bond bonus).
static func xp_reward(balance: BalanceDef, defeated_yield: int, defeated_level: int,
		is_tamer_battle: bool, underdog_bonus: float) -> int:
	var xp := float(defeated_yield * defeated_level) / float(balance.xp_cfg.divisor)
	if is_tamer_battle:
		xp *= float(balance.xp_cfg.tamer_mult)
	xp *= 1.0 + underdog_bonus
	return maxi(1, int(xp))


## Resolve-based resistance: cap * R / (R + R_avg), where R_avg is an average
## (base 50) creature's Resolve at the opposing level.
static func resolve_chance(resolve: float, opposing_level: int, cap: float) -> float:
	var avg := float(stat_at(50, opposing_level))
	return cap * resolve / maxf(1.0, resolve + avg)
