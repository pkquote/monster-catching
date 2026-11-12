extends GdUnitTestSuite
## A one_ally pick that is no longer legal (a fainted ally) is replaced with a random standing ally,
## the user included, the way one_enemy and two_enemies re-target. A legal pick is kept and draws no RNG.

var db: Database


func before() -> void:
	db = FixtureDB.build()


## Three allies in a 3v1; the middle one (slot 1) has fainted. Returns [engine, user, fainted, other].
func _case(seed_value: int) -> Array:
	var mine := FixtureDB.team(db, 3, "tank", ["hit"])
	var e: BattleEngine = FixtureDB.engine(db, mine, FixtureDB.team(db, 1, "tank", ["hit"]), 3, 1, seed_value)
	var user: Battler = e.sides[0].slots[0]
	var fainted: Battler = e.sides[0].slots[1]
	var other: Battler = e.sides[0].slots[2]
	FixtureDB.knock_out(e, [fainted])
	return [e, user, fainted, other]


func test_a_fainted_pick_becomes_a_random_standing_ally() -> void:
	var seen := {}
	for s: int in range(1, 41):
		var c := _case(s)
		var e: BattleEngine = c[0]
		var got := e.resolve_targets(c[1], "one_ally", (c[2] as Battler).bid)
		assert_int(got.size()).is_equal(1)
		assert_bool(got[0].alive() and got[0].active).is_true()
		seen[got[0].bid] = true
	# Both standing allies (the user and the other one) come up across seeds.
	assert_int(seen.size()).is_equal(2)


func test_a_missing_or_foe_pick_is_replaced_too() -> void:
	var c := _case(3)
	var e: BattleEngine = c[0]
	var foe: Battler = e.sides[1].slots[0]
	for pick: int in [999, -1, foe.bid]:
		var got := e.resolve_targets(c[1], "one_ally", pick)
		assert_int(got.size()).is_equal(1)
		assert_int(got[0].side).is_equal(0)


func test_a_legal_pick_is_kept_and_draws_no_rng() -> void:
	var c := _case(5)
	var e: BattleEngine = c[0]
	for who: Battler in [c[1], c[3]]:
		var before_state := e.rng.state
		var got := e.resolve_targets(c[1], "one_ally", who.bid)
		assert_array(got).contains_exactly([who])
		assert_int(e.rng.state).is_equal(before_state)


func test_without_random_the_user_is_the_fallback() -> void:
	# The AI only ever offers legal picks; this pins what the no-random path does for an illegal one.
	var c := _case(5)
	var e: BattleEngine = c[0]
	var got := e.resolve_targets(c[1], "one_ally", (c[2] as Battler).bid, -1, false)
	assert_array(got).contains_exactly([c[1]])


func test_a_move_aimed_at_a_fainted_ally_lands_on_a_standing_one() -> void:
	var raw := FixtureDB.raw()
	raw.add_entry("moves", FixtureDB.move("cheer", "neutral", "status", 0, 100, "one_ally",
		[{"op": "stat_stage", "stat": "patk", "stages": 1}], {"always_hits": true}))
	var data := Database.from_raw(raw)
	var hit_other := false
	for s: int in range(1, 41):
		var mine := FixtureDB.team(data, 3, "tank", ["cheer"])
		var e: BattleEngine = FixtureDB.engine(data, mine, FixtureDB.team(data, 1, "tank", ["hit"]), 3, 1, s)
		var user: Battler = e.sides[0].slots[0]
		var fainted: Battler = e.sides[0].slots[1]
		var other: Battler = e.sides[0].slots[2]
		FixtureDB.knock_out(e, [fainted])
		var events := e.resolve_round([BattleAction.use_move(user.bid, "cheer", fainted.bid),
			BattleAction.use_move(other.bid, "hit", e.sides[1].slots[0].bid),
			BattleAction.use_move(e.sides[1].slots[0].bid, "hit", user.bid)])
		# Only the user's Cheer raises a stage, so this is where it landed.
		var stages := FixtureDB.events_of(events, BattleEvents.STAT_STAGE)
		assert_int(stages.size()).is_equal(1)
		assert_bool(stages[0].bid == user.bid or stages[0].bid == other.bid).is_true()
		hit_other = hit_other or stages[0].bid == other.bid
	assert_bool(hit_other).is_true()
