extends GdUnitTestSuite
## M6h accuracy pass: retaliation priced through the trigger valuator, the knockout bonus scaling with ref, swap scoring
## that sees the bench creature in place, and the expected (not worst-case) threat in 2v2 and 3v3.

const BURN := [{"op": "apply_status", "status": "burn"}]

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	for p in [
		{"id": "recoup", "triggers": [{"on": "hit", "effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}]},
		{"id": "thorns_status", "triggers": [{"on": "hit", "effects": BURN}]},
		{"id": "contact_burn", "triggers": [{"on": "hit", "contact": true, "effects": BURN}]},
		{"id": "sponge", "effects": [{"op": "absorb_type", "type": "electric", "fraction": 0.25}]},
		{"id": "strong", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0}]},
		{"id": "guard_aura", "scope": "allies", "effects": [{"op": "incoming_type_mod", "mult": 0.5}]},
		{"id": "burn_low", "triggers": [{"on": "hit", "when": {"hp_below": 0.1}, "effects": BURN}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	r.add_entry("moves", FixtureDB.move("twin_hit", "neutral", "physical", 50, 100, "two_enemies", [{"op": "damage"}]))
	r.add_entry("moves", FixtureDB.move("triple", "neutral", "physical", 20, 100, "one_enemy", [{"op": "damage"}], {"hits": {"min": 3, "max": 3}}))
	r.add_entry("items", {"id": "berry_charm", "name": "Berry Charm", "description": "Test held item.", "category": "held", "price": 10,
		"held": {"use": "consumed", "triggers": [{"on": "hit", "when": {"hp_below": 0.5},
		"effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}]}})
	r.add_entry("items", {"id": "scald_charm", "name": "Scald Charm", "description": "Test held item.",
		"category": "held", "price": 10, "held": {"use": "per_battle", "triggers": [{"on": "hit", "effects": BURN}]}})
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String, passive := "", moves: Array = ["hit"], held := "") -> CreatureInstance:
	var c := FixtureDB.make(db, species, 10, moves)
	c.passive = passive
	c.held_item = held
	return c


func _lead(e: BattleEngine) -> Battler:
	return e.sides[0].active()[0]


func _foe(e: BattleEngine) -> Battler:
	return e.sides[1].active()[0]


## 1v1: a blob with `hit` and `blast` against a tank carrying `passive` and `held`.
func _duel(passive := "", held := "") -> BattleEngine:
	return FixtureDB.engine(db, [_make("blob", "", ["hit", "blast"])], [_make("tank", passive, ["hit"], held)])


func _score(e: BattleEngine, move := "hit", style := "tactician") -> float:
	return BattleAI.score(e, _lead(e), db.move(move), _foe(e).bid, style)


# --- Retaliation through the trigger valuator ---------------------------------------------------------------

func test_a_foes_self_heal_on_hit_is_a_retaliation_cost() -> void:
	var plain := _duel("")
	var spiky := _duel("recoup")
	for e in [plain, spiky]:
		_foe(e).creature.hp = _foe(e).creature.max_hp(db) - 20  # damaged, so the heal is real
	var est := BattleAI.estimate_damage(plain, _lead(plain), db.move("hit"), _foe(plain), 1)
	# The trigger fires after the hit, so the heal is capped by the HP missing once the hit has landed.
	var gain := minf(20.0 + roundi(est), 0.25 * float(_foe(spiky).creature.max_hp(db)))
	assert_float(_score(plain) - _score(spiky)).is_equal_approx(gain, 0.001)


func test_a_status_on_the_attacker_costs_what_status_value_says() -> void:
	var plain := _duel("")
	var spiky := _duel("thorns_status")
	var ref := BattleAI.best_damage(plain, _lead(plain))
	assert_float(_score(plain) - _score(spiky)).is_equal_approx(BattleAI.status_value(plain, _lead(plain), "burn", ref), 0.001)


func test_a_contact_trigger_is_ignored_for_a_non_physical_move() -> void:
	var plain := _duel("")
	var spiky := _duel("contact_burn")
	assert_bool(_score(plain, "hit") > _score(spiky, "hit")).is_true()  # physical: contact, pays
	assert_float(_score(plain, "blast")).is_equal_approx(_score(spiky, "blast"), 0.0001)  # special: nothing


func test_a_spent_per_battle_item_and_a_failed_when_cost_nothing() -> void:
	var plain := _duel("")
	var charmed := _duel("", "scald_charm")
	assert_bool(_score(plain) > _score(charmed)).is_true()  # the item costs while it is unspent
	_foe(charmed).held_spent = true
	assert_float(_score(charmed)).is_equal_approx(_score(plain), 0.0001)
	var low := _duel("burn_low")  # `when` hp_below 0.1 fails on a full-HP foe
	assert_float(_score(low)).is_equal_approx(_score(plain), 0.0001)


# --- A knockout bonus that scales with ref ------------------------------------------------------------------

func test_ko_bonus_scales_with_ref() -> void:
	assert_float(BattleAI.ko_bonus(10.0)).is_equal_approx(14.0, 0.0001)
	assert_float(BattleAI.ko_bonus(20.0)).is_equal_approx(2.0 * BattleAI.ko_bonus(10.0), 0.0001)
	assert_bool(BattleAI.ko_bonus(1.0) > 0.0).is_true()


func test_a_finishing_move_gains_the_ko_bonus_of_its_own_ref() -> void:
	var full := _duel("")
	var lethal := _duel("")
	_foe(lethal).creature.hp = 1
	var ref := BattleAI.best_damage(full, _lead(full))
	var est := BattleAI.estimate_damage(full, _lead(full), db.move("hit"), _foe(full), 1)
	# Landed damage is capped at the foe's 1 HP, then the bonus: the difference is 1 + ko_bonus - est.
	assert_float(_score(lethal) - _score(full)).is_equal_approx(1.0 + BattleAI.ko_bonus(ref) - est, 0.001)
	# The style's ko weight removes it: passive (ko 0) scores a lethal and a non-lethal hit alike.
	assert_float(_score(lethal, "hit", "passive")).is_equal_approx(_score(full, "hit", "passive"), 0.0001)


func test_the_doomed_swap_bonus_scales_with_ref() -> void:
	var e := FixtureDB.engine(db, [_make("blob"), _make("tank")], [_make("blob")])
	var lead := _lead(e)
	var bench: Battler = e.sides[0].bench()[0]
	lead.creature.hp = 1  # doomed: the foe's hit kills it, and the bench creature survives
	var ref := BattleAI.best_damage(e, lead)
	var gain := BattleAI.swap_score(e, lead, bench, "tactician", 2.0 * ref) - BattleAI.swap_score(e, lead, bench, "tactician", ref)
	assert_float(gain).is_equal_approx(BattleAI.ko_bonus(ref), 0.001)


# --- Evaluating a swap with the bench creature in place -------------------------------------------------------

## A lead and a bench creature (side 0, one field slot) against a foe whose only move is the electric `zap`.
func _bench_engine(bench_passive := "") -> BattleEngine:
	return FixtureDB.engine(db, [_make("blob"), _make("blob", bench_passive)], [_make("blob", "", ["zap"])])


func _swap_score(e: BattleEngine) -> float:
	var lead := _lead(e)
	return BattleAI.swap_score(e, lead, e.sides[0].bench()[0], "tactician", BattleAI.best_damage(e, lead))


func test_a_bench_absorber_removes_the_threat_it_would_absorb() -> void:
	var plain := _bench_engine("")
	var absorber := _bench_engine("sponge")
	var bench: Battler = plain.sides[0].bench()[0]
	var threat_without := BattleAI.threat(plain, bench)
	assert_bool(threat_without > 0.0).is_true()
	# With the sponge in place the electric hit heals it instead; the foe's free fallback move (scrap, neutral) still
	# lands, so the avoided-damage term gains the electric threat minus what scrap does.
	var foe: Battler = absorber.sides[1].active()[0]
	var scrap := BattleAI.estimate_damage(absorber, foe, absorber.db.move(absorber.fallback_move()), absorber.sides[0].bench()[0], 1)
	assert_bool(scrap < threat_without).is_true()
	var expected := minf(threat_without, float(bench.hp())) - minf(scrap, float(bench.hp()))
	assert_float(_swap_score(absorber) - _swap_score(plain)).is_equal_approx(expected, 0.001)


func test_a_bench_stat_boost_counts_in_its_damage_edge() -> void:
	var plain := _bench_engine("")
	var boosted := _bench_engine("strong")
	# The same creature as a lead, to read its damage with and without the boost.
	var lead_plain := FixtureDB.engine(db, [_make("blob")], [_make("blob", "", ["zap"])])
	var lead_boosted := FixtureDB.engine(db, [_make("blob", "strong")], [_make("blob", "", ["zap"])])
	var edge := BattleAI.best_damage(lead_boosted, _lead(lead_boosted)) - BattleAI.best_damage(lead_plain, _lead(lead_plain))
	assert_bool(edge > 0.0).is_true()
	assert_float(_swap_score(boosted) - _swap_score(plain)).is_equal_approx(edge, 0.001)


func test_an_active_allys_aura_covers_the_incoming_creature() -> void:
	var bare := FixtureDB.engine(db, [_make("blob"), _make("blob"), _make("blob")], [_make("blob", "", ["zap"])], 2, 1)
	var aura := FixtureDB.engine(db, [_make("blob"), _make("blob", "guard_aura"), _make("blob")], [_make("blob", "", ["zap"])], 2, 1)
	var results := []
	for e in [bare, aura]:
		var b: Battler = e.sides[0].active()[0]
		var c: Battler = e.sides[0].bench()[0]
		var outside := BattleAI.threat(e, c)  # benched: the ally's aura does not reach it
		var inside: float = BattleAI._with_swapped_in(e, b, c, func() -> float: return BattleAI.threat(e, c))
		results.append([outside, inside])
	assert_float(results[1][0]).is_equal_approx(results[0][0], 0.0001)  # outside the swap nothing changed
	assert_float(results[0][1]).is_equal_approx(results[0][0], 0.0001)  # no aura: same inside
	assert_float(results[1][1]).is_equal_approx(0.5 * results[0][1], 0.001)  # the aura halves what it takes


func test_the_in_place_evaluation_leaves_no_trace() -> void:
	var e := FixtureDB.engine(db, [_make("blob"), _make("blob", "sponge"), _make("blob", "strong")], [_make("blob", "", ["zap"]), _make("blob")], 2, 2)
	var all: Array[Battler] = []
	all.append_array(e.sides[0].battlers)
	all.append_array(e.sides[1].battlers)
	var snapshot := func() -> Array:
		var out := [e.rng.state, e.sides[0].slots.duplicate(), e.sides[1].slots.duplicate()]
		for b in all:
			out.append([b.active, b.stages.duplicate(), b.creature.hp])
		return out
	var before: Array = snapshot.call()
	for b in e.sides[0].active():
		for c in e.sides[0].bench():
			BattleAI.swap_score(e, b, c, "tactician", BattleAI.best_damage(e, b))
	assert_array(snapshot.call()).is_equal(before)


# --- Expected threat in 2v2 and 3v3 ---------------------------------------------------------------------------

func test_share_by_move_target() -> void:
	var single := db.move("hit")  # one_enemy
	var pair := db.move("twin_hit")  # two_enemies
	var spread := db.move("wave")  # all_enemies
	for n in [1, 2, 3]:
		assert_float(BattleAI._share(single, n)).is_equal_approx(1.0 / n, 0.0001)
		assert_float(BattleAI._share(pair, n)).is_equal_approx(minf(2.0, float(n)) / n, 0.0001)
		assert_float(BattleAI._share(spread, n)).is_equal_approx(1.0, 0.0001)
	assert_float(BattleAI._share(single, 0)).is_equal_approx(1.0, 0.0001)  # never divides by zero


## `ours` creatures on side 0 (all fielded) against `foes` creatures on side 1 that know only `moves`.
func _field(ours: int, foes: int, moves: Array = ["hit"]) -> BattleEngine:
	var mine: Array = []
	for i in ours:
		mine.append(_make("blob"))
	var theirs: Array = []
	for i in foes:
		theirs.append(_make("blob", "", moves))
	return FixtureDB.engine(db, mine, theirs, ours, foes)


func test_threat_counts_a_single_target_move_by_its_share() -> void:
	# Two foes with only a single-target move: each lands on a given one of our n creatures 1/n of the time. (Each field
	# is compared with its own damage estimates: a smaller side also gets an Underdog stat bonus, so fields differ.)
	for ours in [1, 2, 3]:
		var e := _field(ours, 2)
		var x := _lead(e)
		var sum := 0.0
		for foe in e.sides[1].active():
			sum += BattleAI.estimate_damage(e, foe, e.db.move("hit"), x, 1)
		assert_bool(sum > 0.0).is_true()
		assert_float(BattleAI.threat(e, x)).is_equal_approx(sum / float(ours), 0.001)


func test_threat_counts_a_spread_move_in_full() -> void:
	var duo := _field(2, 2, ["wave"])
	var x := _lead(duo)
	var expected := 0.0
	for foe in duo.sides[1].active():
		var best := 0.0
		for mid in duo.usable_moves(foe.bid):
			var m := duo.db.move(mid)
			if m.is_damaging():
				var est := BattleAI.estimate_damage(duo, foe, m, x, BattleAI._hit_count(duo, foe, m, 2))
				best = maxf(best, est * BattleAI._share(m, 2))
		expected += best
	assert_float(BattleAI.threat(duo, x)).is_equal_approx(expected, 0.001)
	# wave is a spread move, so it counts in full: its share is 1 (the fallback single-target move counts half).
	assert_float(BattleAI._share(duo.db.move("wave"), 2)).is_equal_approx(1.0, 0.0001)


func test_a_lead_hit_by_one_of_two_foes_is_not_flagged_doomed() -> void:
	var duo := _field(2, 2)
	var x := _lead(duo)
	var one_foe_hit := BattleAI.estimate_damage(duo, duo.sides[1].active()[0], duo.db.move("hit"), x, 1)
	x.creature.hp = int(1.5 * one_foe_hit)  # more than one foe's hit, less than both
	# Expected: one foe's worth lands (each of two foes picks this creature half the time), so it is not doomed.
	assert_float(BattleAI.threat(duo, x)).is_equal_approx(one_foe_hit, 0.001)
	assert_bool(BattleAI.threat(duo, x) < float(x.hp())).is_true()


func test_a_single_creature_side_keeps_the_plain_sum() -> void:
	var solo := _field(1, 1)
	var x := _lead(solo)
	var foe: Battler = solo.sides[1].active()[0]
	assert_float(BattleAI.threat(solo, x)).is_equal_approx(
		BattleAI.estimate_damage(solo, foe, solo.db.move("hit"), x, 1), 0.001)


# --- Review fixes: hit triggers are priced at the HP the hit leaves, and a once-only item once --------------------

## The heal an Oran-Berry-like item gives a foe left at `hp_after` (25% of max HP, capped by what is missing).
func _berry_heal(foe: Battler, hp_after: int) -> float:
	var max_hp := float(foe.creature.max_hp(db))
	return minf(max_hp - float(hp_after), 0.25 * max_hp)


func test_a_berry_is_priced_at_the_hp_the_hit_leaves() -> void:
	var plain := _duel("")
	var berry := _duel("", "berry_charm")
	var max_hp := _foe(plain).creature.max_hp(db)
	var est := BattleAI.estimate_damage(plain, _lead(plain), db.move("hit"), _foe(plain), 1)
	# Full HP: the hit leaves it above half, so the berry stays in its pouch and costs nothing.
	assert_float(_score(plain) - _score(berry)).is_equal_approx(0.0, 0.0001)
	# Above half before the hit, below half after it: the berry is eaten in the battle, so it costs the heal.
	var hp := int(0.5 * max_hp + 0.5 * est)
	for e in [plain, berry]:
		_foe(e).creature.hp = hp
	var after := maxi(1, hp - roundi(est))
	assert_bool(float(after) < 0.5 * max_hp and float(hp) >= 0.5 * max_hp).is_true()
	assert_float(_score(plain) - _score(berry)).is_equal_approx(_berry_heal(_foe(berry), after), 0.001)


func test_a_consumed_item_is_charged_once_for_a_multi_hit_move() -> void:
	var plain := _duel("")
	var berry := _duel("", "berry_charm")
	_lead(plain).creature.moves = ["hit", "triple"]
	_lead(berry).creature.moves = ["hit", "triple"]
	var est := BattleAI.estimate_damage(plain, _lead(plain), db.move("triple"), _foe(plain), 1)
	var hp := int(_foe(plain).creature.max_hp(db) * 0.5 + 0.5 * est)
	for e in [plain, berry]:
		_foe(e).creature.hp = hp
	var after := maxi(1, hp - roundi(est))
	# One berry, however many hits: the drop is the heal once, not three times.
	assert_float(_score(plain, "triple") - _score(berry, "triple")).is_equal_approx(_berry_heal(_foe(berry), after), 0.001)
