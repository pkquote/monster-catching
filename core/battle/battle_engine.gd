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
##   engine.commit(0)                       # write the player's creatures back
##
## The battle runs on copies of the creatures in the setup; nothing the sides
## brought changes until commit(). AI-controlled sides choose their own actions
## inside resolve_round. Every outcome is reported as an event Dictionary
## { type: BattleEvents.*, ... }; see documentation/battle-engine.md.
##
## This class is the public face: the screen, the AI and effect ops call it.
## The work is split across four parts:
##   actions     (ActionRunner)  turn order and running moves, items, swaps, Rest, fleeing
##   field_rules (FieldRules)    field states and reactions
##   rewards     (BattleRewards) XP, Bond and Affinity
##   passive_rules (PassiveRules) creature passives: always-on effects and auras

var db: Database
var rng: RandomNumberGenerator
var setup: BattleSetup
var sides: Array[BattleSide] = []
var round_number := 0

var actions: ActionRunner
var field_rules: FieldRules
var rewards: BattleRewards
var passive_rules: PassiveRules

var _battlers: Dictionary = {}  # bid -> Battler
var _events: Array = []
var _over := false
var _winner := -1
var _end_reason := ""
var _captured: Array[CreatureInstance] = []
var _starting := false  # placing the opening line-ups (entry triggers wait until all are placed)


func _init(p_db: Database, p_rng: RandomNumberGenerator, p_setup: BattleSetup) -> void:
	db = p_db
	rng = p_rng
	setup = p_setup
	actions = ActionRunner.new(self)
	field_rules = FieldRules.new(self)
	rewards = BattleRewards.new(self)
	passive_rules = PassiveRules.new(self)
	var next_bid := 0
	for i in setup.sides.size():
		var sd := setup.sides[i]
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
			if b.creature.status != "":
				b.status_turns = db.status(b.creature.status).turns
			side.battlers.append(b)
			_battlers[b.bid] = b
		side.slots.resize(clampi(sd.field_count, 1, side.max_active))
		sides.append(side)


# --- Public API ---------------------------------------------------------------

func start() -> Array:
	_events = []
	Log.info(Log.BATTLE, "Battle started", {"wild": setup.is_wild, "tamer": setup.tamer_id,
		"format": "%dv%d" % [sides[0].slots.size(), sides[1].slots.size()],
		"party": sides[0].battlers.map(func(b: Battler): return "%s L%d" % [b.creature.species, b.creature.level]),
		"foes": sides[1].battlers.map(func(b: Battler): return "%s L%d" % [b.creature.species, b.creature.level])})
	emit({"type": BattleEvents.BATTLE_START, "wild": setup.is_wild, "tamer": setup.tamer_id,
		"slots": [sides[0].slots.size(), sides[1].slots.size()]})
	_starting = true
	for side in sides:
		for slot in side.slots.size():
			var bench := side.bench()
			if bench.is_empty():
				break
			place(side, slot, bench[0])
	_starting = false
	# Entry triggers once both sides are out, fastest first.
	for b in _by_speed(sides[0].active() + sides[1].active()):
		passive_rules.fire(b, "enter")
	check_faints()
	_update_underdog()
	check_end()
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
		if m != null and passive_rules.move_cost(b, m) <= b.energy():
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
		"two_enemies":
			for t in sides[1 - b.side].active():
				out.append(t.bid)
		_:
			out.append(-1)
	return out


## Valid second picks for a "two_enemies" move once `first` is chosen: the other
## standing active foes. Empty for any other move.
func second_targets_for(bid: int, move_id: String, first: int) -> Array[int]:
	var out: Array[int] = []
	var b := battler(bid)
	var m := db.move(move_id)
	if b == null or m == null or m.target != "two_enemies":
		return out
	for t in sides[1 - b.side].active():
		if t.bid != first:
			out.append(t.bid)
	return out


## Runs one round. `chosen` covers the caller-controlled sides; AI sides choose their own.
func resolve_round(chosen: Array) -> Array:
	_events = []
	if _over:
		return _events
	round_number += 1
	emit({"type": BattleEvents.ROUND_START, "round": round_number})
	var all: Array = chosen.duplicate()
	for side in sides:
		if side.is_ai():
			all.append_array(BattleAI.choose_all(self, side.index))

	# Each battler gets as many actions as actions_needed() gave it; extras are dropped.
	var allowed := {}
	for side in sides:
		for bid in actions_needed(side.index):
			allowed[bid] = int(allowed.get(bid, 0)) + 1
	var valid: Array = []
	for a: BattleAction in all:
		if int(allowed.get(a.actor, 0)) <= 0:
			emit({"type": BattleEvents.ACTION_INVALID, "bid": a.actor, "reason": "no_action_slot"})
			continue
		allowed[a.actor] -= 1
		valid.append(a)

	if Log.enabled(Log.BATTLE, Log.Level.DEBUG):
		Log.debug(Log.BATTLE, "Round %d" % round_number, {"actions": valid.map(_describe_action)})
	for a in actions.order(valid):
		if _over:
			break
		actions.execute(a)
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
		emit({"type": BattleEvents.ACTION_INVALID, "bid": bid, "reason": "bad_replacement"})
		return _take_events()
	place(side, open[0], b)
	# Its entry trigger may have knocked creatures out (e.g. through a reaction). Underdog is refreshed before the
	# battle can end, so BATTLE_END stays the last event; a foe on an auto-replace side that was knocked out is
	# refilled now, not at the end of the next round.
	check_faints()
	_update_underdog()
	check_end()
	if not _over:
		_refill_auto_replace()
		if not _over:
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
		"affinity": rewards.affinity_log.duplicate(true),
	}


## Writes a side's battle copies back into the creatures its setup brought
## (HP, energy, status, XP, level, moves, Bond, Affinity). Captured creatures are
## skipped: they now belong to the catcher (result().captured holds them).
## Call once, when the battle is over. A battle that's abandoned is simply never committed.
func commit(side_index: int) -> void:
	for b in sides[side_index].battlers:
		if not b.captured:
			b.source.copy_from(b.creature)


func battler(bid: int) -> Battler:
	return _battlers.get(bid)


func all_battlers() -> Array:
	return _battlers.values()


# --- Queries used by formulas and ops -------------------------------------------

func status_passives(b: Battler) -> Array:
	return [] if b.status() == "" else db.status(b.status()).effects


## Every always-on effect on `b`: its side's field states (minus any it shelters from),
## its status, and creature passives (its own active passive and allied auras; see
## PassiveRules.effects_for).
func passives(b: Battler) -> Array:
	return field_rules.passives_for(b) + status_passives(b) + passive_rules.effects_for(b)


## Creature targets for a move/item target key. Invalid choices are re-targeted
## at random (when `allow_random`) so a move aimed at a fainted foe still lands.
func resolve_targets(user: Battler, key: String, chosen: int, second := -1, allow_random := true) -> Array[Battler]:
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
		"two_enemies":
			# Two distinct standing foes: keep valid picks, fill gaps from the rest.
			for pick in [chosen, second]:
				var c := battler(pick)
				if c != null and c.side == opp.index and c.alive() and c.active and not out.has(c):
					out.append(c)
			if allow_random:
				var pool: Array[Battler] = []
				for t in opp.active():
					if not out.has(t):
						pool.append(t)
				while out.size() < 2 and not pool.is_empty():
					out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		"one_ally":
			var c := battler(chosen)
			# Items may target benched allies too.
			if c != null and c.side == own.index and c.alive():
				out.append(c)
			elif allow_random and not own.active().is_empty():
				# An illegal pick (fainted, missing, a foe) becomes a random standing ally,
				# the user included, like the foe targets.
				var pool := own.active()
				out.append(pool[rng.randi_range(0, pool.size() - 1)])
			else:
				out.append(user)
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

## PASSIVE_TRIGGERED for `b`'s active passive (it visibly acted: a trigger, a block, an absorb).
## With `item` (a held item id, PassiveRules.last_item) the event names that item instead:
## `passive` is "" and `item` is set.
func emit_passive(b: Battler, item := "") -> void:
	if item != "":
		emit({"type": BattleEvents.PASSIVE_TRIGGERED, "bid": b.bid, "passive": "", "item": item})
		return
	emit({"type": BattleEvents.PASSIVE_TRIGGERED, "bid": b.bid, "passive": Passives.active_id(b.creature)})


func emit(event: Dictionary) -> void:
	if OS.is_debug_build() and not BattleEvents.ALL.has(event.get("type")):
		Log.error(Log.BATTLE, "Unknown battle event type; add it to BattleEvents", {"type": event.get("type")})
	if Log.enabled(Log.BATTLE, Log.Level.TRACE):
		Log.trace(Log.BATTLE, "Event " + str(event.get("type")), event)
	_events.append(event)


## "Tidepup#0 move riptide -> 3" for the round log.
func _describe_action(a: BattleAction) -> String:
	var who := battler(a.actor)
	var text := "%s#%d %s" % [who.creature.species if who != null else "?", a.actor, a.kind]
	if a.move != "":
		text += " " + a.move
	if a.item != "":
		text += " " + a.item
	if a.target >= 0:
		text += " -> %d" % a.target
	if a.swap_in >= 0:
		text += " swap_in %d" % a.swap_in
	return text


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
			if t.alive() and not (t in ctx.absorbed and e.op != "damage"):
				op.apply(ctx, e, t)


## `contact` is true for physical moves (for hit triggers that need it).
## Returns true when the target's passive absorbed the damage (it healed instead).
func deal_damage(target: Battler, amount: int, attacker: Battler, type: String, type_mult := 1.0,
		contact := false) -> bool:
	# absorb_type: the damage heals instead, and doesn't count as a hit.
	var absorb := passive_rules.absorbs(target, type) if type != "" else 0.0
	if absorb > 0.0:
		emit_passive(target, passive_rules.last_item)
		heal(target, maxi(1, roundi(target.creature.max_hp(db) * absorb)), null)
		return true
	var dealt := mini(amount, target.hp())
	# Resolve: once per battle, a knockout blow from a foe may leave 1 HP.
	if dealt >= target.hp() and target.hp() > 1 and not target.endured and attacker != null \
			and attacker.side != target.side and rng.randf() < BattleMath.endure_chance(self, target, attacker):
		target.endured = true
		dealt = target.hp() - 1
		emit({"type": BattleEvents.ENDURED, "bid": target.bid})
	target.creature.hp -= dealt
	emit({"type": BattleEvents.DAMAGE, "bid": target.bid, "amount": dealt, "hp": target.hp(),
		"max_hp": target.creature.max_hp(db), "by": attacker.bid if attacker != null else -1,
		"damage_type": type, "effectiveness": type_mult})
	passive_rules.note_damage(target)
	if attacker != null and attacker.side != target.side and dealt > 0:
		target.last_hit_by = attacker.bid
		_award_hit(attacker, "hit_dealt")
		if target.hp() > 0:
			_award_hit(target, "hit_survived")
			passive_rules.fire(target, "hit", attacker, contact)
	return false


## While a multi-hit move runs, Affinity from its hits is earned once per move use, not per hit.
var _hit_awards_once := false
var _hit_awarded := {}


func begin_multi_hit() -> void:
	_hit_awards_once = true
	_hit_awarded.clear()


func end_multi_hit() -> void:
	_hit_awards_once = false
	_hit_awarded.clear()


func _award_hit(b: Battler, happening: String) -> void:
	if _hit_awards_once:
		var key := "%s:%d" % [happening, b.bid]
		if _hit_awarded.has(key):
			return
		_hit_awarded[key] = true
	rewards.award(b, happening)


## The next standing active foe of `user` after `fallen`'s slot, wrapping around the side; null if none.
func next_foe_after(user: Battler, fallen: Battler) -> Battler:
	var opp := sides[1 - user.side]
	var n := opp.slots.size()
	var start := opp.slot_of(fallen)
	for i in range(1, n + 1):
		var b: Battler = opp.slots[(start + i) % n]
		if b != null and b.alive() and b.active:
			return b
	return null


## Creatures (by bid) an item's heal or cure helped during the current item use. The item's
## runner awards each one `healed_item` Bond once, however many of its effects landed.
var item_bond_pending := {}


func heal(target: Battler, amount: int, user: Battler, from_item := false) -> void:
	var max_hp := target.creature.max_hp(db)
	var healed := mini(amount, max_hp - target.hp())
	target.creature.hp += healed
	emit({"type": BattleEvents.HEAL, "bid": target.bid, "amount": healed, "hp": target.hp(), "max_hp": max_hp})
	if user != null and healed > 0:
		rewards.award(user, "heal")
	if from_item and healed > 0:
		item_bond_pending[target.bid] = true


func restore_energy(target: Battler, amount: int) -> void:
	var max_e := target.creature.max_energy(db)
	var gained := mini(amount, max_e - target.energy())
	target.creature.energy += gained
	emit({"type": BattleEvents.ENERGY, "bid": target.bid, "change": gained, "energy": target.energy(),
		"max_energy": max_e})


func inflict_status(target: Battler, status_id: String, user: Battler) -> void:
	if target.status() != "":
		emit({"type": BattleEvents.STATUS_FAILED, "bid": target.bid, "status": status_id, "has": target.status()})
		return
	var immune := passive_rules.status_blocker(target, status_id)
	if immune != null:
		emit_passive(immune, passive_rules.last_item)
		return
	if user != target and rng.randf() < BattleMath.resist_chance(self, target, user):
		emit({"type": BattleEvents.RESISTED, "bid": target.bid, "status": status_id})
		return
	target.creature.status = status_id
	target.status_turns = db.status(status_id).turns
	emit({"type": BattleEvents.STATUS_APPLIED, "bid": target.bid, "status": status_id, "turns": target.status_turns})
	if user != null and user.side != target.side:
		rewards.award(user, "status_inflicted")
	passive_rules.fire(target, "status", user)


## Clears `target`'s status (only `status_id` when it is not ""). Does nothing, silently, when
## the target has fallen or has no matching status. Returns whether it cured.
func cure_status(target: Battler, status_id: String, from_item := false) -> bool:
	var current := target.status()
	if not target.alive() or current == "" or (status_id != "" and status_id != current):
		return false
	target.creature.status = ""
	target.status_turns = 0
	emit({"type": BattleEvents.STATUS_ENDED, "bid": target.bid, "status": current, "cured": true})
	if from_item:
		item_bond_pending[target.bid] = true
	return true


func shift_stage(target: Battler, stat: String, amount: int, user: Battler) -> void:
	var guard := passive_rules.stage_guard(target, stat, user) if amount < 0 else null
	if guard != null:
		emit_passive(guard, passive_rules.last_item)
		return
	if amount < 0 and user != null and user.side != target.side \
			and rng.randf() < BattleMath.resist_chance(self, target, user):
		emit({"type": BattleEvents.RESISTED, "bid": target.bid, "stat": stat})
		return
	var moved := target.shift_stage(stat, amount)
	emit({"type": BattleEvents.STAT_STAGE, "bid": target.bid, "stat": stat, "change": moved,
		"stage": target.stages[stat]})
	if moved < 0 and user != null and user.side != target.side:
		rewards.award(user, "stat_lowered", -moved)


## Applies a field state to a side (see FieldRules.apply).
func apply_field_state(side_index: int, state_id: String, stacks: int, turns: int,
		user: Battler, allow_reaction := true) -> void:
	field_rules.apply(side_index, state_id, stacks, turns, user, allow_reaction)


func remove_field_state(side_index: int, state_id: String, reason: String) -> void:
	field_rules.remove(side_index, state_id, reason)


func attempt_capture(user: Battler, target: Battler, item: ItemDef, e: Dictionary) -> void:
	if not sides[target.side].is_wild:
		emit({"type": BattleEvents.CAPTURE_FAILED, "bid": user.bid, "target": target.bid, "reason": "not_wild"})
		return
	var p := BattleMath.capture_chance(self, target, e)
	var success := rng.randf() < p
	emit({"type": BattleEvents.CAPTURE_ATTEMPT, "bid": user.bid, "target": target.bid,
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
	emit({"type": BattleEvents.CAPTURED, "bid": target.bid, "species": target.creature.species})


# --- Shared by the parts ----------------------------------------------------------

func place(side: BattleSide, slot: int, b: Battler) -> void:
	side.slots[slot] = b
	b.active = true
	b.participated = true
	b.acted = _starting
	emit({"type": BattleEvents.SEND_OUT, "side": side.index, "slot": slot, "bid": b.bid,
		"species": b.creature.species, "level": b.creature.level,
		"hp": b.hp(), "max_hp": b.creature.max_hp(db),
		"energy": b.energy(), "max_energy": b.creature.max_energy(db)})
	rewards.check_overwork(b)
	if not _starting:
		passive_rules.fire(b, "enter")


## Faints, then their faint and knockout triggers, unless the faints decided the battle.
## Repeats while those triggers knock more creatures out.
func check_faints() -> void:
	while true:
		var downed: Array[Battler] = []
		for side in sides:
			for b in side.battlers:
				if b.active and b.creature.hp <= 0 and not b.fainted:
					b.fainted = true
					b.active = false
					emit({"type": BattleEvents.FAINT, "bid": b.bid, "side": side.index})
					rewards.on_faint(b)
					downed.append(b)
		if downed.is_empty() or sides.any(func(s: BattleSide): return s.defeated()):
			return
		for b in downed:
			passive_rules.on_faint(b, battler(b.last_hit_by))


func check_end() -> void:
	if _over:
		return
	for side in sides:
		if side.defeated():
			finish(1 - side.index, "defeat")
			return


func finish(winner: int, reason: String) -> void:
	_over = true
	_winner = winner
	_end_reason = reason
	Log.info(Log.BATTLE, "Battle over", {"winner": winner, "reason": reason, "rounds": round_number,
		"captured": _captured.map(func(c): return c.species)})
	if winner != -1:
		rewards.on_win(winner)
	emit({"type": BattleEvents.BATTLE_END, "winner": winner, "reason": reason,
		"captured": _captured.map(func(c): return c.species), "rounds": round_number})


# --- Internals ---------------------------------------------------------------------

## Targets for an effect with its own "target" key. Reactions resolve relative to
## the side the reaction fired on; everything else relative to the user.
func _effect_targets(ctx: EffectContext, key: String) -> Array[Battler]:
	if key == "attacker":
		var hitter: Array[Battler] = []
		if ctx.attacker != null:
			hitter.append(ctx.attacker)
		return hitter
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
				emit({"type": BattleEvents.STATUS_ENDED, "bid": b.bid, "status": b.status()})
				b.creature.status = ""
	check_faints()
	check_end()
	if _over:
		return
	# Passive round_end triggers, before field states count down.
	for b in _by_speed(sides[0].active() + sides[1].active()):
		passive_rules.fire(b, "round_end")
	check_faints()
	check_end()
	if _over:
		return
	field_rules.tick_all()
	_refill_auto_replace()
	if _over:
		return
	for side in sides:
		if not side.auto_replace:
			var n := pending_replacements(side.index)
			if n > 0:
				emit({"type": BattleEvents.REPLACEMENT_NEEDED, "side": side.index, "count": n})
	_update_underdog()
	if round_number >= db.balance.round_limit:
		finish(-1, "round_limit")


## Refills the slots of auto-replace sides from their benches. An entry trigger can knock creatures out on either
## side, so faints are checked after each placement and refilling repeats until nothing changes or the battle ends.
func _refill_auto_replace() -> void:
	var refilled := true
	while refilled:
		refilled = false
		for side in sides:
			if not side.auto_replace:
				continue
			while not side.open_slots().is_empty() and not side.bench().is_empty():
				place(side, side.open_slots()[0], side.bench()[0])
				refilled = true
				check_faints()
				check_end()
				if _over:
					return


func _update_underdog() -> void:
	for side in sides:
		var u := Underdog.compute(db.balance, side.active().size(), sides[1 - side.index].active().size())
		var before := float(side.underdog.get("ratio", 1.0))
		side.underdog = u
		if u.ratio != before:
			emit({"type": BattleEvents.UNDERDOG, "side": side.index, "ratio": u.ratio,
				"bonus_actions": u.bonus_actions, "stat_bonus": u.stat_bonus,
				"spread_reduction": u.spread_reduction, "xp_bonus": u.xp_bonus})


## Fastest first (effective Speed), ties by bid.
func _by_speed(list: Array) -> Array[Battler]:
	var keyed: Array = list.map(func(b: Battler): return [BattleMath.effective_stat(self, b, "spd"), b])
	keyed.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1].bid < y[1].bid))
	var out: Array[Battler] = []
	for k in keyed:
		out.append(k[1])
	return out


func _take_events() -> Array:
	var out := _events
	_events = []
	return out


## Public hooks for callers that settle the engine outside resolve_round() (tests, scripted setups).
## Returns and clears the events queued so far.
func drain_events() -> Array:
	return _take_events()


## Recalculates Underdog for both sides, as the end of a round does.
func refresh_underdog() -> void:
	_update_underdog()
