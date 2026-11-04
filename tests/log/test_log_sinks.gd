extends GdUnitTestSuite
## Log sinks (file, memory, console), config file, and the engine-error bridge.

const DIR := "user://test_logs"
const CFG := "user://test_logging.cfg"

var _state: Dictionary


func before_test() -> void:
	_state = Log.save_state()
	_wipe(DIR)


func after_test() -> void:
	Log.restore_state(_state)
	_wipe(DIR)
	if FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func _record(level: Log.Level, category: String, message: String) -> Dictionary:
	return {"time_ms": 1000, "frame": 1, "level": level, "category": category, "message": message, "data": {}}


func test_file_sink_writes_lines() -> void:
	var sink := LogFileSink.new(DIR, 10, "20261104_120000")
	sink.write(_record(Log.Level.INFO, "save", "written"))
	sink.write(_record(Log.Level.ERROR, "save", "failed"))
	sink.close()
	var text := FileAccess.get_file_as_string(sink.path)
	assert_str(sink.path).ends_with("session_20261104_120000.log")
	assert_str(text).contains("INFO  save      written")
	assert_str(text).contains("ERROR save      failed")


func test_file_sink_keeps_the_newest_10() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for i in 12:
		var f := FileAccess.open("%s/session_200001%02d_000000.log" % [DIR, i + 1], FileAccess.WRITE)
		f.store_string("old")
		f.close()
	var sink := LogFileSink.new(DIR, 10, "20261104_120000")
	sink.close()
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f): return f.ends_with(".log"))
	assert_int(files.size()).is_equal(10)
	assert_bool(files.has("session_20261104_120000.log")).is_true()
	assert_bool(files.has("session_20000101_000000.log")).is_false()  # the oldest went first
	assert_bool(files.has("session_20000103_000000.log")).is_false()


func test_memory_ring_keeps_the_last_n() -> void:
	var mem := LogMemorySink.new(5)
	for i in 8:
		mem.write(_record(Log.Level.INFO if i % 2 == 0 else Log.Level.DEBUG, "battle" if i < 6 else "save", str(i)))
	var all := mem.records()
	assert_int(all.size()).is_equal(5)
	assert_str(all[0].message).is_equal("3")
	assert_str(all[4].message).is_equal("7")
	# Newest first, at least INFO, only "battle".
	var picked := mem.filtered(Log.Level.INFO, "battle").map(func(r): return r.message)
	assert_array(picked).is_equal(["4"])
	assert_int(mem.filtered(Log.Level.TRACE, "").size()).is_equal(5)


func test_config_round_trip() -> void:
	Log.clear_levels()
	Log.default_level = Log.Level.DEBUG
	Log.set_level(Log.BATTLE, Log.Level.TRACE)
	Log.set_level(Log.UI, Log.Level.OFF)
	assert_int(LogConfig.write(CFG)).is_equal(OK)
	Log.clear_levels()
	Log.default_level = Log.Level.ERROR
	LogConfig.read(CFG, Log.Level.INFO)
	assert_int(Log.default_level).is_equal(Log.Level.DEBUG)
	assert_int(Log.level_of(Log.BATTLE)).is_equal(Log.Level.TRACE)
	assert_int(Log.level_of(Log.UI)).is_equal(Log.Level.OFF)


func test_missing_config_uses_the_fallback() -> void:
	Log.clear_levels()
	LogConfig.read("user://no_such_logging.cfg", Log.Level.WARN)
	assert_int(Log.default_level).is_equal(Log.Level.WARN)
	assert_dict(Log.levels()).is_empty()


func test_headless_default_is_warn() -> void:
	assert_int(LogConfig.runtime_default()).is_equal(Log.Level.WARN)


func test_engine_bridge_records_script_errors() -> void:
	var got: Array = []
	var bridge := EngineLogger.new([func(r: Dictionary) -> void: got.append(r)])
	OS.add_logger(bridge)
	push_error("bridge test boom")
	OS.remove_logger(bridge)
	var mine := got.filter(func(r): return "bridge test boom" in r.message)
	assert_int(mine.size()).is_equal(1)
	assert_str(mine[0].category).is_equal(Log.ENGINE)
	assert_int(mine[0].level).is_equal(Log.Level.ERROR)


func test_console_output_is_not_bridged_twice() -> void:
	var got: Array = []
	var bridge := EngineLogger.new([func(r: Dictionary) -> void: got.append(r)])
	OS.add_logger(bridge)
	LogConsoleSink.write(_record(Log.Level.ERROR, "save", "console error once"))
	LogConsoleSink.write(_record(Log.Level.INFO, "save", "console info"))
	OS.remove_logger(bridge)
	assert_array(got.filter(func(r): return "console" in r.message)).is_empty()


func test_headless_startup_ignores_the_saved_levels() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("levels", "default", "INFO")
	cfg.set_value("levels", "battle", "TRACE")
	cfg.save(CFG)
	LogConfig.load_for_startup(CFG)
	assert_int(Log.default_level).is_equal(Log.Level.WARN)
	assert_dict(Log.levels()).is_empty()


func test_migration_failure_is_not_logged_as_migrated() -> void:
	var got: Array = []
	Log.clear_sinks()
	Log.default_level = Log.Level.TRACE
	Log.add_sink(func(r: Dictionary) -> void: got.append(r))
	var f := FileAccess.open("user://test_log_bad_schema.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema": 0}))
	f.close()
	var r := SaveStore.new("user://test_log_sinks_saves").read("user://test_log_bad_schema.json")
	assert_bool(r.ok).is_false()
	assert_array(got.filter(func(x): return x.message == "Migrated")).is_empty()


func test_bridge_does_not_recurse_when_a_sink_raises_an_error() -> void:
	var calls := [0]
	var bridge: EngineLogger
	bridge = EngineLogger.new([func(_r: Dictionary) -> void:
		calls[0] += 1
		if calls[0] < 5:
			push_error("sink trouble")])
	OS.add_logger(bridge)
	push_error("first trouble")
	OS.remove_logger(bridge)
	assert_int(calls[0]).is_equal(1)
