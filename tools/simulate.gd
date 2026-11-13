extends SceneTree
## Seeded AI-vs-AI battle simulator for balance checks.
##   godot --headless --path . --script res://tools/simulate.gd -- --battles=500 --format=2v2
##
## Options (all optional):
##   --battles=N        number of battles (default 200)
##   --seed=N           base RNG seed (default 1); battle i uses seed + i
##   --format=AvB       creatures fielded per side, e.g. 1v1, 2v2, 3v3, 1v3 (default 2v2)
##   --party=N          creatures per team (default 3), clamped to 1..balance.party_size and never
##                      below the larger fielded side (with party_size 6, --party=12 runs with 6)
##   --level=N          level of every creature (default 10)
##   --ai=A,B           AI style per side, any id in data/ai_styles.json: basic | aggressive | tactician | passive |
##                      defensive | trickster (default tactician,aggressive)
##   --pack=1|0         1 (default): also load the debug test content pack (res://data_testpack, skipped
##                      when absent) and draw species from data/ plus the pack; 0: data/ only

const PACK_ROOT: String = "res://data_testpack"

var _opts := {"battles": 200, "seed": 1, "format": "2v2", "party": 3, "level": 10, "ai": "tactician,aggressive",
	"pack": 1}


func _init() -> void:
	_parse_args()
	var packs: Array = [PACK_ROOT] if int(_opts.pack) == 1 and DirAccess.dir_exists_absolute(PACK_ROOT) else []
	var result := DataLoader.load_database("res://data", "", packs)
	if not result.ok():
		for e in result.errors:
			printerr(e)
		quit(1)
		return
	var db := result.db
	var counts: PackedStringArray = str(_opts.format).split("v")
	var field := [int(counts[0]), int(counts[1])]
	var max_active := maxi(field[0], field[1])
	var party_size: int = maxi(clampi(int(_opts.party), 1, db.balance.party_size), max_active)
	if party_size != int(_opts.party):
		print("--party=%d clamped to %d (balance.party_size %d, format %s)" % [int(_opts.party), party_size,
			db.balance.party_size, _opts.format])
	var ais: PackedStringArray = str(_opts.ai).split(",")
	for style in ais:
		if db.ai_style(style) == null:
			printerr("Unknown AI style \"%s\"; use one of: %s" % [style, ", ".join(db.ids("ai_styles"))])
			quit(1)
			return
	var species := db.ids("creatures")

	var wins := [0, 0]
	var draws := 0
	var total_rounds := 0
	var reactions := {}
	var species_stats := {}  # id -> { battles, wins }

	for i in int(_opts.battles):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_opts.seed) + i
		var parties := [[], []]
		for s in 2:
			for n in party_size:
				var sp: String = species[rng.randi_range(0, species.size() - 1)]
				# The battle's RNG rolls the passive too, so passives now vary with the seed (older runs differ).
				parties[s].append(CreatureInstance.create(db, sp, int(_opts.level), PackedStringArray(), rng))
		var setup := BattleSetup.new()
		setup.award_xp = false  # XP only goes to side 0 and would bias results
		setup.add_side(parties[0], max_active, field[0], {}, ais[0], true)
		setup.add_side(parties[1], max_active, field[1], {}, ais[1 % ais.size()], true)
		var engine := BattleEngine.new(db, rng, setup)
		var events := engine.start()
		while not engine.is_over():
			events.append_array(engine.resolve_round([]))
		var res := engine.result()
		total_rounds += res.rounds
		if res.winner == -1:
			draws += 1
		else:
			wins[res.winner] += 1
		for ev in events:
			if ev.type == "reaction":
				reactions[ev.reaction] = int(reactions.get(ev.reaction, 0)) + 1
		for s in 2:
			for c: CreatureInstance in parties[s]:
				if not species_stats.has(c.species):
					species_stats[c.species] = {"battles": 0, "wins": 0}
				species_stats[c.species].battles += 1
				if res.winner == s:
					species_stats[c.species].wins += 1

	var n := float(_opts.battles)
	print("Simulated %d battles · format %s · level %d · party %d · %d species (%s)" % [_opts.battles, _opts.format,
		_opts.level, party_size, species.size(), "data/ + test pack" if not packs.is_empty() else "data/ only"])
	print("  Side 0 (%s): %.1f%% wins" % [ais[0], 100.0 * wins[0] / n])
	print("  Side 1 (%s): %.1f%% wins" % [ais[1 % ais.size()], 100.0 * wins[1] / n])
	print("  Draws (round limit): %d · average rounds: %.1f" % [draws, total_rounds / n])
	print("Reactions triggered:")
	if reactions.is_empty():
		print("  none")
	for r in reactions:
		print("  %-12s %d (%.2f per battle)" % [db.reaction(r).name, reactions[r], reactions[r] / n])
	print("Species win rate (when on a team):")
	var ids := species_stats.keys()
	ids.sort_custom(func(a, b): return species_stats[a].wins * species_stats[b].battles > species_stats[b].wins * species_stats[a].battles)
	for id in ids:
		var st: Dictionary = species_stats[id]
		print("  %-28s %-24s %5.1f%%  (%d appearances)" % [id, db.creature(id).name, 100.0 * st.wins / st.battles,
			st.battles])
	quit(0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not "=" in arg:
			continue
		var kv := arg.substr(2).split("=", true, 1)
		if _opts.has(kv[0]):
			_opts[kv[0]] = kv[1] if _opts[kv[0]] is String else int(kv[1])
