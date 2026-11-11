class_name CounterCriterion
extends Criterion
## `{"kind": "counter", "stat": id, "target": n}`: a lifetime counter (`Counters.BUILT_IN`) reaches the target.


func kind() -> String:
	return "counter"


func watches(c: Dictionary) -> PackedStringArray:
	return PackedStringArray([AchievementWatch.counter_key(str(c.get("stat", "")))])


func progress(_db: Database, save: SaveGame, c: Dictionary) -> Dictionary:
	return Criterion.result(Counters.value(save, str(c.stat)), int(c.target))
