class_name LogConfig
extends RefCounted
## Log levels saved in user://logging.cfg:
##
##   [levels]
##   default="INFO"
##   battle="TRACE"

const PATH := "user://logging.cfg"


## INFO when playing; WARN for headless runs (tests, tools) so their output stays clean.
static func runtime_default() -> Log.Level:
	return Log.Level.WARN if DisplayServer.get_name() == "headless" else Log.Level.INFO


## Applies the file's levels to Log (default first, then one per category).
## A missing or unreadable file leaves `fallback` as the default and no overrides.
static func read(path: String = PATH, fallback: Log.Level = runtime_default()) -> void:
	Log.default_level = fallback
	Log.clear_levels()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	Log.default_level = Log.level_from_name(str(cfg.get_value("levels", "default", Log.level_name(fallback))), fallback)
	for key in cfg.get_section_keys("levels") if cfg.has_section("levels") else PackedStringArray():
		if key != "default":
			Log.set_level(key, Log.level_from_name(str(cfg.get_value("levels", key)), Log.default_level))


## The levels used at startup: the saved file when playing; always WARN and no
## overrides in headless runs (tests, tools), whatever the file says, so their
## output stays clean and a TRACE level saved for play can't slow them down.
static func load_for_startup(path: String = PATH) -> void:
	if DisplayServer.get_name() == "headless":
		Log.default_level = Log.Level.WARN
		Log.clear_levels()
		return
	read(path, Log.Level.INFO)


static func write(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("levels", "default", Log.level_name(Log.default_level))
	var levels := Log.levels()
	for key in levels:
		cfg.set_value("levels", key, Log.level_name(levels[key]))
	return cfg.save(path)
