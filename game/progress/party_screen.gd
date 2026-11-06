class_name PartyScreen
extends ProgressScreen
## The party list from the pause menu: one row per creature, and per row
## Summary, Move (reorder) and Storage (only where it is safe to swap).

const UNSAFE_TEXT := "It isn't safe to swap creatures here."

## Width of a row: the card takes the left of the screen (set_side).
const COLUMN_WIDTH := 306
const ROW_SPRITE := 18
const BAR_WIDTH := 56

var _world: Overworld
var _card: CreatureCard


## Runs until the player closes the list.
static func run(world: Overworld, save: SaveGame = null, db: Database = null) -> void:
	var screen := PartyScreen.new()
	screen._world = world
	screen.use_game(save, db)
	world.add_child(screen)
	await screen._loop()
	screen.close()


func _init() -> void:
	_card = CreatureCard.new()  # built before the screen joins the tree, as the Summary does
	set_side(_card)


func _ready() -> void:
	super()
	menu.button_width = COLUMN_WIDTH


func card() -> CreatureCard:
	return _card


## The row's text: name, level and HP, then (on a second line) the status and growth badges.
## Energy is the second bar.
static func row_text(db: Database, c: CreatureInstance) -> String:
	var line := "%s  Lv %d  HP %d/%d" % [c.display_name(db), c.level, c.hp, c.max_hp(db)]
	var badges: Array[String] = []
	if c.status != "":
		badges.append(db.status(c.status).name.to_upper())
	if Progression.growth_target(db, c) != "":
		badges.append("Ready to grow")
	if not badges.is_empty():
		line += "
" + "  ".join(badges)
	return line


## "Lead passive: <name>" when the lead's active passive works on the overworld
## (has `field` effects), else "".
static func lead_line(db: Database, save: SaveGame) -> String:
	if save.party.is_empty():
		return ""
	var def := db.passive(Passives.active_id(save.party[0]))
	return "Lead passive: " + def.name if def != null and not def.field.is_empty() else ""


## A list row: the text, a sprite on the left, and HP / energy bars on the right. The hint is the
## party index, so the card can follow the cursor.
static func _row_option(db: Database, c: CreatureInstance, value: int) -> Dictionary:
	return {"label": row_text(db, c), "value": value, "hint": value, "decorate": func(b: Button) -> void:
		# Keep the text clear of the sprite and the bars.
		for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := b.get_theme_stylebox(style_name).duplicate() as StyleBox
			style.content_margin_left = ROW_SPRITE + 10
			style.content_margin_right = BAR_WIDTH + 12
			b.add_theme_stylebox_override(style_name, style)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var sprite := CreatureSpriteSlot.new()
		sprite.configure(db, c.species, ROW_SPRITE)
		sprite.position = Vector2(5, 2)
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sprite)
		_add_bar(b, 4, c.hp, c.max_hp(db), Color(0.35, 0.8, 0.4))
		_add_bar(b, 13, c.energy, c.max_energy(db), Color(0.35, 0.6, 0.95))}


static func _add_bar(parent: Control, y: float, value: float, max_value: float, colour: Color) -> void:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = max_value
	bar.value = value
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(COLUMN_WIDTH - BAR_WIDTH - 6, y)
	bar.size = Vector2(BAR_WIDTH, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	parent.add_child(bar)



func _loop() -> void:
	var db := _db
	var save := _save
	while true:
		_title.text = "Party"
		_body.text = lead_line(db, save) if not save.party.is_empty() else "Nobody in your party yet."
		var options: Array = []
		for i in save.party.size():
			options.append(_row_option(db, save.party[i], i))
		options.append({"label": "Back", "value": -1})
		_show_card(0)
		menu.hovered.connect(_on_hover)
		var i = await menu.choose("", options, true, 1)
		menu.hovered.disconnect(_on_hover)
		if i == null or i < 0:
			return
		await _row(i)


func _on_hover(hint: Variant) -> void:
	if hint is int:
		_show_card(hint)  # Back and the end of a choice carry no hint: the card stays


func _show_card(index: int) -> void:
	if index >= 0 and index < _save.party.size():
		_card.show_creature(_db, _save.party[index])
	elif _save.party.is_empty():
		_card.show_empty("No creatures")


func _row(index: int) -> void:
	var db := _db
	var save := _save
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
			await StorageScreen.run(_world, _save, _db)


func _open_summary(index: int) -> void:
	await SummaryScreen.run(_world, _save.party, index, _save, _db)


func _move(from: int) -> void:
	var db := _db
	var save := _save
	_body.text = "Move %s to which slot?" % save.party[from].display_name(db)
	var options: Array = []
	for i in save.party.size():
		options.append(_row_option(db, save.party[i], i))
	options.append({"label": "Cancel", "value": -1})
	var to = await menu.choose("", options, true, 1)
	if to != null and to >= 0:
		Team.reorder(save, from, to)
