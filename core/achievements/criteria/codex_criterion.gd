class_name CodexCriterion
extends Criterion
## `{"kind": "codex", "mode": "seen"|"caught", "target": n}` or `{"mode": "species", "species": id}`:
## enough species seen or caught, or one named species caught. Only species in the Codex list count.


func kind() -> String:
	return "codex"


func watches(_c: Dictionary) -> PackedStringArray:
	return PackedStringArray([AchievementWatch.CODEX])


func progress(db: Database, save: SaveGame, c: Dictionary) -> Dictionary:
	match str(c.mode):
		"species":
			return Criterion.result(1 if Codex.caught(save, str(c.species)) else 0, 1)
		"caught":
			return Criterion.result(_count(db, save, true), int(c.target))
	return Criterion.result(_count(db, save, false), int(c.target))


func problem(c: Dictionary) -> String:
	if c.get("mode") == "species" and not c.has("species"):
		return "mode species needs a species"
	if c.get("mode") in ["seen", "caught"] and not c.has("target"):
		return "mode %s needs a target" % c.get("mode")
	return ""


static func _count(db: Database, save: SaveGame, caught: bool) -> int:
	var n := 0
	for id in Codex.order(db):
		if Codex.caught(save, id) if caught else Codex.seen(save, id):
			n += 1
	return n
