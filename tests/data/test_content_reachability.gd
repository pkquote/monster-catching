extends GdUnitTestSuite
## M9 guards: authored content must be reachable. Each failure names the ids. See tools/content_audit.gd.

var db: Database
var text: String


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "res://dialogue")
	assert_bool(result.ok()).override_failure_message("Shipped data invalid:\n" + "\n".join(result.errors)).is_true()
	db = result.db
	text = ContentAudit.shipped_text()


func _none(list: Array, problem: String) -> void:
	assert_array(list).override_failure_message("%s: %s" % [problem, ", ".join(list)]).is_empty()


func test_every_species_can_be_obtained() -> void:
	_none(ContentAudit.unobtainable_species(db, text),
		"Species nobody can obtain (give it in dialogue, add it to an encounter table a location uses, or make it an evolution of one that is)")


func test_every_passive_is_on_a_species() -> void:
	_none(ContentAudit.orphan_passives(db),
		"Passives no species has (add to a species' passives or affinity_passives)")


func test_every_item_is_given_sold_or_placed() -> void:
	_none(ContentAudit.orphan_items(db, text),
		"Items never given, sold or placed (give_item in dialogue, a shop stock, or a pickup in a map scene)")


func test_every_encounter_table_is_used() -> void:
	_none(ContentAudit.unused_encounters(db),
		"Encounter tables no location uses (link from a map, then regenerate data/locations.json)")


func test_every_move_of_a_populated_type_is_learned() -> void:
	_none(ContentAudit.orphan_moves(db),
		"Moves a species could learn (it has the type) but none does (add to a learnset)")
