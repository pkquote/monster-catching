class_name BattleSetup
extends RefCounted
## Describes a battle before it starts. Side 0 is always the player.

var sides: Array[SideSetup] = []
var is_wild := false
## Tamer id for tamer battles ("" otherwise).
var tamer_id := ""
## Name shown for a tamer-style foe that isn't in the data (debug battles).
## Ignored when tamer_id is set.
var foe_name := ""
## Side 0 earns XP from knockouts. Off for simulations and exhibition battles.
var award_xp := true


func add_side(party: Array, max_active: int, field_count: int = -1, items: Dictionary = {},
		ai: String = "", auto_replace: bool = false) -> BattleSetup:
	var s := SideSetup.new()
	s.party = party
	s.max_active = max_active
	s.field_count = max_active if field_count < 0 else field_count
	s.items = items.duplicate()
	s.ai = ai
	s.auto_replace = auto_replace
	sides.append(s)
	return self


## Player vs a wild pack. Every wild creature is on the field.
## `player_field_count` may be lower than the pack size to take on an Underdog fight.
static func wild(player_party: Array, wild_pack: Array, player_field_count: int = -1,
		player_items: Dictionary = {}) -> BattleSetup:
	var s := BattleSetup.new()
	s.is_wild = true
	var n := wild_pack.size()
	s.add_side(player_party, n, mini(n, player_field_count) if player_field_count > 0 else n, player_items)
	s.add_side(wild_pack, n, n, {}, "basic", true)
	s.sides[1].is_wild = true
	return s


## Player vs an NPC tamer from data. The tamer's max_active sets the format.
static func vs_tamer(db: Database, player_party: Array, tamer_id_: String,
		player_field_count: int = -1, player_items: Dictionary = {}) -> BattleSetup:
	var t := db.tamer(tamer_id_)
	var s := BattleSetup.new()
	s.tamer_id = tamer_id_
	var party: Array = []
	for p in t.party:
		party.append(CreatureInstance.create(db, p.species, p.level, p.moves))
	var bag := {}
	for it in t.items:
		bag[it.item] = it.count
	s.add_side(player_party, t.max_active,
		mini(t.max_active, player_field_count) if player_field_count > 0 else t.max_active, player_items)
	s.add_side(party, t.max_active, t.max_active, bag, t.ai, true)
	return s
