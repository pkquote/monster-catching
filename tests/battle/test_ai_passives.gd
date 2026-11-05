extends GdUnitTestSuite
## How the battle AI weighs creature passives: absorbs, protections, the user's own
## modifiers and what a foe's hit triggers do back.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("moves", FixtureDB._m("twin_zap", "electric", "special", 50, 100, "two_enemies",
		[{"op": "damage"}]))
	r.add_entry("moves", FixtureDB._m("ignite", "fire", "status", 0, 100, "one_enemy",
		[{"op": "apply_status", "status": "burn"}], {"always_hits": true}))
	for p in [
		{"id": "rod", "effects": [{"op": "absorb_type", "type": "electric", "fraction": 0.25}]},
		{"id": "mud_rod", "effects": [{"op": "absorb_type", "type": "earth", "fraction": 0.25}]},
		{"id": "pure", "effects": [{"op": "status_immune"}]},
		{"id": "grip", "effects": [{"op": "guard_stages"}]},
		{"id": "booster", "effects": [{"op": "field_boost", "stacks": 1}]},
		{"id": "rester", "effects": [{"op": "rest_bonus", "fraction": 0.25}]},
		{"id": "scorcher", "triggers": [{"on": "hit", "contact": true,
			"effects": [{"op": "apply_status", "status": "burn"}]}]},
		{"id": "low_scorcher", "triggers": [{"on": "hit", "contact": true, "when": {"hp_below": 0.5},
			"effects": [{"op": "apply_status", "status": "burn"}]}]},
		{"id": "sulker", "triggers": [{"on": "hit",
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	var burn := [{"op": "apply_status", "status": "burn"}]
	var drop := [{"op": "stat_stage", "stat": "patk", "stages": -1}]
	for it in [
		{"id": "burn_charm", "held": {"triggers": [{"on": "hit", "contact": true, "effects": burn}]}},
		{"id": "burn_berry", "held": {"use": "consumed",
			"triggers": [{"on": "hit", "contact": true, "effects": burn}]}},
		{"id": "burn_spiky", "held": {"use": "per_battle",
			"triggers": [{"on": "hit", "contact": true, "effects": burn}]}},
		{"id": "sulk_charm", "held": {"triggers": [{"on": "hit", "effects": drop}]}},
		{"id": "low_burn_charm", "held": {"triggers": [{"on": "hit", "contact": true,
			"when": {"hp_below": 0.5}, "effects": burn}]}},
	]:
		it.merge({"name": str(it.id).capitalize(), "description": "Test held item.", "category": "held",
			"price": 10})
		r.add_entry("items", it)
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test passives invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String, passive: String, moves: Array = ["hit"], level := 10,
		held := "") -> CreatureInstance:
	var c := FixtureDB.make(db, species, level, moves)
	c.passive = passive
	c.held_item = held
	return c


## Score of `move` from side 0's first creature against side 1's first creature.
func _score(e: BattleEngine, move: String, style: String) -> float:
	var me: Battler = e.sides[0].active()[0]
	var foe: Battler = e.sides[1].active()[0]
	return BattleAI.score(e, me, db.move(move), foe.bid, style)


# --- Absorb ---

func test_avoids_hitting_an_absorber() -> void:
	var e := FixtureDB.engine(db, [_make("sparky", "", ["zap"])],
		[_make("tank", "rod"), _make("tank", "")], 1, 2)
	var me: Battler = e.sides[0].active()[0]
	var rod: Battler = e.sides[1].active()[0]
	var plain: Battler = e.sides[1].active()[1]
	rod.creature.hp = rod.creature.max_hp(db) / 2
	assert_float(BattleAI.score(e, me, db.move("zap"), rod.bid, "aggressive")).is_less(0.0)
	assert_int(BattleAI.choose(e, me.bid, "aggressive").target).is_equal(plain.bid)


func test_absorb_heal_is_capped_by_missing_hp() -> void:
	var e := FixtureDB.engine(db, [_make("sparky", "", ["zap"])], [_make("tank", "rod")])
	# At full HP the absorb heals nothing, so the move is just worthless, not harmful.
	assert_float(_score(e, "zap", "aggressive")).is_equal(0.0)


func test_an_ally_absorber_makes_a_spread_move_attractive() -> void:
	var plain := FixtureDB.engine(db, [_make("mole", "", ["quake"]), _make("tank", "")],
		[_make("tank", "")], 2, 1)
	var rod := FixtureDB.engine(db, [_make("mole", "", ["quake"]), _make("tank", "mud_rod")],
		[_make("tank", "")], 2, 1)
	for e in [plain, rod]:
		var ally: Battler = e.sides[0].active()[1]
		ally.creature.hp = ally.creature.max_hp(db) / 2
	assert_float(_score(rod, "quake", "aggressive")).is_greater(_score(plain, "quake", "aggressive"))


# --- Blocks ---

func test_status_move_is_worthless_against_an_immune_foe() -> void:
	var plain := FixtureDB.engine(db, [_make("blob", "", ["ignite"])], [_make("tank", "")])
	var pure := FixtureDB.engine(db, [_make("blob", "", ["ignite"])], [_make("tank", "pure")])
	assert_float(_score(plain, "ignite", "tactician")).is_greater(0.0)
	assert_float(_score(pure, "ignite", "tactician")).is_equal(0.0)


func test_debuff_is_worthless_against_a_stage_guard() -> void:
	var plain := FixtureDB.engine(db, [_make("blob", "", ["growl"])], [_make("tank", "")])
	var grip := FixtureDB.engine(db, [_make("blob", "", ["growl"])], [_make("tank", "grip")])
	assert_float(_score(plain, "growl", "tactician")).is_greater(0.0)
	assert_float(_score(grip, "growl", "tactician")).is_equal(0.0)


# --- The user's own passive ---

func test_field_boost_raises_a_reaction_setups_value() -> void:
	var plain := FixtureDB.engine(db, [_make("sparky", "", ["charge_up"])], [_make("tank", "")])
	var boosted := FixtureDB.engine(db, [_make("sparky", "booster", ["charge_up"])], [_make("tank", "")])
	for e in [plain, boosted]:
		e.apply_field_state(1, "soaked", 2, 3, null, false)
	assert_float(_score(boosted, "charge_up", "tactician")).is_greater(_score(plain, "charge_up", "tactician"))


func test_rest_bonus_makes_rest_more_attractive() -> void:
	var plain := FixtureDB.engine(db, [_make("blob", "")], [_make("tank", "")])
	var rester := FixtureDB.engine(db, [_make("blob", "rester")], [_make("tank", "")])
	var a := BattleAI.rest_score(plain, plain.sides[0].active()[0])
	var b := BattleAI.rest_score(rester, rester.sides[0].active()[0])
	assert_float(b).is_greater(a)


# --- Hit triggers ---

func test_retaliation_lowers_the_score_of_a_contact_hit() -> void:
	var plain := FixtureDB.engine(db, [_make("blob", "", ["hit"])], [_make("tank", "")])
	var scorcher := FixtureDB.engine(db, [_make("blob", "", ["hit"])], [_make("tank", "scorcher")])
	assert_float(_score(scorcher, "hit", "tactician")).is_less(_score(plain, "hit", "tactician"))
	# Aggressive reads damage only.
	assert_float(_score(scorcher, "hit", "aggressive")).is_equal(_score(plain, "hit", "aggressive"))


func test_contact_triggers_ignore_special_moves() -> void:
	var plain := FixtureDB.engine(db, [_make("sparky", "", ["zap"])], [_make("tank", "")])
	var scorcher := FixtureDB.engine(db, [_make("sparky", "", ["zap"])], [_make("tank", "scorcher")])
	assert_float(_score(scorcher, "zap", "tactician")).is_equal(_score(plain, "zap", "tactician"))


func test_retaliation_is_cancelled_by_the_attackers_protection() -> void:
	var plain := FixtureDB.engine(db, [_make("blob", "pure", ["hit"])], [_make("tank", "")])
	var scorcher := FixtureDB.engine(db, [_make("blob", "pure", ["hit"])], [_make("tank", "scorcher")])
	assert_float(_score(scorcher, "hit", "tactician")).is_equal(_score(plain, "hit", "tactician"))
	var sulk_plain := FixtureDB.engine(db, [_make("blob", "grip", ["hit"])], [_make("tank", "")])
	var sulk := FixtureDB.engine(db, [_make("blob", "grip", ["hit"])], [_make("tank", "sulker")])
	assert_float(_score(sulk, "hit", "tactician")).is_equal(_score(sulk_plain, "hit", "tactician"))


func test_no_retaliation_cost_when_the_hit_knocks_out() -> void:
	var plain := FixtureDB.engine(db, [_make("blob", "", ["hit"])], [_make("tank", "")])
	var scorcher := FixtureDB.engine(db, [_make("blob", "", ["hit"])], [_make("tank", "scorcher")])
	for e in [plain, scorcher]:
		e.sides[1].active()[0].creature.hp = 1
	assert_float(_score(scorcher, "hit", "tactician")).is_equal(_score(plain, "hit", "tactician"))


func test_choices_are_unchanged_without_passives() -> void:
	var e := FixtureDB.engine(db, [_make("fish", "", ["hit", "splash"])], [_make("flame", "")])
	assert_str(BattleAI.choose(e, e.sides[0].active()[0].bid, "tactician").move).is_equal("splash")


# --- Held-item hit triggers ---

func _held_foe(held: String, passive := "", attacker_passive := "") -> BattleEngine:
	return FixtureDB.engine(db, [_make("blob", attacker_passive, ["hit"])],
		[_make("tank", passive, ["hit"], 10, held)])


func test_retaliation_prices_a_held_item_hit_trigger() -> void:
	var plain := _held_foe("")
	var charm := _held_foe("burn_charm")
	assert_float(_score(charm, "hit", "tactician")).is_less(_score(plain, "hit", "tactician"))
	assert_float(_score(charm, "hit", "aggressive")).is_equal(_score(plain, "hit", "aggressive"))


func test_retaliation_cancelled_by_attackers_protection_for_items() -> void:
	# Unprotected, the item costs something; with only the attacker's passive added, it costs nothing.
	var open_plain := _held_foe("")
	var open_charm := _held_foe("burn_charm")
	assert_float(_score(open_charm, "hit", "tactician")).is_less(_score(open_plain, "hit", "tactician"))
	var pure_plain := _held_foe("", "", "pure")
	var pure_charm := _held_foe("burn_charm", "", "pure")
	assert_float(_score(pure_charm, "hit", "tactician")).is_equal(_score(pure_plain, "hit", "tactician"))
	var sulk_open_plain := _held_foe("")
	var sulk_open := _held_foe("sulk_charm")
	assert_float(_score(sulk_open, "hit", "tactician")).is_less(_score(sulk_open_plain, "hit", "tactician"))
	var sulk_plain := _held_foe("", "", "grip")
	var sulk := _held_foe("sulk_charm", "", "grip")
	assert_float(_score(sulk, "hit", "tactician")).is_equal(_score(sulk_plain, "hit", "tactician"))


func test_spent_per_battle_item_adds_no_retaliation() -> void:
	var plain := _held_foe("")
	var fresh := _held_foe("burn_spiky")
	var spent := _held_foe("burn_spiky")
	spent.sides[1].active()[0].held_spent = true
	assert_float(_score(fresh, "hit", "tactician")).is_less(_score(plain, "hit", "tactician"))
	assert_float(_score(spent, "hit", "tactician")).is_equal(_score(plain, "hit", "tactician"))


func test_consumed_item_costs_the_same_as_a_permanent_one_for_this_hit() -> void:
	var plain := _held_foe("")
	var perm := _held_foe("burn_charm")
	var eaten := _held_foe("burn_berry")
	var base := _score(plain, "hit", "tactician")
	assert_float(_score(perm, "hit", "tactician")).is_less(base)
	assert_float(_score(eaten, "hit", "tactician")).is_equal(_score(perm, "hit", "tactician"))


func test_trigger_when_gates_the_estimate() -> void:
	var plain := _held_foe("")
	var gated := _held_foe("low_burn_charm")
	assert_float(_score(gated, "hit", "tactician")).is_equal(_score(plain, "hit", "tactician"))
	var low := _held_foe("low_burn_charm")
	low.sides[1].active()[0].creature.hp = low.sides[1].active()[0].creature.max_hp(db) / 4
	var low_plain := _held_foe("")
	low_plain.sides[1].active()[0].creature.hp = low_plain.sides[1].active()[0].creature.max_hp(db) / 4
	assert_float(_score(low, "hit", "tactician")).is_less(_score(low_plain, "hit", "tactician"))


func test_passive_trigger_when_gates_the_estimate() -> void:
	var plain := _held_foe("")
	var gated := _held_foe("", "low_scorcher")
	assert_float(_score(gated, "hit", "tactician")).is_equal(_score(plain, "hit", "tactician"))
	var low := _held_foe("", "low_scorcher")
	var low_plain := _held_foe("")
	for e in [low, low_plain]:
		var f: Battler = e.sides[1].active()[0]
		f.creature.hp = f.creature.max_hp(db) / 4
	assert_float(_score(low, "hit", "tactician")).is_less(_score(low_plain, "hit", "tactician"))


func test_ai_avoids_a_pair_with_an_absorber() -> void:
	var e := FixtureDB.engine(db, [_make("sparky", "", ["twin_zap"])],
		[_make("tank", "rod"), _make("tank", ""), _make("tank", "")], 1, 3)
	var me: Battler = e.sides[0].active()[0]
	var foes: Array = e.sides[1].active()
	foes[0].creature.hp = foes[0].creature.max_hp(db) / 2
	var a := BattleAI.choose(e, me.bid, "aggressive")
	assert_str(a.move).is_equal("twin_zap")
	assert_int(a.second_target).is_not_equal(-1)
	assert_bool(a.target != foes[0].bid and a.second_target != foes[0].bid).is_true()
