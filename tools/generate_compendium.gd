extends SceneTree
## Generates documentation/compendium.md, a readable reference of all game content,
## straight from the JSON data so it never drifts out of date.
##   godot --headless --path . --script res://tools/generate_compendium.gd
## Exits 1 if the content fails validation.

const OUT_PATH := "res://documentation/compendium.md"

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
	"own_side": "Own side",
	"enemy_side": "Enemy side",
	"attacker": "Attacker",
}
const TRIGGER_LABELS := {"enter": "entering", "hit": "being hit", "round_end": "round end",
	"knockout": "a knockout", "faint": "fainting"}
const STAT_LABELS := {"hp": "HP", "patk": "P.Atk", "pdef": "P.Def", "satk": "S.Atk", "sdef": "S.Def",
	"spd": "Spd", "acc": "Acc", "luck": "Luck", "resolve": "Resolve", "stamina": "Stamina"}

var db: Database
var _lines := PackedStringArray()


func _init() -> void:
	var result := DataLoader.load_database("res://data", "res://dialogue")
	if not result.ok():
		for e in result.errors:
			printerr(e)
		printerr("Content is invalid; compendium not generated.")
		quit(1)
		return
	db = result.db
	_build()
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("Wrote %s (%d lines)" % [OUT_PATH, _lines.size()])
	quit(0)


# --- Document ---------------------------------------------------------------

func _build() -> void:
	_w("# Content Compendium")
	_w("")
	_w("> Generated from `data/` by `tools/generate_compendium.gd`. Do not edit by hand;")
	_w("> change the JSON and regenerate.")
	_w("")
	_w("| Category | Count |")
	_w("|---|---|")
	for cat in ["creatures", "moves", "items", "statuses", "field_states", "reactions", "types",
			"affinities", "passives", "tamers", "encounters"]:
		_w("| [%s](#%s) | %d |" % [_title(cat), cat.replace("_", "-"), db.count(cat)])
	_w("")
	_types()
	_statuses()
	_field_states()
	_reactions()
	_affinities()
	_passives()
	_creatures()
	_moves()
	_items()
	_held_items()
	_tamers()
	_encounters()
	_balance()


func _types() -> void:
	var ids := Array(db.ids("types"))  # data order, so related types stay together
	var max_types := int(DataSchemas.ENTRY.creatures.types.max)
	var combos := ids.size()
	if max_types >= 2:
		combos += ids.size() * (ids.size() - 1) / 2
	var used := {}
	for cid in db.ids("creatures"):
		var key := " / ".join(Array(db.creature(cid).types).map(func(t): return db.type_def(t).name))
		used[key] = true
	_section("Types", "%d types. Creatures can have up to %d, giving %d possible single and dual types; %d are in use so far." % [
		ids.size(), max_types, combos, used.size()])
	_w("### Type guide")
	_w("")
	_w("*Pros* and *cons* are written in `data/types.json`. The matchup lines are computed from the chart below.")
	_w("")
	for id in ids:
		var t := db.type_def(id)
		_w("#### %s" % t.name)
		_w("")
		_w("*%s*" % t.description)
		_w("")
		_w("- **Pros:** %s" % "; ".join(t.pros))
		_w("- **Cons:** %s" % "; ".join(t.cons))
		_w("- **Hits hard:** %s" % _type_list(ids.filter(func(d): return t.multiplier_against(d) > 1.0)))
		_w("- **Hits weakly:** %s" % _type_list(ids.filter(func(d): return t.multiplier_against(d) > 0.0 and t.multiplier_against(d) < 1.0)))
		var no_effect := ids.filter(func(d): return t.multiplier_against(d) == 0.0)
		if not no_effect.is_empty():
			_w("- **No effect on:** %s" % _type_list(no_effect))
		_w("- **Weak to:** %s" % _type_list(ids.filter(func(a): return db.type_def(a).multiplier_against(id) > 1.0)))
		_w("- **Resists:** %s" % _type_list(ids.filter(func(a): var m := db.type_def(a).multiplier_against(id); return m > 0.0 and m < 1.0)))
		var immune := ids.filter(func(a): return db.type_def(a).multiplier_against(id) == 0.0)
		if not immune.is_empty():
			_w("- **Immune to:** %s" % _type_list(immune))
		var members := Array(db.ids("creatures")).filter(func(cid): return db.creature(cid).types.has(id))
		_w("- **Creatures:** %s" % _or_dash(", ".join(members.map(func(cid): return db.creature(cid).name))))
		_w("")
	_w("### Type chart")
	_w("")
	_w("Damage multiplier when the **row** type attacks the **column** type. Blank means x1.")
	_w("")
	var header := "| Attacker \\ Defender |"
	var rule := "|---|"
	for id in ids:
		header += " %s |" % db.type_def(id).name
		rule += "---|"
	_w(header)
	_w(rule)
	for a in ids:
		var row := "| **%s** |" % db.type_def(a).name
		for d in ids:
			var m := db.type_def(a).multiplier_against(d)
			row += " %s |" % ("" if m == 1.0 else "x" + _num(m))
		_w(row)
	_w("")


func _type_list(ids: Array) -> String:
	return _or_dash(", ".join(ids.map(func(t): return db.type_def(t).name)))


func _statuses() -> void:
	_section("Statuses", "Conditions on a single creature. Each lasts a set number of rounds.")
	_w("| Status | Id | Rounds | Effect | Description |")
	_w("|---|---|---|---|---|")
	for id in _sorted_ids("statuses"):
		var s := db.status(id)
		_w("| **%s** | `%s` | %d | %s | %s |" % [s.name, s.id, s.turns, _effects(s.effects), s.description])
	_w("")


func _field_states() -> void:
	_section("Field States",
		"Held per side (max %d at once). Passive effects apply to every creature on that side." % db.balance.max_field_states)
	_w("| State | Id | Max stacks | Default rounds | Passive | Reacts with |")
	_w("|---|---|---|---|---|---|")
	for id in _sorted_ids("field_states"):
		var f := db.field_state(id)
		var reacts := PackedStringArray()
		for rid in _sorted_ids("reactions"):
			var r := db.reaction(rid)
			if id in r.inputs:
				var other := r.inputs[1] if r.inputs[0] == id else r.inputs[0]
				reacts.append("%s → %s" % [db.field_state(other).name, r.name])
		_w("| **%s** | `%s` | %d | %d | %s | %s |" % [f.name, f.id, f.max_stacks, f.default_turns,
			_effects(f.passive), _or_dash(", ".join(reacts))])
	_w("")
	for id in _sorted_ids("field_states"):
		var f := db.field_state(id)
		if not f.description.is_empty():
			_w("- **%s:** %s" % [f.name, f.description])
	_w("")


func _reactions() -> void:
	_section("Reactions",
		"Fire immediately when an incoming state meets one already on that side. " +
		"\"All allies\" means every creature on the side where the reaction fired.")
	_w("| Reaction | Inputs | Consumes | Scope | Effects |")
	_w("|---|---|---|---|---|")
	for id in _sorted_ids("reactions"):
		var r := db.reaction(id)
		_w("| **%s** | %s + %s | %s | %s | %s |" % [r.name, _state_name(r.inputs[0]), _state_name(r.inputs[1]),
			", ".join(Array(r.consumes).map(_state_name)),
			"That side" if r.scope == "side" else "Both sides", _effects(r.effects)])
	_w("")
	for id in _sorted_ids("reactions"):
		var r := db.reaction(id)
		if not r.description.is_empty():
			_w("- **%s:** %s" % [r.name, r.description])
	_w("")


func _affinities() -> void:
	_section("Affinities", "Growth tracks filled by how a creature is used in battle. Growth branches need at least %d points in the matching track." % db.balance.growth_affinity_threshold)
	_w("| Affinity | Id | Grows from |")
	_w("|---|---|---|")
	for id in _sorted_ids("affinities"):
		var a := db.affinity(id)
		_w("| **%s** | `%s` | %s |" % [a.name, a.id, a.description])
	_w("")


func _passives() -> void:
	_section("Passives", "Each creature rolls one of its species' passives, and unlocks an Affinity passive at the growth threshold. " +
		"*Aura* passives apply their effects to every creature on the field's side. A `when` condition is shown in brackets.")
	_w("| Passive | Id | Scope | Effects | Triggers | Overworld | Species |")
	_w("|---|---|---|---|---|---|---|")
	for id in _sorted_ids("passives"):
		var p := db.passive(id)
		var species := PackedStringArray()
		for cid in _sorted_ids("creatures"):
			var c := db.creature(cid)
			if p.id in c.passives:
				species.append(c.name)
			elif p.id in c.affinity_passives.values():
				var track := ""
				for k in c.affinity_passives:
					if c.affinity_passives[k] == p.id:
						track = db.affinity(k).name
				species.append("%s (%s)" % [c.name, track])
		_w("| **%s** | `%s` | %s | %s | %s | %s | %s |" % [p.name, p.id, "Aura" if p.scope == "allies" else "Self",
			_effects(p.effects), _triggers(p.triggers), _effects(p.field), ", ".join(species)])
	_w("")
	for id in _sorted_ids("passives"):
		var p := db.passive(id)
		if not p.description.is_empty():
			_w("- **%s:** %s" % [p.name, p.description])
	_w("")


## "On being hit (physical) (30%) [HP below 50%]: effects; ..." or an em dash.
func _triggers(triggers: Array) -> String:
	var parts := PackedStringArray()
	for t in triggers:
		var s := "On %s" % TRIGGER_LABELS[t.on]
		if t.contact:
			s += " (physical)"
		if t.chance < 100:
			s += " (%d%%)" % t.chance
		if not t.when.is_empty():
			s += " [%s]" % _when(t.when)
		parts.append("%s: %s" % [s, _effects(t.effects)])
	return _or_dash("; ".join(parts))


func _held_items() -> void:
	_section("Held items", "One item per creature, given from the Summary screen. *Permanent* items stay held; " +
		"*Consumed* items are used up when they fire; *Per battle* items fire once each battle. " +
		"*Aura* items apply their effects to every creature on the holder's side. A `when` condition is shown in brackets.")
	_w("| Item | Id | Price | Use | Scope | Effects | Triggers | Overworld |")
	_w("|---|---|---|---|---|---|---|---|")
	var ids := _sorted_ids("items").filter(func(id): return db.item(id).held != null)
	for id in ids:
		var i := db.item(id)
		_w("| **%s** | `%s` | %d | %s | %s | %s | %s | %s |" % [i.name, i.id, i.price,
			i.held_use.replace("_", " ").capitalize(), "Aura" if i.held.scope == "allies" else "Self",
			_effects(i.held.effects), _triggers(i.held.triggers), _effects(i.held.field)])
	_w("")
	for id in ids:
		var i := db.item(id)
		if not i.description.is_empty():
			_w("- **%s:** %s" % [i.name, i.description])
	_w("")


func _creatures() -> void:
	_section("Creatures", "Base stats. *Total* sums the six battle stats (HP to Spd); Luck, Resolve and Stamina are listed separately.")
	var header := "| Creature | Types |"
	var rule := "|---|---|"
	for k in DataSchemas.BASE_STATS:
		header += " %s |" % STAT_LABELS[k]
		rule += "---|"
	_w(header + " Total | Catch | XP |")
	_w(rule + "---|---|---|")
	for id in _sorted_ids("creatures"):
		var c := db.creature(id)
		var bs := c.base_stats
		var row := "| [%s](#%s) | %s |" % [c.name, _anchor(c.name), _types_str(c.types)]
		for k in DataSchemas.BASE_STATS:
			row += " %d |" % bs[k]
		var total: int = bs.hp + bs.patk + bs.pdef + bs.satk + bs.sdef + bs.spd
		_w(row + " %d | %d%% | %d |" % [total, roundi(c.catch_rate * 100), c.xp_yield])
	_w("")
	var grows_from := {}
	for id in db.ids("creatures"):
		for g in db.creature(id).growth:
			if not grows_from.has(g.into):
				grows_from[g.into] = PackedStringArray()
			grows_from[g.into].append("%s (Lv %d, %s)" % [db.creature(id).name, g.level, _branch_rule(g)])
	for id in _sorted_ids("creatures"):
		var c := db.creature(id)
		_w("### %s" % c.name)
		_w("")
		_w("`%s` · %s" % [c.id, _types_str(c.types)])
		if not c.description.is_empty():
			_w("")
			_w("*%s*" % c.description)
		_w("")
		var parts := PackedStringArray()
		for k in DataSchemas.BASE_STATS:
			parts.append("%s %d" % [STAT_LABELS[k], c.base_stats[k]])
		_w("- **Base stats:** %s" % " · ".join(parts))
		_w("- **Catch rate:** %d%% base · **XP yield:** %d" % [roundi(c.catch_rate * 100), c.xp_yield])
		var tiers := PackedStringArray()
		for k in DataSchemas.BASE_STATS:
			if c.growth_tier(k) != "steady":
				tiers.append("%s %s" % [STAT_LABELS[k], c.growth_tier(k)])
		if not tiers.is_empty():
			_w("- **Growth:** %s" % ", ".join(tiers))
		_w("- **Lv %d stats:** %s" % [db.balance.level_cap, _stats_at_cap(c)])
		if grows_from.has(id):
			_w("- **Grows from:** %s" % ", ".join(grows_from[id]))
		if not c.growth.is_empty():
			var branches := PackedStringArray()
			for g in c.growth:
				branches.append("Lv %d → **%s** (%s)" % [g.level, db.creature(g.into).name, _branch_rule(g)])
			_w("- **Grows into:** %s" % "; ".join(branches))
		_w("")
		_w("| Lv | Move | Type | Cat. | Power | Cost | Acc |")
		_w("|---|---|---|---|---|---|---|")
		for l in c.learnset:
			var m := db.move(l.move)
			_w("| %d | %s | %s | %s | %s | %d | %s |" % [l.level, m.name, db.type_def(m.type).name,
				m.category.capitalize(), _power(m), m.cost, _acc(m)])
		_w("")


func _stats_at_cap(c: CreatureDef) -> String:
	var lv: int = db.balance.level_cap
	var parts := PackedStringArray()
	var total := 0
	for k in DataSchemas.BASE_STATS:
		var pct := db.balance.growth_percent(c.growth_tier(k))
		var v: int
		if k == "hp":
			v = Stats.hp_at(c.base_stats[k], lv, pct)
		elif k == "stamina":
			v = Stats.energy_at(c.base_stats[k], lv, db.balance.energy_cfg.base, pct)
		else:
			v = Stats.stat_at(c.base_stats[k], lv, pct)
		parts.append("%s %d" % [STAT_LABELS[k], v])
		if k in ["hp", "patk", "pdef", "satk", "sdef", "spd"]:
			total += v
	return "%s · Total %d" % [" · ".join(parts), total]


func _moves() -> void:
	_section("Moves", "Grouped by type. Physical moves use P.Atk vs P.Def; special moves use S.Atk vs S.Def. " +
		"*Cost* is energy spent. Effects run top to bottom; `bonus_if_field` modifiers apply to the damage or heal after them. " +
		"**%s** is always available, even without energy." % db.move(db.balance.energy_cfg.fallback_move).name)
	var learned_by := {}
	for cid in db.ids("creatures"):
		for l in db.creature(cid).learnset:
			if not learned_by.has(l.move):
				learned_by[l.move] = PackedStringArray()
			var n := db.creature(cid).name
			if not learned_by[l.move].has(n):
				learned_by[l.move].append(n)
	for tid in _sorted_ids("types"):
		var move_ids := _sorted_ids("moves").filter(func(mid): return db.move(mid).type == tid)
		if move_ids.is_empty():
			continue
		_w("### %s moves" % db.type_def(tid).name)
		_w("")
		_w("| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |")
		_w("|---|---|---|---|---|---|---|---|---|---|")
		for mid in move_ids:
			var m := db.move(mid)
			var who: PackedStringArray = learned_by.get(mid, PackedStringArray())
			who.sort()
			var effects := _effects(m.effects)
			if not m.description.is_empty():
				effects = "%s<br>*%s*" % [effects, m.description]
			var learners := ", ".join(who)
			if mid == db.balance.energy_cfg.fallback_move:
				learners = "Everyone (fallback)"
			_w("| **%s** | `%s` | %s | %s | %d | %s | %s | %s | %s | %s |" % [m.name, m.id, m.category.capitalize(),
				_power(m), m.cost, _acc(m), _signed(m.priority), TARGET_LABELS[m.target], effects, _or_dash(learners)])
		_w("")


func _items() -> void:
	_section("Items", "")
	_w("| Item | Id | Category | Price | Target | Effects | Description |")
	_w("|---|---|---|---|---|---|---|")
	for id in _sorted_ids("items"):
		var i := db.item(id)
		_w("| **%s** | `%s` | %s | %d | %s | %s | %s |" % [i.name, i.id, i.category.capitalize(), i.price,
			"—" if i.category == "held" else TARGET_LABELS.get(i.target, i.target), _effects(i.effects), i.description])
	_w("")


func _tamers() -> void:
	_section("Tamers", "NPC opponents. *Max active* is how many creatures they field at once.")
	for id in _sorted_ids("tamers"):
		var t := db.tamer(id)
		_w("### %s" % t.name)
		_w("")
		_w("`%s` · Max active **%d** · AI `%s` · Reward %d" % [t.id, t.max_active, t.ai, t.reward_money])
		_w("")
		_w("| Creature | Lv | Moves |")
		_w("|---|---|---|")
		for p in t.party:
			var moves: PackedStringArray = p.moves
			var note := ""
			if moves.is_empty():
				moves = db.creature(p.species).moves_up_to(p.level)
				moves = moves.slice(maxi(0, moves.size() - db.balance.max_moves))
				note = " *(latest learnset)*"
			var held := "" if p.held_item.is_empty() else " *(holds %s)*" % db.item(p.held_item).name
			_w("| %s | %d | %s%s%s |" % [db.creature(p.species).name, p.level,
				", ".join(Array(moves).map(func(mid): return db.move(mid).name)), note, held])
		if not t.items.is_empty():
			_w("")
			_w("**Items:** %s" % ", ".join(t.items.map(func(it): return "%s x%d" % [db.item(it.item).name, it.count])))
		_w("")


func _encounters() -> void:
	_section("Encounters", "Wild encounter tables. Chance is per creature in the pack.")
	for id in _sorted_ids("encounters"):
		var e := db.encounter(id)
		_w("### %s" % e.name)
		_w("")
		_w("`%s` · Pack size %d–%d" % [e.id, e.pack_min, e.pack_max])
		_w("")
		_w("| Creature | Chance | Levels |")
		_w("|---|---|---|")
		for row in e.table:
			_w("| %s | %s%% | %d–%d |" % [db.creature(row.species).name,
				_num(snappedf(100.0 * row.weight / e.total_weight, 0.1)), row.min_level, row.max_level])
		_w("")


func _balance() -> void:
	var b := db.balance
	_section("Balance", "Global tuning values from `data/balance.json`.")
	_w("| Setting | Value |")
	_w("|---|---|")
	_w("| Level cap | %d |" % b.level_cap)
	_w("| Party size | %d |" % b.party_size)
	_w("| Max moves per creature | %d |" % b.max_moves)
	_w("| Same-type attack bonus | x%s |" % _num(b.stab))
	_w("| Multi-target damage | x%s |" % _num(b.spread_mult))
	_w("| Round limit (draw) | %d |" % b.round_limit)
	_w("| XP formula | yield x level / %s, x%s vs tamers |" % [_num(b.xp_cfg.divisor), _num(b.xp_cfg.tamer_mult)])
	_w("| Catch status bonus | x%s |" % _num(b.catch_cfg.status_mult))
	_w("| Max field states per side | %d |" % b.max_field_states)
	_w("| Growth Affinity threshold | %d |" % b.growth_affinity_threshold)
	_w("| Underdog extra actions | floor(%s per ratio step) per creature |" % _num(b.underdog.bonus_actions_per_ratio))
	_w("| Underdog spread reduction | %s per ratio step, max %s |" % [_pct(b.underdog.spread_reduction_per_ratio), _pct(b.underdog.spread_reduction_cap)])
	_w("| Underdog stat bonus | %s per ratio step, max %s |" % [_pct(b.underdog.stat_bonus_per_ratio), _pct(b.underdog.stat_bonus_cap)])
	_w("| Underdog XP bonus | %s per ratio step |" % _pct(b.underdog.xp_bonus_per_ratio))
	_w("| Catch HP weight | %s |" % _num(b.catch_cfg.hp_weight))
	_w("| Resolve resist cap | %s (average creature: half that) |" % _pct(b.resolve_cfg.resist_cap))
	_w("| Resolve endure cap | %s, once per battle |" % _pct(b.resolve_cfg.endure_cap))
	_w("| Energy pool | 2 x base Stamina x Lv / 100 + %d |" % b.energy_cfg.base)
	_w("| Rest restores | %s of max energy |" % _pct(b.energy_cfg.rest_fraction))
	_w("| Training points | %d per level, max %d per stat, +%d HP per point |" % [
		b.training_cfg.points_per_level, b.training_cfg.max_per_stat, b.training_cfg.hp_per_point])
	_w("")
	var bc := b.bond_cfg
	_w("### Bond")
	_w("")
	_w("Range %d to %d; starters begin at %d." % [bc.min, bc.max, bc.starter])
	_w("")
	_w("| Effect | At most |")
	_w("|---|---|")
	_w("| Disobey chance (negative Bond) | %s at %d |" % [_pct(bc.disobey_max_chance), bc.min])
	_w("| Accuracy and damage penalty | %s at %d |" % [_pct(bc.penalty_max), bc.min])
	_w("| Lash out chance | %s at %d or below |" % [_pct(bc.lash_out_chance), bc.lash_out_threshold])
	_w("| XP bonus (positive Bond) | %s at %d |" % [_pct(bc.xp_bonus_max), bc.max])
	_w("")
	_w("| Happening | Bond |")
	_w("|---|---|")
	for key in DataSchemas.BOND_EVENTS:
		if bc.changes.has(key):
			_w("| %s | %s |" % [key.replace("_", " ").capitalize(), _signed(bc.changes[key])])
	_w("")
	_w("### Affinity awards")
	_w("")
	_w("| Happening | Affinity | Points |")
	_w("|---|---|---|")
	for key in DataSchemas.AFFINITY_EVENTS:
		if b.affinity_awards.has(key):
			var a: Dictionary = b.affinity_awards[key]
			_w("| %s | %s | %d |" % [key.replace("_", " ").capitalize(), db.affinity(a.affinity).name, a.points])
	_w("")


# --- Effect descriptions ----------------------------------------------------

func _effects(effects: Array) -> String:
	if effects.is_empty():
		return "—"
	return "; ".join(effects.map(_effect))


func _effect(e: Dictionary) -> String:
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
			s = "Loses %s max HP each round" % _pct(e.fraction)
		"reset_training":
			s = "Returns all spent training points (field use only)"
		"skip_chance":
			s = "%d%% chance to lose its action" % e.chance
		"heal":
			s = "Heals %s max HP" % _pct(e.fraction)
		"apply_status":
			s = "Inflicts %s" % db.status(e.status).name
			if e.has("chance"):
				s += " (%d%%)" % e.chance
		"apply_field_state":
			s = "Applies %s to %s" % [_state_name(e.state), SIDE_LABELS[e.side]]
			var extra := PackedStringArray()
			if e.has("stacks"):
				extra.append("%d stacks" % e.stacks)
			if e.has("turns"):
				extra.append("%d rounds" % e.turns)
			if not extra.is_empty():
				s += " (%s)" % ", ".join(extra)
		"remove_field_state":
			s = "Clears %s from %s" % [_state_name(e.state) if e.has("state") else "all states", SIDE_LABELS[e.side]]
		"bonus_if_field":
			s = "x%s if %s is %s" % [_num(e.mult), SIDE_LABELS[e.side], _state_name(e.state)]
			if e.get("consume", false):
				s += " (consumes it)"
		"stat_stage":
			s = "%s %s" % [STAT_LABELS[e.stat], _signed(e.stages)]
		"stat_mod":
			s = "%s x%s" % [STAT_LABELS[e.stat], _num(e.mult)]
		"incoming_type_mod":
			s = "%s damage taken x%s" % [db.type_def(e.type).name if e.has("type") else "All", _num(e.mult)]
		"type_power":
			s = "%s moves x%s" % [db.type_def(e.type).name, _num(e.mult)]
		"absorb_type":
			s = "%s damage heals %s max HP instead" % [db.type_def(e.type).name, _pct(e.fraction)]
		"status_immune":
			s = "Can't be %s" % ("given %s" % db.status(e.status).name if e.has("status") else "given a status")
		"guard_stages":
			s = "Foes can't lower its %s" % (STAT_LABELS[e.stat] if e.has("stat") else "stats")
		"field_shelter":
			s = "Sheltered from %s" % _state_name(e.state)
		"field_boost":
			var extra := PackedStringArray()
			if e.has("stacks"):
				extra.append("+%d stack(s)" % e.stacks)
			if e.has("turns"):
				extra.append("+%d round(s)" % e.turns)
			s = "Its field states get %s" % " and ".join(extra)
		"reaction_power":
			s = "Reactions it triggers x%s" % _num(e.mult)
		"energy_discount":
			s = "%s moves cost %d less" % [db.type_def(e.type).name if e.has("type") else "All", e.amount]
		"rest_bonus":
			s = "Rest restores +%s max energy" % _pct(e.fraction)
		"scrap_power":
			s = "Scrap x%s" % _num(e.mult)
		"encounter_rate":
			s = "Wild encounter rate x%s" % _num(e.mult)
		"xp_mult":
			s = "XP earned x%s" % _num(e.mult)
		"bond_gain":
			s = "Bond gains x%s" % _num(e.mult)
		"restore_energy":
			s = "Restores %s max energy" % _pct(e.fraction)
		"capture":
			s = "Capture x%s" % _num(e.mult)
			var bonus: Dictionary = e.get("field_bonus", {})
			for st in bonus:
				s += ", x%s on %s" % [_num(bonus[st]), _state_name(st)]
		_:
			s = e.op
	if e.has("when"):
		s += " [%s]" % _when(e.when)
	if e.has("target"):
		s += " → %s" % TARGET_LABELS[e.target].to_lower()
	return s


func _when(w: Dictionary) -> String:
	var parts := PackedStringArray()
	if w.has("hp_below"):
		parts.append("HP below %s" % _pct(w.hp_below))
	if w.get("underdog", false):
		parts.append("outnumbered")
	if w.has("field"):
		parts.append("%s on %s" % [_state_name(w.field), SIDE_LABELS[w.side]])
	return ", ".join(parts)


# --- Helpers ----------------------------------------------------------------

func _w(line: String) -> void:
	_lines.append(line)


func _section(title: String, blurb: String) -> void:
	_w("## %s" % title)
	_w("")
	if not blurb.is_empty():
		_w(blurb)
		_w("")


func _sorted_ids(cat: String) -> Array:
	var ids := Array(db.ids(cat))
	ids.sort_custom(func(a, b): return db.get_def(cat, a).name.naturalnocasecmp_to(db.get_def(cat, b).name) < 0)
	return ids


func _title(cat: String) -> String:
	return cat.replace("_", " ").capitalize()


func _anchor(heading: String) -> String:
	return heading.to_lower().replace(" ", "-")


func _types_str(types: PackedStringArray) -> String:
	return " / ".join(Array(types).map(func(t): return db.type_def(t).name))


func _state_name(id: String) -> String:
	return db.field_state(id).name


func _branch_rule(g: Dictionary) -> String:
	return "default" if g.default else "%s Affinity" % db.affinity(g.affinity).name


func _power(m: MoveDef) -> String:
	return "—" if m.power == 0 else str(m.power)


func _acc(m: MoveDef) -> String:
	return "—" if m.always_hits else "%d%%" % m.accuracy


func _signed(n: int) -> String:
	return "+%d" % n if n > 0 else str(n)


func _num(f: float) -> String:
	return str(int(f)) if f == floorf(f) else str(f)


func _pct(f: float) -> String:
	return "%s%%" % _num(snappedf(f * 100.0, 0.01))


func _or_dash(s: String) -> String:
	return "—" if s.is_empty() else s
