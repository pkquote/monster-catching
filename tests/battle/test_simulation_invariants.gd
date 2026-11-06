extends GdUnitTestSuite
## Seeded AI-vs-AI battles on the real game data (the loop in tools/simulate.gd): tactician vs
## aggressive, random species (and some random held items) at levels 5 and 40, benches from 0 to 9.
## After every round: HP stays within [0, max_hp], no event names an unknown bid, a fainted
## creature takes no action until it is placed again, and the battle ends within the round limit.
## Replaying a seed gives the identical event log, and every format has battles won outright.
##
## Problems are collected as text and asserted empty once per format, so a failure names the
## format, seed and round.

const FORMATS: Array = [[1, 1], [2, 2], [3, 3], [1, 3], [2, 3]]
const SEED_COUNT: int = 20
## Bench sizes cycled per seed; side 1 uses a different one than side 0.
const BENCHES: Array = [0, 1, 3, 6, 9]
## Events whose `bid` is the creature acting.
const ACTION_EVENTS: Array = [BattleEvents.MOVE_USED, BattleEvents.ITEM_USED, BattleEvents.REST,
	BattleEvents.PASS, BattleEvents.FLED, BattleEvents.SWAP_OUT, BattleEvents.DISOBEYED,
	BattleEvents.LASHED_OUT, BattleEvents.ACTION_SKIPPED, BattleEvents.CAPTURE_ATTEMPT]
## Events whose `bid` is a creature something happens to; a fainted creature receives none.
const RECEIVE_EVENTS: Array = [BattleEvents.DAMAGE, BattleEvents.HEAL, BattleEvents.STATUS_APPLIED,
	BattleEvents.STAT_STAGE]

var db: Database
var _held: PackedStringArray = PackedStringArray()


func before() -> void:
	var loaded: DataLoader.LoadResult = DataLoader.load_database("res://data")
	assert(loaded.ok(), "Real data failed to load:\n" + "\n".join(loaded.errors))
	db = loaded.db
	for id: String in db.ids("items"):
		if db.item(id).category == "held":
			_held.append(id)


## Every run's parameters: one entry per (format, seed).
func _runs() -> Array:
	var out: Array = []
	for f: Array in FORMATS:
		for s: int in range(1, SEED_COUNT + 1):
			out.append({"field": f, "seed": s, "level": 5 if s % 2 == 1 else 40,
				"bench": [int(BENCHES[s % BENCHES.size()]), int(BENCHES[(s + 2) % BENCHES.size()])]})
	return out


## Builds and starts the battle for `run` exactly the way tools/simulate.gd does (one RNG for the
## parties and the battle), plus a random held item on about a third of the creatures.
func _engine(run: Dictionary) -> BattleEngine:
	var field: Array = run.field
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(run.seed)
	var species: PackedStringArray = db.ids("creatures")
	var setup: BattleSetup = BattleSetup.new()
	setup.award_xp = false
	var max_active: int = maxi(int(field[0]), int(field[1]))
	var ais: Array = ["tactician", "aggressive"]
	for s: int in 2:
		var party: Array = []
		for n: int in int(field[s]) + int(run.bench[s]):
			var sp: String = species[rng.randi_range(0, species.size() - 1)]
			var c: CreatureInstance = CreatureInstance.create(db, sp, int(run.level), PackedStringArray(), rng)
			if not _held.is_empty() and rng.randi_range(0, 2) == 0:
				c.held_item = _held[rng.randi_range(0, _held.size() - 1)]
			party.append(c)
		setup.add_side(party, max_active, int(field[s]), {}, ais[s], true)
	return BattleEngine.new(db, rng, setup)


## Plays `run` to the end, appending invariant violations to `problems`. Returns
## { history: Array (every event), result: Dictionary, bench_sizes: Array }.
func _play(run: Dictionary, problems: Array) -> Dictionary:
	var e: BattleEngine = _engine(run)
	var tag: String = "%dv%d seed %d L%d" % [run.field[0], run.field[1], run.seed, run.level]
	var down: Dictionary = {}
	var history: Array = []
	var events: Array = e.start()
	_check(e, events, down, problems, tag + " start")
	history.append_array(events)
	var limit: int = db.balance.round_limit
	var guard: int = 0
	while not e.is_over() and guard <= limit + 5:
		guard += 1
		events = e.resolve_round([])
		_check(e, events, down, problems, "%s round %d" % [tag, e.round_number])
		history.append_array(events)
	var res: Dictionary = e.result()
	if not e.is_over():
		problems.append("%s: not over after %d rounds" % [tag, guard])
	if int(res.rounds) > limit:
		problems.append("%s: %d rounds > round_limit %d" % [tag, res.rounds, limit])
	var ends: Array = FixtureDB.events_of(history, BattleEvents.BATTLE_END)
	if ends.size() != 1 or history.back().type != BattleEvents.BATTLE_END:
		problems.append("%s: %d battle_end events, last event %s" % [tag, ends.size(), history.back().type])
	elif int(ends[0].winner) != int(res.winner):
		problems.append("%s: battle_end winner %d != result %d" % [tag, ends[0].winner, res.winner])
	if int(res.winner) == -1 and str(res.reason) != "round_limit":
		problems.append("%s: no winner but reason %s" % [tag, res.reason])
	return {"history": history, "result": res,
		"bench_sizes": [e.sides[0].battlers.size() - int(run.field[0]), e.sides[1].battlers.size() - int(run.field[1])]}


func _check(e: BattleEngine, events: Array, down: Dictionary, problems: Array, where: String) -> void:
	for b: Battler in e.all_battlers():
		var max_hp: int = b.creature.max_hp(db)
		if b.hp() < 0 or b.hp() > max_hp:
			problems.append("%s: bid %d hp %d outside [0, %d]" % [where, b.bid, b.hp(), max_hp])
	for ev: Dictionary in events:
		var type: String = str(ev.type)
		for key: String in ["bid", "by", "target"]:
			if ev.has(key):
				var bid: int = int(ev[key])
				# -1 means "nobody" for an attacker or an untargeted action.
				if e.battler(bid) == null and not (key != "bid" and bid == -1):
					problems.append("%s: %s.%s names unknown bid %d" % [where, type, key, bid])
		if ev.has("targets"):
			for t: Variant in ev.targets:
				if e.battler(int(t)) == null:
					problems.append("%s: %s.targets names unknown bid %d" % [where, type, int(t)])
		if not ev.has("bid"):
			continue
		var who: int = int(ev.bid)
		if type == BattleEvents.FAINT:
			down[who] = true
		elif type == BattleEvents.SEND_OUT:
			if int(ev.hp) <= 0:
				problems.append("%s: bid %d sent out with %d HP" % [where, who, int(ev.hp)])
			down.erase(who)
		elif down.has(who) and (type in ACTION_EVENTS or type in RECEIVE_EVENTS):
			problems.append("%s: fainted bid %d has %s after its faint" % [where, who, type])


func test_simulated_battles_keep_their_invariants_and_replay_identically() -> void:
	var started: int = Time.get_ticks_msec()
	var all_problems: Array = []
	var biggest_bench: int = 0
	var bench_sizes_seen: Dictionary = {}
	var runs: Array = _runs()
	for f: Array in FORMATS:
		var problems: Array = []
		var winners: int = 0
		var by_reason: Dictionary = {}
		for run: Dictionary in runs.filter(func(r: Dictionary) -> bool: return r.field == f):
			var first: Dictionary = _play(run, problems)
			var again: Dictionary = _play(run, [])
			var a: String = JSON.stringify(first.history)
			var b: String = JSON.stringify(again.history)
			if a != b:
				problems.append("%dv%d seed %d: replay differs (%d vs %d events)" % [f[0], f[1], run.seed,
					first.history.size(), again.history.size()])
			if int(first.result.winner) != -1:
				winners += 1
			by_reason[str(first.result.reason)] = int(by_reason.get(str(first.result.reason), 0)) + 1
			for n: Variant in first.bench_sizes:
				biggest_bench = maxi(biggest_bench, int(n))
				bench_sizes_seen[int(n)] = true
		# The simulation means something only if battles are actually decided.
		if winners == 0:
			problems.append("%dv%d: no battle was won outright (%s)" % [f[0], f[1], by_reason])
		print("%dv%d: %d/%d won outright, reasons %s" % [f[0], f[1], winners, SEED_COUNT, by_reason])
		all_problems.append_array(problems)
		assert_array(problems).override_failure_message("%dv%d:\n%s" % [f[0], f[1],
			"\n".join(problems.slice(0, 20))]).is_empty()
	assert_int(biggest_bench).is_greater_equal(6)
	assert_array(bench_sizes_seen.keys()).contains([0, 1, 3, 6, 9])
	print("Simulation invariants: %d battles x2 in %d ms" % [runs.size(), Time.get_ticks_msec() - started])


func test_a_stalled_battle_ends_in_a_draw_exactly_at_the_round_limit() -> void:
	# The AI battles above are all decided well inside the limit, so the limit itself is checked
	# here: two test-controlled sides that only pass, on the real data and balance.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var species: PackedStringArray = db.ids("creatures")
	var setup: BattleSetup = BattleSetup.new()
	for s: int in 2:
		var party: Array = []
		for n: int in 3:
			party.append(CreatureInstance.create(db, species[(s * 3 + n) % species.size()], 40, PackedStringArray(), rng))
		setup.add_side(party, 2, 2)
	var e: BattleEngine = BattleEngine.new(db, rng, setup)
	var problems: Array = []
	var down: Dictionary = {}
	_check(e, e.start(), down, problems, "stall start")
	var limit: int = db.balance.round_limit
	var rounds: int = 0
	while not e.is_over() and rounds <= limit + 5:
		rounds += 1
		var chosen: Array = []
		for side: int in 2:
			for bid: int in e.actions_needed(side):
				chosen.append(BattleAction.pass_turn(bid))
		_check(e, e.resolve_round(chosen), down, problems, "stall round %d" % rounds)
	assert_array(problems).is_empty()
	assert_bool(e.is_over()).is_true()
	assert_int(int(e.result().rounds)).is_equal(limit)
	assert_int(int(e.result().winner)).is_equal(-1)
	assert_str(str(e.result().reason)).is_equal("round_limit")


func test_held_items_exist_in_real_data_for_the_simulation() -> void:
	# The random held items above only exercise anything if the real data has some.
	assert_int(_held.size()).is_greater(0)
