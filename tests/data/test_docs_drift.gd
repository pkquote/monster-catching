extends GdUnitTestSuite
## Guards against the battle engine reference falling behind the code: every event, every effect op and every
## battle test suite is named in documentation/battle-engine.md. (Found by the 2026-11-12 documentation audit.)

const DOC := "res://documentation/battle-engine.md"

var _text: String


func before() -> void:
	_text = FileAccess.get_file_as_string(DOC)
	assert(not _text.is_empty(), "Could not read %s" % DOC)


func _missing(names: Array, wrap: String) -> Array:
	var out := []
	for n: String in names:
		if not _text.contains(wrap % n):
			out.append(n)
	return out


func test_every_battle_event_is_documented() -> void:
	var events := []
	var consts: Dictionary = load("res://core/battle/battle_events.gd").get_script_constant_map()
	for key: String in consts:
		if consts[key] is String:
			events.append(consts[key])
	assert_array(events).is_not_empty()
	assert_array(_missing(events, "`%s`")).override_failure_message("events missing from battle-engine.md").is_empty()


func test_every_effect_op_is_documented() -> void:
	var ops: Array = DataSchemas.EFFECT_OPS.keys()
	assert_array(_missing(ops, "`%s`")).override_failure_message("effect ops missing from battle-engine.md").is_empty()


func test_every_battle_suite_is_in_the_testing_table() -> void:
	var suites := []
	for file: String in DirAccess.get_files_at("res://tests/battle"):
		if file.begins_with("test_") and file.ends_with(".gd"):
			suites.append(file)
	assert_array(suites).is_not_empty()
	assert_array(_missing(suites, "`%s`")).override_failure_message("battle suites missing from the Testing table").is_empty()


func test_the_ai_reference_covers_every_shipped_style_and_the_engine_doc_points_to_it() -> void:
	# The AI material lives in documentation/ai.md; battle-engine.md only summarises it and links to it.
	var ai := FileAccess.get_file_as_string("res://documentation/ai.md")
	assert_bool(ai.is_empty()).is_false()
	var db: Database = DataLoader.load_database("res://data", "res://dialogue").db
	var missing := []
	for id: String in db.ids("ai_styles"):
		if not ai.contains("`%s`" % id):
			missing.append(id)
	assert_array(missing).override_failure_message("styles missing from ai.md").is_empty()
	assert_bool(_text.contains("(ai.md)")).override_failure_message("battle-engine.md should link to ai.md").is_true()
