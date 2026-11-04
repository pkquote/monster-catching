extends GdUnitTestSuite
## The Log class: levels, per-category levels, sinks and formatting.

var records: Array = []
var _state: Dictionary
var _capture := func(r: Dictionary) -> void: records.append(r)


func before_test() -> void:
	_state = Log.save_state()
	Log.clear_sinks()
	Log.clear_levels()
	Log.default_level = Log.Level.INFO
	records.clear()
	Log.add_sink(_capture)


func after_test() -> void:
	Log.restore_state(_state)


func test_levels_filter() -> void:
	Log.trace(Log.BATTLE, "t")
	Log.debug(Log.BATTLE, "d")
	Log.info(Log.BATTLE, "i")
	assert_int(records.size()).is_equal(1)
	assert_int(records[0].level).is_equal(Log.Level.INFO)
	assert_str(records[0].message).is_equal("i")
	assert_str(records[0].category).is_equal("battle")


func test_category_level_overrides_default() -> void:
	Log.set_level(Log.BATTLE, Log.Level.TRACE)
	Log.set_level(Log.SAVE, Log.Level.ERROR)
	Log.trace(Log.BATTLE, "battle trace")
	Log.warn(Log.SAVE, "save warn")
	Log.debug(Log.WORLD, "world debug")
	Log.info(Log.WORLD, "world info")
	assert_array(records.map(func(r): return r.message)).is_equal(["battle trace", "world info"])
	assert_int(Log.level_of(Log.SAVE)).is_equal(Log.Level.ERROR)
	assert_int(Log.level_of("unknown")).is_equal(Log.Level.INFO)


func test_off_silences_a_category() -> void:
	Log.set_level(Log.UI, Log.Level.OFF)
	Log.error(Log.UI, "gone")
	assert_array(records).is_empty()


func test_enabled() -> void:
	Log.set_level(Log.BATTLE, Log.Level.DEBUG)
	assert_bool(Log.enabled(Log.BATTLE, Log.Level.TRACE)).is_false()
	assert_bool(Log.enabled(Log.BATTLE, Log.Level.DEBUG)).is_true()
	assert_bool(Log.enabled(Log.WORLD, Log.Level.DEBUG)).is_false()


func test_record_carries_data_time_and_frame() -> void:
	Log.info(Log.SAVE, "written", {"path": "a.json"})
	var r: Dictionary = records[0]
	assert_dict(r.data).is_equal({"path": "a.json"})
	assert_bool(r.has("time_ms") and r.has("frame")).is_true()


func test_format() -> void:
	var line := Log.format({"time_ms": 12345, "frame": 3, "level": Log.Level.WARN,
		"category": "battle", "message": "Tidepup fainted", "data": {"bid": 2}})
	assert_str(line).is_equal("   12.345 WARN  battle    Tidepup fainted {\"bid\":2}")
	var plain := Log.format({"time_ms": 5, "frame": 0, "level": Log.Level.INFO,
		"category": "ui", "message": "opened", "data": {}})
	assert_str(plain).is_equal("    0.005 INFO  ui        opened")


func test_a_broken_sink_does_not_stop_others() -> void:
	Log.clear_sinks()
	var dead := Callable()
	Log.add_sink(dead)
	Log.add_sink(_capture)
	Log.info(Log.UI, "still delivered")
	assert_int(records.size()).is_equal(1)


func test_remove_sink() -> void:
	Log.remove_sink(_capture)
	Log.info(Log.UI, "nobody hears")
	assert_array(records).is_empty()


func test_level_names_round_trip() -> void:
	for lv in [Log.Level.TRACE, Log.Level.DEBUG, Log.Level.INFO, Log.Level.WARN, Log.Level.ERROR, Log.Level.OFF]:
		assert_int(Log.level_from_name(Log.level_name(lv))).is_equal(lv)
	assert_int(Log.level_from_name("nonsense", Log.Level.WARN)).is_equal(Log.Level.WARN)
