class_name CreatureInstance
extends RefCounted
## One owned or wild creature: everything that persists between battles.
## Definitions (species stats, moves) stay in the Database; this holds only state.

var species: String
var nickname: String = ""
var level: int = 1
var xp: int = 0
var hp: int = 1
## Current energy. Persists between battles, like HP.
var energy: int = 0
## -100..100 (limits from balance.bond). Reflects how the creature is treated.
var bond: int = 0
var moves: PackedStringArray = []
## affinity id -> points
var affinity: Dictionary = {}
## stat id -> training points spent on it
var training: Dictionary = {}
## Status that persists after battle ("" = none). Cleared on heal.
var status: String = ""


## A fresh creature at `level`, at full HP and energy, with its latest learnable moves.
static func create(db: Database, species_id: String, at_level: int,
		move_ids: PackedStringArray = PackedStringArray()) -> CreatureInstance:
	var c := CreatureInstance.new()
	c.species = species_id
	c.level = clampi(at_level, 1, db.balance.level_cap)
	c.xp = Stats.xp_for_level(c.level)
	if move_ids.is_empty():
		var learnable := db.creature(species_id).moves_up_to(c.level)
		c.moves = learnable.slice(maxi(0, learnable.size() - db.balance.max_moves))
	else:
		c.moves = move_ids.duplicate()
	for a in db.ids("affinities"):
		c.affinity[a] = 0
	c.hp = c.max_hp(db)
	c.energy = c.max_energy(db)
	return c


func species_def(db: Database) -> CreatureDef:
	return db.creature(species)


func display_name(db: Database) -> String:
	return nickname if not nickname.is_empty() else species_def(db).name


func trained(stat_name: String) -> int:
	return int(training.get(stat_name, 0))


func max_hp(db: Database) -> int:
	return Stats.hp_at(species_def(db).base_stats.hp, level) \
		+ trained("hp") * int(db.balance.training_cfg.hp_per_point)


func max_energy(db: Database) -> int:
	return Stats.energy_at(species_def(db).base_stats.stamina, level, int(db.balance.energy_cfg.base)) \
		+ trained("stamina")


## Raw (unmodified) stat: patk, pdef, satk, sdef, spd, luck or resolve. Includes training.
func stat(db: Database, stat_name: String) -> int:
	return Stats.stat_at(species_def(db).base_stats[stat_name], level) + trained(stat_name)


func is_fainted() -> bool:
	return hp <= 0


## Full HP and energy, status cleared.
func heal_full(db: Database) -> void:
	hp = max_hp(db)
	energy = max_energy(db)
	status = ""


func to_dict() -> Dictionary:
	return {
		"species": species, "nickname": nickname, "level": level, "xp": xp, "hp": hp,
		"energy": energy, "bond": bond, "moves": Array(moves), "affinity": affinity.duplicate(),
		"training": training.duplicate(), "status": status,
	}


static func from_dict(d: Dictionary) -> CreatureInstance:
	var c := CreatureInstance.new()
	c.species = d.species
	c.nickname = d.get("nickname", "")
	c.level = int(d.level)
	c.xp = int(d.xp)
	c.hp = int(d.hp)
	c.energy = int(d.get("energy", 0))
	c.bond = int(d.get("bond", 0))
	c.moves = PackedStringArray(d.moves)
	c.status = d.get("status", "")
	for k in d.get("affinity", {}):
		c.affinity[k] = int(d.affinity[k])
	for k in d.get("training", {}):
		c.training[k] = int(d.training[k])
	return c
