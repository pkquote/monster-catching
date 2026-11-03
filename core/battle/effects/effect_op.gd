class_name EffectOp
extends RefCounted
## Base class for effect handlers. One subclass per JSON "op".
##
## Creature-level ops (per_target() == true) run once for each creature target.
## Side-level ops run once per effect.
## Passive ops (stat_mod, incoming_type_mod, skip_chance) do nothing when run;
## the engine reads them from statuses and field states instead.


func per_target() -> bool:
	return true


func apply(_ctx: EffectContext, _e: Dictionary, _target: Battler) -> void:
	pass
