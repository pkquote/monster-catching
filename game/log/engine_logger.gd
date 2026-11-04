class_name EngineLogger
extends Logger
## Bridges Godot's own errors and warnings (engine, scripts, push_error from any
## code) into the game's log sinks as category "engine", so a crash's error and
## stack trace land in the same file and viewer as the game's lines.
##
## The engine already prints these to the console, so the bridge feeds only the
## sinks it was given (file, memory), never the console. Lines the console sink
## prints itself are skipped (ignore_begin / ignore_end), so nothing is doubled.
## Godot may call a Logger from any thread; the sinks it feeds lock their state.

## thread id -> depth: only the thread printing its own line is ignored, so an
## engine error raised meanwhile on another thread is still recorded.
static var _ignoring: Dictionary = {}
static var _ignore_lock := Mutex.new()

var _targets: Array[Callable] = []


func _init(targets: Array = []) -> void:
	_targets.assign(targets)


static func ignore_begin() -> void:
	var id := OS.get_thread_caller_id()
	_ignore_lock.lock()
	_ignoring[id] = int(_ignoring.get(id, 0)) + 1
	_ignore_lock.unlock()


static func ignore_end() -> void:
	var id := OS.get_thread_caller_id()
	_ignore_lock.lock()
	var depth := int(_ignoring.get(id, 0)) - 1
	if depth <= 0:
		_ignoring.erase(id)
	else:
		_ignoring[id] = depth
	_ignore_lock.unlock()


static func _ignored() -> bool:
	_ignore_lock.lock()
	var yes := _ignoring.has(OS.get_thread_caller_id())
	_ignore_lock.unlock()
	return yes


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if _ignored():
		return
	var level := Log.Level.WARN if error_type == ERROR_TYPE_WARNING else Log.Level.ERROR
	var message := rationale if rationale != "" else code
	var data := {"at": "%s:%d (%s)" % [file, line, function]}
	if rationale != "" and code != "":
		data["code"] = code
	var trace := PackedStringArray()
	for bt in script_backtraces:
		if bt != null and not bt.is_empty():
			trace.append(bt.format())
	if not trace.is_empty():
		data["backtrace"] = "\n".join(trace)
	_emit(level, message, data)


func _log_message(message: String, error: bool) -> void:
	# Plain print() output isn't logged (it's console chatter); printerr() is.
	if error and not _ignored():
		_emit(Log.Level.WARN, message.strip_edges(), {})


func _emit(level: Log.Level, message: String, data: Dictionary) -> void:
	var record := {"time_ms": Time.get_ticks_msec(), "frame": Engine.get_process_frames(),
		"level": level, "category": Log.ENGINE, "message": message, "data": data}
	ignore_begin()  # an error raised by a sink itself must not come back here
	for t in _targets:
		if t.is_valid():
			t.call(record)
	ignore_end()
