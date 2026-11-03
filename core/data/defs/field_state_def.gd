class_name FieldStateDef
extends RefCounted

var id: String
var name: String
var description: String
var max_stacks: int
var default_turns: int
## Effects active on every creature on the side holding this state.
var passive: Array


static func from_dict(d: Dictionary) -> FieldStateDef:
	var f := FieldStateDef.new()
	f.id = d.id
	f.name = d.name
	f.description = d.get("description", "")
	f.max_stacks = int(d.max_stacks)
	f.default_turns = int(d.default_turns)
	f.passive = d.get("passive", []).duplicate(true)
	return f
