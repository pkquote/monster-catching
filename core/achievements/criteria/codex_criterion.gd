class_name CodexCriterion
extends Criterion
## `{"kind": "codex", "mode": "seen"|"caught", "target": n}`, the same with `"all": true` in place of a
## target (every species), or `{"mode": "species", "species": id}`: enough species seen or caught, or one
## named species caught. Only species in the Codex list count.


func kind() -> String:
	return "codex"


func watches(_c: Dictionary) -> PackedStringArray:
	return PackedStringArray([AchievementWatch.CODEX])


func progress(db: Database, save: SaveGame, c: Dictionary) -> Dictionary:
	match str(c.mode):
		"species":
			return Criterion.result(1 if Codex.caught(save, str(c.species)) else 0, 1)
		"caught":
			return Criterion.result(_count(db, save, true), _target(db, c))
	return Criterion.result(_count(db, save, false), _target(db, c))


func problem(c: Dictionary) -> String:
	if c.get("mode") == "species" and not c.has("species"):
		return "mode species needs a species"
	var all: bool = c.get("all", false)
	if c.get("mode") == "species" and all:
		return "all does not apply to mode species"
	if c.get("mode") in ["seen", "caught"]:
		if all and c.has("target"):
			return "give a target or all, not both"
		if not all and not c.has("target"):
			return "mode %s needs a target or all" % c.get("mode")
	return ""


## The number to reach: every listed species with `all`, else `target`.
static func _target(db: Database, c: Dictionary) -> int:
	return Codex.order(db).size() if c.get("all", false) else int(c.target)


static func _count(db: Database, save: SaveGame, caught: bool) -> int:
	var n := 0
	for id in Codex.order(db):
		if Codex.caught(save, id) if caught else Codex.seen(save, id):
			n += 1
	return n
