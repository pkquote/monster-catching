extends EffectOp
## { "op": "damage", "power"?: int, "type"?: id, "scale_with_stacks"?: bool }


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	var result := BattleMath.damage(ctx.engine, ctx, e, target, true)
	if result.type_mult == 0.0:
		ctx.engine.emit({"type": BattleEvents.NO_EFFECT, "bid": target.bid})
		return
	ctx.engine.deal_damage(target, result.amount, ctx.user, ctx.damage_type(e), result.type_mult)
