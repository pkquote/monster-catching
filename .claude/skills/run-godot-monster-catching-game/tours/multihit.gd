extends RefCounted
## The `multihit` tour (driver.gd --mode=multihit).
## A seeded wild battle: a Voltmoth knowing Spark Volley (2-5 hits) against three 1-HP Frostlings.
## The first hit faints the chosen foe at once, the remaining hits carry on to the next foe in slot
## order, and the text line reads "Hit N times!".
##
## `d` is the driver (a SceneTree): its helpers (expect, shot, hold, press...) and
## its tree (d.root, d.current_scene, d.process_frame).

var d


func run() -> void:
	await d.process_frame
	var gs = d.root.get_node("GameState")
	var router = d.root.get_node("SceneRouter")
	var db = d.root.get_node("DataRegistry").db
	gs.store = SaveStore.new(d.RUN_SAVES)
	d._clear(d.RUN_SAVES)
	gs.start_new_game("Ana")
	router.goto(router.WORLD)
	await d.wait_scene("Overworld", 120)
	await d._frames(10)

	# 1. Voltmoth leads with Spark Volley; three Frostlings with 1 HP each are the wild pack (not Pebblets: Earth is immune to Electric).
	var volt := CreatureInstance.create(db, "voltmoth", 20, PackedStringArray(["spark_volley"]))
	gs.current.party.clear()
	gs.current.party.append(volt)
	for i in 2:  # two Tidepups that only Rest, so the format is 3v3 (no Underdog extra action)
		var pup := CreatureInstance.create(db, "tidepup", 20)
		pup.energy = 0  # Rest is only offered below full energy
		gs.current.party.append(pup)
	var pack := []
	for i in 3:
		var p := CreatureInstance.create(db, "frostling", 3)
		p.hp = 1
		pack.append(p)
	var setup = BattleLauncher.wild_setup(db, gs.current, pack, 3)
	router.goto("res://game/battle/battle_scene.tscn", {"setup": setup, "seed": 7})
	await d.wait_battle_open()
	await d.wait_battle(["command"])
	await d.shot("m01_command")

	# 2. Use Spark Volley on the first foe and watch for the "Hit N times!" line.
	await d.pick_menu("Fight")
	await d.pick_menu("")
	await d.pick_menu("")  # the first foe
	for i in 2:  # the two Tidepups rest
		await d._frames(10)
		await d.pick_menu("Rest")
	await d.pick_menu("Yes, go!")
	var seen_line := ""
	var left_command := false
	for i in 3000:
		var b = d._battle()
		if b == null:
			await d.process_frame
			continue
		if b.phase != "command":
			left_command = true
		if seen_line == "" and b._message.text.begins_with("Hit ") and b._message.text.ends_with(" times!"):
			seen_line = b._message.text
			await d.shot("m02_hit_count")
		if left_command and (b.phase in ["results", "replace"] or (b.phase == "command" and b.menu.is_choosing())):
			break
		await d.process_frame
	d.expect(seen_line != "", "the text line says how many times the move hit (%s)" % seen_line)

	# 3. The log: faint comes between hits and the rest of the hits reach another foe.
	var bs = d._battle()
	var log: Array = bs._log
	var used := log.find_custom(func(e): return e.type == "move_used")
	var count := log.find_custom(func(e): return e.type == "hit_count")
	d.expect(used >= 0 and count > used, "the log has MOVE_USED then HIT_COUNT")
	var segment: Array = log.slice(used, count)
	var faints := segment.filter(func(e): return e.type == "faint")
	var hit_bids := {}
	for e in segment:
		if e.type == "damage":
			hit_bids[e.bid] = true
	d.expect(faints.size() >= 2, "at least two foes fainted during the one move (%d)" % faints.size())
	d.expect(hit_bids.size() >= 2, "the hits reached more than one foe (%s)" % [hit_bids.keys()])
	var first_faint := segment.find_custom(func(e): return e.type == "faint")
	var damage_after := segment.slice(first_faint).filter(func(e): return e.type == "damage")
	d.expect(first_faint >= 0 and not damage_after.is_empty(), "a hit landed after the first faint (the spill)")

	await d.fight_to_end()
	await d._frames(10)
	await d.shot("m03_results")
	d._clear(d.RUN_SAVES)
	d._finish()
