class_name ProgressScreen
extends CanvasLayer
## Base for the progression screens (Learn Move, Grow, Party, Summary, Storage): a
## dimmed overlay above the battle layer, laid out by containers, never by hand:
##
##   info panel   title + body text (+ anything a screen adds to `_info`); as tall as it needs
##   menu area    the rest of the screen; scrolls (following keyboard focus) when the menu
##                panel inside it is taller than the space left
##
## Screens only fill in the text and the options. Set `menu.button_width` to
## MENU_WIDTH for one column or HALF_WIDTH for two (wider buttons widen the screen).

const MARGIN := 4
const GAP := 2
## Button widths that fill the menu panel: one column, or two side by side.
const MENU_WIDTH := 600
const HALF_WIDTH := 296

var menu: CommandMenu

## The playthrough and content this screen works on: whatever use_game() was given,
## else the current game and content, looked up when used (never stale).
## run() takes them as arguments so screens can be opened on any save (tests).
var _save: SaveGame:
	get:
		return _save_override if _save_override != null else GameState.current
var _db: Database:
	get:
		return _db_override if _db_override != null else DataRegistry.db
var _save_override: SaveGame
var _db_override: Database

var _root: Control
var _title: Label
var _body: Label
var _info: HBoxContainer
var _top: PanelContainer
var _scroll: ScrollContainer
var _bottom: PanelContainer
var _side: Control


func _ready() -> void:
	Log.debug(Log.UI, "Screen opened", {"screen": get_script().get_global_name()})
	layer = 72
	_root = Control.new()
	_root.theme = UIKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", GAP)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _side != null:
		# A side control (set_side) takes the left; the info panel and menu use the rest.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", GAP)
		margin.add_child(row)
		_side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(_side)
		row.add_child(column)
	else:
		margin.add_child(column)
	_top = UIKit.panel(column, 10)
	_info = HBoxContainer.new()
	_info.add_theme_constant_override("separation", 10)
	_top.add_child(_info)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_child(col)
	_title = UIKit.label(col, "", UIKit.HEADING_SIZE, UIKit.ACCENT, true)
	_body = UIKit.label(col, "", UIKit.BODY_SIZE, UIKit.TEXT, true)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_bottom = UIKit.panel(_scroll, 8)
	_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # only as tall as its options
	menu = CommandMenu.new()
	menu.button_width = MENU_WIDTH
	_bottom.add_child(menu)


## Puts `control` to the left of the info panel and the menu. Call before the screen joins the tree.
func set_side(control: Control) -> void:
	_side = control


func side_control() -> Control:
	return _side


## Points the screen at `save` / `db` (null keeps the current game's / the content).
func use_game(save: SaveGame, db: Database) -> void:
	if save != null:
		_save_override = save
	if db != null:
		_db_override = db


## The panel with the title and body text.
func info_panel() -> Control:
	return _top


## The space below the info panel that holds (and scrolls) the menu.
func menu_area() -> Control:
	return _scroll


## The panel around the menu itself (inside the menu area).
func menu_panel() -> Control:
	return _bottom


func title_text() -> String:
	return _title.text


func page_text() -> String:
	return _body.text


## Detaches and frees the screen. Deferred so it is safe from a menu's signal.
func close() -> void:
	Log.debug(Log.UI, "Screen closed", {"screen": get_script().get_global_name()})
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()


## The placeholder sprite colour for a species: its first type's colour.
static func species_color(species: String, db: Database = null) -> Color:
	var types: PackedStringArray = (db if db != null else DataRegistry.db).creature(species).types
	return TypeColors.type_color(types[0] if types.size() > 0 else "")
