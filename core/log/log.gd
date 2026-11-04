class_name Log
extends RefCounted
## Logging for the whole game. Static, so pure core/ code, tools and tests can use it:
##
##   Log.info(Log.BATTLE, "Battle started", {"format": "2v2"})
##   if Log.enabled(Log.BATTLE, Log.Level.TRACE):   # skip building costly messages
##       Log.trace(Log.BATTLE, describe(event))
##
## Each category has a minimum level (falling back to `default_level`). Records that
## pass go to every registered sink (console, file, memory: see game/log/). With no
## sinks registered, WARN and ERROR still reach Godot through push_warning/push_error.

enum Level { TRACE, DEBUG, INFO, WARN, ERROR, OFF }

const BATTLE := "battle"
const SAVE := "save"
const WORLD := "world"
const STORY := "story"
const PROGRESS := "progress"
const UI := "ui"
const DATA := "data"
const SETTINGS := "settings"
const MINIGAME := "minigame"
## Errors and warnings raised by the engine or by scripts (see game/log/engine_logger.gd).
const ENGINE := "engine"
const CATEGORIES: PackedStringArray = [BATTLE, SAVE, WORLD, STORY, PROGRESS, UI, DATA, SETTINGS,
	MINIGAME, ENGINE]

const LEVEL_NAMES := {Level.TRACE: "TRACE", Level.DEBUG: "DEBUG", Level.INFO: "INFO",
	Level.WARN: "WARN", Level.ERROR: "ERROR", Level.OFF: "OFF"}

static var default_level: Level = Level.INFO
static var _levels: Dictionary = {}
static var _sinks: Array[Callable] = []


static func trace(category: String, message: String, data: Dictionary = {}) -> void:
	write(Level.TRACE, category, message, data)


static func debug(category: String, message: String, data: Dictionary = {}) -> void:
	write(Level.DEBUG, category, message, data)


static func info(category: String, message: String, data: Dictionary = {}) -> void:
	write(Level.INFO, category, message, data)


static func warn(category: String, message: String, data: Dictionary = {}) -> void:
	write(Level.WARN, category, message, data)


static func error(category: String, message: String, data: Dictionary = {}) -> void:
	write(Level.ERROR, category, message, data)


static func write(level: Level, category: String, message: String, data: Dictionary = {}) -> void:
	if not enabled(category, level):
		return
	var record := {"time_ms": Time.get_ticks_msec(), "frame": Engine.get_process_frames(),
		"level": level, "category": category, "message": message, "data": data}
	if _sinks.is_empty():
		if level == Level.ERROR:
			push_error(format(record))
		elif level == Level.WARN:
			push_warning(format(record))
		return
	for sink in _sinks:
		if sink.is_valid():
			sink.call(record)


## Whether a record of `level` in `category` would be kept.
static func enabled(category: String, level: Level) -> bool:
	return level != Level.OFF and level >= level_of(category)


static func level_of(category: String) -> Level:
	return _levels.get(category, default_level)


static func set_level(category: String, level: Level) -> void:
	_levels[category] = level


static func clear_levels() -> void:
	_levels.clear()


## Category -> Level overrides currently set.
static func levels() -> Dictionary:
	return _levels.duplicate()


static func add_sink(sink: Callable) -> void:
	if not _sinks.has(sink):
		_sinks.append(sink)


static func remove_sink(sink: Callable) -> void:
	_sinks.erase(sink)


static func clear_sinks() -> void:
	_sinks.clear()


## Everything configurable, so tests can change it and put it back.
static func save_state() -> Dictionary:
	return {"default": default_level, "levels": _levels.duplicate(), "sinks": _sinks.duplicate()}


static func restore_state(state: Dictionary) -> void:
	default_level = state.default
	_levels = state.levels.duplicate()
	_sinks.assign(state.sinks)


## "   12.345 WARN  battle    Tidepup fainted {"bid":2}" (seconds since start).
static func format(record: Dictionary) -> String:
	var line := "%9.3f %-5s %-9s %s" % [float(record.time_ms) / 1000.0, level_name(record.level),
		record.category, record.message]
	if not (record.data as Dictionary).is_empty():
		line += " " + JSON.stringify(record.data)
	return line


static func level_name(level: Level) -> String:
	return LEVEL_NAMES.get(level, "INFO")


static func level_from_name(name: String, fallback: Level = Level.INFO) -> Level:
	for lv in LEVEL_NAMES:
		if LEVEL_NAMES[lv] == name.to_upper():
			return lv
	return fallback
