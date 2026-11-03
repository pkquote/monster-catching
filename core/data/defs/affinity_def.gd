class_name AffinityDef
extends RefCounted

var id: String
var name: String
var description: String


static func from_dict(d: Dictionary) -> AffinityDef:
	var a := AffinityDef.new()
	a.id = d.id
	a.name = d.name
	a.description = d.get("description", "")
	return a
