extends CanvasLayer
## Debug tools on any screen: press F1. Debug builds only (the editor, the
## run-skill driver, tests); exported release builds never open it.
##
## Pauses the game while open. This node is the shell (open/close, paging, shared
## helpers); each page lives in game/debug/pages/ (DebugPage). Party tools need a
## loaded game; battles can't be started from inside a battle. Autoload: DebugMenu.

const TOGGLE_KEY := KEY_F1
## Tallest a page may be (the panel adds its padding): keeps the panel on the 360px screen.
const MAX_PAGE_HEIGHT := 320.0

## Shared by the pages that roll random things (wild packs, box fill, custom foes).
var rng := RandomNumberGenerator.new()

var _root: Control
var _box: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _page: DebugPage
var _restore_focus: Control
## The Logs page's text view while that page is open (tests read it).
var _log_view: TextEdit:
	get:
		return (_page as DebugLogsPage).view if _page is DebugLogsPage else null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()


func is_open() -> bool:
	return _root != null


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or SceneRouter.is_busy():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == TOGGLE_KEY:
		get_viewport().set_input_as_handled()
		if is_open():
			close()
		else:
			open()


func open() -> void:
	if is_open() or (Overworld.active != null and Overworld.active.blocks_debug_menu()):
		return
	_restore_focus = get_viewport().gui_get_focus_owner()
	get_tree().paused = true
	_root = Control.new()
	_root.theme = UIKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := UIKit.panel(center, 12)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_scroll.add_child(_box)
	show_page(DebugMainPage.new())


func close() -> void:
	if not is_open():
		return
	_root.queue_free()
	_root = null
	_scroll = null
	_box = null
	_page = null
	get_tree().paused = false
	if is_instance_valid(_restore_focus) and _restore_focus.is_inside_tree():
		_restore_focus.grab_focus()
	_restore_focus = null


# --- Pages -------------------------------------------------------------------------

## Replaces the open page with `page`, showing `status` under its title.
func show_page(page: DebugPage, status := "") -> void:
	if not is_open():
		return
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_page = page
	page.menu = self
	_box.custom_minimum_size = Vector2(page.width(), 0)
	UIKit.label(_box, page.title(), UIKit.HEADING_SIZE, UIKit.ACCENT)
	_status = UIKit.label(_box, status, UIKit.BODY_SIZE, UIKit.ACCENT)  # up here: always in view
	page.build(_box)
	_focus_first()


## Rebuilds the open page from its own fields, keeping keyboard focus on the same
## control (by position) so a change doesn't throw the focus back to the top.
func refresh_page(status := "") -> void:
	if not is_open() or _page == null:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	var index: int = _find_focusable(_box).find(focused) if focused != null else -1
	show_page(_page, status)
	if index < 0:
		return
	(func() -> void:  # after _focus_first's own deferred grab
		if not is_open():
			return
		var list: Array = _find_focusable(_box)
		if index < list.size() and is_instance_valid(list[index]) and list[index].is_inside_tree():
			list[index].grab_focus()).call_deferred()


func set_status(text: String) -> void:
	if _status != null and is_instance_valid(_status):
		_status.text = text


# --- Logs page passthroughs (tests drive the page through these) --------------------
# They act only while the Logs page is the open page; otherwise they do nothing.

func log_lines() -> PackedStringArray:
	return (_page as DebugLogsPage).lines() if _page is DebugLogsPage else PackedStringArray()


func set_log_filter(min_level: Log.Level, category: String) -> void:
	if _page is DebugLogsPage:
		(_page as DebugLogsPage).set_filter(min_level, category)


func set_category_level(category: String, level: Log.Level) -> void:
	if _page is DebugLogsPage:
		(_page as DebugLogsPage).set_level(category, level)


# --- Helpers shared by the pages ---------------------------------------------------

## The party and battle tools only make sense on the overworld, with nothing else going on.
func tools_blocked() -> bool:
	return Overworld.active == null or Overworld.active.is_locked()


## Lets the current screen redraw anything that shows the party or bag.
func refresh_world() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("refresh_hud"):
		scene.refresh_hud()


## The shared "how many?" prompt; back to the main page when cancelled.
func ask(format_size: int, intro: String) -> Variant:
	var n = await FieldCountPrompt.ask(self, format_size, intro)
	if n == null and is_open():
		show_page(DebugMainPage.new())
	return n


## "How many?", then the battle `build.call(count)` returns. Runs here, on the
## autoload, not on the page: closing the menu during the prompt frees the page,
## and the pick must still start the battle. `build` should be a static function.
func ask_then_go(format_size: int, intro: String, build: Callable) -> void:
	var n = await ask(format_size, intro)
	if n != null:
		go(build.call(n))


## Starts a battle over the overworld. Debug battles use the normal defeat rules,
## except exhibitions (the custom battle), which have none.
func go(setup: BattleSetup) -> void:
	close()
	if Overworld.active != null:
		Overworld.active.battles.run_battle(setup, not setup.exhibition)


## A label and a drop-down in `grid`.
func option_row(grid: GridContainer, text: String, choices: Array, selected: int) -> OptionButton:
	UIKit.label(grid, text)
	var o := OptionButton.new()
	for c in choices:
		o.add_item(c)
	o.selected = selected
	grid.add_child(o)
	return o


## A label and a whole-number spin box in `grid` (or any container).
func spin_row(grid: Container, text: String, min_value: int, max_value: int, value: int) -> SpinBox:
	UIKit.label(grid, text)
	var s: SpinBox = SpinBox.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = 1
	s.rounded = true
	s.value = value
	grid.add_child(s)
	return s


## A "Creature" drop-down listing the party.
func creature_picker(box: VBoxContainer) -> OptionButton:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	var db := DataRegistry.db
	var names := GameState.current.party.map(
		func(c: CreatureInstance): return "%s Lv %d" % [c.display_name(db), c.level])
	return option_row(grid, "Creature", names, 0)


## Focus the first button; and let a page taller than the screen scroll (focus follows).
func _focus_first() -> void:
	_scroll.custom_minimum_size.y = minf(_box.get_combined_minimum_size().y, MAX_PAGE_HEIGHT)
	for c in _find_focusable(_box):
		# Deferred until the page is laid out; the page may be rebuilt or closed first.
		(func() -> void:
			if is_instance_valid(c) and c.is_inside_tree():
				c.grab_focus()).call_deferred()
		return


func _find_focusable(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is BaseButton and not c.disabled:
			out.append(c)
		out.append_array(_find_focusable(c))
	return out
