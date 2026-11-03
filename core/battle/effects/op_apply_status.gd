extends EffectOp
## { "op": "apply_status", "status": id, "chance"?: 1..100 }


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	var chance: int = int(e.get("chance", 100))
	if chance < 100 and ctx.engine.rng.randi_range(1, 100) > chance:
		return
	ctx.engine.inflict_status(target, e.status, ctx.user)
