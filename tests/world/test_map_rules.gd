extends GdUnitTestSuite
## Map checker rules, on hand-built map descriptions (no scenes needed).

const TALK := "res://dialogue/x.dialogue"

var db: Database


func before() -> void:
	db = DataLoader.load_database("res://data").db


func _piece(key: String, type: String, props: Dictionary, tile := Vector2i(1, 1)) -> Dictionary:
	return {"key": key, "type": type, "props": props, "pos": GameMap.centre_of(tile)}


## Two maps joined by doors both ways, with one of every checked piece, all valid.
func _good() -> Dictionary:
	return {
		"a": {"spawns": ["start", "from_b"], "default_encounter": "route_01_grass", "pieces": [
			_piece("a/Door", "Door", {"target_map": "b", "target_spawn": "from_a"}),
			_piece("a/Npc", "Npc", {"dialogue": TALK, "title": "hi"}),
			_piece("a/Item", "ItemPickup", {"item": "salve"}),
			_piece("a/Hidden", "HiddenItem", {"item": "tonic"}),
			_piece("a/Tamer", "Tamer", {"tamer_id": "scout_ana", "dialogue": TALK, "title": "",
				"before_title": "hi", "after_title": "bye"}),
			_piece("a/Area", "EncounterArea", {"encounter": "route_01_grass"}),
			_piece("a/Heal", "HealSpot", {"respawn": "start"}),
			_piece("a/Shop", "ShopCounter", {"stock": PackedStringArray(["salve", "lure_cage"])}),
		]},
		"b": {"spawns": ["from_a"], "default_encounter": "", "pieces": [
			_piece("b/Door", "Door", {"target_map": "a", "target_spawn": "from_b"}),
		]},
	}


func _titles() -> Dictionary:
	return {TALK: ["hi", "bye"]}


func _errors(maps: Dictionary) -> PackedStringArray:
	return MapRules.check(maps, db, _titles()).errors


func test_good_maps_are_clean() -> void:
	var r := MapRules.check(_good(), db, _titles())
	assert_array(Array(r.errors)).is_empty()
	assert_array(Array(r.warnings)).is_empty()


func test_door_to_missing_map_or_spawn() -> void:
	var m := _good()
	m.a.pieces[0].props.target_map = "nowhere"
	assert_array(Array(_errors(m))).contains(["a/Door: door to missing map 'nowhere'"])
	m = _good()
	m.a.pieces[0].props.target_spawn = "gone"
	assert_array(Array(_errors(m))).contains(["a/Door: map 'b' has no spawn 'gone'"])


func test_unknown_ids() -> void:
	var m := _good()
	m.a.pieces[2].props.item = "mystery"
	m.a.pieces[4].props.tamer_id = "nobody"
	m.a.pieces[5].props.encounter = "nowhere_grass"
	m.a.pieces[7].props.stock = PackedStringArray(["salve", "fake"])
	m.a.default_encounter = "bad_table"
	var e := Array(_errors(m))
	assert_array(e).contains(["a/Item: unknown item 'mystery'"])
	assert_array(e).contains(["a/Tamer: unknown tamer 'nobody'"])
	assert_array(e).contains(["a/Area: unknown encounter 'nowhere_grass'"])
	assert_array(e).contains(["a/Shop: unknown item 'fake'"])
	assert_array(e).contains(["a: unknown encounter 'bad_table'"])


func test_dialogue_files_and_titles() -> void:
	var m := _good()
	m.a.pieces[1].props.title = "missing"
	m.a.pieces[4].props.dialogue = "res://dialogue/none.dialogue"
	var e := Array(_errors(m))
	assert_array(e).contains(["a/Npc: no title 'missing' in %s" % TALK])
	assert_array(e).contains(["a/Tamer: no dialogue file res://dialogue/none.dialogue"])


func test_heal_spot_needs_its_respawn() -> void:
	var m := _good()
	m.a.pieces[6].props.respawn = "nope"
	assert_array(Array(_errors(m))).contains(["a/Heal: respawn spawn 'nope' isn't on this map"])


func test_off_grid_and_duplicate_keys() -> void:
	var m := _good()
	m.a.pieces[2].pos = Vector2(40, 48)
	m.a.pieces.append(_piece("a/Npc", "Sign", {"text": "dup"}))
	var e := Array(_errors(m))
	assert_array(e).contains(["a/Item: not on the tile grid (40, 48)"])
	assert_array(e).contains(["a/Npc: duplicate save key"])


func test_new_game_map_needs_start() -> void:
	var m := _good()
	m[SaveGame.NEW_GAME_MAP] = {"spawns": ["other"], "default_encounter": "", "pieces": []}
	assert_array(Array(_errors(m))).contains(["%s: no 'start' spawn for new games" % SaveGame.NEW_GAME_MAP])


func test_one_way_door_warns() -> void:
	var m := _good()
	m.b.pieces.clear()
	var r := MapRules.check(m, db, _titles())
	assert_array(Array(r.errors)).is_empty()
	assert_array(Array(r.warnings)).contains(["a/Door: no door on 'b' leads back to 'a'"])
