class_name SideMenu
extends CanvasLayer
## Base for the overworld's menus (pause menu, shop): a command list on the right
## and an info page on the left, over a dimmed map.

## Rows of options that fit the side panel (a longer list, e.g. a party of 12, pages).
const MENU_ROWS := 11

var menu: CommandMenu

var _root: Control
var _title: Label
var _money: Label
var _page: PanelContainer
var _text: Label


func _ready() -> void:
	layer = 65
	_root = Control.new()
	_root.theme = UIKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var side := UIKit.panel(_root, 10)
	side.position = Vector2(420, 8)
	side.custom_minimum_size = Vector2(212, 344)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	side.add_child(col)
	_title = UIKit.label(col, "", UIKit.HEADING_SIZE, UIKit.ACCENT)
	_money = UIKit.label(col, "", 11, UIKit.MUTED)
	menu = CommandMenu.new()
	menu.button_width = 192
	menu.max_rows = MENU_ROWS
	col.add_child(menu)
	_page = UIKit.panel(_root, 10)
	_page.position = Vector2(8, 8)
	_page.custom_minimum_size = Vector2(404, 0)
	_text = UIKit.label(_page, "", UIKit.BODY_SIZE, UIKit.TEXT, true)
	_text.custom_minimum_size = Vector2(384, 0)
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func page_text() -> String:
	return _text.text


func _open(title: String) -> void:
	Log.debug(Log.UI, "Screen opened", {"screen": get_script().get_global_name(), "title": title})
	_title.text = title
	_root.visible = true
	_refresh_money()
	page("")


func _close() -> void:
	Log.debug(Log.UI, "Screen closed", {"screen": get_script().get_global_name()})
	menu.show_idle()
	_root.visible = false


func page(text: String) -> void:
	_text.text = text
	_page.visible = text != ""


func _refresh_money() -> void:
	_money.text = "Money: %d" % Story.money() if GameState.has_game() else ""
