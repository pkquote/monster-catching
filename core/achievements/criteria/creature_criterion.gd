class_name CreatureCriterion
extends Criterion
## `{"kind": "creature", "what": "level"|"bond"|"evolved", "target": n}`: the highest level or Bond among
## the creatures you own (party and boxes), or how many have evolved (the `creatures_evolved` counter).


func kind() -> String:
	return "creature"


func watches(c: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray([AchievementWatch.CREATURE])
	if c.get("what") == "evolved":
		keys.append(AchievementWatch.counter_key("creatures_evolved"))
	return keys


func progress(_db: Database, save: SaveGame, c: Dictionary) -> Dictionary:
	var target := int(c.target)
	if c.what == "evolved":
		return Criterion.result(Counters.value(save, "creatures_evolved"), target)
	var best := 0
	for cr: CreatureInstance in save.party + BoxStorage.all_creatures(save):
		best = maxi(best, cr.level if c.what == "level" else cr.bond)
	return Criterion.result(best, target)
