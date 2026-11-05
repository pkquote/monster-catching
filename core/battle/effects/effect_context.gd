class_name EffectContext
extends RefCounted
## Everything an effect op needs while one move, item, reaction or status runs.

var engine: BattleEngine
## The battler responsible (credited with Affinity). Null for passive ticks.
var user: Battler
## "move" | "item" | "reaction" | "status" | "passive"
var source: String
## For a passive trigger: the creature that set it off (target key "attacker").
var attacker: Battler
var move: MoveDef
var item: ItemDef
var reaction: ReactionDef
## Side a side-level effect falls back to when an effect says side "target"
## and there is no creature target (e.g. enemy_side moves, reactions).
var target_side: int = -1
## Creature targets that were hit (after accuracy).
var targets: Array[Battler] = []
## True when the move hits more than one creature (spread penalty applies).
var spread := false
## Multiplier from bonus_if_field for the damage/heal that follows.
var mult := 1.0
## Stacks used up by a reaction (for scale_with_stacks).
var stacks_consumed := 0
## [side_index, state_id] pairs to remove once the move finishes.
var pending_consume: Array = []


func is_reaction() -> bool:
	return source == "reaction"


## Power and type for the damage op, honouring per-effect overrides.
func damage_power(e: Dictionary) -> int:
	var p: int = int(e.get("power", move.power if move != null else 0))
	if e.get("scale_with_stacks", false):
		p *= maxi(1, stacks_consumed)
	return p


func damage_type(e: Dictionary) -> String:
	if e.has("type"):
		return e.type
	return move.type if move != null else "neutral"


## Resolves an effect's "side" field to a side index.
func side_index(side_key: String) -> int:
	var own := user.side if user != null else target_side
	match side_key:
		"user", "own":
			return own
		"enemy":
			return 1 - own
		"target":
			if not targets.is_empty():
				return targets[0].side
			return target_side if target_side != -1 else 1 - own
	return -1  # "both" is handled by the caller
