extends EffectOp
## { "op": "damage", "power"?: int, "type"?: id, "scale_with_stacks"?: bool }


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	# field_shelter: reactions involving a sheltered state don't damage it.
	if ctx.is_reaction():
		var shelter := ctx.engine.field_rules.reaction_shelter(ctx.reaction, target)
		if shelter != null:
			ctx.engine.emit_passive(shelter)
			return
	var result := BattleMath.damage(ctx.engine, ctx, e, target, true)
	var type := ctx.damage_type(e)
	# An immune creature that absorbs the type still heals (deal_damage handles it).
	if result.type_mult == 0.0 and ctx.engine.passive_rules.absorbs(target, type) <= 0.0:
		ctx.engine.emit({"type": BattleEvents.NO_EFFECT, "bid": target.bid})
		return
	var contact := ctx.move != null and ctx.move.category == "physical"
	ctx.engine.deal_damage(target, result.amount, ctx.user, type, result.type_mult, contact)
