class_name BattleMath
extends RefCounted
## Battle formulas: effective stats, damage, accuracy, Resolve, catch chance.
## Rolls use the engine's seeded RNG; `roll = false` gives the average (for AI).

const ROLL_MIN := 0.85
const ROLL_MAX := 1.0
const ROLL_AVG := 0.925
const UNDERDOG_STATS := ["patk", "pdef", "satk", "sdef"]


## Stat after training, stages, passive stat_mods (statuses + own field) and Underdog.
## "acc" returns a multiplier (1.0 = normal) that also includes the Bond penalty;
## others return a stat value.
static func effective_stat(engine: BattleEngine, b: Battler, stat: String) -> float:
	var v: float
	if stat == "acc":
		v = Progression.bond_performance(engine.db, b.creature)
	else:
		v = float(b.creature.stat(engine.db, stat))
	v *= Stats.stage_mult(stat, b.stages[stat])
	for p in engine.passives(b):
		if p.op == "stat_mod" and p.stat == stat:
			v *= float(p.mult)
	if stat in UNDERDOG_STATS:
		v *= 1.0 + float(engine.sides[b.side].underdog.get("stat_bonus", 0.0))
	return v


## Attack/defense stat pair a damage effect uses: physical -> patk/pdef, special -> satk/sdef.
static func stat_pair(ctx: EffectContext) -> Array:
	var category := ctx.move.category if ctx.move != null else "physical"
	return ["satk", "sdef"] if category == "special" else ["patk", "pdef"]


## Returns { amount: int, type_mult: float }. amount is 0 only when type_mult is 0.
static func damage(engine: BattleEngine, ctx: EffectContext, e: Dictionary, target: Battler,
		roll: bool) -> Dictionary:
	var db := engine.db
	var power := ctx.damage_power(e)
	var type := ctx.damage_type(e)
	var type_mult := db.type_multiplier(type, target.creature.species_def(db).types)
	if power <= 0 or type_mult == 0.0:
		return {"amount": 0, "type_mult": type_mult}
	var user := ctx.user
	var level := user.creature.level if user != null else 1
	var ratio := 1.0
	if not ctx.is_reaction() and user != null:
		var pair := stat_pair(ctx)
		ratio = effective_stat(engine, user, pair[0]) / maxf(1.0, effective_stat(engine, target, pair[1]))
	var base := ((2.0 * level / 5.0 + 2.0) * power * ratio) / 50.0 + 2.0
	var mult := type_mult * ctx.mult
	if not ctx.is_reaction() and user != null:
		if user.creature.species_def(db).types.has(type):
			mult *= db.balance.stab
		mult *= Progression.bond_performance(db, user.creature)
	for p in engine.side_passives(target.side) + engine.status_passives(target):
		if p.op == "incoming_type_mod" and p.type == type:
			mult *= float(p.mult)
	if ctx.spread:
		var reduction := float(engine.sides[target.side].underdog.get("spread_reduction", 0.0))
		mult *= db.balance.spread_mult * (1.0 - reduction)
	var r := engine.rng.randf_range(ROLL_MIN, ROLL_MAX) if roll else ROLL_AVG
	return {"amount": maxi(1, int(base * mult * r)), "type_mult": type_mult}


## Hit chance in percent (may exceed 100).
static func hit_chance(engine: BattleEngine, user: Battler, move: MoveDef) -> float:
	if move.always_hits:
		return 1000.0
	return move.accuracy * effective_stat(engine, user, "acc")


static func rolls_hit(engine: BattleEngine, user: Battler, move: MoveDef) -> bool:
	if move.always_hits:
		return true
	return engine.rng.randf() * 100.0 < hit_chance(engine, user, move)


## Chance `target` resists a status or stat drop from `source` (0..resist_cap).
static func resist_chance(engine: BattleEngine, target: Battler, source: Battler) -> float:
	var level := source.creature.level if source != null else target.creature.level
	return Stats.resolve_chance(effective_stat(engine, target, "resolve"), level,
		float(engine.db.balance.resolve_cfg.resist_cap))


## Chance `target` endures a knockout blow at 1 HP (0..endure_cap).
static func endure_chance(engine: BattleEngine, target: Battler, attacker: Battler) -> float:
	var level := attacker.creature.level if attacker != null else target.creature.level
	return Stats.resolve_chance(effective_stat(engine, target, "resolve"), level,
		float(engine.db.balance.resolve_cfg.endure_cap))


## Catch chance 0..1 for a capture effect against `target`.
static func capture_chance(engine: BattleEngine, target: Battler, e: Dictionary) -> float:
	var db := engine.db
	var cfg := db.balance.catch_cfg
	var max_hp := float(target.creature.max_hp(db))
	var hp_factor := 1.0 - (float(target.hp()) / max_hp) * float(cfg.hp_weight)
	var status_mult := float(cfg.status_mult) if target.status() != "" else 1.0
	var field_mult := 1.0
	var bonus: Dictionary = e.get("field_bonus", {})
	var field := engine.sides[target.side].field
	for state in bonus:
		if field.has(state):
			field_mult *= float(bonus[state])
	var p := target.creature.species_def(db).catch_rate * float(e.get("mult", 1.0)) * hp_factor * status_mult * field_mult
	return clampf(p, 0.0, 1.0)
