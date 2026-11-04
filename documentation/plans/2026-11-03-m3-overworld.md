# M3 Overworld and Story Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder world with an editor-built overworld: maps of painted tiles and
placeable pieces, 8-way movement, doors into buildings, NPCs and conversations, items, grass
encounters, tamers with sight lines, a heal spot, shop and pause menu, a starter cutscene, and a
minigame hook.

**Architecture:** Each map is a `.tscn` (`GameMap` root, TileMapLayers, a Y-sorted `Entities` node of
piece scenes). One `Overworld` scene holds the player and camera and swaps maps. World rules
(story state, encounters, shop, defeat, sight lines) are headless `RefCounted` classes in
`core/`, reached from pieces and `.dialogue` scripts through the `Story` and `Cutscene` autoloads.
A map checker in `check.sh` validates every piece reference.

**Tech Stack:** Godot 4.7.2, typed GDScript, gdUnit4 6.2.3, Dialogue Manager 4.2.0.

**Spec:** [documentation/specs/2026-11-03-m3-overworld-design.md](../specs/2026-11-03-m3-overworld-design.md)
(section numbers below, e.g. §5.2, refer to it).

## Global Constraints

- **Never `git commit`.** The user authors every commit. Each task ends by leaving its changes unstaged.
- `core/` never references `Node`, scenes or autoloads; it takes `Database`, `SaveGame` and a seeded
  `RandomNumberGenerator` explicitly.
- Tiles are 32×32 px; the viewport is 640×360; every piece's position is a multiple of 32 plus 16
  (tile centre) when saved in a map.
- Map id = map file name without `.tscn`; maps live in `res://game/maps/`. Piece save key =
  `"<map_id>/<node path relative to Entities>"`.
- Balance starts (`data/balance.json` → `overworld`): `walk_speed` 4.0, `run_speed` 7.0 (tiles/s),
  `encounter_rate` 0.10, `encounter_grace_tiles` 4, `walk_energy_tiles` 8,
  `defeat_money_fraction` 0.10, `sell_fraction` 0.5. The same block goes into
  `tests/helpers/fixture_db.gd`'s balance.
- New-game start: map `town_01_home`, spawn `start`. Starters: `tidepup`, `emberkit`, `sprigling`
  at level 5 with starter Bond, plus 5 `lure_cage`.
- Single-suite test command (Git Bash, from the repo root):
  `"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a <res://path/to/test.gd> -c --ignoreHeadlessMode`
  with `GODOT` as in `scripts/check.sh`. After adding any new `class_name`, run
  `"$GODOT" --headless --path . --import` once first.
- Full check: `bash scripts/check.sh` → ends with `All checks passed.`
- Real-window check: the run skill (`.claude/skills/run-godot-monster-catching-game/SKILL.md`). Look at every screenshot.
- Follow existing patterns: UI built with `UIKit` helpers; menus via `CommandMenu`; events and ids
  as constants where they exist (`BattleEvents`, `SceneRouter.*`).

## Review Focus

1. **Arriving on a door tile.** A spawn that sits on or next to a door, while the player holds a
   direction, must not bounce them straight back. Expect: the tile you arrive on never fires until
   you have left it. Pinned in Task 4.
2. **Menus during locks.** Pressing Menu or F1 during a conversation, cutscene or map fade must do
   nothing, and Accept must not start a second conversation. Pinned in Tasks 7 and 17.
3. **Resuming inside a trigger or a tamer's sight line.** Expect: nothing fires until the player
   moves to a new tile. Pinned in Tasks 6 and 13.
4. **A save whose map no longer exists** (renamed or deleted map). Expect: Resume falls back to the
   new-game start instead of crashing. Pinned in Task 6.
5. **No healthy creatures in grass** (for example after a debug change). Expect: no encounter roll and
   no battle with an empty team. Tamers can't challenge you either. Pinned in Tasks 11 and 13.

---

## Stage 1 — Maps, movement, doors

### Task 1: Placeholder tileset generator

**Files:**
- Create: `tools/generate_placeholder_tiles.gd`, outputs `game/maps/tiles/placeholder.png`, `game/maps/tiles/placeholder_tileset.tres`, `game/maps/tiles/tile_ids.gd`
- Test: `tests/world/test_tileset.gd`

**Interfaces:**
- Produces: `TileIds` (`class_name`, constants `SOURCE := 0` and one `Vector2i` atlas coord per tile:
  `GRASS, TALL_GRASS, PATH, SAND, WATER, WALL, ROOF, DOOR, FLOOR, CARPET, COUNTER, TABLE, TREE, FENCE, FLOWERS, SIGN`,
  plus `SOLID: Array[Vector2i]`). TileSet with physics layer 0 (full-tile square on every `SOLID` tile)
  and custom data layer `"encounter"` (bool, true only on `TALL_GRASS`).

- [ ] **Step 1: Write the failing test** `test_tileset_has_collision_and_encounter_data`: load the
  `.tres`; assert `get_custom_data_layer_by_name("encounter") >= 0`; for `TileIds.TALL_GRASS` the
  tile data's `encounter` is true and `GRASS` is false; every `TileIds.SOLID` tile has
  `get_collision_polygons_count(0) == 1`, and `GRASS` has 0; the atlas `texture_region_size == Vector2i(32, 32)`.
- [ ] **Step 2: Run it, expect FAIL** (resource missing).
- [ ] **Step 3: Implement the tool** (`extends SceneTree`): draw each tile as a flat colour with a
  1px darker border and a simple glyph (tall grass: blades; water: waves; door: dark rectangle) into
  an `Image` (16 columns × 1 row), `save_png`, build the `TileSet` + `TileSetAtlasSource` in code,
  `ResourceSaver.save`, and write `tile_ids.gd`. Run it:
  `"$GODOT" --headless --path . --script res://tools/generate_placeholder_tiles.gd`, then `--import`.
- [ ] **Step 4: Run the test, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 2: GameMap, pieces base, Spawn and Door, map template

**Files:**
- Create: `game/overworld/game_map.gd`, `game/overworld/pieces/piece.gd`, `game/overworld/pieces/spawn.gd/.tscn`, `game/overworld/pieces/door.gd/.tscn`, `game/maps/_template.tscn`, `game/maps/test_a.tscn`, `game/maps/test_b.tscn` (two tiny maps joined by doors, used by tests; kept as debug maps)
- Test: `tests/world/test_game_map.gd`

**Interfaces:**
- Produces:
  - `class_name GameMap extends Node2D`: `@export var display_name: String`, `@export var default_encounter: String`,
    `@export var indoor: bool`; `func map_id() -> String` (from `scene_file_path`); `func bounds() -> Rect2i`
    (used rect of `Ground`, in tiles); `func is_solid(tile: Vector2i) -> bool` (solid tile on any layer, or a solid piece);
    `func is_encounter_tile(tile: Vector2i) -> bool` (custom data on `Ground` or `Decor`);
    `func spawn(id: String) -> Spawn`; `func pieces() -> Array[Piece]`; `func piece_at(tile: Vector2i) -> Piece`;
    `static func tile_of(pos: Vector2) -> Vector2i` and `static func centre_of(tile: Vector2i) -> Vector2`.
  - `class_name Piece extends Node2D` (`@tool`): snaps `position` to the tile centre in the editor,
    draws an editor-only marker (`_draw` when `Engine.is_editor_hint()`) using `marker_color()` and
    `marker_label()`; `func tile() -> Vector2i`; `func save_key() -> String`; virtual
    `func on_interact(world: Overworld) -> void`, `func on_enter(world: Overworld) -> void`,
    `func blocks() -> bool` (default false).
  - `class_name Spawn extends Piece`: `@export var id: String`.
  - `class_name Door extends Piece`: `@export var target_map: String`, `@export var target_spawn: String`;
    `on_enter` calls `world.change_map(target_map, target_spawn)`.

- [ ] **Step 1: Write failing tests**: `test_tile_math` (`tile_of(Vector2(47, 70)) == Vector2i(1, 2)`,
  `centre_of(Vector2i(1, 2)) == Vector2(48, 80)`); `test_map_basics` (instance `test_a.tscn`:
  `map_id() == "test_a"`, `spawn("start")` not null, `is_solid` true on a painted wall tile and false on
  floor, `piece_at` the door's tile returns a `Door` with `target_map == "test_b"`, `save_key()` of a
  piece named `Door1` is `"test_a/Door1"`).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the scripts; build `_template.tscn` (layers `Ground`, `Decor`, `Entities`
  (`y_sort_enabled`), `Above` (z_index 10) all using the placeholder tileset); paint `test_a`/`test_b`
  (8×6 rooms, walls around, a door each way, `start` and `from_a`/`from_b` spawns).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 3: Player movement and camera

**Files:**
- Create: `game/overworld/player.gd/.tscn`
- Modify: `core/settings/game_settings.gd` (add `"run"` to `ACTIONS`, label "Run", default bindings `KEY_SHIFT` / `JOY_BUTTON_X`), `core/data/schemas.gd` + `core/data/defs/balance_def.gd` + `data/balance.json` + `tests/helpers/fixture_db.gd` (the `overworld` block from Global Constraints; `BalanceDef.overworld_cfg: Dictionary`)
- Test: `tests/world/test_player.gd`, `tests/settings/test_game_settings.gd` (extend)

**Interfaces:**
- Consumes: `GameMap.tile_of`.
- Produces: `class_name Player extends CharacterBody2D`: `var facing: Vector2i` (one of the four unit
  vectors), `var locked := false`, `signal tile_entered(tile: Vector2i)`, `func feet_tile() -> Vector2i`,
  `func front_tile() -> Vector2i`, `func place(pos: Vector2, facing_: Vector2i) -> void` (sets position and
  facing and resets the "current tile" without emitting `tile_entered`), `func step(dir: Vector2, run: bool, delta: float)`
  (movement core, called from `_physics_process` with the input vector; tests call it directly).
  The collision shape is a 20×12 rectangle at the feet; the sprite is a coloured placeholder.

- [ ] **Step 1: Write failing tests**: `test_diagonal_is_normalised` (step with `Vector2(1,1)` for 1 s
  at walk speed moves ≈ `4 * 32` px total length, ±1); `test_run_is_faster`; `test_facing_follows_last_direction`
  (press right then add up → facing up; release up → right); `test_walls_block` (in `test_a`,
  stepping into a wall for 2 s leaves the player on the floor side); `test_tile_entered_once_per_tile`
  (walk across 3 tiles → 3 signals, standing still → none); `test_place_does_not_emit`;
  `test_run_action_is_bindable` (`"run" in GameSettings.ACTIONS`, defaults present).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Facing rule: keep a small stack of held direction actions in press order;
  facing = last held. Speed from `DataRegistry.db.balance.overworld_cfg`. `move_and_slide()`.
- [ ] **Step 4: Run, expect PASS** (plus the existing settings tests).
- [ ] **Step 5: Leave unstaged.**

### Task 4: Overworld screen with map changes

**Files:**
- Create: `game/overworld/overworld.gd/.tscn`
- Modify: `game/autoload/scene_router.gd` (`WORLD := "res://game/overworld/overworld.tscn"`), `game/debug/debug_menu.gd` (`_refresh_world` no longer reloads the overworld; it calls `Overworld.refresh_hud()` when present)
- Delete: `game/world/placeholder_world.gd/.tscn` (and its references in tests/driver)
- Test: `tests/world/test_overworld.gd`

**Interfaces:**
- Consumes: `GameMap`, `Player`, `Door`, `Spawn`.
- Produces: `class_name Overworld extends Node2D` (one instance, at `SceneRouter.WORLD`):
  `var map: GameMap`, `var player: Player`;
  `func change_map(map_id: String, spawn_id: String) -> void` (awaitable; lock → fade → swap → place →
  emit `map_changed` → fade in → unlock); `signal map_changed(map: GameMap)`;
  `func lock(reason: String)`, `func unlock(reason: String)`, `func is_locked() -> bool`
  (player.locked mirrors it); `func load_map_at(map_id: String, pos: Vector2, facing: Vector2i)`
  (no fade, used on scene start); camera: `Camera2D` child of the player with limits from `map.bounds()`,
  centred when the map is smaller than the view, `position_smoothing` off, pixel snap on.
  On `player.tile_entered(tile)`: if `map.piece_at(tile)` exists, call its `on_enter(self)`.
  Temporary start: if no game position exists, load `test_a` / `start` (Task 6 replaces this).

- [ ] **Step 1: Write failing tests**: `test_door_changes_map` (start in `test_a`, `player.place` on the
  tile next to the door, step into it → after `map_changed`, `map.map_id() == "test_b"` and the player's
  feet tile is spawn `from_a`'s tile); `test_arrival_tile_never_fires` (Review Focus 1: in `test_b`
  put spawn `from_a` on a door tile; after arriving, hold the step toward the door for 0.1 s while
  still on the arrival tile → no second map change; leave and re-enter → it fires);
  `test_locked_player_does_not_move`; `test_camera_limits_match_bounds`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** "Arrival tile never fires": `Player.place` sets the current tile
  without emitting, so only a later change emits. The tween for fades uses a `CanvasLayer` `ColorRect`.
- [ ] **Step 4: Run, expect PASS.** Run `bash scripts/check.sh` (the old placeholder-world tests and
  `test_debug_menu` must still pass after the reference updates).
- [ ] **Step 5: Real window:** add `--mode=overworld` to the driver with a first step (new game → overworld
  → walk through the door → screenshot each map). Look at the screenshots.
- [ ] **Step 6: Leave unstaged.**

## Stage 2 — Story state and saving

### Task 5: StoryState and save format version 2

**Files:**
- Create: `core/story/story_state.gd`
- Modify: `core/save/save_game.gd` (`SCHEMA := 2`, replace `flags` with `story: StoryState`, add `position: Dictionary`), `core/save/save_store.gd` (`MIGRATIONS[1]`), `game/battle/battle_launcher.gd` + `game/debug/debug_menu.gd` (`TEST_FLAG` now via `save.story.flags`)
- Test: `tests/story/test_story_state.gd`, `tests/save/test_save_store.gd` (extend)

**Interfaces:**
- Produces: `class_name StoryState extends RefCounted`: `var flags: Dictionary`, `var counters: Dictionary`,
  `var done: Dictionary`, `var last_heal: Dictionary` (`{map, spawn}` or empty);
  `flag(id) -> bool`, `set_flag(id, on := true)`, `count(id) -> int`, `add_count(id, n := 1)`,
  `is_done(key) -> bool`, `mark_done(key)`, `to_dict() -> Dictionary`, `static from_dict(d) -> StoryState`.
  `SaveGame.position := {"map": "", "x": 0.0, "y": 0.0, "facing": "down"}`; `SaveGame.NEW_GAME_MAP := "town_01_home"`,
  `SaveGame.NEW_GAME_SPAWN := "start"`.

- [ ] **Step 1: Write failing tests**: `test_story_round_trip` (set flag, counter 3, done key, last_heal →
  `from_dict(to_dict())` equal); `test_missing_keys_default`; `test_v1_save_migrates` (write a schema-1
  JSON with `"flags": {"debug_test_party_granted": true}` → `read` gives `save.story.flag("debug_test_party_granted")`
  true, `position.map == ""`); `test_v2_round_trip_keeps_position`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Migration 1→2: `d.story = {"flags": d.get("flags", {})}`, erase `flags`,
  `d.position = {}`, `d.schema = 2`. An empty `position.map` means "start a new game here" (Task 6).
- [ ] **Step 4: Run, expect PASS** (all save tests).
- [ ] **Step 5: Leave unstaged.**

### Task 6: Story autoload, position save/resume, autosave on map change

**Files:**
- Create: `game/autoload/story.gd` (autoload `Story`, after `GameState`), `game/overworld/ui/location_banner.gd`
- Modify: `game/overworld/overworld.gd` (start from the save's position; write position before every save; show the banner), `game/autoload/game_state.gd` (`autosave()`/`save_manual()` ask the overworld for the position first via a `position_provider: Callable`), `project.godot`
- Test: `tests/story/test_story_api.gd`, `tests/world/test_overworld.gd` (extend)

**Interfaces:**
- Consumes: `StoryState`, `Overworld.change_map/load_map_at`.
- Produces (`Story`): `flag(id)`, `set_flag(id, on := true)`, `count(id)`, `add_count(id, n := 1)`,
  `is_done(key)`, `mark_done(key)`, `give_item(id, n := 1)`, `take_item(id, n := 1) -> bool`,
  `has_item(id, n := 1) -> bool`, `money() -> int`, `give_money(n)`, `take_money(n) -> bool`,
  `give_creature(species: String, level: int, starter := false) -> CreatureInstance`, `party_size() -> int`.
  (Battle, heal and minigame calls arrive in Tasks 12, 16, 18.)
  Overworld start: `position.map` empty or not a file in `res://game/maps/` → new-game map and spawn
  (Review Focus 4); otherwise `load_map_at(map, Vector2(x, y), facing)`. `map_changed` → `GameState.autosave()`;
  `GameState.current.location = map.display_name`. `LocationBanner.show(text)` slides in for 2 s when
  the new map's `display_name` differs from the previous one (spec §2.1).

- [ ] **Step 1: Write failing tests**: `test_items_and_money` (`give_item("salve", 2)`; `take_item("salve", 3)`
  false and count stays 2; `take_money` beyond balance false); `test_give_creature_party_then_storage`
  (`starter` true sets Bond to `balance.bond_cfg.starter`); `test_resume_restores_exact_position`
  (place at (123, 77) facing left in `test_b`, autosave, rebuild the overworld from the save → same map,
  position, facing); `test_missing_map_falls_back` (position.map `"deleted_map"` → loads `NEW_GAME_MAP`);
  `test_resume_inside_trigger_does_not_fire` (Review Focus 3: save while standing on a `Door` tile in
  `test_a`, resume → still on `test_a` until the player moves off and back);
  `test_banner_only_on_new_location` (two maps with the same `display_name` → no banner; different → banner).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS**; run `bash scripts/check.sh`.
- [ ] **Step 5: Leave unstaged.**

## Stage 3 — Talking, items and triggers

### Task 7: Conversation box and `Overworld.say`

**Files:**
- Create: `game/dialogue/dialogue_box.gd/.tscn`
- Modify: `game/overworld/overworld.gd`
- Test: `tests/world/test_dialogue_box.gd`, plus a fixture `tests/fixtures/test_talk.dialogue` (titles `hello`: two lines + a two-option response; `sets_flag`: `$> Story.set_flag("talked")`)

**Interfaces:**
- Consumes: `Settings.data.text_speed` (`"slow"|"normal"|"fast"|"instant"` → 20/45/90/∞ chars per second), `CommandMenu`, Dialogue Manager `DialogueManager.get_next_dialogue_line(resource, title, [extra_game_states])`.
- Produces: `class_name DialogueBox extends CanvasLayer`: `func run(resource: DialogueResource, title: String) -> void` (awaitable,
  returns at the end); `Overworld.say(dialogue_path: String, title: String) -> void` (awaitable; takes lock `"dialogue"`;
  refuses (returns at once) if a conversation is already running). `Story`, `Cutscene` and `Overworld` are
  passed as extra game states.

- [ ] **Step 1: Write failing tests**: `test_runs_to_end_and_mutations_apply` (instant text; drive Accept
  and pick the first response → `run` returns, `Story.flag("talked")` true after `sets_flag`);
  `test_accept_completes_line_first` (normal speed: one Accept shows the full line, the next advances);
  `test_second_say_is_refused` (Review Focus 2: calling `say` again while one runs returns immediately
  and doesn't stack a second box).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Speaker label above a `UIKit.panel` at the bottom (640×88); responses via `CommandMenu`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 8: Npc, Sign, ItemPickup, HiddenItem, Trigger

**Files:**
- Create: `game/overworld/pieces/{npc,sign,item_pickup,hidden_item,trigger}.gd/.tscn`
- Modify: `game/overworld/overworld.gd` (Accept → `map.piece_at(player.front_tile())?.on_interact(self)` when unlocked; wandering ticks)
- Test: `tests/world/test_pieces.gd`, and add a few of each piece to `test_a`

**Interfaces:**
- Consumes: `Piece`, `Story`, `Overworld.say`.
- Produces:
  - `Npc`: `@export actor_id, display_name, dialogue (path), title, facing ("down"…), wander_tiles: int`;
    `blocks()` true (a `StaticBody2D` child); `func face_toward(tile: Vector2i)`; `func walk_to(tile: Vector2i) -> void`
    (awaitable, straight lines, x then y); wanders only when the overworld is unlocked, at most `wander_tiles` from its start, never onto the player's tile or a solid tile.
  - `Sign`: `@export text`; interact shows the text (single-line conversation without a file).
  - `ItemPickup`: `@export item, count`; interact: `Story.give_item`, "Found X!" (×N when > 1), `Story.mark_done(save_key())`, `queue_free()`. On map load, already-done pickups free themselves.
  - `HiddenItem`: same, invisible, not solid.
  - `Trigger`: `@export dialogue, title, once, requires_flag, blocks_flag, size_tiles: Vector2i = Vector2i.ONE`;
    covers a rectangle (`piece_at` matches any tile in it); `on_enter` runs `say` when
    `(requires_flag == "" or Story.flag(requires_flag)) and (blocks_flag == "" or not Story.flag(blocks_flag))`
    and not (`once` and done); `once` marks done before running.

- [ ] **Step 1: Write failing tests**: `test_pickup_collected_once` (interact → bag +1, node gone; leave
  and return → still gone, bag unchanged); `test_hidden_item_found_by_facing` (facing it from the
  side, interact → found; not found when facing away); `test_npc_turns_to_player`;
  `test_trigger_flags_and_once` (blocked while `blocks_flag` set; `once` fires a single time across a map reload);
  `test_accept_while_locked_does_nothing` (Review Focus 2); `test_wander_stays_in_range` (simulate 200 wander
  ticks → always within range, never on a solid tile).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 9: Map checker

**Files:**
- Create: `tools/check_maps.gd`, `core/world/map_rules.gd` (pure checks taking plain dictionaries, so they're unit-tested)
- Modify: `scripts/check.sh` (new `== Maps` step after Dialogue), `tools/check_dialogue.gd` (verify `Story.*`/`Cutscene.*` call names against the autoload scripts' methods, and ids in `give_item`/`start_battle`/`start_minigame`/`give_creature` against the Database)
- Test: `tests/world/test_map_rules.gd`

**Interfaces:**
- Produces: `class_name MapRules`: `static func check(maps: Dictionary, db: Database, dialogue_titles: Dictionary) -> Dictionary`
  returning `{ "errors": PackedStringArray, "warnings": PackedStringArray }`. `maps` is
  `{ map_id: { "spawns": [id], "pieces": [ { "key", "type", "props": {}, "pos": Vector2 } ] } }`
  (the tool builds it by instancing each scene); `dialogue_titles` is `{ path: [titles] }`.
  Errors: unknown item/tamer/encounter/species/minigame id; door to a missing map or spawn; missing
  dialogue file or title; missing `HealSpot.respawn` spawn; duplicate save key; piece off the grid
  (`pos` not ≡ 16 mod 32); no `start` spawn in `town_01_home` (only once that map exists).
  Warnings: a door whose target map has no door back to this map.

- [ ] **Step 1: Write failing tests**, one per rule above, each building a tiny `maps` dictionary
  (one good case passes clean, then each broken case yields exactly the expected error text,
  e.g. `"test_a/Door1: door to missing map 'nowhere'"`).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `MapRules`, then the tool (`extends SceneTree`: load db, list `res://game/maps/*.tscn`
  except `_template`, instance, collect, print errors and warnings, exit 1 on errors) and the dialogue-call checks.
- [ ] **Step 4: Run tests, expect PASS; run `bash scripts/check.sh`**: `Maps OK`.
- [ ] **Step 5: Leave unstaged.**

## Stage 4 — Encounters and tamers

### Task 10: Grid sight lines, encounter roller, walk tracker

**Files:**
- Create: `core/world/grid.gd`, `core/world/encounter_roller.gd`, `core/world/walk_tracker.gd`
- Test: `tests/world/test_grid.gd`, `tests/world/test_encounter_roller.gd`, `tests/world/test_walk_tracker.gd`

**Interfaces:**
- Produces:
  - `class_name Grid`: `static func sight_tiles(from: Vector2i, facing: Vector2i, length: int, is_solid: Callable) -> Array[Vector2i]` (tiles in front, up to `length`, stopping before the first solid one).
  - `class_name EncounterRoller extends RefCounted`: `_init(balance: BalanceDef, rng: RandomNumberGenerator)`;
    `func on_grass_tile(table_id: String, can_fight: bool) -> bool` (false when `table_id == ""` or not `can_fight`;
    consumes a grace tile if any remain; else rolls `encounter_rate`); `func start_grace()` (sets `encounter_grace_tiles`).
  - `class_name WalkTracker extends RefCounted`: `_init(balance)`; `func on_tile(db: Database, party: Array) -> bool`
    (every `walk_energy_tiles` calls, +1 energy to each party creature with HP > 0, capped; returns true when it gave energy).

- [ ] **Step 1: Write failing tests**: sight: length 4 facing right with a wall at +3 → 2 tiles; all four
  facings; length 0 → empty. Roller: 10 000 seeded rolls ≈ 10% (±1.5%); `table_id ""` never;
  `can_fight` false never (Review Focus 5); after `start_grace()` the next 4 calls are false regardless of rng.
  Walk tracker: 7 calls give nothing, the 8th gives +1 to healthy creatures only, never above max.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 11: Shared field-count prompt, grass encounters, EncounterArea, walking energy

**Files:**
- Create: `game/ui/field_count_prompt.gd`, `game/overworld/pieces/encounter_area.gd/.tscn`, `data/encounters/route_01.json` (add `route_01_deep_grass`: pack 1–2, frostling 40, voltmoth 30, pebblet 30, levels 5–8)
- Modify: `game/debug/debug_menu.gd` (use the shared prompt), `game/overworld/overworld.gd` (on `tile_entered`: walk tracker; if not indoor and `map.is_encounter_tile`, roll with the area's or map's table)
- Test: `tests/world/test_encounters.gd`

**Interfaces:**
- Consumes: `EncounterRoller`, `WalkTracker`, `BattleLauncher.roll_wild_pack/wild_setup/healthy_count/max_fieldable`.
- Produces: `class_name FieldCountPrompt`: `static func ask(parent: Node, format_size: int, intro: String) -> Variant`
  (awaitable; int or null on cancel; returns 1 without showing when only one choice).
  `EncounterArea`: `@export encounter: String`, `@export size_tiles: Vector2i`; `GameMap.encounter_at(tile: Vector2i) -> String`
  (area containing tile, else `default_encounter`). `Overworld.start_wild(table_id: String) -> void` (awaitable:
  lock, pack, prompt, `SceneRouter.goto(BATTLE, {setup, return_to: WORLD})`); returning from battle restores the
  exact position (it's saved before leaving) and calls `roller.start_grace()`. Cancelling the prompt counts as fleeing.

- [ ] **Step 1: Write failing tests**: `test_area_overrides_default` (`encounter_at` inside / outside);
  `test_indoor_never_rolls` (rate forced to 1.0 via a fixture balance, walking on encounter tiles in an
  indoor map → no battle); `test_no_healthy_creatures_no_roll` (Review Focus 5); `test_walking_restores_energy`
  (8 tiles → +1); the debug-menu tests still pass with the shared prompt.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** The overworld owns one `EncounterRoller` and one `WalkTracker` seeded from a
  per-session RNG; tests inject a seeded RNG via `Overworld.rng`.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 12: Defeat rules and `Story.start_battle`

**Files:**
- Create: `core/world/defeat.gd`
- Modify: `game/battle/battle_launcher.gd` (`apply_results` no longer heals on a loss), `game/autoload/story.gd`, `game/overworld/overworld.gd` (handles the loss on return), `game/battle/battle_scene.gd` (loss text "You hurried back to safety...")
- Test: `tests/world/test_defeat.gd`, `tests/game/test_battle_launcher.gd` (update the placeholder-heal test)

**Interfaces:**
- Produces: `class_name Defeat`: `static func apply(db: Database, save: SaveGame) -> Dictionary` (heals the party,
  takes `floor(money × defeat_money_fraction)`, returns `{ "lost_money": int, "map": String, "spawn": String }`
  from `story.last_heal` or the new-game map and spawn).
  `Story.start_battle(tamer_id: String, defeat_rules := true) -> bool` (awaitable; field-count prompt; on return
  with a loss and `defeat_rules`, the overworld applies `Defeat` and moves to the respawn; with `defeat_rules`
  false the party is healed and nothing else happens); `Story.last_battle_won() -> bool`.
  The battle return carries `{"after_battle": {"won": bool, "defeat_rules": bool}}` in `SceneRouter.params`.
  `Story.battle_override: Callable` (default empty): when set, `start_battle` calls it with `(tamer_id)` and uses its
  bool result instead of changing scene. Tests in Tasks 12, 13 and 15 use it.

- [ ] **Step 1: Write failing tests**: `test_defeat_heals_and_costs_money` (money 1005 → loses 100);
  `test_defeat_respawns_at_last_heal` and `test_defeat_respawns_at_new_game_spawn_without_one`; launcher: a loss
  no longer heals; `test_story_battle_without_defeat_rules` (overworld handling `after_battle = {won: false,
  defeat_rules: false}` → party healed, money unchanged, same map).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 13: Tamers with sight lines

**Files:**
- Create: `game/overworld/pieces/tamer.gd/.tscn` (extends the Npc scene), emote bubble `game/overworld/emote.gd`
- Modify: `game/overworld/overworld.gd` (after each `tile_entered`, check unbeaten tamers), `data/tamers/route_01.json` (add `rival_lab`: 1 creature, level 5, `basic` AI, reward 100; add `hiker_tom`: 1v1, pebblet 6 + sprigling 6, reward 250)
- Test: `tests/world/test_tamers.gd`

**Interfaces:**
- Consumes: `Grid.sight_tiles`, `Npc.walk_to/face_toward`, `Story.start_battle`, `Overworld.say`.
- Produces: `Tamer` (`Npc` + `@export tamer_id, sight: int = 4, before_title, after_title`); `func sees(tile: Vector2i, map: GameMap) -> bool`;
  `func challenge(world: Overworld) -> void` (lock, "!" emote 0.6 s, walk to the tile before the player, face each other,
  `say(dialogue, before_title)` whose script calls `Story.start_battle(tamer_id)`; a win `mark_done(save_key())`).
  Beaten tamers never challenge; interact runs `after_title`. Talking to an unbeaten tamer also challenges.
  The `.dialogue` for a tamer's `before_title` must call `Story.start_battle`; the map checker (Task 9) warns if it doesn't.

- [ ] **Step 1: Write failing tests**: `test_tamer_spots_player_in_line` (walk into the line 3 tiles away →
  challenge starts, tamer ends adjacent); `test_wall_blocks_sight`; `test_beaten_tamer_ignores_player`
  (mark done → walking in line does nothing; interact runs `after_title`); `test_no_challenge_without_healthy_creatures`
  (Review Focus 5: shows a "Your team can't fight!" line instead); `test_resume_in_sight_waits_for_a_step`
  (Review Focus 3).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Tests stub the battle with `Story.battle_override` (Task 12).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

## Stage 5 — Cutscenes and the starter

### Task 14: Cutscene autoload

**Files:**
- Create: `game/autoload/cutscene.gd` (autoload `Cutscene`)
- Modify: `project.godot`
- Test: `tests/world/test_cutscene.gd`

**Interfaces:**
- Consumes: `Overworld` (found via `get_tree().current_scene as Overworld`), `Npc.walk_to`, emote.
- Produces (all awaitable): `lock_player()`, `unlock_player()`, `move(actor: String, where: String)`
  (`where` = spawn id or `"x,y"` tile; actor `"player"` walks too), `face(actor, dir_or_actor: String)`,
  `emote(actor, kind: String)` (`"!"`, `"?"`, `"..."`), `pan_camera(where: String)`, `camera_back()`,
  `fade_out()`, `fade_in()`, `wait(seconds: float)`, `change_map(map_id, spawn_id)`. An unknown actor or spot
  `push_error`s and returns at once (so a typo never hangs a cutscene).

- [ ] **Step 1: Write failing tests**: in `test_a` with an `Npc` (`actor_id "guide"`): `move("guide", "start")`
  ends on the spawn's tile; `face("player", "guide")` sets facing toward it; `move("nobody", "start")` returns
  without hanging; lock/unlock round-trips `is_locked()`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 15: Town maps, starter sequence and lab rival

**Files:**
- Create: `game/maps/town_01.tscn`, `town_01_home.tscn`, `town_01_lab.tscn`, `town_01_center.tscn` (centre pieces added in Task 16), `dialogue/town_01/intro.dialogue` (professor), `dialogue/town_01/lab.dialogue` (starter choice + rival), `dialogue/town_01/npcs.dialogue`
- Modify: `game/autoload/game_state.gd` (`start_new_game` sets `position` to the new-game map/spawn)
- Test: `tests/world/test_starter.gd`

**Interfaces:**
- Consumes: everything above. Content per spec §7.3–7.4: home door-mat `Trigger` (`blocks_flag: got_starter`,
  title `intro`); lab script offers the three starters, gives `Story.give_creature(species, 5, true)` + 5 `lure_cage`,
  sets `got_starter`, the rival "picks" a different one (dialogue line only; `rival_lab`'s creature is fixed in data),
  then `Story.start_battle("rival_lab", false)`; town north-exit `Trigger` (`blocks_flag: got_starter`) turns the
  player back with a line.

- [ ] **Step 1: Write failing tests**: `test_new_game_starts_at_home` (fresh game → `town_01_home`, spawn `start`);
  `test_choosing_a_starter` (run `lab.dialogue` title `choose` with the response for Emberkit picked → party is one
  level-5 Emberkit with starter Bond, 5 Lure Cages, flag `got_starter`; `rival_lab` battle requested with
  `defeat_rules == false` via `battle_override`); `test_exit_blocked_without_starter`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Paint the maps and write the scripts.** Run `bash scripts/check.sh` (Maps OK, Dialogue OK).
- [ ] **Step 4: Run tests, expect PASS.**
- [ ] **Step 5: Real window:** extend `--mode=overworld`: new game → intro cutscene → lab → pick a starter
  → rival battle → back in the lab. Look at the screenshots.
- [ ] **Step 6: Leave unstaged.**

## Stage 6 — Heal, shop, pause menu

### Task 16: HealSpot and Story.heal_party

**Files:**
- Create: `game/overworld/pieces/heal_spot.gd/.tscn`
- Modify: `game/autoload/story.gd` (`heal_party()`), `game/maps/town_01_center.tscn` (HealSpot with `respawn: "heal"` and a `heal` spawn)
- Test: `tests/world/test_heal_spot.gd`

**Interfaces:**
- Produces: `Story.heal_party()` (each party creature: `heal_full(db)` then `Progression.rest(db, c)`, which applies the "rested" Bond change);
  `HealSpot` (`@export respawn: String`); interact: "Rest here?" Yes → heal, `story.last_heal = {map, spawn: respawn}`, "Your team is rested."

- [ ] **Step 1: Write failing tests**: heal restores HP, energy and status, applies the "rested" Bond change once
  per creature, and sets `last_heal`; answering No changes nothing.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

### Task 17: Shop and pause menu (Party, Bag, Save, Settings, Quit)

**Files:**
- Create: `core/world/shop.gd`, `core/progress/field_items.gd`, `game/overworld/pieces/shop_counter.gd/.tscn`, `game/overworld/ui/shop_menu.gd`, `game/overworld/ui/pause_menu.gd`
- Modify: `game/overworld/overworld.gd` (Menu action opens the pause menu when unlocked), `game/debug/debug_menu.gd` (F1 refuses while the overworld is locked), `game/maps/town_01_center.tscn` (ShopCounter, stock per spec §7.4)
- Test: `tests/world/test_shop.gd`, `tests/progress/test_field_items.gd`, `tests/world/test_pause_menu.gd`

**Interfaces:**
- Produces:
  - `class_name Shop`: `static func buy(db, save, item_id, n) -> Dictionary` and `static func sell(db, save, item_id, n) -> Dictionary`,
    both `{ "ok": bool, "error": String }`; errors `"not_enough_money"`, `"not_enough_items"`, `"cannot_sell"` (price 0), `"bad_amount"` (n < 1 or > 99).
    Sell price `floor(price × sell_fraction)`.
  - `class_name FieldItems`: `static func can_use(db, item_id, creature) -> bool`;
    `static func use(db, save, item_id, creature) -> Dictionary` `{ ok, error, healed, energy }`; supports `heal`
    (`fraction`) and `restore_energy` (`fraction`) ops; errors `"fainted"`, `"no_effect"` (already full), `"not_usable"`.
  - `ShopCounter` (`@export stock: PackedStringArray`); `ShopMenu.open(world, stock)` (awaitable).
  - `PauseMenu` with entries Party, Bag, Save, Settings (`SceneRouter.goto(SETTINGS, {return_to: WORLD})` after saving the position), Quit to title, Close.

- [ ] **Step 1: Write failing tests**: Shop: buy 3 Salve at 150 with 500 → ok, money 50, bag +3; buy with too
  little money → error, unchanged; sell 2 → +150; sell more than owned → error; `bad_amount` for 0 and 100.
  FieldItems: Salve on a damaged creature heals 33% of max; on a fainted creature → `"fainted"`; Tonic restores
  energy; a capture item → `"not_usable"`. Pause menu: Menu opens it when unlocked; does nothing while
  `is_locked()` (Review Focus 2); Save writes a manual save; F1 during a conversation does nothing (Review Focus 2).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

## Stage 7 — Minigames

### Task 18: Minigame hook and Quick Draw

**Files:**
- Create: `data/minigames.json`, `core/data/defs/minigame_def.gd`, `game/minigames/minigame.gd`, `core/minigames/quick_draw.gd`, `game/minigames/quick_draw/quick_draw.gd/.tscn`, `game/overworld/pieces/minigame_spot.gd/.tscn`
- Modify: `core/data/schemas.gd` (`"minigames": "file"`, entry `{id, name, scene: string}`), `core/data/database.gd` (`minigame(id)`), `core/data/validator.gd` (the scene file exists), `game/autoload/story.gd` (`start_minigame`, `last_minigame`)
- Test: `tests/minigames/test_quick_draw.gd`, `tests/data/test_validator.gd` (extend), `tests/world/test_minigame_hook.gd`

**Interfaces:**
- Produces: `class_name Minigame extends Control`: `signal finished(result: Dictionary)`; virtual `func begin(params: Dictionary)`.
  `Story.start_minigame(id: String, params := {}) -> Dictionary` (awaitable; locks and pauses the map, adds the scene on a
  `CanvasLayer`, awaits `finished`, frees it; result always has `won` and `score`); `Story.last_minigame() -> Dictionary`.
  `class_name QuickDraw extends RefCounted`: `_init(rng, window := 0.45, rounds := 5)`; `func next_delay() -> float`
  (1.0–3.0 s); `func press(at_seconds_after_signal: float) -> String` (`"early"` when negative, `"win"` within `window`,
  else `"slow"`); `func is_over() -> bool`; `func result() -> Dictionary` (`won` = wins ≥ 3).
  `MinigameSpot` (`@export minigame, dialogue, title`).

- [ ] **Step 1: Write failing tests**: QuickDraw: early press loses the round; 0.3 s wins; 0.5 s is slow; 3 of 5 →
  `won`; 2 of 5 → not won; `is_over` after 5 rounds. Validator: a minigame whose scene path doesn't exist → error.
  Hook: a stub minigame scene that finishes immediately with `{won: true, score: 7}` → `start_minigame` returns it,
  `last_minigame()` matches, the map is unpaused and unlocked afterwards.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Leave unstaged.**

## Stage 8 — Content, guide, tour

### Task 19: Route 1, rival rematch and remaining content

**Files:**
- Create: `game/maps/route_01.tscn`, `dialogue/route_01/{tamers,npcs,minigame}.dialogue`
- Modify: `dialogue/route_01/rival_intro.dialogue` (reworked as the rematch: `Story.start_battle("rival_01")`, flag `rival_1_done`), `game/maps/town_01.tscn` (north door to `route_01`)
- Test: `tests/world/test_maps_load.gd`

**Interfaces:**
- Consumes: all pieces. Content per spec §7.4: grass with `default_encounter: route_01_grass`, one `EncounterArea`
  (`route_01_deep_grass`), `Tamer`s `scout_ana` and `hiker_tom`, 2 `ItemPickup`s (salve ×2, tide_net), 1 `HiddenItem` (tonic),
  the rematch `Trigger` (`once`, `requires_flag: got_starter`), a `MinigameSpot` NPC running Quick Draw; the first win gives a Tonic and sets
  flag `quick_draw_won` (later wins just get a line), a "Road closed" `Sign`.

- [ ] **Step 1: Write the failing test** `test_every_map_loads_and_spawns_exist` (instances every map in `game/maps/`,
  each has ≥ 1 spawn, `bounds()` non-empty).
- [ ] **Step 2: Build the map and scripts;** `bash scripts/check.sh` → Maps OK with no warnings, Dialogue OK.
- [ ] **Step 3: Run tests, expect PASS.**
- [ ] **Step 4: Leave unstaged.**

### Task 20: Map-building guide, overworld tour, docs

**Files:**
- Create: `documentation/map-building.md`
- Modify: `.claude/skills/run-godot-monster-catching-game/driver.gd` + `SKILL.md` (full `--mode=overworld` tour, gotchas), `README.md`, `documentation/specs/2026-11-03-monster-rpg-design.md` (M3 status), `documentation/battle-engine.md` (defeat no longer handled by the launcher), `tools/generate_compendium.gd` (list maps, their encounters and tamers)

- [ ] **Step 1: Write the guide**: duplicate `_template.tscn`; paint with the placeholder tileset (which tiles collide,
  which are grass); drag pieces from `game/overworld/pieces/` with a table of every piece's fields (copy spec §2.4);
  connect doors both ways; write dialogue titles; run `bash scripts/check.sh` and read the Maps errors.
- [ ] **Step 2: Follow the guide yourself** to add a one-room test house to `town_01`; `check.sh` passes; remove it afterwards
  unless it's good content.
- [ ] **Step 3: Full tour** (`--mode=overworld`): new game → intro cutscene → starter → rival → town → centre (heal, buy a
  Salve) → route grass encounter → a tamer spotting the player → Quick Draw → pause-menu save → resume at the same spot.
  At least 8 `expect` checks. Run it, look at every screenshot, and run the front-end and battle tours too.
- [ ] **Step 4: `bash scripts/check.sh`** → `All checks passed.` Update `SKILL.md`'s expected `Statistics:` count.
- [ ] **Step 5: Leave unstaged and write the user an example commit message per stage.**
