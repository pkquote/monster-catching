extends GdUnitTestSuite
## Passives, held items and Underdog in 2v2, 3v3 and uneven formats: auras cover every ally and
## no foe, a consumed item is used up once per holder, a per_battle item fires once per battle
## across swaps, absorb on one target of a spread move spares only that target, and Underdog's
## bonuses scale with the ratio and vanish at even sizes.

var db: Database


func before() -> void:
	var r: RawData = FixtureDB.raw()
	r.add_entry("moves", FixtureDB.move("twin_splash", "water", "special", 40, 100, "two_enemies", [{"op": "damage"}]))
	r.add_entry("moves", FixtureDB.move("surge", "water", "special", 150, 100, "all_enemies", [{"op": "damage"}]))
	# Huge special attack, so damage estimates are in the thousands and integer rounding vanishes.
	r.add_entry("creatures", FixtureDB._c("cannon", ["neutral"], FixtureDB.stats({"satk": 255}),
		[{"level": 1, "move": "hit"}]))
	for p: Dictionary in [
		{"id": "rally_aura", "scope": "allies", "effects": [{"op": "stat_mod", "stat": "patk", "mult": 1.5}]},
		{"id": "sponge", "effects": [{"op": "absorb_type", "type": "water", "fraction": 0.25}]},
	]:
		p.merge({"name": str(p.id).capitalize(), "description": "Test passive."})
		r.add_entry("passives", p)
	for it: Dictionary in [
		{"id": "aura_charm", "held": {"scope": "allies", "effects": [{"op": "incoming_type_mod", "mult": 0.5}]}},
		{"id": "berry", "held": {"use": "consumed", "triggers": [{"on": "hit", "when": {"hp_below": 0.5},
			"effects": [{"op": "heal", "fraction": 0.5, "target": "self"}]}]}},
		{"id": "round_berry", "held": {"use": "consumed", "triggers": [{"on": "round_end",
			"effects": [{"op": "heal", "fraction": 0.25}]}]}},
		{"id": "spiky", "held": {"use": "per_battle", "triggers": [{"on": "hit",
			"effects": [{"op": "stat_stage", "stat": "patk", "stages": -1}]}]}},
	]:
		it.merge({"name": str(it.id).capitalize(), "description": "Test held item.", "category": "held", "price": 10})
		r.add_entry("items", it)
	var errors: Array = DataValidator.validate(r)
	assert(errors.is_empty(), "Test data invalid:\n" + "\n".join(errors))
	db = Database.from_raw(r)


func _make(species: String, passive: String = "", held: String = "", moves: Array = ["hit"],
		level: int = 50) -> CreatureInstance:
	var c: CreatureInstance = FixtureDB.make(db, species, level, moves)
	# "" = no passive at all (not the fixture species' harmless "steady"), so effect lists are exact.
	c.passive = passive
	c.held_item = held
	return c


func _plain(n: int, species: String = "tank", moves: Array = ["hit"]) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(_make(species, "", "", moves))
	return out


## Every active creature passes unless `actions` (bid -> BattleAction) says otherwise.
func _round(e: BattleEngine, actions: Dictionary) -> Array:
	var chosen: Array = []
	for side: BattleSide in e.sides:
		for b: Battler in side.active():
			chosen.append(actions.get(b.bid, BattleAction.pass_turn(b.bid)))
	return e.resolve_round(chosen)


func _of(events: Array, type: String, bid: int) -> Array:
	return FixtureDB.events_of(events, type).filter(func(ev: Dictionary) -> bool: return int(ev.bid) == bid)


func _patk_mult(e: BattleEngine, b: Battler) -> float:
	return BattleMath.effective_stat(e, b, "patk") / float(b.creature.stat(db, "patk"))


func _dmg(e: BattleEngine, user: Battler, move: String, target: Battler, count: int = 1) -> float:
	return BattleAI.estimate_damage(e, user, db.move(move), target, count)


func _hurt(b: Battler, fraction: float = 0.25) -> void:
	b.creature.hp = int(b.creature.max_hp(db) * fraction)


# --- Auras -----------------------------------------------------------------------------------

func test_passive_aura_helps_every_ally_but_no_foe_in_2v2_and_3v3() -> void:
	for n: int in [2, 3]:
		var party: Array = _plain(n)
		party[n - 1] = _make("tank", "rally_aura")
		var e: BattleEngine = FixtureDB.engine(db, party, _plain(n), n, n)
		assert_int(e.sides[0].active().size()).is_equal(n)
		for ally: Battler in e.sides[0].active():
			assert_float(_patk_mult(e, ally)).override_failure_message("%dv%d ally %d" % [n, n, ally.bid]) \
				.is_equal_approx(1.5, 0.0001)
		for foe: Battler in e.sides[1].active():
			assert_float(_patk_mult(e, foe)).override_failure_message("%dv%d foe %d" % [n, n, foe.bid]) \
				.is_equal_approx(1.0, 0.0001)
			assert_array(e.passive_rules.effects_for(foe)).is_empty()
		# The holder goes down: nobody keeps the aura (the side is now outnumbered, so only the
		# Underdog stat bonus is left).
		var holder: Battler = e.sides[0].active()[n - 1]
		FixtureDB.knock_out(e, [holder])
		var bonus: float = float(e.sides[0].underdog.get("stat_bonus", 0.0))
		assert_float(bonus).is_greater(0.0)
		assert_array(e.sides[0].active()).has_size(n - 1)
		for ally: Battler in e.sides[0].active():
			assert_float(_patk_mult(e, ally)).is_equal_approx(1.0 + bonus, 0.0001)
			assert_array(e.passive_rules.effects_for(ally).filter(
				func(eff: Dictionary) -> bool: return eff.op == "stat_mod" and float(eff.mult) == 1.5)).is_empty()


func test_held_aura_shields_every_ally_but_no_foe_in_2v2_and_3v3() -> void:
	for n: int in [2, 3]:
		var plain: BattleEngine = FixtureDB.engine(db, _plain(n), _plain(n), n, n)
		var party: Array = _plain(n)
		party[0] = _make("tank", "", "aura_charm")
		var e: BattleEngine = FixtureDB.engine(db, party, _plain(n), n, n)
		var attacker: Battler = e.sides[1].active()[0]
		var plain_attacker: Battler = plain.sides[1].active()[0]
		for i: int in n:
			var shielded: float = _dmg(e, attacker, "hit", e.sides[0].active()[i])
			var base: float = _dmg(plain, plain_attacker, "hit", plain.sides[0].active()[i])
			assert_float(base).is_greater(0.0)
			assert_float(shielded / base).override_failure_message("%dv%d ally slot %d" % [n, n, i]) \
				.is_equal_approx(0.5, 0.05)
		# Foes take full damage from the holder's side.
		for i: int in n:
			assert_float(_dmg(e, e.sides[0].active()[0], "hit", e.sides[1].active()[i])) \
				.is_equal(_dmg(plain, plain.sides[0].active()[0], "hit", plain.sides[1].active()[i]))
			assert_array(e.passive_rules.effects_for(e.sides[1].active()[i])).is_empty()


# --- Consumed and per_battle items -------------------------------------------------------------

func test_consumed_item_is_used_once_per_holder_when_both_trigger_in_one_round() -> void:
	# 2v2: one spread move hits both berry holders (both below half HP) in the same round.
	var holders: Array = [_make("tank", "", "berry"), _make("tank", "", "berry")]
	var e: BattleEngine = FixtureDB.engine(db, [_make("blob", "", "", ["wave"]), _make("blob")], holders, 2, 2)
	var user: Battler = e.sides[0].active()[0]
	var a: Battler = e.sides[1].active()[0]
	var b: Battler = e.sides[1].active()[1]
	_hurt(a)
	_hurt(b)
	var events: Array = _round(e, {user.bid: BattleAction.use_move(user.bid, "wave")})
	var consumed: Array = FixtureDB.events_of(events, BattleEvents.ITEM_CONSUMED)
	assert_array(consumed).has_size(2)
	assert_array(consumed.map(func(ev: Dictionary) -> int: return int(ev.bid))).contains_exactly_in_any_order([a.bid, b.bid])
	for holder: Battler in [a, b]:
		assert_array(_of(events, BattleEvents.ITEM_CONSUMED, holder.bid)).has_size(1)
		assert_array(_of(events, BattleEvents.HEAL, holder.bid)).has_size(1)
		assert_str(holder.creature.held_item).is_equal("")
	# Hurt again and hit again: nothing left to use.
	_hurt(a)
	_hurt(b)
	var again: Array = _round(e, {user.bid: BattleAction.use_move(user.bid, "wave")})
	assert_array(FixtureDB.events_of(again, BattleEvents.ITEM_CONSUMED)).is_empty()
	assert_array(FixtureDB.events_of(again, BattleEvents.PASSIVE_TRIGGERED)).is_empty()
	assert_array(FixtureDB.events_of(again, BattleEvents.HEAL)).is_empty()
	e.commit(1)
	assert_str(holders[0].held_item).is_equal("")
	assert_str(holders[1].held_item).is_equal("")


func test_consumed_round_end_items_on_two_of_three_allies() -> void:
	var party: Array = [_make("tank", "", "round_berry"), _make("tank"), _make("tank", "", "round_berry")]
	var e: BattleEngine = FixtureDB.engine(db, party, _plain(3), 3, 3)
	var side: Array[Battler] = e.sides[0].active()
	for b: Battler in side:
		_hurt(b)
	var hurt_hp: int = side[1].hp()
	var events: Array = _round(e, {})
	assert_array(FixtureDB.events_of(events, BattleEvents.ITEM_CONSUMED)).has_size(2)
	assert_array(_of(events, BattleEvents.ITEM_CONSUMED, side[0].bid)).has_size(1)
	assert_array(_of(events, BattleEvents.ITEM_CONSUMED, side[2].bid)).has_size(1)
	assert_array(_of(events, BattleEvents.HEAL, side[1].bid)).is_empty()
	assert_int(side[1].hp()).is_equal(hurt_hp)
	assert_str(side[0].creature.held_item).is_equal("")
	assert_str(side[2].creature.held_item).is_equal("")
	assert_array(FixtureDB.events_of(_round(e, {}), BattleEvents.ITEM_CONSUMED)).is_empty()


func test_per_battle_item_fires_once_per_battle_across_swaps() -> void:
	var first: CreatureInstance = _make("tank", "", "spiky")
	var second: CreatureInstance = _make("tank", "", "spiky")
	var e: BattleEngine = FixtureDB.engine(db, [_make("blob")], [first, second])
	var me: Battler = e.sides[0].active()[0]
	var a: Battler = e.sides[1].battlers[0]
	var b: Battler = e.sides[1].battlers[1]
	# Round 1: a is hit and fires.
	var ev: Array = _round(e, {me.bid: BattleAction.use_move(me.bid, "hit", a.bid)})
	assert_array(_of(ev, BattleEvents.PASSIVE_TRIGGERED, a.bid)).has_size(1)
	assert_int(int(me.stages.patk)).is_equal(-1)
	# Round 2: a swaps out for b (swap goes first), the hit lands on b, b fires its own item once.
	ev = _round(e, {me.bid: BattleAction.use_move(me.bid, "hit", a.bid), a.bid: BattleAction.swap(a.bid, b.bid)})
	assert_array(_of(ev, BattleEvents.SEND_OUT, b.bid)).has_size(1)
	assert_array(_of(ev, BattleEvents.DAMAGE, b.bid)).has_size(1)
	assert_array(_of(ev, BattleEvents.PASSIVE_TRIGGERED, b.bid)).has_size(1)
	assert_int(int(me.stages.patk)).is_equal(-2)
	# Rounds 3 and 4: each comes back in and is hit again; neither fires a second time.
	for pair: Array in [[b, a], [a, b]]:
		var out: Battler = pair[0]
		var into: Battler = pair[1]
		ev = _round(e, {me.bid: BattleAction.use_move(me.bid, "hit", into.bid), out.bid: BattleAction.swap(out.bid, into.bid)})
		assert_array(_of(ev, BattleEvents.SEND_OUT, into.bid)).has_size(1)
		assert_array(_of(ev, BattleEvents.DAMAGE, into.bid)).has_size(1)
		assert_array(FixtureDB.events_of(ev, BattleEvents.PASSIVE_TRIGGERED)).is_empty()
	assert_int(int(me.stages.patk)).is_equal(-2)
	for holder: Battler in [a, b]:
		assert_bool(holder.held_spent).is_true()
		assert_str(holder.creature.held_item).is_equal("spiky")
	assert_array(FixtureDB.events_of(ev, BattleEvents.ITEM_CONSUMED)).is_empty()
	e.commit(1)
	assert_str(first.held_item).is_equal("spiky")
	assert_str(second.held_item).is_equal("spiky")


# --- Absorb on one target of a multi-target move -------------------------------------------------

## Runs `move` from side 0's first creature at side 1 with the absorber (sponge) in side-1 slot 0
## (or a plain twin in the mirror battle), both targets at half HP. Returns the round's events.
func _absorb_case(n: int, move: String, sponge: bool, picks: Array) -> Dictionary:
	var foes: Array = _plain(n)
	if sponge:
		foes[0] = _make("tank", "sponge")
	var e: BattleEngine = FixtureDB.engine(db, [_make("blob", "", "", [move])] + _plain(n - 1, "blob"), foes, n, n, 7)
	for t: Battler in e.sides[1].active():
		_hurt(t, 0.5)
	var user: Battler = e.sides[0].active()[0]
	var targets: Array[Battler] = e.sides[1].active()
	var first: int = targets[int(picks[0])].bid if picks.size() > 0 else -1
	var second: int = targets[int(picks[1])].bid if picks.size() > 1 else -1
	var hit_count: int = picks.size() if picks.size() > 0 else n
	var estimate: float = _dmg(e, user, move, targets[1], hit_count)
	var events: Array = _round(e, {user.bid: BattleAction.use_move(user.bid, move, first, second)})
	return {"engine": e, "events": events, "targets": targets, "estimate": estimate, "user": user}


func test_absorb_spares_only_the_absorber_of_a_spread_or_two_target_move() -> void:
	# [format size, move, picks]: wave hits every foe; twin_splash hits the two picked.
	for case: Array in [[2, "wave", []], [3, "wave", []], [2, "twin_splash", [0, 1]], [3, "twin_splash", [0, 1]]]:
		var n: int = case[0]
		var move: String = case[1]
		var tag: String = "%dv%d %s" % [n, n, move]
		var got: Dictionary = _absorb_case(n, move, true, case[2])
		var mirror: Dictionary = _absorb_case(n, move, false, case[2])
		var events: Array = got.events
		var absorber: Battler = got.targets[0]
		var other: Battler = got.targets[1]
		# The absorber heals a quarter of max HP instead of taking damage, and says so.
		assert_array(_of(events, BattleEvents.DAMAGE, absorber.bid)).override_failure_message(tag).is_empty()
		var healed: Array = _of(events, BattleEvents.HEAL, absorber.bid)
		assert_array(healed).override_failure_message(tag).has_size(1)
		assert_int(int(healed[0].amount)).is_equal(roundi(absorber.creature.max_hp(db) * 0.25))
		assert_array(_of(events, BattleEvents.PASSIVE_TRIGGERED, absorber.bid)).has_size(1)
		# The other target takes exactly what it takes when nobody absorbs: still a spread hit.
		var dealt: Array = _of(events, BattleEvents.DAMAGE, other.bid)
		var mirror_dealt: Array = _of(mirror.events, BattleEvents.DAMAGE, (mirror.targets[1] as Battler).bid)
		assert_array(dealt).override_failure_message(tag).has_size(1)
		assert_int(int(dealt[0].amount)).override_failure_message(tag).is_equal(int(mirror_dealt[0].amount))
		# At most the reduced damage at the top roll (the estimate uses the average roll 0.925).
		assert_float(float(dealt[0].amount)).override_failure_message(tag) \
			.is_less_equal((float(got.estimate) + 1.0) / BattleMath.ROLL_AVG)
		var single: float = _dmg(mirror.engine, mirror.user, move, mirror.targets[1], 1)
		var expected_count: int = n if move == "wave" else 2
		assert_float(float(got.estimate) / single).is_equal_approx(float(db.balance.spread_mult_for(expected_count)), 0.06)
		# A third foe outside a two-target move is untouched.
		if n == 3 and move == "twin_splash":
			var third: Battler = got.targets[2]
			assert_array(_of(events, BattleEvents.DAMAGE, third.bid)).is_empty()
			assert_int(third.hp()).is_equal(int(third.creature.max_hp(db) * 0.5))


# --- Underdog across formats ------------------------------------------------------------------

## [ally field, enemy field, bonus actions, stat bonus, spread reduction] with the fixture balance
## (bonus_actions_per_ratio 1.0, stat_bonus_per_ratio 0.15 cap 0.4, spread_reduction_per_ratio 0.2 cap 0.5).
const UNDERDOG_CASES: Array = [
	[1, 2, 1, 0.15, 0.2],
	[1, 3, 2, 0.3, 0.4],
	[2, 3, 0, 0.075, 0.1],
	[1, 1, 0, 0.0, 0.0],
	[2, 2, 0, 0.0, 0.0],
	[3, 3, 0, 0.0, 0.0],
]


func test_underdog_bonuses_scale_with_the_ratio_and_vanish_at_even_sizes() -> void:
	for case: Array in UNDERDOG_CASES:
		var mine: int = case[0]
		var theirs: int = case[1]
		var extra: int = case[2]
		var stat_bonus: float = case[3]
		var reduction: float = case[4]
		var tag: String = "%dv%d" % [mine, theirs]
		var e: BattleEngine = FixtureDB.engine(db, _plain(mine, "shell"), _plain(theirs, "cannon", ["surge"]),
			mine, theirs)
		var under: Dictionary = e.sides[0].underdog
		assert_int(int(under.get("bonus_actions", 0))).override_failure_message(tag).is_equal(extra)
		assert_float(float(under.get("stat_bonus", 0.0))).override_failure_message(tag).is_equal_approx(stat_bonus, 0.0001)
		assert_float(float(under.get("spread_reduction", 0.0))).override_failure_message(tag).is_equal_approx(reduction, 0.0001)
		# The larger side never gets anything.
		assert_float(float(e.sides[1].underdog.get("stat_bonus", 0.0))).is_equal(0.0)
		assert_int(int(e.sides[1].underdog.get("bonus_actions", 0))).is_equal(0)
		# Stat bonus: P/S Atk and Def scale, Speed does not.
		for b: Battler in e.sides[0].active():
			for stat: String in ["patk", "pdef", "satk", "sdef"]:
				assert_float(BattleMath.effective_stat(e, b, stat) / float(b.creature.stat(db, stat))) \
					.override_failure_message("%s %s" % [tag, stat]).is_equal_approx(1.0 + stat_bonus, 0.0001)
			assert_float(BattleMath.effective_stat(e, b, "spd")).is_equal(float(b.creature.stat(db, "spd")))
		for b: Battler in e.sides[1].active():
			assert_float(BattleMath.effective_stat(e, b, "patk")).is_equal(float(b.creature.stat(db, "patk")))
		# Spread reduction: a spread hit on the smaller side is cut on top of the spread multiplier.
		var foe: Battler = e.sides[1].active()[0]
		var target: Battler = e.sides[0].active()[0]
		var single: float = _dmg(e, foe, "surge", target, 1)
		for count: int in [2, 3]:
			var expected: float = db.balance.spread_mult_for(count) * (1.0 - reduction)
			assert_float(_dmg(e, foe, "surge", target, count) / single) \
				.override_failure_message("%s spread %d" % [tag, count]).is_equal_approx(expected, 0.002)
		# Extra actions: every slot of every creature on the smaller side really acts.
		var needed: Array[int] = e.actions_needed(0)
		assert_array(needed).override_failure_message(tag).has_size(mine * (1 + extra))
		var chosen: Array = []
		for bid: int in needed:
			chosen.append(BattleAction.use_move(bid, "hit", -1))
		for b: Battler in e.sides[1].active():
			chosen.append(BattleAction.pass_turn(b.bid))
		var events: Array = e.resolve_round(chosen)
		assert_array(FixtureDB.events_of(events, BattleEvents.ACTION_INVALID)).override_failure_message(tag).is_empty()
		for b: Battler in e.sides[0].active():
			assert_array(_of(events, BattleEvents.MOVE_USED, b.bid)).override_failure_message(tag).has_size(1 + extra)


func test_underdog_event_only_for_uneven_starts() -> void:
	for case: Array in UNDERDOG_CASES:
		var mine: int = case[0]
		var theirs: int = case[1]
		var setup: BattleSetup = BattleSetup.new()
		setup.add_side(_plain(mine), maxi(mine, theirs), mine)
		setup.add_side(_plain(theirs), maxi(mine, theirs), theirs)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 1
		var events: Array = BattleEngine.new(db, rng, setup).start()
		var announced: Array = FixtureDB.events_of(events, BattleEvents.UNDERDOG)
		if mine == theirs:
			assert_array(announced).override_failure_message("%dv%d" % [mine, theirs]).is_empty()
		else:
			assert_array(announced).has_size(1)
			assert_int(int(announced[0].side)).is_equal(0)
			assert_float(float(announced[0].ratio)).is_equal_approx(float(theirs) / float(mine), 0.0001)
			assert_int(int(announced[0].bonus_actions)).is_equal(int(case[2]))
