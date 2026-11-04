class_name TypeColors
extends RefCounted
## Placeholder colours for types and field states until real art exists.

const TYPES := {
	"neutral": Color("b8b2a7"), "fire": Color("e8673c"), "water": Color("3f8fe0"),
	"grass": Color("5bb85a"), "electric": Color("f2cf3d"), "ice": Color("8fd8e8"),
	"earth": Color("a9794a"), "magic": Color("b45be0"), "mental": Color("e86fb3"),
	"iron": Color("8a95a3"), "virtual": Color("3fd1b5"), "ghost": Color("6d5fb8"),
	"dark": Color("4a3f57"), "light": Color("f6e7a6"),
}

const STATES := {
	"soaked": Color("3f8fe0"), "scorched": Color("e8673c"), "overgrown": Color("5bb85a"),
	"charged": Color("f2cf3d"), "frosted": Color("bfeaf2"), "enchanted": Color("b45be0"),
	"hazed": Color("e86fb3"), "magnetized": Color("8a95a3"), "glitched": Color("3fd1b5"),
	"haunted": Color("6d5fb8"), "shrouded": Color("2e2738"), "radiant": Color("f6e7a6"),
}


static func type_color(type_id: String) -> Color:
	return TYPES.get(type_id, Color("9aa0ae"))


static func state_color(state_id: String) -> Color:
	return STATES.get(state_id, Color("9aa0ae"))
