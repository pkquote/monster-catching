extends GdUnitTestSuite
## Buying and selling.

var db: Database
var save: SaveGame


func before() -> void:
	db = DataLoader.load_database("res://data").db


func before_test() -> void:
	save = SaveGame.new_game("Ana", 1000, RandomNumberGenerator.new())
	save.money = 500


func test_buy() -> void:
	var r := Shop.buy(db, save, "salve", 3)
	assert_bool(r.ok).is_true()
	assert_int(save.money).is_equal(50)
	assert_int(save.inventory.salve).is_equal(3)


func test_buy_without_enough_money_changes_nothing() -> void:
	var r := Shop.buy(db, save, "salve", 4)
	assert_bool(r.ok).is_false()
	assert_str(r.error).is_equal("not_enough_money")
	assert_int(save.money).is_equal(500)
	assert_bool(save.inventory.has("salve")).is_false()


func test_sell_at_half_price() -> void:
	save.inventory = {"salve": 3}
	var r := Shop.sell(db, save, "salve", 2)
	assert_bool(r.ok).is_true()
	assert_int(save.money).is_equal(650)
	assert_int(save.inventory.salve).is_equal(1)


func test_sell_more_than_owned() -> void:
	save.inventory = {"salve": 1}
	assert_str(Shop.sell(db, save, "salve", 2).error).is_equal("not_enough_items")
	assert_int(save.money).is_equal(500)


func test_bad_amounts() -> void:
	assert_str(Shop.buy(db, save, "salve", 0).error).is_equal("bad_amount")
	assert_str(Shop.buy(db, save, "salve", 100).error).is_equal("bad_amount")
	assert_str(Shop.sell(db, save, "salve", 0).error).is_equal("bad_amount")


func test_sell_price_and_unsellable() -> void:
	assert_int(Shop.sell_price(db, "salve")).is_equal(75)
	assert_int(Shop.sell_price(db, "nonexistent")).is_equal(0)
	save.inventory = {"nonexistent": 1}
	assert_str(Shop.sell(db, save, "nonexistent", 1).error).is_equal("cannot_sell")
