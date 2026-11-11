class_name Counters
extends RefCounted
## Lifetime counters, kept in the story store (SaveGame.story.counters) under reserved ids so
## dialogue can read them too (`Story.count("battles_won")`). Hooks bump them where the thing
## happens; see documentation/tracking.md.

const BUILT_IN: PackedStringArray = ["battles_fought", "battles_won", "tamers_defeated",
	"creatures_caught", "creatures_evolved", "items_used", "money_earned", "steps"]


## Adds `n` to a built-in counter. Returns false (and logs an error) for any other id.
static func add(save: SaveGame, id: String, n := 1) -> bool:
	if not BUILT_IN.has(id):
		push_error("Counters: unknown counter id '%s'" % id)
		return false
	save.story.add_count(id, n)
	return true


static func value(save: SaveGame, id: String) -> int:
	return save.story.count(id)
