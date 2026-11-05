class_name PassiveRules
extends BattlePart
## Creature passives in battle: the always-on effects a battler gets from its own active
## passive and from allied auras (scope "allies"), and its triggers (enter, hit, round_end,
## knockout, faint). Only creatures on the field and standing contribute, receive or fire
## anything (a faint trigger fires as its creature goes down).
##
## Effects run by a trigger never set off further triggers: while one runs (_depth > 0),
## fire() does nothing, and a creature it knocks out fires no faint or knockout triggers.
## They earn no Affinity either (see running()).

## Who a trigger's effects land on when an effect has no "target" of its own.
const DEFAULT_TARGET := {"enter": "self", "hit": "attacker", "round_end": "self",
	"knockout": "self", "faint": "attacker"}

var _depth := 0
## bids knocked out by a trigger's effects (their faint fires no triggers).
var _silenced := {}
## The held item id that supplied the effect matched by the latest _source / absorbs call
## ("" when it came from a passive). Read it right after the lookup, for the banner.
var last_item := ""


## True while a trigger's effects run. Nothing earns Affinity then (BattleRewards.award).
func running() -> bool:
	return _depth > 0


## Always-on effects currently on `b`: its active passive's effects whose `when` holds,
## plus the effects of every allied aura on the field (`b` included), each passive id
## counted once. Empty for a fainted or benched battler.
func effects_for(b: Battler) -> Array:
	var out: Array = []
	_collect(b, out, [])
	return out


## `holders` and `items` run parallel to `out`: who carries each effect, and the held item
## id it comes from ("" for a passive).
func _collect(b: Battler, out: Array, holders: Array, items: Array = []) -> void:
	if not b.active or not b.alive():
		return
	var e := engine
	var seen := {}
	var seen_items := {}
	var own_id := Passives.active_id(b.creature)
	var own := e.db.passive(own_id) if own_id != "" else null
	if own != null:
		seen[own_id] = true
		_append_holding(out, holders, items, b, own.effects, "")
	var own_held := held_def(b)
	if own_held != null:
		seen_items[own_held.id] = true
		_append_holding(out, holders, items, b, own_held.effects, own_held.id)
	for ally in e.sides[b.side].active():
		var pid := Passives.active_id(ally.creature)
		if pid != "" and not seen.has(pid):
			var def := e.db.passive(pid)
			if def != null and def.scope == "allies":
				seen[pid] = true
				# An aura's conditions are read from the creature that carries it.
				_append_holding(out, holders, items, ally, def.effects, "")
		var held := held_def(ally)
		if held != null and held.scope == "allies" and not seen_items.has(held.id):
			seen_items[held.id] = true
			_append_holding(out, holders, items, ally, held.effects, held.id)


## `b`'s held item as a def, or null: nothing held, an unknown or non-held item id, or `b`
## is benched or fainted.
func held_def(b: Battler) -> PassiveDef:
	if not b.active or not b.alive():
		return null
	var item := HeldItems.def_of(engine.db, b.creature)
	return item.held if item != null else null


## Runs each of `b`'s triggers for `on`: its active passive's first, then its held item's
## (unless a per_battle item is already spent). `attacker` is the creature that
## set it off (the hitter for hit, the foe knocked out for knockout, the killer for faint);
## `contact` is true for physical moves (hit triggers with "contact" need it).
## A trigger fires only when its `when` holds, its chance roll passes and its effects would
## change something. Only then is a held item used up (consumed: gone; per_battle: spent).
func fire(b: Battler, on: String, attacker: Battler = null, contact := false) -> void:
	var e := engine
	if _depth > 0 or e.is_over():
		return
	if on != "faint" and (not b.active or not b.alive()):
		return
	var pid := Passives.active_id(b.creature)
	var def := e.db.passive(pid) if pid != "" else null
	if def != null:
		_fire_from(b, def, "", on, attacker, contact)
	var item := HeldItems.def_of(e.db, b.creature)
	var held := _trigger_item(b, on)
	if held != null and item != null and not (item.held_use == "per_battle" and b.held_spent):
		_fire_from(b, held, held.id, on, attacker, contact)


## The held item def whose triggers `b` may run for `on`. A fainting creature has just left
## the field, so its faint triggers don't need it to be active or alive.
func _trigger_item(b: Battler, on: String) -> PassiveDef:
	if on != "faint":
		return held_def(b)
	var item := HeldItems.def_of(engine.db, b.creature)
	return item.held if item != null else null


## One source's triggers (`item_id` is "" for the creature's passive).
func _fire_from(b: Battler, def: PassiveDef, item_id: String, on: String, attacker: Battler,
		contact: bool) -> void:
	var e := engine
	for t: Dictionary in def.triggers:
		if t.on != on or (t.contact and not contact):
			continue
		if not when_holds(b, t.when):
			continue
		if int(t.chance) < 100 and e.rng.randi_range(1, 100) > int(t.chance):
			continue
		var ctx := EffectContext.new()
		ctx.engine = e
		ctx.user = b
		ctx.source = "passive"
		ctx.attacker = attacker
		ctx.target_side = b.side
		var target: Battler = attacker if DEFAULT_TARGET[on] == "attacker" else b
		if target != null:
			ctx.targets.append(target)
		if _does_nothing(ctx, t.effects):
			continue
		e.emit_passive(b, item_id)
		_depth += 1
		e.run_effects(ctx, t.effects)
		_depth -= 1
		if item_id != "" and _use_up(b):
			return


## `b`'s held item fired: a consumed one is gone from the battle copy, a per_battle one is
## spent. Applies the usage bookkeeping and returns whether the item can no longer fire.
func _use_up(b: Battler) -> bool:
	var item := HeldItems.def_of(engine.db, b.creature)
	if item == null:
		return false
	match item.held_use:
		"consumed":
			var id := b.creature.held_item
			b.creature.held_item = ""
			engine.emit({"type": BattleEvents.ITEM_CONSUMED, "bid": b.bid, "item": id})
			return true
		"per_battle":
			b.held_spent = true
			return true
	return false


## True when every effect would change nothing: only heals on creatures at full HP and
## energy restores on creatures at full energy. Such a trigger is skipped (no banner).
func _does_nothing(ctx: EffectContext, effects: Array) -> bool:
	var e := engine
	for eff: Dictionary in effects:
		if eff.op != "heal" and eff.op != "restore_energy":
			return false
		var targets: Array[Battler] = e._effect_targets(ctx, eff.target) if eff.has("target") else ctx.targets
		for t in targets:
			if not t.alive():
				continue
			if eff.op == "heal" and t.hp() < t.creature.max_hp(e.db):
				return false
			if eff.op == "restore_energy" and t.energy() < t.creature.max_energy(e.db):
				return false
	return true


## `b` just fainted (`killer` knocked it out, or null): its faint triggers, then the
## killer's knockout triggers, unless a trigger's effects did the knocking out.
func on_faint(b: Battler, killer: Battler) -> void:
	if _silenced.erase(b.bid):
		return
	fire(b, "faint", killer)
	if killer != null:
		fire(killer, "knockout", b)


## `target` took damage. A knockout from a trigger's effects is remembered so it
## sets off nothing (see on_faint).
func note_damage(target: Battler) -> void:
	if _depth > 0 and target.hp() <= 0:
		_silenced[target.bid] = true


## The share of max HP that damage of `type` heals `target` instead (absorb_type), or 0.
func absorbs(target: Battler, type: String) -> float:
	var best := 0.0
	var best_item := ""
	var effs: Array = []
	var items: Array = []
	_collect(target, effs, [], items)
	for i in effs.size():
		var eff: Dictionary = effs[i]
		if eff.op == "absorb_type" and eff.type == type and float(eff.fraction) > best:
			best = float(eff.fraction)
			best_item = items[i]
	last_item = best_item
	return best


# --- Protection (each returns the creature whose passive protects `b`, or null) ---

## status_immune: `status_id` can't be inflicted on `b`.
func status_blocker(b: Battler, status_id: String) -> Battler:
	return _source(b, func(eff): return eff.op == "status_immune" and eff.get("status", status_id) == status_id)


func blocks_status(b: Battler, status_id: String) -> bool:
	return status_blocker(b, status_id) != null


## guard_stages: `by` (a foe) can't lower `b`'s `stat`. Its own side still can.
func stage_guard(b: Battler, stat: String, by: Battler) -> Battler:
	if by == null or by.side == b.side:
		return null
	return _source(b, func(eff): return eff.op == "guard_stages" and eff.get("stat", stat) == stat)


func guards_stage(b: Battler, stat: String, by: Battler) -> bool:
	return stage_guard(b, stat, by) != null


## field_shelter: `state_id`'s passives skip `b`, and its reactions don't damage it.
func shelter(b: Battler, state_id: String) -> Battler:
	return _source(b, func(eff): return eff.op == "field_shelter" and eff.state == state_id)


func shelters(b: Battler, state_id: String) -> bool:
	return shelter(b, state_id) != null


# --- Game-specific ---

## field_boost: extra (stacks, turns) on every field state `b` applies.
func field_boost(b: Battler) -> Vector2i:
	var out := Vector2i.ZERO
	for eff: Dictionary in effects_for(b):
		if eff.op == "field_boost":
			out += Vector2i(int(eff.get("stacks", 0)), int(eff.get("turns", 0)))
	return out


## reaction_power: damage multiplier for reactions `b` triggers.
func reaction_mult(b: Battler) -> float:
	return _product(b, "reaction_power")


## The energy `move` costs `b`: its cost minus energy_discount (all moves, or the move's
## type), never below 0. Used to pay for moves and to decide which ones it can afford.
func move_cost(b: Battler, move: MoveDef) -> int:
	var discount := 0
	for eff: Dictionary in effects_for(b):
		if eff.op == "energy_discount" and eff.get("type", move.type) == move.type:
			discount += int(eff.amount)
	return maxi(0, move.cost - discount)


## rest_bonus: extra share of max energy that Rest restores.
func rest_bonus(b: Battler) -> float:
	var out := 0.0
	for eff: Dictionary in effects_for(b):
		if eff.op == "rest_bonus":
			out += float(eff.fraction)
	return out


## scrap_power: damage multiplier for `b`'s Scrap.
func scrap_mult(b: Battler) -> float:
	return _product(b, "scrap_power")


func _product(b: Battler, op: String) -> float:
	var out := 1.0
	for eff: Dictionary in effects_for(b):
		if eff.op == op:
			out *= float(eff.mult)
	return out


## True while every key of `when` holds for `b` (an empty `when` always holds).
func when_holds(b: Battler, when: Dictionary) -> bool:
	var e := engine
	if when.has("hp_below") and float(b.hp()) >= float(when.hp_below) * float(b.creature.max_hp(e.db)):
		return false
	if when.get("underdog", false) \
			and e.sides[1 - b.side].active().size() <= e.sides[b.side].active().size():
		return false
	if when.has("field"):
		var side := b.side if when.get("side", "own") == "own" else 1 - b.side
		if not e.sides[side].field.has(when.field):
			return false
	return true


func _append_holding(out: Array, holders: Array, items: Array, holder: Battler, effects: Array,
		item_id: String) -> void:
	for eff: Dictionary in effects:
		if when_holds(holder, eff.get("when", {})):
			out.append(eff)
			holders.append(holder)
			items.append(item_id)


## The creature whose passive or held item gives `b` the first effect matching `pred` (`b`
## itself, or an aura holder), or null. Sets `last_item` to the item that supplied it.
func _source(b: Battler, pred: Callable) -> Battler:
	var effs: Array = []
	var holders: Array = []
	var items: Array = []
	_collect(b, effs, holders, items)
	last_item = ""
	for i in effs.size():
		if pred.call(effs[i]):
			last_item = items[i]
			return holders[i]
	return null
