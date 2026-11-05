extends GdUnitTestSuite
## Held items in battle: always-on effects, ally auras and protection banners.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("passives", {"id": "strong", "name": "Strong", "description": "Test passive.",
		"effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0}]})
	r.add_entry("passives", {"id": "rod", "name": "Rod", "description": "Test passive.",
		"effects": [{"op": "absorb_type", "type": "electric", "fraction": 0.25}]})
	r.add_entry("passives", {"id": "fireproof", "name": "Fireproof", "description": "Test passive.",
		"effects": [{"op": "status_immune", "status": "burn"}]})
	r.add_entry("passives", {"id": "sturdy", "name": "Sturdy", "description": "Test passive.",
		"effects": [{"op": "guard_stages"}]})
	r.add_entry("passives", {"id": "dry", "name": "Dry", "description": "Test passive.",
		"effects": [{"op": "field_shelter", "state": "soaked"}]})
	r.add_entry("passives", {"id": "prickly", "name": "Prickly", "description": "Test passive.",
		"triggers": [{"on": "hit", "effects": [{"op": "stat_stage", "stat": "patk", "stages": -2}]}]})
	for it in [
		{"id": "power_charm", "held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0}]}},
		{"id": "power_charm_b", "held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.5}]}},
		{"id": "low_charm", "held": {"effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0,
			"when": {"hp_below": 0.5}}]}},
		{"id": "fire_charm", "held": {"effects": [{"op": "status_immune", "status": "burn"}]}},
		{"id": "rod_charm", "held": {"effects": [{"op": "absorb_type", "type": "electric", "fraction": 0.25}]}},
		{"id": "guard_charm", "held": {"effects": [{"op": "guard_stages"}]}},
		{"id": "dry_charm", "held": {"effects": [{"op": "field_shelter", "state": "soaked"}]}},
		{"id": "aura_charm", "held": {"scope": "allies",
			"effects": [{"op": "incoming_type_mod", "mult": 0.5}]}},
		{"id": "aura_charm_b", "held": {"scope": "allies",
			"effects": [{"op": "incoming_type_mod", "mult": 0.5}]}},
		# Triggers.
		{"id": "berry", "held": {"use": "consumed", "triggers": [{"on": "hit", "when": {"hp_below": 0.5},
			"effects": [{"op": "heal", "fraction": 0.5, "target": "self"}]}]}},
		{"id": "fickle_berry", "held": {"use": "consumed", "triggers": [{"on": "hit", "chance": 50,
			"effects": [{"op": "heal", "fraction": 0.5, "target": "self"}]}]}},
		{"id": "round_berry", "held": {"use": "consumed", "triggers": [{"on": "round_end",
			"effects": [{"op": "heal", "fraction": 0.25}]}]}},
		{"id": "spiky", "held": {"use": "per_battle", "triggers": [{"on": "hit",
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]}},
		{"id": "spiky_perm", "held": {"triggers": [{"on": "hit",
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]}},
		{"id": "thorn_charm", "held": {"triggers": [{"on": "hit",
			"effects": [{"op": "damage", "power": 30, "target": "attacker"}]}]}},
		{"id": "last_gasp", "held": {"use": "consumed", "triggers": [{"on": "faint",
			"effects": [{"op": "damage", "power": 30, "target": "attacker"}]}]}},
		{"id": "soak_charm", "held": {"triggers": [{"on": "enter",
			"effects": [{"op": "apply_field_state", "side": "enemy", "state": "soaked"}]}]}},
		{"id": "wet_spiky", "held": {"triggers": [{"on": "hit", "when": {"field": "soaked", "side": "own"},
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]}},
	]:
		it.merge({"name": str(it.id).capitalize(), "description": "Test held item.", "category": "held",
			"price": 10})
		r.add_entry("items", it)
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test items invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String, passive := "", held := "", moves: Array = ["hit"]) -> CreatureInstance:
	var c := FixtureDB.make(db, species, 50, moves)
	c.passive = passive
	c.held_item = held
	return c


func _first(e: BattleEngine, side: int) -> Battler:
	return e.sides[side].active()[0]


func _patk(e: BattleEngine, b: Battler) -> float:
	return BattleMath.effective_stat(e, b, "patk")


func _dmg(e: BattleEngine, user: Battler, move: String, target: Battler) -> float:
	return BattleAI.estimate_damage(e, user, db.move(move), target, 1)


func _round(e: BattleEngine, actions: Dictionary) -> Array:
	var chosen: Array = []
	for side in e.sides:
		for b in side.active():
			chosen.append(actions.get(b.bid, BattleAction.pass_turn(b.bid)))
	return e.resolve_round(chosen)


func _triggered(events: Array) -> Array:
	return FixtureDB.events_of(events, BattleEvents.PASSIVE_TRIGGERED)


func test_held_effects_apply_like_passives() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", "power_charm")], [_make("blob")])
	var me := _first(e, 0)
	assert_int(e.passive_rules.effects_for(me).size()).is_equal(1)
	assert_str(e.passive_rules.effects_for(me)[0].op).is_equal("stat_mod")
	assert_float(_patk(e, me)).is_equal_approx(_patk(e, _first(e, 1)) * 2.0, 0.001)
	assert_array(e.passive_rules.effects_for(_first(e, 1))).is_empty()
	assert_object(e.passive_rules.held_def(me)).is_not_null()
	assert_str(e.passive_rules.held_def(me).id).is_equal("power_charm")
	assert_object(e.passive_rules.held_def(_first(e, 1))).is_null()


func test_held_item_and_passive_effects_stack() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "strong", "power_charm")], [_make("blob")])
	assert_float(_patk(e, _first(e, 0))).is_equal_approx(_patk(e, _first(e, 1)) * 4.0, 0.001)
	assert_int(e.passive_rules.effects_for(_first(e, 0)).size()).is_equal(2)


func test_held_effect_respects_when() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", "low_charm")], [_make("blob")])
	var me := _first(e, 0)
	assert_float(_patk(e, me)).is_equal_approx(_patk(e, _first(e, 1)), 0.001)
	me.creature.hp = me.creature.max_hp(db) / 4
	assert_float(_patk(e, me)).is_equal_approx(_patk(e, _first(e, 1)) * 2.0, 0.001)


func test_held_aura_reaches_allies_and_counts_once() -> void:
	var plain := FixtureDB.engine(db, [_make("tank"), _make("tank")], [_make("blob")], 2, 1)
	var base := _dmg(plain, _first(plain, 1), "hit", plain.sides[0].active()[1])
	var one := FixtureDB.engine(db, [_make("tank", "", "aura_charm"), _make("tank")], [_make("blob")], 2, 1)
	for ally in one.sides[0].active():
		assert_float(_dmg(one, _first(one, 1), "hit", ally) / base).is_between(0.45, 0.55)
	# Two holders of the same item: still half, not a quarter.
	var two := FixtureDB.engine(db, [_make("tank", "", "aura_charm"), _make("tank", "", "aura_charm")],
		[_make("blob")], 2, 1)
	for ally in two.sides[0].active():
		assert_float(_dmg(two, _first(two, 1), "hit", ally) / base).is_between(0.45, 0.55)
	# A different item id adds its own effect.
	var mixed := FixtureDB.engine(db, [_make("tank", "", "aura_charm"), _make("tank", "", "aura_charm_b")],
		[_make("blob")], 2, 1)
	for ally in mixed.sides[0].active():
		assert_float(_dmg(mixed, _first(mixed, 1), "hit", ally) / base).is_between(0.2, 0.3)
	# Foes are not covered.
	assert_float(_dmg(one, one.sides[0].active()[0], "hit", _first(one, 1))) \
		.is_equal(_dmg(plain, plain.sides[0].active()[0], "hit", _first(plain, 1)))
	# A passive aura and a held aura with the same effect are separate sources.
	var scope_self := FixtureDB.engine(db, [_make("tank", "", "power_charm"), _make("tank")], [_make("blob")], 2, 1)
	assert_array(scope_self.passive_rules.effects_for(scope_self.sides[0].active()[1])).is_empty()


func test_unknown_or_benched_held_item_gives_nothing() -> void:
	var unknown := FixtureDB.engine(db, [_make("blob", "", "no_such_item")], [_make("blob")])
	assert_array(unknown.passive_rules.effects_for(_first(unknown, 0))).is_empty()
	assert_object(unknown.passive_rules.held_def(_first(unknown, 0))).is_null()
	# A non-held item id (a heal item) is no held item either.
	var heal := FixtureDB.engine(db, [_make("blob", "", "potion")], [_make("blob")])
	assert_object(heal.passive_rules.held_def(_first(heal, 0))).is_null()
	assert_array(heal.passive_rules.effects_for(_first(heal, 0))).is_empty()
	# Benched holder: nothing for itself or for allies.
	var benched := FixtureDB.engine(db, [_make("tank"), _make("tank", "", "aura_charm")], [_make("blob")], 1, 1)
	var holder := benched.sides[0].battlers[1]
	assert_bool(holder.active).is_false()
	assert_array(benched.passive_rules.effects_for(holder)).is_empty()
	assert_object(benched.passive_rules.held_def(holder)).is_null()
	assert_array(benched.passive_rules.effects_for(_first(benched, 0))).is_empty()
	# Fainted holder on the field.
	var fainted := FixtureDB.engine(db, [_make("tank"), _make("tank", "", "aura_charm")], [_make("blob")], 2, 1)
	var down := fainted.sides[0].battlers[1]
	down.creature.hp = 0
	assert_array(fainted.passive_rules.effects_for(down)).is_empty()
	assert_object(fainted.passive_rules.held_def(down)).is_null()
	assert_array(fainted.passive_rules.effects_for(_first(fainted, 0))).is_empty()


func test_protection_banner_names_the_item() -> void:
	# Status immunity.
	var e := FixtureDB.engine(db, [_make("blob", "", "", ["burn_touch"])], [_make("tank", "", "fire_charm")])
	var events := _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "burn_touch", _first(e, 1).bid)})
	assert_str(_first(e, 1).status()).is_equal("")
	assert_int(_triggered(events).size()).is_equal(1)
	assert_str(_triggered(events)[0].item).is_equal("fire_charm")
	assert_str(_triggered(events)[0].passive).is_equal("")
	assert_int(_triggered(events)[0].bid).is_equal(_first(e, 1).bid)
	# Absorb.
	e = FixtureDB.engine(db, [_make("blob", "", "", ["zap"])], [_make("tank", "", "rod_charm")])
	_first(e, 1).creature.hp = _first(e, 1).creature.max_hp(db) / 2
	events = _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "zap", _first(e, 1).bid)})
	assert_int(_triggered(events).size()).is_equal(1)
	assert_str(_triggered(events)[0].item).is_equal("rod_charm")
	assert_str(_triggered(events)[0].passive).is_equal("")
	# Stage guard.
	e = FixtureDB.engine(db, [_make("blob", "", "", ["growl"])], [_make("tank", "", "guard_charm")])
	events = _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "growl")})
	assert_int(_first(e, 1).stages.patk).is_equal(0)
	assert_int(_triggered(events).size()).is_equal(1)
	assert_str(_triggered(events)[0].item).is_equal("guard_charm")
	assert_str(_triggered(events)[0].passive).is_equal("")
	# Shelter from reaction damage.
	e = FixtureDB.engine(db, [_make("blob", "", "", ["charge_up"])], [_make("tank", "", "dry_charm")])
	e.sides[1].field.add("soaked", 1, 3, 3)
	events = _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "charge_up")})
	assert_array(FixtureDB.events_of(events, BattleEvents.DAMAGE)).is_empty()
	assert_int(_triggered(events).size()).is_equal(1)
	assert_str(_triggered(events)[0].item).is_equal("dry_charm")
	assert_str(_triggered(events)[0].passive).is_equal("")


func test_protection_banner_from_a_passive_still_names_the_passive() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", "", ["burn_touch"])], [_make("tank", "fireproof")])
	var events := _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "burn_touch", _first(e, 1).bid)})
	assert_str(_triggered(events)[0].passive).is_equal("fireproof")
	assert_bool(_triggered(events)[0].has("item")).is_false()
	e = FixtureDB.engine(db, [_make("blob", "", "", ["zap"])], [_make("tank", "rod")])
	_first(e, 1).creature.hp = _first(e, 1).creature.max_hp(db) / 2
	events = _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "zap", _first(e, 1).bid)})
	assert_str(_triggered(events)[0].passive).is_equal("rod")
	assert_bool(_triggered(events)[0].has("item")).is_false()
	e = FixtureDB.engine(db, [_make("blob", "", "", ["growl"])], [_make("tank", "sturdy")])
	events = _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "growl")})
	assert_str(_triggered(events)[0].passive).is_equal("sturdy")
	assert_bool(_triggered(events)[0].has("item")).is_false()
	e = FixtureDB.engine(db, [_make("blob", "", "", ["charge_up"])], [_make("tank", "dry")])
	e.sides[1].field.add("soaked", 1, 3, 3)
	events = _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "charge_up")})
	assert_str(_triggered(events)[0].passive).is_equal("dry")
	assert_bool(_triggered(events)[0].has("item")).is_false()


# --- Triggers, when, and using items up ---

func _hit(e: BattleEngine, from_side: int) -> Array:
	var me := _first(e, from_side)
	var foe := _first(e, 1 - from_side)
	return _round(e, {me.bid: BattleAction.use_move(me.bid, "hit", foe.bid)})


func _consumed(events: Array) -> Array:
	return FixtureDB.events_of(events, BattleEvents.ITEM_CONSUMED)


func _hurt(b: Battler) -> void:
	b.creature.hp = b.creature.max_hp(db) / 4


func test_item_trigger_fires_and_names_the_item() -> void:
	var e := FixtureDB.engine(db, [_make("blob")], [_make("tank", "", "berry")])
	var foe := _first(e, 1)
	_hurt(foe)
	var events := _hit(e, 0)
	var fired := _triggered(events)
	assert_int(fired.size()).is_equal(1)
	assert_str(fired[0].item).is_equal("berry")
	assert_str(fired[0].passive).is_equal("")
	assert_int(fired[0].bid).is_equal(foe.bid)
	var healed := FixtureDB.events_of(events, BattleEvents.HEAL)
	assert_int(healed.size()).is_equal(1)
	assert_int(healed[0].amount).is_greater(0)
	# A stat-dropping item hits the attacker.
	var e2 := FixtureDB.engine(db, [_make("blob")], [_make("tank", "", "spiky_perm")])
	var events2 := _hit(e2, 0)
	assert_str(_triggered(events2)[0].item).is_equal("spiky_perm")
	assert_int(_first(e2, 0).stages.patk).is_equal(-1)
	# An enter item applies its field state.
	var e3 := FixtureDB.engine(db, [_make("blob", "", "soak_charm")], [_make("tank")])
	assert_bool(e3.sides[1].field.has("soaked")).is_true()


func test_passive_triggers_run_before_item_triggers_for_the_same_event() -> void:
	var e := FixtureDB.engine(db, [_make("blob")], [_make("tank", "prickly", "spiky_perm")])
	var fired := _triggered(_hit(e, 0))
	assert_int(fired.size()).is_equal(2)
	assert_str(fired[0].passive).is_equal("prickly")
	assert_bool(fired[0].has("item")).is_false()
	assert_str(fired[1].item).is_equal("spiky_perm")
	assert_int(_first(e, 0).stages.patk).is_equal(-3)


func test_trigger_when_gates_firing_for_passives_and_items() -> void:
	# Item: above the HP threshold nothing fires, below it fires.
	var e := FixtureDB.engine(db, [_make("blob")], [_make("tank", "", "berry")])
	var foe := _first(e, 1)
	assert_array(_triggered(_hit(e, 0))).is_empty()
	_hurt(foe)
	assert_int(_triggered(_hit(e, 0)).size()).is_equal(1)
	# Field condition on an item trigger.
	var f := FixtureDB.engine(db, [_make("blob")], [_make("tank", "", "wet_spiky")])
	assert_array(_triggered(_hit(f, 0))).is_empty()
	f.sides[1].field.add("soaked", 1, 3, 3)
	assert_int(_triggered(_hit(f, 0)).size()).is_equal(1)


func test_consumed_item_is_cleared_and_announced() -> void:
	var source := _make("tank", "", "berry")
	var e := FixtureDB.engine(db, [_make("blob")], [source])
	var foe := _first(e, 1)
	_hurt(foe)
	var events := _hit(e, 0)
	assert_str(foe.creature.held_item).is_equal("")
	assert_int(_consumed(events).size()).is_equal(1)
	assert_str(_consumed(events)[0].item).is_equal("berry")
	assert_int(_consumed(events)[0].bid).is_equal(foe.bid)
	# The real creature only loses it on commit.
	assert_str(source.held_item).is_equal("berry")
	e.commit(1)
	assert_str(source.held_item).is_equal("")
	# A second hit fires nothing.
	_hurt(foe)
	var again := _hit(e, 0)
	assert_array(_triggered(again)).is_empty()
	assert_array(_consumed(again)).is_empty()


func test_consumed_item_survives_when_it_does_not_fire() -> void:
	# The when is false.
	var a := _make("tank", "", "berry")
	var e := FixtureDB.engine(db, [_make("blob")], [a])
	var events := _hit(e, 0)
	assert_array(_triggered(events)).is_empty()
	assert_array(_consumed(events)).is_empty()
	assert_str(_first(e, 1).creature.held_item).is_equal("berry")
	e.commit(1)
	assert_str(a.held_item).is_equal("berry")
	# The chance roll fails: use a seed whose first 1-100 roll is above 50.
	var failing := -1
	for s in 200:
		var r := RandomNumberGenerator.new()
		r.seed = s
		if r.randi_range(1, 100) > 50:
			failing = s
			break
	assert_int(failing).is_greater_equal(0)
	var b := _make("tank", "", "fickle_berry")
	var e2 := FixtureDB.engine(db, [_make("blob")], [b])
	_hurt(_first(e2, 1))
	e2.rng.seed = failing
	e2.passive_rules.fire(_first(e2, 1), "hit", _first(e2, 0), true)
	var ev2 := e2._take_events()
	assert_array(_triggered(ev2)).is_empty()
	assert_array(_consumed(ev2)).is_empty()
	assert_str(_first(e2, 1).creature.held_item).is_equal("fickle_berry")
	e2.commit(1)
	assert_str(b.held_item).is_equal("fickle_berry")
	# A round-end heal at full HP would do nothing, so the item is kept.
	var c := _make("tank", "", "round_berry")
	var e3 := FixtureDB.engine(db, [_make("blob")], [c])
	var ev3 := _round(e3, {})
	assert_array(_triggered(ev3)).is_empty()
	assert_array(_consumed(ev3)).is_empty()
	assert_str(_first(e3, 1).creature.held_item).is_equal("round_berry")
	e3.commit(1)
	assert_str(c.held_item).is_equal("round_berry")
	# It is used once the holder is hurt.
	_hurt(_first(e3, 1))
	var ev4 := _round(e3, {})
	assert_int(_triggered(ev4).size()).is_equal(1)
	assert_int(_consumed(ev4).size()).is_equal(1)
	assert_str(_first(e3, 1).creature.held_item).is_equal("")


func test_consumed_item_is_gone_after_the_creature_faints_and_battle_ends() -> void:
	var source := _make("tank", "", "berry")
	var e := FixtureDB.engine(db, [_make("blob")], [source])
	var foe := _first(e, 1)
	_hurt(foe)
	var first := _hit(e, 0)
	assert_int(_consumed(first).size()).is_equal(1)
	assert_bool(e.is_over()).is_false()
	foe.creature.hp = 1
	_hit(e, 0)
	assert_bool(foe.fainted).is_true()
	assert_bool(e.is_over()).is_true()
	e.commit(1)
	assert_str(source.held_item).is_equal("")
	assert_int(source.hp).is_equal(0)


func test_faint_item_trigger_fires_as_the_holder_goes_down() -> void:
	var source := _make("tank", "", "last_gasp")
	var e := FixtureDB.engine(db, [_make("blob")], [source, _make("tank")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	foe.creature.hp = 1
	var hp_before := me.hp()
	var events := _hit(e, 0)
	assert_bool(foe.fainted).is_true()
	assert_bool(e.is_over()).is_false()
	var fired := _triggered(events).filter(func(ev): return ev.get("item", "") == "last_gasp")
	assert_int(fired.size()).is_equal(1)
	assert_int(me.hp()).is_less(hp_before)
	assert_int(_consumed(events).size()).is_equal(1)
	var faint_at := -1
	var consumed_at := -1
	for i in events.size():
		if events[i].type == BattleEvents.FAINT and events[i].bid == foe.bid:
			faint_at = i
		if events[i].type == BattleEvents.ITEM_CONSUMED:
			consumed_at = i
	assert_int(consumed_at).is_greater(faint_at)
	assert_int(faint_at).is_greater_equal(0)
	e.commit(1)
	assert_str(source.held_item).is_equal("")


func test_per_battle_item_fires_once_and_is_kept() -> void:
	var source := _make("tank", "", "spiky")
	var e := FixtureDB.engine(db, [_make("blob")], [source])
	var first := _hit(e, 0)
	assert_int(_triggered(first).size()).is_equal(1)
	assert_array(_consumed(first)).is_empty()
	assert_bool(_first(e, 1).held_spent).is_true()
	var second := _hit(e, 0)
	assert_array(_triggered(second)).is_empty()
	assert_int(_first(e, 0).stages.patk).is_equal(-1)
	assert_str(_first(e, 1).creature.held_item).is_equal("spiky")
	e.commit(1)
	assert_str(source.held_item).is_equal("spiky")
	# A new battle with the same creature starts fresh.
	var e2 := FixtureDB.engine(db, [_make("blob")], [source])
	assert_bool(_first(e2, 1).held_spent).is_false()
	assert_int(_triggered(_hit(e2, 0)).size()).is_equal(1)


func test_permanent_item_fires_every_time() -> void:
	var e := FixtureDB.engine(db, [_make("blob")], [_make("tank", "", "spiky_perm")])
	assert_int(_triggered(_hit(e, 0)).size()).is_equal(1)
	assert_int(_triggered(_hit(e, 0)).size()).is_equal(1)
	assert_int(_first(e, 0).stages.patk).is_equal(-2)
	assert_str(_first(e, 1).creature.held_item).is_equal("spiky_perm")
	assert_bool(_first(e, 1).held_spent).is_false()


func test_held_trigger_effects_earn_no_affinity_and_do_not_chain() -> void:
	# No Affinity: a held heal earns no Warden points.
	var e := FixtureDB.engine(db, [_make("blob")], [_make("tank", "", "round_berry")])
	var holder := _first(e, 1)
	_hurt(holder)
	var hp_before := int(holder.creature.affinity.warden)
	var events := _round(e, {})
	assert_int(FixtureDB.events_of(events, BattleEvents.HEAL).size()).is_equal(1)
	assert_int(int(holder.creature.affinity.warden)).is_equal(hp_before)
	# No chaining: the item damage on the attacker sets off the attacker hit trigger
	# (prickly) for nothing, and earns it no Affinity.
	var f := FixtureDB.engine(db, [_make("blob", "prickly")], [_make("tank", "", "thorn_charm")])
	var me := _first(f, 0)
	var foe := _first(f, 1)
	var warden := int(me.creature.affinity.warden)
	var ev := _hit(f, 0)
	assert_int(_triggered(ev).size()).is_equal(1)
	assert_str(_triggered(ev)[0].item).is_equal("thorn_charm")
	assert_int(foe.stages.patk).is_equal(0)
	assert_int(int(me.creature.affinity.warden)).is_equal(warden)
	assert_int(FixtureDB.events_of(ev, BattleEvents.DAMAGE).size()).is_equal(2)


func test_passive_source_wins_over_item_when_both_protect() -> void:
	# Both give the same immunity: the passive is checked first and is the one named.
	var e := FixtureDB.engine(db, [_make("blob", "", "", ["burn_touch"])], [_make("tank", "fireproof", "fire_charm")])
	var events := _round(e, {_first(e, 0).bid: BattleAction.use_move(_first(e, 0).bid, "burn_touch", _first(e, 1).bid)})
	assert_str(_triggered(events)[0].passive).is_equal("fireproof")
	assert_bool(_triggered(events)[0].has("item")).is_false()
