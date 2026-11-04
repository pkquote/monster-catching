class_name PauseMenu
extends SideMenu
## The Menu key on the overworld: Party, Bag, Save, Settings, Quit to title, Close.
## (Full party/storage management arrives with M4.)


## Runs until closed (or until it leaves the overworld for Settings / the title).
func run(world: Overworld) -> void:
	_open("Menu")
	while true:
		var choice = await menu.choose("", [
			{"label": "Party", "value": "party"}, {"label": "Bag", "value": "bag"},
			{"label": "Save", "value": "save"}, {"label": "Settings", "value": "settings"},
			{"label": "Quit to title", "value": "quit"}, {"label": "Close", "value": "close"},
		], true, 1)
		match choice:
			"party":
				await _party()
			"bag":
				await _bag()
			"save":
				page("Saved." if GameState.save_manual() != "" else "Couldn't save!")
			"settings":
				_close()
				world.store_position()
				GameState.autosave()
				SceneRouter.goto(SceneRouter.SETTINGS, {"return_to": SceneRouter.WORLD})
				return
			"quit":
				_close()
				GameState.autosave()
				GameState.close_game()
				SceneRouter.goto(SceneRouter.TITLE)
				return
			_:
				break
	_close()


func _party() -> void:
	var db := DataRegistry.db
	var lines := PackedStringArray()
	for c: CreatureInstance in GameState.current.party:
		lines.append(creature_line(db, c))
		var moves := Array(c.moves).map(func(m): return db.move(m).name if db.move(m) != null else m)
		lines.append("    " + ", ".join(moves))
	if lines.is_empty():
		lines.append("Nobody in your party yet.")
	page("\n".join(lines))
	await menu.choose("", [{"label": "Back", "value": null}], true, 1)
	page("")


static func creature_line(db: Database, c: CreatureInstance) -> String:
	var types := " / ".join(Array(c.species_def(db).types).map(func(t): return db.type_def(t).name if db.type_def(t) else t))
	var line := "%s  Lv %d  %s   HP %d/%d  EN %d/%d  Bond %+d" % [c.display_name(db), c.level, types,
		c.hp, c.max_hp(db), c.energy, c.max_energy(db), c.bond]
	if c.status != "":
		line += "  " + db.status(c.status).name.to_upper()
	return line


func _bag() -> void:
	var db := DataRegistry.db
	while true:
		var inv: Dictionary = GameState.current.inventory
		var options: Array = []
		for id in inv:
			var it := db.item(id)
			options.append({"label": "%s ×%d" % [it.name if it else id, inv[id]], "value": id})
		options.append({"label": "Back", "value": null})
		page("Your bag is empty." if inv.is_empty() else "Pick an item.")
		var item_id = await menu.choose("", options, true, 1)
		if item_id == null:
			break
		var it := db.item(item_id)
		if not FieldItems.can_use(db, item_id):
			page("%s\n%s" % [it.name, it.description])
			await menu.choose("", [{"label": "Back", "value": null}], true, 1)
			continue
		var who: Array = []
		for c: CreatureInstance in GameState.current.party:
			who.append({"label": "%s  HP %d/%d  EN %d/%d" % [c.display_name(db), c.hp, c.max_hp(db), c.energy, c.max_energy(db)], "value": c})
		who.append({"label": "Back", "value": null})
		page("Use the %s on who?\n%s" % [it.name, it.description])
		var target = await menu.choose("", who, true, 1)
		if target == null:
			continue
		var r := FieldItems.use(db, GameState.current, item_id, target)
		var msg := {"fainted": "It can't be used on a fainted creature.", "no_effect": "It won't have any effect.",
			"none_left": "You don't have any left."}
		page(("%s recovered." % target.display_name(db)) if r.ok else msg.get(r.error, "It can't be used."))
		await menu.choose("", [{"label": "OK", "value": null}], true, 1)
	page("")
