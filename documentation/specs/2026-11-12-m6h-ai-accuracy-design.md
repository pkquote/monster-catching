# M6h AI accuracy pass: design

Status: Implemented, 2026-11-12. Part of M6 (engine backlog) in the [roadmap](2026-11-05-roadmap-m5-m8.md); the follow-on to
[M6e](2026-11-12-m6e-ai-trigger-modelling-design.md), [M6f](2026-11-12-m6f-ai-swapping-design.md) and
[M6g](2026-11-12-m6g-ai-styles-design.md). The four items come from the AI-accuracy group of
`.superpowers/2026-11-12-minors-and-docs-audit.md`; the user chose all four.

## 1. Goal and context

The AI's numbers drift from what a battle actually does in four places. None is a crash; each biases a choice:

| # | Gap | Evidence |
|---|---|---|
| 1 | The knockout bonus is a flat 30, while everything else scales with `ref` (the creature's best single-target damage) | Mean `ref` on the shipped species is 21 at level 10, 59 at 40 and 97 at 70, so 30 is worth 1.4 best hits at level 10, 0.5 at level 40 and 0.3 at level 70. The AI's taste for finishing blows fades as creatures level |
| 2 | A benched creature's own passive, held item and ally auras are missing from `threat(c)` and `best_damage(c)` (`PassiveRules` ignores inactive creatures) | Every matchup term leans against swapping; an absorber on the bench is never seen as the counter. Flagged by the M6f review |
| 3 | `threat(x)` assumes every foe hits `x` | In 2v2 and 3v3 a single-target move hits one of several creatures, so the damage both `b` and `c` are charged is inflated and "doomed" is over-flagged |
| 4 | The tactician's hit-trigger retaliation has its own code, separate from the M6e trigger valuator | Two models of the same thing; the older one covers three ops and only effects that land on the attacker |

Goal: an AI whose knockout, swap and retaliation decisions hold at every level and in every format, verified by the
simulator. Not a goal: new styles, new actions, changes to move scoring other than these four.

## 2. Decisions

| Topic | Decision |
|---|---|
| Scope | All four items (user's choice, 2026-11-12) |
| Order | Retaliation fold first (a refactor, proven against the simulator), then KO scaling, bench passives, expected threat, each measured against the previous state |
| Scale of the knockout bonus | `KO_FACTOR` x `ref`, with `KO_FACTOR` 1.4 (today's level-10 average, so level-10 play changes least). `KO_BONUS` is removed; helper `ko_bonus(ref)` |
| Bench passives | Evaluate a swap with the bench creature **temporarily in the leaver's slot**, then restore. No RNG draw, no event, no change left behind |
| Threat | Expected damage: a single-target foe move counts `1 / n` (n = our active creatures), `two_enemies` counts `min(2, n) / n`, spread moves count in full |
| Retaliation | The tactician's retaliation cost is `-` the sum of `trigger_value` over the target's `hit` triggers (landing on the attacker). The same chance, `when`, contact and spent-item rules |
| Tuning | `KO_FACTOR` and the share rule are the only new numbers; both are constants |
| Randomness | None. Scoring never draws from `engine.rng` |

## 3. The changes

### 3.1 Knockout bonus
`ko_bonus(ref) -> float` returns `KO_FACTOR * ref`. It replaces `KO_BONUS` in `score` (the finishing-move term, times the
style's `ko` weight) and in `swap_score` (the doomed-lead term). Tests that read `BattleAI.KO_BONUS` use `ko_bonus(ref)`.

### 3.2 Evaluating a swap in place
`BattleAI._with_swapped_in(engine, b, c, f: Callable)` puts `c` into `b`'s slot (`b.active` false, `c.active` true),
calls `f`, puts `b` back, and returns `f`'s result. `swap_score` computes `threat(c)`, `best_damage(c)` and
`enter_value(c)` inside it, so `c`'s passive, held item and the allies' auras all apply, exactly as they would after the
swap. `threat(b)` and `best_damage(b)` are computed outside it. Stat stages of `c` are whatever it carries (zero after
a swap-out). Field states already applied to a benched creature, so they are unchanged.

### 3.3 Expected threat
`threat(x)` becomes: for each foe, the best over its usable damaging moves of `estimate_damage x share(move)`, summed,
where `share` is 1 for a spread move (`all_enemies`, `all`), `min(2, n) / n` for `two_enemies` and `1 / n` for the rest,
and n is the number of creatures on `x`'s side (at least 1). A 1v1 battle is unchanged.

### 3.4 Retaliation through the valuator
`_retaliation(engine, b, m, t, ref, style)` loops over `_triggers(engine, t, "hit")`, skips a contact trigger when the move
is not physical, and sums `-trigger_value(engine, b, t, trig, b, ref, style)`. Differences from today, accepted: effects
that land on someone other than the attacker now count (a foe's self-heal on hit is a cost), more ops are priced
(heal, energy, field states), and the style's `trigger_setup` weight applies. For `chill_skin` and the held item that lowers the
attacker's stats the numbers are unchanged. (Corrected after the review: the second shipped hit-trigger item, Oran Berry,
heals its holder, so the old code ignored it and the new code prices it. Hit triggers fire after the damage, so they
are priced at the HP the target is left with, and a consumed or `per_battle` item is charged once per move, not per hit.)

## 4. Not changed
Move scoring, the profile weights and rows, the swap margin, `enter_value`'s own logic, the engine, data and schema.

## 5. Tests
New `tests/battle/test_ai_accuracy.gd`, plus edits to the tests that read `KO_BONUS`:
1. **KO scaling:** a finishing move's bonus is `1.4 x ref` and doubles when `ref` doubles; the doomed-swap bonus likewise; a
   non-finishing move gets none; `KO_BONUS` no longer exists.
2. **Bench passives:** a bench creature with an `absorb_type` passive against a foe whose best move is that type has
   `threat(c)` of 0 in `swap_score` (and a swap that the passive-blind score refused is now chosen); a bench creature with
   a `stat_mod` passive raises `best_damage(c)`'s term; an active ally's aura applies to `c`; after `swap_score` the
   slots, `active` flags and `rng.state` are exactly as before.
3. **Expected threat:** in 2v2 a single-target foe move counts half, a spread move full, `two_enemies` fully at n = 2
   and 2/3 at n = 3; 1v1 is unchanged.
4. **Retaliation:** every existing retaliation test passes unedited (`test_ai_passives.gd`); a foe's self-heal on hit is now
   a cost; a contact trigger is ignored for a non-physical move; a spent `per_battle` item costs nothing; `when` is honoured.
5. **Invariants:** no scoring call changes `rng.state`; `basic` unchanged.

Verification with `tools/simulate.gd` (2v2, 200 battles, seed 1, both orders, levels 10 and 40): after the retaliation
fold the output on `--pack=0` is identical to the baseline; after each later item the side win rates, draw rate,
average rounds and the tactician's swaps per battle are recorded. The M6g targets must still hold: `passive` at most 40%
against the tactician, `defensive` and `trickster` each between 35% and 65%, no style drawing more than 2%. A target
missed because of a change here is tuned by `KO_FACTOR` and reported.

## 6. Documentation
"AI styles" and "Passives and the AI" in `documentation/battle-engine.md` (the knockout bonus, the in-place evaluation
replacing the benched-creature caveat, expected threat, retaliation through the valuator); the Testing table; the HANDOFF
and the audit file record the piece.

## 7. Risks
- **Behaviour drift.** Items 1 to 3 change choices on purpose. The simulator comparison per item, and the M6g targets, are the guard.
- **State mutation in scoring.** Item 2 touches engine state temporarily. The helper restores it and a test checks every
  slot, flag and `rng.state` afterwards; there are no early returns inside it.
- **KO_FACTOR calibration.** 1.4 matches the level-10 average only; per creature the bonus changes in both directions.
  It is one constant to tune.
- **Pessimism removed.** Expected threat flags "doomed" less often; a creature a foe could knock out in the worst case but
  is unlikely to is swapped less. Noted, not mitigated.
