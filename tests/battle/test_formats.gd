extends GdUnitTestSuite
## Multi-creature formats (1v1 up to 3v3) with benches of 0, 3 and 9: the opening line-up,
## refilling empty slots after faints, no creature on the field twice, and every battle finishing.
##
## Invariants are collected as text in a `problems` list and asserted empty once per case, so a
## failure names the format, bench, seed and round.

const FORMATS: Array = [[1, 1], [1, 2], [1, 3], [2, 2], [2, 3], [3, 3]]
const BENCHES: Array = [0, 3, 9]
const SEEDS: Array = [1, 2, 3, 4, 5]

var db: Database


func before() -> void:
	db = FixtureDB.build()


## Both sides test-controlled unless `ai` is set (then both are AI sides, which refill themselves).
func _unstarted(party0: Array, party1: Array, field0: int, field1: int, seed_value: int,
		ai: String = "") -> BattleEngine:
	var setup: BattleSetup = BattleSetup.new()
	var max_active: int = maxi(field0, field1)
	setup.add_side(party0, max_active, field0, {}, ai, ai != "")
	setup.add_side(party1, max_active, field1, {}, ai, ai != "")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return BattleEngine.new(db, rng, setup)


## Side 0 brings level-20 blobs and side 1 level-10 blobs, so most battles are decided by a
## defeat well inside the round limit.
func _format_engine(field0: int, field1: int, bench: int, seed_value: int, ai: String = "") -> BattleEngine:
	return _unstarted(FixtureDB.team(db, field0 + bench, "blob", ["hit"], 20),
		FixtureDB.team(db, field1 + bench, "blob", ["hit"], 10), field0, field1, seed_value, ai)


## The pass/hit script: every action slot uses `hit` (Scrap once out of energy) at a random foe;
## side 1 passes every third round.
func _script(e: BattleEngine, side_index: int) -> Array:
	var out: Array = []
	for bid: int in e.actions_needed(side_index):
		if side_index == 1 and e.round_number % 3 == 2:
			out.append(BattleAction.pass_turn(bid))
			continue
		var move: String = "hit" if e.usable_moves(bid).has("hit") else e.fallback_move()
		out.append(BattleAction.use_move(bid, move, -1))
	return out


func _alive(side: BattleSide) -> int:
	var n: int = 0
	for b: Battler in side.battlers:
		if b.alive():
			n += 1
	return n


## No bid on the field twice (either side), every standing slot creature is flagged active and
## nobody off the field is, and the field holds min(slots, living creatures) when `full` is set.
func _check_field(e: BattleEngine, label: String, full: bool, problems: Array) -> void:
	var seen: Dictionary = {}
	for side: BattleSide in e.sides:
		var on_field: Array[Battler] = side.active()
		for b: Battler in on_field:
			if seen.has(b.bid):
				problems.append("%s: bid %d on the field twice" % [label, b.bid])
			seen[b.bid] = true
			if not b.active or b.side != side.index:
				problems.append("%s: bid %d in a slot but active=%s side=%d" % [label, b.bid, b.active, b.side])
		for b: Battler in side.battlers:
			if b.active and not on_field.has(b):
				problems.append("%s: bid %d flagged active but not standing in a slot" % [label, b.bid])
		if full:
			var expected: int = mini(side.slots.size(), _alive(side))
			if on_field.size() != expected:
				problems.append("%s: side %d has %d on the field, expected %d" % [label, side.index,
					on_field.size(), expected])


func _check_start(e: BattleEngine, events: Array, field0: int, field1: int, label: String, problems: Array) -> void:
	var fields: Array = [field0, field1]
	var sends: Array = FixtureDB.events_of(events, BattleEvents.SEND_OUT)
	if sends.size() != field0 + field1:
		problems.append("%s: %d send_out at start, expected %d" % [label, sends.size(), field0 + field1])
	for i: int in 2:
		var side: BattleSide = e.sides[i]
		if side.slots.size() != int(fields[i]) or side.active().size() != int(fields[i]):
			problems.append("%s: side %d starts with %d slots / %d active, expected %d" % [label, i,
				side.slots.size(), side.active().size(), fields[i]])
		# The opening line-up is the first creatures of the party, in slot order.
		for slot: int in side.active().size():
			if side.slots[slot] != side.battlers[slot]:
				problems.append("%s: side %d slot %d is not party member %d" % [label, i, slot, slot])
	var start: Array = FixtureDB.events_of(events, BattleEvents.BATTLE_START)
	if start.size() != 1 or start[0].slots != [field0, field1]:
		problems.append("%s: battle_start slots %s" % [label, str(start)])


func _check_end(e: BattleEngine, label: String, problems: Array) -> void:
	var res: Dictionary = e.result()
	if not e.is_over():
		problems.append("%s: not over after %d rounds" % [label, e.round_number])
	if int(res.rounds) > db.balance.round_limit:
		problems.append("%s: %d rounds > round_limit" % [label, res.rounds])
	if res.reason == "defeat":
		var winner: int = int(res.winner)
		if not e.sides[1 - winner].defeated() or e.sides[winner].defeated():
			problems.append("%s: defeat with winner %d but the loser is not wiped out" % [label, winner])
	elif res.reason != "round_limit":
		problems.append("%s: unexpected end reason %s" % [label, res.reason])


## Runs a test-controlled battle to the end, filling every replacement the engine asks for.
## Returns how many replacements were made.
func _run_manual(field0: int, field1: int, bench: int, seed_value: int, problems: Array) -> int:
	var label: String = "%dv%d bench %d seed %d" % [field0, field1, bench, seed_value]
	var e: BattleEngine = _format_engine(field0, field1, bench, seed_value)
	var start_events: Array = e.start()
	_check_start(e, start_events, field0, field1, label, problems)
	_check_field(e, label + " start", true, problems)
	var replaced: int = 0
	while not e.is_over() and e.round_number <= db.balance.round_limit:
		var events: Array = e.resolve_round(_script(e, 0) + _script(e, 1))
		var round_label: String = "%s round %d" % [label, e.round_number]
		if e.is_over():
			_check_field(e, round_label, false, problems)
			break
		for side_index: int in 2:
			var side: BattleSide = e.sides[side_index]
			var expected: int = mini(side.open_slots().size(), side.bench().size())
			var pending: int = e.pending_replacements(side_index)
			if pending != expected:
				problems.append("%s: side %d pending %d, expected %d" % [round_label, side_index, pending, expected])
			if bench == 0 and pending != 0:
				problems.append("%s: side %d asks for a replacement with no bench" % [round_label, side_index])
			var asks: Array = FixtureDB.events_of(events, BattleEvents.REPLACEMENT_NEEDED).filter(
				func(ev: Dictionary) -> bool: return int(ev.side) == side_index)
			if pending > 0 and (asks.size() != 1 or int(asks[0].count) != pending):
				problems.append("%s: side %d replacement_needed %s for %d pending" % [round_label, side_index,
					str(asks), pending])
			if pending == 0 and not asks.is_empty():
				problems.append("%s: side %d replacement_needed with nothing pending" % [round_label, side_index])
			for n: int in pending:
				var slot: int = side.open_slots()[0]
				var incoming: Battler = side.bench()[0]
				e.replace(side_index, incoming.bid)
				replaced += 1
				if side.slots[slot] != incoming or not incoming.active:
					problems.append("%s: side %d replacement %d did not land in open slot %d" % [round_label,
						side_index, incoming.bid, slot])
			if e.pending_replacements(side_index) != 0:
				problems.append("%s: side %d still pending after replacing" % [round_label, side_index])
		_check_field(e, round_label, true, problems)
	_check_end(e, label, problems)
	return replaced


func test_every_format_and_bench_runs_to_completion() -> void:
	for format: Array in FORMATS:
		for bench: int in BENCHES:
			var problems: Array = []
			var replaced: int = 0
			for seed_value: int in SEEDS:
				replaced += _run_manual(int(format[0]), int(format[1]), bench, seed_value, problems)
			assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
			# A bench is actually used: faints happen in every format, so a bench refills them.
			if bench == 0:
				assert_int(replaced).is_equal(0)
			else:
				assert_int(replaced).override_failure_message("%s bench %d made no replacement" % [str(format), bench]) \
					.is_greater(0)


func test_ai_sides_refill_their_own_slots() -> void:
	for format: Array in FORMATS:
		for bench: int in BENCHES:
			var problems: Array = []
			for seed_value: int in SEEDS:
				var field0: int = int(format[0])
				var field1: int = int(format[1])
				var label: String = "AI %dv%d bench %d seed %d" % [field0, field1, bench, seed_value]
				var e: BattleEngine = _format_engine(field0, field1, bench, seed_value, "basic")
				_check_start(e, e.start(), field0, field1, label, problems)
				while not e.is_over() and e.round_number <= db.balance.round_limit:
					var events: Array = e.resolve_round([])
					var round_label: String = "%s round %d" % [label, e.round_number]
					_check_field(e, round_label, not e.is_over(), problems)
					if not FixtureDB.events_of(events, BattleEvents.REPLACEMENT_NEEDED).is_empty():
						problems.append("%s: an AI side asked for a replacement" % round_label)
					for side_index: int in 2:
						if e.pending_replacements(side_index) != 0:
							problems.append("%s: AI side %d has pending replacements" % [round_label, side_index])
				_check_end(e, label, problems)
			assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


## The review-focus case: a single creature against a full 3-wide field with a 12-creature party
## (bench of 9). Each orientation, test-controlled and AI.
func test_one_creature_against_a_twelve_creature_party() -> void:
	for ai: String in ["", "basic"]:
		for lone_side: int in 2:
			for seed_value: int in SEEDS:
				var label: String = "lone side %d ai '%s' seed %d" % [lone_side, ai, seed_value]
				var lone: Array = FixtureDB.team(db, 1, "tank", ["hit"], 60)
				var crowd: Array = FixtureDB.team(db, 12, "blob", ["hit"], 5)
				var party0: Array = lone if lone_side == 0 else crowd
				var party1: Array = crowd if lone_side == 0 else lone
				var field0: int = 1 if lone_side == 0 else 3
				var field1: int = 3 if lone_side == 0 else 1
				var e: BattleEngine = _unstarted(party0, party1, field0, field1, seed_value, ai)
				var problems: Array = []
				var events: Array = e.start()
				_check_start(e, events, field0, field1, label, problems)
				var crowd_side: BattleSide = e.sides[1 - lone_side]
				assert_int(crowd_side.battlers.size()).is_equal(12)
				assert_int(crowd_side.bench().size()).is_equal(9)
				# Underdog: the lone creature gets 1 + floor((3 - 1) * 1.0) = 3 actions.
				assert_array(e.actions_needed(lone_side)).has_size(3)
				while not e.is_over() and e.round_number <= db.balance.round_limit:
					var chosen: Array = []
					if ai == "":
						var lone_actions: Array = []
						for bid: int in e.actions_needed(lone_side):
							lone_actions.append(BattleAction.use_move(bid, "hit", -1))
						chosen = lone_actions + _script(e, 1 - lone_side)
					events.append_array(e.resolve_round(chosen))
					if e.is_over():
						break
					for n: int in e.pending_replacements(1 - lone_side):
						events.append_array(e.replace(1 - lone_side, crowd_side.bench()[0].bid))
					_check_field(e, "%s round %d" % [label, e.round_number], true, problems)
				_check_end(e, label, problems)
				assert_array(problems).override_failure_message("\n".join(problems)).is_empty()
				# The level-60 tank knocks out a level-5 blob per hit, three hits a round: it wins, and
				# each of the twelve came onto the field exactly once.
				assert_int(int(e.result().winner)).override_failure_message(label).is_equal(lone_side)
				assert_str(str(e.result().reason)).is_equal("defeat")
				for b: Battler in crowd_side.battlers:
					var sent: int = FixtureDB.events_of(events, BattleEvents.SEND_OUT).filter(
						func(ev: Dictionary) -> bool: return int(ev.bid) == b.bid).size()
					assert_int(sent).override_failure_message("%s: bid %d sent out %d times" % [label, b.bid, sent]) \
						.is_equal(1)
				assert_int(e.round_number).is_less_equal(db.balance.round_limit)


## An auto-replace side refills every slot that emptied this round, in bench order, before the
## next round, and never asks for a replacement.
func test_auto_replace_side_refills_every_empty_slot_at_end_of_round() -> void:
	for bench: int in [3, 1]:
		var setup: BattleSetup = BattleSetup.new()
		setup.add_side(FixtureDB.team(db, 3, "blob", ["hit"], 30), 3)
		setup.add_side(FixtureDB.team(db, 3 + bench, "tank"), 3, 3, {}, "", true)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 7
		var e: BattleEngine = BattleEngine.new(db, rng, setup)
		e.start()
		var side: BattleSide = e.sides[1]
		var left: Battler = side.slots[0]
		var right: Battler = side.slots[2]
		var middle: Battler = side.slots[1]
		left.creature.hp = 1
		right.creature.hp = 1
		var bench_order: Array[Battler] = side.bench()
		var mine: Array[Battler] = e.sides[0].active()
		var events: Array = e.resolve_round([BattleAction.use_move(mine[0].bid, "hit", left.bid),
			BattleAction.use_move(mine[1].bid, "hit", right.bid), BattleAction.pass_turn(mine[2].bid)])
		assert_array(FixtureDB.events_of(events, BattleEvents.FAINT)).has_size(2)
		assert_array(FixtureDB.events_of(events, BattleEvents.REPLACEMENT_NEEDED)).is_empty()
		assert_int(e.pending_replacements(1)).is_equal(0)
		var refills: Array = FixtureDB.events_of(events, BattleEvents.SEND_OUT)
		assert_array(refills).has_size(mini(2, bench))
		assert_object(side.slots[0]).is_same(bench_order[0])
		assert_int(int(refills[0].slot)).is_equal(0)
		if bench >= 2:
			assert_object(side.slots[2]).is_same(bench_order[1])
			assert_int(int(refills[1].slot)).is_equal(2)
		assert_object(side.slots[1]).is_same(middle)
		assert_int(side.active().size()).is_equal(mini(3, 1 + bench))


## The player may replace with any bench member, not only the first: from a 9-deep bench, the last
## one and then a middle one enter the vacated slot, and everyone else stays benched in order.
func test_replacement_can_pick_a_later_member_of_a_deep_bench() -> void:
	for field: int in [1, 3]:
		var e: BattleEngine = FixtureDB.engine(db, FixtureDB.team(db, field + 9), FixtureDB.team(db, field, "tank"),
			field, field)
		var side: BattleSide = e.sides[0]
		var slot: int = field - 1 if field == 1 else 1
		var others: Array = []
		for i: int in field:
			if i != slot:
				others.append(side.slots[i])
		for pick: String in ["last", "middle"]:
			var bench_before: Array = Array(side.bench())
			assert_int(bench_before.size()).is_equal(9 if pick == "last" else 8)
			FixtureDB.knock_out(e, [side.slots[slot]])
			assert_int(e.pending_replacements(0)).is_equal(1)
			var chosen: Battler = bench_before[bench_before.size() - 1] if pick == "last" else bench_before[4]
			var events: Array = e.replace(0, chosen.bid)
			assert_array(FixtureDB.events_of(events, BattleEvents.ACTION_INVALID)).is_empty()
			var sends: Array = FixtureDB.events_of(events, BattleEvents.SEND_OUT)
			assert_array(sends).has_size(1)
			assert_int(int(sends[0].bid)).is_equal(chosen.bid)
			assert_int(int(sends[0].slot)).is_equal(slot)
			assert_object(side.slots[slot]).is_same(chosen)
			var rest: Array = bench_before.filter(func(b: Battler) -> bool: return b != chosen)
			assert_array(Array(side.bench())).override_failure_message("%d-wide %s" % [field, pick]) \
				.is_equal(rest)
			for i: int in others.size():
				assert_bool((others[i] as Battler).active).is_true()
			assert_int(e.pending_replacements(0)).is_equal(0)


## Replacements land in the slot that emptied, in party-bench order; a bench smaller than the
## gaps fills what it can; no bench leaves the slot empty (and the side becomes the underdog).
func test_replacements_fill_the_emptied_slots() -> void:
	for bench: int in [3, 1, 0]:
		var e: BattleEngine = FixtureDB.engine(db, FixtureDB.team(db, 3 + bench), FixtureDB.team(db, 3, "tank"), 3, 3)
		var side: BattleSide = e.sides[0]
		var middle: Battler = side.slots[1]
		var outer_a: Battler = side.slots[0]
		var outer_b: Battler = side.slots[2]
		outer_a.creature.hp = 1
		outer_b.creature.hp = 1
		var foes: Array[Battler] = e.sides[1].active()
		var events: Array = e.resolve_round([BattleAction.pass_turn(outer_a.bid), BattleAction.pass_turn(middle.bid),
			BattleAction.pass_turn(outer_b.bid), BattleAction.use_move(foes[0].bid, "hit", outer_a.bid),
			BattleAction.use_move(foes[1].bid, "hit", outer_b.bid), BattleAction.pass_turn(foes[2].bid)])
		assert_array(FixtureDB.events_of(events, BattleEvents.FAINT)).has_size(2)
		assert_array(side.open_slots()).contains_exactly([0, 2])
		var expected: int = mini(2, bench)
		assert_int(e.pending_replacements(0)).is_equal(expected)
		var asks: Array = FixtureDB.events_of(events, BattleEvents.REPLACEMENT_NEEDED)
		if expected == 0:
			assert_array(asks).is_empty()
			# Outnumbered 1v3 now: Underdog recalculated at end of round.
			assert_float(float(side.underdog.ratio)).is_equal_approx(3.0, 0.0001)
			assert_array(e.actions_needed(0)).has_size(3)
			continue
		assert_array(asks).has_size(1)
		assert_int(int(asks[0].count)).is_equal(expected)
		var bench_order: Array[Battler] = side.bench()
		# A creature already on the field, a fainted one, a foe and an unknown bid are refused.
		for bad: int in [middle.bid, outer_a.bid, foes[0].bid, 999]:
			var refused: Array = e.replace(0, bad)
			assert_array(FixtureDB.events_of(refused, BattleEvents.ACTION_INVALID)).has_size(1)
			assert_str(str(FixtureDB.events_of(refused, BattleEvents.ACTION_INVALID)[0].reason)).is_equal("bad_replacement")
		assert_int(e.pending_replacements(0)).is_equal(expected)
		e.replace(0, bench_order[0].bid)
		assert_object(side.slots[0]).is_same(bench_order[0])
		if bench >= 2:
			e.replace(0, bench_order[1].bid)
			assert_object(side.slots[2]).is_same(bench_order[1])
		assert_object(side.slots[1]).is_same(middle)
		assert_int(e.pending_replacements(0)).is_equal(0)
		assert_int(side.active().size()).is_equal(mini(3, 1 + bench))
		# Nothing left to fill: one more replacement is refused.
		if not side.bench().is_empty() and side.open_slots().is_empty():
			var extra: Array = e.replace(0, side.bench()[0].bid)
			assert_array(FixtureDB.events_of(extra, BattleEvents.ACTION_INVALID)).has_size(1)
