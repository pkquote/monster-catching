class_name FlagCriterion
extends Criterion
## `{"kind": "flag", "flag": id}`: a story flag is set.


func kind() -> String:
	return "flag"


func watches(c: Dictionary) -> PackedStringArray:
	return PackedStringArray([AchievementWatch.flag_key(str(c.get("flag", "")))])


func progress(_db: Database, save: SaveGame, c: Dictionary) -> Dictionary:
	return Criterion.result(1 if save.story.flag(str(c.flag)) else 0, 1)
