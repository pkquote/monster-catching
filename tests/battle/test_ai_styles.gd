extends GdUnitTestSuite
## The AI reads its style from data (data/ai_styles.json through Database.ai_style): the weights scale the terms they
## name. The shipped styles' values and the unchanged choices of the existing three are pinned by the data test and the
## other AI suites.

var db: Database


## A fresh Database per test: several tests change a shared style object (def.heal = 2.0) and must not leak into the next.
func before_test() -> void:
	var r := FixtureDB.raw()
	r.add_entry("moves", FixtureDB.move("focus", "neutral", "status", 0, 100, "self",
		[{"op": "stat_stage", "stat": "patk", "stages": 1}], {"always_hits": true}))
	r.add_entry("moves", FixtureDB.move("peck", "neutral", "physical", 20, 100, "one_enemy", [{"op": "damage"}]))
	r.add_entry("moves", FixtureDB.move("slam", "neutral", "physical", 90, 100, "one_enemy", [{"op": "damage"}]))
	r.add_entry("moves", FixtureDB.move("empower", "neutral", "physical", 20, 100, "one_enemy",
		[{"op": "damage"}, {"op": "stat_stage", "stat": "patk", "stages": 1, "target": "self"}]))
	r.add_entry("passives", {"id": "pure", "name": "Pure", "description": "Test passive.", "effects": [{"op": "status_immune"}]})
	r.add_entry("passives", {"id": "thorns", "name": "Thorns", "description": "Test passive.",
		"triggers": [{"on": "hit", "effects": [{"op": "damage", "power": 40, "target": "attacker"}]}]})
	r.add_entry("creatures", FixtureDB._c("puncher", ["neutral"], FixtureDB.stats({"patk": 150}), [{"level": 1, "move": "hit"}]))
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String, moves: Array = ["hit"]) -> CreatureInstance:
	return FixtureDB.make(db, species, 10, moves)


func _engine(lead: String, bench: String, foe: String) -> BattleEngine:
	return FixtureDB.engine(db, [_make(lead), _make(bench)], [_make(foe)])


func test_profile_resolves_each_style() -> void:
	var e := _engine("blob", "blob", "blob")
	for id in ["basic", "aggressive", "tactician"]:
		assert_str(BattleAI.profile(e, id).id).is_equal(id)


func test_rest_score_scales_with_the_rest_weight() -> void:
	var e := _engine("blob", "blob", "blob")
	var b: Battler = e.sides[0].active()[0]
	var base := BattleAI.rest_score(e, b, "tactician")
	assert_float(BattleAI.rest_score(e, b)).is_equal_approx(base, 0.0001)
	var def := db.ai_style("tactician")
	def.rest = 2.0
	assert_float(BattleAI.rest_score(e, b, "tactician")).is_equal_approx(base * 2.0, 0.0001)
	def.rest = 1.0


func test_swap_avoid_scales_the_damage_avoided_term() -> void:
	var e := _engine("blob", "tank", "blob")
	var lead: Battler = e.sides[0].active()[0]
	var bench: Battler = e.sides[0].bench()[0]
	lead.creature.hp = 1
	var ref := BattleAI.best_damage(e, lead)
	var avoided := minf(BattleAI.threat(e, lead), float(lead.hp())) - minf(BattleAI.threat(e, bench), float(bench.hp()))
	avoided += BattleAI.KO_BONUS  # the lead is doomed and the bench creature survives
	var base := BattleAI.swap_score(e, lead, bench, "tactician", ref)
	var def := db.ai_style("tactician")
	def.swap_avoid = 2.0
	assert_float(BattleAI.swap_score(e, lead, bench, "tactician", ref) - base).is_equal_approx(avoided, 0.001)
	def.swap_avoid = 1.0


func test_heal_weight_scales_a_heal_move() -> void:
	var e := _engine("blob", "blob", "blob")
	var lead: Battler = e.sides[0].active()[0]
	var foe: Battler = e.sides[1].active()[0]
	lead.creature.hp = int(lead.creature.max_hp(db) * 0.3)
	var base := BattleAI.score(e, lead, db.move("mend"), -1, "tactician")
	assert_bool(base > 0.0).is_true()
	var def := db.ai_style("tactician")
	def.heal = 2.0
	assert_float(BattleAI.score(e, lead, db.move("mend"), -1, "tactician")).is_equal_approx(base * 2.0, 0.001)
	def.heal = 1.0
	assert_object(foe).is_not_null()


func test_damage_and_ko_weights_scale_a_finishing_hit() -> void:
	var e := _engine("blob", "blob", "blob")
	var lead: Battler = e.sides[0].active()[0]
	var foe: Battler = e.sides[1].active()[0]
	foe.creature.hp = 1
	var base := BattleAI.score(e, lead, db.move("hit"), foe.bid, "tactician")
	var def := db.ai_style("tactician")
	def.ko = 2.0
	assert_float(BattleAI.score(e, lead, db.move("hit"), foe.bid, "tactician") - base).is_equal_approx(BattleAI.KO_BONUS, 0.001)
	def.ko = 1.0
	def.damage = 2.0
	# the foe has 1 HP, so a hit lands 1 HP: doubling the damage weight adds 1
	assert_float(BattleAI.score(e, lead, db.move("hit"), foe.bid, "tactician") - base).is_equal_approx(1.0, 0.001)
	def.damage = 1.0


func test_setup_and_retaliation_weights_can_be_zeroed() -> void:
	var e := _engine("blob", "blob", "blob")
	var lead: Battler = e.sides[0].active()[0]
	var foe: Battler = e.sides[1].active()[0]
	var jolt := db.move("jolt")  # a status move: worth something only through setup
	assert_bool(BattleAI.score(e, lead, jolt, foe.bid, "tactician") > 0.0).is_true()
	var def := db.ai_style("tactician")
	def.setup = 0.0
	assert_float(BattleAI.score(e, lead, jolt, foe.bid, "tactician")).is_equal_approx(0.0, 0.0001)
	def.setup = 1.0


func test_reference_constants_match_the_shipped_data() -> void:
	# The constants are kept because older tests read them; the data is authoritative, so they must not drift.
	assert_float(BattleAI.AGGRESSIVE_SETUP_MULT).is_equal(db.ai_style("aggressive").trigger_setup)
	assert_float(BattleAI.SWAP_MARGIN).is_equal(db.ai_style("tactician").swap_margin)


# --- passive: avoids attacking, prefers buffs, heals and Rest, else its weakest hit -------------------------

func _passive_engine(moves: Array, foe := "tank") -> BattleEngine:
	return FixtureDB.engine(db, [_make("blob", moves), _make("tank")], [_make(foe)])


func _lead(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _foe(e: BattleEngine) -> Battler:
	return e.sides[1].active()[0]


func _chosen(e: BattleEngine, style := "passive") -> BattleAction:
	return BattleAI.choose(e, _lead(e).bid, style)


func test_buff_value_is_zero_for_the_existing_styles() -> void:
	var e := _passive_engine(["focus", "peck"])
	for style in ["tactician", "aggressive"]:
		assert_float(BattleAI.score(e, _lead(e), db.move("focus"), -1, style)).is_equal_approx(0.0, 0.0001)


func test_buff_value_for_passive() -> void:
	var e := _passive_engine(["focus", "peck"])
	var ref := BattleAI.best_damage(e, _lead(e))
	assert_float(BattleAI.score(e, _lead(e), db.move("focus"), -1, "passive")).is_equal_approx(
		BattleAI.DEBUFF_VALUE.patk * ref, 0.001)
	_lead(e).stages.patk = Battler.STAGE_MAX
	assert_float(BattleAI.score(e, _lead(e), db.move("focus"), -1, "passive")).is_equal_approx(0.0, 0.0001)


func test_passive_prefers_a_buff_to_any_attack() -> void:
	var e := _passive_engine(["peck", "slam", "focus"])
	assert_str(_chosen(e).move).is_equal("focus")


func test_passive_heals_below_half() -> void:
	var e := _passive_engine(["peck", "slam", "focus", "mend"])
	_lead(e).creature.hp = int(_lead(e).creature.max_hp(db) * 0.3)
	assert_str(_chosen(e).move).is_equal("mend")


func test_passive_attacks_weakly_when_nothing_else() -> void:
	var e := _passive_engine(["slam", "peck"])
	assert_str(_chosen(e).move).is_equal("peck")
	# a foe that slam would knock out but peck would not: it still does not chase the knockout
	var slam_est := BattleAI.estimate_damage(e, _lead(e), db.move("slam"), _foe(e), 1)
	var peck_est := BattleAI.estimate_damage(e, _lead(e), db.move("peck"), _foe(e), 1)
	assert_bool(peck_est < slam_est).is_true()
	_foe(e).creature.hp = int(slam_est)
	assert_str(_chosen(e).move).is_equal("peck")


func test_passive_takes_a_hit_over_a_pointless_move() -> void:
	var e := _passive_engine(["jolt", "peck"])
	_foe(e).creature.status = "burn"
	_foe(e).status_turns = 2
	assert_float(BattleAI.score(e, _lead(e), db.move("jolt"), _foe(e).bid, "passive")).is_equal_approx(0.0, 0.0001)
	assert_str(_chosen(e).move).is_equal("peck")


func test_heal_at_full_hp_is_not_rewarded() -> void:
	var e := _passive_engine(["mend", "peck"])
	assert_str(_chosen(e).move).is_equal("peck")


func test_passive_prefers_rest_at_low_energy() -> void:
	var e := _passive_engine(["peck", "slam"])
	_lead(e).creature.energy = 0
	assert_str(_chosen(e).kind).is_equal("rest")
	assert_float(BattleAI.rest_score(e, _lead(e), "passive")).is_equal_approx(
		BattleAI.rest_score(e, _lead(e), "tactician") * 2.0, 0.0001)


func test_passive_never_swaps() -> void:
	var e := FixtureDB.engine(db, [_make("blob", ["peck"]), _make("tank")], [_make("puncher")])
	_lead(e).creature.hp = 1
	assert_str(BattleAI.choose(e, _lead(e).bid, "tactician").kind).is_equal("swap")  # the same fixture swaps for the tactician
	assert_str(_chosen(e).kind).is_not_equal("swap")


func test_passive_scoring_draws_no_rng() -> void:
	var e := _passive_engine(["peck", "slam", "focus", "mend"])
	var before_state := e.rng.state
	_chosen(e)
	assert_int(e.rng.state).is_equal(before_state)


# --- defensive: survival, earlier heals, heavier retaliation, swaps more readily ----------------------------

## The highest HP percentage (stepping down from 100 in 5s) at which `style` picks the heal over a strong hit, or 0.
func _heal_threshold(style: String, moves: Array = ["hit", "mend"]) -> int:
	for pct in range(100, 0, -5):
		var e := FixtureDB.engine(db, [_make("puncher", moves), _make("tank")], [_make("tank")])
		_lead(e).creature.hp = maxi(1, int(_lead(e).creature.max_hp(db) * pct / 100.0))
		if _chosen(e, style).move == "mend":
			return pct
	return 0


func test_defensive_heals_at_a_higher_hp_than_the_tactician() -> void:
	var tactician := _heal_threshold("tactician")
	assert_int(_heal_threshold("defensive")).is_greater(tactician)  # a strong hitter: the tactician attacks where defensive heals


func test_defensive_takes_a_swap_the_tactician_declines() -> void:
	# A swap whose edge over the best move sits between the defensive margin (0.1 x ref) and the tactician's (0.25 x ref).
	# Stat drops on the lead add a smooth escape value, which walks the swap score through that band.
	var found := false
	for stat in ["spd", "pdef", "sdef"]:
		for stage in [-1, -2, -3, -4, -5, -6]:
			for foe in ["blob", "tank"]:
				var e := FixtureDB.engine(db, [_make("blob", ["hit"]), _make("tank")], [_make(foe)])
				_lead(e).stages[stat] = stage
				if _chosen(e, "defensive").kind == "swap" and _chosen(e, "tactician").kind != "swap":
					found = true
	assert_bool(found).is_true()


func test_defensive_values_damage_avoided_more() -> void:
	var e := FixtureDB.engine(db, [_make("blob", ["peck"]), _make("tank")], [_make("blob")])
	var lead := _lead(e)
	var bench: Battler = e.sides[0].bench()[0]
	lead.creature.hp = 1
	var ref := BattleAI.best_damage(e, lead)
	var avoided := minf(BattleAI.threat(e, lead), float(lead.hp())) - minf(BattleAI.threat(e, bench), float(bench.hp()))
	avoided += BattleAI.KO_BONUS
	var gain := BattleAI.swap_score(e, lead, bench, "defensive", ref) - BattleAI.swap_score(e, lead, bench, "tactician", ref)
	assert_float(gain).is_equal_approx(0.5 * avoided, 0.001)


func test_defensive_charges_more_retaliation() -> void:
	var plain := _passive_engine(["hit"])
	var spiky := _passive_engine(["hit"])
	_foe(spiky).creature.passive = "thorns"
	var cost := func(style: String) -> float:
		return BattleAI.score(plain, _lead(plain), db.move("hit"), _foe(plain).bid, style) \
			- BattleAI.score(spiky, _lead(spiky), db.move("hit"), _foe(spiky).bid, style)
	var tactician: float = cost.call("tactician")
	assert_bool(tactician > 0.0).is_true()
	assert_float(cost.call("defensive")).is_equal_approx(1.5 * tactician, 0.001)


# --- trickster: statuses, debuffs and field setup first -----------------------------------------------------

func test_trickster_prefers_a_status_to_a_hit_more_than_the_tactician() -> void:
	var e := _passive_engine(["peck", "burn_touch"])
	var gap := func(style: String) -> float:
		return BattleAI.score(e, _lead(e), db.move("burn_touch"), _foe(e).bid, style) \
			- BattleAI.score(e, _lead(e), db.move("peck"), _foe(e).bid, style)
	assert_bool(float(gap.call("trickster")) > float(gap.call("tactician"))).is_true()
	assert_float(BattleAI.score(e, _lead(e), db.move("burn_touch"), _foe(e).bid, "trickster")).is_equal_approx(
		1.5 * BattleAI.score(e, _lead(e), db.move("burn_touch"), _foe(e).bid, "tactician"), 0.001)


func test_trickster_still_takes_a_knockout() -> void:
	var e := _passive_engine(["slam", "burn_touch"])
	_foe(e).creature.hp = 1
	assert_str(_chosen(e, "trickster").move).is_equal("slam")


func test_trickster_ignores_a_blocked_status() -> void:
	var e := _passive_engine(["peck", "burn_touch"])
	_foe(e).creature.status = "chill"
	_foe(e).status_turns = 2
	assert_float(BattleAI.score(e, _lead(e), db.move("burn_touch"), _foe(e).bid, "trickster")).is_equal_approx(0.0, 0.0001)
	assert_str(_chosen(e, "trickster").move).is_equal("peck")


# --- review fixes -----------------------------------------------------------------------------------------

func test_passive_attacks_a_thorny_foe_rather_than_a_pointless_move() -> void:
	# A retaliation cost is real HP, far above the weakest-hit band; it must not push every attack below a worth-0 move.
	var e := _passive_engine(["jolt", "peck"])
	_foe(e).creature.passive = "thorns"
	_foe(e).creature.status = "burn"  # jolt (a status) is now worth 0
	_foe(e).status_turns = 2
	assert_float(BattleAI.score(e, _lead(e), db.move("jolt"), _foe(e).bid, "passive")).is_equal_approx(0.0, 0.0001)
	assert_bool(BattleAI.score(e, _lead(e), db.move("peck"), _foe(e).bid, "passive") > 0.0).is_true()
	assert_str(_chosen(e).move).is_equal("peck")


func test_retaliation_still_ranks_passive_attacks() -> void:
	var plain := _passive_engine(["peck"])
	var spiky := _passive_engine(["peck"])
	_foe(spiky).creature.passive = "thorns"
	assert_bool(BattleAI.score(spiky, _lead(spiky), db.move("peck"), _foe(spiky).bid, "passive")
		< BattleAI.score(plain, _lead(plain), db.move("peck"), _foe(plain).bid, "passive")).is_true()


func test_buff_value_follows_the_effects_own_target() -> void:
	# A one_enemy attack whose buff effect names target "self" still earns the buff.
	var e := _passive_engine(["empower", "peck"])
	var ref := BattleAI.best_damage(e, _lead(e))
	var gain := BattleAI.score(e, _lead(e), db.move("empower"), _foe(e).bid, "passive") \
		- BattleAI.score(e, _lead(e), db.move("peck"), _foe(e).bid, "passive")
	assert_float(gain).is_equal_approx(BattleAI.DEBUFF_VALUE.patk * ref, 0.001)


# --- hardening: each weight is isolated, and the blocked-status case is a real blocker -------------------------

func test_retaliation_weight_scales_and_zeroes_the_retaliation_cost() -> void:
	var plain := _passive_engine(["hit"])
	var spiky := _passive_engine(["hit"])
	_foe(spiky).creature.passive = "thorns"
	var cost := func() -> float:
		return BattleAI.score(plain, _lead(plain), db.move("hit"), _foe(plain).bid, "tactician") \
			- BattleAI.score(spiky, _lead(spiky), db.move("hit"), _foe(spiky).bid, "tactician")
	var full: float = cost.call()
	assert_bool(full > 0.0).is_true()
	var def := db.ai_style("tactician")
	def.retaliation = 0.5
	assert_float(cost.call()).is_equal_approx(full * 0.5, 0.001)
	def.retaliation = 0.0
	assert_float(cost.call()).is_equal_approx(0.0, 0.0001)


func test_the_heal_weight_alone_moves_the_defensive_heal_threshold() -> void:
	# puncher with slam: slam scores 21.7 (x0.7 for defensive), mend 15 at heal 1.0 and 22.5 at heal 1.5
	var shipped := _heal_threshold("defensive", ["slam", "mend"])
	db.ai_style("defensive").heal = 1.0
	assert_int(shipped).is_greater(_heal_threshold("defensive", ["slam", "mend"]))


func test_the_swap_margin_alone_decides_a_defensive_swap() -> void:
	# One pdef drop makes the swap exactly as good as the best move; each further spd drop adds 0.08 x ref of escape
	# value, so the edge walks 0, 0.72, 1.44, 2.16... against margins of 0.9 (0.1 x ref) and 2.25 (0.25 x ref).
	var swaps_at := func() -> Array:
		var out := []
		for spd_stage in [0, -1, -2, -3, -4, -5, -6]:
			var e := FixtureDB.engine(db, [_make("blob", ["hit"]), _make("tank")], [_make("blob")])
			_lead(e).stages.pdef = -1
			_lead(e).stages.spd = spd_stage
			out.append(_chosen(e, "defensive").kind == "swap")
		return out
	var narrow: Array = swaps_at.call()  # the shipped margin, 0.1
	db.ai_style("defensive").swap_margin = 0.25
	var wide: Array = swaps_at.call()
	var only_narrow := 0
	for i in narrow.size():
		assert_bool(wide[i] and not narrow[i]).override_failure_message("a wider margin never adds a swap").is_false()
		if narrow[i] and not wide[i]:
			only_narrow += 1
	assert_int(only_narrow).is_greater(0)


func test_trickster_ignores_a_status_the_foe_cannot_be_given() -> void:
	var e := _passive_engine(["peck", "burn_touch"])
	_foe(e).creature.passive = "pure"  # status_immune
	assert_bool(e.passive_rules.blocks_status(_foe(e), "burn")).is_true()
	assert_float(BattleAI.score(e, _lead(e), db.move("burn_touch"), _foe(e).bid, "trickster")).is_equal_approx(0.0, 0.0001)
	assert_str(_chosen(e, "trickster").move).is_equal("peck")
