class_name BattleEvents
extends RefCounted
## Names of every event the battle engine reports. Events are Dictionaries
## { type: <one of these>, ... }; documentation/battle-engine.md lists each one's fields.
##
## Use these constants when emitting, so a typo fails to parse instead of failing
## silently. BattleEngine.emit() rejects unknown types in debug builds, and
## tests/battle/test_battle_events.gd checks the battle screen handles every type.

# Flow
const BATTLE_START := "battle_start"
const ROUND_START := "round_start"
const BATTLE_END := "battle_end"
const SEND_OUT := "send_out"
const SWAP_OUT := "swap_out"
const REPLACEMENT_NEEDED := "replacement_needed"
const UNDERDOG := "underdog"
const FLED := "fled"

# Actions
const MOVE_USED := "move_used"
const ITEM_USED := "item_used"
const REST := "rest"
const PASS := "pass"
const ACTION_INVALID := "action_invalid"
const ACTION_SKIPPED := "action_skipped"
const NO_TARGET := "no_target"
const MISS := "miss"

# Effects on creatures
const DAMAGE := "damage"
const NO_EFFECT := "no_effect"
const ENDURED := "endured"
const HEAL := "heal"
const ENERGY := "energy"
const STATUS_APPLIED := "status_applied"
const STATUS_FAILED := "status_failed"
const STATUS_ENDED := "status_ended"
const RESISTED := "resisted"
const STAT_STAGE := "stat_stage"
const FAINT := "faint"

# Field states
const FIELD_APPLIED := "field_applied"
const FIELD_REMOVED := "field_removed"
const REACTION := "reaction"

# Capture
const CAPTURE_ATTEMPT := "capture_attempt"
const CAPTURE_FAILED := "capture_failed"
const CAPTURED := "captured"

# Bond and growth
const BOND := "bond"
const LASHED_OUT := "lashed_out"
const DISOBEYED := "disobeyed"
const XP_GAIN := "xp_gain"
const LEVEL_UP := "level_up"
const MOVE_LEARNED := "move_learned"
const MOVE_OFFERED := "move_offered"
const PASSIVE_UNLOCKED := "passive_unlocked"

# Creature passives
## A passive visibly acts: a trigger fires, a hit is absorbed. { bid, passive }
const PASSIVE_TRIGGERED := "passive_triggered"
## A held item was used up and is gone from its holder. { bid, item }
const ITEM_CONSUMED := "item_consumed"

const ALL := [
	BATTLE_START, ROUND_START, BATTLE_END, SEND_OUT, SWAP_OUT, REPLACEMENT_NEEDED, UNDERDOG, FLED,
	MOVE_USED, ITEM_USED, REST, PASS, ACTION_INVALID, ACTION_SKIPPED, NO_TARGET, MISS,
	DAMAGE, NO_EFFECT, ENDURED, HEAL, ENERGY, STATUS_APPLIED, STATUS_FAILED, STATUS_ENDED,
	RESISTED, STAT_STAGE, FAINT,
	FIELD_APPLIED, FIELD_REMOVED, REACTION,
	CAPTURE_ATTEMPT, CAPTURE_FAILED, CAPTURED,
	BOND, LASHED_OUT, DISOBEYED, XP_GAIN, LEVEL_UP, MOVE_LEARNED, MOVE_OFFERED,
	PASSIVE_UNLOCKED, PASSIVE_TRIGGERED, ITEM_CONSUMED,
]
