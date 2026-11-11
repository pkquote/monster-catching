class_name PauseMenu
extends SideMenu
## The Menu key on the overworld: Party, Bag, Codex, Save, Settings, Quit to title, Close.

var _bag_summary: BagSummary


## Runs until closed (or until it leaves the overworld for Settings / the title).
func run(world: Overworld) -> void:
	_open("Menu")
	while true:
		var choice = await menu.choose("", [
			{"label": "Party", "value": "party"}, {"label": "Bag", "value": "bag"},
			{"label": "Codex", "value": "codex"},
			{"label": "Save", "value": "save"}, {"label": "Settings", "value": "settings"},
			{"label": "Quit to title", "value": "quit"}, {"label": "Close", "value": "close"},
		], true, 1)
		match choice:
			"party":
				await _party(world)
			"bag":
				await _bag()
			"codex":
				await CodexScreen.run(world)
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


func _party(world: Overworld) -> void:
	await PartyScreen.run(world)


## The bag's left pane while the item list is up (made on first use, kept by the page).
func bag_summary() -> BagSummary:
	if _bag_summary == null:
		_bag_summary = BagSummary.new()
	return _bag_summary


func _bag() -> void:
	var db := DataRegistry.db
	var summary := bag_summary()
	# The focused item fills the left pane; Back (no hint) shows the "Pick an item." line.
	var show_hint := func(hint: Variant) -> void:
		if hint != null:
			summary.show_item(db, GameState.current, str(hint))
		elif GameState.current.inventory.is_empty():
			summary.show_empty("Your bag is empty.")
		else:
			summary.show_empty()
	while true:
		var inv: Dictionary = GameState.current.inventory
		var options: Array = []
		for id in inv:
			var it := db.item(id)
			options.append({"label": "%s ×%d" % [it.name if it else id, inv[id]], "value": id, "hint": id})
		options.append({"label": "Back", "value": null})
		show_hint.call(null)
		page_control(summary)
		menu.hovered.connect(show_hint)  # only while the list is up, as the shop does
		var item_id = await menu.choose("", options, true, 1)
		menu.hovered.disconnect(show_hint)
		if item_id == null:
			break
		var it := db.item(item_id)
		if not FieldItems.can_use(db, item_id):
			var text := "%s\nUnknown item." % item_id
			if it != null:
				text = "%s\n%s" % [it.name, it.description]
			if it != null and it.category == "held":
				text += "\nGive it from the Summary."
			page(text)
			await menu.choose("", [{"label": "Back", "value": null}], true, 1)
			continue
		var is_seed: bool = it.category == "training"
		var who: Array = []
		for c: CreatureInstance in GameState.current.party:
			if is_seed:
				who.append({"label": "%s  Lv %d  %d points spent" % [c.display_name(db), c.level,
					Training.spent(c)], "value": c})
			else:
				who.append({"label": "%s  HP %d/%d  EN %d/%d" % [c.display_name(db), c.hp, c.max_hp(db),
					c.energy, c.max_energy(db)], "value": c})
		who.append({"label": "Back", "value": null})
		page("Use the %s on who?
%s" % [it.name, it.description])
		var target = await menu.choose("", who, true, 1)
		if target == null:
			continue
		if is_seed and not await ResetSeedPrompt.confirm(menu, page, target):
			continue
		var r := FieldItems.use(db, GameState.current, item_id, target)
		var msg := {"fainted": "It can't be used on a fainted creature.", "no_effect": "It won't have any effect.",
			"none_left": "You don't have any left."}
		var cname: String = target.display_name(db)
		if r.ok:
			if is_seed:
				page("%s's %s came back." % [cname, ResetSeedPrompt.points(r.refunded)])
			elif r.cured and r.healed == 0 and r.energy == 0:
				page("%s was cured." % cname)
			else:
				page("%s recovered." % cname)
		else:
			page(msg.get(r.error, "It can't be used."))
		await menu.choose("", [{"label": "OK", "value": null}], true, 1)
	page("")
