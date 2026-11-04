extends Node
## Roughs out the starter maps from ASCII layouts (see MapBuilder for the legend)
## and writes the blank map template. Existing maps are left alone, so edits made
## in the Godot editor are safe.
##
##   godot --headless --path . res://tools/build_maps.tscn                    # new maps only
##   godot --headless --path . res://tools/build_maps.tscn -- --only=a,b      # rebuild these maps
##   godot --headless --path . res://tools/build_maps.tscn -- --force-all     # rebuild every map
##
## Rebuilding throws away edits made in the editor, so it always has to be asked for
## by name (--only) or spelled out (--force-all). A plain --force is refused. Once you
## edit a map by hand, remove its entry from maps() below so nothing can rebuild it.
##
## It runs as a scene (not --script) so the game's autoloads exist: piece scripts
## use Story, and a script that fails to compile would drop the piece's settings.

const TEMPLATE := "res://game/maps/_template.tscn"
const TEST_TALK := "res://tests/fixtures/test_talk.dialogue"
const STORY := "res://dialogue/town_01/story.dialogue"
const NPCS := "res://dialogue/town_01/npcs.dialogue"
const ROUTE_TAMERS := "res://dialogue/route_01/tamers.dialogue"
const ROUTE_MINIGAME := "res://dialogue/route_01/minigame.dialogue"
const ROUTE_RIVAL := "res://dialogue/route_01/rival_intro.dialogue"
const ROUTE_NPCS := "res://dialogue/route_01/npcs.dialogue"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--force" in args:
		printerr("build_maps: --force is no longer accepted: it would throw away editor edits on every map.
"
			+ "  Rebuild specific maps with -- --only=id,id, or all of them with -- --force-all.")
		get_tree().quit(1)
		return
	var force := "--force-all" in args
	var only := PackedStringArray()
	for a in args:
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GameMap.MAPS_DIR))
	if force or not ResourceLoader.exists(TEMPLATE):
		var t := MapBuilder.make_empty("New map")
		t.name = "NewMap"
		var scene := PackedScene.new()
		scene.pack(t)
		ResourceSaver.save(scene, TEMPLATE)
		t.free()
		print("Wrote ", TEMPLATE)
	for def in maps():
		var path := MapBuilder.build(def, force or def.id in only)
		print(("Wrote " + path) if path != "" else ("Kept " + GameMap.path_of(def.id)))
	get_tree().quit(0)


static func maps() -> Array:
	return [
		# --- Fernmoor Town -----------------------------------------------------------
		{
			"id": "town_01", "display_name": "Fernmoor Town",
			"rows": [
				"tttttttttttttttptttttttttttttt",
				"tggggggggggggggpgggggggggggggt",
				"tggggggggggggggpgggggggggggggt",
				"tggRRRRRgggggggpggggRRRRRRRggt",
				"tggRRRRRgFFFgggpggggRRRRRRRggt",
				"tgg##D##gFgggggpgggg###D###ggt",
				"tggggpgggggggggpgggggggpgggggt",
				"tggppppppppppppppppppppppppggt",
				"tgggggggggggggSpgggggggggggggt",
				"tggggggggggggggpggggggggggFFgt",
				"tgggggggtggFFggpgggggggggtgggt",
				"tgggggggtggggggpgggggggggggggt",
				"tgggFFgggggggggpgggRRRRRRRgggt",
				"tggggggggtgggggpgggRRRRRRRgggt",
				"tggtgggggggggggpggg###D###gggt",
				"tgggtggggggggggpggggggpggggggt",
				"tggppppppppppppppppppppppppggt",
				"tggggggggggggggggggggggggggggt",
				"tggggggggggggggggggggggggggggt",
				"tttttttttttttttttttttttttttttt",
			],
			"pieces": [
				{"type": "spawn", "name": "FromHome", "at": [5, 6], "props": {"id": "from_home"}},
				{"type": "spawn", "name": "FromLab", "at": [23, 6], "props": {"id": "from_lab"}},
				{"type": "spawn", "name": "FromCenter", "at": [22, 15], "props": {"id": "from_center"}},
				{"type": "spawn", "name": "FromRoute", "at": [15, 1], "props": {"id": "from_route"}},
				{"type": "door", "name": "HomeDoor", "at": [5, 5], "props": {"target_map": "town_01_home", "target_spawn": "from_town"}},
				{"type": "door", "name": "LabDoor", "at": [23, 5], "props": {"target_map": "town_01_lab", "target_spawn": "entry"}},
				{"type": "door", "name": "CenterDoor", "at": [22, 14], "props": {"target_map": "town_01_center", "target_spawn": "entry"}},
				{"type": "door", "name": "NorthExit", "at": [15, 0], "props": {"target_map": "route_01", "target_spawn": "from_town"}},
				# Leaving home the first time: the professor stops you.
				{"type": "trigger", "name": "Intro", "at": [4, 7], "props": {"dialogue": STORY, "title": "intro",
					"blocks_flag": "got_starter", "size": Vector2i(3, 1)}},
				# No tall grass without a creature.
				{"type": "trigger", "name": "TooEarly", "at": [15, 1], "props": {"dialogue": STORY, "title": "too_early",
					"blocks_flag": "got_starter"}},
				{"type": "npc", "name": "Prof", "at": [24, 6], "props": {"actor_id": "prof", "display_name": "Prof. Alder",
					"dialogue": STORY, "title": "prof_town", "hide_when_flag": "met_prof"}},
				{"type": "npc", "name": "Kid", "at": [10, 12], "props": {"actor_id": "kid", "display_name": "Kid",
					"dialogue": NPCS, "title": "kid", "wander_tiles": 2}},
				{"type": "npc", "name": "Elder", "at": [27, 12], "props": {"actor_id": "elder", "display_name": "Elder",
					"dialogue": NPCS, "title": "elder", "wander_tiles": 1, "start_facing": "left"}},
				{"type": "sign", "name": "TownSign", "at": [14, 8], "props": {"text": "Fernmoor Town. Every journey starts slow."}},
			],
		},
		{
			"id": "town_01_home", "display_name": "Fernmoor Town", "indoor": true,
			"rows": [
				"#########",
				"#cc...T.#",
				"#.......#",
				"#.......#",
				"#.......#",
				"#.......#",
				"####D####",
			],
			"pieces": [
				{"type": "spawn", "name": "Start", "at": [2, 2], "props": {"id": "start"}},
				{"type": "spawn", "name": "FromTown", "at": [4, 5], "props": {"id": "from_town"}},
				{"type": "door", "name": "Door", "at": [4, 6], "props": {"target_map": "town_01", "target_spawn": "from_home"}},
				{"type": "npc", "name": "Mum", "at": [6, 3], "props": {"actor_id": "mum", "display_name": "Mum",
					"dialogue": NPCS, "title": "mum", "start_facing": "left"}},
			],
		},
		{
			"id": "town_01_lab", "display_name": "Fernmoor Town", "indoor": true,
			"rows": [
				"###########",
				"#CC.....CC#",
				"#.........#",
				"#...TTT...#",
				"#.........#",
				"#.........#",
				"#.........#",
				"#.........#",
				"#####D#####",
			],
			"pieces": [
				{"type": "spawn", "name": "Entry", "at": [5, 7], "props": {"id": "entry"}},
				{"type": "door", "name": "Door", "at": [5, 8], "props": {"target_map": "town_01", "target_spawn": "from_lab"}},
				{"type": "npc", "name": "Prof", "at": [5, 2], "props": {"actor_id": "prof", "display_name": "Prof. Alder",
					"dialogue": STORY, "title": "prof"}},
				{"type": "npc", "name": "Rival", "at": [8, 5], "props": {"actor_id": "rival", "display_name": "Rival",
					"dialogue": STORY, "title": "rival_talk", "start_facing": "left", "hide_when_flag": "rival_lab_done"}},
			],
		},
		{
			"id": "town_01_center", "display_name": "Fernmoor Town", "indoor": true,
			"rows": [
				"###########",
				"#.........#",
				"#CCCCCCCCC#",
				"#.........#",
				"#..ccccc..#",
				"#..ccccc..#",
				"#.........#",
				"#####D#####",
			],
			"pieces": [
				{"type": "spawn", "name": "Entry", "at": [5, 6], "props": {"id": "entry"}},
				{"type": "spawn", "name": "Heal", "at": [3, 3], "props": {"id": "heal"}},
				{"type": "door", "name": "Door", "at": [5, 7], "props": {"target_map": "town_01", "target_spawn": "from_center"}},
				{"type": "heal_spot", "name": "HealCounter", "at": [3, 2], "props": {"respawn": "heal"}},
				{"type": "npc", "name": "Nurse", "at": [3, 1], "props": {"actor_id": "nurse", "display_name": "Nurse",
					"dialogue": NPCS, "title": "nurse"}},
				{"type": "shop_counter", "name": "ShopCounter", "at": [7, 2], "props": {"stock":
					PackedStringArray(["lure_cage", "tide_net", "snare_vine", "salve", "tonic", "reset_seed"])}},
				{"type": "storage_box", "name": "StorageBox", "at": [8, 2]},
				{"type": "npc", "name": "Clerk", "at": [7, 1], "props": {"actor_id": "clerk", "display_name": "Clerk",
					"dialogue": NPCS, "title": "clerk"}},
			],
		},
		# --- Route 1 ----------------------------------------------------------------
		{
			"id": "route_01", "display_name": "Route 1", "default_encounter": "route_01_grass",
			"rows": [
				"tttttttttttttttttttt",
				"tggggggggggggggggggt",
				"tfffffffffffffffffft",
				"tgggggggggpSgggggggt",
				"tgggggggggpggggggggt",
				"tgggggggggpggggggggt",
				"tgggggTgggpggwwwwwgt",
				"tgggggggggpggwwwwwgt",
				"tgggggggggpggwwwwwgt",
				"tgggtgggggpggwwwwwgt",
				"tgggggggggpggggggggt",
				"tgggggggggpggggggggt",
				"tgggggggggpggggggggt",
				"tgggggggggpggggggggt",
				"tgwwwwwwggpggggggggt",
				"tgwwwwwwggpggggggggt",
				"tgwwwwwwggpggggggggt",
				"tgwwwwwwggpggggggggt",
				"tgwwwwwwggpggggttggt",
				"tgggggggggpggggggggt",
				"tgggggggggpgFFgggggt",
				"tgggggggggpggggggggt",
				"tgggggggggpggggggggt",
				"tgggggggggpggggggggt",
				"tgggggggggpggwwwwwgt",
				"tggtggggggpggwwwwwgt",
				"tgggggggggpggwwwwwgt",
				"tggggggtggpggwwwwwgt",
				"tggggggtggpggwwwwwgt",
				"tgggggggggpggggggggt",
				"tgwwwwwgggpggggggggt",
				"tgwwwwwgggpggggggggt",
				"tgwwwwwgggpggggggggt",
				"tgwwwwwgggpgggggtggt",
				"tgwwwwwgggpggggggtgt",
				"tgggggggggpggggggggt",
				"tgggggFFggpggggggggt",
				"tgggggggggpggggggggt",
				"tgggggggggpggggggggt",
				"ttttttttttDttttttttt",
			],
			"pieces": [
				{"type": "spawn", "name": "FromTown", "at": [10, 38], "props": {"id": "from_town"}},
				{"type": "door", "name": "SouthExit", "at": [10, 39], "props": {"target_map": "town_01", "target_spawn": "from_route"}},
				{"type": "encounter_area", "name": "DeepGrass", "at": [13, 6], "props": {"encounter": "route_01_deep_grass",
					"size": Vector2i(5, 4)}},
				{"type": "unsafe_area", "name": "UnsafeZone", "at": [13, 6], "props": {"size": Vector2i(5, 4)}},
				{"type": "tamer", "name": "ScoutAna", "at": [4, 22], "props": {"actor_id": "ana", "display_name": "Scout Ana",
					"tamer_id": "scout_ana", "sight": 6, "start_facing": "right", "dialogue": ROUTE_TAMERS,
					"before_title": "ana_before", "after_title": "ana_after"}},
				{"type": "tamer", "name": "HikerTom", "at": [16, 12], "props": {"actor_id": "tom", "display_name": "Hiker Tom",
					"tamer_id": "hiker_tom", "sight": 6, "start_facing": "left", "dialogue": ROUTE_TAMERS,
					"before_title": "tom_before", "after_title": "tom_after"}},
				{"type": "item_pickup", "name": "Salves", "at": [3, 10], "props": {"item": "salve", "count": 2}},
				{"type": "item_pickup", "name": "TideNet", "at": [17, 31], "props": {"item": "tide_net"}},
				{"type": "hidden_item", "name": "HiddenTonic", "at": [18, 20], "props": {"item": "tonic"}},
				{"type": "npc", "name": "Sharpshooter", "at": [6, 5], "props": {"actor_id": "sharpshooter",
					"display_name": "Sharpshooter", "dialogue": ROUTE_MINIGAME, "title": "quick_draw"}},
				{"type": "minigame_spot", "name": "QuickDrawTable", "at": [6, 6], "props": {"minigame": "quick_draw",
					"dialogue": ROUTE_MINIGAME, "title": "quick_draw"}},
				{"type": "npc", "name": "Rival", "at": [10, 3], "props": {"actor_id": "rival", "display_name": "Rival",
					"dialogue": ROUTE_RIVAL, "title": "rival_waiting"}},
				# Walking up to the rival starts the rematch, until you win it.
				{"type": "trigger", "name": "RivalRematch", "at": [9, 5], "props": {"dialogue": ROUTE_RIVAL,
					"title": "rival_intro", "requires_flag": "got_starter", "blocks_flag": "rival_1_done", "size": Vector2i(3, 1)}},
				{"type": "sign", "name": "RoadClosed", "at": [11, 3], "props": {"text": "ROAD CLOSED. Rockslide ahead."}},
				{"type": "npc", "name": "Rambler", "at": [14, 35], "props": {"actor_id": "rambler", "display_name": "Rambler",
					"dialogue": ROUTE_NPCS, "title": "route_tip", "wander_tiles": 2}},
			],
		},
		# Tiny test maps used by the automated tests (and handy for trying pieces).
		{
			"id": "test_a", "display_name": "Test Room", "indoor": true,
			"rows": [
				"########",
				"#......#",
				"#......#",
				"#......#",
				"#......#",
				"####D###",
			],
			"pieces": [
				{"type": "spawn", "name": "Start", "at": [2, 2], "props": {"id": "start"}},
				{"type": "spawn", "name": "FromB", "at": [4, 4], "props": {"id": "from_b"}},
				{"type": "door", "name": "Door1", "at": [4, 5], "props": {"target_map": "test_b", "target_spawn": "from_a"}},
				{"type": "npc", "name": "Guide", "at": [6, 1], "props": {"actor_id": "guide", "display_name": "Guide",
					"dialogue": TEST_TALK, "title": "hello"}},
				{"type": "item_pickup", "name": "Salve1", "at": [1, 4], "props": {"item": "salve"}},
				{"type": "hidden_item", "name": "Hidden1", "at": [6, 4], "props": {"item": "tonic"}},
			],
		},
		{
			"id": "test_b", "display_name": "Test Field", "default_encounter": "route_01_grass",
			"rows": [
				"tttttttttttt",
				"tggggggggggt",
				"tgwwgggggggt",
				"tgwwgggggggt",
				"tggggggggggt",
				"tggggggggggt",
				"tgggggwwgggt",
				"ttttDttttttt",
			],
			"pieces": [
				# Arrives on the door tile itself: the door must not fire until the player leaves it.
				{"type": "spawn", "name": "FromA", "at": [4, 7], "props": {"id": "from_a"}},
				{"type": "spawn", "name": "Middle", "at": [6, 4], "props": {"id": "middle"}},
				{"type": "door", "name": "Door1", "at": [4, 7], "props": {"target_map": "test_a", "target_spawn": "from_b"}},
				{"type": "sign", "name": "Sign1", "at": [6, 2], "props": {"text": "Test field. Mind the grass."}},
				{"type": "npc", "name": "Walker", "at": [10, 6], "props": {"actor_id": "walker", "display_name": "Walker",
					"dialogue": TEST_TALK, "title": "hello", "wander_tiles": 2}},
				# Sees (6..9, 4); the "middle" spawn is in its line, but arriving never triggers it.
				{"type": "tamer", "name": "Watcher", "at": [10, 4], "props": {"actor_id": "watcher", "display_name": "Watcher",
					"tamer_id": "scout_ana", "sight": 4, "start_facing": "left", "dialogue": TEST_TALK,
					"before_title": "battle", "after_title": "bye"}},
				# Looks left along row 2; the sign at (6, 2) blocks its view past (7, 2).
				{"type": "tamer", "name": "Guard", "at": [10, 2], "props": {"actor_id": "guard", "display_name": "Guard",
					"tamer_id": "scout_ana", "sight": 6, "start_facing": "left", "dialogue": TEST_TALK,
					"before_title": "battle", "after_title": "bye"}},
				{"type": "encounter_area", "name": "DeepGrass", "at": [2, 2], "props": {"encounter": "route_01_deep_grass",
					"size": Vector2i(2, 2)}},
				{"type": "unsafe_area", "name": "UnsafeZone", "at": [2, 2], "props": {"size": Vector2i(2, 2)}},
				{"type": "trigger", "name": "Gate", "at": [8, 5], "props": {"dialogue": TEST_TALK, "title": "sets_flag",
					"once": true, "blocks_flag": "gate_off", "size": Vector2i(2, 1)}},
			],
		},
	]
