extends EffectOp
## { "op": "stat_stage", "stat": atk|def|spd|acc, "stages": -3..3 }


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	ctx.engine.shift_stage(target, e.stat, int(e.stages), ctx.user)
