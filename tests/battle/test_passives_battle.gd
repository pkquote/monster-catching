extends GdUnitTestSuite
## Creature passives in battle: always-on effects, `when` conditions and ally auras.

var db: Database


func before() -> void:
	var r := FixtureDB.raw()
	r.add_entry("moves", FixtureDB._m("zap_drop", "electric", "special", 50, 100, "one_enemy",
		[{"op": "damage"}, {"op": "stat_stage", "stat": "patk", "stages": -1}]))
	for p in [
		{"id": "water_power", "effects": [{"op": "type_power", "type": "water", "mult": 2.0}]},
		{"id": "strong", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0}]},
		{"id": "speedy", "effects": [{"op": "stat_mod", "stat": "spd", "mult": 2.0}]},
		{"id": "earth_skin", "effects": [{"op": "incoming_type_mod", "type": "earth", "mult": 0.5}]},
		{"id": "warded", "effects": [{"op": "incoming_type_mod", "mult": 0.5}]},
		{"id": "desperate", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0, "when": {"hp_below": 0.5}}]},
		{"id": "rally", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0, "when": {"underdog": true}}]},
		{"id": "wet_own", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0,
			"when": {"field": "soaked", "side": "own"}}]},
		{"id": "wet_enemy", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 2.0,
			"when": {"field": "soaked", "side": "enemy"}}]},
		{"id": "aura", "scope": "allies", "effects": [{"op": "incoming_type_mod", "mult": 0.5}]},
		# Triggers.
		{"id": "soaker", "triggers": [{"on": "enter",
			"effects": [{"op": "apply_field_state", "side": "enemy", "state": "soaked"}]}]},
		{"id": "prickly", "triggers": [{"on": "hit", "contact": true,
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]},
		{"id": "fickle", "triggers": [{"on": "hit", "chance": 50,
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]},
		{"id": "rod", "effects": [{"op": "absorb_type", "type": "electric", "fraction": 0.25}],
			"triggers": [{"on": "hit", "effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]},
		{"id": "regen", "triggers": [{"on": "round_end", "effects": [{"op": "heal", "fraction": 0.25}]}]},
		{"id": "recharge", "triggers": [{"on": "round_end", "effects": [{"op": "restore_energy", "fraction": 0.25}]}]},
		{"id": "regen_rush", "triggers": [{"on": "round_end", "effects": [{"op": "heal", "fraction": 0.25},
			{"op": "stat_stage", "stat": "spd", "stages": 1}]}]},
		{"id": "closer", "triggers": [{"on": "knockout", "effects": [{"op": "stat_stage", "stat": "spd", "stages": 1}]}]},
		{"id": "trail", "triggers": [{"on": "faint",
			"effects": [{"op": "apply_field_state", "side": "enemy", "state": "scorched"}]}]},
		# Hits back hard enough to knock out, and would react to every outcome if chains were allowed.
		{"id": "thorns", "triggers": [
			{"on": "hit", "effects": [{"op": "damage", "power": 60, "target": "attacker"}]},
			{"on": "knockout", "effects": [{"op": "stat_stage", "stat": "spd", "stages": 1}]},
			{"on": "faint", "effects": [{"op": "apply_field_state", "side": "enemy", "state": "scorched"}]}]},
		# Protection.
		{"id": "fireproof", "effects": [{"op": "status_immune", "status": "burn"}]},
		{"id": "pure", "effects": [{"op": "status_immune"}]},
		{"id": "sturdy_all", "effects": [{"op": "guard_stages"}]},
		{"id": "grip", "effects": [{"op": "guard_stages", "stat": "patk"}]},
		{"id": "dry", "effects": [{"op": "field_shelter", "state": "soaked"}]},
		{"id": "ward_aura", "scope": "allies",
			"effects": [{"op": "status_immune", "status": "burn"}, {"op": "guard_stages"}]},
		# Game-specific.
		{"id": "booster", "effects": [{"op": "field_boost", "stacks": 1, "turns": 2}]},
		{"id": "sparker", "effects": [{"op": "reaction_power", "mult": 2.0}]},
		{"id": "saver", "effects": [{"op": "energy_discount", "amount": 5}]},
		{"id": "zap_saver", "effects": [{"op": "energy_discount", "type": "electric", "amount": 1}]},
		{"id": "rester", "effects": [{"op": "rest_bonus", "fraction": 0.25}]},
		{"id": "scrapper", "effects": [{"op": "scrap_power", "mult": 2.0}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	var errors := DataValidator.validate(r)
	assert(errors.is_empty(), "Test passives invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String, passive: String, moves: Array = ["hit"], level := 50) -> CreatureInstance:
	var c := FixtureDB.make(db, species, level, moves)
	c.passive = passive
	return c


func _dmg(e: BattleEngine, user: Battler, move: String, target: Battler) -> float:
	return BattleAI.estimate_damage(e, user, db.move(move), target, 1)


func _patk(e: BattleEngine, b: Battler) -> float:
	return BattleMath.effective_stat(e, b, "patk")


func _first(e: BattleEngine, side: int) -> Battler:
	return e.sides[side].active()[0]


# --- Always-on ops ---

func test_type_power_boosts_its_type_only() -> void:
	var boosted := FixtureDB.engine(db, [_make("fish", "water_power", ["splash", "hit"])], [_make("tank", "")])
	var plain := FixtureDB.engine(db, [_make("fish", "", ["splash", "hit"])], [_make("tank", "")])
	var splash_ratio := _dmg(boosted, _first(boosted, 0), "splash", _first(boosted, 1)) \
		/ _dmg(plain, _first(plain, 0), "splash", _first(plain, 1))
	assert_float(splash_ratio).is_between(1.9, 2.1)
	assert_float(_dmg(boosted, _first(boosted, 0), "hit", _first(boosted, 1))) \
		.is_equal(_dmg(plain, _first(plain, 0), "hit", _first(plain, 1)))


func test_stat_mod_from_passive() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "strong")], [_make("blob", "")])
	assert_float(_patk(e, _first(e, 0))).is_equal_approx(_patk(e, _first(e, 1)) * 2.0, 0.001)


func test_incoming_type_mod_and_typeless_resistance() -> void:
	var skin := FixtureDB.engine(db, [_make("mole", "", ["quake", "hit"])], [_make("tank", "earth_skin")])
	var ward := FixtureDB.engine(db, [_make("mole", "", ["quake", "hit"])], [_make("tank", "warded")])
	var plain := FixtureDB.engine(db, [_make("mole", "", ["quake", "hit"])], [_make("tank", "")])
	var base_quake := _dmg(plain, _first(plain, 0), "quake", _first(plain, 1))
	var base_hit := _dmg(plain, _first(plain, 0), "hit", _first(plain, 1))
	# Typed: only Earth damage is reduced.
	assert_float(_dmg(skin, _first(skin, 0), "quake", _first(skin, 1)) / base_quake).is_between(0.45, 0.55)
	assert_float(_dmg(skin, _first(skin, 0), "hit", _first(skin, 1))).is_equal(base_hit)
	# No type: every damage type is reduced.
	assert_float(_dmg(ward, _first(ward, 0), "quake", _first(ward, 1)) / base_quake).is_between(0.45, 0.55)
	assert_float(_dmg(ward, _first(ward, 0), "hit", _first(ward, 1)) / base_hit).is_between(0.45, 0.55)


# --- when ---

func test_when_hp_below_switches_live() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "desperate")], [_make("blob", "")])
	var me := _first(e, 0)
	var base := _patk(e, _first(e, 1))
	assert_float(_patk(e, me)).is_equal_approx(base, 0.001)
	me.creature.hp = me.creature.max_hp(db) / 4
	assert_float(_patk(e, me)).is_equal_approx(base * 2.0, 0.001)
	me.creature.hp = me.creature.max_hp(db)
	assert_float(_patk(e, me)).is_equal_approx(base, 0.001)


func test_when_underdog() -> void:
	var even := FixtureDB.engine(db, [_make("blob", "rally")], [_make("blob", "")])
	assert_float(_patk(even, _first(even, 0))).is_equal_approx(_patk(even, _first(even, 1)), 0.001)
	var e := FixtureDB.engine(db, [_make("blob", "rally")], [_make("blob", ""), _make("blob", "")], 1, 2)
	var me := _first(e, 0)
	var foe := _first(e, 1)
	# Outnumbered also brings the Underdog stat bonus; the passive doubles on top.
	var bonus := 1.0 + float(e.sides[0].underdog.stat_bonus)
	assert_float(_patk(e, me)).is_equal_approx(_patk(e, foe) * bonus * 2.0, 0.001)
	# A foe goes down: no longer outnumbered, read live.
	e.sides[1].active()[1].creature.hp = 0
	assert_float(_patk(e, me)).is_equal_approx(_patk(e, foe) * bonus, 0.001)


func test_when_field_own_and_enemy() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "wet_own"), _make("blob", "wet_enemy")],
		[_make("blob", ""), _make("blob", "wet_enemy")], 2, 2)
	var own_cond := e.sides[0].active()[0]
	var enemy_cond := e.sides[0].active()[1]
	var plain := e.sides[1].active()[0]
	var foe_enemy_cond := e.sides[1].active()[1]
	var base := _patk(e, plain)
	assert_float(_patk(e, own_cond)).is_equal_approx(base, 0.001)
	e.sides[0].field.add("soaked", 1, 3, 3)
	assert_float(_patk(e, own_cond)).is_equal_approx(base * 2.0, 0.001)
	assert_float(_patk(e, enemy_cond)).is_equal_approx(base, 0.001)
	assert_float(_patk(e, foe_enemy_cond)).is_equal_approx(base * 2.0, 0.001)


# --- Which passive ---

func test_only_active_passive_applies() -> void:
	var c := _make("blob", "strong")
	c.affinity_passive = "speedy"
	var e := FixtureDB.engine(db, [c], [_make("blob", "")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	assert_float(_patk(e, me)).is_equal_approx(_patk(e, foe) * 2.0, 0.001)
	assert_float(BattleMath.effective_stat(e, me, "spd")).is_equal_approx(BattleMath.effective_stat(e, foe, "spd"), 0.001)
	me.creature.active_passive = Passives.SLOT_AFFINITY
	assert_float(_patk(e, me)).is_equal_approx(_patk(e, foe), 0.001)
	assert_float(BattleMath.effective_stat(e, me, "spd")).is_equal_approx(BattleMath.effective_stat(e, foe, "spd") * 2.0, 0.001)


# --- Auras ---

func test_aura_applies_to_allies_once() -> void:
	var plain := FixtureDB.engine(db, [_make("tank", ""), _make("tank", "")], [_make("blob", "")], 2, 1)
	var base := _dmg(plain, _first(plain, 1), "hit", plain.sides[0].active()[1])
	# One aura holder: its ally and itself take half.
	var one := FixtureDB.engine(db, [_make("tank", "aura"), _make("tank", "")], [_make("blob", "")], 2, 1)
	for ally in one.sides[0].active():
		assert_float(_dmg(one, _first(one, 1), "hit", ally) / base).is_between(0.45, 0.55)
	# Two holders of the same aura: still half, not a quarter.
	var two := FixtureDB.engine(db, [_make("tank", "aura"), _make("tank", "aura")], [_make("blob", "")], 2, 1)
	for ally in two.sides[0].active():
		assert_float(_dmg(two, _first(two, 1), "hit", ally) / base).is_between(0.45, 0.55)
	# Foes are not covered.
	var foe := _first(one, 1)
	assert_float(_dmg(one, one.sides[0].active()[0], "hit", foe)) \
		.is_equal(_dmg(plain, plain.sides[0].active()[0], "hit", _first(plain, 1)))


func test_benched_or_fainted_aura_does_not_apply() -> void:
	var plain := FixtureDB.engine(db, [_make("tank", "")], [_make("blob", "")])
	var base := _dmg(plain, _first(plain, 1), "hit", _first(plain, 0))
	# Benched holder: no aura, and its own always-on effects are off too.
	var benched := FixtureDB.engine(db, [_make("tank", ""), _make("tank", "aura")], [_make("blob", "")], 1, 1)
	assert_float(_dmg(benched, _first(benched, 1), "hit", _first(benched, 0))).is_equal(base)
	var holder := benched.sides[0].battlers[1]
	assert_bool(holder.active).is_false()
	assert_array(benched.passive_rules.effects_for(holder)).is_empty()
	# Fainted holder on the field: no aura (compared with the same 2v1 line-up, no passives).
	var plain_pair := FixtureDB.engine(db, [_make("tank", ""), _make("tank", "")], [_make("blob", "")], 2, 1)
	plain_pair.sides[0].battlers[1].creature.hp = 0
	var pair_base := _dmg(plain_pair, _first(plain_pair, 1), "hit", _first(plain_pair, 0))
	var fainted := FixtureDB.engine(db, [_make("tank", ""), _make("tank", "aura")], [_make("blob", "")], 2, 1)
	var down := fainted.sides[0].battlers[1]
	down.creature.hp = 0
	assert_float(_dmg(fainted, _first(fainted, 1), "hit", _first(fainted, 0))).is_equal(pair_base)
	assert_array(fainted.passive_rules.effects_for(down)).is_empty()


# --- Triggers ---

func _unstarted(party0: Array, party1: Array, field0 := 1, field1 := 1, seed_value := 1) -> BattleEngine:
	var setup := BattleSetup.new()
	var max_active := maxi(field0, field1)
	setup.add_side(party0, max_active, field0)
	setup.add_side(party1, max_active, field1)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return BattleEngine.new(db, rng, setup)


func _triggered(events: Array) -> Array:
	return FixtureDB.events_of(events, BattleEvents.PASSIVE_TRIGGERED)


func _index_of(events: Array, type: String) -> int:
	for i in events.size():
		if events[i].type == type:
			return i
	return -1


func test_enter_sets_field_state_at_start_in_speed_order() -> void:
	var e := _unstarted([_make("slow", "soaker")], [_make("fast", "soaker")])
	var events := e.start()
	var fired := _triggered(events)
	assert_int(fired.size()).is_equal(2)
	# Fastest first, and only once both sides are on the field.
	assert_int(fired[0].bid).is_equal(_first(e, 1).bid)
	assert_int(fired[1].bid).is_equal(_first(e, 0).bid)
	assert_str(fired[0].passive).is_equal("soaker")
	var last_send_out := 0
	for i in events.size():
		if events[i].type == BattleEvents.SEND_OUT:
			last_send_out = i
	assert_int(_index_of(events, BattleEvents.PASSIVE_TRIGGERED)).is_greater(last_send_out)
	assert_bool(e.sides[0].field.has("soaked")).is_true()
	assert_bool(e.sides[1].field.has("soaked")).is_true()


func test_enter_on_swap_in() -> void:
	var e := FixtureDB.engine(db, [_make("blob", ""), _make("blob", "soaker")], [_make("tank", "")])
	assert_bool(e.sides[1].field.has("soaked")).is_false()
	var bench := e.sides[0].battlers[1]
	var events := e.resolve_round([BattleAction.swap(_first(e, 0).bid, bench.bid),
		BattleAction.pass_turn(_first(e, 1).bid)])
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(_triggered(events)[0].bid).is_equal(bench.bid)
	assert_bool(e.sides[1].field.has("soaked")).is_true()


func test_hit_contact_only_on_physical() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", ["hit", "blast"])], [_make("tank", "prickly")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	var events := e.resolve_round([BattleAction.use_move(me.bid, "blast", foe.bid), BattleAction.pass_turn(foe.bid)])
	assert_array(_triggered(events)).is_empty()
	assert_int(me.stages.patk).is_equal(0)
	events = e.resolve_round([BattleAction.use_move(me.bid, "hit", foe.bid), BattleAction.pass_turn(foe.bid)])
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(_triggered(events)[0].bid).is_equal(foe.bid)
	# Default target of a hit trigger: the attacker.
	assert_int(me.stages.patk).is_equal(-1)
	assert_int(foe.stages.patk).is_equal(0)


func test_hit_chance_uses_rng() -> void:
	var fired := 0
	for s in range(1, 21):
		var e := FixtureDB.engine(db, [_make("blob", "")], [_make("tank", "fickle")], -1, -1, s)
		var me := _first(e, 0)
		var events := e.resolve_round([BattleAction.use_move(me.bid, "hit", _first(e, 1).bid),
			BattleAction.pass_turn(_first(e, 1).bid)])
		var n := _triggered(events).size()
		assert_int(me.stages.patk).is_equal(-n)
		fired += n
	assert_int(fired).is_between(1, 19)


func test_absorb_type_heals_instead() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", ["zap"])], [_make("tank", "rod")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	var max_hp := foe.creature.max_hp(db)
	foe.creature.hp = max_hp / 2
	var events := e.resolve_round([BattleAction.use_move(me.bid, "zap", foe.bid), BattleAction.pass_turn(foe.bid)])
	assert_array(FixtureDB.events_of(events, BattleEvents.DAMAGE)).is_empty()
	var heals := FixtureDB.events_of(events, BattleEvents.HEAL)
	assert_int(heals.size()).is_equal(1)
	assert_int(heals[0].bid).is_equal(foe.bid)
	assert_int(heals[0].amount).is_equal(roundi(max_hp * 0.25))
	assert_int(foe.hp()).is_equal(max_hp / 2 + roundi(max_hp * 0.25))
	# Shown as the passive acting, but not a hit: no hit trigger, no hit credit.
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(_index_of(events, BattleEvents.PASSIVE_TRIGGERED)).is_less(_index_of(events, BattleEvents.HEAL))
	assert_int(me.stages.patk).is_equal(0)
	assert_int(foe.last_hit_by).is_equal(-1)
	assert_bool(e.rewards.affinity_log.has(me.bid)).is_false()


func test_absorbed_move_skips_its_side_effects() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", ["zap_drop"])], [_make("tank", "rod")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	foe.creature.hp = foe.creature.max_hp(db) / 2
	e.resolve_round([BattleAction.use_move(me.bid, "zap_drop", foe.bid), BattleAction.pass_turn(foe.bid)])
	assert_int(foe.stages.patk).is_equal(0)
	# A creature without the passive still takes the side effect.
	var plain := FixtureDB.engine(db, [_make("blob", "", ["zap_drop"])], [_make("tank", "")])
	var target := _first(plain, 1)
	plain.resolve_round([BattleAction.use_move(_first(plain, 0).bid, "zap_drop", target.bid), BattleAction.pass_turn(target.bid)])
	assert_int(target.stages.patk).is_equal(-1)


func test_absorb_when_immune_still_heals() -> void:
	# Electric does nothing to Earth (type multiplier 0), but the absorb still heals.
	var e := FixtureDB.engine(db, [_make("blob", "", ["zap"])], [_make("mole", "rod")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	var max_hp := foe.creature.max_hp(db)
	foe.creature.hp = max_hp / 2
	var events := e.resolve_round([BattleAction.use_move(me.bid, "zap", foe.bid), BattleAction.pass_turn(foe.bid)])
	assert_array(FixtureDB.events_of(events, BattleEvents.NO_EFFECT)).is_empty()
	assert_array(FixtureDB.events_of(events, BattleEvents.DAMAGE)).is_empty()
	assert_int(FixtureDB.events_of(events, BattleEvents.HEAL).size()).is_equal(1)
	assert_int(foe.hp()).is_greater(max_hp / 2)
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(me.stages.patk).is_equal(0)
	assert_int(foe.last_hit_by).is_equal(-1)
	assert_bool(e.rewards.affinity_log.has(me.bid)).is_false()


func test_round_end_heal() -> void:
	var e := FixtureDB.engine(db, [_make("tank", "regen")], [_make("tank", "")])
	var me := _first(e, 0)
	var max_hp := me.creature.max_hp(db)
	me.creature.hp = max_hp / 2
	e.sides[0].field.add("charged", 1, 1, 3)
	var events := e.resolve_round([BattleAction.pass_turn(me.bid), BattleAction.pass_turn(_first(e, 1).bid)])
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(me.hp()).is_equal(max_hp / 2 + roundi(max_hp * 0.25))
	# Before field states count down.
	assert_int(_index_of(events, BattleEvents.PASSIVE_TRIGGERED)).is_less(_index_of(events, BattleEvents.FIELD_REMOVED))
	# Only while on the field.
	var benched := FixtureDB.engine(db, [_make("tank", ""), _make("tank", "regen")], [_make("tank", "")])
	events = benched.resolve_round([BattleAction.pass_turn(_first(benched, 0).bid),
		BattleAction.pass_turn(_first(benched, 1).bid)])
	assert_array(_triggered(events)).is_empty()


func test_knockout_and_faint_triggers() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "closer")], [_make("blob", "trail"), _make("blob", "")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	foe.creature.hp = 1
	var events := e.resolve_round([BattleAction.use_move(me.bid, "hit", foe.bid), BattleAction.pass_turn(foe.bid)])
	var fired := _triggered(events).map(func(ev): return ev.bid)
	assert_array(fired).contains_exactly_in_any_order([me.bid, foe.bid])
	assert_int(_index_of(events, BattleEvents.FAINT)).is_less(_index_of(events, BattleEvents.PASSIVE_TRIGGERED))
	# Faint: side ops are relative to the fainted creature, so its enemy side is scorched.
	assert_bool(e.sides[0].field.has("scorched")).is_true()
	assert_bool(e.sides[1].field.has("scorched")).is_false()
	# Knockout: defaults to the creature itself.
	assert_int(me.stages.spd).is_equal(1)


func test_triggered_effects_do_not_chain() -> void:
	# The foe's thorns knock the attacker out. The attacker's own hit, faint and
	# knockout triggers, and the foe's knockout trigger, must all stay quiet.
	var e := FixtureDB.engine(db, [_make("blob", "thorns"), _make("blob", "")], [_make("tank", "thorns")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	me.creature.hp = 1
	var events := e.resolve_round([BattleAction.use_move(me.bid, "hit", foe.bid), BattleAction.pass_turn(foe.bid)])
	var fired := _triggered(events)
	assert_int(fired.size()).is_equal(1)
	assert_int(fired[0].bid).is_equal(foe.bid)
	assert_bool(me.fainted).is_true()
	assert_bool(e.sides[0].field.has("scorched") or e.sides[1].field.has("scorched")).is_false()
	assert_int(foe.stages.spd).is_equal(0)


func test_no_triggers_after_battle_over() -> void:
	# The last foe faints: the battle is decided, so neither its faint trigger nor the
	# knockout trigger fires.
	var e := FixtureDB.engine(db, [_make("blob", "closer")], [_make("blob", "trail")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	foe.creature.hp = 1
	var events := e.resolve_round([BattleAction.use_move(me.bid, "hit", foe.bid), BattleAction.pass_turn(foe.bid)])
	assert_bool(e.is_over()).is_true()
	assert_array(_triggered(events)).is_empty()
	assert_bool(e.sides[0].field.has("scorched")).is_false()
	assert_int(me.stages.spd).is_equal(0)
	# Nothing fires once the battle is over, or for a fainted creature.
	var over := FixtureDB.engine(db, [_make("tank", "regen")], [_make("blob", "")])
	over.finish(0, "defeat")
	over.passive_rules.fire(_first(over, 0), "round_end")
	assert_array(_triggered(over._take_events())).is_empty()
	var down := FixtureDB.engine(db, [_make("tank", "regen")], [_make("blob", ""), _make("blob", "")])
	var b := _first(down, 0)
	b.creature.hp = 0
	down.passive_rules.fire(b, "round_end")
	assert_array(_triggered(down._take_events())).is_empty()


# An entry trigger can set off a reaction that knocks creatures out (Undertow's soak onto a
# Charged side sets off Conduction). Those faints are handled at once, not next round.

func test_enter_on_replace_knockouts_are_checked_at_once() -> void:
	for foe_bench in [false, true]:
		var foes: Array = [_make("blob", "")]
		if foe_bench:
			foes.append(_make("blob", ""))
		var e := FixtureDB.engine(db, [_make("blob", ""), _make("blob", "soaker")], foes)
		var foe := _first(e, 1)
		_first(e, 0).creature.hp = 0
		e.check_faints()
		e.sides[1].field.add("charged", 1, 3, 3)
		foe.creature.hp = 1
		var events := e.replace(0, e.sides[0].battlers[1].bid)
		assert_int(FixtureDB.events_of(events, BattleEvents.REACTION).size()).is_equal(1)
		var faints := FixtureDB.events_of(events, BattleEvents.FAINT)
		assert_int(faints.size()).is_equal(1)
		assert_int(faints[0].bid).is_equal(foe.bid)
		assert_bool(foe.active).is_false()
		# The last foe going down ends the battle right there.
		assert_bool(e.is_over()).is_equal(not foe_bench)
		assert_int(FixtureDB.events_of(events, BattleEvents.BATTLE_END).size()).is_equal(0 if foe_bench else 1)


func test_enter_on_auto_replace_knockouts_are_checked_at_once() -> void:
	# Side 1 refills on its own; its soaker lands on side 0's Charged field and knocks
	# side 0's lead out, so side 0 must be asked for a replacement this same round.
	var setup := BattleSetup.new()
	setup.add_side([_make("blob", ""), _make("blob", "")], 1, 1)
	setup.add_side([_make("blob", ""), _make("blob", "soaker")], 1, 1, {}, "", true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var e := BattleEngine.new(db, rng, setup)
	e.start()
	var me := _first(e, 0)
	var foe := _first(e, 1)
	foe.creature.hp = 1
	me.creature.hp = 1
	e.sides[0].field.add("charged", 1, 3, 3)
	var events := e.resolve_round([BattleAction.use_move(me.bid, "hit", foe.bid), BattleAction.pass_turn(foe.bid)])
	var faints := FixtureDB.events_of(events, BattleEvents.FAINT).map(func(ev): return ev.bid)
	assert_array(faints).contains_exactly([foe.bid, me.bid])
	assert_bool(me.active).is_false()
	var needed := FixtureDB.events_of(events, BattleEvents.REPLACEMENT_NEEDED)
	assert_int(needed.size()).is_equal(1)
	assert_int(needed[0].side).is_equal(0)
	assert_int(e.pending_replacements(0)).is_equal(1)


# --- Protection ---

## Every active battler passes, except `actions` (bid -> BattleAction).
func _round(e: BattleEngine, actions: Dictionary) -> Array:
	var chosen: Array = []
	for side in e.sides:
		for b in side.active():
			chosen.append(actions.get(b.bid, BattleAction.pass_turn(b.bid)))
	return e.resolve_round(chosen)


func test_status_immune_specific_and_all() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", ["burn_touch", "jolt"])], [_make("tank", "fireproof")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	var events := _round(e, {me.bid: BattleAction.use_move(me.bid, "burn_touch", foe.bid)})
	assert_str(foe.status()).is_equal("")
	assert_array(FixtureDB.events_of(events, BattleEvents.STATUS_APPLIED)).is_empty()
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(_triggered(events)[0].bid).is_equal(foe.bid)
	assert_str(_triggered(events)[0].passive).is_equal("fireproof")
	# Only the named status is blocked.
	_round(e, {me.bid: BattleAction.use_move(me.bid, "jolt", foe.bid)})
	assert_str(foe.status()).is_equal("shock")
	# No status named: every status is blocked.
	var all := FixtureDB.engine(db, [_make("blob", "", ["burn_touch", "jolt"])], [_make("tank", "pure")])
	me = _first(all, 0)
	foe = _first(all, 1)
	for move in ["burn_touch", "jolt"]:
		events = _round(all, {me.bid: BattleAction.use_move(me.bid, move, foe.bid)})
		assert_str(foe.status()).is_equal("")
		assert_int(_triggered(events).size()).is_equal(1)


func test_guard_stages_blocks_foe_drops_not_own() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", ["growl"])], [_make("tank", "sturdy_all")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	var events := _round(e, {me.bid: BattleAction.use_move(me.bid, "growl")})
	assert_int(foe.stages.patk).is_equal(0)
	assert_array(FixtureDB.events_of(events, BattleEvents.STAT_STAGE)).is_empty()
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(_triggered(events)[0].bid).is_equal(foe.bid)
	# Its own effects still lower it.
	e.shift_stage(foe, "patk", -1, foe)
	assert_int(foe.stages.patk).is_equal(-1)
	# A stat-specific guard covers only that stat.
	var grip := FixtureDB.engine(db, [_make("blob", "", ["growl"])], [_make("tank", "grip")])
	me = _first(grip, 0)
	foe = _first(grip, 1)
	_round(grip, {me.bid: BattleAction.use_move(me.bid, "growl")})
	assert_int(foe.stages.patk).is_equal(0)
	grip.shift_stage(foe, "spd", -1, me)
	assert_int(foe.stages.spd).is_equal(-1)


func test_field_shelter_ignores_state_and_reaction_damage() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", ["zap", "charge_up"]), _make("blob", "")],
		[_make("tank", "dry"), _make("tank", "")], 2, 2)
	var me := _first(e, 0)
	var dry := e.sides[1].active()[0]
	var wet := e.sides[1].active()[1]
	e.sides[1].field.add("soaked", 1, 3, 3)
	# The Soaked passive (Electric damage taken x1.5) skips the sheltered creature.
	assert_float(_dmg(e, me, "zap", wet) / _dmg(e, me, "zap", dry)).is_between(1.45, 1.55)
	# Charged meets Soaked: Conduction hits the side, but not the sheltered creature.
	var hp := dry.hp()
	var events := _round(e, {me.bid: BattleAction.use_move(me.bid, "charge_up")})
	assert_int(FixtureDB.events_of(events, BattleEvents.REACTION).size()).is_equal(1)
	var hit := FixtureDB.events_of(events, BattleEvents.DAMAGE).map(func(ev): return ev.bid)
	assert_array(hit).contains_exactly([wet.bid])
	assert_int(dry.hp()).is_equal(hp)
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(_triggered(events)[0].bid).is_equal(dry.bid)


# --- Game-specific ---

func test_field_boost_stacks_and_turns() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "booster", ["drench"])], [_make("tank", "")])
	var me := _first(e, 0)
	var events := _round(e, {me.bid: BattleAction.use_move(me.bid, "drench")})
	var applied := FixtureDB.events_of(events, BattleEvents.FIELD_APPLIED)
	assert_int(applied.size()).is_equal(1)
	assert_int(applied[0].stacks).is_equal(2)
	assert_int(applied[0].turns).is_equal(3 + 2)
	# Still capped at the state's max stacks.
	_round(e, {me.bid: BattleAction.use_move(me.bid, "drench")})
	assert_int(e.sides[1].field.stacks("soaked")).is_equal(3)
	# Without the passive: the move's own stacks and the state's default turns.
	var plain := FixtureDB.engine(db, [_make("blob", "", ["drench"])], [_make("tank", "")])
	me = _first(plain, 0)
	applied = FixtureDB.events_of(_round(plain, {me.bid: BattleAction.use_move(me.bid, "drench")}),
		BattleEvents.FIELD_APPLIED)
	assert_int(applied[0].stacks).is_equal(1)
	assert_int(applied[0].turns).is_equal(3)


func _reaction_damage(passive: String) -> int:
	var e := FixtureDB.engine(db, [_make("blob", passive, ["charge_up"])], [_make("tank", "")])
	var me := _first(e, 0)
	e.sides[1].field.add("soaked", 1, 3, 3)
	var events := _round(e, {me.bid: BattleAction.use_move(me.bid, "charge_up")})
	var dmg := FixtureDB.events_of(events, BattleEvents.DAMAGE)
	assert_int(dmg.size()).is_equal(1)
	return dmg[0].amount


func test_reaction_power() -> void:
	assert_float(float(_reaction_damage("sparker")) / _reaction_damage("")).is_between(1.9, 2.1)
	# Its own moves are not boosted.
	var boosted := FixtureDB.engine(db, [_make("blob", "sparker")], [_make("tank", "")])
	var plain := FixtureDB.engine(db, [_make("blob", "")], [_make("tank", "")])
	assert_float(_dmg(boosted, _first(boosted, 0), "hit", _first(boosted, 1))) \
		.is_equal(_dmg(plain, _first(plain, 0), "hit", _first(plain, 1)))


func test_energy_discount_never_negative() -> void:
	var e := FixtureDB.engine(db, [_make("tank", "saver", ["hit", "big_hit"])],
		[_make("tank", "", ["hit", "big_hit"])])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	var rules := e.passive_rules
	# hit costs 2: 2 - 5 is clamped to 0, never a refund.
	assert_int(rules.move_cost(me, db.move("hit"))).is_equal(0)
	assert_int(rules.move_cost(me, db.move("big_hit"))).is_equal(20)
	assert_int(rules.move_cost(me, db.move("scrap"))).is_equal(0)
	assert_int(rules.move_cost(foe, db.move("big_hit"))).is_equal(25)
	me.creature.energy = 20
	foe.creature.energy = 20
	# Affordability uses the discounted cost.
	assert_bool(e.usable_moves(me.bid).has("big_hit")).is_true()
	assert_bool(e.usable_moves(foe.bid).has("big_hit")).is_false()
	var events := _round(e, {me.bid: BattleAction.use_move(me.bid, "hit", foe.bid),
		foe.bid: BattleAction.use_move(foe.bid, "hit", me.bid)})
	assert_int(me.energy()).is_equal(20)
	assert_int(foe.energy()).is_equal(18)
	assert_array(FixtureDB.events_of(events, BattleEvents.ENERGY).filter(func(ev): return ev.bid == me.bid)).is_empty()
	events = _round(e, {me.bid: BattleAction.use_move(me.bid, "big_hit", foe.bid)})
	assert_array(FixtureDB.events_of(events, BattleEvents.ACTION_INVALID)).is_empty()
	assert_int(me.energy()).is_equal(0)
	# A typed discount covers only its type.
	var z := FixtureDB.engine(db, [_make("tank", "zap_saver", ["zap", "hit"])], [_make("tank", "")])
	assert_int(z.passive_rules.move_cost(_first(z, 0), db.move("zap"))).is_equal(1)
	assert_int(z.passive_rules.move_cost(_first(z, 0), db.move("hit"))).is_equal(2)


func test_rest_bonus() -> void:
	var e := FixtureDB.engine(db, [_make("tank", "rester")], [_make("tank", "")])
	var me := _first(e, 0)
	var foe := _first(e, 1)
	me.creature.energy = 0
	foe.creature.energy = 0
	_round(e, {me.bid: BattleAction.rest(me.bid), foe.bid: BattleAction.rest(foe.bid)})
	var max_e := me.creature.max_energy(db)
	assert_int(me.energy()).is_equal(roundi(max_e * 0.5))
	assert_int(foe.energy()).is_equal(roundi(max_e * 0.25))


func test_scrap_power() -> void:
	var boosted := FixtureDB.engine(db, [_make("blob", "scrapper")], [_make("tank", "")])
	var plain := FixtureDB.engine(db, [_make("blob", "")], [_make("tank", "")])
	var ratio := _dmg(boosted, _first(boosted, 0), "scrap", _first(boosted, 1)) \
		/ _dmg(plain, _first(plain, 0), "scrap", _first(plain, 1))
	assert_float(ratio).is_between(1.9, 2.1)
	assert_float(_dmg(boosted, _first(boosted, 0), "hit", _first(boosted, 1))) \
		.is_equal(_dmg(plain, _first(plain, 0), "hit", _first(plain, 1)))


func test_aura_protection_applies_to_ally() -> void:
	var e := FixtureDB.engine(db, [_make("blob", "", ["burn_touch", "growl"]), _make("blob", "")],
		[_make("tank", "ward_aura"), _make("tank", "")], 2, 2)
	var me := _first(e, 0)
	var holder := e.sides[1].active()[0]
	var ally := e.sides[1].active()[1]
	var events := _round(e, {me.bid: BattleAction.use_move(me.bid, "burn_touch", ally.bid)})
	assert_str(ally.status()).is_equal("")
	# Shown as the aura holder's passive.
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(_triggered(events)[0].bid).is_equal(holder.bid)
	assert_str(_triggered(events)[0].passive).is_equal("ward_aura")
	events = _round(e, {me.bid: BattleAction.use_move(me.bid, "growl")})
	assert_int(holder.stages.patk).is_equal(0)
	assert_int(ally.stages.patk).is_equal(0)
	assert_int(_triggered(events).size()).is_equal(2)
	# The aura covers its own side only.
	e.shift_stage(me, "patk", -1, holder)
	assert_int(me.stages.patk).is_equal(-1)


# --- Passive-sourced effects earn no Affinity ---

func _catalyst(e: BattleEngine, b: Battler) -> int:
	return int(e.rewards.affinity_log.get(b.bid, {}).get("catalyst", 0))


func _warden(e: BattleEngine, b: Battler) -> int:
	return int(e.rewards.affinity_log.get(b.bid, {}).get("warden", 0))


func test_enter_trigger_earns_no_affinity() -> void:
	var c := _make("slow", "soaker")
	var before := int(c.affinity.catalyst)
	var e := _unstarted([c], [_make("tank", "")])
	e.start()
	assert_bool(e.sides[1].field.has("soaked")).is_true()
	assert_int(_catalyst(e, _first(e, 0))).is_equal(0)
	assert_int(int(c.affinity.catalyst)).is_equal(before)


func test_round_end_heal_trigger_earns_no_affinity() -> void:
	var e := FixtureDB.engine(db, [_make("tank", "regen")], [_make("tank", "")])
	var me := _first(e, 0)
	me.creature.hp = me.creature.max_hp(db) / 2
	var before := int(me.creature.affinity.warden)
	var events := _round(e, {})
	assert_int(FixtureDB.events_of(events, BattleEvents.HEAL)[0].amount).is_greater(0)
	assert_int(_warden(e, me)).is_equal(0)
	assert_int(int(me.creature.affinity.warden)).is_equal(before)


func test_trigger_reaction_earns_no_affinity() -> void:
	var e := FixtureDB.engine(db, [_make("blob", ""), _make("blob", "soaker")], [_make("tank", "")])
	e.sides[1].field.add("charged", 1, 3, 3)
	var bench := e.sides[0].battlers[1]
	var events := e.resolve_round([BattleAction.swap(_first(e, 0).bid, bench.bid),
		BattleAction.pass_turn(_first(e, 1).bid)])
	assert_int(FixtureDB.events_of(events, BattleEvents.REACTION).size()).is_equal(1)
	assert_bool(e.rewards.affinity_log.is_empty()).is_true()


func test_chosen_moves_still_earn_affinity() -> void:
	# Regression: moves the player picks are credited exactly as before.
	var e := FixtureDB.engine(db, [_make("blob", "", ["drench", "mend", "charge_up"])], [_make("tank", "")])
	var me := _first(e, 0)
	_round(e, {me.bid: BattleAction.use_move(me.bid, "drench")})
	assert_int(_catalyst(e, me)).is_equal(2)
	me.creature.hp = me.creature.max_hp(db) / 4
	_round(e, {me.bid: BattleAction.use_move(me.bid, "mend")})
	assert_int(_warden(e, me)).is_equal(2)
	var events := _round(e, {me.bid: BattleAction.use_move(me.bid, "charge_up")})
	assert_int(FixtureDB.events_of(events, BattleEvents.REACTION).size()).is_equal(1)
	# Conduction uses up the incoming Charged, so only the reaction is credited.
	assert_int(_catalyst(e, me)).is_equal(2 + 4)


# --- Triggers that would do nothing stay quiet ---

func test_full_hp_heal_trigger_is_skipped() -> void:
	var e := FixtureDB.engine(db, [_make("tank", "regen")], [_make("tank", "")])
	var me := _first(e, 0)
	assert_int(me.hp()).is_equal(me.creature.max_hp(db))
	var events := _round(e, {})
	assert_array(_triggered(events)).is_empty()
	assert_array(FixtureDB.events_of(events, BattleEvents.HEAL)).is_empty()


func test_damaged_heal_trigger_fires_then_heals() -> void:
	var e := FixtureDB.engine(db, [_make("tank", "regen")], [_make("tank", "")])
	var me := _first(e, 0)
	me.creature.hp = me.creature.max_hp(db) - 1
	var events := _round(e, {})
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(FixtureDB.events_of(events, BattleEvents.HEAL).size()).is_equal(1)
	assert_int(_index_of(events, BattleEvents.PASSIVE_TRIGGERED)).is_less(_index_of(events, BattleEvents.HEAL))


func test_full_energy_restore_trigger_is_skipped() -> void:
	var e := FixtureDB.engine(db, [_make("tank", "recharge")], [_make("tank", "")])
	var me := _first(e, 0)
	me.creature.energy = me.creature.max_energy(db)
	var events := _round(e, {})
	assert_array(_triggered(events)).is_empty()


func test_trigger_with_some_real_effect_still_fires() -> void:
	var e := FixtureDB.engine(db, [_make("tank", "regen_rush")], [_make("tank", "")])
	var me := _first(e, 0)
	assert_int(me.hp()).is_equal(me.creature.max_hp(db))
	var events := _round(e, {})
	assert_int(_triggered(events).size()).is_equal(1)
	assert_int(me.stages.spd).is_equal(1)
