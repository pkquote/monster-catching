class_name EffectText
extends RefCounted
## Plain-language wording for effects, `when` conditions and triggers.
## Shared by the compendium builder and in-game text.

const SIDE_LABELS := {
	"user": "the user's side",
	"target": "the target's side",
	"own": "own side",
	"enemy": "the enemy side",
	"both": "both sides",
}
const TARGET_LABELS := {
	"self": "Self",
	"one_ally": "One ally",
	"one_enemy": "One enemy",
	"all_allies": "All allies",
	"all_enemies": "All enemies",
	"all": "Everyone",
	"two_enemies": "Two foes",
	"own_side": "Own side",
	"enemy_side": "Enemy side",
	"attacker": "Attacker",
}
const TRIGGER_LABELS := {"enter": "entering", "hit": "being hit", "round_end": "round end",
	"knockout": "a knockout", "faint": "fainting", "status": "getting a status"}
const STAT_LABELS := {"hp": "HP", "patk": "P.Atk", "pdef": "P.Def", "satk": "S.Atk", "sdef": "S.Def",
	"spd": "Spd", "acc": "Acc", "luck": "Luck", "resolve": "Resolve", "stamina": "Stamina"}


static func effects(db: Database, effects: Array) -> String:
	if effects.is_empty():
		return "—"
	return "; ".join(effects.map(func(e: Dictionary) -> String: return effect(db, e)))


## A compact `effects` for tight spaces (the battle's field-state labels): damage-taken modifiers
## with the same multiplier merge ("Dark & Ghost dmg taken x0.75"); everything else reads as in `effect`.
static func short(db: Database, effects: Array) -> String:
	if effects.is_empty():
		return "—"
	var taken: Dictionary = {}  # multiplier text -> type names, in the order first seen
	var order: Array = []
	for e: Dictionary in effects:
		if e.op == "incoming_type_mod":
			var key: String = num(e.mult)
			if not taken.has(key):
				taken[key] = []
				order.append({"taken": key})
			taken[key].append(db.type_def(e.type).name if e.has("type") else "All")
		else:
			order.append({"text": effect(db, e)})
	var parts: PackedStringArray = PackedStringArray()
	for item: Dictionary in order:
		if item.has("taken"):
			parts.append("%s dmg taken x%s" % [" & ".join(taken[item.taken]), item.taken])
		else:
			parts.append(item.text)
	return "; ".join(parts)


static func effect(db: Database, e: Dictionary) -> String:
	var s := ""
	match e.op:
		"damage":
			s = "Damage"
			if e.has("power"):
				s += " (power %d" % e.power
				if e.has("type"):
					s += " %s" % db.type_def(e.type).name
				s += ")"
			if e.get("scale_with_stacks", false):
				s += ", scales with stacks consumed"
		"damage_fraction":
			s = "Loses %s max HP each round" % pct(e.fraction)
		"reset_training":
			s = "Returns all spent training points (field use only)"
		"skip_chance":
			s = "%d%% chance to lose its action" % e.chance
		"heal":
			s = "Heals %s max HP" % pct(e.fraction)
		"apply_status":
			s = "Inflicts %s" % db.status(e.status).name
			if e.has("chance"):
				s += " (%d%%)" % e.chance
		"apply_field_state":
			s = "Applies %s to %s" % [state_name(db, e.state), SIDE_LABELS[e.side]]
			var extra := PackedStringArray()
			if e.has("stacks"):
				extra.append("%d stacks" % e.stacks)
			if e.has("turns"):
				extra.append("%d rounds" % e.turns)
			if not extra.is_empty():
				s += " (%s)" % ", ".join(extra)
		"remove_field_state":
			s = "Clears %s from %s" % [state_name(db, e.state) if e.has("state") else "all states", SIDE_LABELS[e.side]]
		"bonus_if_field":
			s = "x%s if %s is %s" % [num(e.mult), SIDE_LABELS[e.side], state_name(db, e.state)]
			if e.get("consume", false):
				s += " (consumes it)"
		"stat_stage":
			s = "%s %s" % [STAT_LABELS[e.stat], signed(e.stages)]
		"stat_mod":
			s = "%s x%s" % [STAT_LABELS[e.stat], num(e.mult)]
		"incoming_type_mod":
			s = "%s damage taken x%s" % [db.type_def(e.type).name if e.has("type") else "All", num(e.mult)]
		"type_power":
			s = "%s moves x%s" % [db.type_def(e.type).name, num(e.mult)]
		"absorb_type":
			s = "%s damage heals %s max HP instead" % [db.type_def(e.type).name, pct(e.fraction)]
		"status_immune":
			s = "Can't be %s" % ("given %s" % db.status(e.status).name if e.has("status") else "given a status")
		"guard_stages":
			s = "Foes can't lower its %s" % (STAT_LABELS[e.stat] if e.has("stat") else "stats")
		"field_shelter":
			s = "Sheltered from %s" % state_name(db, e.state)
		"field_boost":
			var extra := PackedStringArray()
			if e.has("stacks"):
				extra.append("+%d stack(s)" % e.stacks)
			if e.has("turns"):
				extra.append("+%d round(s)" % e.turns)
			s = "Its field states get %s" % " and ".join(extra)
		"reaction_power":
			s = "Reactions it triggers x%s" % num(e.mult)
		"energy_discount":
			s = "%s moves cost %d less" % [db.type_def(e.type).name if e.has("type") else "All", e.amount]
		"rest_bonus":
			s = "Rest restores +%s max energy" % pct(e.fraction)
		"scrap_power":
			s = "Scrap x%s" % num(e.mult)
		"encounter_rate":
			s = "Wild encounter rate x%s" % num(e.mult)
		"xp_mult":
			s = "XP earned x%s" % num(e.mult)
		"bond_gain":
			s = "Bond gains x%s" % num(e.mult)
		"restore_energy":
			s = "Restores %s max energy" % pct(e.fraction)
		"cure_status":
			s = "Cures %s" % (db.status(e.status).name if e.has("status") else "any status")
		"capture":
			s = "Capture x%s" % num(e.mult)
			var bonus: Dictionary = e.get("field_bonus", {})
			for st: String in bonus:
				s += ", x%s on %s" % [num(bonus[st]), state_name(db, st)]
		_:
			s = e.op
	if e.has("when"):
		s += " [%s]" % when(db, e.when)
	if e.has("target"):
		s += " → %s" % TARGET_LABELS[e.target].to_lower()
	return s


static func when(db: Database, w: Dictionary) -> String:
	var parts := PackedStringArray()
	if w.has("hp_below"):
		parts.append("HP below %s" % pct(w.hp_below))
	if w.get("underdog", false):
		parts.append("outnumbered")
	if w.has("field"):
		parts.append("%s on %s" % [state_name(db, w.field), SIDE_LABELS[w.side]])
	return ", ".join(parts)


## "On being hit (physical) (30%) [HP below 50%]: effects; ..." or an em dash.
static func triggers(db: Database, triggers: Array) -> String:
	var parts := PackedStringArray()
	for t: Dictionary in triggers:
		var s := "On %s" % TRIGGER_LABELS[t.on]
		if t.contact:
			s += " (physical)"
		if t.chance < 100:
			s += " (%d%%)" % t.chance
		if not t.when.is_empty():
			s += " [%s]" % when(db, t.when)
		parts.append("%s: %s" % [s, effects(db, t.effects)])
	return or_dash("; ".join(parts))


static func state_name(db: Database, id: String) -> String:
	return db.field_state(id).name


static func signed(n: int) -> String:
	return "+%d" % n if n > 0 else str(n)


static func num(f: float) -> String:
	return str(int(f)) if f == floorf(f) else str(f)


static func pct(f: float) -> String:
	return "%s%%" % num(snappedf(f * 100.0, 0.01))


static func or_dash(s: String) -> String:
	return "—" if s.is_empty() else s
