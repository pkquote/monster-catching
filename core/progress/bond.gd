class_name Bond
extends RefCounted
## Bond (spec §2.11): how a creature feels about its trainer, -100..100. Low Bond
## makes it disobey or lash out; high Bond earns extra XP.

## Applies a Bond change from balance.bond.changes. Returns the actual change.
static func change(db: Database, c: CreatureInstance, happening: String) -> int:
	var cfg := db.balance.bond_cfg
	var delta: int = int(cfg.changes.get(happening, 0))
	var before := c.bond
	c.bond = clampi(c.bond + delta, cfg.min, cfg.max)
	return c.bond - before


## How far into negative Bond this creature is, 0..1.
static func deficit(db: Database, c: CreatureInstance) -> float:
	if c.bond >= 0:
		return 0.0
	return clampf(float(-c.bond) / float(-db.balance.bond_cfg.min), 0.0, 1.0)


static func disobey_chance(db: Database, c: CreatureInstance) -> float:
	return float(db.balance.bond_cfg.disobey_max_chance) * deficit(db, c)


## Multiplier on accuracy and damage from negative Bond (1.0 = no penalty).
static func performance(db: Database, c: CreatureInstance) -> float:
	return 1.0 - float(db.balance.bond_cfg.penalty_max) * deficit(db, c)


static func lash_out_chance(db: Database, c: CreatureInstance) -> float:
	if c.bond > db.balance.bond_cfg.lash_out_threshold:
		return 0.0
	return float(db.balance.bond_cfg.lash_out_chance)


## XP multiplier from positive Bond.
static func xp_mult(db: Database, c: CreatureInstance) -> float:
	if c.bond <= 0:
		return 1.0
	return 1.0 + float(db.balance.bond_cfg.xp_bonus_max) * float(c.bond) / float(db.balance.bond_cfg.max)


## Gives a starter its starting Bond.
static func make_starter(db: Database, c: CreatureInstance) -> void:
	c.bond = db.balance.bond_cfg.starter


## Resting at a rest point: full HP and energy, status cleared, Bond up.
static func rest(db: Database, c: CreatureInstance) -> int:
	c.heal_full(db)
	return change(db, c, "rested")
