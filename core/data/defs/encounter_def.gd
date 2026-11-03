class_name EncounterDef
extends RefCounted

var id: String
var name: String
var pack_min: int
var pack_max: int
## Array of { species, weight, min_level, max_level }
var table: Array
var total_weight: int


static func from_dict(d: Dictionary) -> EncounterDef:
	var e := EncounterDef.new()
	e.id = d.id
	e.name = d.name
	e.pack_min = int(d.pack_min)
	e.pack_max = int(d.pack_max)
	e.table = []
	e.total_weight = 0
	for row in d.table:
		var r := {
			"species": row.species,
			"weight": int(row.weight),
			"min_level": int(row.min_level),
			"max_level": int(row.max_level),
		}
		e.total_weight += r.weight
		e.table.append(r)
	return e


## Picks one table row using `rng`.
func roll(rng: RandomNumberGenerator) -> Dictionary:
	var pick := rng.randi_range(1, total_weight)
	for row in table:
		pick -= row.weight
		if pick <= 0:
			return row
	return table.back()
