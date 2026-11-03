extends EffectOp
## { "op": "apply_field_state", "side": user|target|own|enemy|both, "state": id,
##   "stacks"?: int, "turns"?: int }


func per_target() -> bool:
	return false


func apply(ctx: EffectContext, e: Dictionary, _target: Battler) -> void:
	var stacks: int = int(e.get("stacks", 1))
	var turns: int = int(e.get("turns", 0))
	var sides: Array = [0, 1] if e.side == "both" else [ctx.side_index(e.side)]
	for s in sides:
		ctx.engine.apply_field_state(s, e.state, stacks, turns, ctx.user, not ctx.is_reaction())
