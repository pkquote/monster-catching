extends GdUnitTestSuite
## Targeting matrix: every creature target key the moves use (self, one_enemy, two_enemies,
## all_enemies, one_ally, all_allies, all) against 1, 2 and 3 standing foes and allies, including
## fainted creatures left in the slots between them. Checks targets_for / second_targets_for, the
## creatures actually hit, one event per target, and the spread multiplier for the real hit count.
##
## The damage windows are run twice: with FixtureDB's table (2 -> 0.85, 3 -> 0.75) and with a wide
## table (2 -> 0.5, 3 -> 0.25) whose roll windows don't overlap, so a wrong count or a wrong table
## lookup cannot hide inside the 0.85-1.0 damage roll.

## [fielded, fainted slots]. No benches, so a fainted creature's slot stays empty.
const ALLY_LAYOUTS: Array = [[1, []], [2, []], [3, []], [3, [1]]]
const FOE_LAYOUTS: Array = [[1, []], [2, []], [3, []], [3, [1]], [3, [0]], [2, [0]], [3, [0, 1]], [3, [0, 2]]]
const SEEDS: Array = [1, 2, 3]
## [move, aim]: "last" aims at the last standing creature of the move's side, "fainted" at a
## fainted one (only run when the layout has one), "none" leaves the pick to the engine.
## For twin_strike, "pair" picks the first and last standing foes explicitly (needs two standing),
## "bad_second" picks the first standing foe plus an invalid second (a fainted foe, else an ally).
const RUNS: Array = [
	["hit", "last"], ["hit", "fainted"], ["twin_strike", "none"], ["twin_strike", "pair"],
	["twin_strike", "bad_second"], ["broadside", "none"],
	["tremor", "none"], ["brace", "none"], ["cheer", "last"], ["cheer", "fainted"], ["rally", "none"],
]
const DAMAGING: Array = ["hit", "twin_strike", "broadside", "tremor"]

var db: Database
var wide: Database


func _raw(spread: Dictionary) -> RawData:
	var r: RawData = FixtureDB.raw()
	# Same power, type and category as `hit`, so `hit`'s single-target estimate is every move's baseline.
	r.add_entry("moves", FixtureDB.move("twin_strike", "neutral", "physical", 50, 100, "two_enemies", [{"op": "damage"}]))
	r.add_entry("moves", FixtureDB.move("broadside", "neutral", "physical", 50, 100, "all_enemies", [{"op": "damage"}]))
	r.add_entry("moves", FixtureDB.move("tremor", "neutral", "physical", 50, 100, "all", [{"op": "damage"}]))
	r.add_entry("moves", FixtureDB.move("brace", "neutral", "status", 0, 100, "self",
		[{"op": "stat_stage", "stat": "pdef", "stages": 1}], {"always_hits": true}))
	r.add_entry("moves", FixtureDB.move("cheer", "neutral", "status", 0, 100, "one_ally",
		[{"op": "stat_stage", "stat": "patk", "stages": 1}], {"always_hits": true}))
	r.add_entry("moves", FixtureDB.move("rally", "neutral", "status", 0, 100, "all_allies",
		[{"op": "stat_stage", "stat": "spd", "stages": 1}], {"always_hits": true}))
	var b: Dictionary = FixtureDB.balance()
	b["spread_mults"] = spread
	r.set_single("balance", b)
	return r


func _build(spread: Dictionary) -> Database:
	var r: RawData = _raw(spread)
	var errors: Array = DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	return Database.from_raw(r)


func before() -> void:
	db = _build({"2": 0.85, "3": 0.75})
	wide = _build({"2": 0.5, "3": 0.25})


## Attacker (a level-90 blob knowing every test move) in slot 0 plus tank allies, against tanks.
## Fainted creatures stay in their slots; Underdog is recalculated as an end of round would.
func _case(database: Database, allies: Array, foes: Array, seed_value: int) -> BattleEngine:
	var mine: Array = [FixtureDB.make(database, "blob", 90,
		["hit", "twin_strike", "broadside", "tremor", "brace", "cheer", "rally"])]
	mine.append_array(FixtureDB.team(database, int(allies[0]) - 1, "tank", ["hit"], 90))
	var theirs: Array = FixtureDB.team(database, int(foes[0]), "tank", ["hit"], 90)
	var e: BattleEngine = FixtureDB.engine(database, mine, theirs, int(allies[0]), int(foes[0]), seed_value)
	var down: Array = []
	for slot: int in allies[1]:
		down.append(e.sides[0].slots[slot])
	for slot: int in foes[1]:
		down.append(e.sides[1].slots[slot])
	FixtureDB.knock_out(e, down)
	return e


func _bids(list: Array) -> Array:
	return list.map(func(b: Battler) -> int: return b.bid)


func _fainted_in_slots(side: BattleSide) -> Array:
	var out: Array = []
	for occupant: Variant in side.slots:
		if occupant != null and not (occupant as Battler).alive():
			out.append(occupant)
	return out


## The legal picks targets_for must list for each move.
func _expected_picks(e: BattleEngine, move: String) -> Array:
	match move:
		"hit", "twin_strike":
			return _bids(e.sides[1].active())
		"cheer":
			# PIN: undocumented current behaviour. one_ally lists every standing creature on the
			# user's side, the user included (documentation/battle-engine.md doesn't say either way).
			return _bids(e.sides[0].active())
	return [-1]


func _run(database: Database, allies: Array, foes: Array, seed_value: int, move: String, aim: String,
		problems: Array) -> void:
	var e: BattleEngine = _case(database, allies, foes, seed_value)
	var label: String = "%s/%s allies %s foes %s seed %d" % [move, aim, str(allies), str(foes), seed_value]
	var me: Battler = e.sides[0].slots[0]
	var foes_up: Array = _bids(e.sides[1].active())
	var allies_up: Array = _bids(e.sides[0].active())
	var aim_side: BattleSide = e.sides[0] if move == "cheer" else e.sides[1]
	var target: int = -1
	var second: int = -1
	if aim == "last":
		target = aim_side.active()[aim_side.active().size() - 1].bid
	elif aim == "fainted":
		var down: Array = _fainted_in_slots(aim_side)
		if down.is_empty():
			return
		target = (down[0] as Battler).bid
	elif aim == "pair":
		if foes_up.size() < 2:
			return
		target = int(foes_up[0])
		second = int(foes_up[foes_up.size() - 1])
	elif aim == "bad_second":
		target = int(foes_up[0])
		var down_foes: Array = _fainted_in_slots(e.sides[1])
		second = (down_foes[0] as Battler).bid if not down_foes.is_empty() else me.bid

	# targets_for / second_targets_for: only standing creatures on the right side.
	var picks: Array = Array(e.targets_for(me.bid, move))
	var want: Array = _expected_picks(e, move)
	picks.sort()
	want.sort()
	if picks != want:
		problems.append("%s: targets_for %s, expected %s" % [label, str(picks), str(want)])
	var seconds: Array = Array(e.second_targets_for(me.bid, move, int(foes_up[0])))
	var want_seconds: Array = foes_up.slice(1) if move == "twin_strike" else []
	seconds.sort()
	want_seconds.sort()
	if seconds != want_seconds:
		problems.append("%s: second_targets_for %s, expected %s" % [label, str(seconds), str(want_seconds)])

	# Baselines before the round: `hit`'s average single-target damage on each creature.
	var baseline: Dictionary = {}
	var hp_before: Dictionary = {}
	for b: Battler in e.sides[0].active() + e.sides[1].active():
		baseline[b.bid] = BattleAI.estimate_damage(e, me, database.move("hit"), b, 1)
		hp_before[b.bid] = b.hp()

	var events: Array = e.resolve_round([BattleAction.use_move(me.bid, move, target, second)])
	var used: Array = FixtureDB.events_of(events, BattleEvents.MOVE_USED)
	if used.size() != 1:
		problems.append("%s: %d move_used events" % [label, used.size()])
		return
	var hit: Array = used[0].targets.duplicate()
	hit.sort()

	# Who should have been hit.
	var expected: Array = []
	match move:
		"hit":
			expected = [target] if foes_up.has(target) else []
		"broadside":
			expected = foes_up.duplicate()
		"tremor":
			# PIN: undocumented current behaviour. `all` hits every standing creature except the
			# user (the docs list the key without saying whether the user is included).
			expected = allies_up.filter(func(bid: int) -> bool: return bid != me.bid) + foes_up
		"brace":
			expected = [me.bid]
		"cheer":
			expected = [target]
		"rally":
			expected = allies_up.duplicate()
	if move == "twin_strike":
		var distinct: Dictionary = {}
		for bid: int in hit:
			distinct[bid] = true
			if not foes_up.has(bid):
				problems.append("%s: hit %d, not a standing foe" % [label, bid])
		if hit.size() != mini(2, foes_up.size()) or distinct.size() != hit.size():
			problems.append("%s: hit %s, expected %d distinct standing foes" % [label, str(hit),
				mini(2, foes_up.size())])
		# Valid picks are honoured; an invalid second pick is never hit (it is replaced).
		if aim == "pair":
			var pair: Array = [target, second]
			pair.sort()
			if hit != pair:
				problems.append("%s: hit %s, expected the chosen pair %s" % [label, str(hit), str(pair)])
		elif aim == "bad_second" and (not hit.has(target) or hit.has(second)):
			problems.append("%s: hit %s, expected %d kept and invalid %d replaced" % [label, str(hit),
				target, second])
	elif move == "hit" and aim == "fainted":
		# Aimed at a fainted foe: re-targeted at one standing foe.
		if hit.size() != 1 or not foes_up.has(hit[0]):
			problems.append("%s: hit %s, expected one standing foe" % [label, str(hit)])
	elif move == "cheer" and aim == "fainted":
		# A fainted ally is not a legal pick: it is replaced with a random standing ally (the user included).
		if hit.size() != 1 or not allies_up.has(hit[0]):
			problems.append("%s: hit %s, expected one standing ally" % [label, str(hit)])
	else:
		expected.sort()
		if hit != expected:
			problems.append("%s: hit %s, expected %s" % [label, str(hit), str(expected)])

	if DAMAGING.has(move):
		_check_damage(database, e, events, hit, baseline, label, problems)
	else:
		var ups: Array = _bids_of(FixtureDB.events_of(events, BattleEvents.STAT_STAGE))
		ups.sort()
		if ups != hit:
			problems.append("%s: stat_stage events for %s, expected one each for %s" % [label, str(ups), str(hit)])
		if not FixtureDB.events_of(events, BattleEvents.DAMAGE).is_empty():
			problems.append("%s: a status move dealt damage" % label)
	# Nobody outside the hit list lost HP.
	for bid: int in hp_before:
		if not hit.has(bid) and e.battler(bid).hp() != int(hp_before[bid]):
			problems.append("%s: bid %d was not a target but lost HP" % [label, bid])


## The documented rule, read straight from the loaded `balance.spread_mults` table (not through
## BalanceDef.spread_mult_for, so a broken lookup can't agree with itself): one creature 1.0,
## two the "2" value, three or more the "3" value.
func _table_value(database: Database, count: int) -> float:
	if count <= 1:
		return 1.0
	return float(database.balance.spread_mults[2 if count == 2 else 3])


func _bids_of(events: Array) -> Array:
	return events.map(func(ev: Dictionary) -> int: return int(ev.bid))


## One damage event per creature hit, each inside the roll window of
## baseline x spread_mult_for(count) x (1 - that side's Underdog spread reduction, spread only).
func _check_damage(database: Database, e: BattleEngine, events: Array, hit: Array, baseline: Dictionary,
		label: String, problems: Array) -> void:
	var damages: Array = FixtureDB.events_of(events, BattleEvents.DAMAGE)
	var damaged: Array = _bids_of(damages)
	damaged.sort()
	if damaged != hit:
		problems.append("%s: damage events for %s, expected one each for %s" % [label, str(damaged), str(hit)])
	var count: int = hit.size()
	var table: float = _table_value(database, count)
	for ev: Dictionary in damages:
		var t: Battler = e.battler(int(ev.bid))
		var reduction: float = float(e.sides[t.side].underdog.get("spread_reduction", 0.0)) if count > 1 else 0.0
		var m: float = table * (1.0 - reduction)
		var s: float = float(baseline[t.bid])
		var lo: float = s / BattleMath.ROLL_AVG * m * BattleMath.ROLL_MIN - 1.0
		var hi: float = (s + 1.0) / BattleMath.ROLL_AVG * m + 1.0
		var amount: float = float(ev.amount)
		if amount < lo or amount > hi:
			problems.append("%s: %d damage on %d outside [%.1f, %.1f] (count %d, mult %.3f)" % [label,
				int(ev.amount), t.bid, lo, hi, count, m])


func _matrix(database: Database) -> Array:
	var problems: Array = []
	for allies: Array in ALLY_LAYOUTS:
		for foes: Array in FOE_LAYOUTS:
			for run: Array in RUNS:
				var move: String = run[0]
				var seeds: Array = SEEDS if DAMAGING.has(move) else [1]
				for seed_value: int in seeds:
					_run(database, allies, foes, seed_value, move, str(run[1]), problems)
	return problems


func test_matrix_with_the_fixture_spread_table() -> void:
	var problems: Array = _matrix(db)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_matrix_with_a_wide_spread_table() -> void:
	var problems: Array = _matrix(wide)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


## The table itself, as the matrix reads it.
func test_spread_table_values() -> void:
	assert_float(db.balance.spread_mult_for(1)).is_equal(1.0)
	assert_float(db.balance.spread_mult_for(2)).is_equal_approx(0.85, 0.0001)
	assert_float(db.balance.spread_mult_for(3)).is_equal_approx(0.75, 0.0001)
	assert_float(db.balance.spread_mult_for(5)).is_equal_approx(0.75, 0.0001)
	assert_float(wide.balance.spread_mult_for(2)).is_equal_approx(0.5, 0.0001)
	assert_float(wide.balance.spread_mult_for(3)).is_equal_approx(0.25, 0.0001)


## Concrete spot checks with exact numbers (wide table): the same foe takes about half from a
## two-target hit and about a quarter from a three-target hit, with a fainted foe in between.
func test_fainted_slot_between_foes_changes_the_count() -> void:
	for seed_value: int in SEEDS:
		# 1 attacker vs 3 foes with the middle one down: broadside hits 2 at x0.5.
		var e: BattleEngine = _case(wide, [1, []], [3, [1]], seed_value)
		var me: Battler = e.sides[0].slots[0]
		var outer: Battler = e.sides[1].slots[0]
		var s: float = BattleAI.estimate_damage(e, me, wide.move("hit"), outer, 1)
		var events: Array = e.resolve_round([BattleAction.use_move(me.bid, "broadside")])
		var damages: Array = FixtureDB.events_of(events, BattleEvents.DAMAGE)
		assert_array(damages).has_size(2)
		assert_array(_bids_of(damages)).contains_exactly_in_any_order(
			[(e.sides[1].slots[0] as Battler).bid, (e.sides[1].slots[2] as Battler).bid])
		for ev: Dictionary in damages:
			assert_float(float(ev.amount)).is_between(s / BattleMath.ROLL_AVG * 0.5 * BattleMath.ROLL_MIN - 1.0,
				(s + 1.0) / BattleMath.ROLL_AVG * 0.5 + 1.0)
		# All three up: x0.25.
		var full: BattleEngine = _case(wide, [1, []], [3, []], seed_value)
		var me3: Battler = full.sides[0].slots[0]
		var s3: float = BattleAI.estimate_damage(full, me3, wide.move("hit"), full.sides[1].slots[0], 1)
		var events3: Array = full.resolve_round([BattleAction.use_move(me3.bid, "broadside")])
		var damages3: Array = FixtureDB.events_of(events3, BattleEvents.DAMAGE)
		assert_array(damages3).has_size(3)
		for ev: Dictionary in damages3:
			assert_float(float(ev.amount)).is_between(s3 / BattleMath.ROLL_AVG * 0.25 * BattleMath.ROLL_MIN - 1.0,
				(s3 + 1.0) / BattleMath.ROLL_AVG * 0.25 + 1.0)
		# Two of three down: twin_strike hits the one left, unreduced.
		var lone: BattleEngine = _case(wide, [1, []], [3, [0, 2]], seed_value)
		var me1: Battler = lone.sides[0].slots[0]
		var middle: Battler = lone.sides[1].slots[1]
		var s1: float = BattleAI.estimate_damage(lone, me1, wide.move("hit"), middle, 1)
		var events1: Array = lone.resolve_round([BattleAction.use_move(me1.bid, "twin_strike")])
		var damages1: Array = FixtureDB.events_of(events1, BattleEvents.DAMAGE)
		assert_array(damages1).has_size(1)
		assert_int(int(damages1[0].bid)).is_equal(middle.bid)
		assert_float(float(damages1[0].amount)).is_between(s1 / BattleMath.ROLL_AVG * BattleMath.ROLL_MIN - 1.0,
			(s1 + 1.0) / BattleMath.ROLL_AVG + 1.0)
