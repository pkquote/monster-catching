class_name LogConsoleSink
extends RefCounted
## Prints log records to the output panel / terminal. WARN and ERROR go through
## push_warning / push_error so they also show in the editor's debugger. The
## engine bridge is told to ignore these, so they aren't recorded twice.


static func write(record: Dictionary) -> void:
	var line := Log.format(record)
	EngineLogger.ignore_begin()
	match record.level:
		Log.Level.ERROR:
			push_error(line)
		Log.Level.WARN:
			push_warning(line)
		_:
			print(line)
	EngineLogger.ignore_end()
