extends GdUnitTestSuite
## Test-pack (tp_) content must never reach a real save through a random pick.

var _dirs: PackedStringArray = []


func after_test() -> void:
	for d: String in _dirs:
		_remove_recursive(d)
	_dirs.clear()


## A database of data/ plus a pack holding one tp_ creature, one tp_ move and a tp_ encounter table.
func _pack_db() -> Database:
	var move: String = '{"id": "tp_jab", "name": "Jab", "type": "neutral", "category": "physical", "power": 40, "cost": 1, "accuracy": 100, "target": "one_enemy", "effects": [{"op": "damage"}]}'
	var passive: String = '{"id": "tp_pass", "name": "Pass", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.0}]}'
	var creature: String = '{"id": "tp_dummy", "name": "Dummy", "types": ["fire"], "base_stats": {"hp": 45, "patk": 45, "pdef": 40, "satk": 60, "sdef": 45, "spd": 60, "luck": 55, "resolve": 40, "stamina": 50}, "catch_rate": 0.45, "xp_yield": 55, "learnset": [{"level": 1, "move": "tp_jab"}], "passives": ["tp_pass"]}'
	var enc: String = '{"id": "tp_all_pack", "name": "Pack", "pack_min": 1, "pack_max": 1, "table": [{"species": "tp_dummy", "weight": 1, "min_level": 3, "max_level": 3}]}'
	var root: String = _make_pack({
		"moves/m.json": _entries(move), "passives/p.json": _entries(passive),
		"creatures/c.json": _entries(creature), "encounters/e.json": _entries(enc)})
	var result := DataLoader.load_database("res://data", "", [root])
	assert_array(Array(result.errors)).is_empty()
	assert_bool(result.db.has("creatures", "tp_dummy")).is_true()
	return result.db


func test_save_safe_species_drops_only_pack_ids() -> void:
	var db: Database = _pack_db()
	var safe: Array = BattleLauncher.save_safe_species(db)
	assert_bool(safe.has("tp_dummy")).is_false()
	for id: String in safe:
		assert_bool(Database.is_test_content(id)).is_false()
	var base: Database = DataLoader.load_database("res://data").db
	assert_array(safe).contains_exactly_in_any_order(Array(base.ids("creatures")))
	var sorted: Array = safe.duplicate()
	sorted.sort()
	assert_array(safe).is_equal(sorted)


func test_fill_box_never_adds_a_pack_creature() -> void:
	var db: Database = _pack_db()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var save: SaveGame = SaveGame.new_game("Ana", 1000, rng)
	for batch: int in 10:
		BattleLauncher.fill_box(db, save, 12, 7, rng)
	assert_int(BoxStorage.count(save)).is_equal(120)
	for c: CreatureInstance in BoxStorage.all_creatures(save):
		assert_bool(Database.is_test_content(c.species)).override_failure_message(c.species).is_false()
		assert_int(c.level).is_equal(7)


func test_roll_wild_pack_from_a_base_table_never_yields_pack_species() -> void:
	var db: Database = _pack_db()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var seen: int = 0
	for i: int in 200:
		for c: CreatureInstance in BattleLauncher.roll_wild_pack(db, "route_01_grass", rng):
			seen += 1
			assert_bool(Database.is_test_content(c.species)).is_false()
	assert_int(seen).is_greater(0)


func test_pack_encounter_table_is_the_only_way_to_roll_a_pack_species() -> void:
	# Sanity check that the guard above is meaningful: the pack table does roll tp_dummy.
	var db: Database = _pack_db()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var pack: Array = BattleLauncher.roll_wild_pack(db, "tp_all_pack", rng)
	assert_str(pack[0].species).is_equal("tp_dummy")


func test_set_passive_page_drops_only_pack_passives() -> void:
	# F1 "Set passive" writes to the real party and autosaves.
	var db: Database = _pack_db()
	var safe: PackedStringArray = DebugPassivePage.save_safe_passives(db)
	assert_bool(db.has("passives", "tp_pass")).is_true()
	assert_bool(safe.has("tp_pass")).is_false()
	var base: Database = DataLoader.load_database("res://data").db
	assert_array(Array(safe)).contains_exactly_in_any_order(Array(base.ids("passives")))


func test_shipped_tamers_never_field_pack_content_with_the_pack_loaded() -> void:
	# Tamer parties come from the tamer tables, so only a tp_ tamer can field a tp_ creature.
	var loaded: DataLoader.LoadResult = DataLoader.load_database("res://data", "", ["res://data_testpack"])
	assert_array(Array(loaded.errors)).is_empty()
	var db: Database = loaded.db
	var player: Array = [CreatureInstance.create(db, "tidepup", 10)]
	var checked: int = 0
	for tamer: String in db.ids("tamers"):
		if Database.is_test_content(tamer):
			continue
		for s: int in 5:
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = s
			var setup: BattleSetup = BattleSetup.vs_tamer(db, player, tamer, -1, {}, rng)
			assert_int(setup.sides[1].party.size()).is_greater(0)
			for c: CreatureInstance in setup.sides[1].party:
				var what: String = "%s: %s / %s / %s" % [tamer, c.species, c.passive, c.held_item]
				assert_bool(Database.is_test_content(c.species)).override_failure_message(what).is_false()
				assert_bool(Database.is_test_content(c.passive)).override_failure_message(what).is_false()
				assert_bool(Database.is_test_content(c.held_item)).override_failure_message(what).is_false()
				for m: String in c.moves:
					assert_bool(Database.is_test_content(m)).override_failure_message(what + " " + m).is_false()
			for item: String in setup.sides[1].items:
				assert_bool(Database.is_test_content(item)).override_failure_message(tamer + " " + item).is_false()
		checked += 1
	# Every shipped tamer (those in a base-only database) was checked, and the pack adds some.
	var base: Database = DataLoader.load_database("res://data").db
	assert_int(checked).is_equal(base.count("tamers"))
	assert_int(checked).is_greater(0)
	assert_int(db.count("tamers")).is_greater(base.count("tamers"))


func _entries(body: String) -> String:
	return '{"schema": 1, "entries": [%s]}' % body


func _make_pack(files: Dictionary) -> String:
	var root: String = "user://testpack_safety_%d" % Time.get_ticks_usec()
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
