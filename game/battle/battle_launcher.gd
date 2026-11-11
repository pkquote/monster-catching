class_name BattleLauncher
extends RefCounted
## Builds battles from the current save, and folds the results back into it.
## No UI here, so it can be tested directly.

const TEST_PARTY := [["tidepup", 8], ["emberkit", 8], ["voltmoth", 8]]
const TEST_BAG := {"lure_cage": 5, "tide_net": 3, "snare_vine": 3, "salve": 3, "tonic": 2}
const TEST_FLAG := "debug_test_party_granted"
## Most creatures one side can have on the field (the battle screen has 3 slots).
const MAX_SIDE := 3


## A randomized generator for creation sites that have none of their own.
static func fresh_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


## Creature ids a random pick may put into a real save: every species except the debug
## test pack's (`tp_`). Use this, not `db.ids("creatures")`, for any random species that
## ends up in a party or box. Sorted, so a seeded rng picks reproducibly.
static func save_safe_species(db: Database) -> Array:
	var out: Array = []
	for id: String in db.ids("creatures"):
		if not Database.is_test_content(id):
			out.append(id)
	out.sort()
	return out


## Debug helper: adds up to `count` random save-safe creatures at `level` to the box.
static func fill_box(db: Database, save: SaveGame, count: int, level: int, rng: RandomNumberGenerator) -> void:
	var species: Array = save_safe_species(db)
	for i: int in count:
		var c := CreatureInstance.create(db, species[rng.randi() % species.size()], level,
			PackedStringArray(), rng)
		if not BoxStorage.add(save, c):
			return


## Debug helper until starters exist (M3): a small party and bag, once per playthrough.
## Returns false if this playthrough already got it.
static func grant_test_party(db: Database, save: SaveGame) -> bool:
	if save.story.flag(TEST_FLAG):
		return false
	var rng := fresh_rng()
	for entry in TEST_PARTY:
		var c := CreatureInstance.create(db, entry[0], entry[1], PackedStringArray(), rng)
		if save.party.is_empty():
			Bond.make_starter(db, c)
		add_to_party(db, save, c)
	for item in TEST_BAG:
		save.inventory[item] = int(save.inventory.get(item, 0)) + TEST_BAG[item]
	save.story.set_flag(TEST_FLAG)
	return true


static func healthy_count(save: SaveGame) -> int:
	return save.party.filter(func(c: CreatureInstance): return c.hp > 0).size()


## How many creatures the player may field against a format of `format_size`.
static func max_fieldable(save: SaveGame, format_size: int) -> int:
	return mini(format_size, healthy_count(save))


## Rolls a wild pack from an encounter table.
static func roll_wild_pack(db: Database, encounter_id: String, rng: RandomNumberGenerator) -> Array:
	var enc := db.encounter(encounter_id)
	var pack: Array = []
	for i in rng.randi_range(enc.pack_min, enc.pack_max):
		var row := enc.roll(rng)
		pack.append(CreatureInstance.create(db, row.species, rng.randi_range(row.min_level, row.max_level),
			PackedStringArray(), rng))
	return pack


static func wild_setup(db: Database, save: SaveGame, pack: Array, field_count: int) -> BattleSetup:
	return _with_lead_field(db, save, BattleSetup.wild(save.party, pack, field_count, save.inventory))


static func tamer_setup(db: Database, save: SaveGame, tamer_id: String, field_count: int) -> BattleSetup:
	return _with_lead_field(db, save,
		BattleSetup.vs_tamer(db, save.party, tamer_id, field_count, save.inventory, fresh_rng()))


## The party lead's overworld XP and Bond-gain multipliers, onto `setup`.
static func _with_lead_field(db: Database, save: SaveGame, setup: BattleSetup) -> BattleSetup:
	setup.xp_mult = Passives.field_mult(db, save, "xp_mult")
	setup.bond_gain = Passives.field_mult(db, save, "bond_gain")
	return setup


## Exhibition battle between hand-built teams (Array[CreatureSpec]). Nothing in it
## touches the save: side 0 fights with a copy of `bag`, and `exhibition` stops the
## results being applied. `wild` foes (clamped to MAX_SIDE) can be caught and fled
## from; otherwise they are a tactician "Sparring Partner".
static func exhibition_setup(db: Database, mine: Array, mine_field: int, foes: Array, foe_field: int,
		wild: bool, bag: Dictionary, rng: RandomNumberGenerator) -> BattleSetup:
	assert(not mine.is_empty() and not foes.is_empty(), "exhibition_setup needs a creature on each side")
	var my_team: Array = []
	for spec: CreatureSpec in mine.slice(0, db.balance.party_size):
		my_team.append(spec.to_instance(db, rng))
	var foe_specs: Array = foes.slice(0, mini(MAX_SIDE, db.balance.party_size) if wild else db.balance.party_size)
	var foe_team: Array = []
	for spec: CreatureSpec in foe_specs:
		foe_team.append(spec.to_instance(db, rng))
	var my_n: int = clampi(mine_field, 1, mini(MAX_SIDE, my_team.size()))
	var foe_n: int = clampi(foe_field, 1, mini(MAX_SIDE, foe_team.size()))
	var s: BattleSetup = BattleSetup.new()
	s.is_wild = wild
	s.exhibition = true
	s.add_side(my_team, my_n, my_n, bag)
	s.add_side(foe_team, foe_n, foe_n, {}, "basic" if wild else "tactician", true)
	s.sides[1].is_wild = wild
	if not wild:
		s.foe_name = "Sparring Partner"
	return s


## Average level of the party (1 if empty). The custom battle's default level.
static func party_level(save: SaveGame) -> int:
	if save.party.is_empty():
		return 1
	var total := 0
	for c: CreatureInstance in save.party:
		total += c.level
	return roundi(float(total) / save.party.size())


## Writes the battle's outcome into the save: the party's battle copies (HP, energy,
## XP, Bond...), the bag, catches and money. Call once, after the battle ends.
## Returns the summary for the results panel and the overworld.
static func apply_results(db: Database, save: SaveGame, engine: BattleEngine) -> BattleSummary:
	var levels_before := {}
	var passives_before := {}
	var bag_before := save.inventory.duplicate()
	for b in engine.sides[0].battlers:
		levels_before[b.source] = b.source.level
		passives_before[b.source] = b.source.affinity_passive
	engine.commit(0)
	var res := engine.result()
	var summary := BattleSummary.new()
	summary.tamer_id = engine.setup.tamer_id
	for c: CreatureInstance in save.party:
		if levels_before.has(c):
			var entry := Progression.progress_entry(db, c, levels_before[c], passives_before[c])
			if entry != null:
				summary.progress.append(entry)
	save.inventory = {}
	for item in engine.sides[0].items:
		if int(engine.sides[0].items[item]) > 0:
			save.inventory[item] = int(engine.sides[0].items[item])
	_record_tracking(save, engine, bag_before)
	for c: CreatureInstance in res.captured:
		Counters.add(save, "creatures_caught")
		summary.captured.append(c.display_name(db))
		if not add_to_party(db, save, c):
			summary.to_storage += 1
	match res.reason:
		"fled":
			summary.outcome = BattleSummary.FLED
		"round_limit":
			summary.outcome = BattleSummary.DRAW
		_:
			summary.outcome = BattleSummary.WON if res.winner == 0 else BattleSummary.LOST
	if summary.outcome == BattleSummary.WON and not res.captured.is_empty() and engine.setup.is_wild:
		summary.outcome = BattleSummary.CAPTURED
	if summary.outcome == BattleSummary.WON and engine.setup.tamer_id != "":
		summary.money = db.tamer(engine.setup.tamer_id).reward_money
		save.money += summary.money
		Counters.add(save, "tamers_defeated")
		if summary.money > 0:
			Counters.add(save, "money_earned", summary.money)
	if summary.outcome != BattleSummary.FLED:
		Counters.add(save, "battles_fought")
	if summary.outcome == BattleSummary.WON or summary.outcome == BattleSummary.CAPTURED:
		Counters.add(save, "battles_won")
	Log.info(Log.BATTLE, "Results applied", {"outcome": summary.outcome, "money": summary.money,
		"captured": summary.captured, "to_storage": summary.to_storage,
		"levelled": summary.progress.map(func(e: ProgressEntry): return e.creature.species)})
	return summary


## Codex and counter updates that need the finished engine: every foe that was fielded is
## seen, and the items the battle used up are counted (the bag before against after).
static func _record_tracking(save: SaveGame, engine: BattleEngine, bag_before: Dictionary) -> void:
	for b: Battler in engine.sides[1].battlers:
		if b.participated:
			Codex.mark_seen(save, b.creature.species)
	var used := 0
	for item: String in bag_before:
		used += maxi(int(bag_before[item]) - int(save.inventory.get(item, 0)), 0)
	if used > 0:
		Counters.add(save, "items_used", used)


## Places a new creature could still go: free party room plus empty box slots.
static func room_left(db: Database, save: SaveGame) -> int:
	return maxi(int(db.balance.party_size) - save.party.size(), 0) + BoxStorage.empty_count(save)


## Adds to the party, or to storage when the party is full. Returns true for party.
## Every creature that joins counts as caught in the Codex, whatever way it arrived.
static func add_to_party(db: Database, save: SaveGame, c: CreatureInstance) -> bool:
	Codex.mark_caught(save, c.species)
	if save.party.size() < db.balance.party_size:
		save.party.append(c)
		return true
	if not BoxStorage.add(save, c):
		# Never lose a creature: open another box (capture is refused up front when full).
		if not BoxStorage.unlock_box(save) or not BoxStorage.add(save, c):
			save.storage.append(c)
			save.boxes_unlocked = ceili(save.storage.size() / float(BoxStorage.BOX_SIZE))
	return false
