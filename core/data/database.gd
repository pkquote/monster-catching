class_name Database
extends RefCounted
## Immutable-by-convention collection of typed content definitions.
## Built by DataLoader.build() from validated RawData. Core systems receive
## a Database explicitly; nothing in core/ reads a global registry.

## Ids of debug-only test-pack content start with this prefix.
const TEST_PREFIX: String = "tp_"

## category -> { id: Def }
var _tables: Dictionary = {}
var balance: BalanceDef


static func _builders() -> Dictionary:
	return {
		"creatures": CreatureDef,
		"moves": MoveDef,
		"items": ItemDef,
		"tamers": TamerDef,
		"encounters": EncounterDef,
		"locations": LocationDef,
		"types": TypeDef,
		"statuses": StatusDef,
		"field_states": FieldStateDef,
		"reactions": ReactionDef,
		"affinities": AffinityDef,
		"minigames": MinigameDef,
		"passives": PassiveDef,
	}


static func is_test_content(id: String) -> bool:
	return id.begins_with(TEST_PREFIX)


static func from_raw(raw: RawData) -> Database:
	var db := Database.new()
	var builders := _builders()
	for cat in builders:
		var table := {}
		for rec in raw.get_entries(cat):
			var def = builders[cat].from_dict(rec.entry)
			table[def.id] = def
		db._tables[cat] = table
	db.balance = BalanceDef.from_dict(raw.singles.balance.data)
	return db


func get_def(category: String, id: String) -> RefCounted:
	return _tables.get(category, {}).get(id)


func has(category: String, id: String) -> bool:
	return _tables.get(category, {}).has(id)


func ids(category: String) -> PackedStringArray:
	return PackedStringArray(_tables.get(category, {}).keys())


func count(category: String) -> int:
	return _tables.get(category, {}).size()


# Typed convenience accessors.
func creature(id: String) -> CreatureDef: return get_def("creatures", id)
func move(id: String) -> MoveDef: return get_def("moves", id)
func item(id: String) -> ItemDef: return get_def("items", id)
func tamer(id: String) -> TamerDef: return get_def("tamers", id)
func encounter(id: String) -> EncounterDef: return get_def("encounters", id)
func location(id: String) -> LocationDef: return get_def("locations", id)
func type_def(id: String) -> TypeDef: return get_def("types", id)
func status(id: String) -> StatusDef: return get_def("statuses", id)
func field_state(id: String) -> FieldStateDef: return get_def("field_states", id)
func reaction(id: String) -> ReactionDef: return get_def("reactions", id)
func affinity(id: String) -> AffinityDef: return get_def("affinities", id)
func minigame(id: String) -> MinigameDef: return get_def("minigames", id)
func passive(id: String) -> PassiveDef: return get_def("passives", id)


## Reaction triggered by `incoming` meeting `existing`, or null.
func find_reaction(existing: String, incoming: String) -> ReactionDef:
	for r: ReactionDef in _tables.get("reactions", {}).values():
		if r.matches(existing, incoming):
			return r
	return null


## Type effectiveness of an attack type against a defender's types.
func type_multiplier(attack_type: String, defender_types: PackedStringArray) -> float:
	var t := type_def(attack_type)
	if t == null:
		return 1.0
	var mult := 1.0
	for dt in defender_types:
		mult *= t.multiplier_against(dt)
	return mult
