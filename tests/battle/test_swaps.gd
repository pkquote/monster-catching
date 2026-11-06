extends GdUnitTestSuite
## Swapping: one action, priority 6 (before items and moves), stages reset on the way out,
## refused swaps, big (12-creature) benches and entry triggers.

var db: Database


func before() -> void:
	var r: RawData = FixtureDB.raw()
	# Raises its own Speed one stage whenever it is placed on the field (a visible, countable entry).
	r.add_entry("passives", {"id": "greeter", "name": "Greeter", "description": "Test entry trigger.",
		"triggers": [{"on": "enter", "effects": [{"op": "stat_stage", "stat": "spd", "stages": 1}]}]})
	var errors: Array = DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _mk(species: String = "blob", passive: String = "") -> CreatureInstance:
	var c: CreatureInstance = FixtureDB.make(db, species, 10, ["hit", "quick_jab"])
	if passive != "":
		c.passive = passive
	return c


func _invalid(events: Array, reason: String) -> Array:
	return FixtureDB.events_of(events, BattleEvents.ACTION_INVALID).filter(
		func(ev: Dictionary) -> bool: return str(ev.reason) == reason)


func _index_of(events: Array, type: String, bid: int) -> int:
	for i: int in events.size():
		if events[i].type == type and int(events[i].get("bid", -1)) == bid:
			return i
	return -1


func _moves_by(events: Array, bid: int) -> Array:
	return FixtureDB.events_of(events, BattleEvents.MOVE_USED).filter(
		func(ev: Dictionary) -> bool: return int(ev.bid) == bid)


func test_swap_takes_the_swappers_action() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank")])
	var lead: Battler = e.sides[0].active()[0]
	var bench: Battler = e.sides[0].bench()[0]
	var foe: Battler = e.sides[1].active()[0]
	var events: Array = e.resolve_round([BattleAction.swap(lead.bid, bench.bid),
		BattleAction.use_move(lead.bid, "hit", foe.bid), BattleAction.use_move(bench.bid, "hit", foe.bid)])
	# One action slot: the swap is taken, the follow-up move is refused, and the creature coming
	# in has no action of its own this round.
	assert_array(FixtureDB.events_of(events, BattleEvents.SWAP_OUT)).has_size(1)
	assert_array(_invalid(events, "no_action_slot")).has_size(2)
	assert_array(_moves_by(events, lead.bid)).is_empty()
	assert_array(_moves_by(events, bench.bid)).is_empty()
	assert_int(foe.hp()).is_equal(foe.creature.max_hp(db))
	# Move first in the list: the move is the action and the swap is refused.
	var e2: BattleEngine = FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank")])
	var lead2: Battler = e2.sides[0].active()[0]
	var bench2: Battler = e2.sides[0].bench()[0]
	var events2: Array = e2.resolve_round([BattleAction.use_move(lead2.bid, "hit", -1),
		BattleAction.swap(lead2.bid, bench2.bid)])
	assert_array(FixtureDB.events_of(events2, BattleEvents.SWAP_OUT)).is_empty()
	assert_array(_moves_by(events2, lead2.bid)).has_size(1)
	assert_object(e2.sides[0].active()[0]).is_same(lead2)


# PIN: pins current engine behaviour; revisit if the design decision changes. The docs only say
# "each action runs if its creature is still on the field"; nothing says who keeps the extra slots.
func test_underdog_swapper_loses_its_remaining_actions_current_behaviour() -> void:
	# 1v3: three action slots for the lead. The swap runs first, and the lead's queued moves are
	# dropped because it is no longer on the field; the newcomer gets none of them. The foes act
	# too, so MOVE_USED is not empty for lack of actions: only side 0's moves are missing.
	var e: BattleEngine = FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank"), _mk("tank"), _mk("tank")], 1, 3)
	var lead: Battler = e.sides[0].active()[0]
	var bench: Battler = e.sides[0].bench()[0]
	var foes: Array[Battler] = e.sides[1].active()
	assert_array(e.actions_needed(0)).has_size(3)
	var chosen: Array = [BattleAction.use_move(lead.bid, "hit", -1),
		BattleAction.swap(lead.bid, bench.bid), BattleAction.use_move(lead.bid, "hit", -1)]
	for foe: Battler in foes:
		chosen.append(BattleAction.use_move(foe.bid, "hit", lead.bid))
	var events: Array = e.resolve_round(chosen)
	assert_array(FixtureDB.events_of(events, BattleEvents.SWAP_OUT)).has_size(1)
	assert_array(_invalid(events, "no_action_slot")).is_empty()
	assert_array(_moves_by(events, lead.bid)).is_empty()
	assert_array(_moves_by(events, bench.bid)).is_empty()
	for foe: Battler in foes:
		assert_array(_moves_by(events, foe.bid)).has_size(1)
	assert_array(FixtureDB.events_of(events, BattleEvents.MOVE_USED)).has_size(3)
	assert_object(e.sides[0].active()[0]).is_same(bench)


func test_swap_resolves_before_priority_moves_and_items() -> void:
	for seed_value: int in range(1, 9):
		# The slow swapper against a fast foe using a priority move aimed at it.
		var e: BattleEngine = FixtureDB.engine(db, [_mk("slow"), _mk("slow"), _mk("tank")],
			[_mk("fast"), _mk("fast")], 2, 2, seed_value, false, {"potion": 1})
		var swapper: Battler = e.sides[0].active()[0]
		var healer: Battler = e.sides[0].active()[1]
		var incoming: Battler = e.sides[0].bench()[0]
		var foes: Array[Battler] = e.sides[1].active()
		healer.creature.hp -= 5
		var events: Array = e.resolve_round([BattleAction.use_item(healer.bid, "potion", healer.bid),
			BattleAction.use_move(foes[0].bid, "quick_jab", swapper.bid),
			BattleAction.swap(swapper.bid, incoming.bid),
			BattleAction.use_move(foes[1].bid, "hit", swapper.bid)])
		var swap_at: int = _index_of(events, BattleEvents.SWAP_OUT, swapper.bid)
		assert_int(swap_at).is_greater_equal(0)
		assert_int(swap_at).is_less(_index_of(events, BattleEvents.ITEM_USED, healer.bid))
		assert_int(swap_at).is_less(_index_of(events, BattleEvents.MOVE_USED, foes[0].bid))
		assert_int(swap_at).is_less(_index_of(events, BattleEvents.MOVE_USED, foes[1].bid))
		# The moves aimed at the swapper land on a standing foe of theirs, never the creature that left.
		assert_int(swapper.hp()).is_equal(swapper.creature.max_hp(db))
		for ev: Dictionary in FixtureDB.events_of(events, BattleEvents.DAMAGE):
			assert_int(int(ev.bid)).is_not_equal(swapper.bid)
	# The documented priorities themselves (Flee 7, Swap 6, Item 5), checked once.
	var p: BattleEngine = FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank")])
	var actor: int = p.sides[0].active()[0].bid
	assert_int(ActionRunner.PRIORITY_SWAP).is_equal(6)
	assert_int(p.actions.priority(BattleAction.swap(actor, p.sides[0].bench()[0].bid))).is_equal(6)
	assert_int(p.actions.priority(BattleAction.use_item(actor, "potion"))).is_equal(5)
	assert_int(p.actions.priority(BattleAction.flee(actor))).is_equal(7)


func test_leaving_the_field_resets_stat_stages() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_mk(), _mk(), _mk()], [_mk("tank"), _mk("tank")], 2, 2)
	var leaving: Battler = e.sides[0].active()[0]
	var staying: Battler = e.sides[0].active()[1]
	var incoming: Battler = e.sides[0].bench()[0]
	for stat: String in ["patk", "pdef", "spd", "acc"]:
		leaving.stages[stat] = 3
		staying.stages[stat] = 2
	leaving.stages["satk"] = -4
	e.resolve_round([BattleAction.swap(leaving.bid, incoming.bid), BattleAction.pass_turn(staying.bid)])
	for stat: String in leaving.stages:
		assert_int(int(leaving.stages[stat])).override_failure_message("leaving " + stat).is_equal(0)
		assert_int(int(incoming.stages[stat])).override_failure_message("incoming " + stat).is_equal(0)
	for stat: String in ["patk", "pdef", "spd", "acc"]:
		assert_int(int(staying.stages[stat])).is_equal(2)
	# Coming back in starts from zero too.
	e.resolve_round([BattleAction.swap(incoming.bid, leaving.bid), BattleAction.pass_turn(staying.bid)])
	assert_object(e.sides[0].slots[0]).is_same(leaving)
	assert_int(int(leaving.stages.patk)).is_equal(0)


func test_bad_swaps_are_refused() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_mk(), _mk(), _mk(), _mk()], [_mk("tank"), _mk("tank"), _mk("tank")], 2, 2)
	var a: Battler = e.sides[0].active()[0]
	var b: Battler = e.sides[0].active()[1]
	var fainted: Battler = e.sides[0].battlers[2]
	var healthy: Battler = e.sides[0].battlers[3]
	fainted.creature.hp = 0
	var foe_bench: Battler = e.sides[1].bench()[0]
	for bad: int in [fainted.bid, b.bid, a.bid, foe_bench.bid, 999]:
		var events: Array = e.resolve_round([BattleAction.swap(a.bid, bad), BattleAction.pass_turn(b.bid)])
		assert_array(_invalid(events, "bad_swap")).override_failure_message("swap in %d" % bad).has_size(1)
		assert_array(FixtureDB.events_of(events, BattleEvents.SWAP_OUT)).is_empty()
		assert_array(FixtureDB.events_of(events, BattleEvents.SEND_OUT)).is_empty()
		assert_object(e.sides[0].slots[0]).is_same(a)
		assert_object(e.sides[0].slots[1]).is_same(b)
	assert_bool(fainted.active).is_false()
	# The one healthy bench creature is still accepted afterwards.
	var ok_events: Array = e.resolve_round([BattleAction.swap(a.bid, healthy.bid), BattleAction.pass_turn(b.bid)])
	assert_array(_invalid(ok_events, "bad_swap")).is_empty()
	assert_object(e.sides[0].slots[0]).is_same(healthy)
	# The same bench creature twice in one round: the first swap wins, the second is refused.
	for seed_value: int in range(1, 6):
		var e2: BattleEngine = FixtureDB.engine(db, [_mk(), _mk(), _mk()], [_mk("tank"), _mk("tank")], 2, 2, seed_value)
		var x: Battler = e2.sides[0].active()[0]
		var y: Battler = e2.sides[0].active()[1]
		var spare: Battler = e2.sides[0].bench()[0]
		var events2: Array = e2.resolve_round([BattleAction.swap(x.bid, spare.bid), BattleAction.swap(y.bid, spare.bid)])
		assert_array(FixtureDB.events_of(events2, BattleEvents.SWAP_OUT)).has_size(1)
		assert_array(_invalid(events2, "bad_swap")).has_size(1)
		var on_field: Array = e2.sides[0].active().map(func(t: Battler) -> int: return t.bid)
		assert_array(on_field).has_size(2)
		assert_array(on_field.filter(func(bid: int) -> bool: return bid == spare.bid)).has_size(1)
		assert_int(e2.sides[0].bench().size()).is_equal(1)


func test_twelve_creature_party_swaps_every_bench_member_in_once() -> void:
	# 1v1: the lead swaps to each of the 11 benched creatures in turn.
	var party: Array = []
	for i: int in 12:
		party.append(_mk())
	var e: BattleEngine = FixtureDB.engine(db, party, [_mk("tank")])
	var side: BattleSide = e.sides[0]
	assert_int(side.battlers.size()).is_equal(12)
	var bench_bids: Array = side.bench().map(func(t: Battler) -> int: return t.bid)
	assert_array(bench_bids).has_size(11)
	var sent: Dictionary = {}
	for bid: int in bench_bids:
		var current: Battler = side.active()[0]
		var events: Array = e.resolve_round([BattleAction.swap(current.bid, bid)])
		assert_array(_invalid(events, "bad_swap")).override_failure_message("swap in %d" % bid).is_empty()
		assert_array(FixtureDB.events_of(events, BattleEvents.SWAP_OUT)).has_size(1)
		for ev: Dictionary in FixtureDB.events_of(events, BattleEvents.SEND_OUT):
			sent[int(ev.bid)] = int(sent.get(int(ev.bid), 0)) + 1
		assert_int(side.active()[0].bid).is_equal(bid)
	for bid: int in bench_bids:
		assert_int(int(sent.get(bid, 0))).override_failure_message("bid %d" % bid).is_equal(1)
	assert_int(sent.size()).is_equal(11)

	# 3v3 with a bench of 9: rotate the slots through every benched creature.
	var big: Array = []
	for i: int in 12:
		big.append(_mk())
	var e3: BattleEngine = FixtureDB.engine(db, big, [_mk("tank"), _mk("tank"), _mk("tank")], 3, 3)
	var side3: BattleSide = e3.sides[0]
	var bench3: Array = side3.bench().map(func(t: Battler) -> int: return t.bid)
	assert_array(bench3).has_size(9)
	var sent3: Dictionary = {}
	for i: int in bench3.size():
		var slot: int = i % 3
		var out_bid: int = (side3.slots[slot] as Battler).bid
		var events3: Array = e3.resolve_round([BattleAction.swap(out_bid, int(bench3[i]))])
		assert_array(_invalid(events3, "bad_swap")).is_empty()
		for ev: Dictionary in FixtureDB.events_of(events3, BattleEvents.SEND_OUT):
			sent3[int(ev.bid)] = int(sent3.get(int(ev.bid), 0)) + 1
			assert_int(int(ev.slot)).is_equal(slot)
		assert_int((side3.slots[slot] as Battler).bid).is_equal(int(bench3[i]))
		assert_int(side3.active().size()).is_equal(3)
	for bid: int in bench3:
		assert_int(int(sent3.get(bid, 0))).is_equal(1)


func _greets(events: Array, bid: int) -> int:
	return FixtureDB.events_of(events, BattleEvents.PASSIVE_TRIGGERED).filter(
		func(ev: Dictionary) -> bool: return int(ev.bid) == bid).size()


func test_swap_in_fires_enter_once() -> void:
	var setup: BattleSetup = BattleSetup.new()
	setup.add_side([_mk("blob", "greeter"), _mk("blob", "greeter"), _mk("blob", "greeter")], 1)
	setup.add_side([_mk("tank")], 1)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var e: BattleEngine = BattleEngine.new(db, rng, setup)
	var start_events: Array = e.start()
	var lead: Battler = e.sides[0].active()[0]
	var second: Battler = e.sides[0].battlers[1]
	var third: Battler = e.sides[0].battlers[2]
	assert_int(_greets(start_events, lead.bid)).is_equal(1)
	assert_int(_greets(start_events, second.bid)).is_equal(0)
	assert_int(int(lead.stages.spd)).is_equal(1)

	var events: Array = e.resolve_round([BattleAction.swap(lead.bid, second.bid)])
	assert_int(_greets(events, second.bid)).is_equal(1)
	assert_int(_greets(events, lead.bid)).is_equal(0)
	var ups: Array = FixtureDB.events_of(events, BattleEvents.STAT_STAGE).filter(
		func(ev: Dictionary) -> bool: return int(ev.bid) == second.bid)
	assert_array(ups).has_size(1)
	assert_int(int(second.stages.spd)).is_equal(1)
	assert_int(int(lead.stages.spd)).is_equal(0)

	# Back in again: fires once more (stages were reset on the way out, so +1 again).
	events = e.resolve_round([BattleAction.swap(second.bid, lead.bid)])
	assert_int(_greets(events, lead.bid)).is_equal(1)
	assert_int(int(lead.stages.spd)).is_equal(1)

	# A replacement after a faint is an entry too: once.
	lead.creature.hp = 1
	var foe: Battler = e.sides[1].active()[0]
	e.resolve_round([BattleAction.pass_turn(lead.bid), BattleAction.use_move(foe.bid, "hit", lead.bid)])
	assert_bool(lead.alive()).is_false()
	var replaced: Array = e.replace(0, third.bid)
	assert_int(_greets(replaced, third.bid)).is_equal(1)
	assert_int(int(third.stages.spd)).is_equal(1)
