extends GdUnitTestSuite
## How the battle AI weighs creature passives: absorbs, protections, the user's own
## modifiers and what a foe's hit triggers do back.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
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
		{"id": "sulker", "triggers": [{"on": "hit",
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test passives invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String, passive: String, moves: Array = ["hit"], level := 10) -> CreatureInstance:
	var c := FixtureDB.make(db, species, level, moves)
	c.passive = passive
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
