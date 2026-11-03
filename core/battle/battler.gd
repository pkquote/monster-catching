class_name Battler
extends RefCounted
## A creature taking part in one battle. Wraps the persistent CreatureInstance
## (HP and status write straight through to it) and adds battle-only state.

const STAGE_MIN := -6
const STAGE_MAX := 6

## Battle-unique id used in actions and events.
var bid: int
var side: int
var creature: CreatureInstance
## Stat stages, reset when the creature leaves the field.
var stages := {"patk": 0, "pdef": 0, "satk": 0, "sdef": 0, "spd": 0, "acc": 0, "resolve": 0, "luck": 0}
var status_turns := 0
var active := false
## Was on the field at some point (eligible for XP).
var participated := false
var fainted := false
var captured := false
## bid of the last battler that damaged this one (for knockout credit).
var last_hit_by := -1
## Has already survived a knockout blow through Resolve this battle.
var endured := false
## Has already lost Bond for being overworked this battle.
var overworked := false


func _init(p_bid: int, p_side: int, p_creature: CreatureInstance) -> void:
	bid = p_bid
	side = p_side
	creature = p_creature


func alive() -> bool:
	return creature.hp > 0 and not captured


func hp() -> int:
	return creature.hp


func status() -> String:
	return creature.status


func energy() -> int:
	return creature.energy


func reset_stages() -> void:
	for k in stages:
		stages[k] = 0


## Changes a stage and returns how much it actually moved.
func shift_stage(stat: String, amount: int) -> int:
	var before: int = stages[stat]
	stages[stat] = clampi(before + amount, STAGE_MIN, STAGE_MAX)
	return stages[stat] - before
