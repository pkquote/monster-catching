# Logging

Design background: [logging design](specs/2026-11-04-logging-design.md).

## Where logs go

- **The Godot output panel / terminal**, one line per record:
  `   12.345 INFO  battle    Battle started {"format":"1v1","foes":["pebblet L3"],...}`.
  Warnings and errors also appear in the editor's Debugger → Errors tab.
- **A file per play session:** `user://logs/session_<date>_<time>.log`. The newest 10 sessions are kept.
  On Windows `user://` is `%APPDATA%\Godot\app_userdata\Monster Catching Game\`.
  F1 → Logs... → **Open log folder** opens it. Headless runs (tests, tools) don't write files.
  The same folder also holds Godot's own `godot*.log` files (the engine's file logging); those are
  separate and not rotated by the game.
- **F1 → Logs...:** the newest 300 records, filtered by a minimum level and a category.
- **Engine errors too:** Godot's own errors and script errors (with stack traces) are copied into
  the file and the viewer under the category `engine`.

## Levels

`TRACE` < `DEBUG` < `INFO` < `WARN` < `ERROR` (and `OFF`). Each category has its own minimum; the
`default` level covers the rest. Out of the box: INFO when playing. Headless runs (tests, tools)
always use WARN and ignore `logging.cfg`, so a level saved for play never floods the test output.

| Category | INFO | DEBUG | TRACE |
|---|---|---|---|
| `battle` | battle started (format, party, foes), battle over, results applied | each round's actions | every engine event |
| `save` | saved, loaded, migrated; load failures (WARN) | move-pool backfill | |
| `world` | map changed/loaded, tamer spotted the player, wild encounter | locks taken/released, stepped on / interacted with a piece | |
| `story` | flags set, creatures given, party healed, story battles, dialogue started/ended | items and money, counters, marked done, every Cutscene command | |
| `progress` | level up, move learned, grew (branch and the Affinity behind it), training reset | moves offered/set, trained, storage moves and refusals | |
| `minigame` | started, finished (won, score) | | |
| `ui` | | screens opened and closed | |
| `data`, `settings`, `engine` | content errors; logging started; engine/script errors | | |

**Turn a category up:** F1 → Logs... → pick its level under "Levels" (it applies at once), then
**Save levels** to keep it. The levels are saved to `user://logging.cfg`, which you can also edit:

```
[levels]
default="INFO"
battle="TRACE"
world="DEBUG"
```

## Logging from code

```gdscript
Log.info(Log.WORLD, "Map changed", {"map": map_id, "spawn": spawn_id})
Log.warn(Log.SAVE, "Load failed", {"path": path, "error": err})

# Skip building expensive messages nobody will see:
if Log.enabled(Log.BATTLE, Log.Level.TRACE):
	Log.trace(Log.BATTLE, describe(event), event)
```

- `Log` is a static class (`core/log/log.gd`), usable from `core/`, `game/`, tools and tests.
- Keep the message short and constant ("Map changed"), and put the details in the data dictionary.
  That keeps lines easy to search.
- A new category is just a new string. Add a constant to `Log.CATEGORIES` so the viewer lists it.
- Use `Log.error` / `Log.warn` instead of `push_error` / `push_warning`; they still reach the editor.
- Tests can watch the log: `Log.save_state()`, `Log.clear_sinks()`, `Log.add_sink(callable)`, then
  `Log.restore_state(state)` afterwards (see `tests/log/`).
