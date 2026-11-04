class_name Progression
extends RefCounted
## XP, levelling, Affinity and growth rules. Mutates CreatureInstances and
## returns event dictionaries describing what happened.


## Adds XP, levels up as many times as earned, learns moves (into free slots only;
## a full moveset reports `move_offered` for the UI to decide).
static func award_xp(db: Database, c: CreatureInstance, amount: int, bid: int = -1) -> Array:
	var events: Array = []
	if amount <= 0 or c.level >= db.balance.level_cap:
		return events
	c.xp += amount
	events.append({"type": BattleEvents.XP_GAIN, "bid": bid, "amount": amount})
	while c.level < db.balance.level_cap and c.xp >= Stats.xp_for_level(c.level + 1):
		var old_max := c.max_hp(db)
		var old_energy := c.max_energy(db)
		c.level += 1
		# Keep damage taken / energy spent the same; the gain is added on top.
		if c.hp > 0:
			c.hp += c.max_hp(db) - old_max
		c.energy += c.max_energy(db) - old_energy
		events.append({"type": BattleEvents.LEVEL_UP, "bid": bid, "level": c.level,
			"training_points": training_points_available(db, c)})
		for l in c.species_def(db).learnset:
			if l.level != c.level or c.moves.has(l.move):
				continue
			if c.moves.size() < db.balance.max_moves:
				c.moves.append(l.move)
				events.append({"type": BattleEvents.MOVE_LEARNED, "bid": bid, "move": l.move})
			else:
				events.append({"type": BattleEvents.MOVE_OFFERED, "bid": bid, "move": l.move})
	return events


## Adds Affinity points for a battle happening (see balance.affinity_awards).
## Returns the affinity id that was credited, or "".
static func award_affinity(db: Database, c: CreatureInstance, happening: String, times: int = 1) -> String:
	var award: Dictionary = db.balance.affinity_awards.get(happening, {})
	if award.is_empty() or award.points == 0 or times <= 0:
		return ""
	c.affinity[award.affinity] = int(c.affinity.get(award.affinity, 0)) + award.points * times
	return award.affinity


## Affinity id with the most points, or "" if every track is 0.
## Ties go to the track listed first in data/affinities.json.
static func dominant_affinity(db: Database, c: CreatureInstance) -> String:
	var best := ""
	var best_points := 0
	for a in db.ids("affinities"):
		var p := int(c.affinity.get(a, 0))
		if p > best_points:
			best = a
			best_points = p
	return best


## Species this creature would grow into right now, or "" if none is due.
## Rules: take the lowest growth level the creature has reached; among those
## branches pick the one matching its dominant Affinity (if that track meets
## the threshold), otherwise the default branch.
static func growth_target(db: Database, c: CreatureInstance) -> String:
	var growth: Array = c.species_def(db).growth
	var due_level := -1
	for g in growth:
		if g.level <= c.level and (due_level == -1 or g.level < due_level):
			due_level = g.level
	if due_level == -1:
		return ""
	var dominant := dominant_affinity(db, c)
	var meets: bool = dominant != "" and int(c.affinity.get(dominant, 0)) >= db.balance.growth_affinity_threshold
	var fallback := ""
	for g in growth:
		if g.level != due_level:
			continue
		if meets and g.affinity == dominant:
			return g.into
		if g.default:
			fallback = g.into
	return fallback


## Changes species, keeping level, XP, moves, Affinity, Bond and training.
## HP and energy keep their ratios.
static func apply_growth(db: Database, c: CreatureInstance, into: String) -> Dictionary:
	var from := c.species
	var hp_ratio := float(c.hp) / float(c.max_hp(db))
	var energy_ratio := float(c.energy) / float(maxi(1, c.max_energy(db)))
	c.species = into
	c.hp = maxi(1, roundi(hp_ratio * c.max_hp(db))) if c.hp > 0 else 0
	c.energy = roundi(energy_ratio * c.max_energy(db))
	return {"type": "grew", "from": from, "into": into}


# --- Training points -----------------------------------------------------------

static func training_points_total(db: Database, c: CreatureInstance) -> int:
	return (c.level - 1) * int(db.balance.training_cfg.points_per_level)


static func training_points_spent(c: CreatureInstance) -> int:
	var n := 0
	for k in c.training:
		n += int(c.training[k])
	return n


static func training_points_available(db: Database, c: CreatureInstance) -> int:
	return training_points_total(db, c) - training_points_spent(c)


## Puts `points` into `stat`. Returns "" on success, or why it was refused.
## HP and energy gained this way are added to current HP/energy too.
static func train(db: Database, c: CreatureInstance, stat: String, points: int) -> String:
	if not stat in DataSchemas.TRAINABLE_STATS:
		return "not_trainable"
	if points <= 0:
		return "bad_amount"
	if points > training_points_available(db, c):
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


# --- Bond ------------------------------------------------------------------------

## Applies a Bond change from balance.bond.changes. Returns the actual change.
static func change_bond(db: Database, c: CreatureInstance, happening: String) -> int:
	var cfg := db.balance.bond_cfg
	var delta: int = int(cfg.changes.get(happening, 0))
	var before := c.bond
	c.bond = clampi(c.bond + delta, cfg.min, cfg.max)
	return c.bond - before


## How far into negative Bond this creature is, 0..1.
static func bond_deficit(db: Database, c: CreatureInstance) -> float:
	if c.bond >= 0:
		return 0.0
	return clampf(float(-c.bond) / float(-db.balance.bond_cfg.min), 0.0, 1.0)


static func disobey_chance(db: Database, c: CreatureInstance) -> float:
	return float(db.balance.bond_cfg.disobey_max_chance) * bond_deficit(db, c)


## Multiplier on accuracy and damage from negative Bond (1.0 = no penalty).
static func bond_performance(db: Database, c: CreatureInstance) -> float:
	return 1.0 - float(db.balance.bond_cfg.penalty_max) * bond_deficit(db, c)


static func lash_out_chance(db: Database, c: CreatureInstance) -> float:
	if c.bond > db.balance.bond_cfg.lash_out_threshold:
		return 0.0
	return float(db.balance.bond_cfg.lash_out_chance)


## XP multiplier from positive Bond.
static func bond_xp_mult(db: Database, c: CreatureInstance) -> float:
	if c.bond <= 0:
		return 1.0
	return 1.0 + float(db.balance.bond_cfg.xp_bonus_max) * float(c.bond) / float(db.balance.bond_cfg.max)


## Gives a starter its starting Bond.
static func make_starter(db: Database, c: CreatureInstance) -> void:
	c.bond = db.balance.bond_cfg.starter


## Resting at a rest point: full HP and energy, status cleared, Bond up.
static func rest(db: Database, c: CreatureInstance) -> int:
	c.heal_full(db)
	return change_bond(db, c, "rested")
