class_name CreatureDef
extends RefCounted

var id: String
var name: String
var description: String
var types: PackedStringArray
## { hp, atk, def, spd } base values
var base_stats: Dictionary
var catch_rate: float
var xp_yield: int
## Array of { level: int, move: String }, sorted by level
var learnset: Array
## Array of { level: int, affinity: String (or ""), default: bool, into: String }
var growth: Array


static func from_dict(d: Dictionary) -> CreatureDef:
	var c := CreatureDef.new()
	c.id = d.id
	c.name = d.name
	c.description = d.get("description", "")
	c.types = PackedStringArray(d.types)
	c.base_stats = {}
	for k in d.base_stats:
		c.base_stats[k] = int(d.base_stats[k])
	c.catch_rate = float(d.catch_rate)
	c.xp_yield = int(d.xp_yield)
	c.learnset = []
	for l in d.learnset:
		c.learnset.append({"level": int(l.level), "move": l.move})
	c.learnset.sort_custom(func(a, b): return a.level < b.level)
	c.growth = []
	for g in d.get("growth", []):
		c.growth.append({
			"level": int(g.level),
			"affinity": g.get("affinity", ""),
			"default": g.get("default", false),
			"into": g.into,
		})
	return c


## Move ids learnable at or below `level`, in learn order.
func moves_up_to(level: int) -> PackedStringArray:
	var out := PackedStringArray()
	for l in learnset:
		if l.level <= level and not out.has(l.move):
			out.append(l.move)
	return out
