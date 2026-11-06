class_name SummaryScreen
extends ProgressScreen
## One party creature: its CreatureCard on the left (the affinity bars and the greyed passive under it), an
## info block and a one-column menu on the right.
## The top-level menu opens three sub-lists (Moves, Train, Held item) in the same column, each ending in
## Back. Left/Right and the shoulder buttons step to the previous/next creature (top level only);
## Up/Down belong to the menu's own focus.

const STAT_NAMES := {"hp": "HP", "stamina": "Stamina", "patk": "Physical Attack", "pdef": "Physical Defense",
	"satk": "Special Attack", "sdef": "Special Defense", "spd": "Speed", "resolve": "Resolve", "luck": "Luck"}
const MODES := ["top", "moves", "train", "held"]
## Buttons are one column inside the right-hand side of the screen (the card takes the left).
const COLUMN_WIDTH := 306
## Longest "Held item" text shown (name and description), so it stays on one line in the info block.
const HELD_LINE_MAX := 48
const REFRESH := "@refresh"
const PREV := "@prev"
const NEXT := "@next"
const TOP := "@top"
const OPEN := {"@moves": "moves", "@train": "train", "@held": "held"}

var mode := "top"

var _party: Array
var _index := 0
var _notice := ""
var _last: Variant = null  # the option picked last: it keeps the focus across the re-render
var _busy := false  # a sub-screen is open: leave the keys to it
var _opener := ""  # the top-level entry that opened the current sub-list
var _extra: VBoxContainer
var _card: CreatureCard


## Runs until the player closes the screen.
static func run(parent: Node, party: Array, index: int, save: SaveGame = null, db: Database = null) -> void:
	if party.is_empty():
		return
	var screen := SummaryScreen.new()
	screen.use_game(save, db)
	screen._party = party
	screen._index = clampi(index, 0, party.size() - 1)
	# Under the card (it leaves about 80px): the greyed passive line and the affinity bars.
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 2)
	screen._card = CreatureCard.new()
	side.add_child(screen._card)
	var extra_panel := UIKit.panel(side, 6)
	screen._extra = VBoxContainer.new()
	screen._extra.add_theme_constant_override("separation", 2)
	extra_panel.add_child(screen._extra)
	screen.set_side(side)
	parent.add_child(screen)
	await screen._loop(parent)
	screen.close()


func _ready() -> void:
	super()
	menu.button_width = COLUMN_WIDTH
	menu.linear_focus = true


## The creature being shown.
func creature() -> CreatureInstance:
	return _party[_index]


func card() -> CreatureCard:
	return _card


## Opens the top level or one of the sub-lists ("moves", "train", "held").
func show_mode(name: String) -> void:
	if not MODES.has(name):
		return
	mode = name
	_notice = ""
	_last = null
	menu.interrupt(REFRESH)


func show_creature(index: int) -> void:
	if index < 0 or index >= _party.size():
		return
	_index = index
	_notice = ""
	_last = null
	menu.interrupt(REFRESH)


## Steps to the previous/next creature, wrapping. Nothing with a single creature.
func _step_creature(step: int) -> void:
	if _party.size() > 1:
		show_creature(posmod(_index + step, _party.size()))


## `_input`, not `_unhandled_input`: the menu's GUI focus navigation would otherwise
## take Left/Right first. Only the top level switches creature.
func _input(event: InputEvent) -> void:
	if _busy or mode != "top":
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("next_creature"):
		_step_creature(1)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("prev_creature"):
		_step_creature(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _loop(parent: Node) -> void:
	var db := _db
	while true:
		var c := creature()
		_card.show_creature(db, c)
		_title.text = _title_text(c)
		var options: Array = _render(db, c)
		if mode == "top":
			if _party.size() > 1:
				options.append({"label": "Previous creature", "value": PREV})
				options.append({"label": "Next creature", "value": NEXT})
			options.append({"label": "Back", "value": null})
		else:
			options.append({"label": "Back", "value": TOP})
		if _last != null:
			for o in options:
				o["focus"] = typeof(o.value) == typeof(_last) and o.value == _last
		var hint := "Left / Right: switch creature" if mode == "top" and _party.size() > 1 else ""
		var choice = await menu.choose(hint, options, true, 1)
		if choice == null:
			if mode == "top":
				return
			_leave_sub()
			continue
		if choice is String and choice.begins_with("@"):
			match choice:
				PREV:
					_step_creature(-1)
				NEXT:
					_step_creature(1)
				TOP:
					_leave_sub()
				_:
					if OPEN.has(choice):
						mode = OPEN[choice]
						_opener = choice
						_notice = ""
						_last = null
			continue
		_last = choice
		_busy = true
		await _act(parent, db, c, choice)
		_busy = false


func _title_text(c: CreatureInstance) -> String:
	var text := "%s  Lv %d" % [c.display_name(_db), c.level]
	if _party.size() > 1:
		text += "  (%d / %d)" % [_index + 1, _party.size()]
	return text


## Back to the top level with the focus on the entry that opened the sub-list.
func _leave_sub() -> void:
	mode = "top"
	_notice = ""
	_last = _opener if _opener != "" else null


## Fills the info block and returns this mode's own menu options.
func _render(db: Database, c: CreatureInstance) -> Array:
	for n in _extra.get_children():
		_extra.remove_child(n)
		n.queue_free()
	match mode:
		"moves":
			return _render_moves(db, c)
		"train":
			return _render_train(db, c)
		"held":
			return _render_held(db, c)
	return _render_top(db, c)


func _render_top(db: Database, c: CreatureInstance) -> Array:
	var progress := "Max level" if c.level >= db.balance.level_cap \
		else "XP to next level: %d" % (Stats.xp_for_level(c.level + 1) - c.xp)
	var active := PassiveUnlockScreen.passive_line(db, Passives.active_id(c))
	var lines: PackedStringArray = [progress + "   Bond: %d" % c.bond,
		"Passive: " + (active if active != "" else "none"), "Held item: " + _held_line(db, c)]
	if _notice != "":
		lines.append(_notice)
	_body.text = "\n".join(lines)
	var options: Array = []
	var other := _other_passive(db, c)
	if other.has("text"):
		UIKit.label(_extra, other.text, UIKit.BODY_SIZE, UIKit.MUTED, true)
	_affinity_grid(db, c)
	if Progression.growth_target(db, c) != "":
		options.append({"label": "Grow", "value": "grow"})
	options.append({"label": "Moves...", "value": "@moves"})
	options.append({"label": "Train...", "value": "@train"})
	if not c.held_item.is_empty() or not _bag_held(db).is_empty():
		options.append({"label": "Held item...", "value": "@held"})
	if other.has("slot"):
		options.append({"label": "Use " + other.name, "value": {"passive": other.slot}})
	return options


## The affinity tracks as a 2-column grid of name, bar and points.
func _affinity_grid(db: Database, c: CreatureInstance) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	_extra.add_child(grid)
	for id in db.ids("affinities"):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		UIKit.label(row, db.affinity(id).name, UIKit.BODY_SIZE, UIKit.MUTED).custom_minimum_size = Vector2(56, 0)
		var points := int(c.affinity.get(id, 0))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = maxi(db.balance.growth_affinity_threshold, points)
		bar.value = points
		bar.custom_minimum_size = Vector2(60, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		UIKit.label(row, str(points), UIKit.BODY_SIZE)
		grid.add_child(row)


## The held item's name and description; "none"; or the raw id when the data lacks it.
func _held_line(db: Database, c: CreatureInstance) -> String:
	if c.held_item.is_empty():
		return "none"
	var def := HeldItems.def_of(db, c)
	if def == null:
		return "unknown item: " + c.held_item
	var text := "%s - %s" % [def.name, def.description] if def.description != "" else def.name
	# One line only: the page has no room for a wrapped second one.
	return text if text.length() <= HELD_LINE_MAX else text.left(HELD_LINE_MAX - 1).strip_edges() + "…"


## The bag's held items: [{id, def, count}].
func _bag_held(db: Database) -> Array:
	var out: Array = []
	for id in _save.inventory:
		var def := db.item(id)
		if def != null and def.category == "held" and int(_save.inventory[id]) > 0:
			out.append({"id": id, "def": def, "count": int(_save.inventory[id])})
	return out


## The passive that isn't active: {text} for the greyed line, plus {name, slot} when
## the player can switch to it. {} for an empty rolled slot or an id the data lacks.
func _other_passive(db: Database, c: CreatureInstance) -> Dictionary:
	var slot := Passives.SLOT_ROLLED if c.active_passive == Passives.SLOT_AFFINITY else Passives.SLOT_AFFINITY
	var id := c.passive if slot == Passives.SLOT_ROLLED else c.affinity_passive
	if id == "":
		if slot == Passives.SLOT_AFFINITY:
			return {"text": "Affinity passive: unlocks when a track reaches %d" % db.balance.growth_affinity_threshold}
		return {}
	var def := db.passive(id)
	if def == null:
		return {}
	return {"text": "%s (not active)" % def.name, "name": def.name, "slot": slot}


func _render_moves(db: Database, c: CreatureInstance) -> Array:
	var lines: PackedStringArray = ["Equipped:"]
	for m in c.moves:
		lines.append("  " + LearnMoveScreen.move_line(db, m))
	for i in range(c.moves.size(), db.balance.max_moves):
		lines.append("  - empty -")
	var options: Array = []
	for m in c.move_pool:
		if not c.moves.has(m):
			options.append({"label": LearnMoveScreen.move_line(db, m), "value": {"move": m}})
	lines.append("Other known moves: pick one to swap it in." if not options.is_empty() else "No other known moves.")
	_body.text = "\n".join(lines)
	return options


func _render_train(db: Database, c: CreatureInstance) -> Array:
	var lines: PackedStringArray = ["Points to spend: %d" % Training.available(db, c)]
	if _notice != "":
		lines.append(_notice)
	_body.text = "\n".join(lines)
	var options: Array = []
	for stat in DataSchemas.TRAINABLE_STATS:
		var label: String = "+1 " + STAT_NAMES[stat]
		if c.trained(stat) > 0:
			label += "  (+%d)" % c.trained(stat)
		options.append({"label": label, "value": {"train": stat}})
	var seeds := int(_save.inventory.get("reset_seed", 0))
	options.append({"label": "Use a Reset Seed (you have %d)" % seeds, "value": "seed", "disabled": seeds <= 0})
	return options


func _render_held(db: Database, c: CreatureInstance) -> Array:
	var lines: PackedStringArray = ["Held item: " + _held_line(db, c)]
	if _notice != "":
		lines.append(_notice)
	var options: Array = []
	var bag_has := not _bag_held(db).is_empty()
	if not c.held_item.is_empty():
		if bag_has:
			options.append({"label": "Swap held item", "value": {"held": "swap"}})
		options.append({"label": "Take back", "value": {"held": "take"}})
	elif bag_has:
		options.append({"label": "Give held item", "value": {"held": "give"}})
	else:
		lines.append("No held items in the bag.")
	_body.text = "\n".join(lines)
	return options


func _act(parent: Node, db: Database, c: CreatureInstance, choice: Variant) -> void:
	_notice = ""
	if choice is Dictionary and choice.has("passive"):
		Passives.set_active(c, choice.passive)
	elif choice is Dictionary and choice.has("train"):
		_train(db, c, choice.train)
	elif choice is Dictionary and choice.has("move"):
		await LearnMoveScreen.run(parent, c, choice.move, true, _db)
	elif choice is Dictionary and choice.has("held"):
		await _held(db, c, choice.held)
	elif choice == "seed":
		if not await ResetSeedPrompt.confirm(menu, func(t: String) -> void: _body.text = t, c, _db):
			return
		var result := FieldItems.use(db, _save, "reset_seed", c)
		if result.ok:
			_notice = "%d training %s came back." % [result.refunded, "point" if result.refunded == 1 else "points"]
	elif choice == "grow":
		await GrowScreen.run(parent, c, _db)


func _held(db: Database, c: CreatureInstance, action: String) -> void:
	if action == "take":
		var known := HeldItems.def_of(db, c)
		var taken := HeldItems.take(_save, c)
		if taken.ok:
			_notice = ("Took back the %s." % known.name) if known != null else "%s took back the held item." % c.display_name(db)
		return
	var options: Array = []
	for entry in _bag_held(db):
		options.append({"label": "%s ×%d" % [entry.def.name, entry.count], "value": entry.id})
	options.append({"label": "Back", "value": null})
	_body.text = "Give %s which item?" % c.display_name(db)
	var id = await menu.choose("Pick an item.", options, true, 1)
	if id == null:
		return
	var r := HeldItems.give(db, _save, c, id)
	if r.ok:
		_notice = "%s now holds the %s." % [c.display_name(db), db.item(id).name]
	else:
		_notice = "You don't have any left."


func _train(db: Database, c: CreatureInstance, stat: String) -> void:
	match Training.train(db, c, stat, 1):
		"stat_capped":
			_notice = "%s is at the %d-point limit." % [STAT_NAMES[stat], int(db.balance.training_cfg.max_per_stat)]
		"not_enough_points":
			_notice = "No points left to spend."
