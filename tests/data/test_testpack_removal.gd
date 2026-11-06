extends GdUnitTestSuite
## Proves the test content pack's removal checklist (documentation/battle-engine.md, "Test
## content pack"): data/ validates on its own, and nothing the shipped game is built from refers
## to the pack except the allow-listed lines below, so deleting data_testpack/, the
## DataRegistry pack lines and the pack test suites leaves the game and check.sh intact.
## The reference scan covers only res://data, res://game, res://core and res://dialogue (text files:
## gd, json, tscn, tres, dialogue, cfg, md, txt); tools/, scripts/, tests/ and docs are not scanned
## (the checklist lists their pack lines). This suite is itself one of the pack suites the
## checklist deletes.

const SCANNED_ROOTS: Array = ["res://data", "res://game", "res://core", "res://dialogue"]
const TEXT_EXTENSIONS: Array = ["gd", "json", "tscn", "tres", "dialogue", "cfg", "md", "txt"]
## The only files under SCANNED_ROOTS allowed to mention the pack, and why.
const ALLOWED: Dictionary = {
	# PACK_ROOT and the debug-build-only `packs.append(PACK_ROOT)` (checklist step 2).
	"res://game/autoload/data_registry.gd": "PACK_ROOT",
	# Database.TEST_PREFIX / is_test_content: harmless without the pack, kept.
	"res://core/data/database.gd": "TEST_PREFIX",
	# BattleLauncher.save_safe_species / fill_box (the F1 Fill box filter): harmless, kept.
	"res://game/battle/battle_launcher.gd": "save_safe_species",
	# DebugPassivePage.save_safe_passives (the F1 Set passive filter): harmless, kept.
	"res://game/debug/pages/debug_passive_page.gd": "save_safe_passives",
}


func test_base_data_validates_without_the_pack() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "res://dialogue")
	assert_array(Array(result.errors)).is_empty()
	assert_bool(result.ok()).is_true()
	# Without the pack, the database is exactly the non-tp_ part of data/ + pack.
	var with_pack: Database = DataLoader.load_database("res://data", "", ["res://data_testpack"]).db
	for cat: String in DataSchemas.CATEGORIES:
		if DataSchemas.CATEGORIES[cat] == "single":
			continue
		var expected: Array = Array(with_pack.ids(cat)).filter(func(id: String) -> bool:
			return not Database.is_test_content(id))
		assert_array(Array(result.db.ids(cat))).override_failure_message(cat) 			.contains_exactly_in_any_order(expected)
	assert_int(result.db.count("creatures")).is_greater(0)
	assert_int(with_pack.count("creatures")).is_greater(result.db.count("creatures"))


func test_base_data_alone_reads_without_pack_folders() -> void:
	# data/ is complete by itself: a non-optional read finds every category folder and file.
	var errors: PackedStringArray = PackedStringArray()
	DataLoader.read_raw("res://data", errors)
	assert_array(Array(errors)).is_empty()


func test_only_allow_listed_files_refer_to_the_pack() -> void:
	var pattern: RegEx = RegEx.create_from_string("(?<![A-Za-z0-9_])tp_|data_testpack|testpack")
	var offenders: Array = []
	var allowed_hits: Dictionary = {}
	var scanned: int = 0
	for root: String in SCANNED_ROOTS:
		for path: String in _files(root):
			scanned += 1
			var text: String = FileAccess.get_file_as_string(path)
			if pattern.search(text) == null:
				continue
			if ALLOWED.has(path):
				allowed_hits[path] = true
				assert_str(text).override_failure_message(path).contains(str(ALLOWED[path]))
			else:
				offenders.append(path)
	assert_array(offenders).override_failure_message("files referring to the test pack: %s" % [offenders]) \
		.is_empty()
	# The allow-list stays exact: every entry still refers to the pack (no stale entries).
	assert_array(allowed_hits.keys()).contains_exactly_in_any_order(ALLOWED.keys())
	assert_int(scanned).is_greater(50)


func test_the_pack_root_appears_once_in_the_registry() -> void:
	var text: String = FileAccess.get_file_as_string("res://game/autoload/data_registry.gd")
	assert_int(text.count("data_testpack")).is_equal(1)
	assert_int(text.count("PACK_ROOT")).is_equal(3)
	for path: String in ["res://core/data/database.gd", "res://game/battle/battle_launcher.gd"]:
		assert_int(FileAccess.get_file_as_string(path).count("data_testpack")).override_failure_message(path) \
			.is_equal(0)


func _files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub: String in dir.get_directories():
		out.append_array(_files(dir_path.path_join(sub)))
	for f: String in dir.get_files():
		if f.get_extension() in TEXT_EXTENSIONS:
			out.append(dir_path.path_join(f))
	return out
