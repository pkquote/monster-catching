extends EffectOp
## { "op": "capture", "mult": float, "field_bonus"?: { state_id: mult } }


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	ctx.engine.attempt_capture(ctx.user, target, ctx.item, e)
