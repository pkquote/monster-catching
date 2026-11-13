# M6f AI swapping: design

Status: Implemented, 2026-11-12. Part of M6 (engine backlog) in the
[roadmap](2026-11-05-roadmap-m5-m8.md). Builds on [M6e](2026-11-12-m6e-ai-trigger-modelling-design.md), whose
`BattleAI.enter_value` this piece finally calls. Engine facts are in the
[battle engine reference](../battle-engine.md).

## 1. Goal and context

The AI picks a move or Rest. It never swaps. This piece lets the **tactician** style swap an active creature for a
benched one when the swap is worth more than the best move. `basic` and `aggressive` never swap and score exactly
as before. M6g's `defensive` style will reuse this machinery with its own weights.

Engine facts the design relies on (see the reference): a swap is priority 6, so it resolves before every move; it is
the swapping creature's whole turn (its other slots that round, including Underdog bonus actions, are dropped and the
newcomer does not act); the creature leaving has its stat stages reset, **statuses are not cleared**; the newcomer's
`enter` triggers fire.

## 2. Decisions

| Topic | Decision |
|---|---|
| Styles | Tactician only. `basic` and `aggressive` never swap; a test pins their choices unchanged |
| Reasons | All four: save a doomed creature, better matchup (defence and offence), valuable `enter` triggers, escape bad stat stages or a turn-skipping status |
| Method | A swap is scored like a move, in the same HP-equivalent units, and competes with moves and Rest. The best score wins |
| Stability | A swap must beat the best non-swap option by `SWAP_MARGIN` (a constant), so near-ties stay with the move |
| Randomness | None. Scoring never draws from `engine.rng` |
| Replacement after a faint | Out of scope: the engine fills open slots itself |

## 3. The swap score

For an active creature `b` and a benched creature `c` (alive, not active, same side), `BattleAI.swap_score(engine,
b, c, style, ref) -> float` is the sum of:

| Term | Value |
|---|---|
| Damage avoided | `min(threat(b), hp_b) - min(threat(c), hp_c)`, plus `KO_BONUS` when `threat(b) >= hp_b` and `threat(c) < hp_c`. `threat(x)` is the sum over the foe's active creatures of the best expected damage of each (its usable damaging moves via `estimate_damage`), as if every foe targets `x`; the pessimistic assumption is deliberate |
| Offence | `(best_damage(c) - best_damage(b)) x OFFENCE_ROUNDS` (constant 1, because `c` acts from next round). Negative when `c` hits worse |
| Entry | `enter_value(engine, b, c, style)` (M6e) |
| Escape | the cost `b` carries that the swap removes: for each stage on `b`, `DEBUFF_VALUE[stat] x ref x -stage` (negative stages add; positive stages subtract, because the swap throws a buff away), plus `status_value` of a `skip_chance` status on `b` (the swap replaces a turn `b` may lose). Statuses are not cleared, so only the skip share counts |

`SWAP_MARGIN` (0.25 x `ref`, so it scales with level) and the "every foe targets this creature" threat are first
guesses, tuned with the simulator. A creature placed at battle start counts as having acted.

## 4. Choosing

- `choose` adds one `BattleAction.swap(bid, c.bid)` option per eligible bench creature, scored by `swap_score`,
  only for `tactician`. The best option wins; a swap is picked only if its score exceeds the best non-swap score by
  `SWAP_MARGIN`.
- `choose_all` tracks claimed bench creatures: two actives never swap in the same one. A creature that picks a swap
  takes no further actions that round (Underdog bonus actions repeat a bid, so `choose_all` stops asking that bid).
- A creature that entered the field this round (a swap or faint replacement at the end of the last round) does not
  swap out in the next command phase before it has acted once: the AI's own swap would otherwise ping-pong. `Battler`
  gets one field, `acted: bool` (false on placement, true after the creature runs any action); the AI skips a
  creature whose `acted` is false. This is the only engine-side change.

## 5. Not changed

Data and schema; move scoring and the trigger valuators of M6e; Rest; faint replacement; wild creatures (no bench).
Changes: `core/battle/ai/battle_ai.gd`, the `Battler.acted` flag (set in `place` and the action runner), tests and docs.

## 6. Tests

New `tests/battle/test_ai_swaps.gd`, with fixtures built in the style of `test_ai_triggers.gd`:

1. Damage avoided: a doomed active with a healthy bench creature swaps; with a healthy active it does not; a bench
   creature that is also doomed does not.
2. Offence: a bench creature that hits much harder is preferred; one that hits worse is not.
3. Entry: a bench creature whose `enter` field state is valuable raises the score; a harmful one lowers it.
4. Escape: stat drops on `b` raise the score; a skip-chance status adds its skip share; a non-skip status adds nothing.
5. Margin: a swap that beats the best move by less than `SWAP_MARGIN` is not chosen.
6. Coordination: in 2v2, two doomed actives with one healthy bench creature produce one swap, to the right creature;
   a swapping creature takes no second action.
7. A creature that has not acted since entering is never chosen to swap out; once it has acted it may.
8. Invariants: `basic` and `aggressive` choices equal their pre-M6f choices; no scoring call changes `rng.state`.

The pack suites re-run; changes to their exemption lists are reported. `tools/simulate.gd` runs before and after
(2v2 and 3v3, levels 10 and 40, both style orders) for swap frequency and win-rate outliers.

## 7. Documentation

"Passives and the AI" gains the swap rules and drops "the AI never swaps"; the AI styles table gets the tactician
swap row; the test table gains the new file. The HANDOFF records the piece.

## 8. Risks

- **Over-swapping.** A swap costs a turn. The margin and the same-round rule limit it; the simulator reports swaps
  per battle.
- **Pessimistic threat.** Assuming every foe hits the creature in the slot inflates "doomed" in 2v2. It is one
  assumption to tune or replace (for example, split by number of our actives) if the simulator shows swaps that are
  too eager.
- **Status escape is partial.** Statuses are not cleared by a swap, so the escape term is smaller than the name
  suggests. A cleanse-on-swap rule would be an engine change, not part of this piece.
