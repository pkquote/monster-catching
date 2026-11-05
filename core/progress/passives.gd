class_name Passives
extends RefCounted
## Creature passives: rolling the species passive and reading which slot is active.

const SLOT_ROLLED := "rolled"
const SLOT_AFFINITY := "affinity"


## A passive from the species' list: uniform with `rng`, the first listed without one.
static func roll(db: Database, species_id: String, rng: RandomNumberGenerator) -> String:
	var list := db.creature(species_id).passives
	if list.is_empty():
		return ""
	if rng == null:
		return list[0]
	return list[rng.randi_range(0, list.size() - 1)]


## The id of the passive in the creature's active slot, or "" if that slot is empty.
static func active_id(c: CreatureInstance) -> String:
	return c.affinity_passive if c.active_passive == SLOT_AFFINITY else c.passive


## Makes `slot` (SLOT_ROLLED / SLOT_AFFINITY) the active passive. "" on success,
## "bad_slot" for any other slot, "locked" when that slot holds no passive yet.
static func set_active(c: CreatureInstance, slot: String) -> String:
	if slot != SLOT_ROLLED and slot != SLOT_AFFINITY:
		return "bad_slot"
	if (c.affinity_passive if slot == SLOT_AFFINITY else c.passive) == "":
		return "locked"
	c.active_passive = slot
	Log.info(Log.PROGRESS, "Active passive set", {"species": c.species, "slot": slot})
	return ""


## Overworld multiplier for `op` (encounter_rate, xp_mult, bond_gain): the product of the
## party lead's active passive's `field` entries with that op. The lead is party[0], fainted
## or not; 1.0 with an empty party or no such entry.
static func field_mult(db: Database, save: SaveGame, op: String) -> float:
	if save.party.is_empty():
		return 1.0
	var def := db.passive(active_id(save.party[0]))
	if def == null:
		return 1.0
	var mult := 1.0
	for f: Dictionary in def.field:
		if f.op == op:
			mult *= float(f.mult)
	return mult


## Fills a missing rolled passive for saves from before passives, by a stable hash so
## repeated loads agree. A species no longer in the data is left alone.
static func backfill(db: Database, c: CreatureInstance) -> void:
	var def := c.species_def(db)
	if def == null:
		Log.warn(Log.SAVE, "Unknown species in save; passive left as is", {"species": c.species})
		return
	if c.passive.is_empty() and not def.passives.is_empty():
		c.passive = def.passives[absi(hash("%s%d%d" % [c.species, c.level, c.xp])) % def.passives.size()]
		Log.debug(Log.SAVE, "Passive backfilled", {"species": c.species, "passive": c.passive})
	# Saves from before passives: a track already at the threshold unlocks (highest first).
	var best := ""
	var best_points := 0
	for a in db.ids("affinities"):
		var p := int(c.affinity.get(a, 0))
		if p >= db.balance.growth_affinity_threshold and p > best_points:
			best = a
			best_points = p
	if best != "":
		try_unlock(db, c, best)


## Unlocks the creature's Affinity passive if `track` has reached the growth threshold and
## the species lists a passive for it. One unlock per creature. Returns the id, or "".
static func try_unlock(db: Database, c: CreatureInstance, track: String) -> String:
	if c.affinity_passive != "" or int(c.affinity.get(track, 0)) < db.balance.growth_affinity_threshold:
		return ""
	var def := c.species_def(db)
	if def == null or not def.affinity_passives.has(track):
		return ""
	c.affinity_passive = def.affinity_passives[track]
	Log.info(Log.PROGRESS, "Passive unlocked", {"species": c.species, "track": track,
		"passive": c.affinity_passive})
	return c.affinity_passive


## After growth into a new species: the rolled passive keeps its list position (the new
## species' first if it has fewer), and the Affinity passive becomes the new species'
## passive for the same track, or stays if there is none. `active_passive` is untouched.
static func carry_over(db: Database, c: CreatureInstance, from_species: String) -> void:
	var from := db.creature(from_species)
	var to := c.species_def(db)
	if from == null or to == null:
		return
	if not to.passives.is_empty() and c.passive != "":
		var idx := maxi(0, from.passives.find(c.passive))
		c.passive = to.passives[idx] if idx < to.passives.size() else to.passives[0]
	for track in from.affinity_passives:
		if from.affinity_passives[track] == c.affinity_passive and to.affinity_passives.has(track):
			c.affinity_passive = to.affinity_passives[track]
			break
