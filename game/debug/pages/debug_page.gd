class_name DebugPage
extends RefCounted
## One page of the F1 debug menu (game/debug/debug_menu.gd). The menu draws the
## title and status line; build() adds the page's controls to `box`.
##
## `menu` is the DebugMenu autoload, for its shared helpers: show_page(), close(),
## option_row(), ask(), go(), tools_blocked(), refresh_world() and `rng`.

var menu: Node


func title() -> String:
	return ""


## How wide the page's content is (most pages are a narrow column of buttons).
func width() -> float:
	return 260.0


func build(_box: VBoxContainer) -> void:
	pass
