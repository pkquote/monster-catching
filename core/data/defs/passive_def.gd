class_name PassiveDef
extends RefCounted

var id: String
var name: String
var description: String
## "self" or "allies" (an aura applying its effects to every creature on the field's side).
var scope: String
## Always-on effects; each may carry a `when` condition.
var effects: Array
## Array of { on, chance, contact, when, effects }.
var triggers: Array
## Overworld effects (encounter_rate, xp_mult, bond_gain).
var field: Array


static func from_dict(d: Dictionary) -> PassiveDef:
	var p := PassiveDef.new()
	p.id = d.id
	p.name = d.name
	p.description = d.get("description", "")
	p.scope = d.get("scope", "self")
	p.effects = d.get("effects", []).duplicate(true)
	p.triggers = []
	for t in d.get("triggers", []):
		p.triggers.append({
			"on": t.on,
			"chance": int(t.get("chance", 100)),
			"contact": t.get("contact", false),
			"when": t.get("when", {}).duplicate(true),
			"effects": t.effects.duplicate(true),
		})
	p.field = d.get("field", []).duplicate(true)
	return p
