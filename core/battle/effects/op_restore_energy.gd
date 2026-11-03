extends EffectOp
## { "op": "restore_energy", "fraction": 0..1 } — share of max energy.


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	var amount := maxi(1, roundi(target.creature.max_energy(ctx.engine.db) * float(e.fraction)))
	ctx.engine.restore_energy(target, amount)
