class_name ProgressScreen
extends CanvasLayer
## Base for the Learn Move and Grow screens: a dimmed overlay (above the battle
## layer) with an info panel on top and a command menu below it.

var menu: CommandMenu

var _root: Control
var _title: Label
var _body: Label
var _info: HBoxContainer
var _bottom: PanelContainer


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
	var top := UIKit.panel(_root, 10)
	top.position = Vector2(8, 8)
	top.custom_minimum_size = Vector2(624, 0)
	_info = HBoxContainer.new()
	_info.add_theme_constant_override("separation", 10)
	top.add_child(_info)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(600, 0)
	_info.add_child(col)
	_title = UIKit.label(col, "", UIKit.HEADING_SIZE, UIKit.ACCENT, true)
	_body = UIKit.label(col, "", UIKit.BODY_SIZE, UIKit.TEXT, true)
	_bottom = UIKit.panel(_root, 10)
	_bottom.position = Vector2(8, 196)
	_bottom.custom_minimum_size = Vector2(624, 0)
	menu = CommandMenu.new()
	menu.button_width = 600
	_bottom.add_child(menu)


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
static func species_color(species: String) -> Color:
	var types: PackedStringArray = DataRegistry.db.creature(species).types
	return TypeColors.type_color(types[0] if types.size() > 0 else "")
