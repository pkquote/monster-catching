# One field state per side (M5b side change)

Status: Implemented.

## Goal
Each side holds one field state by default. The player removes it by firing a reaction that
consumes it, or by applying a different state over it. Fewer chips also frees the bottom-right of the
battle stage, so the "Your field" view goes back there.

## Decisions
- `balance.max_field_states` stays (schema, `BalanceDef`, docs) so a higher cap remains a tuning
  option. `data/balance.json` changes from 3 to 1.
- Overwriting is unconditional: any non-reacting different state replaces the current one, including a
  state a teammate just set up. It is the player's choice.
- Re-applying the same state still adds stacks (up to `max_stacks`) and refreshes its duration.
- Applies to every side: player, foes, wild creatures, tamers.

## Rules (`core/battle/field_rules.gd`, `core/battle/field.gd`)
- Reaction check is unchanged: if the incoming state reacts with a state already present, the
  reaction fires first. The incoming state lands unless the reaction consumed it; existing states
  are removed only if the reaction consumed them.
- If the incoming state is not on the side and the side is at `max_field_states`, the oldest state is
  removed with `field_removed` reason `replaced` (was `pushed_out`) before the new one lands.
- Validator: every reaction must consume at least one of its two inputs (otherwise a one-slot side
  would hold two states). Checked in `core/data/validator.gd`, with the test pack and fixtures
  updated if any reaction fails it. Shipped reactions all pass.
- Battle log text (`game/battle/battle_text.gd`): `replaced` reads "The <state> on <side> was
  replaced."

## AI (`core/battle/ai/battle_ai.gd`)
`_setup_value` gets a case for a non-reacting state applied to a side already at the cap:
- Replacing a helpful state on the AI's own side costs value; replacing a harmful one gains value.
- Replacing the enemy's harmful state costs value; replacing a helpful one gains value
  (using `state_benefit`, scaled like the existing `NEW_STATE` / `OWN_BUFF` constants).
- `_best_follow_up` considers only the states actually present.
Documented under "Passives and the AI" / AI section of `documentation/battle-engine.md`.

## UI (`game/battle/field_view.gd`, `battle_scene.gd`)
- Foe's view stays top-left. Yours returns to the bottom-right edge of the stage, growing leftwards.
- The effect label sits above the chip for your side (so it cannot run off the stage) and below it for
  the foe's. `field_column` in the battle scene is removed.
- Extra states (cap > 1) still render, left to right.
- Checked in the real window with the battle tour (1v1, 3v1, crowded 3v3): no overlap with
  creatures, labels or the command panel.

## Docs
`documentation/battle-engine.md` (Field states section, `field_removed` reasons, AI notes), the
main design spec's field-state line, the compendium text (it prints the cap), and `.superpowers/HANDOFF.md`.

## Tests
- Update tests that assume several states on a side (`test_field_reactions`, `test_testpack_mechanics`,
  `test_ai`, `test_field_view`, fixtures that set the cap).
- New: replace removes the old state and emits `replaced`; reaction leaving one state
  (soaked + charged keeps soaked); reaction leaving none (steam); same-state restack; cap 2 still
  holds two (guards the tuning option); validator rejects a reaction consuming neither input; AI
  overwrite cases; FieldView single chip with bottom-right placement and label above/below.
- Run the pack simulations and `bash scripts/check.sh` (a cap of 1 shifts balance); no commits.

## Out of scope
Rebalancing moves or reactions, new UI for inspecting field states, per-side caps.
