class_name DebugLogsPage
extends DebugPage
## Recent log records (newest first) filtered by a minimum level and a category,
## the live level of each category, and where the session files are.

const VIEW_LINES := 300
const LEVELS: Array = [Log.Level.TRACE, Log.Level.DEBUG, Log.Level.INFO, Log.Level.WARN, Log.Level.ERROR]

## Kept between visits to the page.
static var min_level: Log.Level = Log.Level.DEBUG
static var category := ""

var view: TextEdit


func title() -> String:
	return "Logs"


func width() -> float:
	return 580.0


func build(box: VBoxContainer) -> void:
	var filters := GridContainer.new()
	filters.columns = 4
	filters.add_theme_constant_override("h_separation", 8)
	box.add_child(filters)
	var shown: OptionButton = menu.option_row(filters, "Show at least", LEVELS.map(Log.level_name), LEVELS.find(min_level))
	shown.item_selected.connect(func(i: int) -> void: set_filter(LEVELS[i], category))
	var cats: Array = [""] + Array(Log.CATEGORIES)
	var cat: OptionButton = menu.option_row(filters, "Category", cats.map(func(c): return "all" if c == "" else c),
		cats.find(category))
	cat.item_selected.connect(func(i: int) -> void: set_filter(min_level, cats[i]))
	view = TextEdit.new()
	view.editable = false
	view.focus_mode = Control.FOCUS_NONE  # keyboard focus skips it (it would swallow Up/Down); the wheel scrolls it
	view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	view.custom_minimum_size = Vector2(width(), 110)
	view.add_theme_font_size_override("font_size", 10)
	box.add_child(view)
	refresh()
	UIKit.label(box, "Levels (change live; Save keeps them)", 11, UIKit.MUTED)
	var levels := GridContainer.new()
	levels.columns = 6
	levels.add_theme_constant_override("h_separation", 8)
	box.add_child(levels)
	var all_levels: Array = LEVELS + [Log.Level.OFF]
	for c in ["default"] + Array(Log.CATEGORIES):
		var current: Log.Level = Log.default_level if c == "default" else Log.level_of(c)
		var pick: OptionButton = menu.option_row(levels, c, all_levels.map(Log.level_name), all_levels.find(current))
		pick.item_selected.connect(func(i: int) -> void: set_level(c, all_levels[i]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	UIKit.button(row, "Save levels", func() -> void:
		menu.set_status("Levels saved." if Logging.save_levels() == OK else "Couldn't save the levels."))
	UIKit.button(row, "Open log folder", func() -> void: OS.shell_open(Logging.log_dir()))
	UIKit.button(row, "Refresh", refresh)
	UIKit.button(row, "Back", func() -> void: menu.show_page(DebugMainPage.new()))


## Shows records at or above `p_min_level` in `p_category` ("" = all).
func set_filter(p_min_level: Log.Level, p_category: String) -> void:
	min_level = p_min_level
	category = p_category
	refresh()


## Changes a category's level ("default" changes the fallback level) right away.
func set_level(p_category: String, level: Log.Level) -> void:
	if p_category == "default":
		Log.default_level = level
	else:
		Log.set_level(p_category, level)
	Log.info(Log.SETTINGS, "Log level changed", {"category": p_category, "level": Log.level_name(level)})
	var note := "%s: %s" % [p_category, Log.level_name(level)]
	if p_category == "default":
		menu.show_page(DebugLogsPage.new(), note)  # categories that follow the default show the new value
	else:
		menu.set_status(note)


## The lines the page is showing (newest first).
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for r in Logging.memory.filtered(min_level, category).slice(0, VIEW_LINES):
		out.append(Log.format(r))
	return out


func refresh() -> void:
	if view == null or not is_instance_valid(view):
		return
	var shown := lines()
	view.text = "\n".join(shown) if not shown.is_empty() else "(nothing at this level yet)"
