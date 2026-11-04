class_name SummaryScreen
extends ProgressScreen
## One party creature in three tabs: Stats, Moves and Training. Left/Right switch
## tab. Up/Down belong to the menu's own focus, so the previous/next creature are
## menu options and the shoulder buttons (see Settings.SHOULDER_ACTIONS).

const TABS := ["stats", "moves", "training"]
const TAB_NAMES := {"stats": "Stats", "moves": "Moves", "training": "Training"}
const STAT_NAMES := {"hp": "HP", "stamina": "Stamina", "patk": "Physical Attack", "pdef": "Physical Defense",
	"satk": "Special Attack", "sdef": "Special Defense", "spd": "Speed", "resolve": "Resolve", "luck": "Luck"}
const COLUMN_WIDTH := 296
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
static func run(parent: Node, party: Array, index: int) -> void:
	if party.is_empty():
		return
	var screen := SummaryScreen.new()
	screen._party = party
	screen._index = clampi(index, 0, party.size() - 1)
	parent.add_child(screen)
	await screen._loop(parent)
	screen.close()


func _ready() -> void:
	super()
	menu.button_width = COLUMN_WIDTH
	menu.linear_focus = true  # Up/Down must reach both columns; Left/Right belong to the tabs
	(_info.get_parent() as Control).position.y = 4
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
	var db := DataRegistry.db
	while true:
		var c := creature()
		var shown_tab := tab
		var shown_index := _index
		_title.text = "%s  Lv %d  -  %s" % [c.display_name(db), c.level, TAB_NAMES[tab]]
		var options: Array = _render(db, c)
		await get_tree().process_frame  # wrapped text needs a layout pass before it has a height
		if tab != shown_tab or _index != shown_index:
			continue  # switched during that frame (the refresh had no menu to interrupt): draw the new page
		var top: Control = _info.get_parent()
		_bottom.position.y = top.position.y + top.get_combined_minimum_size().y + 2
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
		if c.trained(key) > 0:
			text += " (+%d)" % c.trained(key)
		cells.append(text)
	for i in range(0, cells.size(), 3):
		lines.append("   ".join(cells.slice(i, i + 3)))
	if c.level >= db.balance.level_cap:
		lines.append("Max level")
	else:
		lines.append("XP to next level: %d" % (Stats.xp_for_level(c.level + 1) - c.xp))
	lines.append("Bond: %d" % c.bond)
	_body.text = "\n".join(lines)
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
	var options: Array = []
	if Progression.growth_target(db, c) != "":
		options.append({"label": "Grow", "value": "grow"})
	return options


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
	var lines: PackedStringArray = ["Points to spend: %d" % Progression.training_points_available(db, c)]
	if _notice != "":
		lines.append(_notice)
	_body.text = "\n".join(lines)
	var options: Array = []
	for stat in DataSchemas.TRAINABLE_STATS:
		var label: String = "+1 " + STAT_NAMES[stat]
		if c.trained(stat) > 0:
			label += "  (+%d)" % c.trained(stat)
		options.append({"label": label, "value": {"train": stat}})
	var seeds := int(GameState.current.inventory.get("reset_seed", 0))
	options.append({"label": "Use a Reset Seed (you have %d)" % seeds, "value": "seed", "disabled": seeds <= 0})
	return options


func _act(parent: Node, db: Database, c: CreatureInstance, choice: Variant) -> void:
	_notice = ""
	if choice is Dictionary and choice.has("train"):
		_train(db, c, choice.train)
	elif choice is Dictionary and choice.has("move"):
		await LearnMoveScreen.run(parent, c, choice.move)
	elif choice == "seed":
		if not await ResetSeedPrompt.confirm(menu, func(t: String) -> void: _body.text = t, c):
			return
		var result := FieldItems.use(db, GameState.current, "reset_seed", c)
		if result.ok:
			_notice = "%d training %s came back." % [result.refunded, "point" if result.refunded == 1 else "points"]
		elif result.error == "nothing_to_refund":
			_notice = "%s has no training to reset." % c.display_name(db)
	elif choice == "grow":
		await GrowScreen.run(parent, c)


func _train(db: Database, c: CreatureInstance, stat: String) -> void:
	match Progression.train(db, c, stat, 1):
		"stat_capped":
			_notice = "%s is at the %d-point limit." % [STAT_NAMES[stat], int(db.balance.training_cfg.max_per_stat)]
		"not_enough_points":
			_notice = "No points left to spend."
