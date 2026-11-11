# M7c Achievements — Design

Date: 2026-11-11
Status: Implemented, with amendments (plan: [documentation/plans/2026-11-11-m7c-achievements.md](../plans/2026-11-11-m7c-achievements.md)).

**Amendments made in the plan and implementation** (the text below is the original design):
- No "next unmet target" cache: the key index already limits a step to the achievements that watch `counter:steps`, and unlocked ones are skipped before they are checked. `AchievementService.checks` is a diagnostic the tests pin.
- `AchievementWatch.push` always records (core cannot see `GameState`); the service drops keys when no game is loaded.
- A full pass is the key `AchievementWatch.ALL` (`"*"`), pushed when `GameState.current` changes and after a debug reset.
- `creature` keys are pushed from `Bond.change`, `Progression.award_xp`, `GrowScreen.record_growth` and `BattleLauncher.add_to_party`, and `apply_results` once after `engine.commit(0)` (found in review: battle levels and Bond live on battle copies until then).
- `close_friends` is Bond 80; the hidden achievement is the `quick_draw_won` flag, "Quick on the Draw".
- `AchievementService.unlock(id)` is public, so the debug page unlocks through the service.
Parent: [M7 Collection and achievements](2026-11-11-m7-collection-achievements-design.md), sub-project 7c.
Builds on [7a Tracking](2026-11-11-m7a-tracking-design.md) (the Codex and the lifetime counters) and
[7b Codex screens](2026-11-11-m7b-codex-screens-design.md) (the `ProgressScreen` list-and-preview pattern).

## Goal
Add achievements: a data entry per achievement, a small class per kind of criterion, an evaluator that reacts to
tracked changes without costing frames, a pause-menu screen, and placeholder icons. The core records unlocks and
announces them with a signal; nothing draws a toast yet. No gameplay changes, no rewards.

**Success:** adding an achievement of an existing kind needs only JSON; adding a kind needs one class, one schema
entry and one registry line; a battle, a catch or a step can unlock an achievement in play; a step with no target
reached does no evaluation; `bash scripts/check.sh` ends "All checks passed."

## Decisions
| Topic | Decision |
|---|---|
| Evaluation | Event-driven: every tracked change pushes a watch key; a service drains the keys once per frame and evaluates only the locked achievements that watch them |
| Hot path | A counter achievement keeps the next unmet target, so a step costs one integer compare |
| Starter content | One achievement per criterion kind plus a hidden one (11 entries); the real list is M9 |
| Presentation | The service emits `unlocked(id)`; nothing subscribes yet. Ids are stable strings for a later platform bridge |
| Rewards | None. An optional `reward` field can be added later without changing the data shape |
| Hidden | `hidden: true`: while locked it shows `???`, with no name, description or progress |
| Test content | Test-pack achievements use `tp_` ids and are not listed on the screen |

## Data
- **Category `achievements`**, a folder category: `data/achievements/*.json`. Entry:
  `{id, name, description, hidden?, criterion: {kind, ...}}`. One criterion per entry. `AchievementDef` in
  `core/data/defs/`, built by `Database._builders()`.
- **Criteria kinds** (`core/achievements/criteria/`, one class each, registered in one place like `EffectOps`;
  each has a schema block in `schemas.gd`):

  | Kind | Fields | Met when | Watch key |
  |---|---|---|---|
  | `counter` | `stat`, `target` | `Counters.value(stat) >= target`; `stat` is in `Counters.BUILT_IN` | `counter:<stat>` |
  | `codex` | `mode` (`seen`, `caught`, `species`), `target` or `species` | the Codex count reaches the target, or that species is caught | `codex` |
  | `flag` | `flag` | the story flag is set | `flag:<id>` |
  | `creature` | `what` (`level`, `bond`, `evolved`), `target` | the highest level or Bond among owned creatures (party and boxes) reaches the target; `evolved` reads `creatures_evolved` | `creature`, or `counter:creatures_evolved` |

  Each class gives `watches(def) -> Array[String]`, `progress(db, save, def) -> {current, target}`, and its icon kind.
- **Validator:** known kind; `stat` in `Counters.BUILT_IN`; a named species exists; targets at least 1; a `codex`
  target not above the species count; unique ids; `hidden` a bool. A flag achievement names a free-form flag id
  (flags are not declared anywhere), so it is not cross-checked.
- **Save:** `SaveGame.achievements`, a dictionary of id to unlock time (Unix seconds); schema 8. The migration starts it
  empty. The full pass on load unlocks anything an old save already earned, stamped with the time of that load.
- **Starter set:** `first_steps` (500 steps), `first_victory` (1 battle won), `tamer_trouncer` (1 tamer defeated),
  `first_catch` (1 creature caught), `field_notes` (4 species seen), `collector` (all species caught),
  `first_evolution` (1 creature evolved), `rising_star` (a creature at level 20), `close_friends` (a creature at a
  Bond target the plan reads from the real scale), `big_spender` (1,000 money earned), and one hidden `flag`
  achievement tied to a real story flag the plan picks.

## Evaluation
- **`AchievementWatch`** (`core/achievements/achievement_watch.gd`, static, pure): a set of changed keys.
  `push(key)`, `drain() -> Array`. Pushing a key already in the set costs nothing; with no loaded game nothing is
  pushed.
- **Push points:** `Counters.add` (`counter:<id>`), `Codex.mark_seen` / `mark_caught` (`codex`, only when the record
  changed), `StoryState.set_flag` (`flag:<id>`, only when the value changed), and `creature` from the places a
  level, Bond or party membership changes: `GrowScreen.record_growth`, `BattleLauncher.apply_results` and
  `BattleLauncher.add_to_party`.
- **`Achievements`** (`core/achievements/achievements.gd`, static, pure): `evaluate(db, save, keys) -> Array` returns
  the ids newly met among the locked achievements whose watch keys intersect `keys` (all locked ones when `keys` is
  empty). Test content is evaluated like the rest. A counter achievement is checked first against its target by an
  integer compare.
- **Service** (`game/autoload/achievements_service.gd`, autoload `AchievementService`): each frame it drains the
  watch set; when non-empty it builds the key-to-locked-achievements index (rebuilt when a game loads or an
  achievement unlocks), evaluates the matching ones, writes `save.achievements[id]`, removes the id from the
  index and emits `unlocked(id)`. It runs a full pass when a game loads. Idle frames cost one empty check.
- **Exhibition battles** never reach `apply_results`, so they push nothing.

## Screen
- **Entry:** an **Achievements** row in `PauseMenu`, after Codex.
- **`AchievementsScreen`** (`game/progress/achievements_screen.gd`), a `ProgressScreen`: title bar
  "Unlocked n / N" (counting listed achievements only); a list, one row per achievement in file order,
  `Name ✓` when unlocked or `Name 7 / 10` with progress; a left preview that follows the focused row: a large icon,
  the name, the description, and "Unlocked <date>" or "Progress 7 / 10". A hidden locked row reads `???` in the
  list and the preview. Back returns to the pause menu.
- **`AchievementIconSlot`** (`game/ui/achievement_icon_slot.gd`), like `ItemIconSlot`: a colour and a letter per
  criterion kind; locked entries greyed. Real art is M8.
- Keyboard and gamepad navigation come with `ProgressScreen`; the screen fits 640x360 (`ScreenFit`).

## Debug, docs and tooling
- **F1 "Collection" page:** mark a species seen or caught, set a counter, unlock or reset one achievement, reset all.
  Each action pushes its watch key, so the service reacts as it does in play.
- **Docs:** `documentation/achievements.md` (add an achievement with JSON; add a criterion kind: one class, one
  schema entry, one registry line); the generated compendium gains an Achievements section (hidden entries listed);
  `tracking.md` notes the watch pushes; the handoff and the parent spec's status are updated.
- **Tour** `--mode=achievements`: a new game, earn one in play (a catch or a won battle), open Achievements, check
  the row and the preview, then the hidden entry's `???`.

## Tests
- Each criterion kind: progress, watch keys, the boundary at the target.
- `AchievementWatch`: push, dedup, drain empties, nothing pushed without a loaded game.
- Push points: each hook pushes its key, and only when the value changed.
- `Achievements.evaluate`: only matching locked achievements are checked; a met one is returned once.
- Service: unlock writes the save and emits `unlocked(id)` exactly once; an unlocked id leaves the index; the load
  pass catches up an old save; a step that reaches no target evaluates nothing (counted by a probe).
- Validator rules, the schema 8 migration, a compendium pin.
- Screen: row text, hidden masking, the preview, fit at 640x360 with the longest name and description; the pause
  menu has the row and returns to the menu.
- Existing suites stay green; `bash scripts/check.sh` ends "All checks passed."

## Out of scope
Rewards, an unlock toast, a Steam or other platform bridge, filtering or sorting the list, achievement categories,
and real art (M8).
