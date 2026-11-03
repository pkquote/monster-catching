# Monster Catching Game

A top-down monster-catching RPG in Godot 4.7 (typed GDScript). Its signature mechanics are
field states with combo reactions, behavior-shaped growth, and N-vs-M battles with Underdog compensation.

Design spec: [documentation/specs/2026-11-03-monster-rpg-design.md](documentation/specs/2026-11-03-monster-rpg-design.md)

Content reference (every creature, move, item, status, field state, reaction, tamer and encounter):
[documentation/compendium.md](documentation/compendium.md). It is generated from `data/`, so don't edit it by hand.

Battle engine reference (API, round order, formulas, events, AI):
[documentation/battle-engine.md](documentation/battle-engine.md)

## Layout

| Folder | Contents |
|---|---|
| `core/data/` | JSON loader, schemas, validator, typed definitions. |
| `core/progress/` | Creature instances, stat/XP formulas, Affinity and growth. |
| `core/battle/` | Headless battle engine, effect ops, AI. |
| `core/` | All of `core/` is pure game logic. It never touches nodes, scenes, or autoloads. |
| `core/save/`, `core/settings/` | Save format and file store; settings model and input bindings. |
| `game/` | Scenes and autoloads that present `core/`: splash, menus, placeholder world, `SceneRouter`, `GameState`, `Settings`. |
| `data/` | All content as JSON (creatures, moves, items, tamers, encounters, ...). |
| `dialogue/` | Dialogue Manager `.dialogue` files for conversations and cutscenes. |
| `tests/` | gdUnit4 suites. |
| `tools/` | Headless scripts: data validator, dialogue checker, compendium generator, battle simulator. |
| `addons/` | gdUnit4 6.2.3, Dialogue Manager 4.2.0. |

## Running

Press F5 in the editor (or run the project). The game boots to a splash screen, then the title
menu: Resume, New Game, Load Game, Settings, Quit. Player data lives in Godot's user folder
(`%APPDATA%/Godot/app_userdata/Monster Catching Game/` on Windows):

- `saves/<playthrough>/autosave.json` and `save_<timestamp>.json`, plus `saves/last.json` (the Resume target)
- `settings.json`

## Adding content

Drop entries into any `.json` file under a category folder, e.g. `data/moves/my_new_moves.json`:

```json
{ "schema": 1, "entries": [ { "id": "my_move", ... } ] }
```

Every field is checked against `core/data/schemas.gd`. New effect behaviors are added as an `op`
in `DataSchemas.EFFECT_OPS` (and as a handler in the battle engine). When you add an op, also give it a
readable description in `tools/generate_compendium.gd` (`_effect()`).

After changing content, regenerate the compendium (`scripts/check.sh` does this too):

```bash
godot --headless --path . --script res://tools/generate_compendium.gd
```

## Checks

```bash
bash scripts/check.sh
```

This runs the data validator, compiles every dialogue file, and runs the unit tests. Set `GODOT` if your Godot
executable lives somewhere else. To run the checks one at a time:

```bash
godot --headless --path . --script res://tools/validate_data.gd
godot --headless --path . --script res://tools/check_dialogue.gd
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests --ignoreHeadlessMode -c
```

## Notes

- Dialogue Manager 4 syntax: mutations use `$>` (`do`/`set` are deprecated), and response conditions are
  self-closing: `- Text [if cond /]`.
- The .NET build of the Godot editor shows ".NET Sdk not found" at startup unless the .NET 8 SDK is installed.
  The project is GDScript-only, so this is harmless. The standard (non-.NET) Godot 4.7 build avoids it.
