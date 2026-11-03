extends EffectOp
## { "op": "remove_field_state", "side": ..., "state"?: id } — no state = clear all.


func per_target() -> bool:
	return false


func apply(ctx: EffectContext, e: Dictionary, _target: Battler) -> void:
	var sides: Array = [0, 1] if e.side == "both" else [ctx.side_index(e.side)]
	for s in sides:
		var field: Field = ctx.engine.sides[s].field
		var ids: PackedStringArray = PackedStringArray([e.state]) if e.has("state") else field.ids()
		for id in ids:
			ctx.engine.remove_field_state(s, id, "cleared")
