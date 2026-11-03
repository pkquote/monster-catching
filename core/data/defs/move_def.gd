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
	return m


func is_damaging() -> bool:
	return category != "status"
