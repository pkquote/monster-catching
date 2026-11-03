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
## A setup that enables a reaction next turn is worth this share of that reaction's value.
const FOLLOW_DISCOUNT := 0.6
## Below this share of max energy, Rest becomes an option worth REST_VALUE.
const LOW_ENERGY := 0.2
const REST_VALUE := 6.0


static func choose_all(engine: BattleEngine, side_index: int) -> Array:
	var style := engine.sides[side_index].ai
	var out: Array = []
	for bid in engine.actions_needed(side_index):
		out.append(choose(engine, bid, style))
	return out


static func choose(engine: BattleEngine, bid: int, style: String) -> BattleAction:
	var b := engine.battler(bid)
	var options: Array = []
	var known_affordable := 0
	var ref := best_damage(engine, b)
	for mid in engine.usable_moves(bid):
		var m := engine.db.move(mid)
		if mid != engine.fallback_move():
			known_affordable += 1
		elif style == "basic" and known_affordable > 0:
			continue  # basic AI only flails when it has nothing else
		for t in engine.targets_for(bid, mid):
			options.append({"action": BattleAction.use_move(bid, mid, t),
				"score": 0.0 if style == "basic" else score(engine, b, m, t, style, ref)})
	var max_e := float(b.creature.max_energy(engine.db))
	if float(b.energy()) < max_e * LOW_ENERGY:
		options.append({"action": BattleAction.rest(bid), "score": REST_VALUE})
	if options.is_empty():
		return BattleAction.pass_turn(bid)
	if style == "basic":
		return options[engine.rng.randi_range(0, options.size() - 1)].action
	var best: Dictionary = options[0]
	for o in options:
		if o.score > best.score:
			best = o
	return best.action


static func score(engine: BattleEngine, b: Battler, m: MoveDef, target_bid: int, style: String,
		ref := -1.0) -> float:
	var db := engine.db
	if ref < 0.0:
		ref = best_damage(engine, b)
	var targets := engine.resolve_targets(b, m.target, target_bid, false)
	var value := 0.0
	for t in targets:
		var est := estimate_damage(engine, b, m, t, targets.size() > 1)
		if est <= 0.0:
			continue
		var landed := minf(est, float(t.hp()))
		if t.side == b.side:
			value -= landed * 1.5
		else:
			value += landed + (KO_BONUS if est >= t.hp() else 0.0)
	for e in m.effects:
		if e.op == "heal":
			var max_hp := float(b.creature.max_hp(db))
			var missing := max_hp - b.hp()
			value += minf(missing, max_hp * float(e.fraction)) * (1.0 if b.hp() < max_hp * 0.5 else 0.2)
	if style == "tactician":
		value += _setup_value(engine, b, m, targets, ref)
	if not m.always_hits:
		value *= minf(1.0, BattleMath.hit_chance(engine, b, m) / 100.0)
	return value


## Highest expected damage `b` can deal to one foe right now with a usable move (min 1).
static func best_damage(engine: BattleEngine, b: Battler) -> float:
	var best := 1.0
	var foes := engine.sides[1 - b.side].active()
	for mid in engine.usable_moves(b.bid):
		var m := engine.db.move(mid)
		if not m.is_damaging():
			continue
		for t in foes:
			best = maxf(best, estimate_damage(engine, b, m, t, m.target in ["all_enemies", "all"] and foes.size() > 1))
	return best


## Average expected damage of `m` from `b` against `t` (no randomness).
static func estimate_damage(engine: BattleEngine, b: Battler, m: MoveDef, t: Battler, spread: bool) -> float:
	var ctx := EffectContext.new()
	ctx.engine = engine
	ctx.user = b
	ctx.source = "move"
	ctx.move = m
	ctx.spread = spread
	ctx.targets.append(t)
	var total := 0.0
	for e in m.effects:
		if e.op == "bonus_if_field":
			var s := ctx.side_index(e.side)
			if s != -1 and engine.sides[s].field.has(e.state):
				ctx.mult *= float(e.mult)
		elif e.op == "damage":
			total += BattleMath.damage(engine, ctx, e, t, false).amount
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
					value += sign * minf(float(t.hp()), float(BattleMath.damage(engine, ctx, e, t, false).amount))
				"apply_status":
					if t.status() == "":
						value += sign * status_value(engine, t, e.status, ref) * float(e.get("chance", 100)) / 100.0
				"stat_stage":
					if int(e.stages) < 0:
						value += sign * float(DEBUFF_VALUE.get(e.stat, 0.1)) * ref * -int(e.stages)
	return value


## Expected value of inflicting `status_id` on `t`, from what the status actually does.
static func status_value(engine: BattleEngine, t: Battler, status_id: String, ref: float) -> float:
	var sdef := engine.db.status(status_id)
	var rounds := float(mini(sdef.turns, STATUS_HORIZON))
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
	var db := engine.db
	var value := 0.0
	for e in m.effects:
		match e.op:
			"apply_field_state":
				var ctx := EffectContext.new()
				ctx.engine = engine
				ctx.user = b
				ctx.target_side = 1 - b.side if m.target == "enemy_side" else b.side
				var s := ctx.side_index(e.side)
				if s == -1:
					continue
				var field := engine.sides[s].field
				var stacks := int(e.get("stacks", 1))
				if field.has(e.state):
					value += RESTACK * ref
					continue
				var fired := false
				for existing in field.ids():
					var r := db.find_reaction(existing, e.state)
					if r != null:
						# Stacks used up: the consumed existing states plus the incoming one if consumed.
						var used := 0
						for c in r.consumes:
							used += stacks if c == e.state else field.stacks(c)
						value += reaction_value(engine, b, r, s, used, ref)
						fired = true
						break
				if fired:
					continue
				var benefit := state_benefit(engine, e.state)
				if s == b.side:
					if benefit > 0.0:
						value += OWN_BUFF * ref
					continue
				if benefit > 0.0:
					value -= OWN_BUFF * ref  # never buff the enemy
					continue
				value += NEW_STATE * ref
				var follow := _best_follow_up(engine, b, e.state, s, stacks, ref)
				if follow > 0.0:
					value += FOLLOW_DISCOUNT * follow
				elif _team_can_cash_in(engine, b.side, e.state):
					value += FOLLOW_CASH_IN * ref
			"apply_status":
				for t in targets:
					if t.side != b.side and t.status() == "":
						value += status_value(engine, t, e.status, ref) * float(e.get("chance", 100)) / 100.0
			"stat_stage":
				if int(e.stages) < 0:
					for t in targets:
						if t.side != b.side:
							value += float(DEBUFF_VALUE.get(e.stat, 0.1)) * ref * -int(e.stages)
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
