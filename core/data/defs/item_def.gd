class_name ItemDef
extends RefCounted

var id: String
var name: String
var description: String
var category: String  # capture | heal | battle | key
var price: int
var target: String
var effects: Array


static func from_dict(d: Dictionary) -> ItemDef:
	var i := ItemDef.new()
	i.id = d.id
	i.name = d.name
	i.description = d.get("description", "")
	i.category = d.category
	i.price = int(d.price)
	i.target = d.get("target", "self")
	i.effects = d.get("effects", []).duplicate(true)
	return i
