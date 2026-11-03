class_name ReactionDef
extends RefCounted

var id: String
var name: String
var description: String
var inputs: PackedStringArray
var consumes: PackedStringArray
## "side": affects the side where it triggered. "both_sides": affects everyone.
var scope: String
var effects: Array


static func from_dict(d: Dictionary) -> ReactionDef:
	var r := ReactionDef.new()
	r.id = d.id
	r.name = d.name
	r.description = d.get("description", "")
	r.inputs = PackedStringArray(d.inputs)
	r.consumes = PackedStringArray(d.consumes)
	r.scope = d.scope
	r.effects = d.effects.duplicate(true)
	return r


func matches(a: String, b: String) -> bool:
	return (inputs[0] == a and inputs[1] == b) or (inputs[0] == b and inputs[1] == a)
