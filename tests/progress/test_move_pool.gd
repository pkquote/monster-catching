extends GdUnitTestSuite
## The move pool: every move a creature has learned, whether or not it's in a slot.

var db: Database


func before() -> void:
	db = DataLoader.load_database("res://data").db


func test_create_pools_all_learnable_moves() -> void:
	var c := CreatureInstance.create(db, "tidepup", 14)
	assert_array(Array(c.move_pool)).contains_exactly_in_any_order(
		["tackle", "splash_jab", "drench", "riptide", "taunting_howl", "tide_beam"])
	assert_array(Array(c.moves)).contains_exactly(["drench", "riptide", "taunting_howl", "tide_beam"])


func test_create_with_explicit_moves_pools_them_first() -> void:
	var c := CreatureInstance.create(db, "tidepup", 5, PackedStringArray(["ember_flick"]))
	assert_array(Array(c.move_pool)).contains_exactly_in_any_order(["ember_flick", "tackle", "splash_jab", "drench"])


func test_level_up_with_free_slot_learns_and_pools() -> void:
	var c := CreatureInstance.create(db, "tidepup", 4, PackedStringArray(["tackle", "splash_jab"]))
	var events := Progression.award_xp(db, c, Stats.xp_for_level(5) - c.xp)
	assert_bool(c.moves.has("drench")).is_true()
	assert_bool(c.move_pool.has("drench")).is_true()
	assert_array(events.filter(func(e): return e.type == "move_learned")).has_size(1)


func test_level_up_with_full_slots_pools_and_offers() -> void:
	var c := CreatureInstance.create(db, "tidepup", 8,
		PackedStringArray(["tackle", "splash_jab", "drench", "tide_beam"]))
	var events := Progression.award_xp(db, c, Stats.xp_for_level(9) - c.xp)
	assert_bool(c.move_pool.has("riptide")).is_true()
	assert_bool(c.moves.has("riptide")).is_false()
	assert_array(events.filter(func(e): return e.type == "move_offered")).has_size(1)


func test_pool_round_trips_through_dict() -> void:
	var c := CreatureInstance.create(db, "tidepup", 14)
	var back := CreatureInstance.from_dict(c.to_dict())
	assert_array(Array(back.move_pool)).is_equal(Array(c.move_pool))


func test_old_dict_without_pool_uses_moves() -> void:
	var d := CreatureInstance.create(db, "tidepup", 14).to_dict()
	d.erase("move_pool")
	var back := CreatureInstance.from_dict(d)
	assert_array(Array(back.move_pool)).is_equal(Array(back.moves))


func test_copy_from_copies_the_pool() -> void:
	var a := CreatureInstance.create(db, "tidepup", 14)
	var b := CreatureInstance.create(db, "tidepup", 1)
	b.copy_from(a)
	assert_array(Array(b.move_pool)).is_equal(Array(a.move_pool))


func test_backfill_pool_adds_learnset_moves() -> void:
	var c := CreatureInstance.create(db, "tidepup", 9)
	c.moves = PackedStringArray(["tackle"])
	c.move_pool = PackedStringArray(["tackle"])
	Progression.backfill_pool(db, c)
	for m in ["tackle", "splash_jab", "drench", "riptide"]:
		assert_bool(c.move_pool.has(m)).is_true()
	var size: int = c.move_pool.size()
	Progression.backfill_pool(db, c)
	assert_int(c.move_pool.size()).is_equal(size)


func test_set_moves_refusals() -> void:
	var c := CreatureInstance.create(db, "tidepup", 14)
	assert_str(Progression.set_moves(db, c, PackedStringArray())).is_equal("empty")
	assert_str(Progression.set_moves(db, c, PackedStringArray(["tackle", "splash_jab", "drench", "riptide", "tide_beam"]))).is_equal("too_many")
	assert_str(Progression.set_moves(db, c, PackedStringArray(["tackle", "tackle"]))).is_equal("duplicate")
	assert_str(Progression.set_moves(db, c, PackedStringArray(["tackle", "quake_stomp"]))).is_equal("not_in_pool")
	assert_array(Array(c.moves)).contains_exactly(["drench", "riptide", "taunting_howl", "tide_beam"])
	c.moves = PackedStringArray(["tackle", "drench"])
	assert_str(Progression.set_moves(db, c, PackedStringArray(["riptide", "drench"]))).is_equal("")
	assert_array(Array(c.moves)).contains_exactly(["riptide", "drench"])


func test_reset_training_refunds_and_clamps() -> void:
	var c := CreatureInstance.create(db, "tidepup", 14)
	assert_str(Training.train(db, c, "hp", 10)).is_equal("")
	var refunded := Training.reset(db, c)
	assert_int(refunded).is_equal(10)
	assert_int(Training.spent(c)).is_equal(0)
	assert_int(c.hp).is_less_equal(c.max_hp(db))
	assert_int(c.hp).is_greater_equal(1)
	assert_int(c.energy).is_less_equal(c.max_energy(db))
	var f := CreatureInstance.create(db, "tidepup", 14)
	Training.train(db, f, "hp", 10)
	f.hp = 0
	Training.reset(db, f)
	assert_int(f.hp).is_equal(0)
	assert_int(Training.reset(db, f)).is_equal(0)


func test_growth_learns_moves_at_current_level() -> void:
	var full := CreatureInstance.create(db, "tidepup", 16)
	assert_int(full.moves.size()).is_equal(4)
	var ev := Progression.apply_growth(db, full, "torrentusk")
	assert_bool(full.move_pool.has("quake_stomp")).is_true()
	assert_bool(full.moves.has("quake_stomp")).is_false()
	assert_bool(ev.offered.has("quake_stomp")).is_true()
	assert_array(ev.learned).is_empty()
	var open := CreatureInstance.create(db, "tidepup", 16, PackedStringArray(["tackle", "drench", "riptide"]))
	var ev2 := Progression.apply_growth(db, open, "torrentusk")
	assert_bool(ev2.learned.has("quake_stomp")).is_true()
	assert_bool(open.moves.has("quake_stomp")).is_true()
	assert_bool(open.move_pool.has("quake_stomp")).is_true()


func test_growth_keeps_known_moves() -> void:
	var c := CreatureInstance.create(db, "tidepup", 16)
	var before := Array(c.moves)
	var pool_before := Array(c.move_pool)
	var ev := Progression.apply_growth(db, c, "torrentusk")
	assert_array(Array(c.moves)).is_equal(before)
	for m in pool_before:
		assert_bool(c.move_pool.has(m)).is_true()
	assert_str(ev.into).is_equal("torrentusk")
	assert_str(ev.from).is_equal("tidepup")


func test_progress_entry_reports_offers_and_growth() -> void:
	var c := CreatureInstance.create(db, "tidepup", 15)
	c.affinity["striker"] = 30
	Progression.award_xp(db, c, Stats.xp_for_level(16) - c.xp)
	var e := Progression.progress_entry(db, c, 15)
	assert_bool(e.growth_due).is_true()
	assert_object(e.creature).is_same(c)
	assert_array(e.offered_moves).is_empty()
	# Offers: a creature with full slots that reaches level 12 is offered taunting_howl.
	var d := CreatureInstance.create(db, "tidepup", 11, PackedStringArray(["tackle", "splash_jab", "drench", "riptide"]))
	Progression.award_xp(db, d, Stats.xp_for_level(12) - d.xp)
	var e2 := Progression.progress_entry(db, d, 11)
	assert_array(e2.offered_moves).contains_exactly(["taunting_howl"])
	assert_bool(e2.growth_due).is_false()


func test_progress_entry_empty_without_level_gain() -> void:
	var c := CreatureInstance.create(db, "tidepup", 15)
	assert_object(Progression.progress_entry(db, c, 15)).is_null()


func test_backfill_skips_a_removed_species() -> void:
	var c := CreatureInstance.create(db, "tidepup", 9)
	c.species = "no_longer_exists"
	var before := c.move_pool.duplicate()
	Progression.backfill_pool(db, c)
	assert_array(Array(c.move_pool)).is_equal(Array(before))


func test_growth_branch_names_the_affinity_behind_it() -> void:
	var c := CreatureInstance.create(db, "tidepup", 16)
	assert_dict(Progression.growth_branch(db, c)).is_equal({"into": "torrentusk", "affinity": ""})
	c.affinity["catalyst"] = db.balance.growth_affinity_threshold
	assert_dict(Progression.growth_branch(db, c)).is_equal({"into": "mistcoil", "affinity": "catalyst"})
	assert_str(Progression.growth_target(db, c)).is_equal("mistcoil")
	assert_dict(Progression.growth_branch(db, CreatureInstance.create(db, "tidepup", 5))).is_empty()
