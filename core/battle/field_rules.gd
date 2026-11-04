class_name FieldRules
extends BattlePart
## Field states on each side and the reactions between them: applying, stacking,
## pushing out, expiring, cashing in, and firing reactions.


## Passive effects (stat_mod, incoming_type_mod...) from the states on a side.
func side_passives(side_index: int) -> Array:
	var out: Array = []
	var db := engine.db
	for st in engine.sides[side_index].field.states:
		out.append_array(db.field_state(st.id).passive)
	return out


## Applies a field state to a side. If it meets a state it reacts with (and
## `allow_reaction`), the reaction fires instead of a normal stack.
func apply(side_index: int, state_id: String, stacks: int, turns: int, user: Battler,
		allow_reaction := true) -> void:
	var e := engine
	var field := e.sides[side_index].field
	var fdef := e.db.field_state(state_id)
	var t := turns if turns > 0 else fdef.default_turns
	if allow_reaction and not field.has(state_id):
		for existing in field.ids():
			var r := e.db.find_reaction(existing, state_id)
			if r != null:
				_trigger_reaction(side_index, r, existing, state_id, stacks, t, user)
				return
	if not field.has(state_id) and field.size() >= e.db.balance.max_field_states:
		var old := field.pop_oldest()
		e.emit({"type": BattleEvents.FIELD_REMOVED, "side": side_index, "state": old, "reason": "pushed_out"})
	var n := field.add(state_id, stacks, t, fdef.max_stacks)
	e.emit({"type": BattleEvents.FIELD_APPLIED, "side": side_index, "state": state_id, "stacks": n,
		"turns": t, "by": user.bid if user != null else -1})
	if user != null:
		e.rewards.award(user, "field_applied")


func remove(side_index: int, state_id: String, reason: String) -> void:
	if engine.sides[side_index].field.remove(state_id) > 0:
		engine.emit({"type": BattleEvents.FIELD_REMOVED, "side": side_index, "state": state_id, "reason": reason})


## Removes the states a move "cashed in" (bonus_if_field with consume), once each.
func finish_consume(ctx: EffectContext) -> void:
	var done := {}
	for pair in ctx.pending_consume:
		var key := "%d:%s" % pair
		if done.has(key):
			continue
		done[key] = true
		if engine.sides[pair[0]].field.has(pair[1]):
			remove(pair[0], pair[1], "cashed_in")
			engine.rewards.award(ctx.user, "field_cashed_in")


## Counts every side's states down at the end of a round and drops expired ones.
func tick_all() -> void:
	for side in engine.sides:
		for id in side.field.tick():
			engine.emit({"type": BattleEvents.FIELD_REMOVED, "side": side.index, "state": id, "reason": "expired"})


func _trigger_reaction(side_index: int, r: ReactionDef, existing: String, incoming: String,
		incoming_stacks: int, turns: int, user: Battler) -> void:
	var e := engine
	var field := e.sides[side_index].field
	var consumed := 0
	var removed := PackedStringArray()
	for s in r.consumes:
		if s == incoming:
			consumed += incoming_stacks
		elif field.has(s):
			consumed += field.remove(s)
			removed.append(s)
	e.emit({"type": BattleEvents.REACTION, "reaction": r.id, "side": side_index, "inputs": [existing, incoming],
		"stacks": consumed, "by": user.bid if user != null else -1})
	for s in removed:
		e.emit({"type": BattleEvents.FIELD_REMOVED, "side": side_index, "state": s, "reason": "reacted"})
	if user != null:
		e.rewards.award(user, "reaction_triggered")
	# The incoming state still lands unless the reaction used it up.
	if not r.consumes.has(incoming):
		apply(side_index, incoming, incoming_stacks, turns, user, false)
	var ctx := EffectContext.new()
	ctx.engine = e
	ctx.user = user
	ctx.source = "reaction"
	ctx.reaction = r
	ctx.target_side = side_index
	ctx.stacks_consumed = consumed
	if r.scope == "both_sides":
		ctx.targets.append_array(e.sides[0].active())
		ctx.targets.append_array(e.sides[1].active())
	else:
		ctx.targets.append_array(e.sides[side_index].active())
	e.run_effects(ctx, r.effects)
