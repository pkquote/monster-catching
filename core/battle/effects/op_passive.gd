extends EffectOp
## stat_mod, incoming_type_mod, skip_chance: read by the engine from statuses and
## field states (see BattleMath / BattleEngine). reset_training is field-only (refused in
## battle). Running them directly does nothing.


func per_target() -> bool:
	return false
