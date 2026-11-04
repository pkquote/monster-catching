# M3 — Overworld and Story: Design

Date: 2026-11-03
Status: Approved and implemented (plan: [documentation/plans/2026-11-03-m3-overworld.md](../plans/2026-11-03-m3-overworld.md))
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md) (milestone M3)

## 1. Goal

Replace the placeholder world with a real overworld the player walks around: a town with
buildings to enter, a route with tall grass, NPCs to talk to, items to find, tamers who challenge
you, a heal spot and shop, a starter-choosing cutscene, and a hook for minigames.

The main success measure is **easy map building**: a new map is made in the Godot editor by
painting tiles and dragging in ready-made pieces, filling in a few Inspector fields, and running
`check.sh` to catch broken references, with no code.

### Decisions

| Topic | Decision |
|---|---|
| Map authoring | Godot editor: TileMapLayers + placeable piece scenes with Inspector settings, one `.tscn` per map |
| Movement | Smooth 8-way physics movement; pieces and triggers snap to the 32px grid |
| Behaviour | Each piece type is a scene with its own script; world rules (collected, beaten, shop, healing, defeat) live in headless `core/` code; Dialogue Manager handles words and branching |
| M3 scope | Maps, movement, doors and interiors, NPC conversations, grass encounters, items and hidden items, tamers with line of sight, heal spot + shop, pause menu, starter cutscene, minigame hook with one example |
| Minigames | Only the hook and one tiny example (Quick Draw). Real minigames get their own spec. |
| Art | A generated placeholder tileset; real art can replace the image later without touching maps |

### Out of scope for M3

Full party/storage/training menus (M4), real art and audio, a second town, minigames beyond the
example, day/night, following creatures, surf/cut-style field abilities, repels.

## 2. Maps

### 2.1 The overworld screen

- `game/overworld/overworld.tscn` replaces `game/world/placeholder_world.tscn`. It holds the player,
  the camera, the on-screen UI (location banner, conversation box, pause menu) and one map instance.
- `SceneRouter.WORLD` points at the overworld, so battles, Settings and Resume all return to it.
- Changing map (`Overworld.change_map(map_path, spawn_id)`): lock the player, fade out, free the old
  map, instance the new one, place the player at the spawn, autosave, fade in, unlock. The player
  node is kept, not rebuilt.
- On entering a map whose display name differs from the last one, a location banner slides in.

### 2.2 A map scene

Maps live in `game/maps/`, one `.tscn` each, made by duplicating `game/maps/_template.tscn`. The map
id is the file name without extension (`town_01`, `town_01_lab`, `route_01`).

```
TownMap (GameMap)
  Ground    (TileMapLayer)  floor, grass, paths, water
  Decor     (TileMapLayer)  fences, flowers, signs; may carry collision
  Entities  (Node2D, y_sort_enabled)  every piece, plus the player while on this map
  Above     (TileMapLayer)  roofs and treetops drawn over the player
```

`GameMap` Inspector fields:

| Field | Meaning |
|---|---|
| `display_name` | Location label (banner, save browser) |
| `default_encounter` | Encounter table id used by grass tiles on this map ("" = none) |
| `indoor` | No wild encounters; camera centres the map when it's smaller than the screen |

Collision comes from the tileset (walls, water, trees, counters have physics shapes). The map's
bounds are the used rectangle of `Ground`.

### 2.3 Tileset

`tools/generate_placeholder_tiles.gd` writes `game/maps/tiles/placeholder.png` (32px tiles) and
`game/maps/tiles/placeholder_tileset.tres`, with:

- tiles: grass, tall grass, path, sand, water, wall, roof, door frame, floor, carpet, counter,
  table, tree, fence, flowers, sign;
- a physics layer with collision on solid tiles;
- a custom data layer `encounter: bool`, true on tall grass.

Real art later replaces the PNG with the same layout (or a new atlas mapped to the same terrain).
Maps reference tile ids, not pixels, so they keep working.

### 2.4 Pieces

Pieces live in `game/overworld/pieces/`, each a small scene with a `@tool` script that snaps its
position to the 32px grid in the editor and draws a coloured editor-only marker and label. Each
piece's save key is `<map_id>/<node path under Entities>`, e.g. `route_01/Potion1`.

| Piece | Inspector settings | Behaviour |
|---|---|---|
| `Spawn` | `id` | Arrival point for doors, new games and defeat respawn. Invisible. |
| `Door` | `target_map` (map id), `target_spawn` | Fires when the player's feet enter its tile. |
| `Npc` | `actor_id`, `display_name`, `dialogue` (file), `title`, `facing`, `wander_tiles` (0 = stand still) | Solid. Accept while facing it: turns to the player and runs `title`. Wanders within `wander_tiles` of its start when unlocked. |
| `Tamer` | `Npc` fields + `tamer_id`, `sight` (tiles), `before_title`, `after_title` | Spots the player along its facing (§5.2). Once beaten, talks with `after_title`. |
| `ItemPickup` | `item`, `count` | Visible item. Accept: gives it, shows "Found X!", disappears for good. |
| `HiddenItem` | `item`, `count` | Invisible. Accept while facing its tile: gives it once. |
| `EncounterArea` | `encounter`, `size_tiles` | Grass inside its rectangle uses this table instead of the map default. |
| `Trigger` | `dialogue`, `title`, `once`, `requires_flag`, `blocks_flag`, `size_tiles` | Runs `title` when the player's feet enter. `once` remembers it; `requires_flag` / `blocks_flag` gate it (e.g. block the route until `got_starter`). |
| `HealSpot` | `respawn` (spawn id on this map) | Accept: "Rest here?" → heals (§6.1). |
| `ShopCounter` | `stock` (item ids) | Accept: opens the shop (§6.2). |
| `MinigameSpot` | `minigame` (id), `dialogue`, `title` | Accept: runs `title`, which starts the minigame from the script (§8). |
| `Sign` | `text` | Accept: shows the text in the conversation box. |

Pieces never hold rules themselves. They call `Story` (§4.2) or `Overworld`, so a pickup and a
dialogue line that gives an item go through the same code.

## 3. Movement, camera, interaction

- **Player** (`game/overworld/player.tscn`, `CharacterBody2D`): 8-way movement from the move
  actions, normalised so diagonals aren't faster. Speed `balance.overworld.walk_speed` tiles/s
  (start: 4), `run_speed` (start: 7) while the new **Run** action is held. Slides along walls.
- **Run** joins `GameSettings.ACTIONS` with a default binding (Shift / gamepad X, the left face button), so it
  appears in the Controls tab and can be rebound.
- **Facing** is one of four directions: the most recently pressed direction that's still held.
- **Feet tile** = the tile under the player's feet point. Entering a new feet tile is what fires
  doors, triggers, encounter rolls and walking energy.
- **Interact** (Accept): finds the piece whose tile is the one in front of the feet tile along the
  facing. NPCs are solid, but found by tile, so no pixel-exact lining up.
- **Camera**: follows the player, clamped to map bounds, centred on maps smaller than the view,
  pixel-snapped. The view is 640×360 (20×11.25 tiles).
- **Locking**: `Overworld.lock(reason)` / `unlock(reason)` with a reason set. While any lock is held,
  the player ignores movement input and wandering NPCs pause. Conversations, cutscenes, menus,
  map changes and battle transitions take locks.

## 4. Story state and saving

### 4.1 `core/story/story_state.gd` (`StoryState`)

Plain data plus rules, no nodes:

- `flags: Dictionary` (String → bool), `counters: Dictionary` (String → int),
- `done: Dictionary` (piece save key → true) for collected items, beaten tamers, used one-time triggers,
- `last_heal: Dictionary` `{ map, spawn }` (empty = the new-game spawn),
- `to_dict()` / `from_dict()`.

### 4.2 `Story` autoload (`game/autoload/story.gd`)

The single API for pieces and `.dialogue` scripts, acting on `GameState.current`:

| Call | Does |
|---|---|
| `flag(id)`, `set_flag(id, on := true)` | Story flags |
| `count(id)`, `add_count(id, n := 1)` | Counters |
| `is_done(key)`, `mark_done(key)` | One-time pieces |
| `give_item(id, n := 1)`, `take_item(id, n := 1) -> bool`, `has_item(id, n := 1)` | Bag |
| `money()`, `give_money(n)`, `take_money(n) -> bool` | Money |
| `give_creature(species, level, starter := false)` | Adds to party (or storage); `starter` applies starter Bond |
| `party_size()` | For script branching |
| `heal_party()` | Full heal + "rested" Bond change |
| `start_battle(tamer_id, defeat_rules := true) -> bool` (awaitable) | Field-count prompt, battle, return; result also in `last_battle_won()`. With `defeat_rules` false a loss just returns `false` (party healed, no money lost, no respawn), for story battles |
| `start_minigame(id, params := {}) -> Dictionary` (awaitable) | §8; result also in `last_minigame()` |

### 4.3 Save format version 2

`SaveGame.SCHEMA` becomes 2, adding:

- `story`: `StoryState.to_dict()`, replacing the old top-level `flags`;
- `position`: `{ map, x, y, facing }` (pixels, exact);
- `location` is now set from the map's `display_name`.

Migration 1 → 2 (in `SaveStore`'s existing migration chain): `flags` move into `story.flags`;
`position` is the new-game start (`town_01_home`, spawn `start`). Old test saves keep working.

**Autosave**: on every map change, after every battle (when back on the map), and from the pause
menu. **Manual saves**: pause menu. **Resume** restores the exact position and facing.

## 5. Encounters and tamers

### 5.1 Wild encounters

- On entering a new feet tile whose `Ground` (or `Decor`) cell has `encounter = true`, on a map that
  isn't `indoor`: roll `balance.overworld.encounter_rate` (start: 0.10).
- Table: the `EncounterArea` containing the tile, else the map's `default_encounter`. No table, no roll.
- After any battle, the next `balance.overworld.encounter_grace_tiles` (start: 4) grass tiles don't roll.
- A hit: lock, pack rolled (`BattleLauncher.roll_wild_pack`), field-count prompt, battle, return to
  the same spot.
- The field-count prompt moves from `DebugMenu` into `game/ui/field_count_prompt.gd`, shared by
  encounters, tamers, `Story.start_battle` and the debug menu.
- The roll logic lives in `core/world/encounter_roller.gd` (`EncounterRoller`: rate, grace counter,
  table choice, seeded RNG) so it's tested headless.

### 5.2 Tamers who spot you

- Sight line: from the tamer's tile, `sight` tiles along its facing, stopping at the first solid tile.
  Computed by `core/world/grid.gd` (`Grid.sight_tiles(from, facing, length, is_solid: Callable)`).
- Checked whenever the player enters a new feet tile (and when a tamer turns), for unbeaten tamers only.
- Spotted: lock, "!" emote over the tamer, tamer walks to the tile next to the player, both face each
  other, `before_title` runs. The script calls `Story.start_battle(tamer_id)` and branches on the result.
- Beaten (`mark_done` on a win): the tamer no longer spots; talking runs `after_title`. A loss leaves
  it unbeaten for a rematch.

### 5.3 Walking energy

Every `balance.overworld.walk_energy_tiles` (start: 8) new feet tiles, each party creature with HP > 0
regains 1 energy (capped). HP doesn't regenerate. Counted in `core/world/walk_tracker.gd`.

### 5.4 Defeat (replaces the M2 placeholder)

On a lost battle (wild or tamer): fade out, the party is fully healed, the player loses
`floor(money × balance.overworld.defeat_money_fraction)` (start: 0.10), and wakes at `last_heal` (or
the new-game spawn) facing down, with a short "You hurried back to safety..." line. Rules in
`core/world/defeat.gd`; `BattleLauncher.apply_results` no longer heals on a loss.

## 6. Heal spot, shop, pause menu

### 6.1 HealSpot

"Rest here?" → Yes: `Story.heal_party()` (full HP, energy, status cleared, "rested" Bond change per
creature), sets `last_heal` to this map and the spot's `respawn` spawn (the map checker requires it to
exist), "Your team is rested."

### 6.2 Shop

- `ShopCounter.stock` lists item ids; prices come from each item's `price`.
- Shop screen (overlay, `game/overworld/ui/shop_menu.gd`): Buy and Sell tabs, item list with price
  and owned count, amount picker (1–99, limited by money or count), money shown.
- Selling pays `floor(price × balance.overworld.sell_fraction)` (start: 0.5). Items with `price` 0
  can't be sold.
- Rules in `core/world/shop.gd` (`Shop.buy(save, db, item, n)`, `Shop.sell(...)`, returning
  `{ ok, error }`), tested headless.

### 6.3 Pause menu

Opens with the Menu action when the player isn't locked. Pauses the map. Entries:

- **Party**: each creature's name, level, types, HP, energy, Bond, status and moves (read-only).
- **Bag**: items with counts and descriptions. Healing items (`category: "heal"`) can be used on a
  party creature. Uses `core/progress/field_items.gd` (`FieldItems.use(db, item, creature) -> Dictionary`),
  which supports the `heal` and `restore_energy` ops outside battle.
- **Save** (manual save, "Saved."), **Settings** (returns to the overworld), **Quit to title**
  (autosave first), **Close**.

The F1 debug menu is unchanged and works over the overworld.

## 7. Conversations, cutscenes, starter, first maps

### 7.1 Conversation box

`game/dialogue/dialogue_box.tscn`, used for every Dialogue Manager conversation:

- bottom panel (UIKit style) with the speaker name above it;
- typewriter text at the Text speed setting (`instant` shows the full line); Accept completes the
  line, then advances;
- responses shown with a `CommandMenu`;
- `Overworld.say(dialogue, title)` (awaitable) opens it, takes a lock, and releases it at the end.

### 7.2 `Cutscene` autoload

Awaitable commands for `.dialogue` scripts. Actors are `"player"` or an `actor_id` on the current map.

| Command | Does |
|---|---|
| `lock_player()`, `unlock_player()` | Cutscene lock |
| `move(actor, spawn_or_tile)` | Walks the actor along a straight-line-then-turn path to a spawn id or `"x,y"` tile |
| `face(actor, dir)` | `"up"`, `"down"`, `"left"`, `"right"`, or another actor's id |
| `emote(actor, kind)` | `"!"`, `"?"`, `"..."` bubble |
| `pan_camera(spawn_or_tile)`, `camera_back()` | Camera moves |
| `fade_out()`, `fade_in()`, `wait(seconds)` | Timing |
| `change_map(map, spawn)` | Map change from a script |

### 7.3 New game and the starter

1. New Game → overworld at `town_01_home`, spawn `start`.
2. A `Trigger` on the house's door mat (`blocks_flag: got_starter`) plays the professor cutscene: the
   professor enters, talks, and leads the player to `town_01_lab`.
3. In the lab, the script offers **Tidepup, Emberkit or Sprigling**. The pick gets
   `Story.give_creature(species, 5, true)` and 5 Lure Cages; `got_starter` is set.
4. The rival picks another and challenges you: new tamer `rival_lab` (1v1, one level-5 creature,
   no items). The script calls `Story.start_battle("rival_lab", false)`. Win or lose, the story
   continues in the lab (a loss heals the party and costs nothing; see §4.2).
5. A `Trigger` at the town's north exit (`blocks_flag: got_starter`) turns the player back until then.

The debug test party (F1) still works for testing, independent of the story.

### 7.4 First maps

| Map | Content |
|---|---|
| `town_01` (~30×20, outdoor) | Home, lab and heal centre with doors; path north to the route; 2 wandering NPCs; a sign |
| `town_01_home` | Player's room, `start` spawn, mum NPC |
| `town_01_lab` | Professor, rival, starter table |
| `town_01_center` | `HealSpot`, `ShopCounter` (lure_cage, tide_net, snare_vine, salve, tonic), clerk NPC |
| `route_01` (~20×40, outdoor) | Grass patches with `default_encounter: route_01_grass`; one `EncounterArea` with a new rarer table `route_01_deep_grass`; Scout Ana and one new tamer with sight lines; 2 `ItemPickup`s and 1 `HiddenItem`; the rival rematch `Trigger` (`rival_01`, 2v2) near the end; a `MinigameSpot` NPC; a "Road closed" sign at the far end |

The existing `dialogue/route_01/rival_intro.dialogue` is reworked into the route rematch.

## 8. Minigame hook

- `data/minigames.json` lists minigames: `{ id, name, scene }` (validated like other data; the scene
  path must exist).
- A minigame scene's root extends `Minigame` (`game/minigames/minigame.gd`): it receives `params`
  in `begin(params)` and emits `finished(result: Dictionary)` with at least `won: bool` and
  `score: int`.
- `Story.start_minigame(id, params)` pauses the map, opens the scene as an overlay, awaits
  `finished`, closes it and returns the result (also kept for `Story.last_minigame()`). Scripts give
  rewards, e.g. `if Story.last_minigame().won` → `Story.give_item("tonic")`.
- Any non-trivial minigame rules go in `core/minigames/` so they're tested headless.
- **Example: Quick Draw** (`game/minigames/quick_draw/`): five rounds; after a random delay a "!"
  appears and the player presses Accept within `params.window` seconds (default 0.45). Pressing
  early loses the round. Three or more wins = `won`. Round logic in `core/minigames/quick_draw.gd`.

## 9. Code structure

```
core/story/story_state.gd
core/world/grid.gd                encounter_roller.gd   walk_tracker.gd   shop.gd   defeat.gd
core/progress/field_items.gd
core/minigames/quick_draw.gd
game/autoload/story.gd            cutscene.gd
game/overworld/overworld.gd/.tscn player.gd/.tscn  game_map.gd
game/overworld/pieces/*.gd/.tscn  (spawn, door, npc, tamer, item_pickup, hidden_item,
                                   encounter_area, trigger, heal_spot, shop_counter,
                                   minigame_spot, sign, plus piece.gd base)
game/overworld/ui/pause_menu.gd   shop_menu.gd   location_banner.gd
game/ui/field_count_prompt.gd
game/dialogue/dialogue_box.gd/.tscn
game/minigames/minigame.gd        quick_draw/quick_draw.gd/.tscn
game/maps/_template.tscn          town_01*.tscn   route_01.tscn   tiles/
data/minigames.json               data/tamers (rival_lab, one route tamer)  data/encounters (route_01_deep_grass)
dialogue/town_01/*.dialogue       dialogue/route_01/*.dialogue
tools/generate_placeholder_tiles.gd   tools/check_maps.gd
documentation/map-building.md
```

`game/world/placeholder_world.*` is removed. New balance block `balance.overworld`:
`walk_speed`, `run_speed`, `encounter_rate`, `encounter_grace_tiles`, `walk_energy_tiles`,
`defeat_money_fraction`, `sell_fraction` (validated in `DataSchemas`).

## 10. Testing

- **Headless (`core/`)**: StoryState round-trip; save migration 1 → 2; `Grid.sight_tiles` (length,
  walls, all four facings); `EncounterRoller` (rate over many seeded rolls, grace tiles, area
  override, indoor/no table); `WalkTracker`; `Shop` buy/sell (not enough money, not enough items,
  unsellable); `FieldItems` (heal, energy, fainted creature, non-heal item); `Defeat` (money loss,
  heal, respawn target); Quick Draw rounds.
- **Map checker** (`tools/check_maps.gd`, run by `check.sh`): every map in `game/maps/` loads; piece ids
  exist (items, tamers, encounters, species, minigames); door targets and spawns exist; dialogue
  files and titles exist; each `HealSpot.respawn` spawn exists; no duplicate save keys; pieces sit on the grid; `town_01_home` has `start`;
  warns when a door has no door back.
- **Dialogue checker**: also verifies `Story.*` / `Cutscene.*` calls name real functions, and
  `start_battle` / `give_item` / `start_minigame` ids exist.
- **Scene tests (gdUnit4)**: each map instances; simulated input moves the player and collides with
  walls; a door changes map and places the player at the spawn; an `ItemPickup` is collected once and
  stays gone after leaving and returning; save → resume restores map, position and facing; a
  conversation runs to the end; the pause menu opens and closes.
- **Run skill**: new `--mode=overworld` tour: new game → starter cutscene → town → heal centre (heal,
  buy a Salve) → route grass encounter → a tamer spotting the player → save and resume, with
  screenshots.

## 11. Build order

Each stage ends playable and tested:

1. Tileset generator, `GameMap`, template, overworld screen, player movement and camera, `Door` and
   `Spawn`, two test maps.
2. StoryState, `Story` autoload, save v2 + migration, exact position save/resume, autosave on map change.
3. Piece base, `Npc`, `Sign`, `ItemPickup`, `HiddenItem`, `Trigger`, conversation box, map checker.
4. Encounters (roller, areas, grace, walking energy), shared field-count prompt, tamers with sight
   lines, defeat rules.
5. `Cutscene` autoload, starter sequence, `rival_lab`.
6. HealSpot, shop, pause menu with Party and Bag.
7. Minigame hook and Quick Draw.
8. Final maps and content, `map-building.md`, overworld driver tour, docs.
