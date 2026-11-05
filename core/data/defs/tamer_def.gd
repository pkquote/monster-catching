class_name TamerDef
extends RefCounted

var id: String
var name: String
var max_active: int
var ai: String
var reward_money: int
## Array of { species: String, level: int, moves: PackedStringArray (may be empty), passive: String ("" = roll), held_item: String ("" = none) }
var party: Array
## Array of { item: String, count: int }
var items: Array


static func from_dict(d: Dictionary) -> TamerDef:
	var t := TamerDef.new()
	t.id = d.id
	t.name = d.name
	t.max_active = int(d.max_active)
	t.ai = d.ai
	t.reward_money = int(d.reward_money)
	t.party = []
	for p in d.party:
		t.party.append({
			"species": p.species,
			"level": int(p.level),
			"moves": PackedStringArray(p.get("moves", [])),
			"passive": p.get("passive", ""),
			"held_item": p.get("held_item", ""),
		})
	t.items = []
	for it in d.get("items", []):
		t.items.append({"item": it.item, "count": int(it.count)})
	return t
