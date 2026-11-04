extends GdUnitTestSuite
## Every event the engine sends is a known BattleEvents type, and the battle
## screen either describes each type or deliberately keeps it silent.

var real: Database


func before() -> void:
	real = DataLoader.load_database("res://data").db


func test_real_battles_only_send_known_event_types() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var species := Array(real.ids("creatures"))
	species.sort()
	var seen := {}
	for f in [[1, 1], [2, 2], [3, 3], [1, 3], [3, 1], [2, 3]]:
		for run in 4:
			var setup := BattleSetup.new()
			setup.award_xp = run % 2 == 0
			for side in 2:
				var party: Array = []
				for i in 3:
					party.append(CreatureInstance.create(real, species[rng.randi_range(0, species.size() - 1)], 10))
				setup.add_side(party, f[side], f[side], {}, ["tactician", "basic"][(side + run) % 2], true)
			var e := BattleEngine.new(real, rng, setup)
			for ev in e.start():
				seen[ev.type] = true
			while not e.is_over():
				for ev in e.resolve_round([]):
					seen[ev.type] = true
	for t in seen:
		assert_bool(BattleEvents.ALL.has(t)).override_failure_message("unknown event type '%s'" % t).is_true()
	# Sanity: the run exercised the common events.
	for t in [BattleEvents.MOVE_USED, BattleEvents.DAMAGE, BattleEvents.FAINT, BattleEvents.BATTLE_END,
			BattleEvents.UNDERDOG, BattleEvents.XP_GAIN]:
		assert_bool(seen.has(t)).override_failure_message("never saw '%s'" % t).is_true()


func test_battle_text_covers_every_event_type() -> void:
	var source := FileAccess.get_file_as_string("res://game/battle/battle_text.gd")
	for t in BattleEvents.ALL:
		var handled := BattleText.SILENT.has(t) or source.contains('"%s":' % t)
		assert_bool(handled).override_failure_message(
			"BattleText neither describes '%s' nor lists it in SILENT" % t).is_true()


func test_event_names_are_unique() -> void:
	var names := {}
	for t in BattleEvents.ALL:
		assert_bool(names.has(t)).is_false()
		names[t] = true
