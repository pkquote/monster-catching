# Building maps

Maps are ordinary Godot scenes in `game/maps/`. You paint tiles and drag in ready-made **pieces**
(doors, NPCs, items, grass areas...), fill in a few Inspector fields, then run `bash scripts/check.sh`,
which catches broken doors, typos in ids and missing dialogue titles. No code is needed.

Design background: [M3 overworld design](specs/2026-11-03-m3-overworld-design.md).

## 1. Make the map

1. In the FileSystem dock, duplicate `game/maps/_template.tscn` and rename it. **The file name is the
   map id** (`town_02.tscn` → `town_02`), so use lowercase and underscores.
2. Select the root node (a `GameMap`) and fill in:

   | Field | Meaning |
   |---|---|
   | `display_name` | The place name (location banner, save browser). Interiors usually reuse the town's name. |
   | `default_encounter` | Encounter table for tall grass on this map (an id from `data/encounters/`), or empty. |
   | `indoor` | No wild encounters, and small rooms are centred on screen. |

## 2. Paint

The template has four layers; select one and paint with the placeholder tileset
(`game/maps/tiles/placeholder_tileset.tres`):

| Layer | Use it for |
|---|---|
| `Ground` | Floors, grass, paths, water. The painted area of this layer is the map's size; nobody can walk outside it. |
| `Decor` | Fences, trees, flowers, signs drawn on top of the ground. |
| `Entities` | Not a tile layer: the pieces go here (see below). |
| `Above` | Drawn over the player: roof edges, treetops you walk behind. |

The tiles already know two things:

- **Solid tiles** (walls, water, roofs, counters, tables, trees, fences, signs) block movement.
- **Tall grass** rolls for wild encounters each time the player's feet enter a new grass tile.

To replace the placeholder art later, draw a new `placeholder.png` with the same 16-tile layout.
Every map keeps working. To regenerate the placeholder:
`godot --headless --path . --script res://tools/generate_placeholder_tiles.gd`, then `--import`,
then run it once more.

## 3. Add pieces

Drag a piece scene from `game/overworld/pieces/` onto the map's **Entities** node. Pieces snap to the
32px grid and show a coloured box with a label in the editor (invisible in the game). Give each
piece a clear node name: the name is part of how the save remembers it (`route_01/Potion1`), so
don't rename collected items or beaten tamers after release.

| Piece | Fields | What it does |
|---|---|---|
| `Spawn` | `id` | Where the player appears: doors arrive here; new games use `start` on `town_01_home`; heal spots use one for waking up after a loss. |
| `Door` | `target_map`, `target_spawn` | Walk into it to go to that spawn on that map. The tile you arrive on never fires straight away. |
| `Npc` | `actor_id`, `display_name`, `dialogue`, `title`, `start_facing`, `wander_tiles`, `hide_when_flag` | Solid. Accept while facing them: they turn and run `title`. They wander up to `wander_tiles` from where they start. They vanish once `hide_when_flag` is set. |
| `Tamer` | everything on `Npc` + `tamer_id`, `sight`, `before_title`, `after_title` | Sees `sight` tiles along its facing (walls block it). Spots the player, shows "!", walks up and runs `before_title`. That script must call `Story.start_battle("<tamer_id>")`. A win beats them for good; talking afterwards runs `after_title`. |
| `ItemPickup` | `item`, `count` | A visible item. Accept: into the bag, once per playthrough. |
| `HiddenItem` | `item`, `count` | Invisible. Accept while facing its tile finds it, once. |
| `EncounterArea` | `encounter`, `size` | Tall grass inside this rectangle uses this table instead of the map's default. |
| `Trigger` | `dialogue`, `title`, `once`, `requires_flag`, `blocks_flag`, `size` | Runs `title` when the player's feet enter. Use flags to gate it ("can't leave without a creature"). |
| `HealSpot` | `respawn` | Place it on a counter. "Rest your team?" heals everyone, and you wake at `respawn` after losing. |
| `ShopCounter` | `stock` | Place it on a counter. Opens the shop with these item ids; prices come from the item data. |
| `MinigameSpot` | `minigame`, `dialogue`, `title` | Accept runs `title`; the script starts the game with `Story.start_minigame("<id>")`. |
| `Sign` | `text` | Accept shows the text. |

Interact pieces (NPCs, items, counters) work from the tile in front of the player, so put a counter
piece on the counter tile and the person behind it.

## 4. Connect doors

Doors go both ways: a door on map A to spawn `from_a` on map B, and a door on B back to a spawn on A.
Put each arrival spawn **next to** the door, on the side the player walks out of, so holding the
direction carries them away from it.

## 5. Write the words

Conversations live in `dialogue/<area>/*.dialogue` (Dialogue Manager). A title starts with `~`:

```
~ mum
if Story.flag("got_starter")
	Mum: Your partner looks happy.
else
	Mum: Off you go! The professor wanted to see you.
=> END
```

Scripts can call `Story` (flags, items, money, creatures, battles, minigames, healing) and `Cutscene`
(`lock_player`, `move`, `face`, `emote`, `pan_camera`, `fade_out`, `change_map`...). Jumps (`=> title`)
must stay inside one file. A script that calls `Cutscene.lock_player()` should end with
`Cutscene.unlock_player()`; if it forgets, the player gets control back when the conversation ends
(with a warning in the output). `Cutscene.change_map` fades by itself, so don't wrap it in
`fade_out`/`fade_in`. `bash scripts/check.sh` checks that every called function exists and every
item, tamer and creature id is real.

## 6. Check

```
bash scripts/check.sh
```

The `== Maps` step lists every problem with the piece's save key, for example:

```
route_02/Door1: door to missing map 'route_3'
route_02/Potion: unknown item 'potoin'
town_02/Mayor: no title 'greet' in res://dialogue/town_02/npcs.dialogue
warning: town_02/Door1: no door on 'route_02' leads back to 'town_02'
```

Errors fail the check; warnings don't. Then press F5, start a game, and use F1 → test tools as needed.

## Roughing out maps from text (optional)

`tools/build_maps.gd` builds the starter maps from ASCII layouts (legend in `tools/map_builder.gd`):
`godot --headless --path . res://tools/build_maps.tscn`. It only writes maps that don't exist yet.
**`-- --force` rebuilds them all and throws away edits made in the editor**, so once you start
editing a map by hand, remove its entry from `build_maps.gd`.
