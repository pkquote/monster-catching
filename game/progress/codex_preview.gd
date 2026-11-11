class_name CodexPreview
extends PanelContainer
## The Codex list's left pane: the focused row's sprite, number and name, and whether it was seen or
## caught. An unseen species is a dark disc with "#NNN ???" and "Not seen yet": nothing else leaks.

const SIZE := Vector2(300, 272)
const SPRITE := 128

var _name: Label
var _status: Label
var _slot: CreatureSpriteSlot


func _init() -> void:
	show_empty()


## "#001 Name", or "#001 ???" while unseen. Empty when nothing is shown.
func name_text() -> String:
	return _name.text if _name != null else ""


## "Caught", "Seen, not caught yet" or "Not seen yet". Empty when nothing is shown.
func status_text() -> String:
	return _status.text if _status != null else ""


func is_silhouette() -> bool:
	return _slot != null and _slot.silhouette


func show_empty() -> void:
	_reset()


func show_entry(db: Database, save: SaveGame, species: String) -> void:
	_reset()
	var status := Codex.status(save, species)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	_slot = CreatureSpriteSlot.new()
	_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if status == "unseen":
		_slot.configure_unknown(SPRITE)
	else:
		_slot.configure(db, species, SPRITE)
	col.add_child(_slot)
	var number := Codex.number_text(db, species)
	_name = UIKit.label(col, "%s %s" % [number, "???" if status == "unseen" else db.creature(species).name],
		UIKit.HEADING_SIZE, UIKit.ACCENT, true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = UIKit.label(col, {"caught": "Caught", "seen": "Seen, not caught yet"}.get(status, "Not seen yet"),
		UIKit.BODY_SIZE, UIKit.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _reset() -> void:
	for child in get_children():
		remove_child(child)  # now, not at the end of the frame, so a rebuild never doubles up
		child.queue_free()
	_name = null
	_status = null
	_slot = null
	custom_minimum_size = SIZE
	clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = UIKit.PANEL
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
