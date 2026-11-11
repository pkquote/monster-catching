# Codex and lifetime counters

Reference for M7a. Design: `specs/2026-11-11-m7a-tracking-design.md`.

## Codex (`core/progress/codex.gd`)
`SaveGame.codex` maps a species id to `{"seen": bool, "caught": bool}`. A species with no entry is unseen;
caught implies seen. `Codex` is static: `mark_seen`, `mark_caught` (both return true when the record changed),
`status` (`"unseen"|"seen"|"caught"`), `seen`, `caught`, `seen_count`, `caught_count`, and `backfill`
(marks every creature in the party and boxes caught; `GameState.load_from` runs it after every load, which
fills old saves).

## Counters (`core/progress/counters.gd`)
Lifetime counters live in `SaveGame.story.counters` under reserved ids, so dialogue can read them
(`Story.count("battles_won")`). `Counters.add(save, id, n := 1)` returns false and logs an error for an id
that is not in `Counters.BUILT_IN`; `Counters.value(save, id)` reads one.

| id | Moves when | Hook |
|---|---|---|
| `battles_fought` | a battle ends with a result and wasn't fled | `BattleLauncher.apply_results` |
| `battles_won` | outcome is won or captured | `apply_results` |
| `tamers_defeated` | a tamer battle is won | `apply_results` |
| `creatures_caught` | a creature is captured or given | `apply_results`, `Story.give_creature` |
| `creatures_evolved` | a creature grows into a new species | `GrowScreen.record_growth` |
| `items_used` | an item is used in battle or from the bag | `apply_results` (bag before vs after), `FieldItems.use` |
| `money_earned` | money gained from a tamer reward or `Story.give_money` (shop sales don't count) | `apply_results`, `Story.give_money` |
| `steps` | the player walks one tile | `Player.step` |

## Where things are marked
- **Seen:** every foe battler with `participated` (it was on the field) in `apply_results`.
- **Caught:** `BattleLauncher.add_to_party` (every creature that joins: captures, starters, gifts, debug grants),
  `GrowScreen.record_growth` (the new species), and the load backfill.
- Scripts can't move the reserved counters: `Story.add_count` refuses ids in `Counters.BUILT_IN`.
- Exhibition battles never call `apply_results`, so they track nothing.
- The hooks that need a loaded game (`GrowScreen`, `Player`) do nothing without one.

## Achievement watch pushes (M7c)
`Counters.add`, `Codex.mark_seen`/`mark_caught` and `StoryState.set_flag` each push a key into `AchievementWatch` when
they change something (`counter:<id>`, `codex`, `flag:<id>`), so the achievements that read them are re-checked. See
`achievements.md`.

## Adding a counter
Add its id to `Counters.BUILT_IN`, call `Counters.add` where the thing happens, and add a test for the hook.
