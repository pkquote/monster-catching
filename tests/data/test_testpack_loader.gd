extends GdUnitTestSuite
## Layered test-pack loading: packs merge over data/, tolerate absence, and
## collisions or dangling references surface as validation errors.

const PROBE_MOVE := '{"id": "tp_probe", "name": "Probe", "type": "neutral", "category": "physical", "power": 40, "cost": 1, "accuracy": 100, "target": "one_enemy", "effects": [{"op": "damage"}]}'

var _dirs: PackedStringArray = []


func after_test() -> void:
	for d: String in _dirs:
		_remove_recursive(d)
	_dirs.clear()


func test_pack_entries_merge_into_the_database() -> void:
	var root: String = _make_pack("merge", {"moves/probe.json": _entries(PROBE_MOVE)})
	var result := DataLoader.load_database("res://data", "", [root])
	assert_array(Array(result.errors)).is_empty()
	var ids: PackedStringArray = result.db.ids("moves")
	assert_bool(ids.has("tp_probe")).is_true()
	assert_bool(ids.has("tackle")).is_true()
	assert_bool(result.db.has("creatures", "tidepup")).is_true()


func test_missing_pack_root_is_ignored() -> void:
	var result := DataLoader.load_database("res://data", "", ["user://testpack_does_not_exist"])
	assert_array(Array(result.errors)).is_empty()
	assert_object(result.db).is_not_null()
	assert_bool(result.db.has("moves", "tackle")).is_true()


func test_missing_category_folders_are_skipped() -> void:
	var root: String = _make_pack("onlymoves", {"moves/probe.json": _entries(PROBE_MOVE)})
	var errors := PackedStringArray()
	var raw := DataLoader.read_raw(root, errors, null, true)
	assert_array(Array(errors)).is_empty()
	assert_int(raw.get_entries("moves").size()).is_equal(1)
	assert_int(raw.get_entries("creatures").size()).is_equal(0)


func test_duplicate_id_across_pack_and_base_is_an_error() -> void:
	var dup: String = PROBE_MOVE.replace("tp_probe", "tackle")
	var root: String = _make_pack("dup", {"moves/dup.json": _entries(dup)})
	var result := DataLoader.load_database("res://data", "", [root])
	assert_bool(result.ok()).is_false()
	assert_str(" ".join(result.errors)).contains("tackle").contains("duplicate id")


func test_dangling_reference_in_pack_is_an_error() -> void:
	var creature: String = '{"id": "tp_dangler", "name": "Dangler", "types": ["fire"], "base_stats": {"hp": 45, "patk": 45, "pdef": 40, "satk": 60, "sdef": 45, "spd": 60, "luck": 55, "resolve": 40, "stamina": 50}, "catch_rate": 0.45, "xp_yield": 55, "learnset": [{"level": 1, "move": "tp_no_such_move"}], "passives": [], "affinity_passives": {}}'
	var root: String = _make_pack("dangling", {"creatures/dangler.json": _entries(creature)})
	var result := DataLoader.load_database("res://data", "", [root])
	assert_bool(result.ok()).is_false()
	assert_str(" ".join(result.errors)).contains("tp_no_such_move")


func test_pack_balance_file_is_ignored() -> void:
	# Balance is reused from data/: a pack's balance.json (a "single" category) is skipped
	# silently, even when it would be invalid on its own.
	var base: Database = DataLoader.load_database("res://data").db
	var root: String = _make_pack("balance", {"moves/probe.json": _entries(PROBE_MOVE),
		"balance.json": '{"schema": 1, "data": {"round_limit": 7}}'})
	var result := DataLoader.load_database("res://data", "", [root])
	assert_array(Array(result.errors)).is_empty()
	assert_int(base.balance.round_limit).is_equal(200)
	assert_int(result.db.balance.round_limit).is_equal(200)
	assert_int(result.db.balance.party_size).is_equal(base.balance.party_size)
	assert_bool(result.db.has("moves", "tp_probe")).is_true()


func test_pack_has_entries() -> void:
	assert_bool(DataLoader.pack_has_entries("user://testpack_does_not_exist")).is_false()
	var empty: String = _make_pack("empty", {"moves/notes.txt": "not json"})
	assert_bool(DataLoader.pack_has_entries(empty)).is_false()
	var nested: String = _make_pack("nested", {"creatures/sub/c.json": _entries("")})
	assert_bool(DataLoader.pack_has_entries(nested)).is_true()
	var file_cat: String = _make_pack("filecat", {"types.json": _entries("")})
	assert_bool(DataLoader.pack_has_entries(file_cat)).is_true()
	assert_bool(DataLoader.pack_has_entries("res://data_testpack")).is_true()


func test_registry_falls_back_to_base_data_when_the_pack_is_broken() -> void:
	var creature: String = '{"id": "tp_dangler", "name": "Dangler", "types": ["fire"], "base_stats": {"hp": 45, "patk": 45, "pdef": 40, "satk": 60, "sdef": 45, "spd": 60, "luck": 55, "resolve": 40, "stamina": 50}, "catch_rate": 0.45, "xp_yield": 55, "learnset": [{"level": 1, "move": "tp_no_such_move"}], "passives": [], "affinity_passives": {}}'
	var broken: String = _make_pack("broken", {"creatures/dangler.json": _entries(creature)})
	var good: String = _make_pack("good", {"moves/probe.json": _entries(PROBE_MOVE)})
	var records: Array = []
	var state: Dictionary = Log.save_state()
	Log.clear_sinks()
	Log.add_sink(func(r: Dictionary) -> void: records.append(r))
	var fell_back: DataLoader.LoadResult = DataRegistry.load_with_fallback("res://data", "", [broken])
	var with_good: DataLoader.LoadResult = DataRegistry.load_with_fallback("res://data", "", [good])
	var good_records: int = records.size()
	var no_base: DataLoader.LoadResult = DataRegistry.load_with_fallback("user://testpack_no_base", "", [good])
	Log.restore_state(state)
	# A broken pack: base data loads alone and the pack's errors are logged.
	assert_bool(fell_back.ok()).is_true()
	assert_bool(fell_back.db.has("creatures", "tidepup")).is_true()
	assert_bool(fell_back.db.has("creatures", "tp_dangler")).is_false()
	assert_int(good_records).is_greater(1)
	var texts: String = ""
	for r: Dictionary in records.slice(0, good_records):
		assert_int(int(r.level)).is_equal(Log.Level.ERROR)
		assert_str(str(r.category)).is_equal(Log.DATA)
		texts += str(r.message) + "\n"
	assert_str(texts).contains("tp_no_such_move").contains("without the pack")
	# A good pack loads with no log records.
	assert_bool(with_good.ok()).is_true()
	assert_bool(with_good.db.has("moves", "tp_probe")).is_true()
	# Broken base data still fails (the existing behaviour), with its own errors.
	assert_bool(no_base.ok()).is_false()
	assert_str(" ".join(no_base.errors)).contains("testpack_no_base")


func test_is_test_content() -> void:
	assert_bool(Database.is_test_content("tp_x")).is_true()
	assert_bool(Database.is_test_content("tidepup")).is_false()
	assert_bool(Database.is_test_content("")).is_false()


func test_registry_pack_root_constant() -> void:
	assert_str(DataRegistry.PACK_ROOT).is_equal("res://data_testpack")


func _entries(body: String) -> String:
	return '{"schema": 1, "entries": [%s]}' % body


## Writes `files` (relative path -> text) under a fresh user:// folder.
func _make_pack(name: String, files: Dictionary) -> String:
	var root: String = "user://testpack_%s_%d" % [name, Time.get_ticks_usec()]
	_dirs.append(root)
	for rel: String in files:
		var path: String = root.path_join(rel)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(files[rel])
		f.close()
	return root


func _remove_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_remove_recursive(path.path_join(sub))
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
