# Developer guide

How to change this project by hand: where things live, how a change travels through the code, a recipe for each
common change, and what to do when a check fails. For what the game *is*, see the [README](../README.md) and the
[design spec](specs/2026-11-03-monster-rpg-design.md). Status: complete through M7 (M6 partly: see
[Roadmap](#roadmap-and-where-the-plans-are)).

Contents: [Setup](#setup-and-the-daily-loop) · [How it fits together](#how-it-fits-together) ·
[Where do I find...](#where-do-i-find) · [Recipes](#recipes) · [Tests](#tests) ·
[Generated files](#generated-files-and-what-regenerates-them) · [Troubleshooting](#troubleshooting) ·
[Conventions](#conventions) · [Driving the game from the command line](#driving-the-game-from-the-command-line) ·
[Roadmap](#roadmap-and-where-the-plans-are)

## Setup and the daily loop

- **Godot 4.7.2.** The project is GDScript only. The .NET editor build works (it shows a harmless ".NET Sdk not
  found" at startup); the standard build avoids that.
- **Open the project** in the editor (`project.godot`). The first open imports assets and builds the script class
  list; if scripts show "Identifier not declared" after pulling new files, run
  `godot --headless --path . --import` once, or reopen the editor.
- **Play:** F5 (main scene is the splash). **F1** opens the debug menu in a debug build: test party, give XP, set
  Affinity or a passive, fill or unlock boxes, **Collection...** (Codex and achievements), test battles, the UI
  gallery and the live log viewer.
- **Before you commit:** `bash scripts/check.sh`. It runs, in order: data validation, dialogue compile, map check
  (doors, spawns, ids, `data/locations.json` freshness), the whole test suite, then regenerates
  `documentation/compendium.md`. It must end with `All checks passed.` Run it from Git Bash on Windows. If Godot is
  not at the default path inside the script, set `GODOT` to your **console** executable:

  ```bash
  export GODOT="/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
  ```
- **Run one test suite** (much faster while you work), then the full check at the end:

  ```bash
  "$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/progress/test_codex.gd --ignoreHeadlessMode -c
  ```

  `--add` takes a file or a folder (`res://tests/achievements`) and can be repeated.
- **Do not run two Godot processes at once** (the editor running the game counts): tests, tools and the game share
  save folders and the import cache, and they collide.
- **Player data** (saves, settings, logs) is in Godot's user folder, `%APPDATA%/Godot/app_userdata/Monster Catching Game/`
  on Windows; F1 → Logs... → Open log folder jumps there. Deleting `saves/` gives you a fresh start.

## How it fits together

### The one rule: `core/` is pure

`core/` is game logic that never touches nodes, scenes or autoloads. It takes what it needs as arguments (a
`Database`, a `SaveGame`, an RNG) and returns results. `game/` is the thing that shows `core/` on screen and wires it
to input and scenes. If you are writing logic and find yourself reaching for `GameState` or `get_tree()`, it belongs in
`game/`, or the function should take the value as a parameter. This is why almost everything is unit-testable without
running the game.

### Data flows one way

```
data/*.json ──DataLoader──▶ DataValidator (schemas.gd + cross rules) ──▶ Database (typed *Def objects)
                                                                              │
                         DataRegistry autoload loads it once at boot ─────────┘ passed into core and screens
```

- `core/data/schemas.gd` describes every JSON field; the validator rejects anything not described (typos fail loudly).
- Content is split into **categories**: `folder` categories read every `*.json` in `data/<name>/`; `file` categories
  are one `data/<name>.json`; `balance` is a single object. See `DataSchemas.CATEGORIES`.
- A debug build also layers `data_testpack/` (`tp_` ids) on top; it never reaches saves or release builds. Never
  write the text `tp_` or `testpack` in `core/`, `game/`, `data/` or `dialogue/` (a test enforces it).

### Autoloads (`game/autoload/`)

| Autoload | Role |
|---|---|
| `Logging` | Sets up the logger, sinks and log levels (`Log.info(Log.WORLD, "text", {...})` from anywhere). |
| `DataRegistry` | Loads content once; `DataRegistry.db` is the `Database`. Core code never uses it; screens pass `db` in. |
| `Settings` | The settings model (audio, window, controls) and input bindings. |
| `GameState` | The playthrough in progress: `GameState.current` (a `SaveGame`), saving, loading, autosave, playtime. |
| `SceneRouter` | Changes between the splash, title, new game, load, settings, world and battle scenes. |
| `Story` | The API that map pieces and `.dialogue` scripts use: flags, counters, items, money, creatures, battles, healing. |
| `Cutscene` | Dialogue-script commands that move people and the camera, lock input and change maps. |
| `AchievementService` | Drains `AchievementWatch` keys each frame and unlocks achievements. |
| `DebugMenu` | The F1 menu (debug builds only). |

### Screens

The **Overworld** scene hosts the player, the current map and the pause menu. The pause menu (`game/overworld/ui/pause_menu.gd`)
opens the progression screens, which are `CanvasLayer`s extending `ProgressScreen` (Party, Summary, Codex, Achievements,
Learn Move, Grow...). A `ProgressScreen` has an info panel on top, a scrolling menu below it, and an optional left pane
(`set_side`); a screen only fills in text and options. `ScreenFit.problems(screen)` (in tests) checks a screen fits the
640x360 viewport. Shared pieces live in `game/ui/` (`UIKit`, `CreatureCard`, `CreatureSpriteSlot`, icon slots...).

### Saves

`SaveGame` (`core/save/save_game.gd`) is the whole playthrough; `SaveStore` reads and writes JSON files and migrates
old saves one schema version at a time. Changing what a save holds means a schema bump and a migration (recipe below).

### Tracking and achievements

Lifetime counters and the Codex are recorded at a handful of choke points ([tracking.md](tracking.md)). Every tracked
change also pushes a key into `AchievementWatch`; the service checks only the achievements that watch that key
([achievements.md](achievements.md)).

## Where do I find...

| I want to change... | Look in |
|---|---|
| A number: damage, XP, level cap, party size, Bond, encounter rate, catch rate | `data/balance.json` |
| A creature, move, item, passive, tamer, encounter, type, status | `data/<category>/*.json` (see recipes) |
| What a creature/move/etc. is *called* or described | the same JSON (`name`, `description`) |
| Wild creatures on a route | `data/encounters/`, linked from a map (`default_encounter`) or an `EncounterArea` piece |
| A map's layout, doors, NPCs, shops | `game/maps/<id>.tscn` in the editor ([map-building.md](map-building.md)) |
| What people say, and story events | `dialogue/<area>/*.dialogue` |
| The story state a script reads/writes | `Story` (`game/autoload/story.gd`); data in `core/story/story_state.gd` |
| How a battle plays out (damage, order, effects, AI) | `core/battle/` ([battle-engine.md](battle-engine.md)) |
| Creature stats, XP, growth, Bond, passives, training | `core/progress/` |
| Menus, screens, their layout | `game/progress/`, `game/menus/`, `game/overworld/ui/`, `game/battle/` |
| Colours, fonts, shared widgets | `game/ui/ui_kit.gd` and the widgets beside it |
| Controls and settings | `core/settings/game_settings.gd` (model), `game/menus/settings_menu.gd` (screen) |
| Save format | `core/save/save_game.gd`, `core/save/save_store.gd` |
| What the F1 menu does | `game/debug/` (`pages/` holds one file per page) |
| Logging | `core/log/`, `game/log/`; [logging.md](logging.md) |
| The Codex and where-to-find data | `core/progress/codex.gd`, `locations.gd`, `data/locations.json`; [codex.md](codex.md) |

## Recipes

Every recipe ends the same way: `bash scripts/check.sh` (the validator names the file, entry and field of each
mistake: `res://data/creatures/route_01.json [creatures:emberkit] base_stats.hp: missing required field`).

### Change a balance number
Edit `data/balance.json`. Fields are validated by `DataSchemas.ENTRY["balance"]`; the allowed ranges are there. The
compendium's "Rules and Balance" section is regenerated by the check. Re-run the battle simulator if win rates matter
(see [Balance simulator](battle-engine.md#balance-simulator)).

### Add or edit a creature
1. Add an entry to a file in `data/creatures/` (copy an existing one). Required: `id` (lowercase snake_case), `name`,
   `types` (1-2), the nine `base_stats`, `catch_rate`, `xp_yield`, a `learnset` with at least one level-1 move,
   and 1-2 `passives`. Optional: `description`, `dex`, `growth` (evolution branches), `growth_rates`, `affinity_passives`.
2. Give it a **unique `dex`** number (the next free one: a test requires every shipped creature to have one, with no
   gaps, and the Codex sorts by it) and a `description` (a validator warning otherwise).
3. To make it findable, add it to an encounter table (`data/encounters/`). If you changed which tables a map uses,
   regenerate the locations (below).
4. New moves and passives it names must exist.

### Add a move
Add an entry to the type's file in `data/moves/` (`water.json`...). `type`, `category` (`physical`/`special`/`status`),
`power`, `cost` (energy), `accuracy`, `target`, and `effects`: a list of ops. The available ops and their fields are
`DataSchemas.EFFECT_OPS`; their meaning is in [battle-engine.md](battle-engine.md).

### Add a new effect op (a new kind of thing a move or passive can do)
Follow [Adding a new effect op](battle-engine.md#adding-a-new-effect-op): the schema entry in `EFFECT_OPS`, a handler in the
battle engine, a readable sentence in `EffectText.effect()` (`core/data/effect_text.gd`), and tests.

### Add an item
Entry in `data/items/`: `category` (`capture`, `heal`, `battle`, `key`, `training`, `held`), `price`, `target`,
`effects`, and a `held` block for held items. To sell it, add its id to a shop: the `stock` field of a `ShopCounter`
piece in a map scene (in the Inspector). Starter maps are also described in `tools/build_maps.gd`; once a map is edited
by hand, that list is not used (see map-building.md).

### Add a passive
Entry in `data/passives/core.json` with `effects`, `triggers` and/or `field` ops (at least one). Reference it from a
creature's `passives` or `affinity_passives`. Triggers and when they fire: battle-engine.md → Passives.

### Add a tamer (a trainer you can battle)
1. Entry in `data/tamers/` with `max_active`, `ai` (`basic`/`aggressive`/`tactician`), `reward_money`, and the `party`.
2. A `Tamer` piece on a map (`tamer_id`, `sight`, `before_title`, `after_title`).
3. In the `before_title` dialogue, call `$> Story.start_battle("<tamer_id>")`.

### Add a wild area
1. Encounter table in `data/encounters/` (species, weights, level range, pack size).
2. In the map scene: set `default_encounter` on the map root for all its tall grass, or drop an `EncounterArea` piece for
   a rectangle.
3. Regenerate the where-to-find data, then run the check:

   ```bash
   "$GODOT" --headless --path . res://tools/build_locations.tscn
   ```

### Add or edit a map
See [map-building.md](map-building.md): duplicate `game/maps/_template.tscn`, paint, drop pieces from
`game/overworld/pieces/`, connect doors both ways, write dialogue. The map checker lists broken doors and typos.

### Write dialogue or a story event
Files in `dialogue/<area>/*.dialogue` ([Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager)
4 syntax: mutations are `$> Story.set_flag("x")`, conditions `if Story.flag("x")`, jumps `=> title`, responses
`- Text [if cond /]`). Scripts can call `Story` and `Cutscene`; `scripts/check.sh` verifies every called function and
every item, tamer and creature id. A flag is just a string: invent one in a script and read it elsewhere
(`Story.flag("met_prof")`, a `Trigger` piece's `requires_flag`/`blocks_flag`, or an achievement's `flag` criterion).

### Add an achievement
JSON only: [achievements.md](achievements.md). Entry in `data/achievements/achievements.json` with one criterion
(`counter`, `codex`, `flag` or `creature`).

### Add a new kind of achievement criterion
One `Criterion` subclass, one `Criteria.KINDS` line, one `DataSchemas.CRITERIA` entry, and a push of a *narrow* watch
key wherever the thing it reads changes (achievements.md has the checklist).

### Add a lifetime counter
Add its id to `Counters.BUILT_IN` (`core/progress/counters.gd`), call `Counters.add(save, id)` where it happens, add a
test for the hook ([tracking.md](tracking.md)).

### Add a pause-menu screen
1. Copy `game/progress/codex_screen.gd` (a list with a left preview) or `party_screen.gd`: extend `ProgressScreen`, give it a
   `static func run(parent: Node, save: SaveGame = null, db: Database = null)`, fill `_title`/`_body`, and
   `await menu.choose(...)` in a loop.
2. Add a row to the options list in `game/overworld/ui/pause_menu.gd` and a matching `match` branch that awaits
   `YourScreen.run(world)`.
3. Test it like `tests/world/test_codex_screen.gd` (open it in a `WorldTest` world, read `menu.labels()`, check
   `ScreenFit.problems(screen)` is empty). A tour is optional (see below).

### Add something to a save
1. Add the field to `SaveGame`, write it in `to_dict()` and read it (tolerantly: wrong types must not crash) in `from_dict()`.
2. Bump `SaveGame.SCHEMA`, add `_vN_to_vN+1` in `core/save/save_store.gd` and register it in the migrations table.
3. Add tests like `tests/save/test_achievements_load.gd` (round trip, the migration, junk values), and update any test that
   pins the schema number.

### Add a setting or a rebindable control
`core/settings/game_settings.gd` (field, defaults, load/save; controls are in `ACTIONS` and `default_bindings()`) and the screen
`game/menus/settings_menu.gd`.

### Add an F1 debug page
A `DebugPage` subclass in `game/debug/pages/` (`title()`, `build(box)`), opened from a button in `debug_main_page.gd`. Put the
page's actions in public methods so a test can call them without clicking.

### Log something
`Log.info(Log.STORY, "Flag set", {"flag": id})`. Categories are in `core/log/log.gd`. Headless runs only show WARN and above.

## Tests

- **Layout:** `tests/<area>/test_*.gd`, one folder per area (`battle`, `data`, `progress`, `save`, `world`, `game`, `achievements`...).
  They use GdUnit4 (`extends GdUnitTestSuite`, `assert_*`).
- **Two data sources.** `FixtureDB` (`tests/helpers/fixture_db.gd`) is a small hand-made content set that never changes when you
  rebalance the real game; use it for engine and rules tests. Tests that check shipped content load the real data
  (`DataLoader.load_database("res://data")` or `DataRegistry.db`).
- **Tests that need the overworld or a playthrough** use `WorldTest` (`tests/helpers/world_test.gd`): `begin_suite` (throwaway
  saves), `open` a test map, `find_screen`, `close`, `end_suite`. The maps `test_a` and `test_b` exist for this.
- **Screens fit the viewport:** `ScreenFit.problems(screen)` returns what overflows 640x360; assert it is empty.
- **Static state leaks between tests.** `AchievementWatch` is a static set: call `AchievementWatch.clear()` in `before_test`
  when you depend on it, and reset `GameState.current` if you set it.
- **Write the test first** when you can: watching it fail proves it tests something.
- **The test pack** is exercised by `tests/battle/test_testpack_*.gd`; its content is not part of the shipped game.

## Generated files and what regenerates them

| File | Regenerated by | When you must do it |
|---|---|---|
| `documentation/compendium.md` | `bash scripts/check.sh` (or `tools/generate_compendium.gd`) | After any content change; commit the result. Never edit by hand. |
| `data/locations.json` | `tools/build_locations.tscn` (command above) | After you change which encounter tables a map uses. `check_maps` fails with the exact command when it is stale. |
| `*.gd.uid`, `*.import` | Godot, when it opens or imports the project | Commit the `.uid` files that appear next to new scripts. |
| `reports/` | gdUnit4 | Ignored by git. |
| `game/maps/*.tscn` from `tools/build_maps.gd` | `tools/build_maps.tscn` | Only for the starter maps; it never overwrites an existing map unless asked, and rebuilding discards editor edits (see map-building.md). |

## Troubleshooting

- **`Data failed to load` / a validator line.** The line names the file, `[category:id]`, the field path and the problem.
  Fix the JSON; run `"$GODOT" --headless --path . --script res://tools/validate_data.gd` to see every error.
- **`data/locations.json is out of date`.** Run the `build_locations.tscn` command it prints.
- **A compendium or "contents" test fails.** The compendium is generated: run the check once (it rewrites the file), then
  re-run; if a *test* still fails, a section list changed and `tests/data/test_compendium.gd` needs the new section.
- **`Identifier "X" not declared` / `Could not find type`** after adding or renaming a `class_name`: run
  `godot --headless --path . --import` (or reopen the editor) so the class list refreshes.
- **`Assigned value for constant isn't a constant expression`** when a `const` dictionary holds classes: use
  `preload("res://path.gd")` instead of the class name (see `Criteria.KINDS`).
- **A test about `tp_` or `testpack` fails.** Those words may not appear in `core/`, `game/`, `data/` or `dialogue/`
  except where the test allows them (`tests/data/test_testpack_removal.gd`).
- **A test that passes alone fails in the full run** (or the reverse): shared state. Look for a static (`AchievementWatch`),
  `GameState.current`, an edited `DataRegistry.db` table that was not restored in `after_test`, or a save folder.
- **Dialogue errors:** `bash scripts/check.sh` prints `file.dialogue:line: message`. Titles are `~ name`; jumps stay inside one file.
- **Godot warns about line endings or shows whole-file diffs.** `.gitattributes` normalises to LF in the repository; keep your
  editor from rewriting line endings and avoid editing a file with two tools at once.
- **The game asserts "Content failed validation" on start (debug build).** `DataRegistry` refuses to start with invalid
  content; run the validator command above.
- **Nothing happens when you press F1.** F1 works only in debug builds, on a screen that allows it (not during a transition).

## Conventions

- **Typed GDScript, tabs for indentation.** `class_name` on anything you reference elsewhere. `##` doc comments above a class or
  function are used throughout; say *why*, not what the code already says.
- **`core/` takes arguments, `game/` reaches for globals.** Pure functions are `static` when they hold no state.
- **Content ids** are lowercase snake_case and stable (saves remember them): do not rename a creature, item, flag, map piece
  or achievement id after release; add a new one instead.
- **Piece names in map scenes are part of the save** (`route_01/Potion1`): do not rename collected items or beaten tamers.
- **One responsibility per file**, small files, tests beside the behaviour they pin.
- **Commits** in this repo are titled `<what changed>` with `(Mx)` for milestone work, followed by a short bullet list.

## Driving the game from the command line

`.claude/skills/run-godot-monster-catching-game/` holds a driver that plays the game headlessly or in a real window and takes
screenshots: tours for the frontend, battle, overworld, progress, party, box, bag, codex, achievements and more. Run one with
(note `--fixed-fps 60` comes before `--script`, the mode after `--`):

```bash
"$GODOT" --path . --fixed-fps 60 --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=codex --out="$TEMP/shots"
```

The tour prints `[driver] PASS ...` lines and `ALL CHECKS PASSED`; the screenshots (`.png`) are the quickest way to see a UI
change. `SKILL.md` in that folder lists every mode. These tours need a display; the unit tests and tools do not.

Other tools in `tools/`: `validate_data.gd`, `check_dialogue.gd`, `check_maps.tscn`, `simulate.gd` (seeded AI-vs-AI battles for
balance), `generate_compendium.gd`, `build_locations.tscn`, `build_maps.tscn`, `generate_placeholder_tiles.gd`.

## Roadmap and where the plans are

- **Done:** M0-M5 (engine, battle scene, overworld, progression, box and party screens), M6 status-cure (the `cure_status` op, the
  `status` trigger, Clear Tonic), **M7 Collection and achievements** (tracking, the Codex, achievements).
- **Still open in M6:** multi-hit moves, a growth-tier content pass, AI trigger modelling, a few pinned engine rulings.
- **Next:** M8 art and audio (the icon and sprite slots are placeholders), M9 content expansion.
- **Specs** (the design of each piece) are in `documentation/specs/`, **plans** (how it was built) in `documentation/plans/`.
  The roadmap is `specs/2026-11-05-roadmap-m5-m8.md`; the original design is `specs/2026-11-03-monster-rpg-design.md`.
