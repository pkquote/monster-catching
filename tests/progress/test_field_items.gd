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


func test_capture_item_is_not_usable() -> void:
	assert_bool(FieldItems.can_use(db, "lure_cage")).is_false()
	assert_bool(FieldItems.can_use(db, "salve")).is_true()
	assert_str(FieldItems.use(db, save, "lure_cage", c).error).is_equal("not_usable")
