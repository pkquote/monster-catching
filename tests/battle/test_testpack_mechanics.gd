extends GdUnitTestSuite
## Per-mechanic battle checks on the test content pack (spec 2026-11-05-test-content-pack-design.md section 4).
## Every test builds the smallest battle it needs from named pack creatures and tp_ moves on the real
## Database loaded with data_testpack/, runs scripted rounds with BattleAction objects and pins one
## documented outcome from documentation/battle-engine.md.
##
## Determinism: a fixed seed, passives cleared unless a test is about one, XP off, and in before() the
## in-memory balance's Resolve caps are set to 0 so no status or foe stat drop is resisted and no
## knockout blow is endured (Resolve is not what these tests pin). Moves below 100 accuracy are used
## only where a miss doesn't matter or the user's accuracy stage is raised so the roll can't fail.

const PACK_ROOT: String = "res://data_testpack"
const SEED: int = 7
## Pack creatures used throughout.
const WALL: String = "tp_water_wall"
const PLAIN: String = "tp_neutral_plain"
const CANNON: String = "tp_fire_glass_cannon"
const MAX_STATS: String = "tp_earth_max_stats"
const SPEEDSTER: String = "tp_grass_speedster"
## Stat stage limit (documentation/battle-engine.md, Formulas: "Stat stages (-6...+6)").
const DOC_STAGE_LIMIT: int = 6
## Move ops the engine really runs from a move, and the test(s) that pin each one. A new move-legal op
## fails test_every_move_legal_op_has_a_mechanic_test until it gets a test here.
const OP_TESTS: Dictionary = {
	"damage": ["test_damage_op_deals_formula_damage", "test_damage_is_clamped_to_remaining_hp"],
	"damage_fraction": ["test_damage_fraction_takes_a_share_of_max_hp"],
	"heal": ["test_heal_restores_a_fraction_of_max_hp"],
	"restore_energy": ["test_restore_energy_restores_a_fraction_of_max_energy"],
	"stat_stage": ["test_stat_stage_applied_and_clamped_at_the_engine_limit"],
	"apply_status": ["test_apply_status_with_chance_100_always_lands"],
	"cure_status": ["test_cure_status_clears_a_status_and_ignores_a_mismatch"],
	"apply_field_state": ["test_apply_field_state_stacks_and_clamps_to_max_stacks"],
	"remove_field_state": ["test_remove_field_state_clears_one_or_all_states"],
	"bonus_if_field": ["test_bonus_if_field_with_consume_multiplies_then_cashes_in",
		"test_bonus_if_field_without_consume_keeps_the_state"],
}
## Item-only: needs an item context (Task 3 notes).
const ITEM_ONLY_OPS: PackedStringArray = ["capture"]

var _db: Database
var _start_events: Array = []


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "", [PACK_ROOT])
	assert_array(Array(result.errors)).is_empty()
	_db = result.db
	_db.balance.resolve_cfg["resist_cap"] = 0.0
	_db.balance.resolve_cfg["endure_cap"] = 0.0


# --- helpers ------------------------------------------------------------------------

func _make(species: String, level: int, moves: Array, passive: String = "", held: String = "") -> CreatureInstance:
	assert_object(_db.creature(species)).override_failure_message("unknown species " + species).is_not_null()
	for mid: String in moves:
		assert_object(_db.move(mid)).override_failure_message("unknown move " + mid).is_not_null()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var c: CreatureInstance = CreatureInstance.create(_db, species, level, PackedStringArray(moves), rng)
	c.passive = passive
	c.held_item = held
	return c


## Both sides test-controlled. `field0`/`field1` creatures are placed; the rest are the bench.
func _engine(party0: Array, party1: Array, field0: int = 1, field1: int = 1) -> BattleEngine:
	var setup: BattleSetup = BattleSetup.new()
	var max_active: int = maxi(field0, field1)
	setup.add_side(party0, max_active, field0)
	setup.add_side(party1, max_active, field1)
	setup.award_xp = false
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var e: BattleEngine = BattleEngine.new(_db, rng, setup)
	_start_events = e.start()
	return e


func _first(e: BattleEngine, side: int) -> Battler:
	return e.sides[side].active()[0]


## One round: `given` actions, every other test-controlled action slot passes.
func _round(e: BattleEngine, given: Array) -> Array:
	var chosen: Array = given.duplicate()
	var used: Dictionary = {}
	for a: BattleAction in given:
		used[a.actor] = int(used.get(a.actor, 0)) + 1
	for side: BattleSide in e.sides:
		if side.is_ai():
			continue
		for bid: int in e.actions_needed(side.index):
			if int(used.get(bid, 0)) > 0:
				used[bid] = int(used[bid]) - 1
			else:
				chosen.append(BattleAction.pass_turn(bid))
	return e.resolve_round(chosen)


func _refill(e: BattleEngine) -> void:
	for b: Battler in e.all_battlers():
		if b.alive():
			b.creature.hp = b.creature.max_hp(_db)
			b.creature.energy = b.creature.max_energy(_db)


func _of(events: Array, type: String, bid: int = -2) -> Array:
	var out: Array = []
	for ev: Dictionary in events:
		if ev.type == type and (bid == -2 or int(ev.get("bid", -1)) == bid):
			out.append(ev)
	return out


func _index(events: Array, type: String, bid: int = -2, from: int = 0) -> int:
	for i: int in range(from, events.size()):
		var ev: Dictionary = events[i]
		if ev.type == type and (bid == -2 or int(ev.get("bid", -1)) == bid):
			return i
	return -1


func _move_order(events: Array) -> Array[int]:
	var out: Array[int] = []
	for ev: Dictionary in _of(events, BattleEvents.MOVE_USED):
		out.append(int(ev.bid))
	return out


# --- guard: every move-legal op has a test -----------------------------------------------

func test_every_move_legal_op_has_a_mechanic_test() -> void:
	var passive_script: Script = EffectOps.get_op("stat_mod").get_script()
	var run_ops: Array = []
	for op: String in DataSchemas.EFFECT_OPS:
		if op in DataSchemas.FIELD_OPS or op in ITEM_ONLY_OPS:
			continue
		if EffectOps.get_op(op).get_script() == passive_script:
			continue
		run_ops.append(op)
	assert_int(run_ops.size()).is_equal(10)
	assert_array(run_ops).contains_exactly_in_any_order(OP_TESTS.keys())
	for op: String in OP_TESTS:
		var names: Array = OP_TESTS[op]
		assert_int(names.size()).is_greater(0)
		for fn: String in names:
			assert_bool(has_method(fn)).override_failure_message("missing test " + fn).is_true()


# --- damage ----------------------------------------------------------------------------

func test_damage_op_deals_formula_damage() -> void:
	var move_id: String = "tp_hit_neutral_physical_prio_minus3"
	var e: BattleEngine = _engine([_make(PLAIN, 30, [move_id])], [_make(WALL, 30, [move_id])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	var m: MoveDef = _db.move(move_id)
	var atk: float = BattleMath.effective_stat(e, me, "patk")
	var def: float = BattleMath.effective_stat(e, foe, "pdef")
	# ((2*Lv/5 + 2) * power * A/D) / 50 + 2, x same-type bonus (neutral user, neutral move) x matchup x roll.
	var base: float = ((2.0 * 30.0 / 5.0 + 2.0) * float(m.power) * atk / maxf(1.0, def)) / 50.0 + 2.0
	var type_mult: float = _db.type_multiplier("neutral", foe.creature.species_def(_db).types)
	var mult: float = float(_db.balance.stab) * type_mult
	var hp_before: int = foe.hp()
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, move_id, foe.bid)])
	var hits: Array = _of(evs, BattleEvents.DAMAGE, foe.bid)
	assert_int(hits.size()).is_equal(1)
	var hit: Dictionary = hits[0]
	assert_int(int(hit.amount)).is_between(maxi(1, int(base * mult * 0.85)), maxi(1, int(base * mult)))
	assert_int(int(hit.by)).is_equal(me.bid)
	assert_str(str(hit.damage_type)).is_equal("neutral")
	assert_float(float(hit.effectiveness)).is_equal(type_mult)
	assert_int(foe.hp()).is_equal(hp_before - int(hit.amount))
	assert_int(int(hit.hp)).is_equal(foe.hp())


func test_damage_is_clamped_to_remaining_hp() -> void:
	var e: BattleEngine = _engine([_make(CANNON, 50, ["tp_power_max"])], [_make(PLAIN, 50, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	foe.creature.hp = 3
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_power_max", foe.bid)])
	var hits: Array = _of(evs, BattleEvents.DAMAGE, foe.bid)
	assert_int(hits.size()).is_equal(1)
	assert_int(int(hits[0].amount)).is_equal(3)
	assert_int(foe.hp()).is_equal(0)
	assert_int(_of(evs, BattleEvents.FAINT, foe.bid).size()).is_equal(1)
	assert_bool(e.is_over()).is_true()
	assert_int(int(e.result().winner)).is_equal(0)


func test_damage_fraction_takes_a_share_of_max_hp() -> void:
	# Full: 100% of max HP from full HP knocks out.
	var e: BattleEngine = _engine([_make(MAX_STATS, 20, ["tp_damage_fraction_full"])], [_make(WALL, 50, ["tp_power_min"])])
	var foe: Battler = _first(e, 1)
	var max_hp: int = foe.creature.max_hp(_db)
	assert_int(foe.hp()).is_equal(max_hp)
	var evs: Array = _round(e, [BattleAction.use_move(_first(e, 0).bid, "tp_damage_fraction_full", foe.bid)])
	var hits: Array = _of(evs, BattleEvents.DAMAGE, foe.bid)
	assert_int(hits.size()).is_equal(1)
	assert_int(int(hits[0].amount)).is_equal(max_hp)
	assert_int(int(hits[0].by)).is_equal(-1)
	assert_int(foe.hp()).is_equal(0)
	# Small: 2% of max HP (at least 1) on every foe.
	var e2: BattleEngine = _engine([_make(MAX_STATS, 20, ["tp_damage_fraction_small"])], [_make(WALL, 50, ["tp_power_min"])])
	var foe2: Battler = _first(e2, 1)
	var max2: int = foe2.creature.max_hp(_db)
	var evs2: Array = _round(e2, [BattleAction.use_move(_first(e2, 0).bid, "tp_damage_fraction_small")])
	var hits2: Array = _of(evs2, BattleEvents.DAMAGE, foe2.bid)
	assert_int(hits2.size()).is_equal(1)
	assert_int(int(hits2[0].amount)).is_equal(maxi(1, int(max2 * 0.02)))
	assert_int(foe2.hp()).is_equal(max2 - maxi(1, int(max2 * 0.02)))


# --- heal and energy -------------------------------------------------------------------

func test_heal_restores_a_fraction_of_max_hp() -> void:
	var e: BattleEngine = _engine([_make(WALL, 50, ["tp_heal_self_full", "tp_heal_ally_small"])],
		[_make(WALL, 50, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var max_hp: int = me.creature.max_hp(_db)
	me.creature.hp = 1
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_heal_self_full")])
	var heals: Array = _of(evs, BattleEvents.HEAL, me.bid)
	assert_int(heals.size()).is_equal(1)
	assert_int(int(heals[0].amount)).is_equal(max_hp - 1)
	assert_int(me.hp()).is_equal(max_hp)
	# At full HP the heal is clamped to 0.
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_heal_self_full")])
	heals = _of(evs, BattleEvents.HEAL, me.bid)
	assert_int(heals.size()).is_equal(1)
	assert_int(int(heals[0].amount)).is_equal(0)
	# 5% of max HP on one ally (in 1v1 the user itself).
	me.creature.hp = max_hp / 2
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_heal_ally_small", me.bid)])
	heals = _of(evs, BattleEvents.HEAL, me.bid)
	assert_int(heals.size()).is_equal(1)
	assert_int(int(heals[0].amount)).is_equal(maxi(1, roundi(max_hp * 0.05)))
	assert_int(me.hp()).is_equal(max_hp / 2 + maxi(1, roundi(max_hp * 0.05)))


func test_restore_energy_restores_a_fraction_of_max_energy() -> void:
	var e: BattleEngine = _engine([_make(WALL, 50, ["tp_restore_energy_full_self", "tp_restore_energy_small_allies"])],
		[_make(WALL, 50, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var max_e: int = me.creature.max_energy(_db)
	me.creature.energy = 0
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_restore_energy_full_self")])
	var gains: Array = _of(evs, BattleEvents.ENERGY, me.bid)
	assert_int(gains.size()).is_equal(1)  # cost 0: no payment event
	assert_int(int(gains[0].change)).is_equal(max_e)
	assert_int(me.energy()).is_equal(max_e)
	# 10% to all allies after paying its cost of 2.
	me.creature.energy = 2
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_restore_energy_small_allies")])
	gains = _of(evs, BattleEvents.ENERGY, me.bid)
	assert_int(gains.size()).is_equal(2)
	assert_int(int(gains[0].change)).is_equal(-2)
	assert_int(int(gains[1].change)).is_equal(maxi(1, roundi(max_e * 0.1)))
	assert_int(me.energy()).is_equal(maxi(1, roundi(max_e * 0.1)))


func test_energy_cost_is_paid_and_an_unaffordable_move_is_rejected() -> void:
	var moves: Array = ["tp_hit_grass_special", "tp_power_max", "tp_power_min"]
	var e: BattleEngine = _engine([_make(WALL, 50, moves)], [_make(WALL, 50, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	var before: int = me.energy()
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_hit_grass_special", foe.bid)])
	var paid: Array = _of(evs, BattleEvents.ENERGY, me.bid)
	assert_int(paid.size()).is_equal(1)
	assert_int(int(paid[0].change)).is_equal(-_db.move("tp_hit_grass_special").cost)
	assert_int(me.energy()).is_equal(before - 4)
	# A free move emits no energy event.
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_power_min", foe.bid)])
	assert_array(_of(evs, BattleEvents.ENERGY, me.bid)).is_empty()
	assert_int(_of(evs, BattleEvents.MOVE_USED, me.bid).size()).is_equal(1)
	# Cost 30 with 29 energy: rejected, nothing spent, the move never runs.
	assert_int(_db.move("tp_power_max").cost).is_equal(30)
	me.creature.energy = 29
	assert_bool(Array(e.usable_moves(me.bid)).has("tp_power_max")).is_false()
	assert_bool(Array(e.usable_moves(me.bid)).has(e.fallback_move())).is_true()
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_power_max", foe.bid)])
	var invalid: Array = _of(evs, BattleEvents.ACTION_INVALID, me.bid)
	assert_int(invalid.size()).is_equal(1)
	assert_str(str(invalid[0].reason)).is_equal("no_energy")
	assert_array(_of(evs, BattleEvents.MOVE_USED, me.bid)).is_empty()
	assert_array(_of(evs, BattleEvents.DAMAGE, foe.bid)).is_empty()
	assert_int(me.energy()).is_equal(29)


# --- stat stages and statuses ------------------------------------------------------------

func test_cure_status_clears_a_status_and_ignores_a_mismatch() -> void:
	var e: BattleEngine = _engine([_make(PLAIN, 30, ["tp_purify"])], [_make(PLAIN, 30, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	me.creature.status = "shock"
	me.status_turns = 3
	assert_bool(e.cure_status(me, "burn")).is_false()
	assert_str(me.status()).is_equal("shock")
	me.creature.status = "burn"
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_purify", me.bid)])
	var ended: Array = _of(evs, BattleEvents.STATUS_ENDED, me.bid)
	assert_int(ended.size()).is_equal(1)
	assert_bool(bool(ended[0].cured)).is_true()
	assert_str(me.status()).is_equal("")
	# Nothing to cure: no event.
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_purify", me.bid)])
	assert_int(_of(evs, BattleEvents.STATUS_ENDED).size()).is_equal(0)


func test_status_trigger_berry_cures_the_status_it_was_given() -> void:
	var e: BattleEngine = _engine([_make(PLAIN, 30, ["tp_power_min"], "", "tp_clear_berry")],
		[_make(PLAIN, 30, ["tp_inflict_burn"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	var evs: Array = _round(e, [BattleAction.use_move(foe.bid, "tp_inflict_burn", me.bid)])
	assert_int(_of(evs, BattleEvents.STATUS_APPLIED, me.bid).size()).is_equal(1)
	assert_str(me.status()).is_equal("")
	assert_str(me.creature.held_item).is_equal("")

func test_stat_stage_applied_and_clamped_at_the_engine_limit() -> void:
	var e: BattleEngine = _engine([_make(PLAIN, 30, ["tp_stage_patk_swing"])], [_make(PLAIN, 30, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	var raw_me: float = BattleMath.effective_stat(e, me, "patk")
	var raw_foe: float = BattleMath.effective_stat(e, foe, "patk")
	# +3 self / -3 foe per use: 3, 6, then clamped at the documented +-6 (change 0).
	var expect_stage: Array[int] = [3, 6, 6]
	var expect_change: Array[int] = [3, 3, 0]
	for i: int in expect_stage.size():
		var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_stage_patk_swing", foe.bid)])
		var mine: Array = _of(evs, BattleEvents.STAT_STAGE, me.bid)
		var theirs: Array = _of(evs, BattleEvents.STAT_STAGE, foe.bid)
		assert_int(mine.size()).is_equal(1)
		assert_int(theirs.size()).is_equal(1)
		assert_str(str(mine[0].stat)).is_equal("patk")
		assert_int(int(mine[0].change)).is_equal(expect_change[i])
		assert_int(int(mine[0].stage)).is_equal(expect_stage[i])
		assert_int(int(theirs[0].change)).is_equal(-expect_change[i])
		assert_int(int(theirs[0].stage)).is_equal(-expect_stage[i])
	assert_int(me.stages["patk"]).is_equal(DOC_STAGE_LIMIT)
	assert_int(foe.stages["patk"]).is_equal(-DOC_STAGE_LIMIT)
	# Stage multipliers: (2+6)/2 = 4 and 2/(2+6) = 0.25.
	assert_float(BattleMath.effective_stat(e, me, "patk") / raw_me).is_equal_approx(4.0, 0.0001)
	assert_float(BattleMath.effective_stat(e, foe, "patk") / raw_foe).is_equal_approx(0.25, 0.0001)


func test_apply_status_with_chance_100_always_lands() -> void:
	var e: BattleEngine = _engine([_make(PLAIN, 30, ["tp_inflict_burn"])], [_make(WALL, 50, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	var max_hp: int = foe.creature.max_hp(_db)
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_inflict_burn", foe.bid)])
	var applied: Array = _of(evs, BattleEvents.STATUS_APPLIED, foe.bid)
	assert_int(applied.size()).is_equal(1)
	assert_str(str(applied[0].status)).is_equal("burn")
	assert_int(int(applied[0].turns)).is_equal(_db.status("burn").turns)
	assert_str(foe.status()).is_equal("burn")
	# Burn ticks at end of round: 1/16 of max HP, from nobody.
	var ticks: Array = _of(evs, BattleEvents.DAMAGE, foe.bid)
	assert_int(ticks.size()).is_equal(1)
	assert_int(int(ticks[0].amount)).is_equal(maxi(1, int(max_hp * 0.0625)))
	assert_int(int(ticks[0].by)).is_equal(-1)
	# One status at a time: a second one fails.
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_inflict_burn", foe.bid)])
	var failed: Array = _of(evs, BattleEvents.STATUS_FAILED, foe.bid)
	assert_int(failed.size()).is_equal(1)
	assert_str(str(failed[0].has)).is_equal("burn")
	# A damaging move with chance 100 lands its status every time too.
	var e2: BattleEngine = _engine([_make(PLAIN, 30, ["tp_hit_chill_chance_100"])], [_make(WALL, 50, ["tp_power_min"])])
	var foe2: Battler = _first(e2, 1)
	var evs2: Array = _round(e2, [BattleAction.use_move(_first(e2, 0).bid, "tp_hit_chill_chance_100", foe2.bid)])
	assert_int(_of(evs2, BattleEvents.DAMAGE, foe2.bid).size()).is_equal(1)
	assert_int(_of(evs2, BattleEvents.STATUS_APPLIED, foe2.bid).size()).is_equal(1)
	assert_str(foe2.status()).is_equal("chill")


func test_skip_chance_status_cancels_some_moves_and_the_move_op_is_inert() -> void:
	var e: BattleEngine = _engine([_make(PLAIN, 30, ["tp_inflict_shock"])], [_make(PLAIN, 30, ["tp_skip_chance_in_move"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_inflict_shock", foe.bid)])
	assert_int(_of(evs, BattleEvents.STATUS_APPLIED, foe.bid).size()).is_equal(1)
	assert_str(foe.status()).is_equal("shock")
	foe.status_turns = 1000  # keep the shock for the whole sample
	var rounds: int = 40
	var skipped: int = 0
	for r: int in rounds:
		evs = _round(e, [BattleAction.use_move(foe.bid, "tp_skip_chance_in_move")])
		var skips: Array = _of(evs, BattleEvents.ACTION_SKIPPED, foe.bid)
		var used: Array = _of(evs, BattleEvents.MOVE_USED, foe.bid)
		assert_int(skips.size() + used.size()).is_equal(1)
		if skips.size() == 1:
			assert_str(str(skips[0].status)).is_equal("shock")
			skipped += 1
		# The skip_chance op inside a move does nothing when it runs.
		for t: String in [BattleEvents.STAT_STAGE, BattleEvents.STATUS_APPLIED, BattleEvents.FIELD_APPLIED,
				BattleEvents.DAMAGE, BattleEvents.ENERGY]:
			assert_array(_of(evs, t)).override_failure_message("round %d: %s" % [r, t]).is_empty()
	# Shock skips 25% of the time: some moves are cancelled, not all.
	assert_int(int(_db.status("shock").effects[0].chance)).is_equal(25)
	assert_int(skipped).is_between(1, rounds - 1)


# --- field states -------------------------------------------------------------------------

func test_apply_field_state_stacks_and_clamps_to_max_stacks() -> void:
	var moves: Array = ["tp_apply_scorched", "tp_apply_soaked", "tp_apply_overgrown"]
	var e: BattleEngine = _engine([_make(WALL, 50, moves)], [_make(WALL, 50, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var scorched: FieldStateDef = _db.field_state("scorched")
	assert_int(scorched.max_stacks).is_equal(3)
	# tp_apply_scorched asks for 5 stacks: clamped to the state's max of 3.
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_apply_scorched")])
	var applied: Array = _of(evs, BattleEvents.FIELD_APPLIED)
	assert_int(applied.size()).is_equal(1)
	assert_int(int(applied[0].side)).is_equal(1)
	assert_str(str(applied[0].state)).is_equal("scorched")
	assert_int(int(applied[0].stacks)).is_equal(3)
	assert_int(int(applied[0].turns)).is_equal(scorched.default_turns)
	assert_int(e.sides[1].field.stacks("scorched")).is_equal(3)
	assert_bool(e.sides[0].field.has("scorched")).is_false()
	# Soaked on both sides, one stack at a time up to 3, then clamped.
	var expect: Array[int] = [1, 2, 3, 3]
	for i: int in expect.size():
		evs = _round(e, [BattleAction.use_move(me.bid, "tp_apply_soaked")])
		var soaked: Array = _of(evs, BattleEvents.FIELD_APPLIED)
		assert_int(soaked.size()).is_equal(2)
		for ev: Dictionary in soaked:
			assert_str(str(ev.state)).is_equal("soaked")
			assert_int(int(ev.stacks)).is_equal(expect[i])
		assert_int(e.sides[0].field.stacks("soaked")).is_equal(expect[i])
		assert_int(e.sides[1].field.stacks("soaked")).is_equal(expect[i])
	# Explicit turns on the user's own side.
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_apply_overgrown")])
	var grown: Array = _of(evs, BattleEvents.FIELD_APPLIED)
	assert_int(grown.size()).is_equal(1)
	assert_int(int(grown[0].side)).is_equal(0)
	assert_int(int(grown[0].turns)).is_equal(10)


func test_bonus_if_field_with_consume_multiplies_then_cashes_in() -> void:
	var e: BattleEngine = _engine([_make(CANNON, 50, ["tp_cash_frosted"])], [_make(WALL, 50, ["tp_apply_frosted"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	me.stages["acc"] = 1  # 95 accuracy x 4/3: the roll can't miss
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_cash_frosted", foe.bid)])
	var plain_hits: Array = _of(evs, BattleEvents.DAMAGE, foe.bid)
	assert_int(plain_hits.size()).is_equal(1)
	var d0: int = int(plain_hits[0].amount)
	assert_int(d0).is_greater(10)
	_refill(e)
	evs = _round(e, [BattleAction.use_move(foe.bid, "tp_apply_frosted")])
	assert_bool(e.sides[1].field.has("frosted")).is_true()
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_cash_frosted", foe.bid)])
	var cashed: Array = _of(evs, BattleEvents.DAMAGE, foe.bid)
	assert_int(cashed.size()).is_equal(1)
	# x5 (rolls 0.85-1.0 on each side of the ratio).
	assert_float(float(cashed[0].amount) / float(d0)).is_between(4.0, 6.25)
	var removed: Array = _of(evs, BattleEvents.FIELD_REMOVED)
	assert_int(removed.size()).is_equal(1)
	assert_str(str(removed[0].state)).is_equal("frosted")
	assert_str(str(removed[0].reason)).is_equal("cashed_in")
	assert_int(int(removed[0].side)).is_equal(1)
	assert_int(_index(evs, BattleEvents.FIELD_REMOVED)).is_greater(_index(evs, BattleEvents.DAMAGE, foe.bid))
	assert_bool(e.sides[1].field.has("frosted")).is_false()


func test_bonus_if_field_without_consume_keeps_the_state() -> void:
	var e: BattleEngine = _engine([_make(CANNON, 50, ["tp_cash_scorched", "tp_apply_scorched"])],
		[_make(WALL, 50, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	me.stages["acc"] = 1
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_cash_scorched", foe.bid)])
	var d0: int = int(_of(evs, BattleEvents.DAMAGE, foe.bid)[0].amount)
	assert_int(d0).is_greater(10)
	_refill(e)
	_round(e, [BattleAction.use_move(me.bid, "tp_apply_scorched")])
	_refill(e)
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_cash_scorched", foe.bid)])
	var hits: Array = _of(evs, BattleEvents.DAMAGE, foe.bid)
	assert_int(hits.size()).is_equal(1)
	assert_float(float(hits[0].amount) / float(d0)).is_between(1.5 * 0.8, 1.5 / 0.8)
	assert_array(_of(evs, BattleEvents.FIELD_REMOVED)).is_empty()
	assert_bool(e.sides[1].field.has("scorched")).is_true()


func test_remove_field_state_clears_one_or_all_states() -> void:
	var moves: Array = ["tp_apply_soaked", "tp_clear_soaked", "tp_clear_all_fields"]
	var e: BattleEngine = _engine([_make(WALL, 50, moves)], [_make(WALL, 50, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	_round(e, [BattleAction.use_move(me.bid, "tp_apply_soaked")])
	assert_bool(e.sides[0].field.has("soaked")).is_true()
	assert_bool(e.sides[1].field.has("soaked")).is_true()
	# Own side only.
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_clear_soaked")])
	var removed: Array = _of(evs, BattleEvents.FIELD_REMOVED)
	assert_int(removed.size()).is_equal(1)
	assert_int(int(removed[0].side)).is_equal(0)
	assert_str(str(removed[0].reason)).is_equal("cleared")
	assert_bool(e.sides[0].field.has("soaked")).is_false()
	assert_bool(e.sides[1].field.has("soaked")).is_true()
	# Removing a state that isn't there emits nothing.
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_clear_soaked")])
	assert_array(_of(evs, BattleEvents.FIELD_REMOVED)).is_empty()
	# Everything on both sides.
	evs = _round(e, [BattleAction.use_move(me.bid, "tp_clear_all_fields")])
	removed = _of(evs, BattleEvents.FIELD_REMOVED)
	assert_int(removed.size()).is_equal(1)
	assert_int(int(removed[0].side)).is_equal(1)
	assert_int(e.sides[0].field.size()).is_equal(0)
	assert_int(e.sides[1].field.size()).is_equal(0)


# --- order, accuracy, targets -------------------------------------------------------------

func test_priority_orders_moves_before_speed() -> void:
	var slow: CreatureInstance = _make(WALL, 50, ["tp_hit_earth_physical_prio_plus3", "tp_power_min",
		"tp_hit_neutral_physical_prio_minus3"])
	var fast: CreatureInstance = _make(SPEEDSTER, 50, ["tp_hit_neutral_physical_prio_minus3", "tp_power_min"])
	var e: BattleEngine = _engine([slow], [fast])
	var s: Battler = _first(e, 0)
	var f: Battler = _first(e, 1)
	assert_float(BattleMath.effective_stat(e, f, "spd")).is_greater(BattleMath.effective_stat(e, s, "spd"))
	# Priority +3 (slow) beats -3 (fast).
	var evs: Array = _round(e, [BattleAction.use_move(s.bid, "tp_hit_earth_physical_prio_plus3", f.bid),
		BattleAction.use_move(f.bid, "tp_hit_neutral_physical_prio_minus3", s.bid)])
	assert_array(_move_order(evs)).contains_exactly([s.bid, f.bid])
	_refill(e)
	# Equal priority: the faster creature first.
	evs = _round(e, [BattleAction.use_move(s.bid, "tp_power_min", f.bid),
		BattleAction.use_move(f.bid, "tp_power_min", s.bid)])
	assert_array(_move_order(evs)).contains_exactly([f.bid, s.bid])
	_refill(e)
	# Priority 0 beats -3 even for the slower creature.
	evs = _round(e, [BattleAction.use_move(s.bid, "tp_power_min", f.bid),
		BattleAction.use_move(f.bid, "tp_hit_neutral_physical_prio_minus3", s.bid)])
	assert_array(_move_order(evs)).contains_exactly([s.bid, f.bid])


func test_always_hits_ignores_accuracy() -> void:
	var e: BattleEngine = _engine([_make(MAX_STATS, 30, ["tp_always_hits_damage", "tp_accuracy_min"])],
		[_make(WALL, 99, ["tp_power_min"])])
	var me: Battler = _first(e, 0)
	var foe: Battler = _first(e, 1)
	me.stages["acc"] = -DOC_STAGE_LIMIT  # 50 accuracy x 3/9 would miss most of the time
	assert_float(BattleMath.hit_chance(e, me, _db.move("tp_always_hits_damage"))).is_equal(1000.0)
	var rounds: int = 10
	for r: int in rounds:
		_refill(e)
		var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_always_hits_damage", foe.bid)])
		assert_array(_of(evs, BattleEvents.MISS)).override_failure_message("round %d" % r).is_empty()
		assert_int(_of(evs, BattleEvents.DAMAGE, foe.bid).size()).is_equal(1)
	# Control: accuracy 1 without always_hits misses (1% hit chance per use).
	me.stages["acc"] = 0
	assert_float(BattleMath.hit_chance(e, me, _db.move("tp_accuracy_min"))).is_equal_approx(1.0, 0.0001)
	var misses: int = 0
	for r: int in rounds:
		_refill(e)
		var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_accuracy_min", foe.bid)])
		assert_int(_of(evs, BattleEvents.MOVE_USED, me.bid).size()).is_equal(1)
		misses += _of(evs, BattleEvents.MISS, me.bid).size()
	assert_int(misses).is_greater_equal(rounds - 2)
	# An always_hits status move with accuracy 1 lands its status.
	var e2: BattleEngine = _engine([_make(PLAIN, 30, ["tp_always_hits_status"])], [_make(WALL, 50, ["tp_power_min"])])
	var foe2: Battler = _first(e2, 1)
	var evs2: Array = _round(e2, [BattleAction.use_move(_first(e2, 0).bid, "tp_always_hits_status", foe2.bid)])
	assert_array(_of(evs2, BattleEvents.MISS)).is_empty()
	assert_str(foe2.status()).is_equal("daze")


func test_every_target_kind_selects_the_right_battlers_in_2v3() -> void:
	# kind -> [move, chosen target (index into all five), second target index].
	var cases: Dictionary = {
		"self": ["tp_heal_self_full", -1, -1],
		"one_ally": ["tp_heal_ally_small", 1, -1],
		"one_enemy": ["tp_inflict_burn", 3, -1],
		"two_enemies": ["tp_hit_two_foes", 2, 4],
		"all_allies": ["tp_restore_energy_small_allies", -1, -1],
		"all_enemies": ["tp_damage_fraction_small", -1, -1],
		"all": ["tp_hit_everyone", -1, -1],
		"own_side": ["tp_apply_overgrown", -1, -1],
		"enemy_side": ["tp_apply_scorched", -1, -1],
	}
	# Battlers: 0 user, 1 ally (side 0); 2, 3, 4 foes (side 1). Expected target indexes.
	var expected: Dictionary = {"self": [0], "one_ally": [1], "one_enemy": [3], "two_enemies": [2, 4],
		"all_allies": [0, 1], "all_enemies": [2, 3, 4], "all": [1, 2, 3, 4], "own_side": [], "enemy_side": []}
	assert_array(cases.keys()).contains_exactly_in_any_order(Array(DataSchemas.MOVE_TARGETS))
	for kind: String in cases:
		var spec: Array = cases[kind]
		var move_id: String = spec[0]
		assert_str(_db.move(move_id).target).is_equal(kind)
		var p0: Array = [_make(WALL, 50, [move_id]), _make(WALL, 50, [move_id])]
		var p1: Array = [_make(WALL, 50, ["tp_power_min"]), _make(WALL, 50, ["tp_power_min"]),
			_make(WALL, 50, ["tp_power_min"])]
		var e: BattleEngine = _engine(p0, p1, 2, 3)
		var all: Array[Battler] = e.sides[0].active() + e.sides[1].active()
		assert_int(all.size()).is_equal(5)
		var user: Battler = all[0]
		user.creature.hp = user.creature.max_hp(_db) / 2
		all[1].creature.hp = all[1].creature.max_hp(_db) / 2
		var first: int = all[int(spec[1])].bid if int(spec[1]) >= 0 else -1
		var second: int = all[int(spec[2])].bid if int(spec[2]) >= 0 else -1
		var evs: Array = _round(e, [BattleAction.use_move(user.bid, move_id, first, second)])
		var used: Array = _of(evs, BattleEvents.MOVE_USED, user.bid)
		assert_int(used.size()).override_failure_message(kind).is_equal(1)
		var want: Array = []
		for i: int in expected[kind]:
			want.append(all[i].bid)
		var got: Array = []
		for t: Variant in used[0].targets:
			got.append(int(t))
		assert_array(got).override_failure_message("%s: got %s want %s" % [kind, str(got), str(want)]) \
			.contains_exactly_in_any_order(want)
		if kind == "own_side":
			assert_int(int(used[0].side)).is_equal(0)
			assert_bool(e.sides[0].field.has("overgrown")).is_true()
			assert_bool(e.sides[1].field.has("overgrown")).is_false()
		elif kind == "enemy_side":
			assert_int(int(used[0].side)).is_equal(1)
			assert_bool(e.sides[1].field.has("scorched")).is_true()
			assert_bool(e.sides[0].field.has("scorched")).is_false()


# --- passive triggers -----------------------------------------------------------------------

func test_enter_trigger_fires_once_after_both_sides_are_placed() -> void:
	var e: BattleEngine = _engine([_make(PLAIN, 30, ["tp_power_min"], "tp_kitchen_sink")],
		[_make(PLAIN, 30, ["tp_power_min"])])
	var holder: Battler = _first(e, 0)
	var banners: Array = _of(_start_events, BattleEvents.PASSIVE_TRIGGERED)
	assert_int(banners.size()).is_equal(1)
	assert_int(int(banners[0].bid)).is_equal(holder.bid)
	assert_str(str(banners[0].passive)).is_equal("tp_kitchen_sink")
	var at: int = _index(_start_events, BattleEvents.PASSIVE_TRIGGERED)
	var last_send: int = -1
	for i: int in _start_events.size():
		if _start_events[i].type == BattleEvents.SEND_OUT:
			last_send = i
	assert_int(last_send).is_greater(0)
	assert_int(at).is_greater(last_send)
	var stage: Dictionary = _start_events[at + 1]
	assert_str(str(stage.type)).is_equal(BattleEvents.STAT_STAGE)
	assert_str(str(stage.stat)).is_equal("luck")
	assert_int(int(stage.change)).is_equal(1)


func test_hit_trigger_fires_once_on_a_contact_hit_against_the_attacker() -> void:
	var atk_moves: Array = ["tp_hit_neutral_physical_prio_minus3", "tp_accuracy_max"]
	var e: BattleEngine = _engine([_make(PLAIN, 30, atk_moves)], [_make(WALL, 50, ["tp_power_min"], "tp_kitchen_sink")])
	var attacker: Battler = _first(e, 0)
	var holder: Battler = _first(e, 1)
	var evs: Array = _round(e, [BattleAction.use_move(attacker.bid, "tp_hit_neutral_physical_prio_minus3", holder.bid)])
	var banners: Array = _of(evs, BattleEvents.PASSIVE_TRIGGERED)
	assert_int(banners.size()).is_equal(1)
	assert_int(int(banners[0].bid)).is_equal(holder.bid)
	var hit_at: int = _index(evs, BattleEvents.DAMAGE, holder.bid)
	var banner_at: int = _index(evs, BattleEvents.PASSIVE_TRIGGERED)
	assert_int(banner_at).is_greater(hit_at)
	var drop: Array = _of(evs, BattleEvents.STAT_STAGE, attacker.bid)
	assert_int(drop.size()).is_equal(1)
	assert_str(str(drop[0].stat)).is_equal("spd")
	assert_int(int(drop[0].change)).is_equal(-1)
	assert_int(_index(evs, BattleEvents.STAT_STAGE, attacker.bid)).is_greater(banner_at)
	# A special (non-contact) hit doesn't set off the contact trigger.
	evs = _round(e, [BattleAction.use_move(attacker.bid, "tp_accuracy_max", holder.bid)])
	assert_int(_of(evs, BattleEvents.DAMAGE, holder.bid).size()).is_equal(1)
	assert_array(_of(evs, BattleEvents.PASSIVE_TRIGGERED)).is_empty()


func test_round_end_trigger_fires_once_after_the_actions() -> void:
	var e: BattleEngine = _engine([_make(WALL, 50, ["tp_power_min"], "tp_round_end_when_hp")],
		[_make(WALL, 50, ["tp_power_min"])])
	var holder: Battler = _first(e, 0)
	var max_hp: int = holder.creature.max_hp(_db)
	# Above half HP the `when` fails: nothing.
	var evs: Array = _round(e, [])
	assert_array(_of(evs, BattleEvents.PASSIVE_TRIGGERED)).is_empty()
	holder.creature.hp = max_hp / 4
	evs = _round(e, [])
	var banners: Array = _of(evs, BattleEvents.PASSIVE_TRIGGERED)
	assert_int(banners.size()).is_equal(1)
	assert_int(int(banners[0].bid)).is_equal(holder.bid)
	assert_str(str(banners[0].passive)).is_equal("tp_round_end_when_hp")
	var banner_at: int = _index(evs, BattleEvents.PASSIVE_TRIGGERED)
	for i: int in evs.size():
		if evs[i].type == BattleEvents.PASS:
			assert_int(banner_at).is_greater(i)
	var heals: Array = _of(evs, BattleEvents.HEAL, holder.bid)
	assert_int(heals.size()).is_equal(1)
	assert_int(int(heals[0].amount)).is_equal(roundi(max_hp * 0.25))


func test_knockout_trigger_fires_once_after_the_faint() -> void:
	var holder_c: CreatureInstance = _make(PLAIN, 30, ["tp_hit_neutral_physical_prio_minus3"], "tp_knockout_boost")
	var e: BattleEngine = _engine([holder_c], [_make(PLAIN, 30, ["tp_power_min"]), _make(PLAIN, 30, ["tp_power_min"])])
	var holder: Battler = _first(e, 0)
	var victim: Battler = _first(e, 1)
	victim.creature.hp = 1
	var evs: Array = _round(e, [BattleAction.use_move(holder.bid, "tp_hit_neutral_physical_prio_minus3", victim.bid)])
	assert_bool(e.is_over()).is_false()
	var faint_at: int = _index(evs, BattleEvents.FAINT, victim.bid)
	assert_int(faint_at).is_greater(-1)
	var banners: Array = _of(evs, BattleEvents.PASSIVE_TRIGGERED)
	assert_int(banners.size()).is_equal(1)
	assert_int(int(banners[0].bid)).is_equal(holder.bid)
	assert_str(str(banners[0].passive)).is_equal("tp_knockout_boost")
	assert_int(_index(evs, BattleEvents.PASSIVE_TRIGGERED)).is_greater(faint_at)
	var boost: Array = _of(evs, BattleEvents.STAT_STAGE, holder.bid)
	assert_int(boost.size()).is_equal(1)
	assert_str(str(boost[0].stat)).is_equal("spd")
	assert_int(int(boost[0].change)).is_equal(3)


func test_faint_trigger_fires_once_on_the_killer() -> void:
	var e: BattleEngine = _engine([_make(WALL, 50, ["tp_hit_neutral_physical_prio_minus3"])],
		[_make(PLAIN, 30, ["tp_power_min"], "tp_faint_curse"), _make(PLAIN, 30, ["tp_power_min"])])
	var killer: Battler = _first(e, 0)
	var holder: Battler = _first(e, 1)
	holder.creature.hp = 1
	var evs: Array = _round(e, [BattleAction.use_move(killer.bid, "tp_hit_neutral_physical_prio_minus3", holder.bid)])
	assert_bool(e.is_over()).is_false()
	var faint_at: int = _index(evs, BattleEvents.FAINT, holder.bid)
	assert_int(faint_at).is_greater(-1)
	var banners: Array = _of(evs, BattleEvents.PASSIVE_TRIGGERED)
	assert_int(banners.size()).is_equal(1)
	assert_int(int(banners[0].bid)).is_equal(holder.bid)
	assert_str(str(banners[0].passive)).is_equal("tp_faint_curse")
	assert_int(_index(evs, BattleEvents.PASSIVE_TRIGGERED)).is_greater(faint_at)
	assert_int(_of(evs, BattleEvents.STATUS_APPLIED, killer.bid).size()).is_equal(1)
	assert_str(killer.status()).is_equal("burn")
	# damage_fraction 0.1 on the killer (the burn tick at round end is a second damage event).
	var hurt: Array = _of(evs, BattleEvents.DAMAGE, killer.bid)
	assert_int(hurt.size()).is_greater(0)
	assert_int(int(hurt[0].amount)).is_equal(maxi(1, int(killer.creature.max_hp(_db) * 0.1)))


func test_every_trigger_kind_has_a_test() -> void:
	var tested: Array = ["enter", "hit", "round_end", "knockout", "faint", "status"]
	assert_array(Array(DataSchemas.TRIGGER_ON)).contains_exactly_in_any_order(tested)
	assert_array(Array(DataSchemas.HELD.use.values)).contains_exactly_in_any_order(["permanent", "consumed", "per_battle"])


# --- held item use kinds --------------------------------------------------------------------

func test_consumed_held_item_fires_once_then_is_gone() -> void:
	var holder_c: CreatureInstance = _make(PLAIN, 30, ["tp_power_min"], "", "tp_h_consumed_enter")
	var bench_c: CreatureInstance = _make(PLAIN, 30, ["tp_power_min"])
	var e: BattleEngine = _engine([holder_c, bench_c], [_make(PLAIN, 30, ["tp_power_min"])])
	var holder: Battler = _first(e, 0)
	var banner_at: int = _index(_start_events, BattleEvents.PASSIVE_TRIGGERED, holder.bid)
	assert_int(banner_at).is_greater(-1)
	assert_int(_of(_start_events, BattleEvents.PASSIVE_TRIGGERED).size()).is_equal(1)
	var banner: Dictionary = _start_events[banner_at]
	assert_str(str(banner.item)).is_equal("tp_h_consumed_enter")
	assert_str(str(banner.passive)).is_equal("")
	var stage_at: int = _index(_start_events, BattleEvents.STAT_STAGE, holder.bid)
	assert_int(stage_at).is_greater(banner_at)
	assert_str(str(_start_events[stage_at].stat)).is_equal("resolve")
	assert_int(int(_start_events[stage_at].change)).is_equal(2)
	var used_up: Array = _of(_start_events, BattleEvents.ITEM_CONSUMED, holder.bid)
	assert_int(used_up.size()).is_equal(1)
	assert_str(str(used_up[0].item)).is_equal("tp_h_consumed_enter")
	assert_int(_index(_start_events, BattleEvents.ITEM_CONSUMED)).is_greater(stage_at)
	assert_str(holder.creature.held_item).is_equal("")
	# Swap out and back in: no second firing.
	var bench: Battler = e.sides[0].bench()[0]
	var evs: Array = _round(e, [BattleAction.swap(holder.bid, bench.bid)])
	evs.append_array(_round(e, [BattleAction.swap(bench.bid, holder.bid)]))
	assert_int(_of(evs, BattleEvents.SEND_OUT, holder.bid).size()).is_equal(1)
	assert_array(_of(evs, BattleEvents.PASSIVE_TRIGGERED)).is_empty()
	assert_array(_of(evs, BattleEvents.ITEM_CONSUMED)).is_empty()
	# The original keeps it until the battle is committed, then really has no item.
	assert_str(holder_c.held_item).is_equal("tp_h_consumed_enter")
	e.commit(0)
	assert_str(holder_c.held_item).is_equal("")


func test_per_battle_held_item_fires_once_per_battle() -> void:
	var holder_c: CreatureInstance = _make(WALL, 50, ["tp_power_min"], "", "tp_h_pb_hit_contact")
	var attacker_c: CreatureInstance = _make(PLAIN, 30, ["tp_hit_neutral_physical_prio_minus3"])
	for battle: int in 2:
		var e: BattleEngine = _engine([attacker_c], [holder_c])
		var attacker: Battler = _first(e, 0)
		var holder: Battler = _first(e, 1)
		var banners: int = 0
		for r: int in 3:
			var evs: Array = _round(e, [BattleAction.use_move(attacker.bid, "tp_hit_neutral_physical_prio_minus3", holder.bid)])
			assert_int(_of(evs, BattleEvents.DAMAGE, holder.bid).size()).is_equal(1)
			var fired: Array = _of(evs, BattleEvents.PASSIVE_TRIGGERED, holder.bid)
			assert_int(fired.size()).is_equal(1 if r == 0 else 0)
			if r == 0:
				assert_str(str(fired[0].item)).is_equal("tp_h_pb_hit_contact")
				var drop: Array = _of(evs, BattleEvents.STAT_STAGE, attacker.bid)
				assert_int(drop.size()).is_equal(1)
				assert_int(int(drop[0].change)).is_equal(-1)
			banners += fired.size()
			assert_array(_of(evs, BattleEvents.ITEM_CONSUMED)).is_empty()
		assert_int(banners).override_failure_message("battle %d" % battle).is_equal(1)
		assert_bool(holder.held_spent).is_true()
		assert_str(holder.creature.held_item).is_equal("tp_h_pb_hit_contact")
		e.commit(1)
		assert_str(holder_c.held_item).is_equal("tp_h_pb_hit_contact")


func test_permanent_held_item_blocks_every_time_and_persists() -> void:
	var e: BattleEngine = _engine([_make(PLAIN, 30, ["tp_stage_patk_swing"])],
		[_make(WALL, 50, ["tp_power_min"], "", "tp_h_stat_guard")])
	var user: Battler = _first(e, 0)
	var holder: Battler = _first(e, 1)
	for r: int in 3:
		var evs: Array = _round(e, [BattleAction.use_move(user.bid, "tp_stage_patk_swing", holder.bid)])
		var fired: Array = _of(evs, BattleEvents.PASSIVE_TRIGGERED, holder.bid)
		assert_int(fired.size()).override_failure_message("round %d" % r).is_equal(1)
		assert_str(str(fired[0].item)).is_equal("tp_h_stat_guard")
		assert_array(_of(evs, BattleEvents.STAT_STAGE, holder.bid)).is_empty()
		assert_int(_of(evs, BattleEvents.STAT_STAGE, user.bid).size()).is_equal(1)
		assert_array(_of(evs, BattleEvents.ITEM_CONSUMED)).is_empty()
		assert_int(holder.stages["patk"]).is_equal(0)
		assert_str(holder.creature.held_item).is_equal("tp_h_stat_guard")
	assert_bool(holder.held_spent).is_false()


# --- depth guard ------------------------------------------------------------------------------

func test_chain_pair_depth_guard_stops_the_loop() -> void:
	var move_id: String = "tp_hit_neutral_physical_prio_minus3"
	var e: BattleEngine = _engine([_make(WALL, 50, [move_id], "tp_chain_a")], [_make(WALL, 50, [move_id], "tp_chain_b")])
	var a: Battler = _first(e, 0)
	var b: Battler = _first(e, 1)
	# One hit: B retaliates once; the retaliation damages A but sets off nothing (depth guard).
	var evs: Array = _round(e, [BattleAction.use_move(a.bid, move_id, b.bid)])
	var banners: Array = _of(evs, BattleEvents.PASSIVE_TRIGGERED)
	assert_int(banners.size()).is_equal(1)
	assert_int(int(banners[0].bid)).is_equal(b.bid)
	assert_str(str(banners[0].passive)).is_equal("tp_chain_b")
	var on_a: Array = _of(evs, BattleEvents.DAMAGE, a.bid)
	assert_int(_of(evs, BattleEvents.DAMAGE).size()).is_equal(2)
	assert_int(on_a.size()).is_equal(1)
	assert_int(int(on_a[0].by)).is_equal(b.bid)
	assert_int(_index(evs, BattleEvents.DAMAGE, a.bid)).is_greater(_index(evs, BattleEvents.PASSIVE_TRIGGERED))
	# Both hit each round: exactly one banner per hit, and every round completes.
	for r: int in 3:
		_refill(e)
		evs = _round(e, [BattleAction.use_move(a.bid, move_id, b.bid), BattleAction.use_move(b.bid, move_id, a.bid)])
		assert_int(_of(evs, BattleEvents.ROUND_START).size()).is_equal(1)
		assert_int(_of(evs, BattleEvents.MOVE_USED).size()).is_equal(2)
		assert_int(_of(evs, BattleEvents.PASSIVE_TRIGGERED).size()).override_failure_message("round %d" % r).is_equal(2)
		assert_int(_of(evs, BattleEvents.PASSIVE_TRIGGERED, a.bid).size()).is_equal(1)
		assert_int(_of(evs, BattleEvents.PASSIVE_TRIGGERED, b.bid).size()).is_equal(1)
		assert_int(_of(evs, BattleEvents.DAMAGE).size()).is_equal(4)
		assert_bool(e.is_over()).is_false()


# --- reactions ------------------------------------------------------------------------------

## The state a pack field move applies.
func _state_of(move_id: String) -> String:
	for eff: Dictionary in _db.move(move_id).effects:
		if eff.op == "apply_field_state":
			return str(eff.state)
	return ""


func test_each_base_reaction_is_triggered_by_pack_moves() -> void:
	# reaction -> [[side acting, move], [side acting, move]]. Side 0 aims at side 1; side 1 lays on its
	# own side, so every reaction fires on side 1.
	var plans: Dictionary = {
		"conduction": [[0, "tp_apply_soaked"], [0, "tp_apply_charged"]],
		"wildfire": [[0, "tp_apply_scorched"], [1, "tp_apply_overgrown"]],
		"icebound": [[0, "tp_apply_soaked"], [1, "tp_apply_frosted"]],
		"steam": [[0, "tp_apply_scorched"], [1, "tp_apply_frosted"]],
		"railstorm": [[0, "tp_apply_magnetized"], [0, "tp_apply_charged"]],
		"overload": [[1, "tp_apply_glitched"], [0, "tp_apply_charged"]],
		"nightmare": [[0, "tp_apply_haunted"], [1, "tp_apply_hazed"]],
		"eclipse": [[1, "tp_apply_shrouded"], [0, "tp_apply_radiant"]],
	}
	var base_reactions: Array = []
	for id: String in _db.ids("reactions"):
		if not Database.is_test_content(id):
			base_reactions.append(id)
	assert_int(base_reactions.size()).is_equal(8)
	assert_array(plans.keys()).contains_exactly_in_any_order(base_reactions)
	for rid: String in plans:
		var steps: Array = plans[rid]
		var r: ReactionDef = _db.reaction(rid)
		var states: Array = [_state_of(steps[0][1]), _state_of(steps[1][1])]
		assert_array(states).override_failure_message(rid).contains_exactly_in_any_order(Array(r.inputs))
		var moves: Array = [steps[0][1], steps[1][1]]
		var e: BattleEngine = _engine([_make(WALL, 50, moves)], [_make(WALL, 50, moves)])
		var seen: Array = []
		for step: Array in steps:
			var actor: Battler = _first(e, int(step[0]))
			var evs: Array = _round(e, [BattleAction.use_move(actor.bid, str(step[1]))])
			seen.append_array(_of(evs, BattleEvents.REACTION))
		assert_int(seen.size()).override_failure_message(rid).is_equal(1)
		var ev: Dictionary = seen[0]
		assert_str(str(ev.reaction)).is_equal(rid)
		assert_int(int(ev.side)).override_failure_message(rid).is_equal(1)
		assert_array(Array(ev.inputs)).contains_exactly_in_any_order(Array(r.inputs))
		for s: String in r.consumes:
			assert_bool(e.sides[1].field.has(s)).override_failure_message("%s left %s" % [rid, s]).is_false()


# --- Underdog-gated content on the outnumbered tamer --------------------------------------------

func test_outnumbered_tamer_underdog_content_fires() -> void:
	var t: TamerDef = _db.tamer("tp_tamer_outnumbered_3v2")
	assert_int(t.max_active).is_equal(3)
	assert_int(t.party.size()).is_equal(2)
	var party: Array = []
	for i: int in 3:
		party.append(_make(WALL, 50, ["tp_damage_fraction_full", "tp_power_min"]))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var setup: BattleSetup = BattleSetup.vs_tamer(_db, party, "tp_tamer_outnumbered_3v2", -1, {}, rng)
	setup.award_xp = false
	var e: BattleEngine = BattleEngine.new(_db, rng, setup)
	_start_events = e.start()
	var under: Array = []
	for ev: Dictionary in _of(_start_events, BattleEvents.UNDERDOG):
		if int(ev.side) == 1:
			under.append(ev)
	assert_int(under.size()).is_equal(1)
	assert_float(float(under[0].ratio)).is_equal_approx(1.5, 0.0001)
	var foes: Array[Battler] = e.sides[1].active()
	assert_int(foes.size()).is_equal(2)
	var wall: Battler = null
	var starved: Battler = null
	for b: Battler in foes:
		if b.creature.passive == "tp_aura_underdog_power":
			wall = b
		elif b.creature.passive == "tp_knockout_when_underdog":
			starved = b
	assert_object(wall).is_not_null()
	assert_object(starved).is_not_null()
	# tp_aura_underdog_power: electric power x1.2 on every tamer creature while outnumbered, none on the player.
	for b: Battler in foes:
		var found: bool = false
		for eff: Dictionary in e.passives(b):
			if eff.op == "type_power" and eff.type == "electric":
				assert_float(float(eff.mult)).is_equal_approx(1.2, 0.0001)
				found = true
		assert_bool(found).override_failure_message("no aura on bid %d" % b.bid).is_true()
	for b: Battler in e.sides[0].active():
		for eff: Dictionary in e.passives(b):
			assert_str(str(eff.op)).is_not_equal("type_power")
	# Knock out the aura holder: the tamer is down to 1 vs 3.
	var me: Battler = _first(e, 0)
	var evs: Array = _round(e, [BattleAction.use_move(me.bid, "tp_damage_fraction_full", wall.bid)])
	assert_bool(wall.fainted).is_true()
	assert_bool(e.is_over()).is_false()
	# Now let the energy-starved creature land a knockout while still outnumbered (2 vs 1 after it).
	var ko_round: Array = []
	for r: int in 6:
		for b: Battler in e.sides[0].active():
			b.creature.hp = 1
		starved.creature.energy = starved.creature.max_energy(_db) - 1
		evs = _round(e, [])
		if not _of(evs, BattleEvents.FAINT).is_empty():
			ko_round = evs
			break
	assert_array(ko_round).override_failure_message("the tamer never knocked anyone out").is_not_empty()
	var faint_at: int = _index(ko_round, BattleEvents.FAINT)
	assert_int(int(ko_round[faint_at].side)).is_equal(0)
	var banners: Array = []
	for ev: Dictionary in _of(ko_round, BattleEvents.PASSIVE_TRIGGERED, starved.bid):
		if str(ev.passive) == "tp_knockout_when_underdog":
			banners.append(ev)
	assert_int(banners.size()).is_equal(1)
	var banner_at: int = ko_round.find(banners[0])
	assert_int(banner_at).is_greater(faint_at)
	var gain_at: int = _index(ko_round, BattleEvents.ENERGY, starved.bid, banner_at)
	assert_int(gain_at).is_greater(banner_at)
	assert_int(int(ko_round[gain_at].energy)).is_equal(starved.creature.max_energy(_db))
