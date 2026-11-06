class_name EffectOps
extends RefCounted
## op name -> handler. To add a behavior: add an op schema in DataSchemas.EFFECT_OPS,
## write an op_<name>.gd handler here, register it below, and describe it in
## EffectText.effect() in core/data/effect_text.gd.

static var _registry: Dictionary = {}


static func get_op(op: String) -> EffectOp:
	if _registry.is_empty():
		_registry = {
			"damage": preload("op_damage.gd").new(),
			"damage_fraction": preload("op_damage_fraction.gd").new(),
			"heal": preload("op_heal.gd").new(),
			"apply_status": preload("op_apply_status.gd").new(),
			"stat_stage": preload("op_stat_stage.gd").new(),
			"apply_field_state": preload("op_apply_field_state.gd").new(),
			"remove_field_state": preload("op_remove_field_state.gd").new(),
			"bonus_if_field": preload("op_bonus_if_field.gd").new(),
			"capture": preload("op_capture.gd").new(),
			"restore_energy": preload("op_restore_energy.gd").new(),
			"stat_mod": preload("op_passive.gd").new(),
			"incoming_type_mod": preload("op_passive.gd").new(),
			"skip_chance": preload("op_passive.gd").new(),
			"reset_training": preload("op_passive.gd").new(),
			"type_power": preload("op_passive.gd").new(),
			"absorb_type": preload("op_passive.gd").new(),
			"status_immune": preload("op_passive.gd").new(),
			"guard_stages": preload("op_passive.gd").new(),
			"field_shelter": preload("op_passive.gd").new(),
			"field_boost": preload("op_passive.gd").new(),
			"reaction_power": preload("op_passive.gd").new(),
			"energy_discount": preload("op_passive.gd").new(),
			"rest_bonus": preload("op_passive.gd").new(),
			"scrap_power": preload("op_passive.gd").new(),
			"encounter_rate": preload("op_passive.gd").new(),
			"xp_mult": preload("op_passive.gd").new(),
			"bond_gain": preload("op_passive.gd").new(),
		}
	return _registry.get(op)


## Every op name with a handler (tests check this matches the schema list).
static func known_ops() -> PackedStringArray:
	get_op("damage")
	return PackedStringArray(_registry.keys())
