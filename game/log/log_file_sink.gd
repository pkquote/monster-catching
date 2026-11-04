class_name LogFileSink
extends RefCounted
## Writes log records to user://logs/session_<stamp>.log, keeping the newest `keep`
## session files. WARN and ERROR are flushed at once so they survive a crash;
## other lines are flushed at most every FLUSH_MS.

const FLUSH_MS := 500

var path := ""

var _file: FileAccess
var _last_flush := 0
var _mutex := Mutex.new()


func _init(dir: String = "user://logs", keep: int = 10, stamp: String = "") -> void:
	if stamp == "":
		stamp = Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "_")
	DirAccess.make_dir_recursive_absolute(dir)
	path = "%s/session_%s.log" % [dir, stamp]
	var n := 2
	while FileAccess.file_exists(path):  # two runs started in the same second
		path = "%s/session_%s_%d.log" % [dir, stamp, n]
		n += 1
	_rotate(dir, keep - 1)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("Log file couldn't be opened (%s): %s" % [error_string(FileAccess.get_open_error()), path])


## Deletes the oldest session files so at most `room` remain before the new one.
static func _rotate(dir: String, room: int) -> void:
	var files := Array(DirAccess.get_files_at(dir)).filter(
		func(f: String) -> bool: return f.begins_with("session_") and f.ends_with(".log"))
	files.sort()  # the stamp sorts by time
	while files.size() > maxi(0, room):
		DirAccess.remove_absolute(dir.path_join(files.pop_front()))


func write(record: Dictionary) -> void:
	_mutex.lock()
	if _file == null:
		_mutex.unlock()
		return
	_file.store_line(Log.format(record))
	var now := Time.get_ticks_msec()
	if record.level >= Log.Level.WARN or now - _last_flush >= FLUSH_MS:
		_file.flush()
		_last_flush = now
	_mutex.unlock()


func close() -> void:
	_mutex.lock()
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
	_mutex.unlock()
