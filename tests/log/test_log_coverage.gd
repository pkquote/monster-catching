extends GdUnitTestSuite
## Spot checks that real actions write the log records the logging spec promises.

var records: Array = []
var _state: Dictionary
var _suite: Dictionary
var _capture := func(r: Dictionary) -> void: records.append(r)


func before() -> void:
	_suite = WorldTest.begin_suite("log_coverage", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func before_test() -> void:
	_state = Log.save_state()
	Log.clear_sinks()
	Log.clear_levels()
	Log.default_level = Log.Level.TRACE
	records.clear()
	Log.add_sink(_capture)
	GameState.start_new_game("Ana")


func after_test() -> void:
	Log.restore_state(_state)
	GameState.close_game()


## Records in `category` whose message contains `text`.
func _find(category: String, text: String) -> Array:
	return records.filter(func(r): return r.category == category and text in r.message)


func test_battle_logs_start_round_events_and_results() -> void:
	var db := DataRegistry.db
	var s := GameState.current
	Story.give_creature("tidepup", 10)
	var e := BattleEngine.new(db, RandomNumberGenerator.new(),
		BattleLauncher.wild_setup(s, [CreatureInstance.create(db, "pebblet", 3)], 1))
	e.start()
	e.resolve_round([BattleAction.use_move(0, "tackle", 1)])
	var started := _find(Log.BATTLE, "Battle started")
	assert_int(started.size()).is_equal(1)
	assert_int(started[0].level).is_equal(Log.Level.INFO)
	var round := _find(Log.BATTLE, "Round 1")
	assert_int(round.size()).is_equal(1)
	assert_int(round[0].level).is_equal(Log.Level.DEBUG)
	assert_str(str(round[0].data.actions)).contains("tackle")
	var events := records.filter(func(r): return r.category == Log.BATTLE and r.level == Log.Level.TRACE)
	assert_bool(events.size() > 2).is_true()
	BattleLauncher.apply_results(db, s, e)
	assert_int(_find(Log.BATTLE, "Results applied").size()).is_equal(1)


func test_trace_events_are_skipped_below_trace() -> void:
	Log.set_level(Log.BATTLE, Log.Level.DEBUG)
	var db := DataRegistry.db
	Story.give_creature("tidepup", 10)
	var e := BattleEngine.new(db, RandomNumberGenerator.new(),
		BattleLauncher.wild_setup(GameState.current, [CreatureInstance.create(db, "pebblet", 3)], 1))
	e.start()
	assert_array(records.filter(func(r): return r.level == Log.Level.TRACE)).is_empty()


func test_save_write_load_and_migration_logged() -> void:
	var path := GameState.save_manual()
	var saved := _find(Log.SAVE, "Saved")
	assert_int(saved.size()).is_equal(1)
	assert_str(saved[0].data.path).is_equal(path)
	assert_str(GameState.load_from(path)).is_empty()
	assert_int(_find(Log.SAVE, "Loaded").size()).is_equal(1)
	var v2 := GameState.current.to_dict()
	v2["schema"] = 2
	var f := FileAccess.open("user://test_log_coverage_v2.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(v2))
	f.close()
	GameState.store.read("user://test_log_coverage_v2.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_log_coverage_v2.json"))
	var migrated := _find(Log.SAVE, "Migrated")
	assert_int(migrated.size()).is_equal(1)
	assert_int(int(migrated[0].data.from)).is_equal(2)
	assert_str(GameState.load_from("user://missing.json")).is_not_empty()
	assert_int(_find(Log.SAVE, "Load failed").size()).is_equal(1)


func test_map_change_and_locks_logged() -> void:
	var world := await WorldTest.open(self, "", "", WorldTest.KEEP_GAME)
	records.clear()
	await world.change_map("test_b", "middle")
	var changed := _find(Log.WORLD, "Map changed")
	assert_int(changed.size()).is_equal(1)
	assert_dict(changed[0].data).contains_key_value("map", "test_b")
	assert_dict(changed[0].data).contains_key_value("spawn", "middle")
	assert_int(_find(Log.WORLD, "Lock taken").size()).is_greater_equal(1)
	assert_int(_find(Log.WORLD, "Lock released").size()).is_greater_equal(1)
	WorldTest.close(world)


func test_level_up_moves_and_growth_logged() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 15)
	c.moves = PackedStringArray(["tackle", "splash_jab", "drench", "riptide"])
	records.clear()
	Progression.award_xp(db, c, Stats.xp_for_level(16) - c.xp)
	var up := _find(Log.PROGRESS, "Level up")
	assert_int(up.size()).is_equal(1)
	assert_int(int(up[0].data.level)).is_equal(16)
	assert_int(up[0].level).is_equal(Log.Level.INFO)
	Progression.apply_growth(db, c, "torrentusk")
	var grew := _find(Log.PROGRESS, "Grew")
	assert_int(grew.size()).is_equal(1)
	assert_dict(grew[0].data).contains_key_value("into", "torrentusk")
	assert_int(_find(Log.PROGRESS, "Move offered").size()).is_greater_equal(1)


func test_training_respec_and_storage_refusal_logged() -> void:
	var db := DataRegistry.db
	var c := Story.give_creature("tidepup", 10)
	Progression.train(db, c, "spd", 2)
	assert_int(_find(Log.PROGRESS, "Trained").size()).is_equal(1)
	Progression.reset_training(db, c)
	assert_int(_find(Log.PROGRESS, "Training reset").size()).is_equal(1)
	assert_str(Team.deposit(db, GameState.current, 0)).is_equal("last_healthy")
	var refused := _find(Log.PROGRESS, "Storage refused")
	assert_int(refused.size()).is_equal(1)
	assert_dict(refused[0].data).contains_key_value("reason", "last_healthy")


func test_story_calls_logged() -> void:
	Story.set_flag("met_prof")
	Story.give_item("salve", 2)
	Story.give_money(50)
	var flag := _find(Log.STORY, "Flag set")
	assert_int(flag.size()).is_equal(1)
	assert_int(flag[0].level).is_equal(Log.Level.INFO)
	assert_int(_find(Log.STORY, "Item given").size()).is_equal(1)
	assert_int(_find(Log.STORY, "Money given").size()).is_equal(1)


func test_screens_open_and_close_logged() -> void:
	var screen := LearnMoveScreen.new()
	add_child(screen)
	screen.close()
	await get_tree().process_frame
	assert_int(_find(Log.UI, "Screen opened").size()).is_equal(1)
	assert_int(_find(Log.UI, "Screen closed").size()).is_equal(1)
