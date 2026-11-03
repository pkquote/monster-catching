class_name BattleEngine
extends RefCounted
## Headless N-vs-M battle engine. No nodes, no scenes, no autoloads.
##
##   var engine := BattleEngine.new(db, rng, setup)
##   var events := engine.start()
##   while not engine.is_over():
##       var actions := [...]               # one per slot in engine.actions_needed(0)
##       events = engine.resolve_round(actions)
##       for i in engine.pending_replacements(0): engine.replace(0, chosen_bid)
##   var result := engine.result()
##
## AI-controlled sides choose their own actions inside resolve_round.
## Every outcome is reported as an event Dictionary { type, ... }; see
## documentation/battle-engine.md for the full list.

const PRIORITY_FLEE := 7
const PRIORITY_SWAP := 6
const PRIORITY_ITEM := 5

const CREATURE_TARGETS := ["self", "one_ally", "one_enemy", "all_allies", "all_enemies", "all"]

var db: Database
var rng: RandomNumberGenerator
var setup: BattleSetup
var sides: Array[BattleSide] = []
var round_number := 0

var _battlers: Dictionary = {}  # bid -> Battler
var _events: Array = []
var _over := false
var _winner := -1
var _end_reason := ""
var _captured: Array[CreatureInstance] = []
## bid -> { affinity_id: points gained this battle }
var _affinity_log: Dictionary = {}


func _init(p_db: Database, p_rng: RandomNumberGenerator, p_setup: BattleSetup) -> void:
	db = p_db
	rng = p_rng
	setup = p_setup
	var next_bid := 0
	for i in setup.sides.size():
		var sd: Dictionary = setup.sides[i]
		var side := BattleSide.new()
		side.index = i
		side.max_active = sd.max_active
		side.items = sd.items.duplicate()
		side.ai = sd.ai
		side.is_wild = sd.is_wild
		side.auto_replace = sd.auto_replace or side.is_ai()
		for c: CreatureInstance in sd.party:
			var b := Battler.new(next_bid, i, c)
			next_bid += 1
			if c.status != "":
				b.status_turns = db.status(c.status).turns
			side.battlers.append(b)
			_battlers[b.bid] = b
		side.slots.resize(clampi(int(sd.field_count), 1, side.max_active))
		sides.append(side)


# --- Public API ---------------------------------------------------------------

func start() -> Array:
	_events = []
	emit({"type": "battle_start", "wild": setup.is_wild, "tamer": setup.tamer_id,
		"slots": [sides[0].slots.size(), sides[1].slots.size()]})
	for side in sides:
		for slot in side.slots.size():
			var bench := side.bench()
			if bench.is_empty():
				break
			_place(side, slot, bench[0])
	_update_underdog()
	_check_end()
	return _take_events()


## One bid per action this side gets this round (Underdog bonus actions repeat a bid).
func actions_needed(side_index: int) -> Array[int]:
	var out: Array[int] = []
	var side := sides[side_index]
	for b in side.active():
		for n in 1 + int(side.underdog.get("bonus_actions", 0)):
			out.append(b.bid)
	return out


## The always-available fallback move (Scrap).
func fallback_move() -> String:
	return db.balance.energy_cfg.fallback_move


## Moves this battler can use right now: known moves it has energy for, plus the fallback.
func usable_moves(bid: int) -> PackedStringArray:
	var b := battler(bid)
	var out := PackedStringArray()
	for mid in b.creature.moves:
		var m := db.move(mid)
		if m != null and m.cost <= b.energy():
			out.append(mid)
	if not out.has(fallback_move()):
		out.append(fallback_move())
	return out


## Valid target choices for a move: target bids, or [-1] when no choice is needed.
func targets_for(bid: int, move_id: String) -> Array[int]:
	var b := battler(bid)
	var m := db.move(move_id)
	var out: Array[int] = []
	match m.target:
		"one_enemy":
			for t in sides[1 - b.side].active():
				out.append(t.bid)
		"one_ally":
			for t in sides[b.side].active():
				out.append(t.bid)
		_:
			out.append(-1)
	return out


## Runs one round. `actions` covers the caller-controlled sides; AI sides choose their own.
func resolve_round(actions: Array) -> Array:
	_events = []
	if _over:
		return _events
	round_number += 1
	emit({"type": "round_start", "round": round_number})
	var all: Array = actions.duplicate()
	for side in sides:
		if side.is_ai():
			all.append_array(BattleAI.choose_all(self, side.index))

	var allowed := {}
	for side in sides:
		for bid in actions_needed(side.index):
			allowed[bid] = int(allowed.get(bid, 0)) + 1
	var queue: Array = []
	for a: BattleAction in all:
		if int(allowed.get(a.actor, 0)) <= 0:
			emit({"type": "action_invalid", "bid": a.actor, "reason": "no_action_slot"})
			continue
		allowed[a.actor] -= 1
		queue.append({
			"action": a,
			"priority": _priority(a),
			"speed": BattleMath.effective_stat(self, battler(a.actor), "spd"),
			"tie": rng.randf(),
		})
	queue.sort_custom(func(x, y):
		if x.priority != y.priority:
			return x.priority > y.priority
		if x.speed != y.speed:
			return x.speed > y.speed
		return x.tie > y.tie)

	for q in queue:
		if _over:
			break
		_execute(q.action)
	if not _over:
		_end_of_round()
	return _take_events()


## Open slots the caller should fill with replace() before the next round.
## Leaving a slot empty is allowed (it keeps that side outnumbered).
func pending_replacements(side_index: int) -> int:
	var side := sides[side_index]
	if side.auto_replace or _over:
		return 0
	return mini(side.open_slots().size(), side.bench().size())


func replace(side_index: int, bid: int) -> Array:
	_events = []
	var side := sides[side_index]
	var b := battler(bid)
	var open := side.open_slots()
	if b == null or b.side != side_index or not b.alive() or b.active or open.is_empty():
		emit({"type": "action_invalid", "bid": bid, "reason": "bad_replacement"})
		return _take_events()
	_place(side, open[0], b)
	_update_underdog()
	return _take_events()


func is_over() -> bool:
	return _over


## { over, winner (-1 = none), reason, captured: Array[CreatureInstance], rounds, affinity }
func result() -> Dictionary:
	return {
		"over": _over,
		"winner": _winner,
		"reason": _end_reason,
		"captured": _captured,
		"rounds": round_number,
		"affinity": _affinity_log.duplicate(true),
	}


func battler(bid: int) -> Battler:
	return _battlers.get(bid)


func all_battlers() -> Array:
	return _battlers.values()


# --- Queries used by formulas and ops -------------------------------------------

func side_passives(side_index: int) -> Array:
	var out: Array = []
	for st in sides[side_index].field.states:
		out.append_array(db.field_state(st.id).passive)
	return out


func status_passives(b: Battler) -> Array:
	return [] if b.status() == "" else db.status(b.status()).effects


func passives(b: Battler) -> Array:
	return side_passives(b.side) + status_passives(b)


## Creature targets for a move/item target key. Invalid choices are re-targeted
## at random (when `allow_random`) so a move aimed at a fainted foe still lands.
func resolve_targets(user: Battler, key: String, chosen: int, allow_random := true) -> Array[Battler]:
	var own := sides[user.side]
	var opp := sides[1 - user.side]
	var out: Array[Battler] = []
	match key:
		"self":
			out.append(user)
		"one_enemy":
			var c := battler(chosen)
			if c != null and c.side == opp.index and c.alive() and c.active:
				out.append(c)
			elif allow_random and not opp.active().is_empty():
				var pool := opp.active()
				out.append(pool[rng.randi_range(0, pool.size() - 1)])
		"one_ally":
			var c := battler(chosen)
			# Items may target benched allies too.
			out.append(c if c != null and c.side == own.index and c.alive() else user)
		"all_enemies":
			out.append_array(opp.active())
		"all_allies":
			out.append_array(own.active())
		"all":
			for b in own.active() + opp.active():
				if b != user:
					out.append(b)
	return out


# --- Mutations called by effect ops ------------------------------------------------

func emit(event: Dictionary) -> void:
	_events.append(event)


func run_effects(ctx: EffectContext, effects: Array) -> void:
	for e: Dictionary in effects:
		var op := EffectOps.get_op(e.op)
		if op == null:
			continue
		if not op.per_target():
			op.apply(ctx, e, null)
			continue
		var targets: Array[Battler] = ctx.targets
		if e.has("target"):
			targets = _effect_targets(ctx, e.target)
		for t in targets:
			if t.alive():
				op.apply(ctx, e, t)


func deal_damage(target: Battler, amount: int, attacker: Battler, type: String, type_mult := 1.0) -> void:
	var dealt := mini(amount, target.hp())
	# Resolve: once per battle, a knockout blow from a foe may leave 1 HP.
	if dealt >= target.hp() and target.hp() > 1 and not target.endured and attacker != null \
			and attacker.side != target.side and rng.randf() < BattleMath.endure_chance(self, target, attacker):
		target.endured = true
		dealt = target.hp() - 1
		emit({"type": "endured", "bid": target.bid})
	target.creature.hp -= dealt
	emit({"type": "damage", "bid": target.bid, "amount": dealt, "hp": target.hp(),
		"max_hp": target.creature.max_hp(db), "by": attacker.bid if attacker != null else -1,
		"damage_type": type, "effectiveness": type_mult})
	if attacker != null and attacker.side != target.side and dealt > 0:
		target.last_hit_by = attacker.bid
		_award(attacker, "hit_dealt")
		if target.hp() > 0:
			_award(target, "hit_survived")


func heal(target: Battler, amount: int, user: Battler, from_item := false) -> void:
	var max_hp := target.creature.max_hp(db)
	var healed := mini(amount, max_hp - target.hp())
	target.creature.hp += healed
	emit({"type": "heal", "bid": target.bid, "amount": healed, "hp": target.hp(), "max_hp": max_hp})
	if user != null and healed > 0:
		_award(user, "heal")
	if from_item and healed > 0:
		_bond(target, "healed_item")


func restore_energy(target: Battler, amount: int) -> void:
	var max_e := target.creature.max_energy(db)
	var gained := mini(amount, max_e - target.energy())
	target.creature.energy += gained
	emit({"type": "energy", "bid": target.bid, "change": gained, "energy": target.energy(), "max_energy": max_e})


func inflict_status(target: Battler, status_id: String, user: Battler) -> void:
	if target.status() != "":
		emit({"type": "status_failed", "bid": target.bid, "status": status_id, "has": target.status()})
		return
	if user != target and rng.randf() < BattleMath.resist_chance(self, target, user):
		emit({"type": "resisted", "bid": target.bid, "status": status_id})
		return
	target.creature.status = status_id
	target.status_turns = db.status(status_id).turns
	emit({"type": "status_applied", "bid": target.bid, "status": status_id, "turns": target.status_turns})
	if user != null and user.side != target.side:
		_award(user, "status_inflicted")


func shift_stage(target: Battler, stat: String, amount: int, user: Battler) -> void:
	if amount < 0 and user != null and user.side != target.side \
			and rng.randf() < BattleMath.resist_chance(self, target, user):
		emit({"type": "resisted", "bid": target.bid, "stat": stat})
		return
	var moved := target.shift_stage(stat, amount)
	emit({"type": "stat_stage", "bid": target.bid, "stat": stat, "change": moved, "stage": target.stages[stat]})
	if moved < 0 and user != null and user.side != target.side:
		_award(user, "stat_lowered", -moved)


## Applies a field state to a side. If it meets a state it reacts with (and
## `allow_reaction`), the reaction fires instead of a normal stack.
func apply_field_state(side_index: int, state_id: String, stacks: int, turns: int,
		user: Battler, allow_reaction := true) -> void:
	var field := sides[side_index].field
	var fdef := db.field_state(state_id)
	var t := turns if turns > 0 else fdef.default_turns
	if allow_reaction and not field.has(state_id):
		for existing in field.ids():
			var r := db.find_reaction(existing, state_id)
			if r != null:
				_trigger_reaction(side_index, r, existing, state_id, stacks, t, user)
				return
	if not field.has(state_id) and field.size() >= db.balance.max_field_states:
		var old := field.pop_oldest()
		emit({"type": "field_removed", "side": side_index, "state": old, "reason": "pushed_out"})
	var n := field.add(state_id, stacks, t, fdef.max_stacks)
	emit({"type": "field_applied", "side": side_index, "state": state_id, "stacks": n, "turns": t,
		"by": user.bid if user != null else -1})
	if user != null:
		_award(user, "field_applied")


func remove_field_state(side_index: int, state_id: String, reason: String) -> void:
	if sides[side_index].field.remove(state_id) > 0:
		emit({"type": "field_removed", "side": side_index, "state": state_id, "reason": reason})


func attempt_capture(user: Battler, target: Battler, item: ItemDef, e: Dictionary) -> void:
	if not sides[target.side].is_wild:
		emit({"type": "capture_failed", "bid": user.bid, "target": target.bid, "reason": "not_wild"})
		return
	var p := BattleMath.capture_chance(self, target, e)
	var success := rng.randf() < p
	emit({"type": "capture_attempt", "bid": user.bid, "target": target.bid,
		"item": item.id if item != null else "", "chance": p, "success": success})
	if not success:
		return
	var side := sides[target.side]
	target.captured = true
	target.active = false
	var slot := side.slot_of(target)
	if slot != -1:
		side.slots[slot] = null
	_captured.append(target.creature)
	emit({"type": "captured", "bid": target.bid, "species": target.creature.species})


# --- Round internals ---------------------------------------------------------------

func _priority(a: BattleAction) -> int:
	match a.kind:
		"flee": return PRIORITY_FLEE
		"swap": return PRIORITY_SWAP
		"item": return PRIORITY_ITEM
		"move":
			var m := db.move(a.move)
			return m.priority if m != null else 0
	return 0


func _execute(a: BattleAction) -> void:
	var b := battler(a.actor)
	if b == null or not b.alive() or not b.active:
		return
	match a.kind:
		"pass":
			emit({"type": "pass", "bid": b.bid})
		"flee":
			_do_flee(b)
		"swap":
			_do_swap(b, a.swap_in)
		"item":
			_do_item(b, a)
		"rest":
			_check_overwork(b)
			_do_rest(b)
		"move":
			_check_overwork(b)
			if not _skips_action(b) and not _bond_misbehaves(b, a):
				_do_move(b, a)
		_:
			emit({"type": "action_invalid", "bid": b.bid, "reason": "unknown_kind"})
	_check_faints()
	_check_end()


func _skips_action(b: Battler) -> bool:
	for p in status_passives(b):
		if p.op == "skip_chance" and rng.randi_range(1, 100) <= int(p.chance):
			emit({"type": "action_skipped", "bid": b.bid, "status": b.status()})
			return true
	return false


func _do_move(b: Battler, a: BattleAction) -> void:
	var m := db.move(a.move)
	if m == null or not (b.creature.moves.has(a.move) or a.move == fallback_move()):
		emit({"type": "action_invalid", "bid": b.bid, "reason": "unknown_move", "move": a.move})
		return
	if m.cost > b.energy():
		emit({"type": "action_invalid", "bid": b.bid, "reason": "no_energy", "move": a.move})
		return
	if m.cost > 0:
		b.creature.energy -= m.cost
		emit({"type": "energy", "bid": b.bid, "change": -m.cost, "energy": b.energy(),
			"max_energy": b.creature.max_energy(db)})
	var ctx := EffectContext.new()
	ctx.engine = self
	ctx.user = b
	ctx.source = "move"
	ctx.move = m
	match m.target:
		"own_side":
			ctx.target_side = b.side
		"enemy_side":
			ctx.target_side = 1 - b.side
	var targets := resolve_targets(b, m.target, a.target)
	emit({"type": "move_used", "bid": b.bid, "move": m.id,
		"targets": targets.map(func(t): return t.bid), "side": ctx.target_side})
	if m.target in CREATURE_TARGETS:
		if targets.is_empty():
			emit({"type": "no_target", "bid": b.bid})
			return
		ctx.spread = targets.size() > 1
		for t in targets:
			if t.side == b.side or BattleMath.rolls_hit(self, b, m):
				ctx.targets.append(t)
			else:
				emit({"type": "miss", "bid": b.bid, "target": t.bid})
		if ctx.targets.is_empty():
			return
	run_effects(ctx, m.effects)
	_finish_consume(ctx)


func _do_rest(b: Battler) -> void:
	emit({"type": "rest", "bid": b.bid})
	restore_energy(b, maxi(1, roundi(b.creature.max_energy(db) * float(db.balance.energy_cfg.rest_fraction))))


## Negative Bond: may lash out (Scrap on itself or an ally) or disobey (random other
## usable move, or loafing around). Returns true if the ordered move must not run.
func _bond_misbehaves(b: Battler, a: BattleAction) -> bool:
	if rng.randf() < Progression.lash_out_chance(db, b.creature):
		var pool: Array[Battler] = sides[b.side].active()
		var victim: Battler = pool[rng.randi_range(0, pool.size() - 1)]
		emit({"type": "lashed_out", "bid": b.bid, "target": victim.bid})
		var ctx := EffectContext.new()
		ctx.engine = self
		ctx.user = b
		ctx.source = "move"
		ctx.move = db.move(fallback_move())
		ctx.targets.append(victim)
		run_effects(ctx, ctx.move.effects)
		return true
	if rng.randf() < Progression.disobey_chance(db, b.creature):
		var options := Array(usable_moves(b.bid)).filter(func(mid): return mid != a.move)
		var pick := rng.randi_range(0, options.size())  # == size -> loaf
		if pick >= options.size():
			emit({"type": "disobeyed", "bid": b.bid, "ordered": a.move, "did": ""})
			return true
		emit({"type": "disobeyed", "bid": b.bid, "ordered": a.move, "did": options[pick]})
		_do_move(b, BattleAction.use_move(b.bid, options[pick]))
		return true
	return false


## Bond loss for fighting while worn out (once per battle per creature).
func _check_overwork(b: Battler) -> void:
	if b.overworked:
		return
	var cfg := db.balance.bond_cfg
	var low_hp := float(b.hp()) < float(b.creature.max_hp(db)) * float(cfg.overwork_hp)
	var low_energy := float(b.energy()) < float(b.creature.max_energy(db)) * float(cfg.overwork_energy)
	if low_hp or low_energy:
		b.overworked = true
		_bond(b, "overworked")


func _bond(b: Battler, happening: String) -> void:
	var change := Progression.change_bond(db, b.creature, happening)
	if change != 0:
		emit({"type": "bond", "bid": b.bid, "change": change, "bond": b.creature.bond, "reason": happening})


func _do_item(b: Battler, a: BattleAction) -> void:
	var side := sides[b.side]
	var it := db.item(a.item)
	if it == null or int(side.items.get(a.item, 0)) <= 0:
		emit({"type": "action_invalid", "bid": b.bid, "reason": "no_item", "item": a.item})
		return
	if it.category == "capture" and not setup.is_wild:
		emit({"type": "action_invalid", "bid": b.bid, "reason": "not_wild", "item": a.item})
		return
	side.items[a.item] = int(side.items[a.item]) - 1
	var ctx := EffectContext.new()
	ctx.engine = self
	ctx.user = b
	ctx.source = "item"
	ctx.item = it
	ctx.targets = resolve_targets(b, it.target, a.target)
	emit({"type": "item_used", "bid": b.bid, "item": it.id,
		"targets": ctx.targets.map(func(t): return t.bid), "left": side.items[a.item]})
	run_effects(ctx, it.effects)


func _do_swap(b: Battler, bench_bid: int) -> void:
	var side := sides[b.side]
	var incoming := battler(bench_bid)
	if incoming == null or incoming.side != b.side or not incoming.alive() or incoming.active:
		emit({"type": "action_invalid", "bid": b.bid, "reason": "bad_swap"})
		return
	var slot := side.slot_of(b)
	b.active = false
	b.reset_stages()
	emit({"type": "swap_out", "bid": b.bid, "side": b.side, "slot": slot})
	_place(side, slot, incoming)


func _do_flee(b: Battler) -> void:
	if not setup.is_wild or b.side != 0:
		emit({"type": "action_invalid", "bid": b.bid, "reason": "cannot_flee"})
		return
	emit({"type": "fled", "bid": b.bid})
	_finish(-1, "fled")


func _place(side: BattleSide, slot: int, b: Battler) -> void:
	side.slots[slot] = b
	b.active = true
	b.participated = true
	emit({"type": "send_out", "side": side.index, "slot": slot, "bid": b.bid,
		"species": b.creature.species, "level": b.creature.level,
		"hp": b.hp(), "max_hp": b.creature.max_hp(db),
		"energy": b.energy(), "max_energy": b.creature.max_energy(db)})
	_check_overwork(b)


func _finish_consume(ctx: EffectContext) -> void:
	var done := {}
	for pair in ctx.pending_consume:
		var key := "%d:%s" % pair
		if done.has(key):
			continue
		done[key] = true
		if sides[pair[0]].field.has(pair[1]):
			remove_field_state(pair[0], pair[1], "cashed_in")
			_award(ctx.user, "field_cashed_in")


func _trigger_reaction(side_index: int, r: ReactionDef, existing: String, incoming: String,
		incoming_stacks: int, turns: int, user: Battler) -> void:
	var field := sides[side_index].field
	var consumed := 0
	var removed := PackedStringArray()
	for s in r.consumes:
		if s == incoming:
			consumed += incoming_stacks
		elif field.has(s):
			consumed += field.remove(s)
			removed.append(s)
	emit({"type": "reaction", "reaction": r.id, "side": side_index, "inputs": [existing, incoming],
		"stacks": consumed, "by": user.bid if user != null else -1})
	for s in removed:
		emit({"type": "field_removed", "side": side_index, "state": s, "reason": "reacted"})
	if user != null:
		_award(user, "reaction_triggered")
	# The incoming state still lands unless the reaction used it up.
	if not r.consumes.has(incoming):
		apply_field_state(side_index, incoming, incoming_stacks, turns, user, false)
	var ctx := EffectContext.new()
	ctx.engine = self
	ctx.user = user
	ctx.source = "reaction"
	ctx.reaction = r
	ctx.target_side = side_index
	ctx.stacks_consumed = consumed
	if r.scope == "both_sides":
		ctx.targets.append_array(sides[0].active())
		ctx.targets.append_array(sides[1].active())
	else:
		ctx.targets.append_array(sides[side_index].active())
	run_effects(ctx, r.effects)


## Targets for an effect with its own "target" key. Reactions resolve relative to
## the side the reaction fired on; everything else relative to the user.
func _effect_targets(ctx: EffectContext, key: String) -> Array[Battler]:
	if not ctx.is_reaction() and ctx.user != null:
		return resolve_targets(ctx.user, key, -1)
	var own := sides[ctx.target_side]
	var opp := sides[1 - ctx.target_side]
	var out: Array[Battler] = []
	match key:
		"all_allies", "own_side":
			out.append_array(own.active())
		"all_enemies", "enemy_side":
			out.append_array(opp.active())
		"all":
			out.append_array(own.active() + opp.active())
		"one_ally":
			if not own.active().is_empty():
				out.append(own.active()[0])
		"one_enemy":
			if not opp.active().is_empty():
				out.append(opp.active()[0])
		"self":
			if ctx.user != null:
				out.append(ctx.user)
	return out


func _check_faints() -> void:
	for side in sides:
		for b in side.battlers:
			if b.active and b.creature.hp <= 0 and not b.fainted:
				b.fainted = true
				b.active = false
				emit({"type": "faint", "bid": b.bid, "side": side.index})
				_bond(b, "fainted")
				var killer := battler(b.last_hit_by)
				if killer != null:
					_award(killer, "knockout")
					_bond(killer, "knockout")
				if side.index == 1:
					_award_xp_for(b)


func _award_xp_for(defeated: Battler) -> void:
	if not setup.award_xp:
		return
	var bonus := float(sides[0].underdog.get("xp_bonus", 0.0))
	var amount := Stats.xp_reward(db.balance, defeated.creature.species_def(db).xp_yield,
		defeated.creature.level, not setup.is_wild, bonus)
	for p in sides[0].battlers:
		if p.participated and p.alive():
			var share := maxi(1, int(amount * Progression.bond_xp_mult(db, p.creature)))
			for ev in Progression.award_xp(db, p.creature, share, p.bid):
				emit(ev)


func _award(b: Battler, happening: String, times := 1) -> void:
	if b == null:
		return
	var award: Dictionary = db.balance.affinity_awards.get(happening, {})
	var aff := Progression.award_affinity(db, b.creature, happening, times)
	if aff == "":
		return
	if not _affinity_log.has(b.bid):
		_affinity_log[b.bid] = {}
	_affinity_log[b.bid][aff] = int(_affinity_log[b.bid].get(aff, 0)) + int(award.points) * times


func _check_end() -> void:
	if _over:
		return
	for side in sides:
		if side.defeated():
			_finish(1 - side.index, "defeat")
			return


func _finish(winner: int, reason: String) -> void:
	_over = true
	_winner = winner
	_end_reason = reason
	if winner != -1:
		for b in sides[winner].battlers:
			if b.participated and not b.captured:
				_bond(b, "battle_won")
	emit({"type": "battle_end", "winner": winner, "reason": reason,
		"captured": _captured.map(func(c): return c.species), "rounds": round_number})


func _end_of_round() -> void:
	# Statuses: run their effects (e.g. Burn damage), then count down.
	for side in sides:
		for b in side.active():
			if b.status() == "":
				continue
			var ctx := EffectContext.new()
			ctx.engine = self
			ctx.source = "status"
			ctx.target_side = b.side
			ctx.targets.append(b)
			run_effects(ctx, db.status(b.status()).effects)
			b.status_turns -= 1
			if b.status_turns <= 0 and b.alive():
				emit({"type": "status_ended", "bid": b.bid, "status": b.status()})
				b.creature.status = ""
	_check_faints()
	_check_end()
	if _over:
		return
	for side in sides:
		for id in side.field.tick():
			emit({"type": "field_removed", "side": side.index, "state": id, "reason": "expired"})
	for side in sides:
		if side.auto_replace:
			while not side.open_slots().is_empty() and not side.bench().is_empty():
				_place(side, side.open_slots()[0], side.bench()[0])
		else:
			var n := pending_replacements(side.index)
			if n > 0:
				emit({"type": "replacement_needed", "side": side.index, "count": n})
	_update_underdog()
	if round_number >= db.balance.round_limit:
		_finish(-1, "round_limit")


func _update_underdog() -> void:
	for side in sides:
		var u := Underdog.compute(db.balance, side.active().size(), sides[1 - side.index].active().size())
		var before := float(side.underdog.get("ratio", 1.0))
		side.underdog = u
		if u.ratio != before:
			emit({"type": "underdog", "side": side.index, "ratio": u.ratio,
				"bonus_actions": u.bonus_actions, "stat_bonus": u.stat_bonus,
				"spread_reduction": u.spread_reduction, "xp_bonus": u.xp_bonus})


func _take_events() -> Array:
	var out := _events
	_events = []
	return out
