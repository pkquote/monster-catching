class_name Locations
extends RefCounted
## Where a species can be found in the wild, read from data/locations.json (`LocationDef`), plus the
## builder that file is generated with (tools/build_locations.gd) and a species' evolves-from source.


## One row per map and encounter table that can spawn `species`, maps in id order and a map's tables
## in file order: { map, area (the table's name), min, max } with the levels merged over the table's rows.
static func for_species(db: Database, species: String) -> Array:
	var out: Array = []
	var map_ids := Array(db.ids("locations"))
	map_ids.sort()
	for map_id: String in map_ids:
		var loc: LocationDef = db.location(map_id)
		for enc_id in loc.areas:
			var enc := db.encounter(enc_id)
			if enc == null:
				continue
			var lo := 0
			var hi := 0
			var found := false
			for row in enc.table:
				if row.species != species:
					continue
				lo = row.min_level if not found else mini(lo, row.min_level)
				hi = row.max_level if not found else maxi(hi, row.max_level)
				found = true
			if found:
				out.append({"map": loc.name, "area": enc.name, "min": lo, "max": hi})
	return out


## The species `species` grows from (first in Codex order when several do), or "".
static func evolves_from(db: Database, species: String) -> String:
	for id in Codex.order(db):
		for g in db.creature(id).growth:
			if g.into == species:
				return id
	return ""


## "Route 1 – Route 1 tall grass, Lv 2–5" ("Lv 4" when the range is one level).
static func line(row: Dictionary) -> String:
	var lv := "Lv %d" % row.min if row.min == row.max else "Lv %d–%d" % [row.min, row.max]
	return "%s – %s, %s" % [row.map, row.area, lv]


## The database's locations as `build` lists them (id order): [{ id, name, areas }].
static func file_entries(db: Database) -> Array:
	var ids := Array(db.ids("locations"))
	ids.sort()
	var out: Array = []
	for id: String in ids:
		var loc := db.location(id)
		out.append({"id": loc.id, "name": loc.name, "areas": Array(loc.areas)})
	return out


## The locations file for `maps` ({ map_id: { name, default_encounter, pieces: [{ type, props }] } }, as
## tools/check_maps.gd describes the scenes): maps by id, test maps (`test_`) and maps without
## encounters left out, each map's tables as its default first then every EncounterArea's, once each.
static func build(maps: Dictionary) -> Dictionary:
	var ids := Array(maps.keys())
	ids.sort()
	var entries: Array = []
	for map_id: String in ids:
		if map_id.begins_with("test_"):
			continue
		var m: Dictionary = maps[map_id]
		var areas: Array = []
		var candidates: Array = [m.get("default_encounter", "")]
		for p in m.get("pieces", []):
			if p.type == "EncounterArea":
				candidates.append(p.props.get("encounter", ""))
		for enc in candidates:
			if enc != "" and not areas.has(enc):
				areas.append(enc)
		if not areas.is_empty():
			var map_name: String = m.get("name", "")
			entries.append({"id": map_id, "name": map_name if map_name != "" else map_id, "areas": areas})
	return {"schema": 1, "entries": entries}
