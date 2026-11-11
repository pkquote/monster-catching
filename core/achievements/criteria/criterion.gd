class_name Criterion
extends RefCounted
## One kind of achievement criterion (the `criterion` object of an achievement). A kind says which
## watch keys can change its answer, how far along the player is, and whether its fields agree.
## Register a new kind in `Criteria.KINDS` and `DataSchemas.CRITERIA`.


func kind() -> String:
	return ""


## The watch keys (see AchievementWatch) whose change can move this criterion.
func watches(_c: Dictionary) -> PackedStringArray:
	return PackedStringArray()


## `{"current": int, "target": int}`; `current` is clamped to 0..target, met when it equals target.
func progress(_db: Database, _save: SaveGame, _c: Dictionary) -> Dictionary:
	return {"current": 0, "target": 1}


## A problem with how the fields fit together (the schema covers each field alone); "" when fine.
func problem(_c: Dictionary) -> String:
	return ""


## `value` against `target` as a progress dictionary.
static func result(value: int, target: int) -> Dictionary:
	return {"current": clampi(value, 0, target), "target": target}
