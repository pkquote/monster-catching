class_name AchievementWatch
extends RefCounted
## The keys of what changed since the achievement service last looked. Anything that moves a
## counter, the Codex, a story flag or a creature pushes a key here (one dictionary write); the
## service drains the set once per frame and checks only the achievements that watch those keys.
## Pure and static: core code pushes without knowing about the service or the scene tree.

## Check every locked achievement (a load, a debug reset).
const ALL := "*"
const CODEX := "codex"
## A creature's level, Bond or membership changed.
const CREATURE := "creature"

static var _keys: Dictionary = {}


static func counter_key(id: String) -> String:
	return "counter:" + id


static func flag_key(id: String) -> String:
	return "flag:" + id


static func push(key: String) -> void:
	_keys[key] = true


## The pending keys; empties the set.
static func drain() -> PackedStringArray:
	var out := PackedStringArray(_keys.keys())
	_keys.clear()
	return out


static func is_empty() -> bool:
	return _keys.is_empty()


static func clear() -> void:
	_keys.clear()
