class_name BalanceDef
extends RefCounted
## Global tuning numbers from data/balance.json.

## Schema ceiling for balance.party_size.
const MAX_PARTY_SIZE: int = 12
## Schema ceiling for balance.max_hits (and any move's hits.max).
const MAX_HITS: int = 10

var level_cap: int
var party_size: int
var max_moves: int
## Most times one move use may hit (a move's hits.max may not exceed it).
var max_hits: int
var stab: float
## Damage multiplier by creatures hit: keys 2 and 3 (3 also covers more).
var spread_mults: Dictionary
var round_limit: int
var max_field_states: int
var growth_affinity_threshold: int
## Growth tier id -> multiplier on a stat's per-level growth.
var growth_tiers: Dictionary
## Total tier steps a creature may spend on growth_rates.
var growth_budget: int
var underdog: Dictionary
var catch_cfg: Dictionary
var xp_cfg: Dictionary
## event name -> { affinity: String, points: int }
var affinity_awards: Dictionary
## { resist_cap, endure_cap }
var resolve_cfg: Dictionary
## { base, rest_fraction, fallback_move }
var energy_cfg: Dictionary
## { points_per_level, max_per_stat, hp_per_point }
var training_cfg: Dictionary
## { min, max, starter, disobey_max_chance, penalty_max, lash_out_threshold, lash_out_chance,
##   xp_bonus_max, overwork_hp, overwork_energy, changes: { event: int } }
var bond_cfg: Dictionary
## { walk_speed, run_speed (tiles/s), encounter_rate, encounter_grace_tiles,
##   walk_energy_tiles, defeat_money_fraction, sell_fraction }
var overworld_cfg: Dictionary


static func from_dict(d: Dictionary) -> BalanceDef:
	var b := BalanceDef.new()
	b.level_cap = int(d.level_cap)
	b.party_size = int(d.party_size)
	b.max_moves = int(d.max_moves)
	b.max_hits = int(d.max_hits)
	b.stab = float(d.stab)
	b.spread_mults = {2: float(d.spread_mults["2"]), 3: float(d.spread_mults["3"])}
	b.round_limit = int(d.round_limit)
	b.max_field_states = int(d.max_field_states)
	b.growth_affinity_threshold = int(d.growth_affinity_threshold)
	b.growth_tiers = {}
	for k in d.growth_tiers:
		b.growth_tiers[k] = float(d.growth_tiers[k])
	b.growth_budget = int(d.growth_budget)
	b.underdog = d.underdog.duplicate()
	b.catch_cfg = d.catch.duplicate()
	b.xp_cfg = d.xp.duplicate()
	b.resolve_cfg = d.resolve.duplicate()
	b.energy_cfg = d.energy.duplicate()
	b.training_cfg = d.training.duplicate()
	for k in b.training_cfg:
		b.training_cfg[k] = int(b.training_cfg[k])
	b.bond_cfg = d.bond.duplicate(true)
	b.overworld_cfg = d.overworld.duplicate()
	for k in ["min", "max", "starter", "lash_out_threshold"]:
		b.bond_cfg[k] = int(b.bond_cfg[k])
	for k in b.bond_cfg.changes:
		b.bond_cfg.changes[k] = int(b.bond_cfg.changes[k])
	b.affinity_awards = {}
	for key in d.affinity_awards:
		var a: Dictionary = d.affinity_awards[key]
		b.affinity_awards[key] = {"affinity": a.affinity, "points": int(a.points)}
	return b


## A tier's multiplier as an exact whole percent (1.2 -> 120).
func growth_percent(tier: String) -> int:
	return roundi(float(growth_tiers[tier]) * 100.0)


## Damage multiplier for a move hitting `count` creatures: 1.0 for one or fewer.
func spread_mult_for(count: int) -> float:
	if count <= 1:
		return 1.0
	return float(spread_mults[2 if count == 2 else 3])
