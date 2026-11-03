# Monster Catching Game

A top-down monster-catching RPG in Godot 4.7 (typed GDScript). Its signature mechanics are
field states with combo reactions, behavior-shaped growth, and N-vs-M battles with Underdog compensation.

Design spec: [documentation/specs/2026-11-03-monster-rpg-design.md](documentation/specs/2026-11-03-monster-rpg-design.md)

## Layout

| Folder | Contents |
|---|---|
| `core/` | Pure game logic. Never touches nodes, scenes, or autoloads. |
| `game/` | Scenes and autoloads that present `core/`. |
| `data/` | All content as JSON (creatures, moves, items, tamers, encounters, ...). |
| `dialogue/` | Dialogue Manager `.dialogue` files for conversations and cutscenes. |
| `tests/` | gdUnit4 suites. |
| `tools/` | Headless scripts (data validator, dialogue checker). |
| `addons/` | gdUnit4 6.2.3, Dialogue Manager 4.2.0. |

## Adding content

Drop entries into any `.json` file under a category folder, e.g. `data/moves/my_new_moves.json`:

```json
{ "schema": 1, "entries": [ { "id": "my_move", ... } ] }
```

Every field is checked against `core/data/schemas.gd`. New effect behaviors are added as an `op`
in `DataSchemas.EFFECT_OPS` (and as a handler in the battle engine).

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
