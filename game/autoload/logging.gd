extends Node
## Sets up logging at startup (autoload `Logging`, first in the list): levels from
## user://logging.cfg, then the sinks. Console and memory always; a session file
## in user://logs except in headless runs (tests and tools would otherwise rotate
## real play logs away); and the engine-error bridge into the file and memory.
##
## Game code logs through the static `Log` class; this node only owns the sinks.

const LOG_DIR := "user://logs"
const KEEP_FILES := 10
const MEMORY_SIZE := 2000

var memory := LogMemorySink.new(MEMORY_SIZE)
## Where "Save levels" writes (tests point this elsewhere).
var config_path := LogConfig.PATH
var file_sink: LogFileSink

var _bridge: EngineLogger
var _sinks: Array[Callable] = []


func _enter_tree() -> void:
	LogConfig.load_for_startup(LogConfig.PATH)
	_add(LogConsoleSink.write)
	_add(memory.write)
	var bridge_targets: Array = [memory.write]
	if DisplayServer.get_name() != "headless":
		file_sink = LogFileSink.new(LOG_DIR, KEEP_FILES)
		_add(file_sink.write)
		bridge_targets.append(file_sink.write)
	_bridge = EngineLogger.new(bridge_targets)
	OS.add_logger(_bridge)
	var started := {"godot": Engine.get_version_info().string, "os": OS.get_name(),
		"file": ProjectSettings.globalize_path(file_sink.path) if file_sink != null else "",
		"default_level": Log.level_name(Log.default_level)}
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if version != "":
		started["game"] = version
	Log.info(Log.SETTINGS, "Logging started", started)


func _exit_tree() -> void:
	Log.info(Log.SETTINGS, "Logging stopped")
	if _bridge != null:
		OS.remove_logger(_bridge)
		_bridge = null
	for s in _sinks:
		Log.remove_sink(s)
	_sinks.clear()
	if file_sink != null:
		file_sink.close()


func _add(sink: Callable) -> void:
	_sinks.append(sink)
	Log.add_sink(sink)


## The folder that holds the session log files (absolute path).
func log_dir() -> String:
	return ProjectSettings.globalize_path(LOG_DIR)


## Saves the current levels to `config_path` (user://logging.cfg).
func save_levels() -> Error:
	return LogConfig.write(config_path)
