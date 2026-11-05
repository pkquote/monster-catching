class_name ItemDef
extends RefCounted

var id: String
var name: String
var description: String
var category: String  # capture | heal | battle | key | training | held
var price: int
var target: String
var effects: Array
## Category "held" only: the item's behaviour as a passive (item's own id/name/description), else null.
var held: PassiveDef
## "permanent" | "consumed" | "per_battle" (held items).
var held_use: String = "permanent"


static func from_dict(d: Dictionary) -> ItemDef:
	var i := ItemDef.new()
	i.id = d.id
	i.name = d.name
	i.description = d.get("description", "")
	i.category = d.category
	i.price = int(d.price)
	i.target = d.get("target", "self")
	i.effects = d.get("effects", []).duplicate(true)
	if i.category == "held":
		var h: Dictionary = d.get("held", {}).duplicate(true)
		h["id"] = i.id
		h["name"] = i.name
		h["description"] = i.description
		i.held = PassiveDef.from_dict(h)
		i.held_use = h.get("use", "permanent")
	return i
