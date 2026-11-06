class_name BagSummary
extends VBoxContainer
## The bag's left pane: the focused item's icon beside its name, category and count, then
## its price, description, effect and whether it can be used from the bag right now.
## Sized for SideMenu's info page (404 wide, 10px padding, at most 344 tall): long text
## wraps, and past its line limit it is cut with an ellipsis so the pane never grows off screen.

const EFFECT_PREFIX := "Effect: "
## Prefix for a "not now" reason, so it reads as a refusal ("Can't use: No one needs it right now.").
const CANT_USE_PREFIX := "Can't use: "
## Reasons that already say what to do or that the bag never uses the item: shown as they are.
const INFO_REASONS := ["Give it from the Summary.", "Used in battle.", "Can't be used.", "Can't be used here.",
	"Unknown item.", "You don't have any."]
const EMPTY := "Pick an item."
## The page's inner size (404x344 minus 10px padding each side). The pane always takes
## all of it, so the page doesn't jump in size as the cursor moves between items.
const WIDTH := 384
const HEIGHT := 324
const ICON_SIZE := 48
## Line limits that keep the pane inside 344px however long the text (fallback: ellipsis).
const DESCRIPTION_LINES := 6
const EFFECT_LINES := 4
const USE_LINES := 2

var _header: HBoxContainer
var _icon: ItemIconSlot
var _name: Label
var _category: Label
var _owned: Label
var _price: Label
var _description: Label
var _effect: Label
var _use: Label
var _message: Label


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	add_theme_constant_override("separation", 4)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	add_child(_header)
	_icon = ItemIconSlot.new()
	_icon.configure("", ICON_SIZE)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_header.add_child(_icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(names)
	_name = _line(names, UIKit.HEADING_SIZE, UIKit.ACCENT)
	_category = _line(names, 11, UIKit.MUTED)
	_owned = _line(names, 11, UIKit.MUTED)
	_price = _line(self, UIKit.BODY_SIZE, UIKit.MUTED)
	_description = _wrapped(DESCRIPTION_LINES, UIKit.TEXT)
	_effect = _wrapped(EFFECT_LINES, UIKit.TEXT)
	_use = _wrapped(USE_LINES, UIKit.ACCENT)
	_message = _wrapped(DESCRIPTION_LINES, UIKit.TEXT)
	show_empty()


## Shows `item_id` as held in `save`'s bag (an unknown id still shows its count).
func show_item(db: Database, save: SaveGame, item_id: String) -> void:
	var it := db.item(item_id)
	_set_mode(true)
	_owned.text = "Owned: %d" % int(save.inventory.get(item_id, 0))
	if it == null:
		_icon.configure("unknown", ICON_SIZE)
		_name.text = item_id
		_category.text = "Unknown"
		_price.visible = false
		_effect.visible = false
		_use.visible = false
		_description.text = FieldItems.usability(db, save, item_id).reason
		return
	_icon.configure(it.category, ICON_SIZE)
	_name.text = it.name
	_category.text = it.category.capitalize()
	_price.text = "Price: %d" % it.price if it.price > 0 else "Price: —"
	_description.text = it.description
	_description.visible = it.description != ""
	_effect.text = EFFECT_PREFIX + _effect_text(db, it)
	var usability := FieldItems.usability(db, save, item_id)
	_use.text = use_line(usability)
	_use.add_theme_color_override("font_color", UIKit.ACCENT if usability.ok else UIKit.MUTED)


## The pane's last line for a `FieldItems.usability` result: the reason itself when the item is
## usable or the reason is informational, else the reason after CANT_USE_PREFIX.
static func use_line(usability: Dictionary) -> String:
	var reason: String = usability.reason
	if usability.ok or reason in INFO_REASONS:
		return reason
	return CANT_USE_PREFIX + reason


## Shows a single line in place of an item ("Pick an item.", or "Your bag is empty.").
func show_empty(text: String = EMPTY) -> void:
	_set_mode(false)
	_icon.configure("", ICON_SIZE)
	_name.text = ""
	_message.text = text


func title_text() -> String:
	return _name.text if _header.visible else ""


## How many lines the description takes when laid out, and how many of them are shown.
func description_lines() -> int:
	return _description.get_line_count()


func description_visible_lines() -> int:
	return _description.get_visible_line_count()


## Every visible line below the name, top to bottom.
func body_text() -> String:
	var lines := PackedStringArray()
	for l: Label in [_category, _owned, _price, _description, _effect, _use, _message]:
		if _shown(l):
			lines.append(l.text)
	return "\n".join(lines)


func icon_category() -> String:
	return _icon.category if _header.visible else ""


## An item's effect in words: its own effects, or for a held item its passive's always-on
## effects, triggers and overworld effects ("—" when it has none).
static func _effect_text(db: Database, it: ItemDef) -> String:
	if it.held == null:
		return EffectText.effects(db, it.effects)
	var parts := PackedStringArray()
	if not it.held.effects.is_empty():
		parts.append(EffectText.effects(db, it.held.effects))
	if not it.held.triggers.is_empty():
		parts.append(EffectText.triggers(db, it.held.triggers))
	if not it.held.field.is_empty():
		parts.append(EffectText.effects(db, it.held.field))
	return EffectText.or_dash("; ".join(parts))


func _shown(l: Label) -> bool:
	var n: Node = l
	while n != self:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		n = n.get_parent()
	return true


func _set_mode(item: bool) -> void:
	_header.visible = item
	for l: Label in [_price, _description, _effect, _use]:
		l.visible = item
	_message.visible = not item


func _line(parent: Node, font_size: int, color: Color) -> Label:
	var l := UIKit.label(parent, "", font_size, color)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _wrapped(max_lines: int, color: Color) -> Label:
	var l := UIKit.label(self, "", UIKit.BODY_SIZE, color, true)
	l.custom_minimum_size = Vector2(WIDTH, 0)
	l.max_lines_visible = max_lines
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l
