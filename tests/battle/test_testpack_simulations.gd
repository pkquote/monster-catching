extends GdUnitTestSuite
## Seeded AI-vs-AI battles over data/ plus the debug test pack (data_testpack/), the way
## tools/simulate.gd --pack=1 runs them. Formats 1v1, 2v2, 3v3, 1v3, 2v3 and 3v6 (3 fielded,
## 6-creature teams) x seeds 1..30; level 5 on odd seeds and 60 on even ones; AI styles rotate
## through basic, tactician and aggressive. Every other creature is a pack species taken in turn
## and the rest are random pack species (never base ones, so growing data/ doesn't shift the run);
## pack moves, passives and held items are dealt out in turn as well, so the run covers the whole
## pack deterministically. Base content takes part through data/'s types, statuses, field states,
## reactions and balance; base creatures are covered by test_simulation_invariants.gd.
##
## After every round: HP within [0, max_hp], no event names an unknown bid, a fainted creature
## does nothing until it is placed again, and the battle ends within balance.round_limit (the
## same checks as test_simulation_invariants.gd; _check is a copy of that suite's). Each run is
## replayed and must give the identical JSON.stringify event log.
##
## Draws at the round limit are allowed (extreme pack stat shapes and stall content can lock a
## battle), but fewer than MAX_DRAW_PERCENT of the battles may draw. Across the run every pack
## creature is fielded, every pack move is used (MOVE_USED) and every pack passive and held item
## is fielded; those with triggers must also show a PASSIVE_TRIGGERED banner. What the AI never
## gets to is listed in EXEMPT_MOVES / EXEMPT_TRIGGERS (printed every run); an unlisted miss
## fails, and each list has a cap so it cannot grow silently.
##
## Runtime: 180 battles x 2 plays, about 25 s. 30 seeds because the plan deals the pack out in
## turn, so every pack addition shifts what the AI reaches; fewer seeds needed a growing
## exemption list below.

const PACK_ROOT: String = "res://data_testpack"
## [fielded side 0, fielded side 1, team size (0 = fielded + a seed-dependent bench of 0..2)].
const FORMATS: Array = [[1, 1, 0], [2, 2, 0], [3, 3, 0], [1, 3, 0], [2, 3, 0], [3, 3, 6]]
const SEED_COUNT: int = 30
const AIS: Array = ["basic", "tactician", "aggressive"]
## Observed: 0 of 180 battles draw (all end by defeat). 5% (at most 9 of 180) leaves room for a
## stall from a degenerate pack combo without letting the simulation drift into draws.
const MAX_DRAW_PERCENT: int = 5
## Pack moves the AI never picks in this run, with the reason. Every unused pack move must be
## listed here; the list may not exceed MAX_EXEMPT_MOVES.
const EXEMPT_MOVES: Dictionary = {
	# Tactician and aggressive pick the best score; basic picks a random (move, target) option,
	# and the few fielded basic-AI holders in the plan never rolled these.
	"tp_restore_energy_full_self": "the AI gives restore_energy no score, so only basic would pick it",
	"tp_stage_luck_swing": "costs 23 energy for +/-2 luck, scored below any attack",
}
## About 5% of the pack's moves (92 today).
const MAX_EXEMPT_MOVES: int = 5
## Pack passives / held items with triggers that never fire in this run, with the reason.
const EXEMPT_TRIGGERS: Dictionary = {
	"tp_hit_contact_rare": "1% chance per contact hit",
	"tp_h_pb_knockout": "needs its holder to land a knockout while its side is outnumbered",
	"tp_h_pb_status": "its holder must be given a status; the status trigger is covered in test_cure_status.gd",
}
const MAX_EXEMPT_TRIGGERS: int = 4
## Events whose `bid` is the creature acting.
const ACTION_EVENTS: Array = [BattleEvents.MOVE_USED, BattleEvents.ITEM_USED, BattleEvents.REST,
	BattleEvents.PASS, BattleEvents.FLED, BattleEvents.SWAP_OUT, BattleEvents.DISOBEYED,
	BattleEvents.LASHED_OUT, BattleEvents.ACTION_SKIPPED, BattleEvents.CAPTURE_ATTEMPT]
## Events whose `bid` is a creature something happens to; a fainted creature receives none.
const RECEIVE_EVENTS: Array = [BattleEvents.DAMAGE, BattleEvents.HEAL, BattleEvents.STATUS_APPLIED,
	BattleEvents.STAT_STAGE]

var db: Database
var _pack_species: Array = []
var _pack_moves: Array = []
var _pack_passives: Array = []
var _pack_held: Array = []
var _all_species: Array = []


func before() -> void:
	var loaded: DataLoader.LoadResult = DataLoader.load_database("res://data", "", [PACK_ROOT])
	assert(loaded.ok(), "data/ + pack failed to load:\n" + "\n".join(loaded.errors))
	db = loaded.db
	_all_species = Array(db.ids("creatures"))
	_all_species.sort()
	for id: String in _all_species:
		if Database.is_test_content(id):
			_pack_species.append(id)
	for id: String in db.ids("moves"):
		if Database.is_test_content(id):
			_pack_moves.append(id)
	for id: String in db.ids("passives"):
		if Database.is_test_content(id):
			_pack_passives.append(id)
	for id: String in db.ids("items"):
		if Database.is_test_content(id) and db.item(id).category == "held":
			_pack_held.append(id)
	for list: Array in [_pack_moves, _pack_passives, _pack_held]:
		list.sort()


## Every run's parameters, with each creature spelled out ({species, moves, passive, held}).
## Pack content is dealt in turn through cursors, so the plan is fixed for a given pack.
func _runs() -> Array:
	var out: Array = []
	var cursor: Dictionary = {"species": 0, "moves": 0, "passive": 0, "held": 0, "slot": 0}
	for fi: int in FORMATS.size():
		var f: Array = FORMATS[fi]
		for s: int in range(1, SEED_COUNT + 1):
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = s * 101 + fi
			var level: int = 5 if s % 2 == 1 else 60
			var parties: Array = []
			for side: int in 2:
				var size: int = int(f[2]) if int(f[2]) > 0 else int(f[side]) + (s + side) % 3
				var party: Array = []
				for n: int in size:
					party.append(_plan_creature(cursor, rng, level))
				parties.append(party)
			out.append({"field": [int(f[0]), int(f[1])], "seed": s, "level": level, "parties": parties,
				"ais": [AIS[(s + fi) % AIS.size()], AIS[(s + fi + 1) % AIS.size()]]})
	return out


func _plan_creature(cursor: Dictionary, rng: RandomNumberGenerator, level: int) -> Dictionary:
	var slot: int = int(cursor.slot)
	cursor.slot = slot + 1
	var species: String
	if slot % 2 == 0:
		species = _pack_species[int(cursor.species) % _pack_species.size()]
		cursor.species = int(cursor.species) + 1
	else:
		species = _pack_species[rng.randi_range(0, _pack_species.size() - 1)]
	var moves: PackedStringArray = PackedStringArray()
	# Two creatures in three carry four pack moves dealt in turn; the rest keep their learnset.
	if slot % 3 != 2:
		for k: int in db.balance.max_moves:
			moves.append(_pack_moves[int(cursor.moves) % _pack_moves.size()])
			cursor.moves = int(cursor.moves) + 1
	var passive: String = ""
	if slot % 4 != 3:
		passive = _pack_passives[int(cursor.passive) % _pack_passives.size()]
		cursor.passive = int(cursor.passive) + 1
	var held: String = ""
	if slot % 2 == 1:
		held = _pack_held[int(cursor.held) % _pack_held.size()]
		cursor.held = int(cursor.held) + 1
	return {"species": species, "moves": moves, "passive": passive, "held": held, "level": level}


func _engine(run: Dictionary) -> BattleEngine:
	var field: Array = run.field
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(run.seed)
	var setup: BattleSetup = BattleSetup.new()
	setup.award_xp = false
	var max_active: int = maxi(int(field[0]), int(field[1]))
	for s: int in 2:
		var party: Array = []
		for plan: Dictionary in run.parties[s]:
			var c: CreatureInstance = CreatureInstance.create(db, plan.species, int(plan.level), plan.moves, rng)
			if str(plan.passive) != "":
				c.passive = plan.passive
			c.held_item = plan.held
			party.append(c)
		setup.add_side(party, max_active, int(field[s]), {}, run.ais[s], true)
	return BattleEngine.new(db, rng, setup)


func _tag(run: Dictionary) -> String:
	return "%dv%d(team %d/%d) seed %d L%d %s/%s" % [run.field[0], run.field[1], run.parties[0].size(),
		run.parties[1].size(), run.seed, run.level, run.ais[0], run.ais[1]]


## Plays `run` to the end, appending invariant violations to `problems`. Returns
## { history, result, fielded: Array of the participating source creatures }.
func _play(run: Dictionary, problems: Array) -> Dictionary:
	var e: BattleEngine = _engine(run)
	var tag: String = _tag(run)
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
	var fielded: Array = []
	for b: Battler in e.all_battlers():
		if b.participated:
			fielded.append(b.source)
	return {"history": history, "result": res, "fielded": fielded}


## Copy of test_simulation_invariants.gd's per-round check.
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


func _has_triggers(id: String, is_item: bool) -> bool:
	var p: PassiveDef = db.item(id).held if is_item else db.passive(id)
	return p != null and not p.triggers.is_empty()


func test_pack_simulations_keep_their_invariants_and_cover_the_pack() -> void:
	var started: int = Time.get_ticks_msec()
	var runs: Array = _runs()
	var used_moves: Dictionary = {}
	var banners: Dictionary = {}  # passive or held item id -> count
	var fielded_species: Dictionary = {}
	var fielded_passives: Dictionary = {}
	var fielded_held: Dictionary = {}
	var draws: int = 0
	for fi: int in FORMATS.size():
		var problems: Array = []
		var winners: int = 0
		var by_reason: Dictionary = {}
		for k: int in range(fi * SEED_COUNT, (fi + 1) * SEED_COUNT):
			var run: Dictionary = runs[k]
			var first: Dictionary = _play(run, problems)
			var again: Dictionary = _play(run, [])
			if JSON.stringify(first.history) != JSON.stringify(again.history):
				problems.append("%s: replay differs (%d vs %d events)" % [_tag(run), first.history.size(),
					again.history.size()])
			if int(first.result.winner) == -1:
				draws += 1
			else:
				winners += 1
			by_reason[str(first.result.reason)] = int(by_reason.get(str(first.result.reason), 0)) + 1
			for ev: Dictionary in first.history:
				if ev.type == BattleEvents.MOVE_USED:
					used_moves[str(ev.move)] = true
				elif ev.type == BattleEvents.PASSIVE_TRIGGERED:
					var id: String = str(ev.item) if str(ev.get("item", "")) != "" else str(ev.passive)
					banners[id] = int(banners.get(id, 0)) + 1
			# Coverage reads the SOURCE creatures (Battler.source, untouched until commit(), which
			# never runs here), so a consumed held item still counts as fielded with its holder.
			for c: CreatureInstance in first.fielded:
				fielded_species[c.species] = true
				fielded_passives[Passives.active_id(c)] = true
				fielded_held[c.held_item] = true
		var f: Array = FORMATS[fi]
		if winners == 0:
			problems.append("%dv%d: no battle was won outright (%s)" % [f[0], f[1], by_reason])
		print("pack %dv%d team %d: %d/%d won outright, reasons %s" % [f[0], f[1], f[2], winners, SEED_COUNT,
			by_reason])
		assert_array(problems).override_failure_message("%dv%d:\n%s" % [f[0], f[1],
			"\n".join(problems.slice(0, 20))]).is_empty()

	print("pack simulations: %d draws in %d battles (cap %d%%)" % [draws, runs.size(), MAX_DRAW_PERCENT])
	assert_int(draws * 100).override_failure_message("%d of %d battles drew" % [draws, runs.size()]) \
		.is_less(MAX_DRAW_PERCENT * runs.size())

	var missing_species: Array = _pack_species.filter(func(id: String) -> bool: return not fielded_species.has(id))
	assert_array(missing_species).override_failure_message("pack creatures never fielded: %s" % [missing_species]) \
		.is_empty()
	var missing_passives: Array = _pack_passives.filter(func(id: String) -> bool: return not fielded_passives.has(id))
	assert_array(missing_passives).override_failure_message("pack passives never fielded: %s" % [missing_passives]) \
		.is_empty()
	var missing_held: Array = _pack_held.filter(func(id: String) -> bool: return not fielded_held.has(id))
	assert_array(missing_held).override_failure_message("pack held items never fielded: %s" % [missing_held]) \
		.is_empty()

	var unused_moves: Array = _pack_moves.filter(func(id: String) -> bool: return not used_moves.has(id))
	var silent: Array = []
	for id: String in _pack_passives:
		if _has_triggers(id, false) and not banners.has(id):
			silent.append(id)
	for id: String in _pack_held:
		if _has_triggers(id, true) and not banners.has(id):
			silent.append(id)
	print("pack moves never used by the AI (exempt): %s" % [unused_moves])
	print("pack triggers never fired (exempt): %s" % [silent])
	print("pack banners: %s" % [banners])
	var unlisted_moves: Array = unused_moves.filter(func(id: String) -> bool: return not EXEMPT_MOVES.has(id))
	assert_array(unlisted_moves).override_failure_message("unused pack moves missing from EXEMPT_MOVES: %s" \
		% [unlisted_moves]).is_empty()
	var unlisted_triggers: Array = silent.filter(func(id: String) -> bool: return not EXEMPT_TRIGGERS.has(id))
	assert_array(unlisted_triggers).override_failure_message("silent pack triggers missing from EXEMPT_TRIGGERS: %s" \
		% [unlisted_triggers]).is_empty()
	assert_int(EXEMPT_MOVES.size()).is_less_equal(MAX_EXEMPT_MOVES)
	assert_int(EXEMPT_TRIGGERS.size()).is_less_equal(MAX_EXEMPT_TRIGGERS)
	print("Pack simulations: %d battles x2 in %d ms" % [runs.size(), Time.get_ticks_msec() - started])


func test_the_plan_deals_out_the_whole_pack() -> void:
	# The coverage above is meaningful only if the plan puts every pack entry on some team.
	var planned: Dictionary = {}
	for run: Dictionary in _runs():
		for party: Array in run.parties:
			for plan: Dictionary in party:
				planned[plan.species] = true
				planned[plan.passive] = true
				planned[plan.held] = true
				for m: String in plan.moves:
					planned[m] = true
	for list: Array in [_pack_species, _pack_moves, _pack_passives, _pack_held]:
		for id: String in list:
			assert_bool(planned.has(id)).override_failure_message("%s never planned" % id).is_true()
	for list: Array in [_pack_species, _pack_moves, _pack_passives, _pack_held]:
		assert_int(list.size()).is_greater(0)


func test_the_same_plan_with_a_new_seed_changes_the_battle() -> void:
	# Replays above match because the seed matches, not because the log ignores the RNG.
	var run: Dictionary = _runs()[SEED_COUNT * 2 + 1]
	var other: Dictionary = run.duplicate(true)
	other.seed = int(run.seed) + 1000
	var a: String = JSON.stringify(_play(run, []).history)
	var b: String = JSON.stringify(_play(other, []).history)
	assert_str(a).is_not_equal(b)


func test_base_data_without_the_pack_has_no_test_content() -> void:
	var base: DataLoader.LoadResult = DataLoader.load_database("res://data")
	assert_array(Array(base.errors)).is_empty()
	# Exactly the non-tp_ part of the data/ + pack database the simulations use.
	for cat: String in ["creatures", "moves", "items", "passives", "tamers", "encounters"]:
		var expected: Array = Array(db.ids(cat)).filter(func(id: String) -> bool:
			return not Database.is_test_content(id))
		assert_array(Array(base.db.ids(cat))).override_failure_message(cat).contains_exactly_in_any_order(expected)
	assert_int(base.db.count("creatures")).is_greater(0)
	for cat: String in ["creatures", "moves", "items", "passives", "tamers", "encounters"]:
		for id: String in base.db.ids(cat):
			assert_bool(Database.is_test_content(id)).override_failure_message("%s %s" % [cat, id]).is_false()
