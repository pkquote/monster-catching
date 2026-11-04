extends Control
## The battle screen. Owns a BattleEngine, collects the player's choices, plays
## back the engine's events, and writes the outcome into the save at the end.
##
## Open it with SceneRouter.goto(SceneRouter.BATTLE, {"setup": BattleSetup}), or as an
## overlay: instance it, set `params` before adding it, and await `finished` (the
## overworld does this so a map and any running conversation survive the battle).
## Optional params: "seed" (int), "return_to" (scene path, default the world).

const STAGE_H := 236
## Top-left of each creature view, by side and number of slots on that side.
const FORMATION := [
	{1: [Vector2(90, 150)], 2: [Vector2(40, 120), Vector2(160, 170)],
		3: [Vector2(10, 100), Vector2(105, 140), Vector2(200, 180)]},
	{1: [Vector2(390, 60)], 2: [Vector2(320, 85), Vector2(450, 30)],
		3: [Vector2(290, 105), Vector2(390, 58), Vector2(470, 10)]},
]

## Emitted instead of changing scene when opened as an overlay (params set).
signal finished(summary: BattleSummary)

## Overlay mode: set before adding to the tree. Empty = read SceneRouter.params.
var params: Dictionary = {}
var db: Database
var engine: BattleEngine
var setup: BattleSetup
var tamer_name := ""
## "starting" | "command" | "playback" | "replace" | "results" | "done"
var phase := "starting"

var stage: StageView
var views: Dictionary = {}  # bid -> CreatureView
var fields: Array[FieldView] = []
var menu: CommandMenu
var continue_button: Button
var summary: BattleSummary

var _actors: Control
var _message: Label
var _banner: Label
var _log: Array = []
var _results_panel: Control


func _ready() -> void:
	db = DataRegistry.db
	if params.is_empty():
		params = SceneRouter.params
	setup = params.get("setup")
	if setup == null:
		SceneRouter.goto.call_deferred(SceneRouter.WORLD)
		return
	if setup.tamer_id != "":
		tamer_name = db.tamer(setup.tamer_id).name
	elif not setup.is_wild:
		tamer_name = setup.foe_name if setup.foe_name != "" else "Foe"
	var rng := RandomNumberGenerator.new()
	if params.has("seed"):
		rng.seed = int(params.seed)
	else:
		rng.randomize()
	engine = BattleEngine.new(db, rng, setup)
	_build_ui()
	_run()


# --- Flow --------------------------------------------------------------------------

func _run() -> void:
	await _play(engine.start())
	while not engine.is_over():
		var actions := await _command_phase()
		await _play(engine.resolve_round(actions))
		_sync_views()
		while not engine.is_over() and engine.pending_replacements(0) > 0:
			if not await _replacement_phase():
				break
	await _results()


func _play(events: Array) -> void:
	phase = "playback"
	menu.show_idle()
	var pb := BattlePlayback.new(self, db)
	for ev in events:
		await pb.play(ev)


func _command_phase() -> Array:
	phase = "command"
	var needed := engine.actions_needed(0)
	var actions: Array = []
	var i := 0
	while i < needed.size():
		var a = await _choose_action(needed[i], actions)
		if a == null:
			if i > 0:
				i -= 1
				actions.pop_back()
			continue
		actions.append(a)
		i += 1
		if a.kind == "flee":
			break
	if Settings.data.confirm_end_turn and not actions.is_empty():
		var ok = await menu.choose("End your turn?", [{"label": "Yes, go!", "value": true}, {"label": "No, go back", "value": false}], true, 2)
		if ok != true:
			return await _command_phase()
	return actions


## One action for creature `bid`, or null if the player backs out.
func _choose_action(bid: int, planned: Array) -> BattleAction:
	var b := engine.battler(bid)
	var who := display_name(bid)
	var nth := planned.filter(func(a): return a.actor == bid).size()
	var title := "What will %s do?%s" % [who, "  (extra action)" if nth > 0 else ""]
	_highlight(bid)
	while true:
		var bench := _swap_choices(planned)
		var items := _item_choices()
		var options := [
			{"label": "Fight", "value": "fight"},
			{"label": "Items", "value": "items", "disabled": items.is_empty()},
			{"label": "Swap", "value": "swap", "disabled": bench.is_empty()},
			{"label": "Rest", "value": "rest", "disabled": b.energy() >= b.creature.max_energy(db)},
		]
		if setup.is_wild:
			options.append({"label": "Run", "value": "run"})
		var cmd = await menu.choose(title, options, true)
		var action: BattleAction = null
		match cmd:
			null:
				_highlight(-1)
				return null
			"fight":
				action = await _choose_move(bid)
			"items":
				action = await _choose_item(bid, items)
			"swap":
				var to = await menu.choose("Swap %s for...?" % who, bench, true)
				if to != null:
					action = BattleAction.swap(bid, to)
			"rest":
				action = BattleAction.rest(bid)
			"run":
				action = BattleAction.flee(bid)
		if action != null:
			_highlight(-1)
			return action
	return null


func _choose_move(bid: int) -> BattleAction:
	var b := engine.battler(bid)
	var options: Array = []
	var moves := Array(b.creature.moves)
	moves.append(engine.fallback_move())
	for mid in moves:
		var m := db.move(mid)
		var cat: String = {"physical": "P", "special": "S", "status": "—"}[m.category]
		var power := "" if m.power == 0 else str(m.power)
		var cost := "free" if m.cost == 0 else "%d EN" % m.cost
		options.append({"label": "%s · %s %s%s · %s" % [m.name, db.type_def(m.type).name, cat, power, cost],
			"value": mid, "disabled": m.cost > b.energy()})
	while true:
		var mid = await menu.choose("%s: choose a move  (EN %d/%d)" % [display_name(bid), b.energy(), b.creature.max_energy(db)], options, true)
		if mid == null:
			return null
		var target = await _choose_target(bid, db.move(mid).target, "Use %s on...?" % db.move(mid).name)
		if target != null:
			return BattleAction.use_move(bid, mid, target)
	return null


## Target bid, -1 when the move needs no choice, or null if cancelled.
func _choose_target(bid: int, target_key: String, title: String, include_bench := false) -> Variant:
	var pool: Array = []
	var me := engine.battler(bid)
	match target_key:
		"one_enemy":
			pool = engine.sides[1 - me.side].active()
		"one_ally":
			pool = engine.sides[me.side].battlers.filter(func(x): return x.alive()) if include_bench \
				else engine.sides[me.side].active()
		_:
			return -1
	if pool.size() == 1:
		return pool[0].bid
	var options := pool.map(func(t: Battler): return {
		"label": "%s · %d%% HP" % [display_name(t.bid), roundi(100.0 * t.hp() / t.creature.max_hp(db))],
		"value": t.bid, "hint": t.bid})
	return await menu.choose(title, options, true)


func _item_choices() -> Array:
	var out: Array = []
	var bag: Dictionary = engine.sides[0].items
	for id in bag:
		var count := int(bag[id])
		var item := db.item(id)
		if count <= 0 or item == null or item.category == "key" or item.category == "training":
			continue
		if item.category == "capture" and not setup.is_wild:
			continue
		out.append({"label": "%s ×%d" % [item.name, count], "value": id})
	return out


func _choose_item(bid: int, items: Array) -> BattleAction:
	while true:
		var id = await menu.choose("Use which item?", items, true)
		if id == null:
			return null
		var item := db.item(id)
		var target = await _choose_target(bid, item.target, "Use %s on...?" % item.name, true)
		if target != null:
			return BattleAction.use_item(bid, id, target)
	return null


func _swap_choices(planned: Array) -> Array:
	var taken := planned.filter(func(a): return a.kind == "swap").map(func(a): return a.swap_in)
	return engine.sides[0].bench().filter(func(c: Battler): return not taken.has(c.bid)).map(func(c: Battler): return {
		"label": "%s Lv %d · %d%% HP" % [display_name(c.bid), c.creature.level, roundi(100.0 * c.hp() / c.creature.max_hp(db))],
		"value": c.bid})


## Returns false if the player chose to leave the slot empty.
func _replacement_phase() -> bool:
	phase = "replace"
	var options := engine.sides[0].bench().map(func(c: Battler): return {
		"label": "%s Lv %d · %d%% HP" % [display_name(c.bid), c.creature.level, roundi(100.0 * c.hp() / c.creature.max_hp(db))],
		"value": c.bid})
	options.append({"label": "Leave the slot empty", "value": -1})
	var bid = await menu.choose("Send out who?", options, false)
	if bid == null or bid == -1:
		return false
	await _play(engine.replace(0, bid))
	return true


func _results() -> void:
	phase = "results"
	menu.show_idle()
	var res := engine.result()
	if GameState.has_game():
		summary = BattleLauncher.apply_results(db, GameState.current, engine)
	else:
		summary = BattleSummary.of(BattleSummary.WON if res.winner == 0 else BattleSummary.LOST, [], setup.tamer_id)
	_show_results(res)


# --- Results panel ------------------------------------------------------------------

func _show_results(res: Dictionary) -> void:
	_results_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIKit.PANEL, 0.97)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_results_panel.add_theme_stylebox_override("panel", style)
	_results_panel.custom_minimum_size = Vector2(380, 0)
	_results_panel.position = Vector2(130, 24)
	add_child(_results_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_results_panel.add_child(col)
	var titles := {BattleSummary.WON: "Victory!", BattleSummary.CAPTURED: "Caught!", BattleSummary.LOST: "Defeated...",
		BattleSummary.FLED: "Escaped", BattleSummary.DRAW: "Draw"}
	UIKit.label(col, titles.get(summary.outcome, "Battle over"), UIKit.HEADING_SIZE, UIKit.ACCENT)
	for line in result_lines(res):
		UIKit.label(col, line, 11, UIKit.TEXT, true)
	UIKit.spacer(col, 4)
	continue_button = UIKit.button(col, "Continue", _leave)
	continue_button.grab_focus.call_deferred()


## Human-readable lines summarising XP, levels, moves, Bond, Affinity and rewards.
func result_lines(res: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var xp := {}
	var levels := {}
	var learned := {}
	var bond := {}
	for ev in _log:
		var bid := int(ev.get("bid", -1))
		var b := engine.battler(bid)
		if b == null or b.side != 0:
			continue
		match ev.type:
			"xp_gain": xp[bid] = int(xp.get(bid, 0)) + int(ev.amount)
			"level_up": levels[bid] = int(ev.level)
			"move_learned": learned[bid] = learned.get(bid, []) + [db.move(ev.move).name]
			"bond": bond[bid] = int(bond.get(bid, 0)) + int(ev.change)
	for b in engine.sides[0].battlers:
		var bits := PackedStringArray()
		if xp.has(b.bid):
			bits.append("+%d XP" % xp[b.bid])
		if levels.has(b.bid):
			bits.append("reached Lv %d" % levels[b.bid])
		if learned.has(b.bid):
			bits.append("learned " + ", ".join(learned[b.bid]))
		if bond.has(b.bid) and bond[b.bid] != 0:
			bits.append("Bond %+d" % bond[b.bid])
		var aff: Dictionary = res.affinity.get(b.bid, {})
		for a in aff:
			bits.append("%s +%d" % [db.affinity(a).name, aff[a]])
		if not bits.is_empty():
			lines.append("%s: %s" % [display_name(b.bid), ", ".join(bits)])
	for caught in summary.captured:
		lines.append("%s joined your %s." % [caught, "party" if summary.to_storage == 0 else "storage"])
	if summary.money > 0:
		lines.append("Received %d money." % summary.money)
	if summary.outcome == BattleSummary.LOST:
		lines.append("You hurried back to safety..." if params.get("defeat_rules", true)
			else "Your team was patched up.")
	if lines.is_empty():
		lines.append("Nothing gained this time.")
	return lines


func _leave() -> void:
	phase = "done"
	if params.get("overlay", false):
		finished.emit(summary)
	else:
		SceneRouter.goto(params.get("return_to", SceneRouter.WORLD))


# --- View management (used by BattlePlayback) ---------------------------------------

func display_name(bid: int) -> String:
	var b := engine.battler(bid)
	if b == null:
		return "?"
	var n := b.creature.display_name(db)
	if b.side == 1:
		return ("Wild " if setup.is_wild else "Foe ") + n
	return n


func place_view(bid: int, side: int, slot: int) -> CreatureView:
	var v: CreatureView = views.get(bid)
	if v == null:
		var b := engine.battler(bid)
		v = CreatureView.new()
		v.setup(bid, side, display_name(bid), b.creature.level, b.creature.species_def(db).types)
		_actors.add_child(v)
		views[bid] = v
	var slots := engine.sides[side].slots.size()
	var spots: Array = FORMATION[side].get(slots, FORMATION[side][3])
	v.position = spots[mini(slot, spots.size() - 1)]
	v.visible = true
	v.modulate.a = 1.0
	v.scale = Vector2.ONE
	v.rotation = 0.0
	var status := engine.battler(bid).status()
	v.set_status(status, db.status(status).name if status != "" else "")
	return v


func release_view(bid: int) -> void:
	if views.has(bid):
		views[bid].visible = false


func message(text: String) -> void:
	_message.text = text


func banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_banner, "modulate:a", 1.0, BattlePlayback.scaled(0.15))
	t.tween_interval(BattlePlayback.scaled(0.6))
	t.tween_property(_banner, "modulate:a", 0.0, BattlePlayback.scaled(0.2))
	await t.finished
	_banner.visible = false


func record(ev: Dictionary) -> void:
	_log.append(ev)


## After a round, make every view match the engine exactly (levels, max HP, countdowns).
func _sync_views() -> void:
	for bid in views:
		var b := engine.battler(bid)
		var v: CreatureView = views[bid]
		v.set_hp(b.hp(), b.creature.max_hp(db), false)
		v.set_energy(b.energy(), b.creature.max_energy(db))
		v.set_level(display_name(bid), b.creature.level)
		v.set_status(b.status(), db.status(b.status()).name if b.status() != "" else "")
	for side in 2:
		fields[side].sync(engine.sides[side].field)
		fields[side].set_underdog(int(engine.sides[side].underdog.get("bonus_actions", 0)),
			float(engine.sides[side].underdog.get("ratio", 1.0)))
		stage.set_tint(side, fields[side].newest_color())


func _highlight(bid: Variant) -> void:
	for k in views:
		views[k].set_highlight(bid != null and k == bid)


# --- UI construction ------------------------------------------------------------------

func _build_ui() -> void:
	theme = UIKit.theme()
	stage = StageView.new()
	stage.position = Vector2.ZERO
	stage.size = Vector2(640, STAGE_H)
	add_child(stage)
	_actors = Control.new()
	_actors.size = stage.size
	_actors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_actors)
	for side in 2:
		var f := FieldView.new()
		f.setup(side, db)
		# Yours along the bottom-right edge of the stage (growing leftwards), the foe's top-left.
		if side == 0:
			f.position = Vector2(232, 214)
			f.size = Vector2(400, 18)
			f.alignment = BoxContainer.ALIGNMENT_END
		else:
			f.position = Vector2(8, 6)
		add_child(f)
		fields.append(f)
	_banner = UIKit.label(self, "", UIKit.TITLE_SIZE, UIKit.ACCENT)
	_banner.position = Vector2(0, 92)
	_banner.size = Vector2(640, 40)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.visible = false

	var panel := ColorRect.new()
	panel.color = UIKit.PANEL
	panel.position = Vector2(0, STAGE_H)
	panel.size = Vector2(640, 360 - STAGE_H)
	add_child(panel)
	_message = UIKit.label(self, "", UIKit.BODY_SIZE, UIKit.TEXT, true)
	_message.position = Vector2(10, STAGE_H + 4)
	_message.size = Vector2(620, 18)
	menu = CommandMenu.new()
	menu.position = Vector2(10, STAGE_H + 22)
	menu.size = Vector2(620, 98)
	add_child(menu)
	menu.hovered.connect(func(hint): _highlight(hint))
