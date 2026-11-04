class_name StoryState
extends RefCounted
## What the world remembers about a playthrough: story flags, counters, which
## one-time pieces are used up (collected items, beaten tamers, one-time
## triggers, keyed by Piece.save_key()), and where the player last rested.

## flag id -> true (cleared flags are removed)
var flags: Dictionary = {}
## counter id -> int
var counters: Dictionary = {}
## piece save key -> true
var done: Dictionary = {}
## { map, spawn } of the last heal spot used; empty = the new-game spawn.
var last_heal: Dictionary = {}


func flag(id: String) -> bool:
	return bool(flags.get(id, false))


func set_flag(id: String, on := true) -> void:
	if on:
		flags[id] = true
	else:
		flags.erase(id)


func count(id: String) -> int:
	return int(counters.get(id, 0))


func add_count(id: String, n := 1) -> void:
	counters[id] = count(id) + n


func is_done(key: String) -> bool:
	return done.has(key)


func mark_done(key: String) -> void:
	done[key] = true


func to_dict() -> Dictionary:
	return {"flags": flags.duplicate(), "counters": counters.duplicate(), "done": done.duplicate(),
		"last_heal": last_heal.duplicate()}


static func from_dict(d: Dictionary) -> StoryState:
	var s := StoryState.new()
	for k in d.get("flags", {}):
		if d.flags[k]:
			s.flags[k] = true
	for k in d.get("counters", {}):
		s.counters[k] = int(d.counters[k])
	for k in d.get("done", {}):
		s.done[k] = true
	var h = d.get("last_heal", {})
	if h is Dictionary and h.has("map") and h.has("spawn"):
		s.last_heal = {"map": str(h.map), "spawn": str(h.spawn)}
	return s
