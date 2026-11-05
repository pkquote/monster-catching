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
## Every move this creature has learned, slotted or not. Always contains `moves`.
var move_pool: PackedStringArray = []
## affinity id -> points
var affinity: Dictionary = {}
## stat id -> training points spent on it
var training: Dictionary = {}
## Status that persists after battle ("" = none). Cleared on heal.
var status: String = ""
## The passive rolled from the species' list at creation.
var passive: String = ""
## The passive unlocked by Affinity ("" until then).
var affinity_passive: String = ""
## Which slot is in effect: "rolled" or "affinity".
var active_passive: String = Passives.SLOT_ROLLED


## A fresh creature at `level`, at full HP and energy, with its latest learnable moves.
## Its passive is rolled with `rng` (the first listed without one).
static func create(db: Database, species_id: String, at_level: int,
		move_ids: PackedStringArray = PackedStringArray(), rng: RandomNumberGenerator = null) -> CreatureInstance:
	var c := CreatureInstance.new()
	c.species = species_id
	c.level = clampi(at_level, 1, db.balance.level_cap)
	c.xp = Stats.xp_for_level(c.level)
	var learnable := db.creature(species_id).moves_up_to(c.level)
	if move_ids.is_empty():
		c.moves = learnable.slice(maxi(0, learnable.size() - db.balance.max_moves))
	else:
		c.moves = move_ids.duplicate()
	c.move_pool = c.moves.duplicate()
	for m in learnable:
		if not c.move_pool.has(m):
			c.move_pool.append(m)
	for a in db.ids("affinities"):
		c.affinity[a] = 0
	c.passive = Passives.roll(db, species_id, rng)
	c.hp = c.max_hp(db)
	c.energy = c.max_energy(db)
	return c


func species_def(db: Database) -> CreatureDef:
	return db.creature(species)


func display_name(db: Database) -> String:
	return nickname if not nickname.is_empty() else species_def(db).name


func trained(stat_name: String) -> int:
	return int(training.get(stat_name, 0))


## What the species' growth gives this stat at the current level, before any training.
## `stat_name` is "hp", "stamina" (the energy pool) or any other stat.
func grown(db: Database, stat_name: String) -> int:
	var base: Dictionary = species_def(db).base_stats
	match stat_name:
		"hp":
			return Stats.hp_at(base.hp, level)
		"stamina":
			return Stats.energy_at(base.stamina, level, int(db.balance.energy_cfg.base))
	return Stats.stat_at(base[stat_name], level)


func max_hp(db: Database) -> int:
	return grown(db, "hp") + trained("hp") * int(db.balance.training_cfg.hp_per_point)


func max_energy(db: Database) -> int:
	return grown(db, "stamina") + trained("stamina")


## Raw (unmodified) stat: patk, pdef, satk, sdef, spd, luck or resolve. Includes training.
func stat(db: Database, stat_name: String) -> int:
	return grown(db, stat_name) + trained(stat_name)


## Pulls a creature above the level cap (a hand-edited or older save) back down to it.
func clamp_to_cap(db: Database) -> void:
	if level <= db.balance.level_cap:
		return
	level = db.balance.level_cap
	xp = mini(xp, Stats.xp_for_level(level))
	hp = mini(hp, max_hp(db))
	energy = mini(energy, max_energy(db))


func is_fainted() -> bool:
	return hp <= 0


## Full HP and energy, status cleared.
func heal_full(db: Database) -> void:
	hp = max_hp(db)
	energy = max_energy(db)
	status = ""


## An independent copy (battles work on copies; see BattleEngine.commit).
func copy() -> CreatureInstance:
	return CreatureInstance.from_dict(to_dict())


## Overwrites this creature's state with `other`'s.
func copy_from(other: CreatureInstance) -> void:
	var d := other.to_dict()
	species = d.species
	nickname = d.nickname
	level = d.level
	xp = d.xp
	hp = d.hp
	energy = d.energy
	bond = d.bond
	moves = PackedStringArray(d.moves)
	move_pool = PackedStringArray(d.move_pool)
	affinity = d.affinity
	training = d.training
	status = d.status
	passive = d.passive
	affinity_passive = d.affinity_passive
	active_passive = d.active_passive


func to_dict() -> Dictionary:
	return {
		"species": species, "nickname": nickname, "level": level, "xp": xp, "hp": hp,
		"energy": energy, "bond": bond, "moves": Array(moves), "move_pool": Array(move_pool), "affinity": affinity.duplicate(),
		"training": training.duplicate(), "status": status,
		"passive": passive, "affinity_passive": affinity_passive, "active_passive": active_passive,
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
	c.move_pool = PackedStringArray(d.get("move_pool", d.moves))
	c.status = d.get("status", "")
	c.passive = d.get("passive", "")
	c.affinity_passive = d.get("affinity_passive", "")
	c.active_passive = d.get("active_passive", Passives.SLOT_ROLLED)
	for k in d.get("affinity", {}):
		c.affinity[k] = int(d.affinity[k])
	for k in d.get("training", {}):
		c.training[k] = int(d.training[k])
	return c
