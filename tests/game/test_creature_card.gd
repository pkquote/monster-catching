extends GdUnitTestSuite
## The creature summary card: header, radar, bars, moves, passive, held item; it stays in its rect.

var db: Database


func before() -> void:
	db = DataRegistry.db


func _card() -> CreatureCard:
	var card: CreatureCard = CreatureCard.new()
	add_child(auto_free(card))
	return card


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_header_shows_name_and_level() -> void:
	var card := _card()
	card.show_creature(db, CreatureInstance.create(db, "tidepup", 12))
	await _settle()
	assert_str(card.header_text()).is_equal("Tidepup  Lv 12")


func test_moves_listed_for_four_two_and_zero_moves() -> void:
	var card := _card()
	var c := CreatureInstance.create(db, "tidepup", 16)
	c.moves = PackedStringArray(["tackle", "splash_jab", "drench", "riptide"])
	card.show_creature(db, c)
	await _settle()
	assert_array(card.move_texts()).has_size(4)
	c.moves = PackedStringArray(["tackle", "drench"])
	card.show_creature(db, c)
	await _settle()
	assert_array(card.move_texts()).is_equal([db.move("tackle").name, db.move("drench").name])
	c.moves = PackedStringArray()
	card.show_creature(db, c)
	await _settle()
	assert_array(card.move_texts()).is_empty()


func test_passive_and_held_show_none_when_empty() -> void:
	var card := _card()
	var c := CreatureInstance.create(db, "tidepup", 10)
	c.passive = ""
	c.affinity_passive = ""
	c.held_item = ""
	card.show_creature(db, c)
	await _settle()
	assert_str(card.passive_text()).is_equal("Passive: none")
	assert_str(card.held_text()).is_equal("Held: none")


func test_passive_shows_the_active_slots_passive() -> void:
	var card := _card()
	var c := CreatureInstance.create(db, "tidepup", 10)
	c.passive = "tidal_heart"
	c.affinity_passive = "finisher"
	c.active_passive = Passives.SLOT_AFFINITY
	card.show_creature(db, c)
	await _settle()
	assert_str(card.passive_text()).is_equal("Passive: " + db.passive("finisher").name)


func test_held_item_name_shown() -> void:
	var card := _card()
	var c := CreatureInstance.create(db, "tidepup", 10)
	c.held_item = "oran_berry"
	card.show_creature(db, c)
	await _settle()
	assert_str(card.held_text()).is_equal("Held: " + db.item("oran_berry").name)


func _outside(card: CreatureCard) -> Array:
	var bad: Array = []
	var rect := card.get_global_rect().grow(0.5)
	for n: Node in card.find_children("*", "Control", true, false):
		var r := (n as Control).get_global_rect()
		if (n as Control).visible and r.size.x > 0.0 and not rect.encloses(r):
			bad.append("%s %s" % [n.get_class(), r])
	return bad


func test_long_nickname_and_move_names_stay_inside_the_card() -> void:
	var card := _card()
	var c := CreatureInstance.create(db, "torrentusk", 40)
	c.nickname = "Sir Reginald Bartholomew Torrentusk the Magnificent Third"
	c.held_item = "guard_banner"
	card.show_creature(db, c)
	await _settle()
	var bad := _outside(card)
	assert_array(bad).override_failure_message("outside the card: %s" % [bad]).is_empty()


func test_card_has_the_fixed_size() -> void:
	var card := _card()
	card.show_creature(db, CreatureInstance.create(db, "tidepup", 5))
	await _settle()
	assert_vector(card.size).is_equal(CreatureCard.SIZE)


func test_show_creature_twice_replaces_the_contents() -> void:
	var card := _card()
	var first := CreatureInstance.create(db, "tidepup", 5)
	first.moves = PackedStringArray(["tackle", "drench"])
	card.show_creature(db, first)
	await _settle()
	var children_before := card.find_children("*", "", true, false).size()
	var second := CreatureInstance.create(db, "tidepup", 20)
	second.moves = PackedStringArray(["tackle", "riptide"])
	card.show_creature(db, second)
	await _settle()
	assert_str(card.header_text()).is_equal("Tidepup  Lv 20")
	assert_int(card.find_children("*", "", true, false).size()).is_equal(children_before)
