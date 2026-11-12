# M6e AI trigger modelling: design

Status: Draft, 2026-11-12. Part of M6 (engine backlog) in the
[roadmap](2026-11-05-roadmap-m5-m8.md). Builds on "Passives and the AI" and "Held items and the AI" in the
[battle engine reference](../battle-engine.md).

## 1. Goal and context

The battle AI already prices a target's `hit` triggers (the tactician's retaliation estimate). The other five
trigger kinds (`enter`, `knockout`, `faint`, `status`, `round_end`) are documented as deliberately not modelled, so
the AI ignores, for example, that finishing a foe with a `faint` trigger scorches its own side, or that its own
`knockout` trigger would restore energy. This piece teaches the **tactician and aggressive** styles to read all
five, each with its own weighting (section 3a). `basic` stays random.

This is the first of three pieces agreed on 2026-11-12:

| Piece | Scope |
|---|---|
| **M6e (this spec)** | The AI values `knockout`, `faint`, `status`, `round_end` in move scoring, and `enter` as a value function |
| M6f | AI swapping (a new action choice); reads `enter_value` from M6e |
| M6g | New AI styles: `passive` (prefers buffs, heals and Rest), `defensive` (survival, swaps), `trickster` (statuses, debuffs, field setup) |

M6f and M6g get their own brainstorm, spec and plan.

## 2. Decisions

| Topic | Decision |
|---|---|
| Styles | Tactician and aggressive read all five kinds, scored differently (section 3a). `basic` ignores them and scores exactly as before (a test pins this) |
| Currency | Same as the rest of the tactician: HP for damage and healing, multiples of `ref` (its best available damage) for statuses, stat stages, field states and energy, so values scale with level |
| Sign | Every value is from the scoring creature's side: positive helps the AI's side, negative hurts it. A creature's gain counts for its owner |
| Weighting | Each trigger's value is multiplied by its `chance`. A trigger whose `when` fails (checked on the holder) is worth 0. A spent `per_battle` item is ignored, like retaliation |
| `hit` retaliation | Unchanged in this piece (its tests stay as they are). Folding it into the shared valuator is a deferred minor |
| New randomness | None. Scoring never draws from the battle RNG |

## 3. The shared valuator

`BattleAI.trigger_value(engine, b, holder, trig, landing, ref, style) -> float` values one trigger's effect list for the
AI creature `b`: the trigger's effects land on `landing` (the creature the engine would pass as the target:
the holder for `enter`, `round_end`, `knockout` and `status`; the killer for `faint`; an effect's own `target`
overrides it). The value is the sum over effects, times `chance / 100`, signed by `landing.side == b.side`.

Per effect op (value of the effect for the creature it lands on; ops not listed are worth 0):

| Op | Value |
|---|---|
| `damage` | `-min(hp, BattleMath.damage(...))`, as retaliation computes it |
| `heal` | `+min(missing HP, fraction x max HP)` |
| `apply_status` | `-status_value(...)` x the effect's `chance`; 0 if the target already has one or blocks it |
| `stat_stage` | `DEBUFF_VALUE[stat] x ref x stages` (negative stages are costs); 0 for a drop `guard_stages` blocks |
| `restore_energy` | `+ENERGY_VALUE x ref x fraction` (a new constant, 0.25, covering a full bar), limited to missing energy |
| `cure_status` | `+status_value` of the remaining rounds of a matching status, as `_cure_value` does |
| `apply_field_state` | the value `_setup_value` gives a move's field effect, from the AI creature's view. The branch is extracted from `_setup_value` into `_field_state_value(engine, b, source, effect, side_index, ref, for_trigger)` and `_setup_value` calls it with `for_trigger` false, its results unchanged. In a trigger (`for_trigger` true) a hostile state (`state_benefit` below 0) landing on the AI's own side costs `NEW_STATE x ref`, which a move never does, so Ember Trail's scorching of the AI's side is a cost |

## 3a. How the styles weigh a trigger

Aggressive is the damage-and-knockout style: it trusts HP, not setup. So `trigger_value` takes the style and scales
each effect by the currency it is paid in:

| Effect currency | Ops | Tactician | Aggressive |
|---|---|---|---|
| HP (direct) | `damage`, `heal` | x1.0 | x1.0 |
| Setup (`ref`-denominated) | `apply_status`, `stat_stage`, `restore_energy`, `cure_status`, `apply_field_state` | x1.0 | x`AGGRESSIVE_SETUP_MULT` (0.5) |

Both read the same kinds in the same places (section 4); only this table differs. The aggressive style still never
credits a status or stat-drop move itself (it has no setup value), so for it the `status` rule is a cost only (the term is clamped to at most 0): it
avoids putting a status on a foe whose `status` trigger punishes it, but never seeks one out. The multiplier is a
single constant to tune.

## 4. Where each trigger kind enters the score

All of these are added when `style` is `tactician` or `aggressive`, weighted by the table in section 3a.

| Kind | Rule |
|---|---|
| `knockout` | When a move's estimated damage kills the target (the existing knockout test), add the value of the **user's** `knockout` triggers (its passive and held item): Finisher's energy, Cold Snap's +1 Speed |
| `faint` | In the same case, add the value of the **target's** `faint` triggers, landing on the user (the killer). Normally a cost: Ember Trail's field state on the AI's side. Finishing the AI's own ally pays the `faint` term only: the user's `knockout` trigger is credited for a foe, not an ally |
| `status` | For each `apply_status` effect that would land on a foe that has no status and doesn't block it, add the value of that foe's `status` triggers (they land on the foe itself, so they are usually a cost to the AI), weighted by the effect's `chance`. Own-side `status` triggers are not modelled: no move gives an ally a status |
| `round_end` | A trigger that fires whatever the AI does can't separate two moves, so it only adjusts two existing terms. (a) The AI creature's own end-of-round healing (`heal` effects, and self-damage as a negative) is subtracted from the missing HP that its heal urgency uses. (b) A foe's end-of-round healing is subtracted from the damage a non-lethal hit is credited with, to a floor of 0. Knockout checks are unchanged (a round-end heal can't save a foe the move kills) |
| `enter` | Not part of move scoring (the AI never swaps today). `BattleAI.enter_value(engine, b, incoming) -> float` is the value to `b`'s side of `incoming` entering the field, from its `enter` triggers. M6f's swap scoring will call it. It has tests but no caller yet |

Multi-hit moves: the knockout and faint terms are added once (the move finishes the target once); the existing
per-hit retaliation multiplier is untouched.

## 5. Not changed

- Which triggers fire, and the engine itself: this piece is `core/battle/ai/battle_ai.gd` (plus constants), tests
  and docs. No data or schema change.
- `hit` retaliation, absorb, blocks, cure and field-state values (except the extraction in section 3).
- AI action choices: still moves and Rest only.

## 6. Tests

New `tests/battle/test_ai_triggers.gd`, in the style of `test_ai_passives.gd`, with fixture passives and held
items:

1. `knockout`: a tactician (and an aggressive AI) prefers the finishing move when its own `knockout` trigger is valuable; a non-lethal
   move gets no such term; the term scales with `ref`.
2. `faint`: a target whose `faint` trigger scorches the AI's side lowers the finishing move's score; a trigger that
   lands on nobody useful (a `heal` at full HP) costs nothing; an ally's faint trigger is charged on killing it.
3. `status`: a status move into a foe with a punishing `status` trigger scores lower than into a plain foe; a foe
   that blocks the status adds nothing; the `chance` of both the effect and the trigger weights it.
4. `round_end`: with Photosynth-style round-end healing, the AI's heal move is worth less; a foe with it makes a
   non-lethal hit worth less but a lethal hit unchanged.
5. `enter_value`: positive for a helpful `enter` field state on the AI's side, negative for one that helps the
   foe, zero with no trigger or a failing `when`.
6. Styles: for the same `knockout`, `faint`, `status` and `round_end` fixtures, an effect paid in HP (a `damage`
   faint trigger) is valued equally by both styles, a setup effect (a field state or stat stage) is valued at
   `AGGRESSIVE_SETUP_MULT` of the tactician's, aggressive never credits a status it applies, and `basic` scores
   exactly as before.
7. Invariants: no scoring call changes `rng.state`; `_setup_value` returns the same numbers after the extraction (the existing
   `test_ai.gd`, `test_ai_passives.gd`, `test_ai_cure.gd` and `test_ai_multi_hit.gd` pass unchanged, and move choices in their fixtures, which hold no
   knockout, faint, status or round-end triggers, are the same for every style).
8. Real data: Cold Snap and Finisher raise a knockout move's score, and Ember Trail lowers it, with the shipped
   passives.

The pack suites (`test_testpack_simulations.gd` and the 30-seed pack simulation) re-run; their exemption lists
may shrink or change, and any change is reported. `tools/simulate.gd` runs before and after (2v2, levels 10 and
40) to check for new outliers in win rates.

## 7. Documentation

"Passives and the AI" in `documentation/battle-engine.md` gains the five rules above and drops "Not modelled:
faint, knockout, enter, round-end and status triggers" (replaced by the two deliberate gaps: own-side `status`
triggers, and `enter` until M6f). The test-suite table gains the new file. The HANDOFF records the piece.

## 8. Risks

- **Balance drift.** Valuing `faint` and `knockout` changes tactician and aggressive play in battles that contain
  those passives. The simulator comparison covers both styles (`--ai=tactician,aggressive` and the reverse).
- **Currency mismatch.** HP-denominated terms (heal, damage) and `ref`-denominated ones (energy, stages) are
  combined as the tactician already does. `ENERGY_VALUE` is a first guess; it is a single constant to tune.
- **Unused function.** `enter_value` has no caller until M6f. It is small, tested and documented as waiting for it.
