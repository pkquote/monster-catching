class_name SummaryScreen
extends ProgressScreen
## One party creature in three tabs: Stats, Moves and Training. Left/Right switch
## tab. Up/Down belong to the menu's own focus, so the previous/next creature are
## menu options and the shoulder buttons (see Settings.SHOULDER_ACTIONS).

const TABS := ["stats", "moves", "training"]
const TAB_NAMES := {"stats": "Stats", "moves": "Moves", "training": "Training"}
const STAT_NAMES := {"hp": "HP", "stamina": "Stamina", "patk": "Physical Attack", "pdef": "Physical Defense",
	"satk": "Special Attack", "sdef": "Special Defense", "spd": "Speed", "resolve": "Resolve", "luck": "Luck"}
const COLUMN_WIDTH := ProgressScreen.HALF_WIDTH
## Longest "Held item" text shown (name and description), so it stays on one line.
const HELD_LINE_MAX := 80
const REFRESH := "@refresh"
const PREV := "@prev"
const NEXT := "@next"

var tab := "stats"

var _party: Array
var _index := 0
var _notice := ""
var _last: Variant = null  # the option picked last: it keeps the focus across the re-render
var _busy := false  # a sub-screen is open: leave the keys to it
var _extra: VBoxContainer


## Runs until the player closes the screen.
static func run(parent: Node, party: Array, index: int, save: SaveGame = null, db: Database = null) -> void:
	if party.is_empty():
		return
	var screen := SummaryScreen.new()
	screen.use_game(save, db)
	screen._party = party
	screen._index = clampi(index, 0, party.size() - 1)
	parent.add_child(screen)
	await screen._loop(parent)
	screen.close()


func _ready() -> void:
	super()
	menu.button_width = COLUMN_WIDTH
	menu.linear_focus = true  # Up/Down must reach both columns; Left/Right belong to the tabs
	_extra = VBoxContainer.new()
	_body.get_parent().add_child(_extra)


## The creature being shown.
func creature() -> CreatureInstance:
	return _party[_index]


func show_tab(name: String) -> void:
	if not TABS.has(name):
		return
	tab = name
	_notice = ""
	_last = null
	menu.interrupt(REFRESH)


## Steps through the tabs, wrapping.
func next_tab(step: int = 1) -> void:
	show_tab(TABS[posmod(TABS.find(tab) + step, TABS.size())])


func show_creature(index: int) -> void:
	if index < 0 or index >= _party.size():
		return
	_index = index
	_notice = ""
	_last = null
	menu.interrupt(REFRESH)


## `_input`, not `_unhandled_input`: the menu's GUI focus navigation would otherwise
## take Left/Right first.
func _input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("ui_right"):
		next_tab(1)
	elif event.is_action_pressed("ui_left"):
		next_tab(-1)
	elif event.is_action_pressed("next_creature"):
		show_creature(_index + 1)
	elif event.is_action_pressed("prev_creature"):
		show_creature(_index - 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _loop(parent: Node) -> void:
	var db := _db
	while true:
		var c := creature()
		_title.text = "%s  Lv %d  -  %s" % [c.display_name(db), c.level, TAB_NAMES[tab]]
		var options: Array = _render(db, c)
		if _party.size() > 1:
			options.append({"label": "Previous creature", "value": PREV})
			options.append({"label": "Next creature", "value": NEXT})
		options.append({"label": "Back", "value": null})
		if _last != null:
			for o in options:
				o["focus"] = typeof(o.value) == typeof(_last) and o.value == _last
		var choice = await menu.choose("Left / Right: switch tab", options, true, 2)
		if choice == null:
			return
		_last = choice
		if choice is String and choice.begins_with("@"):
			match choice:
				PREV:
					show_creature(posmod(_index - 1, _party.size()))
				NEXT:
					show_creature(posmod(_index + 1, _party.size()))
			continue
		_busy = true
		await _act(parent, db, c, choice)
		_busy = false


## Fills the page and returns the tab's own menu options.
func _render(db: Database, c: CreatureInstance) -> Array:
	for n in _extra.get_children():
		n.queue_free()
	match tab:
		"moves":
			return _render_moves(db, c)
		"training":
			return _render_training(db, c)
	return _render_stats(db, c)


func _render_stats(db: Database, c: CreatureInstance) -> Array:
	var lines: PackedStringArray = []
	var cells: PackedStringArray = []
	for key in ["hp", "stamina", "patk", "pdef", "satk", "sdef", "spd", "resolve", "luck"]:
		var value := c.max_hp(db) if key == "hp" else c.max_energy(db) if key == "stamina" else c.stat(db, key)
		var text := "%s %d" % [STAT_NAMES[key], value]
		# ▲ / ▼: this species grows the stat faster / slower than steady.
		var tier := db.creature(c.species).growth_tier(key)
		var multiplier: float = db.balance.growth_tiers.get(tier, 1.0)
		if multiplier > 1.0:
			text += "▲"
		elif multiplier < 1.0:
			text += "▼"
		# Growth from the species and level, then what training added on top.
		if c.trained(key) > 0:
			text += " (%d+%d)" % [c.grown(db, key), value - c.grown(db, key)]
		cells.append(text)
	for i in range(0, cells.size(), 3):
		lines.append("   ".join(cells.slice(i, i + 3)))
	if c.level >= db.balance.level_cap:
		lines.append("Max level")
	else:
		lines.append("XP to next level: %d" % (Stats.xp_for_level(c.level + 1) - c.xp))
	lines[lines.size() - 1] += "   Bond: %d" % c.bond
	var active := PassiveUnlockScreen.passive_line(db, Passives.active_id(c))
	lines.append("Passive: " + (active if active != "" else "none"))
	lines.append("Held item: " + _held_line(db, c))
	if _notice != "":
		lines.append(_notice)
	_body.text = "\n".join(lines)
	var options: Array = []
	var other := _other_passive(db, c)
	if other.has("text"):
		UIKit.label(_extra, other.text, UIKit.BODY_SIZE, UIKit.MUTED, true)
	if other.has("slot"):
		options.append({"label": "Use " + other.name, "value": {"passive": other.slot}})
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	_extra.add_child(grid)
	for id in db.ids("affinities"):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		UIKit.label(row, db.affinity(id).name, UIKit.BODY_SIZE, UIKit.MUTED).custom_minimum_size = Vector2(64, 0)
		var points := int(c.affinity.get(id, 0))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = maxi(db.balance.growth_affinity_threshold, points)
		bar.value = points
		bar.custom_minimum_size = Vector2(150, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		UIKit.label(row, str(points), UIKit.BODY_SIZE)
		grid.add_child(row)
	var bag_has := not _bag_held(db).is_empty()
	if not c.held_item.is_empty():
		options.append({"label": "Take back", "value": {"held": "take"}})
		if bag_has:
			options.push_front({"label": "Swap held item", "value": {"held": "swap"}})
	elif bag_has:
		options.append({"label": "Give held item", "value": {"held": "give"}})
	if Progression.growth_target(db, c) != "":
		options.push_front({"label": "Grow", "value": "grow"})
	return options


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


func _render_training(db: Database, c: CreatureInstance) -> Array:
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
	var id = await menu.choose("Pick an item.", options, true, 2)
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
