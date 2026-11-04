class_name Progression
extends RefCounted
## XP, levelling, Affinity and growth rules. Mutates CreatureInstances and
## returns event dictionaries describing what happened.


## Adds XP, levels up as many times as earned, learns moves (always into the pool;
## into a slot only if one is free, otherwise `move_offered` for the UI to decide).
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
		Log.info(Log.PROGRESS, "Level up", {"species": c.species, "level": c.level,
			"training_points": training_points_available(db, c)})
		for l in c.species_def(db).learnset:
			if l.level != c.level or c.moves.has(l.move):
				continue
			if not c.move_pool.has(l.move):
				c.move_pool.append(l.move)
			if c.moves.size() < db.balance.max_moves:
				c.moves.append(l.move)
				events.append({"type": BattleEvents.MOVE_LEARNED, "bid": bid, "move": l.move})
				Log.info(Log.PROGRESS, "Move learned", {"species": c.species, "move": l.move})
			else:
				events.append({"type": BattleEvents.MOVE_OFFERED, "bid": bid, "move": l.move})
				Log.debug(Log.PROGRESS, "Move offered", {"species": c.species, "move": l.move})
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
static func growth_target(db: Database, c: CreatureInstance) -> String:
	return growth_branch(db, c).get("into", "")


## The growth due right now: { into, affinity } where `affinity` is the track that
## chose this branch ("" for the default branch), or {} if none is due.
## Rules: take the lowest growth level the creature has reached; among those
## branches pick the one matching its dominant Affinity (if that track meets
## the threshold), otherwise the default branch.
static func growth_branch(db: Database, c: CreatureInstance) -> Dictionary:
	var growth: Array = c.species_def(db).growth
	var due_level := -1
	for g in growth:
		if g.level <= c.level and (due_level == -1 or g.level < due_level):
			due_level = g.level
	if due_level == -1:
		return {}
	var dominant := dominant_affinity(db, c)
	var meets: bool = dominant != "" and int(c.affinity.get(dominant, 0)) >= db.balance.growth_affinity_threshold
	var fallback := ""
	for g in growth:
		if g.level != due_level:
			continue
		if meets and g.affinity == dominant:
			return {"into": g.into, "affinity": dominant}
		if g.default:
			fallback = g.into
	return {"into": fallback, "affinity": ""} if fallback != "" else {}


## Changes species, keeping level, XP, moves, Affinity, Bond and training.
## HP and energy keep their ratios. Moves the new species learns at or below the
## current level join the pool; they take a free slot or are reported as offered.
static func apply_growth(db: Database, c: CreatureInstance, into: String) -> Dictionary:
	var from := c.species
	var branch := growth_branch(db, c)
	var hp_ratio := float(c.hp) / float(c.max_hp(db))
	var energy_ratio := float(c.energy) / float(maxi(1, c.max_energy(db)))
	c.species = into
	c.hp = maxi(1, roundi(hp_ratio * c.max_hp(db))) if c.hp > 0 else 0
	c.energy = roundi(energy_ratio * c.max_energy(db))
	var learned: Array[String] = []
	var offered: Array[String] = []
	for m in c.species_def(db).moves_up_to(c.level):
		if c.move_pool.has(m):
			continue
		c.move_pool.append(m)
		if c.moves.size() < db.balance.max_moves:
			c.moves.append(m)
			learned.append(m)
		else:
			offered.append(m)
	Log.info(Log.PROGRESS, "Grew", {"from": from, "into": into, "level": c.level,
		"affinity": branch.get("affinity", "") if branch.get("into", "") == into else "",
		"learned": learned})
	for m in offered:
		Log.debug(Log.PROGRESS, "Move offered", {"species": c.species, "move": m})
	return {"type": "grew", "from": from, "into": into, "learned": learned, "offered": offered}


## Replaces the equipped moves with `slots`. Returns "" on success, or why it was
## refused: "empty", "too_many", "duplicate" or "not_in_pool".
static func set_moves(db: Database, c: CreatureInstance, slots: PackedStringArray) -> String:
	if slots.is_empty():
		return "empty"
	if slots.size() > db.balance.max_moves:
		return "too_many"
	var seen := {}
	for m in slots:
		if seen.has(m):
			return "duplicate"
		seen[m] = true
	for m in slots:
		if not c.move_pool.has(m):
			return "not_in_pool"
	c.moves = slots.duplicate()
	Log.debug(Log.PROGRESS, "Moves set", {"species": c.species, "moves": Array(slots)})
	return ""


## Summary of a level gain for the post-battle progress screen, or {} if the
## creature did not level. offered_moves are pool moves learned in the gained
## levels that did not get a slot.
static func progress_entry(db: Database, c: CreatureInstance, level_before: int) -> Dictionary:
	if c.level <= level_before:
		return {}
	var offered: Array[String] = []
	for l in c.species_def(db).learnset:
		if l.level <= level_before or l.level > c.level:
			continue
		if c.move_pool.has(l.move) and not c.moves.has(l.move) and not offered.has(l.move):
			offered.append(l.move)
	return {"creature": c, "offered_moves": offered, "growth_due": growth_target(db, c) != ""}


## Adds every learnset move at or below the creature's level that its pool lacks
## (for saves from before move pools). Safe to call repeatedly. A species that no
## longer exists in the data is left alone rather than breaking the load.
static func backfill_pool(db: Database, c: CreatureInstance) -> void:
	var def := c.species_def(db)
	if def == null:
		Log.warn(Log.SAVE, "Unknown species in save; move pool left as is", {"species": c.species})
		return
	var added: Array[String] = []
	for m in def.moves_up_to(c.level):
		if not c.move_pool.has(m):
			c.move_pool.append(m)
			added.append(m)
	if not added.is_empty():
		Log.debug(Log.SAVE, "Move pool backfilled", {"species": c.species, "added": added})


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


## Refunds every trained point. Max HP/energy drop by what training gave, and
## current HP/energy are clamped (a living creature keeps at least 1 HP; a
## fainted one stays at 0). Returns the points refunded.
static func reset_training(db: Database, c: CreatureInstance) -> int:
	var refunded := training_points_spent(c)
	Log.info(Log.PROGRESS, "Training reset", {"species": c.species, "refunded": refunded})
	c.training = {}
	if c.hp > 0:
		c.hp = clampi(c.hp, 1, c.max_hp(db))
	c.energy = mini(c.energy, c.max_energy(db))
	return refunded


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
