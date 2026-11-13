extends GdUnitTestSuite
## replace(): what the engine settles when the caller fills an emptied slot. The entry trigger of the replacement can
## knock creatures out; the event stream must end cleanly if that decides the battle, and an auto-replace foe that was
## knocked out must be refilled at once, not a round later.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("passives", {"id": "soaker", "name": "Soaker", "description": "Test passive.",
		"triggers": [{"on": "enter", "effects": [{"op": "apply_field_state", "side": "enemy", "state": "soaked"}]}]})
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(passive := "") -> CreatureInstance:
	var c := FixtureDB.make(db, "blob", 10, ["hit"])
	c.passive = passive
	return c


## Side 0 (the caller) has an emptied lead and a soaker on the bench; side 1 has `foes` blobs and a Charged field, so the
## soaker's entry sets off Conduction and knocks out a foe with 1 HP.
func _engine(foes: int, foe_auto_replace: bool) -> BattleEngine:
	var setup := BattleSetup.new()
	setup.add_side([_make(), _make("soaker")], 1, 1)
	var theirs: Array = []
	for i in foes:
		theirs.append(_make())
	setup.add_side(theirs, 1, 1, {}, "", foe_auto_replace)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var e := BattleEngine.new(db, rng, setup)
	e.start()
	e.sides[0].active()[0].creature.hp = 0
	e.check_faints()
	e.sides[1].field.add("charged", 1, 3, 3)
	e.sides[1].active()[0].creature.hp = 1
	e.drain_events()
	return e


func test_a_replacement_that_ends_the_battle_leaves_battle_end_last() -> void:
	var e := _engine(1, false)
	var events := e.replace(0, e.sides[0].battlers[1].bid)
	assert_bool(e.is_over()).is_true()
	assert_str(events[events.size() - 1].type).is_equal(BattleEvents.BATTLE_END)


func test_a_knocked_out_auto_replace_foe_is_refilled_at_once() -> void:
	var e := _engine(2, true)
	var foe: Battler = e.sides[1].active()[0]
	var events := e.replace(0, e.sides[0].battlers[1].bid)
	assert_bool(foe.active).is_false()
	assert_bool(e.is_over()).is_false()
	assert_int(e.sides[1].active().size()).is_equal(1)  # the bench creature is already out
	var sent := FixtureDB.events_of(events, BattleEvents.SEND_OUT).filter(func(ev): return ev.side == 1)
	assert_int(sent.size()).is_equal(1)


func test_a_foe_that_is_not_auto_replaced_waits_for_the_caller() -> void:
	# Control: a side the caller controls is not refilled by the engine; it is asked (REPLACEMENT_NEEDED at round end).
	var e := _engine(2, false)
	e.replace(0, e.sides[0].battlers[1].bid)
	assert_int(e.sides[1].active().size()).is_equal(0)
	assert_int(e.pending_replacements(1)).is_equal(1)


## 2v2: side 0 has an emptied slot and a soaker on the bench; both foes have 1 HP, so the soaker's entry (Conduction
## hits every creature on the Charged side) knocks both out and ends the battle. The outnumbered ratio changes there.
func _engine_two_slots() -> BattleEngine:
	var setup := BattleSetup.new()
	setup.add_side([_make(), _make(), _make("soaker")], 2, 2)
	setup.add_side([_make(), _make()], 2, 2, {}, "", false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var e := BattleEngine.new(db, rng, setup)
	e.start()
	e.sides[0].active()[0].creature.hp = 0
	e.check_faints()
	e.refresh_underdog()  # as the end of a round does: side 0 (1 active vs 2) is now recorded as the underdog
	e.sides[1].field.add("charged", 1, 3, 3)
	for foe in e.sides[1].active():
		foe.creature.hp = 1
	e.drain_events()
	return e


func test_a_replacement_that_ends_a_2v2_battle_changes_underdog_before_the_end() -> void:
	var e := _engine_two_slots()
	var events := e.replace(0, e.sides[0].battlers[2].bid)
	assert_bool(e.is_over()).is_true()
	assert_str(events[events.size() - 1].type).is_equal(BattleEvents.BATTLE_END)
