class_name TypeDef
extends RefCounted

var id: String
var name: String
## What the type is meant to exemplify.
var description: String
## Short player-facing strengths and weaknesses (shown in the compendium).
var pros: PackedStringArray
var cons: PackedStringArray
## defending type id -> damage multiplier (missing = 1.0)
var matchups: Dictionary = {}


static func from_dict(d: Dictionary) -> TypeDef:
	var t := TypeDef.new()
	t.id = d.id
	t.name = d.name
	t.description = d.description
	t.pros = PackedStringArray(d.pros)
	t.cons = PackedStringArray(d.cons)
	t.matchups = d.get("matchups", {}).duplicate()
	return t


func multiplier_against(defending_type: String) -> float:
	return float(matchups.get(defending_type, 1.0))
