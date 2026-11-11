extends GdUnitTestSuite
## Save format and file store, against a temp folder.

var db: Database
var store: SaveStore
var rng := RandomNumberGenerator.new()


func before() -> void:
	db = FixtureDB.build()


func before_test() -> void:
	store = SaveStore.new(create_temp_dir("saves_%d" % randi()))
	rng.seed = 7


func _game(player := "Ana", t := 1_700_000_000) -> SaveGame:
	return SaveGame.new_game(player, t, rng)


func test_round_trip_keeps_everything() -> void:
	var s := _game()
	s.playtime_sec = 3723.5
	s.location = "Route 1"
	s.money = 250
	s.inventory = {"salve": 3}
	s.story.set_flag("rival_met")
	var c := FixtureDB.make(db, "blob", 7)
	c.bond = 12
	s.party.append(c)
	var path := store.write(s, SaveGame.KIND_MANUAL, 1_700_000_100_000)
	var r := store.read(path)
	assert_bool(r.ok).is_true()
	var back: SaveGame = r.save
	assert_str(back.player_name).is_equal("Ana")
	assert_float(back.playtime_sec).is_equal_approx(3723.5, 0.001)
	assert_str(back.location).is_equal("Route 1")
	assert_int(back.inventory.salve).is_equal(3)
	assert_bool(back.story.flag("rival_met")).is_true()
	assert_int(back.party.size()).is_equal(1)
	assert_int(back.party[0].bond).is_equal(12)
	assert_int(back.saved_unix).is_equal(1_700_000_100)


func test_codex_round_trips() -> void:
	var s := _game()
	Codex.mark_seen(s, "blob")
	Codex.mark_caught(s, "fish")
	var back: SaveGame = store.read(store.write(s, SaveGame.KIND_MANUAL, 1000)).save
	assert_str(Codex.status(back, "blob")).is_equal("seen")
	assert_str(Codex.status(back, "fish")).is_equal("caught")
	assert_int(Codex.seen_count(back)).is_equal(2)


func test_schema_6_save_migrates_with_empty_codex() -> void:
	var s := _game()
	var path := store.write(s, SaveGame.KIND_MANUAL, 1000)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	d["schema"] = 6
	d.erase("codex")
	_write(path, JSON.stringify(d))
	var r := store.read(path)
	assert_bool(r.ok).is_true()
	assert_bool(r.save.codex.is_empty()).is_true()


func test_malformed_codex_entries_are_dropped() -> void:
	var s := _game()
	var path := store.write(s, SaveGame.KIND_MANUAL, 1000)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	d["codex"] = {"blob": {"caught": true}, "fish": "nonsense", "mole": {"seen": true}}
	_write(path, JSON.stringify(d))
	var back: SaveGame = store.read(path).save
	assert_str(Codex.status(back, "blob")).is_equal("caught")
	assert_str(Codex.status(back, "mole")).is_equal("seen")
	assert_str(Codex.status(back, "fish")).is_equal("unseen")
	d["codex"] = "nonsense"
	_write(path, JSON.stringify(d))
	assert_bool(store.read(path).save.codex.is_empty()).is_true()


func test_manual_saves_never_overwrite_each_other() -> void:
	var s := _game()
	var a := store.write(s, SaveGame.KIND_MANUAL, 1000)
	var b := store.write(s, SaveGame.KIND_MANUAL, 1000)  # same millisecond
	assert_str(a).is_not_equal(b)
	assert_array(store.list()).has_size(2)


func test_one_autosave_per_playthrough() -> void:
	var one := _game("Ana")
	var two := _game("Bo")
	store.write(one, SaveGame.KIND_AUTO, 1000)
	store.write(one, SaveGame.KIND_AUTO, 2000)
	store.write(two, SaveGame.KIND_AUTO, 3000)
	var autos := store.list().filter(func(e): return e.kind == SaveGame.KIND_AUTO)
	assert_array(autos).has_size(2)


func test_list_grouped_orders_playthroughs_and_saves_newest_first() -> void:
	var old := _game("Old")
	var fresh := _game("Fresh")
	store.write(old, SaveGame.KIND_MANUAL, 1_000_000)
	store.write(fresh, SaveGame.KIND_MANUAL, 2_000_000)
	store.write(old, SaveGame.KIND_AUTO, 3_000_000)
	var groups := store.list_grouped()
	assert_int(groups.size()).is_equal(2)
	assert_str(groups[0].player_name).is_equal("Old")  # its autosave is the most recent file
	assert_str(groups[0].saves[0].kind).is_equal(SaveGame.KIND_AUTO)
	assert_int(groups[0].saves.size()).is_equal(2)


func test_last_path_tracks_writes_and_loads() -> void:
	var s := _game()
	assert_str(store.last_path()).is_equal("")
	var a := store.write(s, SaveGame.KIND_MANUAL, 1000)
	assert_str(store.last_path()).is_equal(a)
	var b := store.write(s, SaveGame.KIND_AUTO, 2000)
	assert_str(store.last_path()).is_equal(b)
	store.set_last(a)
	assert_str(store.last_path()).is_equal(a)


func test_deleting_resume_target_clears_resume() -> void:
	var s := _game()
	var path := store.write(s, SaveGame.KIND_MANUAL, 1000)
	assert_bool(store.delete(path)).is_true()
	assert_str(store.last_path()).is_equal("")
	assert_array(store.list()).is_empty()


func test_damaged_files_are_listed_not_fatal() -> void:
	var s := _game()
	var good := store.write(s, SaveGame.KIND_MANUAL, 1000)
	var bad := good.get_base_dir().path_join("save_99.json")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var entries := store.list()
	assert_array(entries).has_size(2)
	var damaged := entries.filter(func(e): return e.damaged)
	assert_array(damaged).has_size(1)
	assert_str(damaged[0].error).contains("JSON")
	assert_bool(store.read(bad).ok).is_false()


func test_rejects_newer_schema_and_missing_fields() -> void:
	var s := _game()
	var path := store.write(s, SaveGame.KIND_MANUAL, 1000)
	var d := s.to_dict()
	d.schema = SaveGame.SCHEMA + 1
	_write(path, JSON.stringify(d))
	assert_str(store.read(path).error).contains("newer version")
	_write(path, JSON.stringify({"schema": SaveGame.SCHEMA, "player_name": "x"}))
	assert_str(store.read(path).error).contains("missing required fields")


func test_interrupted_write_recovers_from_temp_file() -> void:
	var s := _game()
	var path := store.write(s, SaveGame.KIND_AUTO, 1000)
	# Simulate a crash between removing the old file and renaming the temp file.
	DirAccess.rename_absolute(path, path + ".tmp")
	assert_bool(store.read(path).ok).is_true()
	assert_array(store.list()).has_size(1)


func test_format_playtime() -> void:
	assert_str(SaveGame.format_playtime(65)).is_equal("1m 05s")
	assert_str(SaveGame.format_playtime(3723)).is_equal("1h 02m")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_v1_save_migrates() -> void:
	var dir := store.root.path_join("1700000000_abcdef")
	DirAccess.make_dir_recursive_absolute(dir)
	var v1 := {"schema": 1, "playthrough_id": "1700000000_abcdef", "kind": "manual", "player_name": "Old",
		"created_unix": 1700000000, "saved_unix": 1700000000, "location": "Nowhere yet",
		"party": [], "storage": [], "inventory": {}, "money": 5,
		"flags": {"debug_test_party_granted": true}}
	var path := dir.path_join("save_1.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	var r := store.read(path)
	assert_bool(r.ok).override_failure_message(str(r.error)).is_true()
	var s: SaveGame = r.save
	assert_bool(s.story.flag("debug_test_party_granted")).is_true()
	assert_str(s.position.get("map", "")).is_equal("")
	assert_int(s.money).is_equal(5)


func test_v2_round_trip_keeps_position() -> void:
	var s := _game()
	s.position = {"map": "test_b", "x": 123.5, "y": 77.0, "facing": "left"}
	s.story.mark_done("test_b/Door1")
	var r := store.read(store.write(s, SaveGame.KIND_MANUAL, 1_700_000_100_000))
	var back: SaveGame = r.save
	assert_dict(back.position).is_equal({"map": "test_b", "x": 123.5, "y": 77.0, "facing": "left"})
	assert_bool(back.story.is_done("test_b/Door1")).is_true()
	assert_int(SaveGame.SCHEMA).is_greater_equal(5)


func test_v2_save_migrates_to_v3() -> void:
	var dir := store.root.path_join("1700000000_abcdef")
	DirAccess.make_dir_recursive_absolute(dir)
	var mon := {"species": "blob", "level": 9, "xp": 0, "hp": 10, "moves": ["hit"]}
	var v2 := {"schema": 2, "playthrough_id": "1700000000_abcdef", "kind": "manual", "player_name": "Old",
		"created_unix": 1700000000, "saved_unix": 1700000000, "location": "Nowhere yet",
		"party": [mon], "storage": [mon.duplicate()], "inventory": {}, "money": 5,
		"story": {"flags": {}}, "position": {}}
	var path := dir.path_join("save_1.json")
	_write(path, JSON.stringify(v2))
	var r := store.read(path)
	assert_bool(r.ok).override_failure_message(str(r.error)).is_true()
	var s: SaveGame = r.save
	assert_array(Array(s.party[0].move_pool)).is_equal(["hit"])
	assert_array(Array(s.storage[0].move_pool)).is_equal(["hit"])


## GameState.load_from tops a migrated save's move pool up from the learnset.
func test_loading_a_v2_save_backfills_the_move_pool() -> void:
	var old_store := GameState.store
	GameState.store = store
	var dir := store.root.path_join("1700000000_abcdef")
	DirAccess.make_dir_recursive_absolute(dir)
	var mon := {"species": "tidepup", "level": 9, "xp": 0, "hp": 10, "moves": ["tackle"]}
	var v2 := {"schema": 2, "playthrough_id": "1700000000_abcdef", "kind": "manual", "player_name": "Old",
		"created_unix": 1700000000, "saved_unix": 1700000000, "location": "Nowhere yet",
		"party": [mon], "storage": [], "inventory": {}, "money": 5,
		"story": {"flags": {}}, "position": {}}
	var path := dir.path_join("save_1.json")
	_write(path, JSON.stringify(v2))
	var err := GameState.load_from(path)
	var pool: Array = Array(GameState.current.party[0].move_pool) if err == "" else []
	GameState.close_game()
	GameState.store = old_store
	assert_str(err).is_empty()
	assert_bool(pool.has("drench")).is_true()
	assert_bool(pool.has("riptide")).is_true()
	assert_bool(pool.has("tackle")).is_true()


func test_v3_save_migrates_to_v4() -> void:
	var dir := store.root.path_join("1700000000_abcdef")
	DirAccess.make_dir_recursive_absolute(dir)
	var mon := {"species": "blob", "level": 9, "xp": 0, "hp": 10, "moves": ["hit"], "move_pool": ["hit"]}
	var v3 := {"schema": 3, "playthrough_id": "1700000000_abcdef", "kind": "manual", "player_name": "Old",
		"created_unix": 1700000000, "saved_unix": 1700000000, "location": "Nowhere yet",
		"party": [mon], "storage": [mon.duplicate()], "inventory": {}, "money": 5,
		"story": {"flags": {}}, "position": {}}
	var path := dir.path_join("save_1.json")
	_write(path, JSON.stringify(v3))
	var r := store.read(path)
	assert_bool(r.ok).override_failure_message(str(r.error)).is_true()
	var s: SaveGame = r.save
	for c: CreatureInstance in [s.party[0], s.storage[0]]:
		assert_str(c.passive).is_empty()
		assert_str(c.affinity_passive).is_empty()
		assert_str(c.active_passive).is_equal("rolled")


func _v4_dict() -> Dictionary:
	var mon := {"species": "tidepup", "level": 9, "xp": 0, "hp": 10, "moves": ["tackle"], "move_pool": ["tackle"],
		"passive": "", "affinity_passive": "", "active_passive": "rolled"}
	return {"schema": 4, "playthrough_id": "1700000000_abcdef", "kind": "manual", "player_name": "Old",
		"created_unix": 1700000000, "saved_unix": 1700000000, "location": "Nowhere yet",
		"party": [mon], "storage": [mon.duplicate()], "inventory": {}, "money": 5,
		"story": {"flags": {}}, "position": {}}


func test_v4_to_v5_adds_held_item() -> void:
	var out := SaveStore._v4_to_v5(_v4_dict())
	assert_int(out.schema).is_equal(5)
	assert_bool(out.party[0].has("held_item")).is_true()
	assert_str(out.party[0].held_item).is_empty()
	assert_str(out.storage[0].held_item).is_empty()
	assert_int(SaveGame.SCHEMA).is_greater_equal(5)


func test_loading_a_v4_save_succeeds() -> void:
	var old_store := GameState.store
	GameState.store = store
	var dir := store.root.path_join("1700000000_abcdef")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("save_1.json")
	_write(path, JSON.stringify(_v4_dict()))
	var err := GameState.load_from(path)
	var held := "x"
	if err == "":
		held = GameState.current.party[0].held_item
	GameState.close_game()
	GameState.store = old_store
	assert_str(err).is_empty()
	assert_str(held).is_empty()


## A v3 save loads end to end: known creatures get a rolled passive, an unknown species is left alone.
func test_loading_a_v3_save_backfills_passives() -> void:
	var old_store := GameState.store
	GameState.store = store
	var dir := store.root.path_join("1700000000_abcdef")
	DirAccess.make_dir_recursive_absolute(dir)
	var mon := {"species": "tidepup", "level": 9, "xp": 0, "hp": 10, "moves": ["tackle"], "move_pool": ["tackle"]}
	var odd := {"species": "no_such_species", "level": 3, "xp": 0, "hp": 5, "moves": [], "move_pool": []}
	var v3 := {"schema": 3, "playthrough_id": "1700000000_abcdef", "kind": "manual", "player_name": "Old",
		"created_unix": 1700000000, "saved_unix": 1700000000, "location": "Nowhere yet",
		"party": [mon], "storage": [mon.duplicate(), odd], "inventory": {}, "money": 5,
		"story": {"flags": {}}, "position": {}}
	var path := dir.path_join("save_1.json")
	_write(path, JSON.stringify(v3))
	var err := GameState.load_from(path)
	var passives: Array = []
	if err == "":
		passives = [GameState.current.party[0].passive, GameState.current.storage[0].passive,
			GameState.current.storage[1].passive]
	GameState.close_game()
	GameState.store = old_store
	assert_str(err).is_empty()
	assert_bool(DataRegistry.db.creature("tidepup").passives.has(passives[0])).is_true()
	assert_str(passives[1]).is_equal(passives[0])
	assert_str(passives[2]).is_empty()


# --- schema 6: slot-addressed boxes ---

func _v5_dict(stored: int) -> Dictionary:
	var d := _v4_dict()
	d.schema = 5
	var list: Array = []
	for i in stored:
		var mon := {"species": "tidepup", "level": 1 + i % 90, "xp": 0, "hp": 10, "moves": ["tackle"],
			"move_pool": ["tackle"], "passive": "", "affinity_passive": "", "active_passive": "rolled",
			"held_item": ""}
		list.append(mon)
	d.storage = list
	d.party = []
	return d


func test_current_schema_is_7() -> void:
	assert_int(SaveGame.SCHEMA).is_equal(7)


func test_schema_5_save_migrates_to_6() -> void:
	for n in [0, 1, 30, 31, 300]:
		var out := SaveStore._v5_to_v6(_v5_dict(n))
		assert_int(out.schema).is_equal(6)
		var want := maxi(BoxStorage.START_BOXES, ceili(n / 30.0))
		assert_int(out.boxes_unlocked).is_equal(want)
		assert_int(out.storage.size()).is_equal(want * 30)
		var path := store.root.path_join("1700000000_abcdef")
		DirAccess.make_dir_recursive_absolute(path)
		_write(path.path_join("save_%d.json" % n), JSON.stringify(_v5_dict(n)))
		var r := store.read(path.path_join("save_%d.json" % n))
		assert_bool(r.ok).is_true()
		var save: SaveGame = r.save
		assert_int(BoxStorage.count(save)).is_equal(n)
		var all := BoxStorage.all_creatures(save)
		for i in n:
			assert_int(all[i].level).is_equal(1 + i % 90)
			assert_that(save.storage[i]).is_same(all[i])  # packed into the first slots
		assert_int(save.boxes_unlocked).is_equal(want)


func test_schema_6_round_trip_keeps_holes() -> void:
	var s := _game()
	for slot in [0, 7, 30]:
		s.storage[slot] = FixtureDB.make(db, "blob", 3 + slot)
	var path := store.write(s, SaveGame.KIND_MANUAL, 1_700_000_100_000)
	var back: SaveGame = store.read(path).save
	assert_int(back.storage.size()).is_equal(240)
	for slot in [0, 7, 30]:
		assert_int(back.storage[slot].level).is_equal(3 + slot)
	assert_object(back.storage[1]).is_null()
	assert_int(BoxStorage.count(back)).is_equal(3)


func test_loading_more_creatures_than_boxes_raises_boxes_unlocked() -> void:
	var s := _game()
	var d := s.to_dict()
	var list: Array = []
	for i in 250:
		list.append(FixtureDB.make(db, "blob", 5).to_dict())
	d.storage = list
	d.boxes_unlocked = 8
	var back := SaveGame.from_dict(d)
	assert_int(BoxStorage.count(back)).is_equal(250)
	assert_int(back.boxes_unlocked).is_equal(9)
	assert_int(back.storage.size()).is_equal(270)
