extends EffectOp
## { "op": "bonus_if_field", "side": ..., "state": id, "mult": float, "consume"?: bool }
## Multiplies the damage/heal that follows in the same effect list.
## Consumed states are removed after the whole move resolves.


func per_target() -> bool:
	return false


func apply(ctx: EffectContext, e: Dictionary, _target: Battler) -> void:
	var sides: Array = [0, 1] if e.side == "both" else [ctx.side_index(e.side)]
	for s in sides:
		if ctx.engine.sides[s].field.has(e.state):
			ctx.mult *= float(e.mult)
			if e.get("consume", false):
				ctx.pending_consume.append([s, e.state])
			return
