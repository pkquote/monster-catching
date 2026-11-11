extends GdUnitTestSuite
## Loading a save fills the Codex from the creatures it holds.

var _suite: Dictionary


func before() -> void:
	_suite = WorldTest.begin_suite("codex_load", false)


func after() -> void:
	WorldTest.end_suite(_suite)


func test_old_save_loads_with_codex_backfilled() -> void:
	var db: Database = DataRegistry.db
	GameState.start_new_game("Ana")
	var s: SaveGame = GameState.current
	s.party = [CreatureInstance.create(db, "tidepup", 8)]
	s.storage[s.storage.size() - 1] = CreatureInstance.create(db, "pebblet", 5)
	var path := GameState.store.write(s, SaveGame.KIND_MANUAL, GameState.now_ms())
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	d["schema"] = 6
	d.erase("codex")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	GameState.current = null
	assert_str(GameState.load_from(path)).is_empty()
	assert_bool(Codex.caught(GameState.current, "tidepup")).is_true()
	assert_bool(Codex.caught(GameState.current, "pebblet")).is_true()
	assert_int(Codex.caught_count(GameState.current)).is_equal(2)
	# Saved again, the Codex rides along and loads back the same.
	var again := GameState.store.write(GameState.current, SaveGame.KIND_MANUAL, GameState.now_ms() + 1)
	GameState.current = null
	assert_str(GameState.load_from(again)).is_empty()
	assert_int(Codex.caught_count(GameState.current)).is_equal(2)
	assert_bool(Codex.caught(GameState.current, "tidepup")).is_true()
