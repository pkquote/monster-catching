# Status-cure op Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `cure_status` effect op, a `status` passive/held trigger, bag use of cure items, AI scoring, and a shipped Clear Tonic item.

**Architecture:** `cure_status` is a normal effect op (schema entry, `op_cure_status.gd` handler, registry line, `EffectText` case) that calls a new `BattleEngine.cure_status`. `PassiveRules` gains a `status` trigger fired from `inflict_status`, and learns that a cure on an unafflicted target does nothing. `FieldItems` accepts the op for bag use.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4 suites in `tests/`.

**Spec:** `documentation/specs/2026-11-06-m6-status-cure-design.md`

## Global Constraints
- **Never `git commit`, `git add` or stash.** The user commits. Leave every change in the working tree. The last task gives the commit message.
- Ignore the uncommitted `data/` reshuffle already in the tree (moves split per type); do not touch `data/moves/*`.
- Do not run two Godot or test processes at once (shared save files).
- Run one suite: `"/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<dir>/<file>.gd --ignoreHeadlessMode -c`. Full check: `bash scripts/check.sh` must end "All checks passed."
- Op shape is exactly `{"op": "cure_status", "status"?: id}`; trigger name is exactly `status`; event is `STATUS_ENDED` with an extra `"cured": true`; Clear Tonic id `clear_tonic`, price 200, category `heal`, target `one_ally`.
- A cure with nothing to cure does nothing: no event, no spend, no Bond. A cure earns no Affinity.
- In tour files `d` is untyped, so values derived from it use `=`, not `:=`.

## Review Focus
1. Filtered cure on the wrong status: no event, the bag item is not spent, a held berry is not used up.
2. A consumed held cure berry on `round_end` with nobody afflicted: stays held and shows no banner.
3. `status` trigger must not fire when the status is blocked (`status_failed`, immunity, `resisted`): only after `STATUS_APPLIED`.
4. Fainted targets: engine cure is a no-op; the bag returns `fainted`.
5. A cure inside a trigger must not set off further triggers (depth guard), and a cured creature must not tick a stale `status_turns` at round end.

---

### Task 1: The `cure_status` op in battle

**Files:**
- Modify: `core/data/schemas.gd` (add to `EFFECT_OPS`)
- Create: `core/battle/effects/op_cure_status.gd`
- Modify: `core/battle/effects/effect_ops.gd` (register)
- Modify: `core/battle/battle_engine.gd` (add `cure_status` beside `inflict_status`, ~line 417)
- Modify: `core/data/effect_text.gd` (`effect()`), `game/battle/battle_text.gd` (`status_ended`)
- Test: `tests/battle/test_cure_status.gd` (new), `tests/data/test_validator.gd`, `tests/data/test_effect_text.gd`

**Interfaces:**
- Produces: `BattleEngine.cure_status(target: Battler, status_id: String, from_item := false) -> bool` (true when it cured); `EffectOps.get_op("cure_status")`; event `{"type": "status_ended", "bid", "status", "cured": true}`.

- [ ] **Step 1: Write failing tests.** In `tests/battle/test_cure_status.gd` (suite header like `test_held_items_battle.gd`: `var db`, `before()` builds `FixtureDB.raw()` plus added entries, validates, `Database.from_raw`). Add moves via `FixtureDB.move(...)`: `soothe` (neutral, status, 0 power, 100 acc, target `self`, `[{"op":"cure_status"}]`, `{"always_hits": true}`), `soothe_burn` (same with `"status": "burn"`); items `remedy` (`heal`, `one_ally`, `[{"op":"cure_status"}]`) and `burn_ward` (same with `"status":"burn"`). Tests:
  - `test_cure_clears_status_and_emits_cured_event`: blob with `burn_touch` afflicts the foe tank who knows `soothe`; foe uses `soothe`; assert foe `status()` is `""`, one `status_ended` event with `cured == true` and `status == "burn"`, and `status_turns == 0`.
  - `test_cure_with_no_status_does_nothing`: `soothe` on a healthy creature emits zero `status_ended` events.
  - `test_filtered_cure_ignores_other_status`: afflict with `shock` (`jolt`), `soothe_burn` leaves `status() == "shock"`, no event.
  - `test_filtered_cure_matches`: afflict `burn`, `soothe_burn` clears it.
  - `test_cure_on_fainted_target_does_nothing`: `e.cure_status(b, "burn")` after `FixtureDB.knock_out` returns false.
  - `test_cured_creature_takes_no_burn_damage_next_round`: afflict, cure, pass a round: no `damage` event for that bid.
  - `test_item_cure_awards_bond`: engine built with `items0 = {"remedy": 1}`, afflicted ally uses `BattleAction.use_item(bid, "remedy", bid)` (check the factory name in `core/battle/battle_action.gd`); assert the ally's Bond rose by the fixture's `healed_item` change (1) and no `heal` affinity point was awarded; an unafflicted ally using it gains no Bond.
  Also: `test_validator.gd` gets `test_cure_status_rejects_unknown_status` (an item with `{"op":"cure_status","status":"nope"}` yields an error naming the status) and `test_cure_status_accepts_no_status`; `test_effect_text.gd` gets `test_cure_status_text` asserting `EffectText.effect(db, {"op":"cure_status"})` is `"Cures any status"` and with `"status":"burn"` is `"Cures Burn"`.
- [ ] **Step 2: Run the three suites; expect FAIL** (unknown op / missing method).
- [ ] **Step 3: Implement.** Schema: `"cure_status": {"status": {"t": "ref", "cat": "statuses", "opt": true}}`. Handler `op_cure_status.gd` (extends `EffectOp`): `apply(ctx, e, target)` calls `ctx.engine.cure_status(target, e.get("status", ""), ctx.source == "item")`. Register `"cure_status": preload("op_cure_status.gd").new()`. Engine: if `not target.alive()` or `target.status() == ""` or (`status_id != ""` and it differs) return false; else emit `STATUS_ENDED` with `cured: true` using the old status id, set `target.creature.status = ""` and `target.status_turns = 0`, `rewards.bond(target, "healed_item")` when `from_item`, return true. `EffectText`: the two strings above. `BattleText` `status_ended`: when `ev.get("cured", false)` return `"%s was cured of %s." % [name, status name lowercased]`; the existing wording otherwise.
- [ ] **Step 4: Run the three suites; expect PASS.** Also run `tests/battle/test_battle_engine.gd` (status_ended wording unchanged for expiry).

### Task 2: The `status` trigger and trigger skip

**Files:**
- Modify: `core/data/schemas.gd` (`TRIGGER_ON` add `"status"`), `core/data/effect_text.gd` (`TRIGGER_LABELS`: `"status": "getting a status"`)
- Modify: `core/battle/passive_rules.gd` (`DEFAULT_TARGET` add `"status": "self"`; `_does_nothing`)
- Modify: `core/battle/battle_engine.gd` (`inflict_status`: fire after the `STATUS_APPLIED` emit and reward)
- Modify: `documentation/battle-engine.md` (trigger table ~line 209, skip rule ~line 228)
- Test: `tests/battle/test_cure_status.gd`

**Interfaces:**
- Consumes: Task 1's op and `BattleEngine.cure_status`.
- Produces: trigger `on: "status"`, default target `self`.

- [ ] **Step 1: Write failing tests** (same suite; add held items in `before()`): `clear_berry` (`use: consumed`, trigger `status` with `[{"op":"cure_status"}]`), `round_clear_berry` (`consumed`, trigger `round_end`, same effect), `burn_berry` (`consumed`, trigger `status`, `[{"op":"cure_status","status":"burn"}]`), `ward_charm` (permanent, trigger `status` applying `stat_stage` patk +1 to self), and a passive `purifier` (trigger `round_end`, cure). Tests:
  - `test_status_trigger_cures_the_new_status_and_uses_up_berry`: holder of `clear_berry` is hit by `burn_touch`; afterwards `status() == ""`, `held_item == ""`, events contain `status_applied` then `status_ended` (cured) then `item_consumed`, and one passive banner.
  - `test_status_trigger_filter_mismatch_keeps_berry`: `burn_berry` holder given `shock`: status stays, berry still held, no passive banner.
  - `test_status_trigger_skipped_when_blocked`: holder also immune (use `fire_charm`-style passive `fireproof` from the held test's pattern) to burn: no trigger fires; and `status_failed` case (already afflicted) fires nothing.
  - `test_round_end_cure_berry_not_wasted`: `round_clear_berry` holder with no status passes a round: berry still held, no `passive_triggered` event; afflict it, pass a round: cured and berry gone.
  - `test_cure_passive_at_round_end`: `purifier` holder afflicted by `burn_touch` ends the round cured.
  - `test_status_trigger_target_is_the_afflicted_creature`: `ward_charm` holder gains patk stage when afflicted; its attacker does not.
  - `test_cure_in_trigger_sets_off_no_further_triggers`: a holder with a `status` trigger that applies a different status to self fires once only (depth guard).
- [ ] **Step 2: Run the suite; expect FAIL** (validator rejects trigger `status`).
- [ ] **Step 3: Implement.** In `inflict_status`, after `rewards.award(...)` block (so after the `STATUS_APPLIED` emit), call `passive_rules.fire(target, "status", user)` (the `attacker` argument is the inflicting user, null-safe — read `fire`'s signature first). `_does_nothing`: treat `cure_status` as a third no-op-able op: for each live target, it does something only when the target's status is non-empty and matches `eff.get("status", "")` (empty matches any); update the early `return false` guard so `cure_status` is allowed through. Update the docs table row: `status` | A status was just applied to it (after the `status_applied` event; blocked or resisted statuses don't fire it) | itself; and add `cure_status` on afflicted-less targets to the skip rule.
- [ ] **Step 4: Run the suite and `tests/battle/test_passives_battle.gd`, `test_held_items_battle.gd`; expect PASS.**

### Task 3: Bag use

**Files:**
- Modify: `core/progress/field_items.gd` (`OPS`, `can_use`, `_would_gain`, `use`, return dict)
- Modify: `game/overworld/ui/pause_menu.gd` (result message, ~line 108)
- Test: `tests/progress/test_field_items.gd`, `tests/world/test_pause_menu.gd` (only if an existing assertion breaks)

**Interfaces:**
- Produces: `FieldItems.use(...)` result gains `cured: bool`; errors unchanged (`no_effect` when nothing to heal, restore or cure).

- [ ] **Step 1: Write failing tests** in `test_field_items.gd`. Its `before()` loads real `res://data`; add `clear_tonic` use after Task 5 or build a local fixture db for these (preferred: a second `FixtureDB`-based db with `remedy`, `burn_ward`, `full_remedy` = heal 1.0 + cure). Tests:
  - `test_cure_item_clears_status_and_is_spent`: creature `status = "burn"`, use `remedy` ⇒ `ok`, `cured`, status `""`, inventory decremented.
  - `test_cure_item_no_status_is_no_effect`: `no_effect`, nothing spent.
  - `test_filtered_cure_wrong_status_is_no_effect`: `shock` creature + `burn_ward` ⇒ `no_effect`, status kept.
  - `test_combined_item_cures_and_heals`: `full_remedy` on a burned, hurt creature ⇒ `healed > 0` and `cured`; on a burned full-HP creature ⇒ `ok`, `healed == 0`, `cured`; on a healthy full-HP one ⇒ `no_effect`.
  - `test_fainted_cure_target`: `error == "fainted"`.
  - `test_can_use_and_usability_for_cure_items`: `can_use` true without a `fraction`; `usability` is `ok` only when some party member has a matching status, otherwise `{ok:false, reason:"No one needs it right now."}`.
- [ ] **Step 2: Run the suite; expect FAIL.**
- [ ] **Step 3: Implement.** `OPS` gains `"cure_status"`; `can_use` requires `fraction` only for `heal` and `restore_energy`. `_would_gain` returns true for `cure_status` when `m.status != ""` and the effect has no `status` or equals it. `use`: initialise `cured: false`; in the effect loop a matching `cure_status` sets `out.cured = true`; the `no_effect` guard becomes `healed <= 0 and energy <= 0 and not cured`; on success apply `c.status = ""` when `cured`. Pause menu: when `r.cured` and `r.healed == 0 and r.energy == 0` the message is `"%s was cured." % cname`, else the existing `"%s recovered."`.
- [ ] **Step 4: Run `test_field_items.gd`, `test_pause_menu.gd`, `test_bag_summary.gd`; expect PASS.**

### Task 4: AI scoring

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`_move_value` effect loop, ~line 112)
- Modify: `documentation/battle-engine.md` (AI section: scoring line; "Not modelled" line ~292 adds `status`)
- Test: `tests/battle/test_ai.gd` (or new `tests/battle/test_ai_cure.gd`)

**Interfaces:**
- Consumes: `BattleAI.status_value(engine, t, status_id, ref)` (existing).

- [ ] **Step 1: Write failing tests.** Reuse the Task 1 fixture moves via a small local `before()`. `test_cure_move_scores_zero_on_healthy_user`: `BattleAI.move_value`-equivalent for `soothe` (use the same entry point `test_ai.gd` uses for scoring a move) equals 0 for an unafflicted user. `test_cure_move_scores_positive_when_afflicted`: after the user is burned the score is greater than 0 and equals `status_value` for burn at the same `ref`. `test_cure_move_ignores_filter_mismatch`: shocked user + `soothe_burn` scores 0. `test_cure_move_never_helps_foes`: a `one_enemy`-target cure on an afflicted foe scores 0 (cures only count for the user's own side).
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.** In the `for e in m.effects` loop of `_move_value` add `cure_status`: for each `t` in `targets` on `b.side` with a non-empty, matching status, `value += status_value(engine, t, t.status(), ref)`. Docs: add the cure scoring sentence and add `status` to the "Not modelled" list.
- [ ] **Step 4: Run `test_ai.gd`, `test_ai_passives.gd`; expect PASS.**

### Task 5: Content (Clear Tonic and the test pack)

**Files:**
- Modify: `data/items/healing.json` (add Clear Tonic after Tonic)
- Modify: `tools/build_maps.gd` (~line 167 stock list), `game/maps/town_01_center.tscn` (line 64 stock), `tests/world/test_shop.gd` (stock list in `test_town_shop_buy_list_fits_the_viewport`)
- Modify: `data_testpack/items/tp_healing.json`, `data_testpack/moves/tp_status.json`, `data_testpack/passives/tp_triggers.json`, `data_testpack/items/tp_held.json`
- Create: `tests/data/test_status_cure_data.gd`
- Regenerate: `documentation/compendium.md`

**Interfaces:**
- Consumes: the op and trigger from Tasks 1–2.

- [ ] **Step 1: Write failing tests.** `tests/data/test_status_cure_data.gd`: with `DataLoader.load_database("res://data")`: `test_clear_tonic_is_a_priced_heal_item` (category `heal`, price 200, target `one_ally`, effects exactly `[{"op":"cure_status"}]`, name "Clear Tonic", `FieldItems.can_use` true); with the pack loaded (`DataLoader.load_database("res://data", "res://dialogue", ["res://data_testpack"])` — copy the call shape from `tests/data/test_testpack_loader.gd`): `test_pack_cure_content_exists` asserting `tp_full_restore` has a `cure_status` effect and that the pack contains `tp_antidote` (filtered burn), `tp_cure_all`, move `tp_purify`, passive `tp_purifier`, held `tp_clear_berry`. Update the shop-fit test's stock list to add `"clear_tonic"` after `"tonic"`.
- [ ] **Step 2: Run `test_status_cure_data.gd` and `test_testpack_coverage.gd`; expect FAIL** (entries missing; coverage guard reports `cure_status` and `status` uncovered).
- [ ] **Step 3: Add data.** Clear Tonic: description "Cures a creature's status condition.". Pack (all ids `tp_` prefixed, descriptions say what they test): `tp_antidote` (heal, `one_ally`, `cure_status` burn), `tp_cure_all` (heal, `cure_status`), `tp_full_restore` effects become heal 1.0 + restore_energy 1.0 + `cure_status` with its description corrected, move `tp_purify` (self-target status move with `cure_status`, same stats pattern as neighbouring `tp_status.json` moves), passive `tp_purifier` (trigger `round_end`, `cure_status`), held `tp_clear_berry` (`use: consumed`, trigger `status`, `cure_status`). Add `"clear_tonic"` to both stock lists after `"tonic"`. Give some pack creature the new move or passive only if the existing coverage/simulation tests require it (they should not; pack moves need not be learned).
- [ ] **Step 4: Run** `test_status_cure_data.gd`, `test_testpack_coverage.gd`, `test_pack_coverage.gd`, all `test_testpack_*` suites, `tests/world/test_shop.gd`, `tests/world/test_map_rules.gd`; expect PASS. **If the shop-fit test fails because 12 items no longer fit the 640x360 window, stop and report to the user; do not redesign the shop menu.** Run `bash scripts/check.sh`'s data and maps stages (`validate_data.gd` prints `Data OK` and `Data+pack OK`).

### Task 6: Docs, tour, full check

**Files:**
- Modify: `documentation/battle-engine.md` (op list: add `cure_status` with the no-op rule and Bond note)
- Modify: `.claude/skills/run-godot-monster-catching-game/tours/bag.gd`
- Regenerate: `documentation/compendium.md`

- [ ] **Step 1: Docs.** Add `cure_status` to the effect-op reference in `battle-engine.md` (shape, silent no-op, `cured` flag on `status_ended`, item Bond, no Affinity); fix the event row at ~line 334 to mention `cured`.
- [ ] **Step 2: Tour.** Read `tours/bag.gd` and the skill's SKILL.md for the step pattern. Add steps after the existing item steps: give the lead a status directly (`status = "burn"`), put `clear_tonic` in the bag, open the Bag, pick Clear Tonic, check the pane shows the item and "Usable now.", use it on the burned creature, assert the status is `""` and the item is gone, screenshot and check nothing is clipped.
- [ ] **Step 3: Run the bag tour** per the run skill (`--mode=bag`); expect ALL CHECKS PASSED.
- [ ] **Step 4: Full check.** `bash scripts/check.sh`; expect it to end "All checks passed." (it regenerates the compendium; confirm `compendium.md` now lists Clear Tonic and the cure effect text).
- [ ] **Step 5: Hand over.** Do not commit. Give the user this message:

```
Add M6: cure_status op, status trigger and Clear Tonic
- cure_status effect op (optional status filter) for moves, items and triggers, with a cured flag on status_ended
- New status trigger for passives and held items; cure triggers that would do nothing are skipped
- Bag items can cure, the AI scores cure moves, and Clear Tonic is stocked at the Town 1 shop
- Test pack: tp_full_restore is a real full cure, plus cure item, move, passive and held berry

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
```

---

**Self-review notes:** every spec section has a task (engine 1–2, bag 3, battle-item rule: no change, since heal items are not greyed in the battle menu either, `battle_scene.gd` only disables capture items, AI 4, content 5, docs and tests 6). The spec's "Battle items" paragraph is therefore a no-op; the spec is amended to say so.
