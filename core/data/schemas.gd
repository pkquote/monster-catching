class_name DataSchemas
extends RefCounted
## Declarative schemas for every JSON content category.
##
## Rule keys:
##   when   : true on an "effects" rule to allow a "when" condition on each effect
##   trigger: true on an "effects" rule to allow target "attacker" (passive triggers)
##   t      : "string" | "int" | "number" | "bool" | "id" | "ref" | "enum"
##            | "array" | "dict" | "map" | "effects"
##   opt    : true if the field may be omitted
##   cat    : category name for "ref"
##   values : allowed values for "enum"
##   of     : element rule for "array"
##   fields : field rules for "dict"
##   key / value : rules for "map" (a JSON object with arbitrary keys)
##   min / max   : numeric range, or element count for arrays
##
## Unknown fields are reported as errors so typos never pass silently.

const TARGETS := ["self", "one_ally", "one_enemy", "all_allies", "all_enemies", "all",
	"own_side", "enemy_side"]
## Moves may also hit two chosen foes; items, effect overrides and triggers may not.
const MOVE_TARGETS := TARGETS + ["two_enemies"]
## Passive trigger effects may also aim at the creature that set the trigger off.
const TRIGGER_TARGETS := TARGETS + ["attacker"]
## Overworld-only ops (a passive's "field" list); everything else is for battle.
const FIELD_OPS := ["encounter_rate", "xp_mult", "bond_gain"]
## When a passive trigger fires.
const TRIGGER_ON := ["enter", "hit", "round_end", "knockout", "faint", "status"]
const SIDES := ["user", "target", "own", "enemy", "both"]
## Stats that stages and stat_mod effects can change in battle.
const STATS := ["patk", "pdef", "satk", "sdef", "spd", "acc", "resolve", "luck"]
## Species base stats (Bond is per creature, not per species).
const BASE_STATS := ["hp", "patk", "pdef", "satk", "sdef", "spd", "luck", "resolve", "stamina"]
## Stats the player may put training points into.
const TRAINABLE_STATS := ["hp", "patk", "pdef", "satk", "sdef", "spd", "resolve", "stamina"]
## Happenings that change Bond (see balance.bond.changes).
const BOND_EVENTS := ["battle_won", "knockout", "healed_item", "rested", "fainted", "overworked"]
## Battle happenings that can award Affinity points (see balance.affinity_awards).
const AFFINITY_EVENTS := ["hit_dealt", "knockout", "hit_survived", "heal", "field_applied",
	"reaction_triggered", "field_cashed_in", "status_inflicted", "stat_lowered"]

## Category -> how it is stored on disk.
## "folder": data/<name>/*.json, each file { schema, entries: [...] }
## "file":   data/<name>.json, { schema, entries: [...] }
## "single": data/<name>.json, { schema, data: {...} }
const CATEGORIES := {
	"creatures": "folder",
	"moves": "folder",
	"items": "folder",
	"tamers": "folder",
	"encounters": "folder",
	"locations": "file",
	"achievements": "folder",
	"types": "file",
	"statuses": "file",
	"field_states": "file",
	"reactions": "file",
	"affinities": "file",
	"minigames": "file",
	"passives": "folder",
	"balance": "single",
}

const SCHEMA_VERSION := 1

const _STAT_RULE := {"t": "int", "min": 1, "max": 255}
const _BASE_STATS := {
	"hp": _STAT_RULE, "patk": _STAT_RULE, "pdef": _STAT_RULE, "satk": _STAT_RULE, "sdef": _STAT_RULE,
	"spd": _STAT_RULE, "luck": _STAT_RULE, "resolve": _STAT_RULE, "stamina": _STAT_RULE,
}

## Per-op schemas for entries in any "effects" array. "op" itself is implied.
## Every op may also carry an optional "target" override.
const EFFECT_OPS := {
	"damage": {
		"power": {"t": "int", "opt": true, "min": 1, "max": 300},
		"type": {"t": "ref", "cat": "types", "opt": true},
		"scale_with_stacks": {"t": "bool", "opt": true},
	},
	"heal": {
		"fraction": {"t": "number", "min": 0.0, "max": 1.0},
	},
	"reset_training": {},
	"damage_fraction": {
		"fraction": {"t": "number", "min": 0.0, "max": 1.0},
	},
	"skip_chance": {
		"chance": {"t": "int", "min": 1, "max": 100},
	},
	"apply_status": {
		"status": {"t": "ref", "cat": "statuses"},
		"chance": {"t": "int", "opt": true, "min": 1, "max": 100},
	},
	"apply_field_state": {
		"side": {"t": "enum", "values": SIDES},
		"state": {"t": "ref", "cat": "field_states"},
		"stacks": {"t": "int", "opt": true, "min": 1, "max": 5},
		"turns": {"t": "int", "opt": true, "min": 1, "max": 10},
	},
	"remove_field_state": {
		"side": {"t": "enum", "values": SIDES},
		"state": {"t": "ref", "cat": "field_states", "opt": true},
	},
	"bonus_if_field": {
		"side": {"t": "enum", "values": SIDES},
		"state": {"t": "ref", "cat": "field_states"},
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
		"consume": {"t": "bool", "opt": true},
	},
	"stat_stage": {
		"stat": {"t": "enum", "values": STATS},
		"stages": {"t": "int", "min": -3, "max": 3},
	},
	"stat_mod": {
		"stat": {"t": "enum", "values": STATS},
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"incoming_type_mod": {
		"type": {"t": "ref", "cat": "types", "opt": true},
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"type_power": {
		"type": {"t": "ref", "cat": "types"},
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"absorb_type": {
		"type": {"t": "ref", "cat": "types"},
		"fraction": {"t": "number", "min": 0.0, "max": 1.0},
	},
	"status_immune": {
		"status": {"t": "ref", "cat": "statuses", "opt": true},
	},
	"guard_stages": {
		"stat": {"t": "enum", "values": STATS, "opt": true},
	},
	"field_shelter": {
		"state": {"t": "ref", "cat": "field_states"},
	},
	"field_boost": {
		"stacks": {"t": "int", "opt": true, "min": 1, "max": 5},
		"turns": {"t": "int", "opt": true, "min": 1, "max": 10},
	},
	"reaction_power": {
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"energy_discount": {
		"type": {"t": "ref", "cat": "types", "opt": true},
		"amount": {"t": "int", "min": 1, "max": 30},
	},
	"rest_bonus": {
		"fraction": {"t": "number", "min": 0.0, "max": 1.0},
	},
	"scrap_power": {
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"encounter_rate": {
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"xp_mult": {
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"bond_gain": {
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"restore_energy": {
		"fraction": {"t": "number", "min": 0.0, "max": 1.0},
	},
	"cure_status": {
		"status": {"t": "ref", "cat": "statuses", "opt": true},
	},
	"capture": {
		"mult": {"t": "number", "min": 0.0, "max": 10.0},
		"field_bonus": {"t": "map", "opt": true,
			"key": {"t": "ref", "cat": "field_states"},
			"value": {"t": "number", "min": 0.0, "max": 10.0}},
	},
}

## Ops whose fields are each optional but that need at least one of a set, so a bare
## effect would do nothing (and could not be described in text).
const EFFECT_NEEDS_ONE_OF := {
	"field_boost": ["stacks", "turns"],
}

## Optional condition on a passive's always-on effect.
const WHEN := {
	"hp_below": {"t": "number", "opt": true, "min": 0.0, "max": 1.0},
	"underdog": {"t": "bool", "opt": true},
	"field": {"t": "ref", "cat": "field_states", "opt": true},
	"side": {"t": "enum", "values": ["own", "enemy"], "opt": true},
}

## A passive's (or held item's) list of triggers; each may carry a `when` condition.
const TRIGGERS := {"t": "array", "opt": true, "of": {"t": "dict", "fields": {
	"on": {"t": "enum", "values": TRIGGER_ON},
	"chance": {"t": "int", "opt": true, "min": 1, "max": 100},
	"contact": {"t": "bool", "opt": true},
	"when": {"t": "dict", "fields": WHEN, "opt": true},
	"effects": {"t": "effects", "trigger": true},
}}}

## A held item's behaviour: a passive plus how it is spent.
const HELD := {
	"use": {"t": "enum", "values": ["permanent", "consumed", "per_battle"], "opt": true},
	"scope": {"t": "enum", "values": ["self", "allies"], "opt": true},
	"effects": {"t": "effects", "when": true, "opt": true},
	"triggers": TRIGGERS,
	"field": {"t": "effects", "opt": true},
}

## Per-kind fields of an achievement's `criterion` ("kind" itself is implied). Each kind is a
## `Criterion` subclass registered in `Criteria.KINDS`.
const CRITERIA := {
	"counter": {
		"stat": {"t": "enum", "values": Counters.BUILT_IN},
		"target": {"t": "int", "min": 1},
	},
	"codex": {
		"mode": {"t": "enum", "values": ["seen", "caught", "species"]},
		"target": {"t": "int", "opt": true, "min": 1},
		"species": {"t": "ref", "cat": "creatures", "opt": true},
	},
	"flag": {
		"flag": {"t": "id"},
	},
	"creature": {
		"what": {"t": "enum", "values": ["level", "bond", "evolved"]},
		"target": {"t": "int", "min": 1},
	},
}

const ENTRY := {
	"creatures": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"dex": {"t": "int", "opt": true, "min": 1},
		"description": {"t": "string", "opt": true},
		"types": {"t": "array", "min": 1, "max": 2, "of": {"t": "ref", "cat": "types"}},
		"base_stats": {"t": "dict", "fields": _BASE_STATS},
		"catch_rate": {"t": "number", "min": 0.0, "max": 1.0},
		"xp_yield": {"t": "int", "min": 0},
		"learnset": {"t": "array", "min": 1, "of": {"t": "dict", "fields": {
			"level": {"t": "int", "min": 1, "max": 100},
			"move": {"t": "ref", "cat": "moves"},
		}}},
		"growth": {"t": "array", "opt": true, "of": {"t": "dict", "fields": {
			"level": {"t": "int", "min": 2, "max": 100},
			"affinity": {"t": "ref", "cat": "affinities", "opt": true},
			"default": {"t": "bool", "opt": true},
			"into": {"t": "ref", "cat": "creatures"},
		}}},
		"growth_rates": {"t": "map", "opt": true, "key": {"t": "enum", "values": BASE_STATS}, "value": {"t": "id"}},
		"passives": {"t": "array", "min": 1, "max": 2, "of": {"t": "ref", "cat": "passives"}},
		"affinity_passives": {"t": "map", "opt": true,
			"key": {"t": "ref", "cat": "affinities"},
			"value": {"t": "ref", "cat": "passives"}},
	},
	"passives": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
		"scope": {"t": "enum", "values": ["self", "allies"], "opt": true},
		"effects": {"t": "effects", "when": true, "opt": true},
		"triggers": TRIGGERS,
		"field": {"t": "effects", "opt": true},
	},
	"moves": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
		"type": {"t": "ref", "cat": "types"},
		"category": {"t": "enum", "values": ["physical", "special", "status"]},
		"power": {"t": "int", "min": 0, "max": 300},
		"cost": {"t": "int", "min": 0, "max": 30},
		"accuracy": {"t": "int", "min": 1, "max": 100},
		"always_hits": {"t": "bool", "opt": true},
		"priority": {"t": "int", "opt": true, "min": -3, "max": 3},
		"target": {"t": "enum", "values": MOVE_TARGETS},
		"effects": {"t": "effects"},
	},
	"items": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
		"category": {"t": "enum", "values": ["capture", "heal", "battle", "key", "training", "held"]},
		"price": {"t": "int", "min": 0},
		"target": {"t": "enum", "values": TARGETS, "opt": true},
		"effects": {"t": "effects", "opt": true},
		"held": {"t": "dict", "fields": HELD, "opt": true},
	},
	"tamers": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"max_active": {"t": "int", "min": 1, "max": 3},
		"ai": {"t": "enum", "values": ["basic", "aggressive", "tactician"]},
		"reward_money": {"t": "int", "min": 0},
		"party": {"t": "array", "min": 1, "max": 6, "of": {"t": "dict", "fields": {
			"species": {"t": "ref", "cat": "creatures"},
			"level": {"t": "int", "min": 1, "max": 100},
			"moves": {"t": "array", "opt": true, "min": 1, "max": 4, "of": {"t": "ref", "cat": "moves"}},
			"passive": {"t": "ref", "cat": "passives", "opt": true},
			"held_item": {"t": "ref", "cat": "items", "opt": true},
		}}},
		"items": {"t": "array", "opt": true, "of": {"t": "dict", "fields": {
			"item": {"t": "ref", "cat": "items"},
			"count": {"t": "int", "min": 1, "max": 99},
		}}},
	},
	"encounters": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"pack_min": {"t": "int", "min": 1, "max": 3},
		"pack_max": {"t": "int", "min": 1, "max": 3},
		"table": {"t": "array", "min": 1, "of": {"t": "dict", "fields": {
			"species": {"t": "ref", "cat": "creatures"},
			"weight": {"t": "int", "min": 1},
			"min_level": {"t": "int", "min": 1, "max": 100},
			"max_level": {"t": "int", "min": 1, "max": 100},
		}}},
	},
	"types": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string"},
		"pros": {"t": "array", "min": 1, "of": {"t": "string"}},
		"cons": {"t": "array", "min": 1, "of": {"t": "string"}},
		"matchups": {"t": "map", "opt": true,
			"key": {"t": "ref", "cat": "types"},
			"value": {"t": "number", "min": 0.0, "max": 4.0}},
	},
	"statuses": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
		"turns": {"t": "int", "min": 1, "max": 10},
		"effects": {"t": "effects"},
	},
	"field_states": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
		"max_stacks": {"t": "int", "min": 1, "max": 5},
		"default_turns": {"t": "int", "min": 1, "max": 10},
		"passive": {"t": "effects", "opt": true},
	},
	"reactions": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
		"inputs": {"t": "array", "min": 2, "max": 2, "of": {"t": "ref", "cat": "field_states"}},
		"consumes": {"t": "array", "min": 1, "max": 2, "of": {"t": "ref", "cat": "field_states"}},
		"scope": {"t": "enum", "values": ["side", "both_sides"]},
		"effects": {"t": "effects"},
	},
	"affinities": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
	},
	"locations": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"areas": {"t": "array", "min": 1, "of": {"t": "ref", "cat": "encounters"}},
	},
	"achievements": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string"},
		"hidden": {"t": "bool", "opt": true},
		"criterion": {"t": "criterion"},
	},
	"minigames": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"scene": {"t": "string"},
	},
	"balance": {
		"level_cap": {"t": "int", "min": 1, "max": 100},
		"party_size": {"t": "int", "min": 1, "max": BalanceDef.MAX_PARTY_SIZE},
		"max_moves": {"t": "int", "min": 1, "max": 8},
		"stab": {"t": "number", "min": 1.0, "max": 3.0},
		"max_field_states": {"t": "int", "min": 1, "max": 5},
		"growth_affinity_threshold": {"t": "int", "min": 0},
		"growth_tiers": {"t": "map", "key": {"t": "id"}, "value": {"t": "number", "min": 0.1, "max": 3.0}},
		"growth_budget": {"t": "int", "min": 0, "max": 9},
		"underdog": {"t": "dict", "fields": {
			"bonus_actions_per_ratio": {"t": "number", "min": 0.0, "max": 2.0},
			"spread_reduction_per_ratio": {"t": "number", "min": 0.0, "max": 1.0},
			"spread_reduction_cap": {"t": "number", "min": 0.0, "max": 1.0},
			"stat_bonus_per_ratio": {"t": "number", "min": 0.0, "max": 2.0},
			"stat_bonus_cap": {"t": "number", "min": 0.0, "max": 2.0},
			"xp_bonus_per_ratio": {"t": "number", "min": 0.0, "max": 5.0},
		}},
		"catch": {"t": "dict", "fields": {
			"hp_weight": {"t": "number", "min": 0.0, "max": 1.0},
			"status_mult": {"t": "number", "min": 1.0, "max": 5.0},
		}},
		"spread_mults": {"t": "dict", "fields": {
			"2": {"t": "number", "min": 0.0, "max": 1.0},
			"3": {"t": "number", "min": 0.0, "max": 1.0},
		}},
		"resolve": {"t": "dict", "fields": {
			"resist_cap": {"t": "number", "min": 0.0, "max": 1.0},
			"endure_cap": {"t": "number", "min": 0.0, "max": 1.0},
		}},
		"energy": {"t": "dict", "fields": {
			"base": {"t": "int", "min": 0, "max": 200},
			"rest_fraction": {"t": "number", "min": 0.0, "max": 1.0},
			"fallback_move": {"t": "ref", "cat": "moves"},
		}},
		"training": {"t": "dict", "fields": {
			"points_per_level": {"t": "int", "min": 0, "max": 10},
			"max_per_stat": {"t": "int", "min": 0, "max": 255},
			"hp_per_point": {"t": "int", "min": 1, "max": 10},
		}},
		"bond": {"t": "dict", "fields": {
			"min": {"t": "int", "min": -1000, "max": 0},
			"max": {"t": "int", "min": 0, "max": 1000},
			"starter": {"t": "int", "min": -1000, "max": 1000},
			"disobey_max_chance": {"t": "number", "min": 0.0, "max": 1.0},
			"penalty_max": {"t": "number", "min": 0.0, "max": 1.0},
			"lash_out_threshold": {"t": "int", "min": -1000, "max": 0},
			"lash_out_chance": {"t": "number", "min": 0.0, "max": 1.0},
			"xp_bonus_max": {"t": "number", "min": 0.0, "max": 5.0},
			"overwork_hp": {"t": "number", "min": 0.0, "max": 1.0},
			"overwork_energy": {"t": "number", "min": 0.0, "max": 1.0},
			"changes": {"t": "map",
				"key": {"t": "enum", "values": BOND_EVENTS},
				"value": {"t": "int", "min": -100, "max": 100}},
		}},
		"round_limit": {"t": "int", "min": 1, "max": 1000},
		"overworld": {"t": "dict", "fields": {
			"walk_speed": {"t": "number", "min": 0.5, "max": 20.0},
			"run_speed": {"t": "number", "min": 0.5, "max": 30.0},
			"encounter_rate": {"t": "number", "min": 0.0, "max": 1.0},
			"encounter_grace_tiles": {"t": "int", "min": 0, "max": 100},
			"walk_energy_tiles": {"t": "int", "min": 1, "max": 1000},
			"defeat_money_fraction": {"t": "number", "min": 0.0, "max": 1.0},
			"sell_fraction": {"t": "number", "min": 0.0, "max": 1.0},
		}},
		"xp": {"t": "dict", "fields": {
			"divisor": {"t": "number", "min": 1.0, "max": 100.0},
			"tamer_mult": {"t": "number", "min": 1.0, "max": 5.0},
		}},
		"affinity_awards": {"t": "map",
			"key": {"t": "enum", "values": AFFINITY_EVENTS},
			"value": {"t": "dict", "fields": {
				"affinity": {"t": "ref", "cat": "affinities"},
				"points": {"t": "int", "min": 0, "max": 100},
			}}},
	},
}
