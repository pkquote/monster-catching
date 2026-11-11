# Achievements

Reference for M7c. Design: `specs/2026-11-11-m7c-achievements-design.md`. The data they read (the Codex and the
lifetime counters) is in `tracking.md`.

## Data: `data/achievements/*.json`
A "folder" category. Each entry is `{id, name, description, hidden?, criterion}`, with one criterion:

| Kind | Fields | Met when | Watch key |
|---|---|---|---|
| `counter` | `stat` (one of `Counters.BUILT_IN`), `target` | the counter reaches `target` | `counter:<stat>` |
| `codex` | `mode` `seen`/`caught` with `target`, or `mode` `species` with `species` | enough species seen or caught (only species in the Codex list count), or that species is caught | `codex` |
| `flag` | `flag` | the story flag is set | `flag:<flag>` |
| `creature` | `what` `level`/`bond`/`evolved`, `target` | the highest level or Bond among owned creatures (party and boxes) reaches `target`, or that many creatures have evolved | `creature` (and `counter:creatures_evolved` for `evolved`) |

A `hidden: true` achievement shows only `???` until it is earned. Ids starting `tp_` are test content: evaluated, never
listed. The validator checks the kind, the fields per kind (`DataSchemas.CRITERIA`), that a counter's `stat` is built in,
that a named species exists, that targets are at least 1, and that a `codex` target is not above the species count.
A story flag is a free-form id and is not cross-checked.

## How an unlock happens
1. **Push.** Whatever changes a counter (`Counters.add`), the Codex (`mark_seen`/`mark_caught`), a story flag
   (`StoryState.set_flag`) or a creature (`Bond.change`, a level-up in `Progression.award_xp`, `GrowScreen.record_growth`,
   `BattleLauncher.add_to_party`, and `BattleLauncher.apply_results` after the battle copies are written back, since levels and
   Bond gained in battle reach the save only then) pushes a key into `AchievementWatch`, only when something actually changed.
2. **Drain.** The `AchievementService` autoload drains the set once per frame. An idle frame costs one empty check; many
   pushes in a frame cost one pass.
3. **Index.** `Achievements.watch_index(db)` maps each key to the achievements that watch it, so only those are looked at.
   Unlocked ones are skipped before they are checked. A step therefore costs one integer compare.
4. **Check.** `Achievements.check(db, save, ids)` returns the locked ones now met (`Criterion.progress`).
5. **Unlock.** `AchievementService.unlock(id)` writes `save.achievements[id]` (Unix seconds), logs it and emits
   `unlocked(id)`. Nothing subscribes yet: a toast or a Steam bridge connects to that signal.

When a game loads (or starts) the service pushes `AchievementWatch.ALL`, a full pass, so a save that already earned
something unlocks it on load. `AchievementService.checks` counts achievements checked (a diagnostic the tests use).

## The screen
Menu → **Achievements** (`game/progress/achievements_screen.gd`): a list with `Name ✓` (unlocked), `Name 7 / 10`
(progress) or `???` (hidden and locked); the left pane (`AchievementPreview`) shows the icon, name, description and
"Unlocked <date>" or "Progress 7 / 10". `AchievementIconSlot` draws a placeholder per kind (real art is M8).

## Adding an achievement
Add an entry to `data/achievements/achievements.json` (or a new file in that folder), then `bash scripts/check.sh`.
Nothing else is needed for an existing kind. A `codex` `caught` target above the species count is rejected.

## Adding a criterion kind
1. A `Criterion` subclass in `core/achievements/criteria/` (`watches`, `progress`, `problem`).
2. One line in `Criteria.KINDS` (a `preload` of the script).
3. An entry in `DataSchemas.CRITERIA` with its fields.
4. A push (`AchievementWatch.push(key)`) wherever the thing it reads changes, with a **narrow** key. Do not reuse
   `creature` or `codex` for something that changes every frame: anything that changes often needs its own key, so the
   achievements that watch it are the only ones checked.
5. An icon letter and colour in `AchievementIconSlot`, and a sentence in `CompendiumBuilder._criterion_text`.

## Debug
F1 → **Collection...** (`DebugCollectionPage`): mark a species seen or caught, add to a counter, unlock or reset one
achievement, reset all. Each goes through the real tracking and the service.
