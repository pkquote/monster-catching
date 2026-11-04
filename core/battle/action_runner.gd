class_name ActionRunner
extends BattlePart
## Turn order and running each action: moves (with energy, statuses that skip
## turns and Bond misbehaviour), items, swaps, Rest and fleeing.

const PRIORITY_FLEE := 7
const PRIORITY_SWAP := 6
const PRIORITY_ITEM := 5

const CREATURE_TARGETS := ["self", "one_ally", "one_enemy", "all_allies", "all_enemies", "all"]


## Sorts this round's actions: priority, then effective Speed, then a random tie-break.
func order(actions: Array) -> Array[BattleAction]:
	var e := engine
	var queue: Array = []
	for a: BattleAction in actions:
		queue.append({
			"action": a,
			"priority": priority(a),
			"speed": BattleMath.effective_stat(e, e.battler(a.actor), "spd"),
			"tie": e.rng.randf(),
		})
	queue.sort_custom(func(x, y):
		if x.priority != y.priority:
			return x.priority > y.priority
		if x.speed != y.speed:
			return x.speed > y.speed
		return x.tie > y.tie)
	var out: Array[BattleAction] = []
	for q in queue:
		out.append(q.action)
	return out


func priority(a: BattleAction) -> int:
	match a.kind:
		"flee": return PRIORITY_FLEE
		"swap": return PRIORITY_SWAP
		"item": return PRIORITY_ITEM
		"move":
			var m := engine.db.move(a.move)
			return m.priority if m != null else 0
	return 0


## Runs one action, then checks for faints and the end of the battle.
func execute(a: BattleAction) -> void:
	var e := engine
	var b := e.battler(a.actor)
	if b == null or not b.alive() or not b.active:
		return
	match a.kind:
		"pass":
			e.emit({"type": BattleEvents.PASS, "bid": b.bid})
		"flee":
			_flee(b)
		"swap":
			_swap(b, a.swap_in)
		"item":
			_item(b, a)
		"rest":
			e.rewards.check_overwork(b)
			_rest(b)
		"move":
			e.rewards.check_overwork(b)
			if not _skips_action(b) and not _bond_misbehaves(b, a):
				_move(b, a)
		_:
			e.emit({"type": BattleEvents.ACTION_INVALID, "bid": b.bid, "reason": "unknown_kind"})
	e.check_faints()
	e.check_end()


func _skips_action(b: Battler) -> bool:
	var e := engine
	for p in e.status_passives(b):
		if p.op == "skip_chance" and e.rng.randi_range(1, 100) <= int(p.chance):
			e.emit({"type": BattleEvents.ACTION_SKIPPED, "bid": b.bid, "status": b.status()})
			return true
	return false


func _move(b: Battler, a: BattleAction) -> void:
	var e := engine
	var db := e.db
	var m := db.move(a.move)
	if m == null or not (b.creature.moves.has(a.move) or a.move == e.fallback_move()):
		e.emit({"type": BattleEvents.ACTION_INVALID, "bid": b.bid, "reason": "unknown_move", "move": a.move})
		return
	if m.cost > b.energy():
		e.emit({"type": BattleEvents.ACTION_INVALID, "bid": b.bid, "reason": "no_energy", "move": a.move})
		return
	if m.cost > 0:
		b.creature.energy -= m.cost
		e.emit({"type": BattleEvents.ENERGY, "bid": b.bid, "change": -m.cost, "energy": b.energy(),
			"max_energy": b.creature.max_energy(db)})
	var ctx := EffectContext.new()
	ctx.engine = e
	ctx.user = b
	ctx.source = "move"
	ctx.move = m
	match m.target:
		"own_side":
			ctx.target_side = b.side
		"enemy_side":
			ctx.target_side = 1 - b.side
	var targets := e.resolve_targets(b, m.target, a.target)
	e.emit({"type": BattleEvents.MOVE_USED, "bid": b.bid, "move": m.id,
		"targets": targets.map(func(t): return t.bid), "side": ctx.target_side})
	if m.target in CREATURE_TARGETS:
		if targets.is_empty():
			e.emit({"type": BattleEvents.NO_TARGET, "bid": b.bid})
			return
		ctx.spread = targets.size() > 1
		for t in targets:
			if t.side == b.side or BattleMath.rolls_hit(e, b, m):
				ctx.targets.append(t)
			else:
				e.emit({"type": BattleEvents.MISS, "bid": b.bid, "target": t.bid})
		if ctx.targets.is_empty():
			return
	e.run_effects(ctx, m.effects)
	e.field_rules.finish_consume(ctx)


func _rest(b: Battler) -> void:
	var e := engine
	e.emit({"type": BattleEvents.REST, "bid": b.bid})
	e.restore_energy(b, maxi(1, roundi(b.creature.max_energy(e.db) * float(e.db.balance.energy_cfg.rest_fraction))))


## Negative Bond: may lash out (Scrap on itself or an ally) or disobey (random other
## usable move, or loafing around). Returns true if the ordered move must not run.
func _bond_misbehaves(b: Battler, a: BattleAction) -> bool:
	var e := engine
	if e.rng.randf() < Progression.lash_out_chance(e.db, b.creature):
		var pool: Array[Battler] = e.sides[b.side].active()
		var victim: Battler = pool[e.rng.randi_range(0, pool.size() - 1)]
		e.emit({"type": BattleEvents.LASHED_OUT, "bid": b.bid, "target": victim.bid})
		var ctx := EffectContext.new()
		ctx.engine = e
		ctx.user = b
		ctx.source = "move"
		ctx.move = e.db.move(e.fallback_move())
		ctx.targets.append(victim)
		e.run_effects(ctx, ctx.move.effects)
		return true
	if e.rng.randf() < Progression.disobey_chance(e.db, b.creature):
		var options := Array(e.usable_moves(b.bid)).filter(func(mid): return mid != a.move)
		var pick := e.rng.randi_range(0, options.size())  # == size -> loaf
		if pick >= options.size():
			e.emit({"type": BattleEvents.DISOBEYED, "bid": b.bid, "ordered": a.move, "did": ""})
			return true
		e.emit({"type": BattleEvents.DISOBEYED, "bid": b.bid, "ordered": a.move, "did": options[pick]})
		_move(b, BattleAction.use_move(b.bid, options[pick]))
		return true
	return false


func _item(b: Battler, a: BattleAction) -> void:
	var e := engine
	var side := e.sides[b.side]
	var it := e.db.item(a.item)
	if it == null or int(side.items.get(a.item, 0)) <= 0:
		e.emit({"type": BattleEvents.ACTION_INVALID, "bid": b.bid, "reason": "no_item", "item": a.item})
		return
	if it.category == "capture" and not e.setup.is_wild:
		e.emit({"type": BattleEvents.ACTION_INVALID, "bid": b.bid, "reason": "not_wild", "item": a.item})
		return
	side.items[a.item] = int(side.items[a.item]) - 1
	var ctx := EffectContext.new()
	ctx.engine = e
	ctx.user = b
	ctx.source = "item"
	ctx.item = it
	ctx.targets = e.resolve_targets(b, it.target, a.target)
	e.emit({"type": BattleEvents.ITEM_USED, "bid": b.bid, "item": it.id,
		"targets": ctx.targets.map(func(t): return t.bid), "left": side.items[a.item]})
	e.run_effects(ctx, it.effects)


func _swap(b: Battler, bench_bid: int) -> void:
	var e := engine
	var side := e.sides[b.side]
	var incoming := e.battler(bench_bid)
	if incoming == null or incoming.side != b.side or not incoming.alive() or incoming.active:
		e.emit({"type": BattleEvents.ACTION_INVALID, "bid": b.bid, "reason": "bad_swap"})
		return
	var slot := side.slot_of(b)
	b.active = false
	b.reset_stages()
	e.emit({"type": BattleEvents.SWAP_OUT, "bid": b.bid, "side": b.side, "slot": slot})
	e.place(side, slot, incoming)


func _flee(b: Battler) -> void:
	var e := engine
	if not e.setup.is_wild or b.side != 0:
		e.emit({"type": BattleEvents.ACTION_INVALID, "bid": b.bid, "reason": "cannot_flee"})
		return
	e.emit({"type": BattleEvents.FLED, "bid": b.bid})
	e.finish(-1, "fled")
