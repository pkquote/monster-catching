class_name MinigameDef
extends RefCounted
## A minigame from data/minigames.json: its scene extends Minigame.

var id: String
var name: String
var scene: String


static func from_dict(d: Dictionary) -> MinigameDef:
	var m := MinigameDef.new()
	m.id = d.id
	m.name = d.name
	m.scene = d.scene
	return m
