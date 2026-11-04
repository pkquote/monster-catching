extends GdUnitTestSuite
## Losing a battle: heal, money cost, respawn; story battles without defeat rules.

var db: Database
var rng := RandomNumberGenerator.new()


func before() -> void:
	db = DataLoader.load_database("res://data").db


func _save() -> SaveGame:
	rng.seed = 2
	var s := SaveGame.new_game("Ana", 1000, rng)
	var c := CreatureInstance.create(db, "tidepup", 5)
	c.hp = 0
	c.energy = 0
	s.party.append(c)
	return s


func test_defeat_heals_and_costs_money() -> void:
	var s := _save()
	s.money = 1005
	var r := Defeat.apply(db, s)
	assert_int(r.lost_money).is_equal(100)
	assert_int(s.money).is_equal(905)
	assert_int(s.party[0].hp).is_equal(s.party[0].max_hp(db))
	assert_int(s.party[0].energy).is_equal(s.party[0].max_energy(db))


func test_defeat_respawns_at_last_heal() -> void:
	var s := _save()
	s.story.last_heal = {"map": "town_01_center", "spawn": "heal"}
	var r := Defeat.apply(db, s)
	assert_str(r.map).is_equal("town_01_center")
	assert_str(r.spawn).is_equal("heal")


func test_defeat_respawns_at_new_game_spawn_without_one() -> void:
	var r := Defeat.apply(db, _save())
	assert_str(r.map).is_equal(SaveGame.NEW_GAME_MAP)
	assert_str(r.spawn).is_equal(SaveGame.NEW_GAME_SPAWN)
