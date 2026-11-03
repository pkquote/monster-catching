extends EffectOp
## { "op": "heal", "fraction": 0..1 } — share of max HP, boosted by bonus_if_field.


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	var max_hp := target.creature.max_hp(ctx.engine.db)
	var amount := maxi(1, roundi(max_hp * float(e.fraction) * ctx.mult))
	ctx.engine.heal(target, amount, ctx.user, ctx.source == "item")
