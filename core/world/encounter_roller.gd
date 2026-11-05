class_name EncounterRoller
extends RefCounted
## Decides, per grass tile the player steps onto, whether a wild encounter starts.
## After a battle a few grass tiles are free (`encounter_grace_tiles`).

var _rate: float
var _grace_tiles: int
var _grace := 0
var _rng: RandomNumberGenerator


func _init(balance: BalanceDef, rng: RandomNumberGenerator) -> void:
	_rate = float(balance.overworld_cfg.encounter_rate)
	_grace_tiles = int(balance.overworld_cfg.encounter_grace_tiles)
	_rng = rng


## True when stepping onto this grass tile starts an encounter. Never with no
## table (`table_id` "") or when the party has nobody who can fight. `rate_mult` scales
## the rate (the party lead's `encounter_rate` passive).
func on_grass_tile(table_id: String, can_fight: bool, rate_mult := 1.0) -> bool:
	if table_id == "" or not can_fight:
		return false
	if _grace > 0:
		_grace -= 1
		return false
	return _rng.randf() < _rate * rate_mult


func start_grace() -> void:
	_grace = _grace_tiles
