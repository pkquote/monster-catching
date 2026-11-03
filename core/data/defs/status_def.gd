class_name StatusDef
extends RefCounted

var id: String
var name: String
var description: String
var turns: int
var effects: Array


static func from_dict(d: Dictionary) -> StatusDef:
	var s := StatusDef.new()
	s.id = d.id
	s.name = d.name
	s.description = d.get("description", "")
	s.turns = int(d.turns)
	s.effects = d.effects.duplicate(true)
	return s
