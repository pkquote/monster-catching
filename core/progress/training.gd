class_name Training
extends RefCounted
## Training points (spec §2.10): earned per level, spent on stats, refunded by a
## Reset Seed. One point adds +1 to a stat (+2 to HP), capped per stat.

static func total(db: Database, c: CreatureInstance) -> int:
	return (c.level - 1) * int(db.balance.training_cfg.points_per_level)


static func spent(c: CreatureInstance) -> int:
	var n := 0
	for k in c.training:
		n += int(c.training[k])
	return n


static func available(db: Database, c: CreatureInstance) -> int:
	return total(db, c) - spent(c)


## Puts `points` into `stat`. Returns "" on success, or why it was refused.
## HP and energy gained this way are added to current HP/energy too.
static func train(db: Database, c: CreatureInstance, stat: String, points: int) -> String:
	var refused := _train(db, c, stat, points)
	if refused == "":
		Log.debug(Log.PROGRESS, "Trained", {"species": c.species, "stat": stat, "points": points,
			"now": c.trained(stat)})
	else:
		Log.debug(Log.PROGRESS, "Training refused", {"species": c.species, "stat": stat, "reason": refused})
	return refused


static func _train(db: Database, c: CreatureInstance, stat: String, points: int) -> String:
	if not stat in DataSchemas.TRAINABLE_STATS:
		return "not_trainable"
	if points <= 0:
		return "bad_amount"
	if points > available(db, c):
		return "not_enough_points"
	if c.trained(stat) + points > int(db.balance.training_cfg.max_per_stat):
		return "stat_capped"
	var old_hp := c.max_hp(db)
	var old_energy := c.max_energy(db)
	c.training[stat] = c.trained(stat) + points
	if c.hp > 0:
		c.hp += c.max_hp(db) - old_hp
	c.energy += c.max_energy(db) - old_energy
	return ""


## Refunds every trained point. Max HP/energy drop by what training gave, and
## current HP/energy are clamped (a living creature keeps at least 1 HP; a
## fainted one stays at 0). Returns the points refunded.
static func reset(db: Database, c: CreatureInstance) -> int:
	var refunded := spent(c)
	Log.info(Log.PROGRESS, "Training reset", {"species": c.species, "refunded": refunded})
	c.training = {}
	if c.hp > 0:
		c.hp = clampi(c.hp, 1, c.max_hp(db))
	c.energy = mini(c.energy, c.max_energy(db))
	return refunded
