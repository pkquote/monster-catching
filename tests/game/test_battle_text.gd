extends GdUnitTestSuite
## Battle messages for engine events.

var db: Database
var names := func(bid: int) -> String: return "B%d" % bid


func before() -> void:
	db = FixtureDB.build()


func _say(ev: Dictionary, tamer := "") -> String:
	return BattleText.describe(ev, db, names, tamer)


func test_core_messages() -> void:
	assert_str(_say({"type": "move_used", "bid": 1, "move": "hit"})).is_equal("B1 used Hit!")
	assert_str(_say({"type": "faint", "bid": 2})).is_equal("B2 fainted!")
	assert_str(_say({"type": "miss", "bid": 1, "target": 3})).is_equal("B3 avoided the attack!")
	assert_str(_say({"type": "send_out", "bid": 0, "side": 0})).is_equal("Go, B0!")
	assert_str(_say({"type": "send_out", "bid": 4, "side": 1}, "Ana")).is_equal("Ana sent out B4!")


func test_effectiveness() -> void:
	assert_str(_say({"type": "damage", "bid": 1, "by": 0, "effectiveness": 2.0})).is_equal("It's super effective!")
	assert_str(_say({"type": "damage", "bid": 1, "by": 0, "effectiveness": 0.5})).is_equal("It's not very effective...")
	assert_str(_say({"type": "damage", "bid": 1, "by": 0, "effectiveness": 1.0})).is_equal("")
	assert_str(_say({"type": "damage", "bid": 1, "by": -1, "effectiveness": 1.0})).is_equal("B1 is hurt!")


func test_field_and_stats() -> void:
	assert_str(_say({"type": "field_applied", "side": 1, "state": "soaked", "stacks": 2})).is_equal("Soaked covers the enemy side! (×2)")
	assert_str(_say({"type": "field_removed", "side": 0, "state": "soaked", "reason": "expired"})).is_equal("The soaked on your side faded.")
	assert_str(_say({"type": "field_removed", "side": 0, "state": "soaked", "reason": "reacted"})).is_equal("")
	assert_str(_say({"type": "stat_stage", "bid": 1, "stat": "spd", "change": -2})).is_equal("B1's Speed sharply fell!")
	assert_str(_say({"type": "stat_stage", "bid": 1, "stat": "patk", "change": 0})).contains("won't change")


func test_underdog_and_bond_messages() -> void:
	var text := _say({"type": "underdog", "side": 0, "ratio": 3.0, "bonus_actions": 1, "stat_bonus": 0.15, "xp_bonus": 1.0})
	assert_str(text).contains("You're outnumbered").contains("+1 action").contains("+100% XP")
	assert_str(_say({"type": "underdog", "side": 0, "ratio": 1.0, "bonus_actions": 0, "stat_bonus": 0.0, "xp_bonus": 0.0})).is_equal("")
	assert_str(_say({"type": "disobeyed", "bid": 1, "ordered": "hit", "did": ""})).contains("loafing")
	assert_str(_say({"type": "lashed_out", "bid": 1, "target": 2})).is_equal("B1 lashed out at B2!")


func test_every_event_from_real_battles_describes_without_error() -> void:
	var seen := {}
	for s in 15:
		var setup := BattleSetup.new()
		setup.add_side([FixtureDB.make(db, "blob", 8), FixtureDB.make(db, "fish", 8), FixtureDB.make(db, "sparky", 8)], 2, 2, {}, "tactician")
		setup.add_side([FixtureDB.make(db, "mole", 8), FixtureDB.make(db, "flame", 8)], 2, 2, {}, "basic")
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var e := BattleEngine.new(db, rng, setup)
		var events := e.start()
		while not e.is_over():
			events.append_array(e.resolve_round([]))
		for ev in events:
			var text := _say(ev)
			seen[ev.type] = true
			if not ev.type in BattleText.SILENT and ev.type in ["move_used", "faint", "send_out", "battle_end"]:
				assert_str(text).is_not_empty()
	assert_bool(seen.has("move_used") and seen.has("faint") and seen.has("battle_end")).is_true()


func test_passive_text_lines() -> void:
	assert_str(_say({"type": "passive_triggered", "bid": 1, "passive": "steady"})).is_equal("B1's Steady!")
	assert_str(_say({"type": "passive_unlocked", "bid": 1, "passive": "steady"})).is_equal("B1 awakened Steady!")
