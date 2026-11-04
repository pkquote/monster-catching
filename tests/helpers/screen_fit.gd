class_name ScreenFit
extends RefCounted
## Layout checks for ProgressScreen-based screens, on their real on-screen rects.

const VIEW := Rect2(0, 0, 640, 360)


## Problems with how `screen` sits on the 640x360 screen ([] = fine): the info
## panel and the menu area are on screen, and the menu area starts below the info
## panel. A menu taller than its area scrolls, which counts as fitting.
static func problems(screen: ProgressScreen) -> PackedStringArray:
	var out := PackedStringArray()
	var top := screen.info_panel().get_global_rect()
	var area := screen.menu_area().get_global_rect()
	if not VIEW.encloses(top.grow(-0.5)):
		out.append("info panel %s is off the screen" % top)
	if not VIEW.encloses(area.grow(-0.5)):
		out.append("menu area %s is off the screen" % area)
	if top.end.y > area.position.y + 0.5:
		out.append("info panel (ends %.0f) overlaps the menu area (starts %.0f)" % [top.end.y, area.position.y])
	return out


## True when the menu panel is taller than its area, so the player must scroll to
## reach some options (allowed, but everyday screens should not need it).
static func needs_scroll(screen: ProgressScreen) -> bool:
	return screen.menu_panel().size.y > screen.menu_area().size.y + 0.5


## Fails `suite` with the reasons when `screen` doesn't sit on the screen, or
## needs scrolling when `allow_scroll` is false.
static func check(suite: GdUnitTestSuite, screen: ProgressScreen, allow_scroll := false) -> void:
	var issues := problems(screen)
	if not allow_scroll and needs_scroll(screen):
		issues.append("menu (%.0f tall) needs scrolling in its %.0f px area" % [screen.menu_panel().size.y, screen.menu_area().size.y])
	suite.assert_array(Array(issues)).is_empty()
