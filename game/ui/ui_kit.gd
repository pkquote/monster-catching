class_name UIKit
extends RefCounted
## Small helpers so menu screens can build placeholder UI in code consistently.
## Swap the colours and theme here when real art arrives.

const BG := Color("1b1f2a")
const PANEL := Color("262c3b")
const TEXT := Color("e8e6df")
const MUTED := Color("9aa0ae")
const ACCENT := Color("f2b950")
const DANGER := Color("e2675c")

const TITLE_SIZE := 28
const HEADING_SIZE := 16
const BODY_SIZE := 12


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = BODY_SIZE
	for type in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "TabContainer"]:
		t.set_color("font_color", type, TEXT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_hover_color", "Button", ACCENT)
	# The default unchecked box is near-invisible on the dark background.
	t.set_color("checkbox_unchecked_color", "CheckBox", MUTED)
	t.set_color("checkbox_checked_color", "CheckBox", ACCENT)
	return t


## Background + centered column. Returns the column to add widgets to.
static func screen(root: Control, title: String = "", width: int = 300) -> VBoxContainer:
	root.theme = theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", 6)
	center.add_child(col)
	if title != "":
		label(col, title, TITLE_SIZE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spacer(col, 6)
	return col


## `wrap` is for long text in a column of known width. Leave it off inside grids
## and rows, where a wrapping label collapses to one character per line.
static func label(parent: Node, text: String, size: int = BODY_SIZE, color: Color = TEXT,
		wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


static func button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## A solid rounded panel (dialogs, overlays, results).
static func panel(parent: Node, padding: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = MUTED.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(padding)
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	return p


static func spacer(parent: Node, height: int) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	parent.add_child(c)


## "2026-11-03 14:20" in local time.
static func format_time(unix: int) -> String:
	var bias_min: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(unix + bias_min * 60)
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
