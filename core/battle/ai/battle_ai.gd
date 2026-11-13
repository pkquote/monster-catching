class_name BattleAI
extends RefCounted
## Chooses actions for AI-controlled sides. Styles (from tamer data):
##   basic      : random usable move and target
##   aggressive : most expected damage, favouring knockouts
##   tactician  : aggressive scoring plus the expected payoff of field setup,
##                reactions, statuses and debuffs
##
## Scores are in HP-equivalent units. Non-damage effects are valued as multiples
## of `ref`, the creature's best available single-target damage, so setup and
## attacking stay comparable at every level.

const KO_BONUS := 30.0
## Stat-drop value per stage per foe, x ref. Speed and accuracy matter less than offense/defense.
const DEBUFF_VALUE := {"patk": 0.2, "satk": 0.2, "pdef": 0.2, "sdef": 0.2, "spd": 0.08, "acc": 0.12,
	"resolve": 0.05, "luck": 0.0}
## Rounds a status is assumed to matter for (battles are short).
const STATUS_HORIZON := 4
const NEW_STATE := 0.15  # x ref, a hostile state's passive value on its own
const RESTACK := 0.05  # x ref
const FOLLOW_CASH_IN := 0.3  # x ref, the team knows a move that cashes the state in
const OWN_BUFF := 0.35  # x ref, a helpful state placed on its own side
const REPLACE := 0.2  # x ref, knocking out the state the side already holds (the cap pushes out the oldest)
## A setup that enables a reaction next turn is worth this share of that reaction's value.
const FOLLOW_DISCOUNT := 0.6
## Below this share of max energy, Rest becomes an option worth REST_VALUE.
const LOW_ENERGY := 0.2
const REST_VALUE := 6.0
## x ref per full energy bar restored by a trigger.
const ENERGY_VALUE := 0.25
## Aggressive trusts HP, not setup: trigger effects paid in stages, statuses, energy or field states count this much.
const AGGRESSIVE_SETUP_MULT := 0.5  # reference value: the data (data/ai_styles.json) is authoritative, a test pins them equal
## A swap's offence term counts the bench creature's damage edge over this many rounds (it acts from next round).
const OFFENCE_ROUNDS := 1.0
## A swap must beat the best non-swap option by this much, x ref, so near-ties stay with the move.
const SWAP_MARGIN := 0.25  # reference value for tactician, as above
## HP-equivalent score range of an attack for an `attack: weakest` style: the weakest hit scores BAND, the strongest
## half of it, so every attack still beats a pointless move worth 0 but loses to anything worth more than the band.
const WEAK_ATTACK_BAND := 0.5


## The style's weights (an `ai_styles` entry). An unknown id is a programming error: data validation keeps tamers
## to known ids, and the simulator rejects an unknown name.
static func profile(engine: BattleEngine, style: String) -> AiStyleDef:
	var p := engine.db.ai_style(style)
	assert(p != null, "Unknown AI style '%s'" % style)
	return p


static func choose_all(engine: BattleEngine, side_index: int) -> Array:
	var style := engine.sides[side_index].ai
	var out: Array = []
	var claimed: Array[int] = []  # bench creatures already taken by a swap this round
	var swapped: Array[int] = []  # a swap is the creature's whole turn: it takes no further actions
	for bid in engine.actions_needed(side_index):
		if swapped.has(bid):
			continue
		var a := choose(engine, bid, style, claimed)
		if a.kind == "swap":
			claimed.append(a.swap_in)
			swapped.append(bid)
		out.append(a)
	return out


static func choose(engine: BattleEngine, bid: int, style: String, claimed: Array[int] = []) -> BattleAction:
	var b := engine.battler(bid)
	var prof := profile(engine, style)
	var options: Array = []
	var known_affordable := 0
	var ref := best_damage(engine, b)
	for mid in engine.usable_moves(bid):
		var m := engine.db.move(mid)
		if mid != engine.fallback_move():
			known_affordable += 1
		elif prof.random and known_affordable > 0:
			continue  # basic AI only flails when it has nothing else
		for t in engine.targets_for(bid, mid):
			var seconds: Array[int] = engine.second_targets_for(bid, mid, t)
			if m.target != "two_enemies" or seconds.is_empty():
				options.append({"action": BattleAction.use_move(bid, mid, t),
					"score": 0.0 if prof.random else score(engine, b, m, t, style, ref)})
				continue
			# One option per unordered pair of foes, so each pair is scored once.
			for t2 in seconds:
				if _foe_index(engine, b, t2) < _foe_index(engine, b, t):
					continue
				options.append({"action": BattleAction.use_move(bid, mid, t, t2),
					"score": 0.0 if prof.random else score(engine, b, m, t, style, ref, t2)})
	var max_e := float(b.creature.max_energy(engine.db))
	if float(b.energy()) < max_e * LOW_ENERGY:
		options.append({"action": BattleAction.rest(bid), "score": rest_score(engine, b, style)})
	if options.is_empty():
		return BattleAction.pass_turn(bid)
	if prof.random:
		return options[engine.rng.randi_range(0, options.size() - 1)].action
	var best: Dictionary = options[0]
	for o in options:
		if o.score > best.score:
			best = o
	if prof.swap and b.acted:
		var swap := _best_swap(engine, b, claimed, ref, style)
		if not swap.is_empty() and swap.score > best.score + prof.swap_margin * ref:
			return swap.action
	return best.action


## The best swap for `b` among the unclaimed bench creatures ({} when there is none).
static func _best_swap(engine: BattleEngine, b: Battler, claimed: Array[int], ref: float, style: String) -> Dictionary:
	var best := {}
	for c in engine.sides[b.side].bench():
		if claimed.has(c.bid):
			continue
		var s := swap_score(engine, b, c, style, ref)
		if best.is_empty() or s > best.score:
			best = {"action": BattleAction.swap(b.bid, c.bid), "score": s}
	return best


## Position of `foe_bid` among `b`'s active foes (orders pairs so each is scored once).
static func _foe_index(engine: BattleEngine, b: Battler, foe_bid: int) -> int:
	var foes := engine.sides[1 - b.side].active()
	for i in foes.size():
		if foes[i].bid == foe_bid:
			return i
	return -1


## What Rest is worth: REST_VALUE, scaled up by the creature's rest_bonus passive.
static func rest_score(engine: BattleEngine, b: Battler, style := "tactician") -> float:
	var base := float(engine.db.balance.energy_cfg.rest_fraction)
	return REST_VALUE * (base + engine.passive_rules.rest_bonus(b)) / base * profile(engine, style).rest


## Expected damage `x` takes next round: the sum over its foes of each foe's best usable damaging move on `x`, as if
## every foe targets `x` (pessimistic on purpose). Accuracy is ignored, as in `best_damage`.
static func threat(engine: BattleEngine, x: Battler) -> float:
	var total := 0.0
	var mine := engine.sides[x.side].active().size()
	for foe in engine.sides[1 - x.side].active():
		var best := 0.0
		for mid in engine.usable_moves(foe.bid):
			var m := engine.db.move(mid)
			if m.is_damaging():
				best = maxf(best, estimate_damage(engine, foe, m, x, _hit_count(engine, foe, m, mine)))
		total += best
	return total


## What swapping active `b` for benched `c` is worth to `b`'s side, in the units `score` uses: damage avoided (with a
## knockout bonus when the swap saves `b` and `c` survives), `c`'s damage edge, `c`'s enter triggers, and the cost
## `b` carries that the swap drops (stat stages reset on the way out; a status that skips turns costs a turn).
## `c` is also charged for its own turn-skipping status (statuses do not tick on the bench). Benched, `c` loses its own
## passive, held item and ally auras in `threat` and `best_damage` (`PassiveRules` ignores inactive creatures), while
## `b` keeps them, so the matchup terms lean against swapping; field states still apply to both.
static func swap_score(engine: BattleEngine, b: Battler, c: Battler, style: String, ref: float) -> float:
	var hp_b := float(b.hp())
	var hp_c := float(c.hp())
	var t_b := threat(engine, b)
	var t_c := threat(engine, c)
	var avoided := minf(t_b, hp_b) - minf(t_c, hp_c)
	if t_b >= hp_b and t_c < hp_c:
		avoided += KO_BONUS
	var value := avoided * profile(engine, style).swap_avoid
	value += (best_damage(engine, c) - best_damage(engine, b)) * OFFENCE_ROUNDS
	value += enter_value(engine, b, c, style)
	value += _escape_value(engine, b, ref) - _skip_cost(engine, c, ref)
	return value


## The cost `b` carries that a swap removes: negative stages (positive ones are a loss) and a turn-skipping status.
static func _escape_value(engine: BattleEngine, b: Battler, ref: float) -> float:
	var value := 0.0
	for stat in b.stages:
		value -= float(DEBUFF_VALUE.get(stat, 0.0)) * ref * float(b.stages[stat])
	return value + _skip_cost(engine, b, ref)


## Turns `x` is expected to lose to a skip_chance status, in `ref` units. A status does not tick on the bench, so it
## is also what bringing `x` back in costs.
static func _skip_cost(engine: BattleEngine, x: Battler, ref: float) -> float:
	var value := 0.0
	if x.status() != "":
		var rounds := float(mini(x.status_turns, STATUS_HORIZON))
		for e in engine.db.status(x.status()).effects:
			if e.op == "skip_chance":
				value += float(e.chance) / 100.0 * ref * rounds
	return value


static func score(engine: BattleEngine, b: Battler, m: MoveDef, target_bid: int, style: String,
		ref := -1.0, second_bid := -1) -> float:
	var db := engine.db
	var prof := profile(engine, style)
	if ref < 0.0:
		ref = best_damage(engine, b)
	var targets := engine.resolve_targets(b, m.target, target_bid, second_bid, false)
	var value := 0.0
	for t in targets:
		# A target whose passive absorbs the move's type is healed, not hurt.
		var healed := _absorbed_heal(engine, m, t)
		value += healed if t.side == b.side else -healed
		var est := estimate_damage(engine, b, m, t, targets.size())
		if est <= 0.0:
			continue
		var landed := minf(est, float(t.hp()))
		if t.side == b.side:
			value -= landed * 1.5 * prof.damage
		else:
			if not prof.random and est < float(t.hp()):
				# A foe that heals itself at round end gives back some of a hit that doesn't finish it.
				landed = maxf(0.0, landed - round_end_hp(engine, t, t.hp() - roundi(est)))
			if prof.attack == "weakest":
				# Score by weakness, not damage: the weaker the hit the better. A spread move splits one band.
				value += WEAK_ATTACK_BAND * (1.0 - 0.5 * minf(1.0, est / maxf(ref, 1.0))) / float(targets.size())
			else:
				value += landed * prof.damage + (KO_BONUS * prof.ko if est >= t.hp() else 0.0)
			if prof.retaliation > 0.0 and est < t.hp():
				var cost := _retaliation(engine, b, m, t, ref) * m.mean_hits() * prof.retaliation
				if prof.attack == "weakest":
					# Real HP would sink every weak attack below a worth-0 move. Here retaliation only ranks the
					# attacks (up to 0.4 of the band), so a weak attack still beats a pointless move.
					value -= WEAK_ATTACK_BAND * 0.4 * minf(1.0, cost / maxf(ref, 1.0))
				else:
					value -= cost
		if not prof.random and est >= float(t.hp()):
			value += _kill_triggers_value(engine, b, t, ref, style) * prof.ko
	for e in m.effects:
		if e.op == "heal":
			var max_hp := float(b.creature.max_hp(db))
			var missing := max_hp - b.hp()
			if not prof.random:
				missing = maxf(0.0, missing - round_end_hp(engine, b))  # a round-end heal does part of the job
			value += minf(missing, max_hp * float(e.fraction)) * (1.0 if b.hp() < max_hp * 0.5 else 0.2) * prof.heal
		elif e.op == "cure_status":
			value += _cure_value(engine, b, e, targets, ref)
		elif e.op == "apply_status" and not prof.random:
			value += _status_trigger_value(engine, b, e, targets, ref, style)
	if prof.setup > 0.0:
		value += _setup_value(engine, b, m, targets, ref) * prof.setup
	if prof.buff > 0.0:
		value += _buff_value(engine, b, m, targets, ref) * prof.buff
	if not m.always_hits:
		value *= minf(1.0, BattleMath.hit_chance(engine, b, m) / 100.0)
	return value


## How many creatures `m` hits when `foes` are standing: `all` also hits the user's active allies.
static func _hit_count(engine: BattleEngine, b: Battler, m: MoveDef, foes: int) -> int:
	match m.target:
		"all_enemies":
			return foes
		"all":
			return foes + engine.sides[b.side].active().size() - 1
		"two_enemies":
			return mini(2, foes)
	return 1


## Highest expected damage `b` can deal to one foe right now with a usable move (min 1).
static func best_damage(engine: BattleEngine, b: Battler) -> float:
	var best := 1.0
	var foes := engine.sides[1 - b.side].active()
	for mid in engine.usable_moves(b.bid):
		var m := engine.db.move(mid)
		if not m.is_damaging():
			continue
		for t in foes:
			best = maxf(best, estimate_damage(engine, b, m, t, _hit_count(engine, b, m, foes.size())))
	return best


## Average expected damage of `m` from `b` against `t` (no randomness); a multi-hit move counts
## its mean number of hits. Spill to another foe after a faint is not modelled.
static func estimate_damage(engine: BattleEngine, b: Battler, m: MoveDef, t: Battler, spread_count: int) -> float:
	var ctx := EffectContext.new()
	ctx.engine = engine
	ctx.user = b
	ctx.source = "move"
	ctx.move = m
	ctx.spread_count = spread_count
	ctx.targets.append(t)
	var total := 0.0
	for e in m.effects:
		if e.op == "bonus_if_field":
			var s := ctx.side_index(e.side)
			if s != -1 and engine.sides[s].field.has(e.state):
				ctx.mult *= float(e.mult)
		elif e.op == "damage" and engine.passive_rules.absorbs(t, ctx.damage_type(e)) <= 0.0:
			total += BattleMath.damage(engine, ctx, e, t, false).amount
	return total * m.mean_hits()


## HP that `m`'s damage effects would heal `t` through an absorb_type passive.
static func _absorbed_heal(engine: BattleEngine, m: MoveDef, t: Battler) -> float:
	var healed := 0.0
	var max_hp := float(t.creature.max_hp(engine.db))
	for e in m.effects:
		if e.op != "damage" or int(e.get("power", m.power)) <= 0:
			continue
		var fraction := engine.passive_rules.absorbs(t, str(e.get("type", m.type)))
		if fraction > 0.0:
			healed += maxf(1.0, roundf(max_hp * fraction))
	return minf(healed, max_hp - t.hp())


## Expected cost to `b` of the hit triggers on `t`'s passive and held item when `m` hits it:
## statuses, stat drops and damage that land on the attacker, weighted by chance, less
## whatever b's own passive blocks. Triggers whose `when` fails cost nothing; a spent
## per_battle item is ignored.
static func _retaliation(engine: BattleEngine, b: Battler, m: MoveDef, t: Battler, ref: float) -> float:
	var defs: Array[PassiveDef] = []
	var pdef := engine.db.passive(Passives.active_id(t.creature))
	if pdef != null:
		defs.append(pdef)
	var item: ItemDef = HeldItems.def_of(engine.db, t.creature)
	if item != null and not (item.held_use == "per_battle" and t.held_spent):
		var held: PassiveDef = engine.passive_rules.held_def(t)
		if held != null:
			defs.append(held)
	var cost := 0.0
	var triggers: Array = []
	for d in defs:
		triggers.append_array(d.triggers)
	for trig: Dictionary in triggers:
		if trig.on != "hit" or (trig.contact and m.category != "physical"):
			continue
		if not engine.passive_rules.when_holds(t, trig.get("when", {})):
			continue
		var chance := float(trig.chance) / 100.0
		for e: Dictionary in trig.effects:
			if e.get("target", "attacker") != "attacker":
				continue
			var each := 0.0
			match e.op:
				"apply_status":
					if b.status() == "" and not engine.passive_rules.blocks_status(b, e.status):
						each = status_value(engine, b, e.status, ref) * float(e.get("chance", 100)) / 100.0
				"stat_stage":
					if int(e.stages) < 0 and not engine.passive_rules.guards_stage(b, e.stat, t):
						each = float(DEBUFF_VALUE.get(e.stat, 0.1)) * ref * -int(e.stages)
				"damage":
					var ctx := EffectContext.new()
					ctx.engine = engine
					ctx.user = t
					ctx.source = "passive"
					ctx.attacker = b
					ctx.targets.append(b)
					each = minf(float(b.hp()), float(BattleMath.damage(engine, ctx, e, b, false).amount))
			cost += each * chance
	return cost


## The triggers of kind `on` that `holder`'s passive and held item carry (a spent per_battle item is ignored).
static func _triggers(engine: BattleEngine, holder: Battler, on: String) -> Array:
	var defs: Array[PassiveDef] = []
	var pdef := engine.db.passive(Passives.active_id(holder.creature))
	if pdef != null:
		defs.append(pdef)
	var item: ItemDef = HeldItems.def_of(engine.db, holder.creature)
	if item != null and not (item.held_use == "per_battle" and holder.held_spent):
		# A benched creature (an incoming swap) has no held_def, but its enter triggers still count.
		var held: PassiveDef = item.held if on == "enter" else engine.passive_rules.held_def(holder)
		if held != null:
			defs.append(held)
	var out := []
	for d in defs:
		for trig: Dictionary in d.triggers:
			if trig.on == on:
				out.append(trig)
	return out


## Weight of an effect in a trigger's value: HP effects count fully for every style, setup effects
## (statuses, stages, energy, cures, field states) count the style's `trigger_setup`.
static func _style_weight(engine: BattleEngine, style: String, op: String) -> float:
	if op != "damage" and op != "heal":
		return profile(engine, style).trigger_setup
	return 1.0


## Value to side `b.side` of trigger `trig` (held by `holder`) firing, its effects landing on `landing`
## unless an effect names its own target. Positive helps b's side. Weighted by the trigger's chance;
## 0 when its `when` fails. A fainting holder receives nothing from its own faint trigger.
static func trigger_value(engine: BattleEngine, b: Battler, holder: Battler, trig: Dictionary,
		landing: Battler, ref: float, style: String, pending_status := "") -> float:
	if not engine.passive_rules.when_holds(holder, trig.get("when", {})):
		return 0.0
	var ctx := EffectContext.new()
	ctx.engine = engine
	ctx.user = holder
	ctx.source = "passive"
	ctx.target_side = holder.side
	if trig.on == "faint":
		ctx.attacker = landing
	elif trig.on == "status":
		ctx.attacker = b  # the engine passes whoever inflicted the status
	var total := 0.0
	for e: Dictionary in trig.effects:
		if e.op == "apply_field_state":
			var s := ctx.side_index(e.side)
			if s != -1:
				total += _field_state_value(engine, b, holder, e, s, ref, true) * _style_weight(engine, style, e.op)
			continue
		var victims: Array[Battler] = []
		if e.has("target"):
			victims = _trigger_targets(engine, ctx, e.target)
		else:
			victims.append(landing)
		for t in victims:
			if not t.alive() or (trig.on == "faint" and t == holder):
				continue
			var owner_sign := 1.0 if t.side == b.side else -1.0
			total += _effect_value(engine, holder, e, t, ref, pending_status) * _style_weight(engine, style, e.op) * owner_sign
	return total * float(trig.get("chance", 100)) / 100.0


## The creatures a trigger effect's own `target` names. The engine picks a random creature for
## `one_enemy` and `one_ally`; scoring must not draw from the RNG, so those two get their
## deterministic fallback (the holder for `one_ally`, nobody for `one_enemy`).
static func _trigger_targets(engine: BattleEngine, ctx: EffectContext, key: String) -> Array[Battler]:
	if key == "one_enemy" or key == "one_ally":
		return engine.resolve_targets(ctx.user, key, -1, -1, false)
	return engine._effect_targets(ctx, key)


## What trigger effect `e` (run by `holder`) is worth to the creature `t` it lands on. `pending_status`
## is a status about to land on `t` (a status trigger runs after it lands, so a cure should cancel it).
static func _effect_value(engine: BattleEngine, holder: Battler, e: Dictionary, t: Battler, ref: float,
		pending_status := "") -> float:
	var db := engine.db
	match e.op:
		"damage":
			var ctx := EffectContext.new()
			ctx.engine = engine
			ctx.user = holder
			ctx.source = "passive"
			ctx.attacker = t
			ctx.targets.append(t)
			return -minf(float(t.hp()), float(BattleMath.damage(engine, ctx, e, t, false).amount))
		"heal":
			var max_hp := float(t.creature.max_hp(db))
			return minf(max_hp - t.hp(), float(e.fraction) * max_hp)
		"apply_status":
			if t.status() != "" or engine.passive_rules.blocks_status(t, e.status):
				return 0.0
			return -status_value(engine, t, e.status, ref) * float(e.get("chance", 100)) / 100.0
		"stat_stage":
			var stages := int(e.stages)
			if stages < 0 and engine.passive_rules.guards_stage(t, e.stat, holder):
				return 0.0
			return float(DEBUFF_VALUE.get(e.stat, 0.1)) * ref * stages
		"restore_energy":
			var missing := 1.0 - float(t.energy()) / float(t.creature.max_energy(db))
			return ENERGY_VALUE * ref * minf(float(e.fraction), maxf(0.0, missing))
		"cure_status":
			if t.status() != "" and (not e.has("status") or e.status == t.status()):
				return status_value(engine, t, t.status(), ref, t.status_turns)
			if t.status() == "" and pending_status != "" and (not e.has("status") or e.status == pending_status):
				return status_value(engine, t, pending_status, ref)
	return 0.0


## Value to `b`'s side of `incoming` entering the field, from its enter triggers. M6f's swap scoring calls it;
## nothing in choose does yet.
static func enter_value(engine: BattleEngine, b: Battler, incoming: Battler, style := "tactician") -> float:
	var ref := best_damage(engine, b)
	var total := 0.0
	for trig: Dictionary in _triggers(engine, incoming, "enter"):
		total += trigger_value(engine, b, incoming, trig, incoming, ref, style)
	return total


## What the status triggers of the foes `e` (an apply_status effect) would hit are worth to `b`'s side,
## weighted by the effect's chance. They land on the statused foe, so they are usually a cost. The
## aggressive style never seeks a status out, so its term is capped at 0.
static func _status_trigger_value(engine: BattleEngine, b: Battler, e: Dictionary, targets: Array[Battler],
		ref: float, style: String) -> float:
	var total := 0.0
	for t in targets:
		if t.side == b.side or t.status() != "" or engine.passive_rules.blocks_status(t, e.status):
			continue
		for trig: Dictionary in _triggers(engine, t, "status"):
			total += trigger_value(engine, b, t, trig, t, ref, style, e.status)
	total *= float(e.get("chance", 100)) / 100.0
	return total if profile(engine, style).seeks_status else minf(0.0, total)


## Expected change to `t`'s HP from its own round_end triggers (heals, minus damage to itself), with
## its HP taken as `hp_now` when given. Effects with another target are ignored.
static func round_end_hp(engine: BattleEngine, t: Battler, hp_now := -1) -> float:
	var hp := float(t.hp() if hp_now < 0 else hp_now)
	var max_hp := float(t.creature.max_hp(engine.db))
	var total := 0.0
	for trig: Dictionary in _triggers(engine, t, "round_end"):
		if not engine.passive_rules.when_holds(t, trig.get("when", {})):
			continue
		var part := 0.0
		for e: Dictionary in trig.effects:
			if e.has("target") and e.target != "self":
				continue
			if e.op == "heal":
				part += minf(max_hp - hp, float(e.fraction) * max_hp)
			elif e.op == "damage":
				part += _effect_value(engine, t, e, t, 0.0)
		total += part * float(trig.get("chance", 100)) / 100.0
	return total


## What finishing `t` is worth beyond its HP: `b`'s own knockout triggers (for a foe only) and the
## faint triggers `t` carries, which land on `b`, the killer.
static func _kill_triggers_value(engine: BattleEngine, b: Battler, t: Battler, ref: float, style: String) -> float:
	var total := 0.0
	if t.side != b.side:
		for trig: Dictionary in _triggers(engine, b, "knockout"):
			total += trigger_value(engine, b, b, trig, b, ref, style)
	for trig: Dictionary in _triggers(engine, t, "faint"):
		total += trigger_value(engine, b, t, trig, b, ref, style)
	return total


## Expected payoff of reaction `r` firing on `side_index`, triggered by `b`.
## Positive for harm to b's foes, negative for harm to b's own side.
static func reaction_value(engine: BattleEngine, b: Battler, r: ReactionDef, side_index: int,
		stacks: int, ref: float) -> float:
	var ctx := EffectContext.new()
	ctx.engine = engine
	ctx.user = b
	ctx.source = "reaction"
	ctx.reaction = r
	ctx.target_side = side_index
	ctx.stacks_consumed = stacks
	var victims: Array[Battler] = []
	victims.append_array(engine.sides[side_index].active())
	if r.scope == "both_sides":
		victims.append_array(engine.sides[1 - side_index].active())
	var value := 0.0
	for e in r.effects:
		for t in victims:
			var sign := 1.0 if t.side != b.side else -1.0
			match e.op:
				"damage":
					if engine.field_rules.reaction_shelter(r, t) != null:
						continue
					var fraction := engine.passive_rules.absorbs(t, ctx.damage_type(e))
					if fraction > 0.0:
						var max_hp := float(t.creature.max_hp(engine.db))
						value -= sign * minf(maxf(1.0, roundf(max_hp * fraction)), max_hp - t.hp())
						continue
					value += sign * minf(float(t.hp()), float(BattleMath.damage(engine, ctx, e, t, false).amount))
				"apply_status":
					if t.status() == "" and not engine.passive_rules.blocks_status(t, e.status):
						value += sign * status_value(engine, t, e.status, ref) * float(e.get("chance", 100)) / 100.0
				"stat_stage":
					if int(e.stages) < 0 and not engine.passive_rules.guards_stage(t, e.stat, b):
						value += sign * float(DEBUFF_VALUE.get(e.stat, 0.1)) * ref * -int(e.stages)
	return value


## What a `cure_status` effect on `move_targets` (or the effect's own `target`) is worth: each
## matching afflicted creature on the user's side gains what the status would still have cost it
## (its remaining rounds), and curing a foe costs the same.
static func _cure_value(engine: BattleEngine, b: Battler, e: Dictionary, move_targets: Array[Battler],
		ref: float) -> float:
	var victims := move_targets
	if e.has("target"):
		var ctx := EffectContext.new()
		ctx.engine = engine
		ctx.user = b
		victims = engine._effect_targets(ctx, e.target)
	var value := 0.0
	for t in victims:
		if not t.alive() or t.status() == "" or (e.has("status") and e.status != t.status()):
			continue
		var worth := status_value(engine, t, t.status(), ref, t.status_turns)
		value += worth if t.side == b.side else -worth
	return value


## Expected value of inflicting `status_id` on `t`, from what the status actually does. Counts
## `rounds_left` rounds when given (an existing status), else the status's full duration.
static func status_value(engine: BattleEngine, t: Battler, status_id: String, ref: float,
		rounds_left := -1) -> float:
	var sdef := engine.db.status(status_id)
	var rounds := float(mini(sdef.turns if rounds_left < 0 else rounds_left, STATUS_HORIZON))
	var value := 0.0
	for e in sdef.effects:
		match e.op:
			"damage_fraction":
				value += float(e.fraction) * t.creature.max_hp(engine.db) * rounds
			"skip_chance":
				value += float(e.chance) / 100.0 * ref * rounds
			"stat_mod":
				if float(e.mult) < 1.0:
					value += (1.0 - float(e.mult)) * float(DEBUFF_VALUE.get(e.stat, 0.1)) * 2.0 * ref * rounds
	return value


static func _setup_value(engine: BattleEngine, b: Battler, m: MoveDef, targets: Array[Battler], ref: float) -> float:
	var value := 0.0
	for e in m.effects:
		match e.op:
			"apply_field_state":
				var ctx := EffectContext.new()
				ctx.engine = engine
				ctx.user = b
				ctx.target_side = 1 - b.side if m.target == "enemy_side" else b.side
				var s := ctx.side_index(e.side)
				if s != -1:
					value += _field_state_value(engine, b, b, e, s, ref)
			"apply_status":
				for t in targets:
					if t.side != b.side and t.status() == "" and not engine.passive_rules.blocks_status(t, e.status):
						value += status_value(engine, t, e.status, ref) * float(e.get("chance", 100)) / 100.0
			"stat_stage":
				if int(e.stages) < 0:
					for t in targets:
						if t.side != b.side and not engine.passive_rules.guards_stage(t, e.stat, b):
							value += float(DEBUFF_VALUE.get(e.stat, 0.1)) * ref * -int(e.stages)
	return value


## Value of `m`'s own-side stat buffs: a positive stat_stage on the user or an ally is worth what the same drop is worth
## on a foe (DEBUFF_VALUE x ref x stages), 0 for a creature already at the stage cap.
static func _buff_value(engine: BattleEngine, b: Battler, m: MoveDef, targets: Array[Battler], ref: float) -> float:
	var value := 0.0
	for e in m.effects:
		if e.op != "stat_stage" or int(e.stages) <= 0:
			continue
		var landing := targets
		if e.has("target"):  # an effect can name its own target (a buff on the user riding on an attack)
			var ctx := EffectContext.new()
			ctx.engine = engine
			ctx.user = b
			landing = engine._effect_targets(ctx, e.target)
		for t in landing:
			if t.side == b.side and int(t.stages[e.stat]) < Battler.STAGE_MAX:
				value += float(DEBUFF_VALUE.get(e.stat, 0.1)) * ref * int(e.stages)
	return value


## Value to `b`'s side of field-state effect `e` landing on side `side_index`: stacking, the reaction
## it would set off, the oldest state it would push out, and whether the state helps its holder.
## `source` is the creature whose field_boost adds stacks (the mover; a trigger's holder).
static func _field_state_value(engine: BattleEngine, b: Battler, source: Battler, e: Dictionary,
		side_index: int, ref: float, for_trigger := false) -> float:
	var db := engine.db
	var s := side_index
	var field := engine.sides[s].field
	var stacks := int(e.get("stacks", 1)) + engine.passive_rules.field_boost(source).x
	if field.has(e.state):
		if for_trigger:
			# Restacking helps us when a helpful state lands on our side or a hostile one on theirs.
			var held := state_benefit(engine, e.state)
			var good := held == 0.0 or (held > 0.0) == (s == b.side)
			return (RESTACK if good else -RESTACK) * ref
		return RESTACK * ref
	for existing in field.ids():
		var r := db.find_reaction(existing, e.state)
		if r != null:
			# Stacks used up: the consumed existing states plus the incoming one if consumed.
			var used := 0
			for c in r.consumes:
				used += stacks if c == e.state else field.stacks(c)
			return reaction_value(engine, b, r, s, used, ref)
	var value := 0.0
	# At the cap the oldest state is pushed out: good if it helped the enemy or hurt us.
	if field.size() >= db.balance.max_field_states:
		var lost := state_benefit(engine, field.states[0].id)
		var sign_for_us := -1.0 if s == b.side else 1.0
		if lost > 0.0:
			value += sign_for_us * REPLACE * ref
		elif lost < 0.0:
			value -= sign_for_us * REPLACE * ref
	var benefit := state_benefit(engine, e.state)
	if s == b.side:
		if benefit > 0.0:
			value += OWN_BUFF * ref
		elif for_trigger and benefit < 0.0:
			value -= NEW_STATE * ref  # a hostile state landing on our own side (only a trigger does that)
		return value
	if benefit > 0.0:
		return value - OWN_BUFF * ref  # never buff the enemy
	value += NEW_STATE * ref
	var follow := _best_follow_up(engine, b, e.state, s, stacks, ref)
	if follow > 0.0:
		value += FOLLOW_DISCOUNT * follow
	elif _team_can_cash_in(engine, b.side, e.state):
		value += FOLLOW_CASH_IN * ref
	return value


## Rough sign of a field state for whoever holds it: > 0 helps, < 0 hurts.
static func state_benefit(engine: BattleEngine, state: String) -> float:
	var total := 0.0
	for p in engine.db.field_state(state).passive:
		match p.op:
			"stat_mod":
				total += float(p.mult) - 1.0
			"incoming_type_mod":
				total += 1.0 - float(p.mult)
	return total


## Value of the best reaction b's team could trigger next by adding a state to
## `state` already sitting on `side_index`. 0 if none.
static func _best_follow_up(engine: BattleEngine, b: Battler, state: String, side_index: int,
		stacks: int, ref: float) -> float:
	var db := engine.db
	var best := 0.0
	for ally in engine.sides[b.side].battlers:
		if not ally.alive():
			continue
		for mid in ally.creature.moves:
			for e in db.move(mid).effects:
				if e.op != "apply_field_state":
					continue
				var r := db.find_reaction(state, e.state)
				if r == null:
					continue
				var used := 0
				for c in r.consumes:
					used += int(e.get("stacks", 1)) if c == e.state else stacks
				best = maxf(best, reaction_value(engine, b, r, side_index, used, ref))
	return best


## Does a living ally know a move that gets a bonus from `state`?
static func _team_can_cash_in(engine: BattleEngine, side_index: int, state: String) -> bool:
	for ally in engine.sides[side_index].battlers:
		if not ally.alive():
			continue
		for mid in ally.creature.moves:
			for e in engine.db.move(mid).effects:
				if e.op == "bonus_if_field" and e.state == state:
					return true
	return false
