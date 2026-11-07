extends EffectOp
## { "op": "cure_status", "status"?: id } — clears the target's status (only that one when given).


func apply(ctx: EffectContext, e: Dictionary, target: Battler) -> void:
	ctx.engine.cure_status(target, e.get("status", ""), ctx.source == "item")
