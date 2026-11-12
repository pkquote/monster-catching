class_name MoveDef
extends RefCounted

var id: String
var name: String
var description: String
var type: String
var category: String  # physical | special | status
var power: int
## Energy spent to use the move.
var cost: int
var accuracy: int
var always_hits: bool
var priority: int
var target: String
var effects: Array
## How many times one use hits its target: a count rolled from hits_min to hits_max (both 1 = once).
var hits_min: int = 1
var hits_max: int = 1


static func from_dict(d: Dictionary) -> MoveDef:
	var m := MoveDef.new()
	m.id = d.id
	m.name = d.name
	m.description = d.get("description", "")
	m.type = d.type
	m.category = d.category
	m.power = int(d.power)
	m.cost = int(d.cost)
	m.accuracy = int(d.accuracy)
	m.always_hits = d.get("always_hits", false)
	m.priority = int(d.get("priority", 0))
	m.target = d.target
	m.effects = d.effects.duplicate(true)
	var hits: Dictionary = d.get("hits", {})
	m.hits_min = int(hits.get("min", 1))
	m.hits_max = int(hits.get("max", 1))
	return m


func is_damaging() -> bool:
	return category != "status"


func is_multi_hit() -> bool:
	return hits_max > 1


## Expected number of hits (the AI scores a ranged move by it).
func mean_hits() -> float:
	return (hits_min + hits_max) / 2.0
