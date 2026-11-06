class_name CreatureSpec
extends RefCounted
## One slot of a hand-built (debug) team: species, level, moves, held item and passive.
## Pure data; `to_instance` turns it into a real CreatureInstance for a battle.

const LEARNED := "learned"
const LEARNS_LATER := "later"
const NOT_LEARNABLE := "no"

const ROLLS := "rolls"
const AFFINITY := "affinity"
const NOT_NORMAL := "not_normal"

var species: String = ""
var level: int = 1
var moves: PackedStringArray = PackedStringArray()
var held_item: String = ""
## "" = none.
var passive: String = ""
## True once the moves were hand-picked; `retarget` then keeps them.
var moves_edited: bool = false


## A spec with the natural moves for `species` at `level`, a rolled passive and no item.
static func natural(db: Database, species_id: String, at_level: int, rng: RandomNumberGenerator) -> CreatureSpec:
	var s: CreatureSpec = CreatureSpec.new()
	s.species = species_id
	s.level = at_level
	s.moves = s.natural_moves(db)
	s.passive = Passives.roll(db, species_id, rng) if db.has("creatures", species_id) else ""
	return s


static func from_instance(c: CreatureInstance) -> CreatureSpec:
	var s: CreatureSpec = CreatureSpec.new()
	s.species = c.species
	s.level = c.level
	s.moves = c.moves.duplicate()
	s.held_item = c.held_item
	s.passive = c.passive
	# A copy keeps its exact moves (moves_edited); "Reset to natural" in the editor
	# replaces them with the species' natural moves.
	s.moves_edited = true
	return s


## Callers must run validate() first: an unknown species crashes CreatureInstance.create.
func to_instance(db: Database, rng: RandomNumberGenerator) -> CreatureInstance:
	var lv: int = clampi(level, 1, db.balance.level_cap)
	var c: CreatureInstance = CreatureInstance.create(db, species, lv, moves, rng)
	c.held_item = held_item
	c.passive = passive
	return c


## The moves CreatureInstance.create picks with no explicit list.
func natural_moves(db: Database) -> PackedStringArray:
	if not db.has("creatures", species):
		return PackedStringArray()
	var lv: int = clampi(level, 1, db.balance.level_cap)
	var learnable: PackedStringArray = db.creature(species).moves_up_to(lv)
	return learnable.slice(maxi(0, learnable.size() - db.balance.max_moves))


## Switches species and level; the moves become the new natural ones unless hand-edited.
func retarget(db: Database, new_species: String, new_level: int) -> void:
	species = new_species
	level = new_level
	if not moves_edited:
		moves = natural_moves(db)


## Human-readable problems that would make this spec unusable; empty when valid.
func validate(db: Database) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if not db.has("creatures", species):
		errors.append("Unknown species '%s'" % species)
	if moves.is_empty():
		errors.append("No moves")
	if moves.size() > db.balance.max_moves:
		errors.append("More than %d moves" % db.balance.max_moves)
	var seen: Dictionary = {}
	for m: String in moves:
		if not db.has("moves", m):
			errors.append("Unknown move '%s'" % m)
		if seen.has(m):
			errors.append("Duplicate move '%s'" % m)
		seen[m] = true
	if passive != "" and not db.has("passives", passive):
		errors.append("Unknown passive '%s'" % passive)
	if held_item != "":
		if not db.has("items", held_item):
			errors.append("Unknown held item '%s'" % held_item)
		elif db.item(held_item).category != "held":
			errors.append("'%s' is not a held item" % held_item)
	return errors


## {state: LEARNED | LEARNS_LATER | NOT_LEARNABLE, level: learn level or 0}.
static func move_standing(db: Database, species_id: String, at_level: int, move_id: String) -> Dictionary:
	if not db.has("creatures", species_id):
		return {"state": NOT_LEARNABLE, "level": 0}
	var best: int = 0
	var found: bool = false
	for l: Dictionary in db.creature(species_id).learnset:
		if l.move == move_id and (not found or int(l.level) < best):
			best = int(l.level)
			found = true
	if not found:
		return {"state": NOT_LEARNABLE, "level": 0}
	return {"state": LEARNED if best <= at_level else LEARNS_LATER, "level": best}


static func passive_standing(db: Database, species_id: String, passive_id: String) -> String:
	if not db.has("creatures", species_id):
		return NOT_NORMAL
	var def: CreatureDef = db.creature(species_id)
	if def.passives.has(passive_id):
		return ROLLS
	if def.affinity_passives.values().has(passive_id):
		return AFFINITY
	return NOT_NORMAL


static func move_label(db: Database, species_id: String, at_level: int, move_id: String) -> String:
	var name: String = db.move(move_id).name if db.has("moves", move_id) else move_id
	var st: Dictionary = move_standing(db, species_id, at_level, move_id)
	match st.state:
		LEARNED:
			return "%s ✓ Lv %d" % [name, st.level]
		LEARNS_LATER:
			return "%s Lv %d (later)" % [name, st.level]
	return "%s ✗ can't learn" % name


static func passive_label(db: Database, species_id: String, passive_id: String) -> String:
	var name: String = db.passive(passive_id).name if db.has("passives", passive_id) else passive_id
	match passive_standing(db, species_id, passive_id):
		ROLLS:
			return "%s ★ rolls" % name
		AFFINITY:
			return "%s (Affinity)" % name
	return "%s ✗ not normal" % name


## "Natural at Lv N: A, B, C, D"
func summary(db: Database) -> String:
	var names: PackedStringArray = PackedStringArray()
	for m: String in natural_moves(db):
		names.append(db.move(m).name)
	var lv: int = clampi(level, 1, db.balance.level_cap)
	return "Natural at Lv %d: %s" % [lv, ", ".join(names)]
