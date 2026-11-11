class_name AchievementPreview
extends PanelContainer
## The Achievements list's left pane: the focused row's icon, name, description and whether it is
## unlocked (with the date) or how far along it is. A hidden locked achievement shows only "???".

const SIZE := Vector2(300, 272)
const ICON := 96
## Longest description shown (characters); longer ones end in an ellipsis so the pane stays on screen.
const DESCRIPTION_MAX := 180

var _name: Label
var _description: Label
var _status: Label
var _masked := false


func _init() -> void:
	show_empty()


func name_text() -> String:
	return _name.text if _name != null else ""


func description_text() -> String:
	return _description.text if _description != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


## True while a hidden, locked achievement is shown (nothing about it is revealed).
func is_masked() -> bool:
	return _masked


func show_empty() -> void:
	_reset()


func show_entry(db: Database, save: SaveGame, id: String) -> void:
	_reset()
	var def := db.achievement(id)
	if def == null:
		return
	var unlocked := Achievements.is_unlocked(save, id)
	_masked = def.hidden and not unlocked
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	var icon := AchievementIconSlot.new()
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.configure("unknown" if _masked else str(def.criterion.get("kind", "")), ICON, unlocked)
	col.add_child(icon)
	_name = UIKit.label(col, "???" if _masked else def.name, UIKit.HEADING_SIZE, UIKit.ACCENT, true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var description := "Hidden achievement." if _masked else def.description
	if description.length() > DESCRIPTION_MAX:
		description = description.substr(0, DESCRIPTION_MAX - 1).strip_edges() + "…"
	_description = UIKit.label(col, description, UIKit.BODY_SIZE, UIKit.TEXT, true)
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var status := ""
	if unlocked:
		status = "Unlocked %s" % Time.get_date_string_from_unix_time(int(save.achievements[id]))
	elif not _masked:
		var p := Achievements.progress(db, save, id)
		status = "Progress %d / %d" % [p.current, p.target] if not p.is_empty() else ""
	_status = UIKit.label(col, status, UIKit.BODY_SIZE, UIKit.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _reset() -> void:
	for child in get_children():
		remove_child(child)  # now, not at the end of the frame, so a rebuild never doubles up
		child.queue_free()
	_name = null
	_description = null
	_status = null
	_masked = false
	custom_minimum_size = SIZE
	clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = UIKit.PANEL
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
