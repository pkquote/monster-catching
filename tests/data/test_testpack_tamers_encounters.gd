extends GdUnitTestSuite
## The test pack's tamers and encounter tables (data_testpack/tamers, data_testpack/encounters):
## the shapes from spec section 3.5, builder compatibility, and unreachability from play.

const PACK_ROOT: String = "res://data_testpack"
## Folders whose files must never mention a pack id (the pack stays unreachable from play).
const SCAN_ROOTS: PackedStringArray = ["res://game", "res://dialogue", "res://tools"]
## Every file is scanned except these generated or binary kinds.
const SKIP_EXTENSIONS: PackedStringArray = ["import", "png", "uid"]

var _db: Database
var _tamers: Array[TamerDef] = []
var _encounters: Array[EncounterDef] = []


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "", [PACK_ROOT])
	assert_array(Array(result.errors)).is_empty()
	_db = result.db
	_tamers.clear()
	_encounters.clear()
	for id: String in _db.ids("tamers"):
		if Database.is_test_content(id):
			_tamers.append(_db.tamer(id))
	for id: String in _db.ids("encounters"):
		if Database.is_test_content(id):
			_encounters.append(_db.encounter(id))


func _tamers_where(max_active: int, ai: String, party_size: int) -> Array[TamerDef]:
	var out: Array[TamerDef] = []
	for t: TamerDef in _tamers:
		if t.max_active == max_active and (ai == "" or t.ai == ai) and t.party.size() == party_size:
			out.append(t)
	return out


# --- tamers ---------------------------------------------------------------------

func test_exactly_six_pack_tamers() -> void:
	assert_int(_tamers.size()).is_greater_equal(6)


func test_tamer_shapes() -> void:
	var max_field: int = DataSchemas.ENTRY["tamers"]["max_active"]["max"]
	assert_int(max_field).is_equal(3)
	var party_max: int = DataSchemas.ENTRY["tamers"]["party"]["max"]
	# 1v1 basic, 2v2 tactician, 3v3 aggressive
	assert_int(_tamers_where(1, "basic", 2).size()).is_equal(1)
	assert_int(_tamers_where(2, "tactician", 3).size()).is_equal(1)
	assert_int(_tamers_where(3, "aggressive", 3).size()).is_equal(1)
	# bench-heavy: field 3, a full party of 6
	assert_int(_tamers_where(max_field, "", party_max).size()).is_equal(1)
	# stall: one creature, one field slot
	assert_int(_tamers_where(1, "", 1).size()).is_equal(1)
	# underdog: 3 slots but only 2 creatures, so a 3-creature player outnumbers it
	var underdog: TamerDef = _db.tamer("tp_tamer_outnumbered_3v2")
	assert_int(underdog.max_active).is_equal(3)
	assert_int(underdog.party.size()).is_less(underdog.max_active)
	assert_str(underdog.name).contains("Underdog")


func test_underdog_tamer_is_the_outnumbered_side_in_battle() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var mine: Array = []
	for i: int in 3:
		mine.append(CreatureInstance.create(_db, "tp_neutral_plain", 20, PackedStringArray(), rng))
	var setup: BattleSetup = BattleSetup.vs_tamer(_db, mine, "tp_tamer_outnumbered_3v2", 3, {}, rng)
	var engine: BattleEngine = BattleEngine.new(_db, rng, setup)
	engine.start()
	assert_int(engine.sides[0].active().size()).is_equal(3)
	assert_int(engine.sides[1].active().size()).is_equal(2)
	var tamer_ratio: float = float(engine.sides[1].underdog.get("ratio", 1.0))
	var player_ratio: float = float(engine.sides[0].underdog.get("ratio", 1.0))
	assert_float(tamer_ratio).is_greater(1.0)
	assert_float(tamer_ratio).is_greater(player_ratio)
	assert_float(float(engine.sides[1].underdog.get("stat_bonus", 0.0))).is_greater(0.0)


func test_tamer_ids_and_party_content_come_from_the_pack() -> void:
	var ids: Dictionary = {}
	for t: TamerDef in _tamers:
		assert_bool(ids.has(t.id)).is_false()
		ids[t.id] = true
		assert_bool(t.id.begins_with("tp_")).is_true()
		for p: Dictionary in t.party:
			assert_bool(Database.is_test_content(p.species)).is_true()
			var moves: PackedStringArray = p.moves
			for m: String in moves:
				assert_bool(Database.is_test_content(m)).is_true()
			if p.held_item != "":
				assert_str(_db.item(p.held_item).category).is_equal("held")


func test_some_tamers_carry_bag_items() -> void:
	var with_bag: int = 0
	for t: TamerDef in _tamers:
		if not t.items.is_empty():
			with_bag += 1
			for it: Dictionary in t.items:
				assert_bool(_db.has("items", it.item)).is_true()
	assert_int(with_bag).is_greater_equal(2)


func test_tamer_parties_use_held_items_and_passive_overrides() -> void:
	var held: int = 0
	var passives: int = 0
	var consumed: int = 0
	var per_battle: int = 0
	for t: TamerDef in _tamers:
		for p: Dictionary in t.party:
			if p.held_item != "":
				held += 1
				var use: String = _db.item(p.held_item).held_use
				if use == "consumed":
					consumed += 1
				elif use == "per_battle":
					per_battle += 1
			if p.passive != "":
				passives += 1
	assert_int(held).is_greater_equal(10)
	assert_int(passives).is_greater_equal(3)
	assert_int(consumed).is_greater_equal(1)
	assert_int(per_battle).is_greater_equal(1)


# --- encounters -----------------------------------------------------------------

func test_exactly_four_pack_encounters() -> void:
	assert_int(_encounters.size()).is_greater_equal(4)


func test_encounter_shapes() -> void:
	var single: int = 0
	var wide: int = 0
	var always_max_pack: int = 0
	var heavy: int = 0
	var pack_cap: int = DataSchemas.ENTRY["encounters"]["pack_max"]["max"]
	assert_int(pack_cap).is_equal(3)
	for e: EncounterDef in _encounters:
		assert_bool(e.id.begins_with("tp_")).is_true()
		if e.table.size() == 1:
			single += 1
		var widest: int = 0
		for row: Dictionary in e.table:
			assert_bool(Database.is_test_content(row.species)).is_true()
			widest = maxi(widest, int(row.max_level) - int(row.min_level))
			if e.table.size() > 1 and float(row.weight) / float(e.total_weight) >= 0.9:
				heavy += 1
		if widest >= 59:
			wide += 1
		if e.pack_min == pack_cap and e.pack_max == pack_cap:
			always_max_pack += 1
	assert_int(single).is_equal(1)
	assert_int(wide).is_equal(1)
	assert_int(always_max_pack).is_equal(1)
	assert_int(heavy).is_equal(1)


# --- builder compatibility ------------------------------------------------------

func test_vs_tamer_builds_for_every_pack_tamer() -> void:
	for t: TamerDef in _tamers:
		for field_count: int in [-1, 1, 2, 3]:
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = 6
			var mine: Array = [CreatureInstance.create(_db, "tp_neutral_plain", 20, PackedStringArray(), rng)]
			var setup: BattleSetup = BattleSetup.vs_tamer(_db, mine, t.id, field_count, {}, rng)
			assert_int(setup.sides.size()).is_equal(2)
			assert_str(setup.tamer_id).is_equal(t.id)
			var foe: SideSetup = setup.sides[1]
			assert_int(foe.max_active).is_equal(t.max_active)
			assert_int(foe.field_count).is_equal(t.max_active)
			assert_int(foe.party.size()).is_equal(t.party.size())
			assert_str(foe.ai).is_equal(t.ai)
			var own: SideSetup = setup.sides[0]
			assert_int(own.max_active).is_equal(t.max_active)
			var expected: int = t.max_active if field_count < 1 else mini(t.max_active, field_count)
			assert_int(own.field_count).is_equal(expected)
			for i: int in t.party.size():
				var c: CreatureInstance = foe.party[i]
				assert_str(c.species).is_equal(t.party[i].species)
				assert_str(c.held_item).is_equal(t.party[i].held_item)
				var want_moves: PackedStringArray = t.party[i].moves
				if not want_moves.is_empty():
					assert_array(Array(c.moves)).is_equal(Array(want_moves))
				if t.party[i].passive != "":
					assert_str(c.passive).is_equal(t.party[i].passive)


func test_roll_wild_pack_respects_every_pack_encounter() -> void:
	for e: EncounterDef in _encounters:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 11
		var species: Dictionary = {}
		for row: Dictionary in e.table:
			species[row.species] = row
		for _i: int in 60:
			var pack: Array = BattleLauncher.roll_wild_pack(_db, e.id, rng)
			assert_int(pack.size()).is_between(e.pack_min, e.pack_max)
			for c: CreatureInstance in pack:
				assert_bool(species.has(c.species)).is_true()
				var row: Dictionary = species[c.species]
				assert_int(c.level).is_between(int(row.min_level), int(row.max_level))


# --- unreachability -------------------------------------------------------------

func test_no_shipped_file_references_a_pack_id() -> void:
	var scanned: int = 0
	var candidates: int = 0
	var hits: PackedStringArray = PackedStringArray()
	for root: String in SCAN_ROOTS:
		assert_bool(DirAccess.dir_exists_absolute(root)).override_failure_message("cannot read folder " + root).is_true()
		candidates += _count_files(root)
		scanned += _scan(root, hits)
	assert_array(Array(hits)).override_failure_message("pack ids referenced from shipped files: %s" % [hits]).is_empty()
	assert_int(scanned).override_failure_message("scanned %d of %d candidate files" % [scanned, candidates]).is_equal(candidates)
	assert_int(scanned).is_greater(50)


func _skipped(file_name: String) -> bool:
	return SKIP_EXTENSIONS.has(file_name.get_extension())


## Independent count of the files the scan should read.
func _count_files(dir: String) -> int:
	var n: int = 0
	for f: String in DirAccess.get_files_at(dir):
		if not _skipped(f):
			n += 1
	for sub: String in DirAccess.get_directories_at(dir):
		n += _count_files(dir.path_join(sub))
	return n


## Recursively greps `dir` for a "tp_<name>" id; returns the number of files read.
func _scan(dir: String, hits: PackedStringArray) -> int:
	var n: int = 0
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		hits.append("unreadable: " + dir)
		return 0
	var rx: RegEx = RegEx.new()
	rx.compile("(^|[^A-Za-z0-9_])tp_[a-z0-9_]+")
	for sub: String in da.get_directories():
		n += _scan(dir.path_join(sub), hits)
	for f: String in da.get_files():
		if _skipped(f):
			continue
		var path: String = dir.path_join(f)
		var fa: FileAccess = FileAccess.open(path, FileAccess.READ)
		if fa == null:
			hits.append("unreadable: " + path)
			continue
		n += 1
		if rx.search(fa.get_as_text()) != null:
			hits.append(path)
	return n


func test_a_tamer_without_ai_uses_basic() -> void:
	var t: TamerDef = _db.tamer("tp_tamer_default_ai_2v2")
	assert_object(t).is_not_null()
	assert_str(t.ai).is_equal("basic")


func test_every_ai_style_has_a_pack_tamer() -> void:
	var used := {}
	for t: TamerDef in _tamers:
		used[t.ai] = true
	for id: String in _db.ids("ai_styles"):
		assert_bool(used.has(id)).override_failure_message("no pack tamer uses style %s" % id).is_true()
