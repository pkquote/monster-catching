# Monster Catching Game

A top-down monster-catching RPG in Godot 4.7 (typed GDScript). Its signature mechanics are
field states with combo reactions, behavior-shaped growth, N-vs-M battles with Underdog compensation,
and creature passives (a rolled passive for life plus one unlocked through Affinity; one is active at a time).

**Status:** milestones M0-M7 are done (battle engine, overworld, progression, the box and party screens, the Codex and
achievements), and so is the M6 engine backlog (AI trigger modelling, swapping and styles; multi-hit moves; status cure); M8 (art and audio) and M9 (content) are next. All art is still placeholder.

**Making a change by hand? Start with the [developer guide](documentation/developer-guide.md):** setup, how the code fits
together, where to find things, a recipe for each common change (a creature, a move, a map, dialogue, an achievement, a
screen, a save field...) and what to do when a check fails.

Design spec: [documentation/specs/2026-11-03-monster-rpg-design.md](documentation/specs/2026-11-03-monster-rpg-design.md)

Content reference (every creature, move, item, status, field state, reaction, passive, AI style, tamer, encounter and achievement):
[documentation/compendium.md](documentation/compendium.md). It is generated from `data/` by `tools/generate_compendium.gd` (via `tools/compendium_builder.gd`), so don't edit it by hand. Rules and Balance come first, then Types through Held items, Moves, Items, Creatures, AI Styles, Tamers, Encounters and Achievements.

Battle engine reference (API, round order, formulas, passives and their triggers, events, effect ops, tests):
[documentation/battle-engine.md](documentation/battle-engine.md)

Battle AI (the styles, how moves, Rest and swaps are scored, what it values from passives, held items and triggers):
[documentation/ai.md](documentation/ai.md)

Building maps (painting tiles, placing doors, NPCs, items, tamers, triggers; checking them):
[documentation/map-building.md](documentation/map-building.md)

Tracking and collection: [tracking.md](documentation/tracking.md) (the Codex's seen/caught data and the eight lifetime counters),
[codex.md](documentation/codex.md) (the Codex screens, `dex` numbers and where-to-find data),
[achievements.md](documentation/achievements.md) (adding achievements and criterion kinds). Logging:
[documentation/logging.md](documentation/logging.md).

## Layout

| Folder | Contents |
|---|---|
| `core/data/` | JSON loader, schemas, validator, typed definitions. |
| `core/progress/` | Creature instances, stat/XP formulas, Affinity and growth, passives (rolling, unlocking, the active slot), box storage, the Codex and lifetime counters, where-to-find lookups. |
| `core/achievements/` | Achievement criteria (counter, codex, flag, creature), the pure evaluator, and the watch set that tells the service what changed. |
| `core/battle/` | Headless battle engine, effect ops, AI. |
| `core/` | All of `core/` is pure game logic. It never touches nodes, scenes, or autoloads. |
| `core/save/`, `core/settings/` | Save format and file store; settings model and input bindings. |
| `core/story/`, `core/world/`, `core/minigames/` | Story state; overworld rules (encounters, sight lines, shop, defeat, map checks); minigame rules. |
| `game/` | Scenes and autoloads that present `core/`: splash, menus, overworld, battle, the progression screens (`game/progress/`: party, summary, Codex, Achievements...), shared UI widgets (`game/ui/`), and the autoloads `DataRegistry`, `GameState`, `SceneRouter`, `Story`, `Cutscene`, `Settings`, `AchievementService`, `DebugMenu`. |
| `game/maps/` | One scene per map (built in the Godot editor; see the map-building guide). |
| `data/` | All content as JSON (creatures, moves, items, passives, AI styles, tamers, encounters, ...). |
| `dialogue/` | Dialogue Manager `.dialogue` files for conversations and cutscenes. |
| `tests/` | gdUnit4 suites. |
| `data_testpack/` | Debug-only test content (`tp_` ids), never in release builds. |
| `scripts/` | `check.sh`, the one command that runs every check. |
| `tools/` | Data validator, dialogue checker, map checker, map builder, locations generator, tileset generator, compendium generator, battle simulator. |
| `documentation/` | Guides, specs (the design of each piece) and plans (how it was built); see the [developer guide](documentation/developer-guide.md). |
| `.claude/skills/` | A driver that plays the game from the command line and takes screenshots (tours per screen). |
| `addons/` | gdUnit4 6.2.3, Dialogue Manager 4.2.0. |

## Running

Press F5 in the editor (or run the project). The game boots to a splash screen, then the title
menu: Resume, New Game, Load Game, Settings, Quit. A new game starts at home in Fernmoor Town; walk
out to meet the professor and pick a starter. Arrow keys / WASD move, Shift runs, Z / Enter talks and
confirms, C / Tab opens the menu (Party, Bag, Codex, Achievements, Save, Settings, Quit to title, Close). The **Codex** lists every species with a seen or caught mark (an unseen species is `???`) and opens a page per species with its description and where to find it; **Achievements** lists them with progress and unlock dates (hidden ones read `???` until earned). The Bag shows an item summary pane (icon, count, price, description, effect and whether it can be used now) for the focused item. Party shows each creature's Summary (stats and passives, with a **Use …** option that switches the active one; moves; training), lets you reorder the team and, outside unsafe areas, reach the creature box; storage boxes in buildings do the same. Press **F1** on any screen (debug
builds only) for the debug tools: **Get test party**, **Heal party**, **Give XP**, **Set Affinity** (also unlocks the Affinity passive), **Set passive** (any passive in either slot, except the debug test pack's `tp_` ones), **Collection...** (mark species seen or caught, add to counters, unlock or reset achievements), **Fill box**, **Unlock a box**, **UI gallery...**, **Logs...**, and test battles (wild Route 1,
Scout Ana 1v1, Rival 2v2, and a **Custom battle** team builder: both sides up to `party_size` creatures, each with its own species, level, moves, held item and passive, a bag editor, and any format up to 3v3 such as 1v3 or 3v1; these are exhibitions, so nothing in them is saved). Player data lives in Godot's user folder
(`%APPDATA%/Godot/app_userdata/Monster Catching Game/` on Windows):

- `saves/<playthrough>/autosave.json` and `save_<timestamp>.json`, plus `saves/last.json` (the Resume target)
- `settings.json`
- `logs/session_<date>_<time>.log` (the newest 10 play sessions) and `logging.cfg` (log levels). F1 → **Logs...**
  shows recent records and changes levels live; see [documentation/logging.md](documentation/logging.md).

## Adding content

Drop entries into any `.json` file under a category folder, e.g. `data/moves/my_new_moves.json`:

```json
{ "schema": 1, "entries": [ { "id": "my_move", ... } ] }
```

Every field is checked against `core/data/schemas.gd`. New effect behaviors are added as an `op`
in `DataSchemas.EFFECT_OPS` (and as a handler in the battle engine). When you add an op, also give it a
readable description in `EffectText.effect()` in `core/data/effect_text.gd`.

A few categories need one more step: after changing which encounter tables a map uses, regenerate the where-to-find data with
`godot --headless --path . res://tools/build_locations.tscn` (the check tells you when it is stale); every shipped creature needs a
unique `dex` and a `description`. The [developer guide](documentation/developer-guide.md) has a recipe for each kind of change.

How an AI opponent plays is content too: `data/ai_styles.json` holds weight profiles (`basic`, `aggressive`, `tactician`, `passive`, `defensive`, `trickster`), and a tamer picks one with its `ai` field (`basic` when omitted).

After changing content, regenerate the compendium (`scripts/check.sh` does this too):

```bash
godot --headless --path . --script res://tools/generate_compendium.gd
```

## Checks

```bash
bash scripts/check.sh
```

This runs the data validator, compiles every dialogue file, checks every map (and that `data/locations.json` matches them), runs
the unit tests and regenerates the compendium; it must end with `All checks passed.` Run it from Git Bash on Windows. Set `GODOT` to
your Godot **console** executable if it is not where the script expects. To run the checks one at a time:

```bash
godot --headless --path . --script res://tools/validate_data.gd
godot --headless --path . --script res://tools/check_dialogue.gd
godot --headless --path . res://tools/check_maps.tscn
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests --ignoreHeadlessMode -c
```

## Notes

- `data_testpack/` is a debug-only test content pack (`tp_` ids) loaded on top of `data/` in debug builds, the F1 team builder and `tools/simulate.gd`; it never reaches saves or release builds. See "Test content pack" in [documentation/battle-engine.md](documentation/battle-engine.md) (including how to remove it).

- Dialogue Manager 4 syntax: mutations use `$>` (`do`/`set` are deprecated), and response conditions are
  self-closing: `- Text [if cond /]`.
- The .NET build of the Godot editor shows ".NET Sdk not found" at startup unless the .NET 8 SDK is installed.
  The project is GDScript-only, so this is harmless. The standard (non-.NET) Godot 4.7 build avoids it.
