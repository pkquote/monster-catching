extends GdUnitTestSuite
## The shipped species' growth tiers (M6b): the rule, the budget, and the starter lines.
##
## The rule: a stat 8 or more above the species' own average across its nine stats is `fast`, 8 or more
## below is `slow`, at most two of each (biggest gaps first), so a species' total growth stays neutral.
## A balanced species stays all-steady. Changing these numbers is a balance decision: change them here too.

const TIERS := {
	"tidepup": {},
	"torrentusk": {"patk": "fast", "hp": "fast", "satk": "slow", "luck": "slow"},
	"mistcoil": {"satk": "fast", "spd": "fast", "patk": "slow", "pdef": "slow"},
	"emberkit": {"satk": "fast", "spd": "fast", "pdef": "slow", "resolve": "slow"},
	"blazefox": {"spd": "fast", "satk": "fast", "pdef": "slow", "resolve": "slow"},
	"cinderwisp": {"sdef": "fast", "satk": "fast", "patk": "slow", "pdef": "slow"},
	"sprigling": {"sdef": "fast", "resolve": "fast", "spd": "slow", "satk": "slow"},
	"thornwall": {"sdef": "fast", "hp": "fast", "spd": "slow", "satk": "slow"},
	"mossweaver": {"sdef": "fast", "satk": "fast", "patk": "slow", "pdef": "slow"},
	"voltmoth": {"spd": "fast", "satk": "fast", "pdef": "slow", "patk": "slow"},
	"frostling": {},
	"pebblet": {"pdef": "fast", "resolve": "fast", "spd": "slow", "satk": "slow"},
}

## Each starter, then its two evolutions (the default branch leads to the first).
const LINES := {
	"tidepup": ["torrentusk", "mistcoil"],
	"emberkit": ["blazefox", "cinderwisp"],
	"sprigling": ["thornwall", "mossweaver"],
}

var db: Database


func before() -> void:
	var result: DataLoader.LoadResult = DataLoader.load_database("res://data", "res://dialogue")
	assert_bool(result.ok()).is_true()
	db = result.db


func test_every_shipped_species_has_its_tiers() -> void:
	assert_array(Array(db.ids("creatures"))).contains_exactly_in_any_order(TIERS.keys())
	for id: String in TIERS:
		var c := db.creature(id)
		var tiers: Dictionary = TIERS[id]
		for stat: String in DataSchemas.BASE_STATS:
			assert_str(c.growth_tier(stat)).override_failure_message("%s %s" % [id, stat]) \
				.is_equal(tiers.get(stat, "steady"))


func test_every_species_is_within_the_growth_budget() -> void:
	for id in db.ids("creatures"):
		var total := 0
		for stat: String in DataSchemas.BASE_STATS:
			var mult := float(db.balance.growth_tiers[db.creature(id).growth_tier(stat)])
			total += 1 if mult > 1.0 else (-1 if mult < 1.0 else 0)
		assert_int(total).override_failure_message(id).is_less_equal(db.balance.growth_budget)


func test_each_starter_has_two_evolutions_at_16_with_a_default() -> void:
	for starter: String in LINES:
		var growth: Array = db.creature(starter).growth
		var into := growth.map(func(g: Dictionary) -> String: return g.into)
		for evolved: String in LINES[starter]:
			assert_array(into).override_failure_message("%s -> %s" % [starter, evolved]).contains([evolved])
			assert_bool(db.has("creatures", evolved)).is_true()
		for g: Dictionary in growth:
			assert_int(g.level).is_equal(16)
		assert_int(growth.filter(func(g: Dictionary) -> bool: return g.default).size()).is_equal(1)
		assert_str(growth.filter(func(g: Dictionary) -> bool: return g.default)[0].into).is_equal(LINES[starter][0])


func test_evolved_forms_are_evolution_only_and_have_no_further_growth() -> void:
	for starter: String in LINES:
		for evolved: String in LINES[starter]:
			var c := db.creature(evolved)
			assert_array(c.growth).is_empty()
			assert_float(c.catch_rate).is_equal(0.1)
			assert_int(c.xp_yield).is_equal(160)
			assert_str(c.description).is_not_empty()


func test_starters_and_evolved_forms_are_never_wild() -> void:
	var never_wild := LINES.keys()
	for starter: String in LINES:
		never_wild.append_array(LINES[starter])
	for enc_id in db.ids("encounters"):
		for row: Dictionary in db.encounter(enc_id).table:
			assert_bool(never_wild.has(row.species)).override_failure_message("%s is wild in %s" % [row.species, enc_id]).is_false()


func test_dex_numbers_keep_each_family_together() -> void:
	var order := ["tidepup", "torrentusk", "mistcoil", "emberkit", "blazefox", "cinderwisp", "sprigling", "thornwall",
		"mossweaver", "voltmoth", "frostling", "pebblet"]
	for i in order.size():
		assert_int(db.creature(order[i]).dex).override_failure_message(order[i]).is_equal(i + 1)


func test_each_branch_is_taken_by_its_affinity() -> void:
	var cases := [
		["emberkit", "", "blazefox"], ["emberkit", "striker", "blazefox"], ["emberkit", "catalyst", "cinderwisp"],
		["emberkit", "warden", "blazefox"],
		["sprigling", "", "thornwall"], ["sprigling", "warden", "thornwall"], ["sprigling", "trickster", "mossweaver"],
		["sprigling", "striker", "thornwall"],
		["tidepup", "catalyst", "mistcoil"], ["tidepup", "striker", "torrentusk"],
	]
	for case: Array in cases:
		var c := CreatureInstance.create(db, case[0], 16)
		if case[1] != "":
			c.affinity[case[1]] = db.balance.growth_affinity_threshold + 5
		assert_str(Progression.growth_target(db, c)).override_failure_message("%s with %s" % [case[0], case[1]]) 			.is_equal(case[2])
		var below := CreatureInstance.create(db, case[0], 15)
		assert_str(Progression.growth_target(db, below)).is_equal("")
