class_name WalkTracker
extends RefCounted
## Walking slowly restores energy: every `walk_energy_tiles` tiles, each party
## creature that can still fight gains 1 energy (up to its max). HP doesn't regenerate.

var _every: int
var _steps := 0


func _init(balance: BalanceDef) -> void:
	_every = maxi(1, int(balance.overworld_cfg.walk_energy_tiles))


## Call once per new tile walked. Returns true on the tiles that gave energy.
func on_tile(db: Database, party: Array) -> bool:
	_steps += 1
	if _steps < _every:
		return false
	_steps = 0
	for c: CreatureInstance in party:
		if c.hp > 0:
			c.energy = mini(c.energy + 1, c.max_energy(db))
	return true
