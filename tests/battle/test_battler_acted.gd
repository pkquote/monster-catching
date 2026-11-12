extends GdUnitTestSuite
## Battler.acted: true for creatures placed at battle start (and never-placed bench creatures), false for a creature
## placed afterwards (swap-in or faint replacement) until it runs an action. The AI will not swap such a creature out.

var db: Database


func before() -> void:
	var r: RawData = FixtureDB.raw()
	var errors: Array = DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _mk(species: String = "blob") -> CreatureInstance:
	return FixtureDB.make(db, species, 10, ["hit"])


func test_lead_creatures_start_acted() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank")])
	assert_bool(e.sides[0].active()[0].acted).is_true()
	assert_bool(e.sides[1].active()[0].acted).is_true()
	assert_bool(e.sides[0].bench()[0].acted).is_true()


func test_swap_in_has_not_acted() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank")])
	var lead: Battler = e.sides[0].active()[0]
	var bench: Battler = e.sides[0].bench()[0]
	e.resolve_round([BattleAction.swap(lead.bid, bench.bid)])
	assert_bool(lead.acted).is_true()
	assert_bool(bench.acted).is_false()


func test_acts_once_it_acts() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank")])
	var lead: Battler = e.sides[0].active()[0]
	var bench: Battler = e.sides[0].bench()[0]
	var foe: Battler = e.sides[1].active()[0]
	e.resolve_round([BattleAction.swap(lead.bid, bench.bid)])
	e.resolve_round([BattleAction.use_move(bench.bid, "hit", foe.bid)])
	assert_bool(bench.acted).is_true()


func test_faint_replacement_has_not_acted() -> void:
	var e: BattleEngine = FixtureDB.engine(db, [_mk(), _mk()], [_mk("tank")])
	var lead: Battler = e.sides[0].active()[0]
	var bench: Battler = e.sides[0].bench()[0]
	var foe: Battler = e.sides[1].active()[0]
	lead.creature.hp = 1
	e.resolve_round([BattleAction.pass_turn(lead.bid), BattleAction.use_move(foe.bid, "hit", lead.bid)])
	assert_bool(lead.alive()).is_false()
	e.replace(0, bench.bid)
	assert_bool(bench.acted).is_false()
