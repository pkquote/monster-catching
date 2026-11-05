extends EffectOp
## stat_mod, incoming_type_mod, skip_chance and the passive-only ops (type_power, absorb_type,
## status_immune, guard_stages, field_shelter, field_boost, reaction_power, energy_discount,
## rest_bonus, scrap_power; overworld: encounter_rate, xp_mult, bond_gain) are read by the engine
## from statuses, field states and passives (see BattleMath / BattleEngine). reset_training is field-only (refused in
## battle). Running them directly does nothing.


func per_target() -> bool:
	return false
