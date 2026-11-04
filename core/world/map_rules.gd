class_name MapRules
extends RefCounted
## The map checker's rules, on plain descriptions of maps (tools/check_maps.gd
## builds them by opening every map scene). Kept free of nodes so it's tested headless.
##
## maps: { map_id: { "spawns": [id], "default_encounter": String,
##                   "pieces": [{ "key", "type" (class name), "props": {}, "pos": Vector2 }] } }
## dialogue_titles: { dialogue path: [titles] } for every .dialogue file that exists.

const TILE := 32
const NEW_GAME_SPAWN := "start"


static func check(maps: Dictionary, db: Database, dialogue_titles: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var keys := {}
	for map_id in maps:
		var m: Dictionary = maps[map_id]
		var enc: String = m.get("default_encounter", "")
		if enc != "" and not db.has("encounters", enc):
			errors.append("%s: unknown encounter '%s'" % [map_id, enc])
		if map_id == SaveGame.NEW_GAME_MAP and not NEW_GAME_SPAWN in m.get("spawns", []):
			errors.append("%s: no 'start' spawn for new games" % map_id)
		for p in m.get("pieces", []):
			var key: String = p.key
			if keys.has(key):
				errors.append("%s: duplicate save key" % key)
			keys[key] = true
			var pos: Vector2 = p.pos
			if fposmod(pos.x, TILE) != TILE / 2.0 or fposmod(pos.y, TILE) != TILE / 2.0:
				errors.append("%s: not on the tile grid (%d, %d)" % [key, pos.x, pos.y])
			_check_piece(map_id, p, maps, db, dialogue_titles, errors, warnings)
	return {"errors": errors, "warnings": warnings}


static func _check_piece(map_id: String, p: Dictionary, maps: Dictionary, db: Database,
		titles: Dictionary, errors: PackedStringArray, warnings: PackedStringArray) -> void:
	var key: String = p.key
	var props: Dictionary = p.props
	match p.type:
		"Door":
			var target: String = props.get("target_map", "")
			if not maps.has(target):
				errors.append("%s: door to missing map '%s'" % [key, target])
			else:
				var spawn: String = props.get("target_spawn", "")
				if not spawn in maps[target].get("spawns", []):
					errors.append("%s: map '%s' has no spawn '%s'" % [key, target, spawn])
				if not _has_door_to(maps[target], map_id):
					warnings.append("%s: no door on '%s' leads back to '%s'" % [key, target, map_id])
		"ItemPickup", "HiddenItem":
			_ref(db, "items", "item", props.get("item", ""), key, errors)
		"ShopCounter":
			for it in props.get("stock", []):
				_ref(db, "items", "item", it, key, errors)
		"Tamer":
			_ref(db, "tamers", "tamer", props.get("tamer_id", ""), key, errors)
			for t in ["before_title", "after_title"]:
				_dialogue(props.get("dialogue", ""), props.get(t, ""), key, titles, errors)
		"Npc", "Trigger", "MinigameSpot":
			if props.get("dialogue", "") != "":
				_dialogue(props.dialogue, props.get("title", ""), key, titles, errors)
			if p.type == "MinigameSpot" and DataSchemas.CATEGORIES.has("minigames"):
				_ref(db, "minigames", "minigame", props.get("minigame", ""), key, errors)
		"EncounterArea":
			_ref(db, "encounters", "encounter", props.get("encounter", ""), key, errors)
		"HealSpot":
			if not props.get("respawn", "") in maps[map_id].get("spawns", []):
				errors.append("%s: respawn spawn '%s' isn't on this map" % [key, props.get("respawn", "")])
	if props.has("species"):
		_ref(db, "creatures", "species", props.species, key, errors)


static func _ref(db: Database, cat: String, what: String, id: String, key: String, errors: PackedStringArray) -> void:
	if not db.has(cat, id):
		errors.append("%s: unknown %s '%s'" % [key, what, id])


static func _dialogue(path: String, title: String, key: String, titles: Dictionary, errors: PackedStringArray) -> void:
	if not titles.has(path):
		errors.append("%s: no dialogue file %s" % [key, path])
	elif not title in titles[path]:
		errors.append("%s: no title '%s' in %s" % [key, title, path])


static func _has_door_to(m: Dictionary, map_id: String) -> bool:
	return m.get("pieces", []).any(func(p): return p.type == "Door" and p.props.get("target_map", "") == map_id)
