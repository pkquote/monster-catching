extends EffectOp
## { "op": "damage_fraction", "fraction": 0..1 } — fixed share of max HP (e.g. Burn).


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	var amount := maxi(1, int(target.creature.max_hp(ctx.engine.db) * float(e.fraction)))
	ctx.engine.deal_damage(target, amount, null, "")
