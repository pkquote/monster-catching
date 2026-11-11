class_name AchievementDef
extends RefCounted
## An achievement from data/achievements/*.json: a name, a description and one criterion.

var id: String
var name: String
var description: String
## A locked hidden achievement shows only "???".
var hidden: bool
## `{"kind": ..., ...}`; the kinds are in `Criteria`.
var criterion: Dictionary


static func from_dict(d: Dictionary) -> AchievementDef:
	var a := AchievementDef.new()
	a.id = d.id
	a.name = d.name
	a.description = d.description
	a.hidden = bool(d.get("hidden", false))
	a.criterion = d.criterion.duplicate(true)
	return a
