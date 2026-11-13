# Minors triage and documentation audit (2026-11-12)

Branch `milestone/M6`, working tree clean at the time of writing (M6f and M6g are committed). Nothing here has been
changed: this is a proposal to pick from. "Verified" means I read the code; "reasoned" means from the handoff text only.

## Part 1: the open minors, as a whole

About 60 items from five sources: the passives handoff (31), M6c (5), M6e (6), M6f (9), M6g (12). They fall into five groups.

### A. Drop (moot, intended, or unreachable): 13
| Item | Why |
|---|---|
| Passives T2: `tools/simulate.gd` uses the first-passive default | Moot: the simulator now passes the battle RNG, so passives are rolled |
| M6e/M6f/M6g "Not done: swapping", "swaps for defensive", "`EXEMPT_TRIGGERS` at its cap", ".uid files untracked" | Done or moot (cap is 5, the tree is clean) |
| Passives T3 "v3->v4 test written with no RED run recorded" | A process note, not a defect |
| Passives T4 `when_holds` treats any non-"own" side as enemy | The validator enum guards it |
| Passives T6 `passives_for` cost per field state | Fine at current scale (the handoff says so) |
| Passives T8 `BattleText` null guard on `db.passive(...)` | The validator prevents bad ids |
| Passives Final: `start()` does not refill after an entry-trigger KO at battle start | Unreachable with shipped content |
| Passives Final: `PassiveUnlockScreen` "Current:" shows `c.passive` | Only reachable via debug or hand-edited saves |
| Passives T9: unknown id in `set_active` / an empty "New:" line | Same: needs a hand-edited save |
| Passives T3: `carry_over` maps a missing rolled passive to index 0 | Same |
| M6c: `EffectContext.hit_index` is unused | Delete the field if nothing needs it (one line); otherwise ignore |
| M6g: no test for an unknown style id | GdUnit cannot catch a GDScript `assert` |
| M6g: a spread attack under `weakest` splits one band | Intended; documented |

### B. Real behaviour issues, small: 6 (worth one piece)
| Item | Status | Effect |
|---|---|---|
| `replace()` calls `check_end()` then `_update_underdog()` (`battle_engine.gd:219-221`) | Verified | A replacement that decides the battle can emit `UNDERDOG` after `BATTLE_END` |
| Absorb at full HP emits `PASSIVE_TRIGGERED` and a `HEAL 0` | Reasoned | Cosmetic banner and log noise |
| Auto-replace side: a foe KO'd during the player's `replace()` is refilled only at the next round end | Reasoned | A one-round hole in 2v2/3v3 |
| `Passives.backfill` tries only the highest track at 30+, and refills a slot emptied with debug "(none)" on every load | Reasoned | Progression edge case; the second half is debug-only |
| An unlock-only entry for a growth-ready creature re-shows the Grow prompt | Reasoned | Minor UX |
| Knockout credit uses `last_hit_by` (`battle_rewards.gd:55`), so a status tick that faints a creature credits the last attacker | Verified | A design choice more than a bug: decide and document |

### C. AI accuracy (optional; each needs the simulator to justify): 15
Ranked by likely effect:
1. A benched creature's own passive, held item and ally auras are missing from `threat(c)` and `best_damage(c)`, so every matchup term leans against swapping (the M6f review's largest finding, left as docs only).
2. `KO_BONUS` is a flat 30 while everything else scales with `ref`, so at high levels a knockout is worth less relative to a status or a swap.
3. The "every foe targets this creature" threat is pessimistic in 2v2.
4. `hit` retaliation still has its own code instead of going through `trigger_value`.
5. The heal term's cliff at 50% HP (full value below, 0.2 above) limits what a style's `heal` weight can do.

The rest are small modelling gaps: a foe's round-end self-damage inflates the non-lethal credit; `when` is checked before the knockout (underdog, faint with `hp_below`); knockout credit counts once per finished foe on spread moves; `restore_energy` ignores the move's cost and `stat_stage` ignores the stage cap; `field_boost` of a benched creature; a creature with a skip status is not compared against skipping its swap turn; a swapped-out creature can be swapped back in by its ally next round; swap scores are not scaled by hit chance; `ko` 0 also zeroes a foe's faint-trigger cost for `passive`; own-side `status` triggers; multi-hit per-hit model (status retaliation overcounted, absorb heal not multiplied).
My view: take 1 to 3 together as one small "AI accuracy" piece if the simulator is happy, and drop the rest.

### D. Test hardening (no behaviour change, one piece): about 20
Weak or missing tests, mostly from reviews:
- Cannot fail or do not isolate what their name says: `test_no_damage_avoided_when_lead_is_healthy`, the basic-RNG half of `test_basic_and_aggressive_never_swap`, `test_lead_creatures_start_acted`, `test_setup_and_retaliation_weights_can_be_zeroed` (never zeroes retaliation), the defensive heal and swap sweeps (do not isolate `heal` / `swap_margin`), the blocked-status test (uses an already-statused foe), the M6c Resolve-endure test (the foe has 1 HP).
- Shared style objects are reset without try/finally in `test_ai_styles.gd`.
- `EXEMPT_TRIGGERS` lists entries that now fire, and the six-style rotation pairs only neighbours (tactician never meets passive in the pack run).
- Missing: table-driven content assertions for the 19 passives; cross-source stacking and aura-when pinning; chance-less trigger consumes no RNG; a status blocked inside a trigger; guard tests for foe raises and same-side ally drops; `rate_mult` 0 still draws one `randf`; M6c spec section 9 gaps (self-buff stacking, `finish_consume` once, no faint triggers on the battle-ending knockout); `ScreenFit` on the longest passive descriptions.

### E. Process
Put the surviving minors in one list in the HANDOFF (not five handoffs and five entries), each with a status, so the
next audit starts from a short list.

## Part 2: documentation audit

Mechanical checks that came back clean: every relative link and backticked repo path in the README and guides resolves
(two intentional examples excepted); every backticked identifier in the guides exists in the code; every test file named
in a doc exists; every `BattleEvents` constant except one is documented.

### Findings, in priority order
| # | Where | Problem | Proposed fix |
|---|---|---|---|
| 1 | `.superpowers/HANDOFF.md` | 47 KB. Header says branch `milestone/M6c`, last commit `55ff864`, "everything committed except M6c"; the M6c, M6e, M6f and M6g entries still say "uncommitted"; "Possible next steps" says the rest of M6 is next; the commit-format example says Opus 5.5; test counts are stale (`test_ai_triggers.gd` 26, actual 30) | Rewrite as a short current-state page (about 8 KB: state, standing rules, open minors, next steps) and move the per-piece history to `.superpowers/history/` |
| 2 | `documentation/developer-guide.md` | Status line and Roadmap section say M6 is partly done and "still open: AI trigger modelling, a few pinned engine rulings" (both done). "Where do I find..." has no row for AI behaviour or styles | Update the roadmap bullets; add a row: AI behaviour and styles -> `data/ai_styles.json`, `core/battle/ai/` |
| 3 | `README.md` | "M6 is partly done"; the content reference line omits AI Styles and Achievements; nothing mentions that AI styles are data | Update the status and the compendium line; one line under "Adding content" |
| 4 | `documentation/battle-engine.md` | (a) "three parts" lists four, here and in `battle_engine.gd:20`; (b) the Testing table omits 14 of the battle suites, including the core ones (`test_battle_engine`, `test_ai`, `test_underdog`, `test_passives_battle`, `test_field_reactions`...); (c) no reference list of effect ops: `apply_status`, `apply_field_state`, `remove_field_state`, `damage_fraction`, `reset_training` and `capture` are never named, although the developer guide points here for op meanings; (d) the `capture_failed` event is undocumented | Fix each; for (c) add an "Effect ops" table generated from `DataSchemas.EFFECT_OPS` (or checked against it by a test, so it cannot drift) |
| 5 | `battle-engine.md` size | 49 KB, and the AI material (styles, swapping, passives and the AI, held items and the AI, multi-hit AI) is about a quarter of it and growing | Move the AI sections to `documentation/ai.md` and link it from the README and the guide |
| 6 | Spec and plan status lines | Roadmap says "Draft (awaiting review)" and its M6 list is not updated; the M6e, M6f and M6g specs say "Draft"; the logging design says "Approved" (implemented); the M2 spec has none; plans have none | Set statuses; add the M6 outcome to the roadmap |
| 7 | Code comments | `battle_ai.gd` header lists three styles and a pre-M6e summary; `battle_engine.gd:20` as in 4a; the compendium "AI Styles" table omits `trigger_setup`, `seeks_status`, `swap_avoid` | Update the header comment; add the columns (or a "see battle-engine.md" note) |
| 8 | Drift guard | Nothing stops findings 2 to 4 recurring | A small test: every `BattleEvents` constant and every `EFFECT_OPS` key appears in `battle-engine.md`; every test file in `tests/battle/` appears in its Testing table |

## Suggested order
1. **Docs sweep** (Part 2, items 1 to 4, 6, 7 and the drift test in 8): no behaviour change, small, and it fixes the HANDOFF that every new session reads first.
2. **Test hardening** (group D) and the **small behaviour fixes** (group B), as two separate pieces.
3. **Split `ai.md` out** (item 5) with the docs sweep if you want it, otherwise later.
4. **AI accuracy** (group C, items 1 to 3) only if you want it; it needs simulator runs and may change win rates.

## Progress: docs sweep and test hardening (2026-11-12)
- **Docs sweep:** done (committed).
- **Test hardening:** done for the items below, each verified by mutating the code the test guards (the mutation made the test fail; code restored). Only test files changed.
  - Strengthened: `test_no_damage_avoided_when_lead_is_healthy` (now compares against a lower-defence bench creature), the basic-RNG half of `test_basic_and_aggressive_never_swap` (split into an aggressive test that checks the best move and a basic test that checks exactly one `randi_range` draw), `test_lead_creatures_start_acted` (new test clears the flag first so `place()` must write it), `test_setup_and_retaliation_weights_can_be_zeroed` (new retaliation scaling test), the defensive heal and swap sweeps (new tests isolate `heal` and `swap_margin`; the old ones passed through other weights), the blocked-status test (new test uses a real `status_immune` blocker), the M6c Resolve-endure test (it could not fail: a 1 HP foe never endures; it now uses a resolute foe with a few HP), shared style objects (a fresh Database per test).
  - Added: a chance-less trigger draws no RNG, a status blocked inside a trigger shows the block and no `STATUS_APPLIED`, `guard_stages` lets a foe raise a stage and an ally lower it, a self-buff effect stacks once per hit, a cash-in is consumed once per multi-hit move, the battle-ending knockout runs no faint trigger (with a control), a zero `rate_mult` still draws one number per tile, the foe's Bond is not scaled by the player's `bond_gain`.
  - `test_testpack_simulations.gd` now prints exempt entries that were reached this run (report only).
- **Not done, on purpose:** table-driven content assertions for the 19 passives (it would duplicate the JSON); the six-style pack rotation (changing it reshuffles the seeded run and the exemption lists); delisting exempt entries that fired this run (`tp_restore_energy_full_self`, `tp_stage_luck_swing`, `tp_hit_contact_rare`, `tp_h_pb_knockout`, `tp_h_pb_status`: they depend on the seeded run, so a decision for you).
- **Not done, still open:** cross-source stacking and aura-when-on-holder pinning; a seeded count for the encounter-rate test; `ScreenFit` on the longest passive descriptions; `test_party_lead_passive_line` leaves a screen open; the guard tests for the Set passive page (refresh_world, drop-down by position).

## Progress: small behaviour fixes (2026-11-12)
Group B, six items, each checked against the code before deciding:
- **Fixed** (failing test first, then the fix): `replace()` emitted `UNDERDOG` after `BATTLE_END` when the replacement's entry ended a battle whose Underdog ratio had been recorded (reproduced in 2v2); `replace()` now refreshes Underdog before the battle can end. A foe on an auto-replace side knocked out by the player's `replace()` stayed empty until the end of the next round (a round with an empty foe slot); the refill loop is now a shared `_refill_auto_replace()` that `replace()` also calls. Tests: `tests/battle/test_replace_settling.gd`.
- **Fixed:** `Passives.backfill` tried only the single highest track at 30+; it now tries each eligible track from highest to lowest (ties to the track listed first, explicit because `sort_custom` is not stable) and stops at the first that unlocks. Only matters for a species with no passive listed for a track; every shipped species lists all four. Test: `test_backfill_falls_back_to_the_next_track_when_the_highest_has_no_passive`.
- **Dropped, not a bug:** absorb at full HP. The player sees the absorb banner, then "X's HP is already full." That is accurate and informative. The debug "(none)" slot refilled on load: that is what `backfill` is for (it cannot tell a debug blank from a legacy save), and it is debug-only. The Grow prompt after an unlock-only entry: an Affinity unlock can change which growth branch is due, so showing it again is defensible.
- **Documented, kept:** a status tick that delivers the final HP credits the last creature that hit the fainted one (`battle-engine.md`, Affinity section).
- **New, unverified:** a creature that knocks out its own ally with an `all`-target move may earn knockout credit (`BattleRewards.on_faint` does not check the killer's side). A scratch test showed no Bond change and one Affinity point, so it is inconclusive; check before treating it as a bug.

## Progress: AI accuracy pass, M6h (2026-11-12)
Group C items 1 to 3 and the retaliation fold (item 4) are done, uncommitted: benched-creature passives, held items and ally auras are now scored in place; `KO_BONUS` is replaced by `ko_bonus(ref)`; `threat` is an expected value; hit retaliation runs through `trigger_value`. Measured effect and rulings are in the HANDOFF ("What changed in M6h"). Still open from group C: a foe's round-end self-damage inflating the non-lethal credit; `when` checked before the knockout; knockout credit once per finished foe on spread moves; `restore_energy` ignoring the move's cost and `stat_stage` the stage cap; a skip-status creature not compared against skipping its swap turn; a swapped-out creature swapped back in by its ally next round; swap scores not scaled by hit chance; `ko` 0 zeroing a foe's faint cost for `passive`; own-side `status` triggers; the multi-hit per-hit model; the heal term's 50% HP cliff.
