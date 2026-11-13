extends GdUnitTestSuite
## The generated compendium (CompendiumBuilder over the real data/): section order, the
## contents table, the held/non-held item split, test-pack exclusion and the rules text
## the other sections rely on (spec 2026-11-05-m5a-housekeeping-design §5).

const SECTIONS: Array[String] = ["Rules and Balance", "Types", "Affinities", "Statuses", "Field States",
	"Reactions", "Passives", "Held items", "Moves", "Items", "Creatures", "AI Styles", "Tamers", "Encounters", "Achievements"]
## The contents row for Rules and Balance has no count: it is a settings page, not a list.
const NO_COUNT := "—"

var _db: Database
var _text: String


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data")
	assert_bool(result.ok()).is_true()
	_db = result.db
	_text = CompendiumBuilder.build(_db)


# --- Helpers ------------------------------------------------------------------

func _lines() -> PackedStringArray:
	return _text.split("\n")


## The text of `## title` up to the next `## ` heading ("" if missing).
func _section(title: String) -> String:
	var start: int = _text.find("\n## %s\n" % title)
	if start < 0:
		return ""
	var end: int = _text.find("\n## ", start + 1)
	return _text.substr(start, (end if end >= 0 else _text.length()) - start)


## GitHub's heading anchor: lower case, punctuation dropped, spaces to hyphens.
func _anchor(heading: String) -> String:
	var re: RegEx = RegEx.create_from_string("[^a-z0-9 _-]")
	return re.sub(heading.to_lower(), "", true).replace(" ", "-")


## Every heading anchor in the document, with GitHub's -1, -2 suffixes for repeats.
func _all_anchors() -> Dictionary:
	var seen: Dictionary = {}
	var out: Dictionary = {}
	for line: String in _lines():
		if not line.begins_with("#"):
			continue
		var base: String = _anchor(line.lstrip("#").strip_edges())
		var n: int = int(seen.get(base, 0))
		out[base if n == 0 else "%s-%d" % [base, n]] = true
		seen[base] = n + 1
	return out


## Contents rows before the first section: [title, anchor, count].
func _contents_rows() -> Array[PackedStringArray]:
	var re: RegEx = RegEx.create_from_string("^\\| \\[(.+)\\]\\(#(.+)\\) \\| (.+) \\|$")
	var out: Array[PackedStringArray] = []
	for line: String in _lines():
		if line.begins_with("## "):
			break
		var m: RegExMatch = re.search(line)
		if m != null:
			out.append(PackedStringArray([m.get_string(1), m.get_string(2), m.get_string(3)]))
	return out


func _held_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _db.ids("items"):
		if _db.item(id).category == "held":
			out.append(id)
	return out


func _expected_count(title: String) -> String:
	var held: int = _held_ids().size()
	match title:
		"Rules and Balance":
			return NO_COUNT
		"Held items":
			return str(held)
		"Items":
			return str(_db.count("items") - held)
	return str(_db.count(title.to_lower().replace(" ", "_")))


# --- Layout -------------------------------------------------------------------

func test_sections_appear_once_in_the_agreed_order() -> void:
	var found: Array[String] = []
	for line: String in _lines():
		if line.begins_with("## "):
			found.append(line.substr(3))
	assert_array(found).is_equal(SECTIONS)


func test_contents_table_lists_every_section_with_a_matching_anchor() -> void:
	var rows: Array[PackedStringArray] = _contents_rows()
	var titles: Array[String] = []
	for row: PackedStringArray in rows:
		titles.append(row[0])
		assert_str(row[1]).is_equal(_anchor(row[0]))
		assert_bool(_text.contains("\n## %s\n" % row[0])) \
			.override_failure_message("no heading for contents row %s" % row[0]).is_true()
	assert_array(titles).is_equal(SECTIONS)
	assert_str(_anchor("Rules and Balance")).is_equal("rules-and-balance")
	assert_str(_anchor("Held items")).is_equal("held-items")


func test_counts_match_database() -> void:
	for row: PackedStringArray in _contents_rows():
		assert_str(row[2]).override_failure_message("count for %s" % row[0]).is_equal(_expected_count(row[0]))


func test_every_in_document_link_resolves() -> void:
	var anchors: Dictionary = _all_anchors()
	var re: RegEx = RegEx.create_from_string("\\]\\(#([^)]+)\\)")
	var links: Array[RegExMatch] = re.search_all(_text)
	assert_bool(links.is_empty()).is_false()
	for m: RegExMatch in links:
		assert_bool(anchors.has(m.get_string(1))) \
			.override_failure_message("link to missing anchor #%s" % m.get_string(1)).is_true()


func test_achievements_section_lists_every_achievement_once_and_marks_the_hidden_one() -> void:
	var section: String = _section("Achievements")
	assert_str(section).is_not_empty()
	for id: String in _db.ids("achievements"):
		assert_int(section.count("`%s`" % id)).override_failure_message("achievement %s" % id).is_equal(1)
	var hidden_row := ""
	for line: String in section.split("
"):
		if line.contains("`quick_on_the_draw`"):
			hidden_row = line
	assert_str(hidden_row).contains("(hidden)")
	assert_str(section).contains("500 steps")


func test_items_table_has_no_held_items() -> void:
	var items: String = _section("Items")
	assert_str(items).is_not_empty()
	for id: String in _held_ids():
		assert_bool(items.contains("`%s`" % id)).override_failure_message("held item %s in Items" % id).is_false()
	for id: String in _db.ids("items"):
		if _db.item(id).category != "held":
			assert_bool(items.contains("`%s`" % id)).override_failure_message("missing item %s" % id).is_true()


func test_every_held_item_is_in_held_items() -> void:
	var held: String = _section("Held items")
	assert_bool(_held_ids().is_empty()).is_false()
	for id: String in _held_ids():
		assert_bool(held.contains("| `%s` |" % id)).override_failure_message("held item %s missing" % id).is_true()


func test_no_test_pack_ids() -> void:
	assert_bool(_text.contains("tp_")).is_false()
	assert_bool(_text.contains("data_testpack")).is_false()


func test_ends_with_one_newline() -> void:
	assert_bool(_text.ends_with("\n")).is_true()
	assert_bool(_text.ends_with("\n\n")).is_false()


func test_builder_output_is_deterministic() -> void:
	var first: String = CompendiumBuilder.build(_db)
	assert_bool(first.is_empty()).is_false()
	assert_str(CompendiumBuilder.build(_db)).is_equal(first)


# --- Systems checklist (spec §5.3) --------------------------------------------

func test_rules_cover_level_cap_and_party_size() -> void:
	var rules: String = _section("Rules and Balance")
	assert_str(rules).contains("| Level cap | %d |" % _db.balance.level_cap)
	assert_str(rules).contains("| Party size | %d |" % _db.balance.party_size)
	assert_str(rules).contains("in tamer battles the tamer's *Max active* sets it")
	assert_str(rules).contains("in wild battles the pack size sets the foe side")


func test_rules_list_growth_tiers_and_budget() -> void:
	var rules: String = _section("Rules and Balance")
	for tier: String in _db.balance.growth_tiers:
		assert_str(rules).contains("%s x%s" % [tier.capitalize(), EffectText.num(_db.balance.growth_tiers[tier])])
	assert_str(rules).contains("| Growth tier budget | %d " % _db.balance.growth_budget)


func test_rules_explain_turn_order_and_priority() -> void:
	var rules: String = _section("Rules and Balance")
	assert_str(rules).contains("| Turn order | Fleeing (wild battles only), then swaps")
	assert_str(rules).contains("*Pri*")
	assert_str(_section("Moves")).contains("*Pri*")


func test_rules_spread_table_covers_two_foes() -> void:
	var rules: String = _section("Rules and Balance")
	assert_str(rules).contains("### Multi-target damage")
	assert_str(rules).contains("*Two foes*")
	assert_str(rules).contains("(see [Underdog](#underdog))")
	assert_str(rules).contains("| 1 | x1 |")
	assert_str(rules).contains("| 2 | x%s |" % EffectText.num(_db.balance.spread_mult_for(2)))
	assert_str(rules).contains("| 3 or more | x%s |" % EffectText.num(_db.balance.spread_mult_for(3)))


func test_rules_underdog_table_matches_the_engine() -> void:
	var rules: String = _section("Rules and Balance")
	assert_str(rules).contains("### Underdog")
	var max_active: int = int(DataSchemas.ENTRY.tamers.max_active.max)
	for own: int in range(1, max_active + 1):
		for foes: int in range(own + 1, max_active + 1):
			var u: Dictionary = Underdog.compute(_db.balance, own, foes)
			assert_str(rules).contains("| %d vs %d | %s | %d | +%s | -%s | +%s |" % [own, foes,
				EffectText.num(u.ratio - 1.0), u.bonus_actions, EffectText.pct(u.stat_bonus),
				EffectText.pct(u.spread_reduction), EffectText.pct(u.xp_bonus)])


func test_held_items_explain_use_scope_and_overworld() -> void:
	var held: String = _section("Held items")
	assert_str(held).contains("*Per battle*")
	assert_str(held).contains("*Aura*")
	assert_str(held).contains("leads the party")
	assert_bool(held.contains("Per Battle")).override_failure_message("use label not sentence case").is_false()
	for id: String in _held_ids():
		if _db.item(id).held_use == "per_battle":
			assert_str(held).contains("| `%s` | %d | Per battle |" % [id, _db.item(id).price])


func test_passives_explain_slots_triggers_and_overworld() -> void:
	var passives: String = _section("Passives")
	assert_str(passives).contains("*rolled*")
	assert_str(passives).contains("*Affinity*")
	assert_str(passives).contains("%d points" % _db.balance.growth_affinity_threshold)
	assert_str(passives).contains("(physical)")
	assert_str(passives).contains("leads the party")
	assert_str(passives).contains("it is skipped when it would only heal or restore a creature that is already full.")
	assert_str(_section("Affinities")).contains("[Passives](#passives)")


func test_creatures_explain_growth_and_list_cap_stats() -> void:
	var creatures: String = _section("Creatures")
	assert_str(creatures).contains("[Rules and Balance](#rules-and-balance)")
	assert_str(creatures).contains("**Growth**")
	var marker: String = "- **Lv %d stats:**" % _db.balance.level_cap
	assert_int(creatures.count(marker)).is_equal(_db.count("creatures"))


func test_moves_list_every_move_once() -> void:
	var moves: String = _section("Moves")
	for id: String in _db.ids("moves"):
		assert_int(moves.count("| `%s` |" % id)).override_failure_message("move %s" % id).is_equal(1)


func test_creatures_say_where_they_are_found() -> void:
	var creatures := _section("Creatures")
	var wild := ""
	var tame := ""
	for id in Codex.order(_db):
		var rows := Locations.for_species(_db, id)
		if rows.is_empty() and tame == "":
			tame = id
		elif not rows.is_empty() and wild == "":
			wild = id
	assert_str(wild).is_not_empty()
	assert_str(tame).is_not_empty()
	var lines := Locations.for_species(_db, wild).map(func(r: Dictionary) -> String: return Locations.line(r))
	assert_str(creatures).contains("- **Found:** " + "; ".join(lines))
	assert_str(creatures).contains("- **Found:** Not found in the wild")
