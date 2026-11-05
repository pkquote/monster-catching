extends GdUnitTestSuite
## Held item parsing: ItemDef.held / held_use, trigger `when`, tamer held_item.

var db: Database


func before() -> void:
	var raw := FixtureDB.raw()
	raw.add_entry("items", {"id": "berry", "name": "Berry", "description": "Eaten when hurt.",
		"category": "held", "price": 10, "held": {"use": "consumed", "triggers": [
			{"on": "hit", "when": {"hp_below": 0.5},
				"effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}]}})
	raw.add_entry("items", {"id": "charm", "name": "Charm", "category": "held", "price": 10,
		"held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.1}]}})
	raw.add_entry("passives", {"id": "pricker", "name": "Pricker", "triggers": [
		{"on": "hit", "effects": [{"op": "heal", "fraction": 0.25, "target": "self"}]}]})
	raw.add_entry("tamers", {"id": "t2", "name": "T2", "max_active": 1, "ai": "basic", "reward_money": 1,
		"party": [{"species": raw.get_entries("creatures")[0].entry.id, "level": 5, "held_item": "berry"},
			{"species": raw.get_entries("creatures")[0].entry.id, "level": 5}]})
	db = Database.from_raw(raw)


func test_item_def_parses_held_block() -> void:
	var item := db.item("berry")
	assert_object(item.held).is_not_null()
	assert_str(item.held.id).is_equal("berry")
	assert_str(item.held.name).is_equal("Berry")
	assert_str(item.held.description).is_equal("Eaten when hurt.")
	assert_str(item.held_use).is_equal("consumed")
	assert_str(item.held.triggers[0].on).is_equal("hit")
	assert_float(item.held.triggers[0].when.hp_below).is_equal(0.5)
	assert_int(item.held.triggers[0].chance).is_equal(100)
	assert_bool(item.held.triggers[0].contact).is_false()
	assert_object(db.item("tonic").held).is_null()


func test_held_use_defaults_to_permanent() -> void:
	assert_str(db.item("charm").held_use).is_equal("permanent")
	assert_str(db.item("charm").held.scope).is_equal("self")


func test_trigger_when_defaults_to_empty() -> void:
	assert_dict(db.passive("pricker").triggers[0].when).is_empty()


func test_tamer_def_reads_held_item() -> void:
	var t := db.tamer("t2")
	assert_str(t.party[0].held_item).is_equal("berry")
	assert_str(t.party[1].held_item).is_equal("")


func test_shipped_held_items_cover_every_usage_kind() -> void:
	var loaded := DataLoader.load_database("res://data", "res://dialogue")
	assert_array(loaded.errors).is_empty()
	assert_array(loaded.warnings).is_empty()
	var shipped: Database = loaded.db
	var uses := {}
	var aura := false
	var field := false
	for id in shipped.ids("items"):
		var item := shipped.item(id)
		if item.category != "held":
			continue
		uses[item.held_use] = true
		aura = aura or item.held.scope == "allies"
		field = field or not item.held.field.is_empty()
	assert_bool(uses.has("permanent")).is_true()
	assert_bool(uses.has("consumed")).is_true()
	assert_bool(uses.has("per_battle")).is_true()
	assert_bool(aura).is_true()
	assert_bool(field).is_true()
