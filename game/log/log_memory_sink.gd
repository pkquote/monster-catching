class_name LogMemorySink
extends RefCounted
## Keeps the most recent `capacity` log records for the F1 log viewer.

var capacity: int

var _ring: Array = []
var _next := 0
var _mutex := Mutex.new()


func _init(p_capacity: int = 2000) -> void:
	capacity = maxi(1, p_capacity)


func write(record: Dictionary) -> void:
	_mutex.lock()
	if _ring.size() < capacity:
		_ring.append(record)
	else:
		_ring[_next] = record
	_next = (_next + 1) % capacity
	_mutex.unlock()


## Oldest first.
func records() -> Array:
	_mutex.lock()
	var out: Array = _ring.duplicate() if _ring.size() < capacity else _ring.slice(_next) + _ring.slice(0, _next)
	_mutex.unlock()
	return out


## Newest first, at or above `min_level`, in `category` ("" = every category).
func filtered(min_level: Log.Level, category: String) -> Array:
	var out := records().filter(func(r: Dictionary) -> bool:
		return r.level >= min_level and (category == "" or r.category == category))
	out.reverse()
	return out


func clear() -> void:
	_mutex.lock()
	_ring.clear()
	_next = 0
	_mutex.unlock()
