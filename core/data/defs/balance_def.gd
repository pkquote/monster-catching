class_name BalanceDef
extends RefCounted
## Global tuning numbers from data/balance.json.

var level_cap: int
var party_size: int
var max_moves: int
var stab: float
var max_field_states: int
var growth_affinity_threshold: int
var underdog: Dictionary
var catch_cfg: Dictionary


static func from_dict(d: Dictionary) -> BalanceDef:
	var b := BalanceDef.new()
	b.level_cap = int(d.level_cap)
	b.party_size = int(d.party_size)
	b.max_moves = int(d.max_moves)
	b.stab = float(d.stab)
	b.max_field_states = int(d.max_field_states)
	b.growth_affinity_threshold = int(d.growth_affinity_threshold)
	b.underdog = d.underdog.duplicate()
	b.catch_cfg = d.catch.duplicate()
	return b
