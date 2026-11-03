class_name BalanceDef
extends RefCounted
## Global tuning numbers from data/balance.json.

var level_cap: int
var party_size: int
var max_moves: int
var stab: float
var spread_mult: float
var round_limit: int
var max_field_states: int
var growth_affinity_threshold: int
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


static func from_dict(d: Dictionary) -> BalanceDef:
	var b := BalanceDef.new()
	b.level_cap = int(d.level_cap)
	b.party_size = int(d.party_size)
	b.max_moves = int(d.max_moves)
	b.stab = float(d.stab)
	b.spread_mult = float(d.spread_mult)
	b.round_limit = int(d.round_limit)
	b.max_field_states = int(d.max_field_states)
	b.growth_affinity_threshold = int(d.growth_affinity_threshold)
	b.underdog = d.underdog.duplicate()
	b.catch_cfg = d.catch.duplicate()
	b.xp_cfg = d.xp.duplicate()
	b.resolve_cfg = d.resolve.duplicate()
	b.energy_cfg = d.energy.duplicate()
	b.training_cfg = d.training.duplicate()
	for k in b.training_cfg:
		b.training_cfg[k] = int(b.training_cfg[k])
	b.bond_cfg = d.bond.duplicate(true)
	for k in ["min", "max", "starter", "lash_out_threshold"]:
		b.bond_cfg[k] = int(b.bond_cfg[k])
	for k in b.bond_cfg.changes:
		b.bond_cfg.changes[k] = int(b.bond_cfg.changes[k])
	b.affinity_awards = {}
	for key in d.affinity_awards:
		var a: Dictionary = d.affinity_awards[key]
		b.affinity_awards[key] = {"affinity": a.affinity, "points": int(a.points)}
	return b
