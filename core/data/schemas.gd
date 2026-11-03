class_name DataSchemas
extends RefCounted
## Declarative schemas for every JSON content category.
##
## Rule keys:
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
const SIDES := ["user", "target", "own", "enemy", "both"]
const STATS := ["atk", "def", "spd", "acc"]

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
	"types": "file",
	"statuses": "file",
	"field_states": "file",
	"reactions": "file",
	"affinities": "file",
	"balance": "single",
}

const SCHEMA_VERSION := 1

const _BASE_STATS := {
	"hp": {"t": "int", "min": 1, "max": 255},
	"atk": {"t": "int", "min": 1, "max": 255},
	"def": {"t": "int", "min": 1, "max": 255},
	"spd": {"t": "int", "min": 1, "max": 255},
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
		"type": {"t": "ref", "cat": "types"},
		"mult": {"t": "number", "min": 0.0, "max": 5.0},
	},
	"capture": {
		"mult": {"t": "number", "min": 0.0, "max": 10.0},
		"field_bonus": {"t": "map", "opt": true,
			"key": {"t": "ref", "cat": "field_states"},
			"value": {"t": "number", "min": 0.0, "max": 10.0}},
	},
}

const ENTRY := {
	"creatures": {
		"id": {"t": "id"},
		"name": {"t": "string"},
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
	},
	"moves": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
		"type": {"t": "ref", "cat": "types"},
		"category": {"t": "enum", "values": ["physical", "special", "status"]},
		"power": {"t": "int", "min": 0, "max": 300},
		"accuracy": {"t": "int", "min": 1, "max": 100},
		"always_hits": {"t": "bool", "opt": true},
		"priority": {"t": "int", "opt": true, "min": -3, "max": 3},
		"target": {"t": "enum", "values": TARGETS},
		"effects": {"t": "effects"},
	},
	"items": {
		"id": {"t": "id"},
		"name": {"t": "string"},
		"description": {"t": "string", "opt": true},
		"category": {"t": "enum", "values": ["capture", "heal", "battle", "key"]},
		"price": {"t": "int", "min": 0},
		"target": {"t": "enum", "values": TARGETS, "opt": true},
		"effects": {"t": "effects", "opt": true},
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
	"balance": {
		"level_cap": {"t": "int", "min": 1, "max": 100},
		"party_size": {"t": "int", "min": 1, "max": 6},
		"max_moves": {"t": "int", "min": 1, "max": 8},
		"stab": {"t": "number", "min": 1.0, "max": 3.0},
		"max_field_states": {"t": "int", "min": 1, "max": 5},
		"growth_affinity_threshold": {"t": "int", "min": 0},
		"underdog": {"t": "dict", "fields": {
			"spread_reduction_per_ratio": {"t": "number", "min": 0.0, "max": 1.0},
			"spread_reduction_cap": {"t": "number", "min": 0.0, "max": 1.0},
			"stat_bonus_per_ratio": {"t": "number", "min": 0.0, "max": 2.0},
			"stat_bonus_cap": {"t": "number", "min": 0.0, "max": 2.0},
			"xp_bonus_per_ratio": {"t": "number", "min": 0.0, "max": 5.0},
		}},
		"catch": {"t": "dict", "fields": {
			"hp_weight": {"t": "number", "min": 0.0, "max": 1.0},
		}},
	},
}
