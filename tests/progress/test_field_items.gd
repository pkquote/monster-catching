extends GdUnitTestSuite
## Using healing items outside battle (pause menu Bag).

var db: Database
var save: SaveGame
var c: CreatureInstance


func before() -> void:
	db = DataLoader.load_database("res://data").db


func before_test() -> void:
	save = SaveGame.new_game("Ana", 1000, RandomNumberGenerator.new())
	save.inventory = {"salve": 2, "tonic": 1, "lure_cage": 1}
	c = CreatureInstance.create(db, "tidepup", 10)


func test_salve_heals_a_third() -> void:
	c.hp = 1
	var r := FieldItems.use(db, save, "salve", c)
	assert_bool(r.ok).is_true()
	assert_int(r.healed).is_equal(roundi(c.max_hp(db) * 0.33))
	assert_int(c.hp).is_equal(1 + r.healed)
	assert_int(save.inventory.salve).is_equal(1)


func test_fainted_creature() -> void:
	c.hp = 0
	var r := FieldItems.use(db, save, "salve", c)
	assert_str(r.error).is_equal("fainted")
	assert_int(save.inventory.salve).is_equal(2)


func test_tonic_restores_energy() -> void:
	c.energy = 0
	var r := FieldItems.use(db, save, "tonic", c)
	assert_bool(r.ok).is_true()
	assert_int(c.energy).is_equal(roundi(c.max_energy(db) * 0.5))
	assert_bool(save.inventory.has("tonic")).is_false()


func test_full_creature_is_no_effect() -> void:
	assert_str(FieldItems.use(db, save, "salve", c).error).is_equal("no_effect")
	assert_int(save.inventory.salve).is_equal(2)


func test_reset_seed_refunds_and_is_spent() -> void:
	save.inventory.reset_seed = 1
	c.training = {"patk": 3, "hp": 2}
	var r := FieldItems.use(db, save, "reset_seed", c)
	assert_bool(r.ok).is_true()
	assert_int(r.refunded).is_equal(5)
	assert_bool(c.training.is_empty()).is_true()
	assert_bool(save.inventory.has("reset_seed")).is_false()


func test_reset_seed_refused_without_spent_points() -> void:
	save.inventory.reset_seed = 1
	var r := FieldItems.use(db, save, "reset_seed", c)
	assert_bool(r.ok).is_false()
	assert_str(r.error).is_equal("nothing_to_refund")
	assert_int(r.refunded).is_equal(0)
	assert_int(save.inventory.reset_seed).is_equal(1)


func test_reset_seed_works_on_fainted_creature() -> void:
	save.inventory.reset_seed = 1
	c.training = {"patk": 2}
	c.hp = 0
	var r := FieldItems.use(db, save, "reset_seed", c)
	assert_bool(r.ok).is_true()
	assert_int(r.refunded).is_equal(2)
	assert_int(c.hp).is_equal(0)


func test_healing_results_report_zero_refunded() -> void:
	c.hp = 1
	assert_int(FieldItems.use(db, save, "salve", c).refunded).is_equal(0)


func test_capture_item_is_not_usable() -> void:
	assert_bool(FieldItems.can_use(db, "lure_cage")).is_false()
	assert_bool(FieldItems.can_use(db, "salve")).is_true()
	assert_str(FieldItems.use(db, save, "lure_cage", c).error).is_equal("not_usable")


func _party_of(creatures: Array) -> void:
	save.party = creatures


func test_usability_unknown_item() -> void:
	var u := FieldItems.usability(db, save, "no_such_item")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("Unknown item.")


func test_usability_held_item() -> void:
	var u := FieldItems.usability(db, save, "tide_charm")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("Give it from the Summary.")


func test_usability_capture_item() -> void:
	var u := FieldItems.usability(db, save, "lure_cage")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("Used in battle.")


## A fixture database (public route: raw + validate + from_raw) with extra items for categories
## the shipped data has none of, plus a combined heal + restore_energy item.
func _fixture_db() -> Database:
	var r := FixtureDB.raw()
	r.add_entry("items", {"id": "test_battle_item", "name": "Battle Thing", "category": "battle",
		"price": 1, "target": "one_ally"})
	r.add_entry("items", {"id": "test_key_item", "name": "Key Thing", "category": "key", "price": 0})
	r.add_entry("items", {"id": "elixir", "name": "Elixir", "category": "heal", "price": 1,
		"target": "one_ally",
		"effects": [{"op": "heal", "fraction": 0.5}, {"op": "restore_energy", "fraction": 0.5}]})
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	return Database.from_raw(r)


func test_usability_battle_item() -> void:
	var u := FieldItems.usability(_fixture_db(), save, "test_battle_item")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("Used in battle.")


func test_usability_key_item() -> void:
	var u := FieldItems.usability(_fixture_db(), save, "test_key_item")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("Can't be used.")


func test_usability_heal_with_hurt_creature() -> void:
	c.hp = 1
	_party_of([c])
	var u := FieldItems.usability(db, save, "salve")
	assert_bool(u.ok).is_true()
	assert_str(u.reason).is_equal("Usable now.")


func test_usability_heal_when_full_or_fainted() -> void:
	var fainted: CreatureInstance = CreatureInstance.create(db, "tidepup", 10)
	fainted.hp = 0
	_party_of([c, fainted])
	var u := FieldItems.usability(db, save, "salve")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("No one needs it right now.")


func test_usability_heal_ignores_fainted_that_would_gain() -> void:
	c.hp = 0
	c.energy = 0
	_party_of([c])
	assert_bool(FieldItems.usability(db, save, "salve").ok).is_false()
	assert_bool(FieldItems.usability(db, save, "tonic").ok).is_false()
	# Control: a living creature at full HP but with no energy does gain from the tonic.
	var living: CreatureInstance = CreatureInstance.create(db, "tidepup", 10)
	living.energy = 0
	_party_of([c, living])
	assert_bool(FieldItems.usability(db, save, "tonic").ok).is_true()
	assert_bool(FieldItems.usability(db, save, "salve").ok).is_false()


func test_usability_energy_item() -> void:
	c.energy = 0
	_party_of([c])
	var u := FieldItems.usability(db, save, "tonic")
	assert_bool(u.ok).is_true()
	assert_str(u.reason).is_equal("Usable now.")
	c.energy = c.max_energy(db)
	u = FieldItems.usability(db, save, "tonic")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("No one needs it right now.")


func test_usability_reset_seed() -> void:
	save.inventory.reset_seed = 1
	_party_of([c])
	var u := FieldItems.usability(db, save, "reset_seed")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("No one has training points to return.")
	c.training = {"patk": 1}
	u = FieldItems.usability(db, save, "reset_seed")
	assert_bool(u.ok).is_true()
	assert_str(u.reason).is_equal("Usable now.")


func test_usability_needs_the_item_in_the_bag() -> void:
	c.hp = 1
	c.training = {"patk": 1}
	_party_of([c])
	save.inventory["salve"] = 0
	var u := FieldItems.usability(db, save, "salve")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("You don't have any.")
	# No entry at all is the same as a count of 0.
	assert_bool(save.inventory.has("reset_seed")).is_false()
	u = FieldItems.usability(db, save, "reset_seed")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("You don't have any.")
	# Reasons for items the bag never uses do not depend on the count.
	assert_str(FieldItems.usability(db, save, "lure_cage").reason).is_equal("Used in battle.")
	assert_str(FieldItems.usability(db, save, "tide_charm").reason).is_equal("Give it from the Summary.")
	assert_str(FieldItems.usability(db, save, "no_such_item").reason).is_equal("Unknown item.")
	save.inventory["salve"] = 1
	assert_bool(FieldItems.usability(db, save, "salve").ok).is_true()


func test_usability_heal_item_rejected_by_can_use() -> void:
	var local_db: Database = DataLoader.load_database("res://data").db
	local_db.item("salve").effects = []
	var u := FieldItems.usability(local_db, save, "salve")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("Can't be used here.")


func test_usability_ok_agrees_with_use_on_some_creature() -> void:
	_assert_usability_matches_use(db, "tidepup",
			["salve", "tonic", "reset_seed", "lure_cage", "tide_charm", "no_such_item"])


func test_usability_agrees_with_use_for_combined_heal_and_energy_item() -> void:
	var fx: Database = _fixture_db()
	_assert_usability_matches_use(fx, "blob",
			["elixir", "potion", "tonic", "seed", "test_battle_item", "test_key_item"])


func _assert_usability_matches_use(d: Database, species: String, ids: Array) -> void:
	var hurt: CreatureInstance = CreatureInstance.create(d, species, 10)
	hurt.hp = 2
	var tired: CreatureInstance = CreatureInstance.create(d, species, 10)
	tired.energy = 0
	var trained: CreatureInstance = CreatureInstance.create(d, species, 10)
	trained.training = {"hp": 1}
	var fainted: CreatureInstance = CreatureInstance.create(d, species, 10)
	fainted.hp = 0
	var full: CreatureInstance = CreatureInstance.create(d, species, 10)
	var parties: Array = [[], [full], [fainted], [full, fainted], [hurt], [tired], [trained],
			[full, hurt, tired, trained, fainted]]
	for id: String in ids:
		save.inventory[id] = 1
	for party: Array in parties:
		save.party = party
		for id: String in ids:
			var u := FieldItems.usability(d, save, id)
			var any_ok := false
			for member: CreatureInstance in party:
				var trial := SaveGame.new_game("Ana", 1000, RandomNumberGenerator.new())
				trial.inventory = {id: 1}
				if FieldItems.use(d, trial, id, member.copy()).ok:
					any_ok = true
					break
			assert_bool(u.ok).override_failure_message(
					"%s on party of %d: usability.ok=%s but use-success=%s" % [id, party.size(), u.ok, any_ok]
			).is_equal(any_ok)


# --- Cure items (fixture data) ---

func _cure_db() -> Database:
	var r := FixtureDB.raw()
	r.add_entry("items", {"id": "remedy", "name": "Remedy", "category": "heal", "price": 1,
		"target": "one_ally", "effects": [{"op": "cure_status"}]})
	r.add_entry("items", {"id": "burn_ward", "name": "Burn Ward", "category": "heal", "price": 1,
		"target": "one_ally", "effects": [{"op": "cure_status", "status": "burn"}]})
	r.add_entry("items", {"id": "full_remedy", "name": "Full Remedy", "category": "heal", "price": 1,
		"target": "one_ally", "effects": [{"op": "heal", "fraction": 1.0}, {"op": "cure_status"}]})
	return Database.from_raw(r)


func _cure_setup(cdb: Database) -> CreatureInstance:
	save.inventory = {"remedy": 2, "burn_ward": 1, "full_remedy": 1}
	save.party.clear()
	var m := CreatureInstance.create(cdb, "blob", 10)
	save.party.append(m)
	return m


func test_cure_item_clears_status_and_is_spent() -> void:
	var cdb := _cure_db()
	var m := _cure_setup(cdb)
	m.status = "burn"
	var r := FieldItems.use(cdb, save, "remedy", m)
	assert_bool(r.ok).is_true()
	assert_bool(r.cured).is_true()
	assert_str(m.status).is_equal("")
	assert_int(save.inventory.remedy).is_equal(1)


func test_cure_item_with_no_status_is_no_effect() -> void:
	var cdb := _cure_db()
	var m := _cure_setup(cdb)
	assert_str(FieldItems.use(cdb, save, "remedy", m).error).is_equal("no_effect")
	assert_int(save.inventory.remedy).is_equal(2)


func test_filtered_cure_on_the_wrong_status_is_no_effect() -> void:
	var cdb := _cure_db()
	var m := _cure_setup(cdb)
	m.status = "shock"
	assert_str(FieldItems.use(cdb, save, "burn_ward", m).error).is_equal("no_effect")
	assert_str(m.status).is_equal("shock")
	assert_int(save.inventory.burn_ward).is_equal(1)


func test_combined_item_cures_and_heals() -> void:
	var cdb := _cure_db()
	var m := _cure_setup(cdb)
	m.status = "burn"
	m.hp = 1
	var r := FieldItems.use(cdb, save, "full_remedy", m)
	assert_bool(r.ok).is_true()
	assert_bool(r.cured).is_true()
	assert_int(r.healed).is_greater(0)
	assert_int(m.hp).is_equal(m.max_hp(cdb))
	# Burned at full HP: still worth using.
	save.inventory.full_remedy = 1
	m.status = "burn"
	r = FieldItems.use(cdb, save, "full_remedy", m)
	assert_bool(r.ok).is_true()
	assert_int(r.healed).is_equal(0)
	# Healthy at full HP: nothing to do.
	save.inventory.full_remedy = 1
	assert_str(FieldItems.use(cdb, save, "full_remedy", m).error).is_equal("no_effect")


func test_cure_item_on_a_fainted_creature() -> void:
	var cdb := _cure_db()
	var m := _cure_setup(cdb)
	m.status = "burn"
	m.hp = 0
	assert_str(FieldItems.use(cdb, save, "remedy", m).error).is_equal("fainted")
	assert_int(save.inventory.remedy).is_equal(2)


func test_can_use_and_usability_for_cure_items() -> void:
	var cdb := _cure_db()
	var m := _cure_setup(cdb)
	assert_bool(FieldItems.can_use(cdb, "remedy")).is_true()
	assert_bool(FieldItems.can_use(cdb, "burn_ward")).is_true()
	var u := FieldItems.usability(cdb, save, "remedy")
	assert_bool(u.ok).is_false()
	assert_str(u.reason).is_equal("No one needs it right now.")
	m.status = "shock"
	assert_bool(FieldItems.usability(cdb, save, "remedy").ok).is_true()
	assert_bool(FieldItems.usability(cdb, save, "burn_ward").ok).is_false()


# --- Counting item use (M7a) ---

func test_successful_use_counts_an_item() -> void:
	c.hp = 1
	FieldItems.use(db, save, "salve", c)
	assert_int(Counters.value(save, "items_used")).is_equal(1)


func test_failed_use_counts_nothing() -> void:
	assert_str(FieldItems.use(db, save, "salve", c).error).is_equal("no_effect")
	assert_int(Counters.value(save, "items_used")).is_equal(0)


func test_reset_seed_counts() -> void:
	save.inventory.reset_seed = 1
	c.training = {"patk": 2}
	assert_bool(FieldItems.use(db, save, "reset_seed", c).ok).is_true()
	assert_int(Counters.value(save, "items_used")).is_equal(1)
