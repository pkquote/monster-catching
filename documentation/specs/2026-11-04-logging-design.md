# Logging — Design

Date: 2026-11-04
Status: Approved (plan: [documentation/plans/2026-11-04-logging.md](../plans/2026-11-04-logging.md))

## 1. Goal

Trace what the game is doing so problems can be found after the fact: one call style usable from
`core/`, `game/`, tools and tests; levels per area; output to the console, a file per session, and a
viewer in the F1 debug menu; engine and script errors captured in the same log.

## 2. The `Log` class (`core/log/log.gd`, `class_name Log`)

- Static, not an autoload, so pure `core/` code and `--script` tools can call it.
- `Log.trace/debug/info/warn/error(category: String, message: String, data: Dictionary = {})`.
- Levels: `TRACE` < `DEBUG` < `INFO` < `WARN` < `ERROR`, plus `OFF` (enum `Log.Level`).
- Categories (constants on `Log`): `battle`, `save`, `world`, `story`, `progress`, `ui`, `data`,
  `settings`, `minigame`. Unknown categories are allowed and use the default level.
- `Log.default_level` and `Log.set_level(category, level)` / `Log.level_of(category)`.
- `Log.enabled(category, level) -> bool` so hot paths skip building messages.
- A record is `{ time_ms: int, frame: int, level: Level, category: String, message: String, data: Dictionary }`.
- Sinks: `Log.add_sink(callable)` / `remove_sink`, each called with a record that passed the filter.
  With no sinks, WARN and ERROR still reach Godot (`push_warning` / `push_error`) and nothing else prints.
- `Log.format(record) -> String`: `"   12.345 INFO  battle    message {data}"`.

## 3. Sinks and setup (`game/log/`, autoload `Logging`, first in the autoload list)

- **Console sink:** prints the formatted line; WARN and ERROR go through `push_warning` / `push_error`
  so they show in the editor debugger.
- **File sink:** `user://logs/session_<YYYYMMDD_HHMMSS>.log`; keeps the newest 10 files; writes
  every record, flushing immediately for WARN+ and otherwise at most every 0.5s.
- **Memory sink:** ring buffer of the last 2000 records for the viewer.
- **Engine bridge:** a `Logger` subclass registered with `OS.add_logger` records engine/script errors
  and warnings (with backtraces when Godot provides them) into the file and memory sinks under category
  `engine`. It ignores the game's own output (a re-entrancy guard), so nothing is logged twice or loops.
- **Config:** `user://logging.cfg` (`[levels] default=INFO`, one key per category). Defaults: INFO;
  WARN when running headless (tests, tools), so test output stays clean.
- Startup line: game version, Godot version, OS, log file path.

## 4. Viewer (F1 → "Logs...")

- The newest records first, as formatted lines, filtered by a minimum level and a category ("all").
- Per-category level pickers that change levels live; "Save levels" writes `user://logging.cfg`.
- "Open log folder" (`OS.shell_open` on the logs folder). "Back".

## 5. What gets logged

| Area | INFO | DEBUG / TRACE |
|---|---|---|
| battle | battle start (kind, format, foes), outcome, results applied | round actions (DEBUG), every engine event (TRACE) |
| save | save written / loaded (path, kind), migrations run | backfill details |
| world | map changes (map, spawn) | locks taken/released, triggers, doors, tamer sightings |
| story | start_battle / start_minigame / flags set, dialogue start and end | items/money given or taken, Cutscene commands |
| progress | level-ups, moves learned, growth (branch and why), respec | moves offered/slotted, training, storage moves and refusals |
| ui | — | screens opened and closed |

Existing `push_error` / `push_warning` calls in `game/` and `core/` become `Log.error` / `Log.warn`.
Tools keep `print`.

## 6. Testing

Capture-sink tests: level filtering, per-category levels, `enabled`, format, file rotation (10 kept),
memory ring size, config load/save, the engine bridge and its re-entrancy guard, the viewer's filters;
spot checks that a battle round, a save write, a map change and a level-up produce their records.
