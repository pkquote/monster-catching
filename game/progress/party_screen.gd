class_name PartyScreen
extends ProgressScreen
## The party list from the pause menu: one row per creature, and per row
## Summary, Move (reorder) and Storage (only where it is safe to swap).

const UNSAFE_TEXT := "It isn't safe to swap creatures here."

var _world: Overworld


## Runs until the player closes the list.
static func run(world: Overworld) -> void:
	var screen := PartyScreen.new()
	screen._world = world
	world.add_child(screen)
	await screen._loop()
	screen.close()


static func row_text(db: Database, c: CreatureInstance) -> String:
	var line := "%s  Lv %d  HP %d/%d  EN %d/%d" % [c.display_name(db), c.level,
		c.hp, c.max_hp(db), c.energy, c.max_energy(db)]
	if c.status != "":
		line += "  " + db.status(c.status).name.to_upper()
	if Progression.growth_target(db, c) != "":
		line += "  Ready to grow"
	return line


## A list row: the text, a placeholder sprite as the button icon, and HP / energy bars.
static func _row_option(db: Database, c: CreatureInstance, value: int) -> Dictionary:
	return {"label": row_text(db, c), "value": value, "decorate": func(b: Button) -> void:
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		img.fill(species_color(c.species))
		b.icon = ImageTexture.create_from_image(img)
		_add_bar(b, 3, c.hp, c.max_hp(db), Color(0.35, 0.8, 0.4))
		_add_bar(b, 12, c.energy, c.max_energy(db), Color(0.35, 0.6, 0.95))}


static func _add_bar(parent: Control, y: float, value: float, max_value: float, colour: Color) -> void:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = max_value
	bar.value = value
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(440, y)
	bar.size = Vector2(150, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	parent.add_child(bar)



func _loop() -> void:
	var db := DataRegistry.db
	var save := GameState.current
	while true:
		_title.text = "Party"
		_body.text = "" if not save.party.is_empty() else "Nobody in your party yet."
		var options: Array = []
		for i in save.party.size():
			options.append(_row_option(db, save.party[i], i))
		options.append({"label": "Back", "value": -1})
		var i = await menu.choose("", options, true, 1)
		if i == null or i < 0:
			return
		await _row(i)


func _row(index: int) -> void:
	var db := DataRegistry.db
	var save := GameState.current
	var c: CreatureInstance = save.party[index]
	var safe := _world.is_safe_here()
	_title.text = c.display_name(db)
	_body.text = "" if safe else UNSAFE_TEXT
	var choice = await menu.choose("", [
		{"label": "Summary", "value": "summary"},
		{"label": "Move", "value": "move", "disabled": save.party.size() < 2},
		{"label": "Storage", "value": "storage", "disabled": not safe},
		{"label": "Cancel", "value": null}], true, 1)
	match choice:
		"summary":
			await _open_summary(index)
		"move":
			await _move(index)
		"storage":
			await StorageScreen.run(_world)


func _open_summary(index: int) -> void:
	await SummaryScreen.run(_world, GameState.current.party, index)


func _move(from: int) -> void:
	var db := DataRegistry.db
	var save := GameState.current
	_body.text = "Move %s to which slot?" % save.party[from].display_name(db)
	var options: Array = []
	for i in save.party.size():
		options.append(_row_option(db, save.party[i], i))
	options.append({"label": "Cancel", "value": -1})
	var to = await menu.choose("", options, true, 1)
	if to != null and to >= 0:
		Team.reorder(save, from, to)
