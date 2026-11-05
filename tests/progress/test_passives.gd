extends GdUnitTestSuite
## Rolled creature passives: creation, persistence, backfill, tamer parties.

var db: Database


func before() -> void:
	db = DataLoader.load_database("res://data", "res://dialogue").db


func test_create_without_rng_takes_first_passive() -> void:
	var c := CreatureInstance.create(db, "emberkit", 5)
	assert_str(c.passive).is_equal("kindling")
	assert_str(c.affinity_passive).is_empty()
	assert_str(c.active_passive).is_equal("rolled")
	assert_str(Passives.active_id(c)).is_equal("kindling")


func test_create_with_rng_rolls_from_the_list() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 50:
		seen[CreatureInstance.create(db, "emberkit", 5, PackedStringArray(), rng).passive] = true
	assert_array(seen.keys()).contains_exactly_in_any_order(["kindling", "ember_trail"])


func test_active_id_is_empty_when_that_slot_is_empty() -> void:
	var c := CreatureInstance.create(db, "emberkit", 5)
	c.active_passive = "affinity"
	assert_str(Passives.active_id(c)).is_empty()
	c.affinity_passive = "finisher"
	assert_str(Passives.active_id(c)).is_equal("finisher")


func test_passive_round_trips_and_copies() -> void:
	var c := CreatureInstance.create(db, "emberkit", 5)
	c.passive = "ember_trail"
	c.affinity_passive = "finisher"
	c.active_passive = "affinity"
	var back := CreatureInstance.from_dict(c.to_dict())
	assert_str(back.passive).is_equal("ember_trail")
	assert_str(back.affinity_passive).is_equal("finisher")
	assert_str(back.active_passive).is_equal("affinity")
	var other := CreatureInstance.create(db, "emberkit", 5)
	other.copy_from(c)
	assert_str(other.passive).is_equal("ember_trail")
	assert_str(other.affinity_passive).is_equal("finisher")
	assert_str(other.active_passive).is_equal("affinity")


func test_backfill_is_deterministic_and_idempotent() -> void:
	var a := CreatureInstance.create(db, "emberkit", 9)
	a.passive = ""
	Passives.backfill(db, a)
	var first := a.passive
	assert_bool(db.creature("emberkit").passives.has(first)).is_true()
	Passives.backfill(db, a)
	assert_str(a.passive).is_equal(first)
	var b := CreatureInstance.create(db, "emberkit", 9)
	b.passive = ""
	Passives.backfill(db, b)
	assert_str(b.passive).is_equal(first)


func test_backfill_unknown_species_leaves_it() -> void:
	var c := CreatureInstance.new()
	c.species = "no_such_species"
	Passives.backfill(db, c)
	assert_str(c.passive).is_empty()
	assert_str(c.affinity_passive).is_empty()


func test_tamer_party_can_fix_a_passive() -> void:
	var tamer := db.tamer("rival_01")
	tamer.party[0]["passive"] = "lightning_rod"
	var player := [CreatureInstance.create(db, "emberkit", 5)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var setup := BattleSetup.vs_tamer(db, player, "rival_01", -1, {}, rng)
	assert_str(setup.sides[1].party[0].passive).is_equal("lightning_rod")
	tamer.party[0]["passive"] = ""


func test_tamer_party_can_hold_an_item() -> void:
	var tamer := db.tamer("rival_01")
	tamer.party[0]["held_item"] = "some_item"
	var player := [CreatureInstance.create(db, "emberkit", 5)]
	var setup := BattleSetup.vs_tamer(db, player, "rival_01")
	assert_str(setup.sides[1].party[0].held_item).is_equal("some_item")
	tamer.party[0]["held_item"] = ""


func test_unlock_once_at_threshold() -> void:
	var c := CreatureInstance.create(db, "emberkit", 5)
	c.affinity["striker"] = 29
	assert_str(Passives.try_unlock(db, c, "striker")).is_empty()
	assert_str(c.affinity_passive).is_empty()
	c.affinity["striker"] = 30
	assert_str(Passives.try_unlock(db, c, "striker")).is_equal("finisher")
	assert_str(c.affinity_passive).is_equal("finisher")
	assert_str(Passives.try_unlock(db, c, "striker")).is_empty()


func test_no_unlock_for_unlisted_track() -> void:
	var def := db.creature("emberkit")
	var saved: Dictionary = def.affinity_passives.duplicate()
	def.affinity_passives.erase("warden")
	var c := CreatureInstance.create(db, "emberkit", 5)
	c.affinity["warden"] = 40
	assert_str(Passives.try_unlock(db, c, "warden")).is_empty()
	assert_str(c.affinity_passive).is_empty()
	def.affinity_passives = saved


func test_unlock_only_one_per_creature() -> void:
	var c := CreatureInstance.create(db, "emberkit", 5)
	c.affinity["striker"] = 30
	c.affinity["warden"] = 45
	assert_str(Passives.try_unlock(db, c, "striker")).is_equal("finisher")
	assert_str(Passives.try_unlock(db, c, "warden")).is_empty()
	assert_str(c.affinity_passive).is_equal("finisher")


func test_award_affinity_unlocks_and_keeps_its_return_value() -> void:
	var c := CreatureInstance.create(db, "emberkit", 5)
	c.affinity["striker"] = 29
	assert_str(Progression.award_affinity(db, c, "hit_dealt")).is_equal("striker")
	assert_str(c.affinity_passive).is_equal("finisher")


func test_growth_keeps_rolled_position_and_track_passive() -> void:
	var c := CreatureInstance.create(db, "tidepup", 16)
	c.passive = "undertow"
	c.affinity_passive = "finisher"
	c.active_passive = "affinity"
	var to := db.creature("torrentusk")
	var saved: Dictionary = to.affinity_passives.duplicate()
	to.affinity_passives["striker"] = "guardian_aura"
	Progression.apply_growth(db, c, "torrentusk")
	to.affinity_passives = saved
	assert_str(c.passive).is_equal("bulwark_hide")
	assert_str(c.affinity_passive).is_equal("guardian_aura")
	assert_str(c.active_passive).is_equal("affinity")


func test_growth_keeps_affinity_passive_when_new_species_lacks_the_track() -> void:
	var c := CreatureInstance.create(db, "tidepup", 16)
	c.affinity_passive = "finisher"
	var to := db.creature("torrentusk")
	var saved: Dictionary = to.affinity_passives.duplicate()
	to.affinity_passives = {}
	Progression.apply_growth(db, c, "torrentusk")
	to.affinity_passives = saved
	assert_str(c.affinity_passive).is_equal("finisher")
	assert_str(c.passive).is_equal("tidal_heart")


func test_growth_to_single_passive_species_takes_its_first() -> void:
	var c := CreatureInstance.create(db, "tidepup", 16)
	c.passive = "undertow"
	var to := db.creature("torrentusk")
	var saved := to.passives
	to.passives = PackedStringArray(["bulwark_hide"])
	Progression.apply_growth(db, c, "torrentusk")
	to.passives = saved
	assert_str(c.passive).is_equal("bulwark_hide")


func test_backfill_unlocks_highest_track_at_30() -> void:
	var c := CreatureInstance.create(db, "emberkit", 20)
	c.affinity["striker"] = 31
	c.affinity["catalyst"] = 50
	Passives.backfill(db, c)
	assert_str(c.affinity_passive).is_equal("reaction_spark")
	var tie := CreatureInstance.create(db, "emberkit", 20)
	tie.affinity["warden"] = 30
	tie.affinity["striker"] = 30
	Passives.backfill(db, tie)
	assert_str(tie.affinity_passive).is_equal("finisher")
	var low := CreatureInstance.create(db, "emberkit", 20)
	low.affinity["striker"] = 29
	Passives.backfill(db, low)
	assert_str(low.affinity_passive).is_empty()


func test_unlock_event_emitted() -> void:
	var fx := FixtureDB.build()
	fx.creature("blob").affinity_passives = {"striker": "steady"}
	var a := FixtureDB.make(fx, "blob", 10, ["hit"])
	a.affinity["striker"] = fx.balance.growth_affinity_threshold - 1
	var e := FixtureDB.engine(fx, [a], [FixtureDB.make(fx, "tank", 10, ["hit"])])
	var events := e.resolve_round([BattleAction.use_move(e.sides[0].active()[0].bid, "hit", e.sides[1].active()[0].bid)])
	var found := FixtureDB.events_of(events, BattleEvents.PASSIVE_UNLOCKED)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0].passive).is_equal("steady")
	assert_int(found[0].bid).is_equal(e.sides[0].active()[0].bid)


func test_passive_trigger_with_a_failing_when_does_not_fire() -> void:
	var r := FixtureDB.raw()
	r.add_entry("passives", {"id": "grit", "name": "Grit", "description": "Test passive.",
		"triggers": [{"on": "hit", "when": {"hp_below": 0.5},
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]})
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test passive invalid:\n" + "\n".join(errors))
	var fx := Database.from_raw(r)
	var holder := FixtureDB.make(fx, "tank", 20, ["hit"])
	holder.passive = "grit"
	var e := FixtureDB.engine(fx, [FixtureDB.make(fx, "blob", 20, ["hit"])], [holder])
	var me: Battler = e.sides[0].active()[0]
	var foe: Battler = e.sides[1].active()[0]
	var events := e.resolve_round([BattleAction.use_move(me.bid, "hit", foe.bid), BattleAction.pass_turn(foe.bid)])
	assert_array(FixtureDB.events_of(events, BattleEvents.PASSIVE_TRIGGERED)).is_empty()
	assert_int(me.stages.patk).is_equal(0)
	# Hurt enough, the same trigger fires.
	foe.creature.hp = foe.creature.max_hp(fx) / 4
	events = e.resolve_round([BattleAction.use_move(me.bid, "hit", foe.bid), BattleAction.pass_turn(foe.bid)])
	assert_int(FixtureDB.events_of(events, BattleEvents.PASSIVE_TRIGGERED).size()).is_equal(1)
	assert_int(me.stages.patk).is_equal(-1)


func test_foe_unlock_is_silent() -> void:
	var fx := FixtureDB.build()
	fx.creature("blob").affinity_passives = {"striker": "steady"}
	var foe := FixtureDB.make(fx, "blob", 10, ["hit"])
	foe.affinity["striker"] = fx.balance.growth_affinity_threshold - 1
	var e := FixtureDB.engine(fx, [FixtureDB.make(fx, "tank", 10, ["hit"])], [foe])
	var events := e.resolve_round([BattleAction.use_move(e.sides[1].active()[0].bid, "hit", e.sides[0].active()[0].bid)])
	assert_array(FixtureDB.events_of(events, BattleEvents.PASSIVE_UNLOCKED)).is_empty()
	# The unlock still happens; it just isn't announced.
	assert_bool(e.sides[1].active()[0].creature.affinity_passive == "steady").is_true()


func test_existing_affinity_passive_is_not_reported_as_unlocked() -> void:
	var c := CreatureInstance.create(db, "emberkit", 5)
	c.affinity_passive = "finisher"
	assert_object(Progression.progress_entry(db, c, c.level, c.affinity_passive)).is_null()
	Progression.award_xp(db, c, Stats.xp_for_level(c.level + 1) - c.xp)
	var e := Progression.progress_entry(db, c, c.level - 1, "finisher")
	assert_object(e).is_not_null()
	assert_str(e.unlocked_passive).is_empty()


# --- Overworld field effects (the party lead's active passive) ---

func _party(creatures: Array) -> SaveGame:
	var s := SaveGame.new()
	s.party.assign(creatures)
	return s


func _with(species: String, passive: String) -> CreatureInstance:
	var c := CreatureInstance.create(db, species, 5)
	c.passive = passive
	return c


func test_field_mult_uses_lead_active_passive_only() -> void:
	var undertow := _with("tidepup", "undertow")
	var plain := _with("tidepup", "tidal_heart")
	assert_float(Passives.field_mult(db, _party([undertow, plain]), "encounter_rate")).is_equal_approx(0.8, 0.0001)
	# A non-lead's field effects don't count.
	assert_float(Passives.field_mult(db, _party([plain, undertow]), "encounter_rate")).is_equal(1.0)
	# Only the lead's active slot: Undertow sits in the rolled slot, Finisher is active.
	undertow.affinity_passive = "finisher"
	undertow.active_passive = Passives.SLOT_AFFINITY
	assert_float(Passives.field_mult(db, _party([undertow, plain]), "encounter_rate")).is_equal(1.0)


func _held_db() -> Database:
	var r := FixtureDB.raw()
	r.add_entry("passives", {"id": "lure", "name": "Lure", "description": "Test passive.",
		"field": [{"op": "encounter_rate", "mult": 2.0}]})
	r.add_entry("items", {"id": "calm_charm", "name": "Calm Charm", "description": "Test held item.",
		"category": "held", "price": 10,
		"held": {"field": [{"op": "encounter_rate", "mult": 0.5}, {"op": "xp_mult", "mult": 1.5}]}})
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	return Database.from_raw(r)


func test_field_mult_includes_the_leads_held_item() -> void:
	var hdb := _held_db()
	var lead := CreatureInstance.create(hdb, "blob", 5)
	var other := CreatureInstance.create(hdb, "blob", 5)
	lead.held_item = "calm_charm"
	assert_float(Passives.field_mult(hdb, _party([lead, other]), "encounter_rate")).is_equal_approx(0.5, 0.0001)
	assert_float(Passives.field_mult(hdb, _party([lead, other]), "xp_mult")).is_equal_approx(1.5, 0.0001)
	assert_float(Passives.field_mult(hdb, _party([lead, other]), "bond_gain")).is_equal(1.0)
	# Together with the lead's passive.
	lead.passive = "lure"
	assert_float(Passives.field_mult(hdb, _party([lead, other]), "encounter_rate")).is_equal_approx(1.0, 0.0001)
	# A fainted lead still counts.
	lead.hp = 0
	assert_float(Passives.field_mult(hdb, _party([lead, other]), "xp_mult")).is_equal_approx(1.5, 0.0001)
	# A non-lead's item is ignored.
	assert_float(Passives.field_mult(hdb, _party([other, lead]), "xp_mult")).is_equal(1.0)
	# An unknown item id and no lead.
	lead.held_item = "gone"
	assert_float(Passives.field_mult(hdb, _party([lead, other]), "xp_mult")).is_equal(1.0)
	assert_float(Passives.field_mult(hdb, SaveGame.new(), "xp_mult")).is_equal(1.0)


func test_field_mult_empty_party_is_one() -> void:
	assert_float(Passives.field_mult(db, SaveGame.new(), "encounter_rate")).is_equal(1.0)
	assert_float(Passives.field_mult(db, SaveGame.new(), "xp_mult")).is_equal(1.0)


func test_field_mult_counts_a_fainted_lead() -> void:
	var lead := _with("tidepup", "undertow")
	lead.hp = 0
	assert_float(Passives.field_mult(db, _party([lead, _with("emberkit", "kindling")]), "encounter_rate")) \
		.is_equal_approx(0.8, 0.0001)


func test_field_mult_reads_only_the_named_op() -> void:
	var s := _party([_with("sprigling", "photosynth")])
	assert_float(Passives.field_mult(db, s, "bond_gain")).is_equal_approx(1.25, 0.0001)
	assert_float(Passives.field_mult(db, s, "xp_mult")).is_equal(1.0)
	assert_float(Passives.field_mult(db, s, "encounter_rate")).is_equal(1.0)
	assert_float(Passives.field_mult(db, _party([_with("frostling", "cold_snap")]), "xp_mult")) \
		.is_equal_approx(1.1, 0.0001)
	# No passive at all.
	assert_float(Passives.field_mult(db, _party([_with("frostling", "")]), "xp_mult")).is_equal(1.0)


func test_bond_gain_scales_rest_and_never_losses() -> void:
	var rested := int(db.balance.bond_cfg.changes.rested)
	var c := CreatureInstance.create(db, "sprigling", 5)
	c.bond = 0
	assert_int(Bond.rest(db, c, 1.25)).is_equal(roundi(rested * 1.25))
	# A tiny multiplier still gives at least 1.
	c.bond = 0
	assert_int(Bond.change(db, c, "rested", 0.01)).is_equal(1)
	# Losses are never scaled.
	c.bond = 0
	assert_int(Bond.change(db, c, "fainted", 2.0)).is_equal(int(db.balance.bond_cfg.changes.fainted))


func test_set_active_refuses_locked() -> void:
	var c := CreatureInstance.create(db, "tidepup", 5)
	assert_str(Passives.set_active(c, Passives.SLOT_AFFINITY)).is_equal("locked")
	assert_str(c.active_passive).is_equal("rolled")
	assert_str(Passives.set_active(c, "sideways")).is_equal("bad_slot")
	assert_str(c.active_passive).is_equal("rolled")
	c.affinity_passive = "finisher"
	assert_str(Passives.set_active(c, Passives.SLOT_AFFINITY)).is_equal("")
	assert_str(Passives.active_id(c)).is_equal("finisher")
	assert_str(Passives.set_active(c, Passives.SLOT_ROLLED)).is_equal("")
	assert_str(Passives.active_id(c)).is_equal("tidal_heart")
	c.passive = ""
	assert_str(Passives.set_active(c, Passives.SLOT_ROLLED)).is_equal("locked")  # an empty slot
