class_name CompendiumBuilder
extends RefCounted
## Builds the text of documentation/compendium.md from a loaded Database.
## Pure: no file access. tools/generate_compendium.gd writes the result.

## Section headings in reading order (spec 2026-11-05-m5a-housekeeping-design §5.2). Rules come
## first because everything after refers to them.
const SECTIONS: Array[String] = ["Rules and Balance", "Types", "Affinities", "Statuses", "Field States",
	"Reactions", "Passives", "Held items", "Moves", "Items", "Creatures", "Tamers", "Encounters", "Achievements"]
const RULES := "Rules and Balance"

var db: Database
var _lines := PackedStringArray()


## The whole document, ending in exactly one newline.
static func build(database: Database) -> String:
	var builder := CompendiumBuilder.new()
	builder.db = database
	builder._build()
	while not builder._lines.is_empty() and builder._lines[builder._lines.size() - 1].is_empty():
		builder._lines.remove_at(builder._lines.size() - 1)
	return "\n".join(builder._lines) + "\n"


func _build() -> void:
	_w("# Content Compendium")
	_w("")
	_w("> Generated from `data/` by `tools/generate_compendium.gd`. Do not edit by hand;")
	_w("> change the JSON and regenerate.")
	_w("")
	_w("| Section | Count |")
	_w("|---|---|")
	for title: String in SECTIONS:
		_w("| %s | %s |" % [_link(title), _section_count(title)])
	_w("")
	_rules()
	_types()
	_affinities()
	_statuses()
	_field_states()
	_reactions()
	_passives()
	_held_items()
	_moves()
	_items()
	_creatures()
	_tamers()
	_encounters()
	_achievements()


## A contents-table count: entries in the section, or an em dash for Rules and Balance.
func _section_count(title: String) -> String:
	var held: int = _held_ids().size()
	match title:
		RULES:
			return "—"
		"Held items":
			return str(held)
		"Items":
			return str(db.count("items") - held)
	return str(db.count(title.to_lower().replace(" ", "_")))


func _held_ids() -> Array:
	return _sorted_ids("items").filter(func(id: String) -> bool: return db.item(id).category == "held")


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
		_w("- **Creatures:** %s" % EffectText.or_dash(", ".join(members.map(func(cid): return db.creature(cid).name))))
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
			row += " %s |" % ("" if m == 1.0 else "x" + EffectText.num(m))
		_w(row)
	_w("")


func _type_list(ids: Array) -> String:
	return EffectText.or_dash(", ".join(ids.map(func(t): return db.type_def(t).name)))


func _statuses() -> void:
	_section("Statuses", "Conditions on a single creature. Each lasts a set number of rounds.")
	_w("| Status | Id | Rounds | Effect | Description |")
	_w("|---|---|---|---|---|")
	for id in _sorted_ids("statuses"):
		var s := db.status(id)
		_w("| **%s** | `%s` | %d | %s | %s |" % [s.name, s.id, s.turns, EffectText.effects(db, s.effects), s.description])
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
			EffectText.effects(db, f.passive), EffectText.or_dash(", ".join(reacts))])
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
		_w("| **%s** | %s + %s | %s | %s | %s |" % [r.name, EffectText.state_name(db, r.inputs[0]), EffectText.state_name(db, r.inputs[1]),
			", ".join(Array(r.consumes).map(func(s: String) -> String: return EffectText.state_name(db, s))),
			"That side" if r.scope == "side" else "Both sides", EffectText.effects(db, r.effects)])
	_w("")
	for id in _sorted_ids("reactions"):
		var r := db.reaction(id)
		if not r.description.is_empty():
			_w("- **%s:** %s" % [r.name, r.description])
	_w("")


func _affinities() -> void:
	_section("Affinities", ("Growth tracks filled by how a creature is used in battle (points per happening are in %s). " +
		"Growth branches need at least %d points in the matching track, and the first track to reach %d unlocks " +
		"the species' Affinity passive for that track (see %s).") % [_link(RULES),
		db.balance.growth_affinity_threshold, db.balance.growth_affinity_threshold, _link("Passives")])
	_w("| Affinity | Id | Grows from |")
	_w("|---|---|---|")
	for id in _sorted_ids("affinities"):
		var a := db.affinity(id)
		_w("| **%s** | `%s` | %s |" % [a.name, a.id, a.description])
	_w("")


func _passives() -> void:
	_section("Passives", ("Every creature has two passive slots. Its *rolled* passive is picked at random from its species' list " +
		"(*Species* shows the name alone); its *Affinity* passive unlocks when its first Affinity track reaches %d points " +
		"(*Species* shows the track in brackets). Only the active slot works; the player picks it on the Summary screen. " +
		"*Self* passives' effects apply only to their holder; *Aura* passives apply their effects to every active creature on the holder's side " +
		"(the same aura does not stack). A trigger reads *On event (physical) (chance) [when]*: (physical) means only physical " +
		"moves set it off, the percentage is its chance to fire, and it is skipped when it would only heal or restore a creature that is already full. " +
		"*Overworld* effects apply while the creature leads the party (first in the party, fainted or not). A `when` condition is shown in brackets.") %
		db.balance.growth_affinity_threshold)
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
			EffectText.effects(db, p.effects), EffectText.triggers(db, p.triggers), EffectText.effects(db, p.field), ", ".join(species)])
	_w("")
	for id in _sorted_ids("passives"):
		var p := db.passive(id)
		if not p.description.is_empty():
			_w("- **%s:** %s" % [p.name, p.description])
	_w("")


func _held_items() -> void:
	_section("Held items", ("One item per creature, given and taken back on the Summary screen. *Use*: *Permanent* items stay held; " +
		"*Consumed* items are used up the first time they fire; *Per battle* items fire once each battle. " +
		"*Scope*: *Self* items' effects apply only to their holder; *Aura* items apply their effects to every active creature on the holder's side " +
		"(the same item does not stack). Triggers read as for %s, and run after the holder's passive. " +
		"*Overworld* effects apply while the holder leads the party (first in the party, fainted or not). A `when` condition is shown in brackets.") % _link("Passives"))
	_w("| Item | Id | Price | Use | Scope | Effects | Triggers | Overworld |")
	_w("|---|---|---|---|---|---|---|---|")
	var ids: Array = _held_ids()
	for id: String in ids:
		var i: ItemDef = db.item(id)
		var use: String = i.held_use.replace("_", " ")
		_w("| **%s** | `%s` | %d | %s | %s | %s | %s | %s |" % [i.name, i.id, i.price,
			use.left(1).to_upper() + use.substr(1), "Aura" if i.held.scope == "allies" else "Self",
			EffectText.effects(db, i.held.effects), EffectText.triggers(db, i.held.triggers), EffectText.effects(db, i.held.field)])
	_w("")
	for id: String in ids:
		var i: ItemDef = db.item(id)
		if not i.description.is_empty():
			_w("- **%s:** %s" % [i.name, i.description])
	_w("")


func _creatures() -> void:
	var tiered: int = Array(db.ids("creatures")).filter(func(cid: String) -> bool:
		return not db.creature(cid).growth_rates.is_empty()).size()
	_section("Creatures", ("Base stats. *Total* sums the six battle stats (HP to Spd); Luck, Resolve and Stamina are listed separately. " +
		"A **Growth** line lists any stat that grows faster or slower than steady (tier multipliers in %s); " +
		"%s. *Lv %d stats* are untrained, with each stat's growth tier applied.") % [_link(RULES),
		"no species has one yet, so every stat grows at the steady rate" if tiered == 0 else
		"%d of %d species have one" % [tiered, db.count("creatures")], db.balance.level_cap])
	var header := "| Creature | Types |"
	var rule := "|---|---|"
	for k in DataSchemas.BASE_STATS:
		header += " %s |" % EffectText.STAT_LABELS[k]
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
			parts.append("%s %d" % [EffectText.STAT_LABELS[k], c.base_stats[k]])
		_w("- **Base stats:** %s" % " · ".join(parts))
		_w("- **Catch rate:** %d%% base · **XP yield:** %d" % [roundi(c.catch_rate * 100), c.xp_yield])
		var tiers := PackedStringArray()
		for k in DataSchemas.BASE_STATS:
			if c.growth_tier(k) != "steady":
				tiers.append("%s %s" % [EffectText.STAT_LABELS[k], c.growth_tier(k)])
		if not tiers.is_empty():
			_w("- **Growth:** %s" % ", ".join(tiers))
		_w("- **Lv %d stats:** %s" % [db.balance.level_cap, _stats_at_cap(c)])
		var found := Locations.for_species(db, id).map(func(r: Dictionary) -> String: return Locations.line(r))
		_w("- **Found:** %s" % ("; ".join(found) if not found.is_empty() else "Not found in the wild"))
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
		parts.append("%s %d" % [EffectText.STAT_LABELS[k], v])
		if k in ["hp", "patk", "pdef", "satk", "sdef", "spd"]:
			total += v
	return "%s · Total %d" % [" · ".join(parts), total]


func _moves() -> void:
	_section("Moves", ("Grouped by type. Physical moves use P.Atk vs P.Def; special moves use S.Atk vs S.Def. " +
		"*Cost* is energy spent (some passives lower it). *Pri* is turn-order priority: higher acts first, then the faster creature. " +
		"Moves that hit more than one creature deal less to each; turn order, energy and the multi-target table are in %s. " +
		"Effects run top to bottom; `bonus_if_field` modifiers apply to the damage or heal after them. " +
		"**%s** is always available, even without energy.") % [_link(RULES), db.move(db.balance.energy_cfg.fallback_move).name])
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
			var effects := EffectText.effects(db, m.effects)
			if m.is_multi_hit():
				effects = "%s; %s" % [EffectText.hits_label(m), effects]
			if not m.description.is_empty():
				effects = "%s<br>*%s*" % [effects, m.description]
			var learners := ", ".join(who)
			if mid == db.balance.energy_cfg.fallback_move:
				learners = "Everyone (fallback)"
			_w("| **%s** | `%s` | %s | %s | %d | %s | %s | %s | %s | %s |" % [m.name, m.id, m.category.capitalize(),
				_power(m), m.cost, _acc(m), EffectText.signed(m.priority), EffectText.TARGET_LABELS[m.target], effects, EffectText.or_dash(learners)])
		_w("")


func _items() -> void:
	_section("Items", "Bag items, used from the bag in battle or on the field. Held items are listed under %s." % _link("Held items"))
	_w("| Item | Id | Category | Price | Target | Effects | Description |")
	_w("|---|---|---|---|---|---|---|")
	for id: String in _sorted_ids("items"):
		var i: ItemDef = db.item(id)
		if i.category == "held":
			continue
		_w("| **%s** | `%s` | %s | %d | %s | %s | %s |" % [i.name, i.id, i.category.capitalize(), i.price,
			EffectText.TARGET_LABELS.get(i.target, i.target), EffectText.effects(db, i.effects), i.description])
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
				EffectText.num(snappedf(100.0 * row.weight / e.total_weight, 0.1)), row.min_level, row.max_level])
		_w("")


func _achievements() -> void:
	_section("Achievements", "Unlocked by play and shown in the Achievements screen. A hidden one reads \"???\" there until it is earned.")
	_w("| Achievement | Id | Needs |")
	_w("|---|---|---|")
	for id in db.ids("achievements"):
		var a := db.achievement(id)
		_w("| **%s**%s | `%s` | %s |" % [a.name, " (hidden)" if a.hidden else "", a.id, _criterion_text(a.criterion)])
	_w("")


## The criterion in words, from its fields only.
func _criterion_text(c: Dictionary) -> String:
	match str(c.get("kind")):
		"counter":
			return "%d %s" % [int(c.target), str(c.stat).replace("_", " ")]
		"codex":
			match str(c.mode):
				"species":
					return "%s caught" % db.creature(str(c.species)).name
				"caught":
					return "every species caught" if c.get("all", false) else "%d species caught" % int(c.target)
			return "every species seen" if c.get("all", false) else "%d species seen" % int(c.target)
		"flag":
			return "story flag `%s`" % c.flag
		"creature":
			match str(c.what):
				"level":
					return "a creature at level %d" % int(c.target)
				"bond":
					return "a creature at Bond %d" % int(c.target)
			return "%d creature(s) evolved" % int(c.target)
	return ""


func _rules() -> void:
	var b := db.balance
	_section(RULES, "Global rules and tuning values from `data/balance.json`. The sections after this one refer to them.")
	_w("| Setting | Value |")
	_w("|---|---|")
	_w("| Level cap | %d |" % b.level_cap)
	_w("| Party size | %d |" % b.party_size)
	_w(("| Battle format | Up to %d active a side; in tamer battles the tamer's *Max active* sets it and the player may field fewer; " +
		"in wild battles the pack size sets the foe side |") % _max_active())
	_w("| Max moves per creature | %d |" % b.max_moves)
	_w("| Turn order | Fleeing (wild battles only), then swaps, then items, then moves by *Pri* (higher first, default 0); ties go to the faster creature, then at random |")
	_w("| Same-type attack bonus | x%s |" % EffectText.num(b.stab))
	_w("| Round limit (draw) | %d |" % b.round_limit)
	_w("| XP formula | yield x level / %s, x%s vs tamers |" % [EffectText.num(b.xp_cfg.divisor), EffectText.num(b.xp_cfg.tamer_mult)])
	_w("| Catch status bonus | x%s |" % EffectText.num(b.catch_cfg.status_mult))
	_w("| Max field states per side | %d |" % b.max_field_states)
	_w("| Growth Affinity threshold | %d |" % b.growth_affinity_threshold)
	_w("| Growth tiers | %s on a stat's per-level growth |" % _growth_tiers_str())
	_w("| Growth tier budget | %d (each faster stat counts +1, each slower one -1) |" % b.growth_budget)
	_w("| Catch HP weight | %s |" % EffectText.num(b.catch_cfg.hp_weight))
	_w("| Resolve resist cap | %s (average creature: half that) |" % EffectText.pct(b.resolve_cfg.resist_cap))
	_w("| Resolve endure cap | %s, once per battle |" % EffectText.pct(b.resolve_cfg.endure_cap))
	_w("| Energy pool | 2 x base Stamina x Lv / 100 + %d |" % b.energy_cfg.base)
	_w("| Rest restores | %s of max energy |" % EffectText.pct(b.energy_cfg.rest_fraction))
	_w("| Training points | %d per level, max %d per stat, +%d HP per point |" % [
		b.training_cfg.points_per_level, b.training_cfg.max_per_stat, b.training_cfg.hp_per_point])
	_w("")
	_w("### Multi-target damage")
	_w("")
	_w("A move that hits more than one creature deals less to each. *Two foes* moves hit two foes the user picks " +
		"(one foe left standing takes full damage); *All enemies*, *All allies* and *Everyone* count every creature they hit. " +
		"An outnumbered side takes less of it (see %s)." % _link("Underdog"))
	_w("")
	_w("| Creatures hit | Damage to each |")
	_w("|---|---|")
	_w("| 1 | x1 |")
	_w("| 2 | x%s |" % EffectText.num(b.spread_mult_for(2)))
	_w("| 3 or more | x%s |" % EffectText.num(b.spread_mult_for(3)))
	_w("")
	_underdog()
	_bond_and_awards()


## Underdog: the rule in words, then the numbers for every uneven format, from Underdog.compute.
func _underdog() -> void:
	var u: Dictionary = db.balance.underdog
	var stats: Array = BattleMath.UNDERDOG_STATS.map(func(s: String) -> String: return EffectText.STAT_LABELS[s])
	_w("### Underdog")
	_w("")
	_w(("A side is *outnumbered* when the foes have more creatures active. Its *step* is foes active / own active - 1 " +
		"(1 vs 2 is 1, 1 vs 3 is 2). Per step it gets %s extra actions per creature each round (rounded down), " +
		"%s %s (max %s), %s less spread damage taken (max %s) and, on the player's side, %s more XP. " +
		"Passive `when` conditions that say *outnumbered* test the same rule.") % [
		EffectText.num(u.bonus_actions_per_ratio), ", ".join(stats), "+" + EffectText.pct(u.stat_bonus_per_ratio),
		EffectText.pct(u.stat_bonus_cap), EffectText.pct(u.spread_reduction_per_ratio), EffectText.pct(u.spread_reduction_cap),
		EffectText.pct(u.xp_bonus_per_ratio)])
	_w("")
	_w("| Format | Step | Extra actions | Stat bonus | Spread damage taken | XP bonus |")
	_w("|---|---|---|---|---|---|")
	for own: int in range(1, _max_active() + 1):
		for foes: int in range(own + 1, _max_active() + 1):
			var r: Dictionary = Underdog.compute(db.balance, own, foes)
			_w("| %d vs %d | %s | %d | +%s | -%s | +%s |" % [own, foes, EffectText.num(r.ratio - 1.0), r.bonus_actions,
				EffectText.pct(r.stat_bonus), EffectText.pct(r.spread_reduction), EffectText.pct(r.xp_bonus)])
	_w("")


## "Slow x0.8, Steady x1, Fast x1.2": the tiers from slowest to fastest.
func _growth_tiers_str() -> String:
	var tiers: Array = db.balance.growth_tiers.keys()
	tiers.sort_custom(func(a: String, c: String) -> bool:
		return float(db.balance.growth_tiers[a]) < float(db.balance.growth_tiers[c]))
	return ", ".join(tiers.map(func(t: String) -> String:
		return "%s x%s" % [t.capitalize(), EffectText.num(db.balance.growth_tiers[t])]))


## Most creatures a side can have active (the schema ceiling for a tamer's max_active).
func _max_active() -> int:
	return int(DataSchemas.ENTRY.tamers.max_active.max)


func _bond_and_awards() -> void:
	var b := db.balance
	var bc := b.bond_cfg
	_w("### Bond")
	_w("")
	_w("Range %d to %d; starters begin at %d." % [bc.min, bc.max, bc.starter])
	_w("")
	_w("| Effect | At most |")
	_w("|---|---|")
	_w("| Disobey chance (negative Bond) | %s at %d |" % [EffectText.pct(bc.disobey_max_chance), bc.min])
	_w("| Accuracy and damage penalty | %s at %d |" % [EffectText.pct(bc.penalty_max), bc.min])
	_w("| Lash out chance | %s at %d or below |" % [EffectText.pct(bc.lash_out_chance), bc.lash_out_threshold])
	_w("| XP bonus (positive Bond) | %s at %d |" % [EffectText.pct(bc.xp_bonus_max), bc.max])
	_w("")
	_w("| Happening | Bond |")
	_w("|---|---|")
	for key in DataSchemas.BOND_EVENTS:
		if bc.changes.has(key):
			_w("| %s | %s |" % [key.replace("_", " ").capitalize(), EffectText.signed(bc.changes[key])])
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


## GitHub's heading anchor: lower case, punctuation dropped, spaces to hyphens.
func _anchor(heading: String) -> String:
	var re: RegEx = RegEx.create_from_string("[^a-z0-9 _-]")
	return re.sub(heading.to_lower(), "", true).replace(" ", "-")


## A markdown link to a heading in this document.
func _link(heading: String) -> String:
	return "[%s](#%s)" % [heading, _anchor(heading)]


func _types_str(types: PackedStringArray) -> String:
	return " / ".join(Array(types).map(func(t): return db.type_def(t).name))


func _branch_rule(g: Dictionary) -> String:
	return "default" if g.default else "%s Affinity" % db.affinity(g.affinity).name


func _power(m: MoveDef) -> String:
	return "—" if m.power == 0 else str(m.power)


func _acc(m: MoveDef) -> String:
	return "—" if m.always_hits else "%d%%" % m.accuracy
