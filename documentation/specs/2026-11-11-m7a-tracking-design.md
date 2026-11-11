# M7a Tracking — Design

Date: 2026-11-11
Status: Implemented
Parent: [M7 Collection and achievements](2026-11-11-m7-collection-achievements-design.md), sub-project 7a.

## Goal
Record which creature species the player has seen and caught (the **Codex** data) and keep lifetime
counters, so 7b (Codex screens) and 7c (achievements) have something to read. No screens in this piece.

**Success:** seen and caught state is right for every way a creature appears or joins; the eight counters
move at the right moments and only then; old saves load with the Codex backfilled; `bash scripts/check.sh`
ends "All checks passed."

## Decisions
| Topic | Decision |
|---|---|
| Name | Codex (class `Codex`, save field `codex`) |
| Seen | A foe species counts as seen once one of its creatures has been fielded in a battle (`Battler.participated`, which `BattleEngine.place` already sets) |
| Caught | Every way a creature joins: capture, starter or gift, evolution (the new species); old saves are backfilled from the party and boxes. Caught implies seen |
| Counter store | The existing `story.counters` (`StoryState.add_count` / `count`), under reserved ids, so dialogue can read them (`Story.count("battles_won")`) |
| Exhibitions | Track nothing (they already save nothing) |
| Old saves | Codex backfilled on load; counters start at 0 |

## Codex (`core/progress/codex.gd`, `class_name Codex`, static)
- `save.codex`: species id → `{"seen": bool, "caught": bool}`. Entries are only created when a species is seen
  or caught; absence means unseen.
- `mark_seen(save, species)`: sets `seen`. `mark_caught(save, species)`: sets `seen` and `caught`. Both return
  true when the entry changed (so callers can tell a first sighting).
- `status(save, species) -> "unseen" | "seen" | "caught"`, `seen(save, species)`, `caught(save, species)`.
- `seen_count(save)` and `caught_count(save)` count entries; `backfill(save)` marks every creature in the party
  and every box as caught.

## Counters (`core/progress/counters.gd`, `class_name Counters`, static)
`BUILT_IN` (reserved ids, tested to be unique and non-empty):

| id | Moves when |
|---|---|
| `battles_fought` | a battle ends with a result and wasn't fled |
| `battles_won` | outcome is won or captured |
| `tamers_defeated` | a tamer battle is won |
| `creatures_caught` | a creature is captured, or given by `Story.give_creature` |
| `creatures_evolved` | a creature grows into a new species |
| `items_used` | an item is used in battle or from the bag |
| `money_earned` | money is gained from a battle reward or `Story.give_money` (shop sales don't count) |
| `steps` | the player walks one tile |

`Counters.add(save, id, n := 1) -> bool` (logs an error and returns false for an id not in `BUILT_IN`) and
`Counters.value(save, id) -> int` wrap `save.story.add_count` / `count` (`value`, not `get`, which would clash
with `Object.get`).

## Hooks
- **`BattleLauncher.apply_results`:** after `engine.commit`, every foe battler with `participated` is marked seen; each captured creature is marked caught and `creatures_caught` bumped; then the
  battle counters (`battles_fought` unless fled, `battles_won`, `tamers_defeated`); `money_earned` for a tamer
  reward; `items_used` by the positive per-item difference between the bag before and after.
- **`Story.give_creature`:** marks the species caught and bumps `creatures_caught`. `Story.give_money` bumps
  `money_earned`.
- **`grow_screen.gd`** (the only caller of `Progression.apply_growth`): marks the new species caught and bumps
  `creatures_evolved` after a successful growth.
- **`FieldItems.use`:** bumps `items_used` on success.
- **`player.gd`:** accumulates distance moved and bumps `steps` once per tile (not saved; resets on load).
- **Load:** `GameState.load_from` runs `Codex.backfill` after migration so an old save is never empty.

## Save
`SaveGame.SCHEMA` 6 → 7: new `codex` dictionary written by `to_dict` and read by `from_dict` (missing = empty).
`SaveStore._v6_to_v7` sets `codex` to `{}` and the schema; the backfill itself runs in `GameState.load_from`
because core migrations can't see the database (same pattern as the earlier passive backfill).

## Debug
No F1 page in 7a (the Collection page arrives with 7c). Tours are not needed: no screens change.

## Tests
- `Codex`: seen/caught transitions, `caught` implies `seen`, counts, `backfill`.
- `Counters`: unknown id rejected, `add`/`get`, ids unique.
- Migration 6 → 7: an old save loads, `codex` starts empty, and `GameState.load_from` backfills the party and
  boxes (including a creature in a high box slot).
- Hooks: `apply_results` for a won tamer battle, a won wild battle, a capture, a flee, and a loss (counter
  values and Codex marks); a bench foe that was never fielded stays unseen; `give_creature`; `give_money`;
  `grow_screen` growth; `FieldItems.use`; steps (one per tile, none for partial movement); an exhibition
  changes nothing.
- Existing suites stay green; saves from schema 6 still load.

## Out of scope
Screens (7b, 7c), achievements, per-sighting location tracking, backfilling counters, and step counting
while a cutscene moves the player.
