extends GdUnitTestSuite
## The cure_status op and the status trigger: moves, items, passives and held items.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("moves", FixtureDB.move("soothe", "neutral", "status", 0, 100, "self",
		[{"op": "cure_status"}], {"always_hits": true}))
	r.add_entry("moves", FixtureDB.move("soothe_burn", "neutral", "status", 0, 100, "self",
		[{"op": "cure_status", "status": "burn"}], {"always_hits": true}))
	r.add_entry("items", {"id": "remedy", "name": "Remedy", "category": "heal", "price": 1,
		"target": "one_ally", "effects": [{"op": "cure_status"}]})
	r.add_entry("passives", {"id": "fireproof", "name": "Fireproof", "description": "Test passive.",
		"effects": [{"op": "status_immune", "status": "burn"}]})
	r.add_entry("passives", {"id": "purifier", "name": "Purifier", "description": "Test passive.",
		"triggers": [{"on": "round_end", "effects": [{"op": "cure_status"}]}]})
	for it in [
		{"id": "clear_berry", "held": {"use": "consumed", "triggers": [{"on": "status",
			"effects": [{"op": "cure_status"}]}]}},
		{"id": "burn_berry", "held": {"use": "consumed", "triggers": [{"on": "status",
			"effects": [{"op": "cure_status", "status": "burn"}]}]}},
		{"id": "round_clear_berry", "held": {"use": "consumed", "triggers": [{"on": "round_end",
			"effects": [{"op": "cure_status"}]}]}},
		{"id": "ward_charm", "held": {"triggers": [{"on": "status",
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": 1}]}]}},
		{"id": "loop_charm", "held": {"triggers": [{"on": "status", "effects": [
			{"op": "cure_status"}, {"op": "apply_status", "status": "shock", "target": "self"}]}]}},
	]:
		it.merge({"name": str(it.id).capitalize(), "description": "Test held item.", "category": "held",
			"price": 10})
		r.add_entry("items", it)
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _bid(e: BattleEngine, side: int, slot := 0) -> int:
	return e.sides[side].active()[slot].bid


## A duel where `me` (blob) can afflict and `foe` (tank) knows the cure moves.
func _duel(items0: Dictionary = {}) -> BattleEngine:
	return FixtureDB.engine(db,
		[FixtureDB.make(db, "blob", 10, ["burn_touch", "jolt", "hit"])],
		[FixtureDB.make(db, "tank", 10, ["soothe", "soothe_burn", "hit"])], -1, -1, 1, false, items0)


func _afflict(e: BattleEngine, b: Battler, status: String) -> void:
	b.creature.status = status
	b.status_turns = 3


func test_cure_clears_status_and_emits_cured_event() -> void:
	var e := _duel()
	var foe := e.battler(_bid(e, 1))
	_afflict(e, foe, "burn")
	var events := e.resolve_round([BattleAction.use_move(foe.bid, "soothe", foe.bid)])
	assert_str(foe.status()).is_equal("")
	assert_int(foe.status_turns).is_equal(0)
	var ended := FixtureDB.events_of(events, "status_ended")
	assert_array(ended).has_size(1)
	assert_bool(ended[0].get("cured", false)).is_true()
	assert_str(ended[0].status).is_equal("burn")


func test_cure_with_no_status_does_nothing() -> void:
	var e := _duel()
	var foe := e.battler(_bid(e, 1))
	var events := e.resolve_round([BattleAction.use_move(foe.bid, "soothe", foe.bid)])
	assert_array(FixtureDB.events_of(events, "status_ended")).is_empty()


func test_filtered_cure_ignores_other_status() -> void:
	var e := _duel()
	var foe := e.battler(_bid(e, 1))
	_afflict(e, foe, "shock")
	var events := e.resolve_round([BattleAction.use_move(foe.bid, "soothe_burn", foe.bid)])
	assert_str(foe.status()).is_equal("shock")
	assert_array(FixtureDB.events_of(events, "status_ended")).is_empty()


func test_filtered_cure_matches() -> void:
	var e := _duel()
	var foe := e.battler(_bid(e, 1))
	_afflict(e, foe, "burn")
	e.resolve_round([BattleAction.use_move(foe.bid, "soothe_burn", foe.bid)])
	assert_str(foe.status()).is_equal("")


func test_cure_on_fainted_target_does_nothing() -> void:
	var e := _duel()
	var foe := e.battler(_bid(e, 1))
	_afflict(e, foe, "burn")
	foe.creature.hp = 0
	assert_bool(e.cure_status(foe, "")).is_false()
	assert_str(foe.status()).is_equal("burn")


func test_cured_creature_takes_no_burn_damage_next_round() -> void:
	var e := _duel()
	var foe := e.battler(_bid(e, 1))
	_afflict(e, foe, "burn")
	e.resolve_round([BattleAction.use_move(foe.bid, "soothe", foe.bid)])
	var events := e.resolve_round([BattleAction.pass_turn(_bid(e, 0))])
	var hurt := FixtureDB.events_of(events, "damage").filter(func(ev): return ev.bid == foe.bid)
	assert_array(hurt).is_empty()


func test_item_cure_awards_bond_only_when_it_cured() -> void:
	var e := _duel({"remedy": 2})
	var me := e.battler(_bid(e, 0))
	var events := e.resolve_round([BattleAction.use_item(me.bid, "remedy", me.bid)])
	assert_array(FixtureDB.events_of(events, "bond")).is_empty()
	_afflict(e, me, "burn")
	events = e.resolve_round([BattleAction.use_item(me.bid, "remedy", me.bid)])
	var bond := FixtureDB.events_of(events, "bond")
	assert_array(bond).has_size(1)
	assert_str(bond[0].reason).is_equal("healed_item")
	assert_str(me.status()).is_equal("")


# --- The status trigger and cure triggers ---

## A meek (never resists) holder on the foe side, with `passive` and `held`; the player's blob can afflict it.
func _holder(passive := "", held := "") -> BattleEngine:
	var c := FixtureDB.make(db, "meek", 10, ["hit"])
	c.passive = passive
	c.held_item = held
	return FixtureDB.engine(db, [FixtureDB.make(db, "blob", 10, ["burn_touch", "jolt", "hit"])], [c])


func _hit_with(e: BattleEngine, move: String) -> Array:
	return e.resolve_round([BattleAction.use_move(_bid(e, 0), move, _bid(e, 1))])


func test_status_trigger_cures_the_new_status_and_uses_up_the_berry() -> void:
	var e := _holder("", "clear_berry")
	var holder := e.battler(_bid(e, 1))
	var events := _hit_with(e, "burn_touch")
	assert_str(holder.status()).is_equal("")
	assert_str(holder.creature.held_item).is_equal("")
	var types: Array = events.map(func(ev): return ev.type)
	assert_bool(types.find("status_applied") < types.find("status_ended")).is_true()
	assert_array(FixtureDB.events_of(events, "item_consumed")).has_size(1)
	assert_array(FixtureDB.events_of(events, "passive_triggered")).has_size(1)


func test_status_trigger_filter_mismatch_keeps_the_berry() -> void:
	var e := _holder("", "burn_berry")
	var holder := e.battler(_bid(e, 1))
	var events := _hit_with(e, "jolt")
	assert_str(holder.status()).is_equal("shock")
	assert_str(holder.creature.held_item).is_equal("burn_berry")
	assert_array(FixtureDB.events_of(events, "passive_triggered")).is_empty()


func test_status_trigger_does_not_fire_when_the_status_is_blocked() -> void:
	var e := _holder("fireproof", "ward_charm")
	var holder := e.battler(_bid(e, 1))
	var events := _hit_with(e, "burn_touch")
	assert_str(holder.status()).is_equal("")
	assert_int(holder.stages["patk"]).is_equal(0)
	assert_array(FixtureDB.events_of(events, "status_applied")).is_empty()
	# Already afflicted: the second status fails and fires nothing.
	var e2 := _holder("", "ward_charm")
	var h2 := e2.battler(_bid(e2, 1))
	_hit_with(e2, "burn_touch")
	assert_int(h2.stages["patk"]).is_equal(1)
	_hit_with(e2, "jolt")
	assert_int(h2.stages["patk"]).is_equal(1)


func test_round_end_cure_berry_is_not_wasted() -> void:
	var e := _holder("", "round_clear_berry")
	var holder := e.battler(_bid(e, 1))
	var events := e.resolve_round([BattleAction.pass_turn(_bid(e, 0))])
	assert_str(holder.creature.held_item).is_equal("round_clear_berry")
	assert_array(FixtureDB.events_of(events, "passive_triggered")).is_empty()
	holder.creature.status = "burn"
	holder.status_turns = 3
	events = e.resolve_round([BattleAction.pass_turn(_bid(e, 0))])
	assert_str(holder.status()).is_equal("")
	assert_str(holder.creature.held_item).is_equal("")


func test_cure_passive_at_round_end() -> void:
	var e := _holder("purifier")
	var holder := e.battler(_bid(e, 1))
	_hit_with(e, "burn_touch")
	assert_str(holder.status()).is_equal("")


func test_status_trigger_lands_on_the_afflicted_creature() -> void:
	var e := _holder("", "ward_charm")
	_hit_with(e, "burn_touch")
	assert_int(e.battler(_bid(e, 1)).stages["patk"]).is_equal(1)
	assert_int(e.battler(_bid(e, 0)).stages["patk"]).is_equal(0)


func test_effects_inside_a_status_trigger_set_off_no_further_triggers() -> void:
	var e := _holder("", "loop_charm")
	var holder := e.battler(_bid(e, 1))
	var events := _hit_with(e, "burn_touch")
	assert_str(holder.status()).is_equal("shock")
	assert_array(FixtureDB.events_of(events, "passive_triggered")).has_size(1)
