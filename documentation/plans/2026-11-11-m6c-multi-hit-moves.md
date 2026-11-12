# Multi-Hit Moves Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `one_enemy` move can carry `hits: {min, max}` and hit its foe that many times, repeating its whole effect list per hit, with a mid-move faint spilling the remaining hits to the next foe in slot order.

**Architecture:** `MoveDef` and the schema/validator gain `hits`; `balance.max_hits` caps it. `ActionRunner._move` keeps its single accuracy roll, then a new `_run_hits` loop runs the effect list once per hit, calling `check_faints()` between hits and moving to `BattleEngine.next_foe_after` when the target falls. One new event, `HIT_COUNT`, reports the hits landed. The AI scores a ranged move at its mean hit count. Affinity from hits is earned once per move use.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4. Checks: `bash scripts/check.sh`.

**Spec:** [documentation/specs/2026-11-11-m6c-multi-hit-moves-design.md](../specs/2026-11-11-m6c-multi-hit-moves-design.md)

**Commits:** the user writes every commit in this project. Do not `git commit`, stage or stash; each task ends with its test run, and the final message gives a suggested commit message.

**One suite:** run a single test file with
`"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<path>.gd --ignoreHeadlessMode -c`
where `GODOT` is the console exe named in `scripts/check.sh`. Below this is written `RUN <path>`.

## Global Constraints

- `hits` is `{"min": int, "max": int}`; `1 <= min <= max <= balance.max_hits`; `balance.max_hits` is an integer 2 to 10, shipped as 5.
- `hits` is valid only on a move whose `target` is `one_enemy`.
- A move without `hits` behaves exactly as today and must not draw from the battle RNG for hits (seeded tests stay stable).
- Accuracy is rolled once per move; spill hits take no new roll; `spread_count` stays 1.
- The whole `effects` list runs once per hit; `finish_consume` runs once, after the last hit.
- The next target after a faint is the next standing active foe in slot order, wrapping; none left ends the move.
- `hit_dealt` and `hit_survived` Affinity awards are earned once per move use.
- `HIT_COUNT` is `{type: "hit_count", bid: <user bid>, hits: <hits landed>}`, emitted only for multi-hit moves.
- Test code must not contain the literals `tp_` or `testpack` outside the test pack's own files.

## Review Focus

- A seeded battle with only single-hit moves is unchanged (no extra RNG draw): the existing suites stay green and a new test compares two engines.
- The attacker faints mid-move to a retaliation trigger: the loop stops.
- The only foe faints on hit 1 of 5: `HIT_COUNT.hits` is 1, no error, no further `DAMAGE`.
- A 3-foe wraparound: the first target is the last slot and the spill goes to slot 0.
- A benched foe never takes a spill hit, and no replacement enters mid-move.
- The hit that ends the battle: `HIT_COUNT` comes before `BATTLE_END`, and faint triggers do not fire on that knockout.

## File Structure

- Modify: `core/data/schemas.gd`, `core/data/validator.gd`, `core/data/defs/move_def.gd`, `core/data/defs/balance_def.gd`, `data/balance.json`, `tests/helpers/fixture_db.gd`
- Modify: `core/battle/battle_events.gd`, `core/battle/effects/effect_context.gd`, `core/battle/battle_engine.gd`, `core/battle/action_runner.gd`, `core/battle/ai/battle_ai.gd`
- Modify: `game/battle/battle_text.gd`, `core/data/effect_text.gd`, `tools/compendium_builder.gd`
- Modify: `data/moves/water.json`, `data/moves/ice.json`, `data/moves/electric.json`, `data/creatures/starter_line.json`, `data/creatures/route_01.json`
- Create: `tests/data/test_multi_hit_data.gd`, `tests/battle/test_multi_hit_moves.gd`, `tests/battle/test_ai_multi_hit.gd`, `tests/data/test_multi_hit_moves_data.gd`, `.claude/skills/run-godot-monster-catching-game/tours/multihit.gd`
- Docs: `documentation/battle-engine.md`, `documentation/compendium.md` (generated), `documentation/specs/2026-11-03-monster-rpg-design.md` (§2.4 pointer), `documentation/developer-guide.md`, `.superpowers/HANDOFF.md`, tour `SKILL.md`

---

### Task 1: Data — `hits`, `balance.max_hits`, validator

**Files:**
- Modify: `core/data/schemas.gd` (moves schema near line 269; balance schema near line 379), `core/data/validator.gd` (moves loop near line 379), `core/data/defs/move_def.gd`, `core/data/defs/balance_def.gd`, `data/balance.json`, `tests/helpers/fixture_db.gd` (`balance()`)
- Test: `tests/data/test_multi_hit_data.gd`

**Interfaces:**
- Produces: `MoveDef.hits_min: int`, `MoveDef.hits_max: int` (both 1 without `hits`), `MoveDef.is_multi_hit() -> bool` (`hits_max > 1`), `MoveDef.mean_hits() -> float` (`(hits_min + hits_max) / 2.0`); `BalanceDef.max_hits: int`, `BalanceDef.MAX_HITS: int = 10`.

- [ ] **Step 1: Write the failing tests** in `tests/data/test_multi_hit_data.gd` (`extends GdUnitTestSuite`):

```gdscript
func _raw_with(hits: Variant, target := "one_enemy") -> RawData:
	var r := FixtureDB.raw()
	var extra := {} if hits == null else {"hits": hits}
	r.add_entry("moves", FixtureDB.move("flurry", "neutral", "physical", 20, 100, target, [{"op": "damage"}], extra))
	return r

func _errors(r: RawData) -> String:
	return "\n".join(DataValidator.validate(r))

func test_a_move_without_hits_hits_once() -> void
	# FixtureDB.build() db; db.move("hit"): hits_min == 1, hits_max == 1, is_multi_hit() false, mean_hits() 1.0
func test_hits_range_is_read() -> void
	# db from _raw_with({"min": 2, "max": 5}) via Database.from_raw: min 2, max 5, is_multi_hit true, mean_hits 3.5
func test_a_fixed_count_is_min_equal_max() -> void
	# {"min": 3, "max": 3}: validates with no errors, is_multi_hit true, mean_hits 3.0
func test_validator_rejects_bad_hits() -> void
	# for each label: _errors(...) contains "hits":
	#   min_above_max {"min": 3, "max": 2}; zero_min {"min": 0, "max": 2}; above_balance {"min": 1, "max": 6};
	#   two_enemies_target (hits {"min":2,"max":3}, "two_enemies"); self_target (..., "self"); all_target (..., "all_enemies")
func test_balance_max_hits_range() -> void
	# b := FixtureDB.balance(); b["max_hits"] = n; r.set_single("balance", b):
	# 1 and 11 produce an error containing "max_hits"; 2, 5 and 10 produce none
func test_shipped_balance_has_max_hits_five() -> void
	# DataLoader.load_database("res://data", "res://dialogue"): result.db.balance.max_hits == 5
```

- [ ] **Step 2: Run to verify failure** — `RUN tests/data/test_multi_hit_data.gd`. Expected: FAIL (unknown field `hits` / no `max_hits`).

- [ ] **Step 3: Implement.**
  - `schemas.gd` moves: `"hits": {"t": "dict", "opt": true, "fields": {"min": {"t": "int", "min": 1, "max": BalanceDef.MAX_HITS}, "max": {"t": "int", "min": 1, "max": BalanceDef.MAX_HITS}}}`. Balance: `"max_hits": {"t": "int", "min": 2, "max": BalanceDef.MAX_HITS}`.
  - `validator.gd`, in the moves loop after the power checks: if `m.get("hits")` is a Dictionary — `_err("hits", "only one_enemy moves can have hits")` when `m.get("target") != "one_enemy"`; when `min` and `max` are numbers, `_err("hits", "min must not exceed max")` if `min > max`, else `_err("hits", "max %d is above balance.max_hits (%d)" % [...])` if `max` exceeds the raw balance's `max_hits` (read `_raw.singles["balance"].data.get("max_hits")` only when it is a number).
  - `MoveDef.from_dict`: read `d.get("hits", {})` into `hits_min` / `hits_max` (default 1); add the two methods. `BalanceDef`: `const MAX_HITS: int = 10`, `var max_hits: int`, `b.max_hits = int(d.max_hits)`.
  - `data/balance.json`: add `"max_hits": 5` beside `"max_moves"`. `FixtureDB.balance()`: add `"max_hits": 5`.

- [ ] **Step 4: Run to verify pass** — `RUN tests/data/test_multi_hit_data.gd`. Expected: PASS. Then `RUN tests/data` (the folder, same `--add res://tests/data`) to confirm no other data suite broke. Expected: PASS.

---

### Task 2: Engine — the hit loop, spill, awards and `HIT_COUNT`

**Files:**
- Modify: `core/battle/battle_events.gd`, `core/battle/effects/effect_context.gd`, `core/battle/battle_engine.gd` (`deal_damage`, new helpers), `core/battle/action_runner.gd` (`_move`, new `_run_hits`), `game/battle/battle_text.gd`
- Test: `tests/battle/test_multi_hit_moves.gd`; `tests/battle/test_battle_events.gd` already checks every event has text.

**Interfaces:**
- Consumes: `MoveDef.hits_min/hits_max/is_multi_hit()` (Task 1).
- Produces: `BattleEvents.HIT_COUNT := "hit_count"` (added to `ALL`); `EffectContext.hit_index: int = 0`; `BattleEngine.next_foe_after(user: Battler, fallen: Battler) -> Battler` (null when none); `BattleEngine.begin_multi_hit() -> void` and `end_multi_hit() -> void`; `ActionRunner._run_hits(b: Battler, m: MoveDef, ctx: EffectContext) -> void`.

- [ ] **Step 1: Write the failing tests** in `tests/battle/test_multi_hit_moves.gd`. Setup in `before()`: `FixtureDB.raw()`, then add these moves with `FixtureDB.move(id, "neutral", "physical", 20, 100, "one_enemy", effects, extra)`: `triple` (`hits` 3-3), `flurry` (`hits` 2-5), `doubled` (`hits` 3-3, effects `[{"op":"damage"},{"op":"damage"}]`), `jolting` (`hits` 3-3, effects `[{"op":"damage"},{"op":"apply_status","status":"shock","chance":100}]`), `single` (no `hits`); and passives `thorns` (`{"id":"thorns","triggers":[{"on":"hit","effects":[{"op":"damage","power":200,"target":"attacker"}]}]}`, merged with `name` and `description` as `test_passives_battle.gd` does) and `pricker` (`{"on":"hit","effects":[{"op":"stat_stage","stat":"patk","stages":-1}]}`). Validate and build the db as `test_two_target_moves.gd` does. Helpers as in that suite (`_mk(species, moves)`, `_versus(foes, bench, seed)`, `_me`, `_foes`); a foe's passive is set with `creature.passive = id`.

```gdscript
func test_a_fixed_count_hits_exactly_that_many_times() -> void
	# _versus(1), triple on the foe: 3 DAMAGE events, HIT_COUNT.hits == 3, one MOVE_USED
func test_a_range_stays_within_min_and_max_and_covers_it() -> void
	# seeds 1..60 with flurry: every HIT_COUNT.hits in 2..5, and the set of values seen is {2,3,4,5}
func test_a_move_without_hits_emits_no_hit_count_and_hits_once() -> void
	# single: 1 DAMAGE, no HIT_COUNT
func test_single_hit_moves_do_not_draw_extra_rng() -> void
	# two engines, same seed, same single-hit round: identical event lists (compare event dictionaries)
func test_a_miss_deals_no_hits_and_no_hit_count() -> void
	# triple with accuracy 1 against a foe: over seeds 1..40 whenever a MISS event is present there is no DAMAGE and no HIT_COUNT
func test_the_whole_effect_list_runs_per_hit() -> void
	# doubled: 6 DAMAGE events; jolting (chance 100): the foe's status is shock and STATUS_APPLIED occurs on hit 1 only (later hits report STATUS_FAILED) — assert status_applied count == 1 and status_failed count == 2
func test_hit_triggers_fire_once_per_hit() -> void
	# foe passive "pricker" (stat_stage -1 patk on being hit): after triple, the attacker's patk stage is -3 (e.sides[0] attacker .stages["patk"])
func test_resolve_endure_still_happens_once() -> void
	# db built with FixtureDB.build({"resolve": {"resist_cap": 0.0, "endure_cap": 1.0}}) variant of the suite db: a foe with hp 1 hit by triple: at most one ENDURED event
func test_affinity_from_hits_is_earned_once_per_move() -> void
	# e.rewards.affinity_log[attacker.bid]["striker"] after triple on a tank equals the log after a single-hit move (1 point); the foe's "warden" log is also 1
func test_a_fainted_target_faints_at_once_and_the_rest_spill_in_slot_order() -> void
	# _versus(3): foes[0].creature.hp = 1; triple aimed at foes[0]: event order is DAMAGE(foes[0]), FAINT(foes[0]), DAMAGE(foes[1]), DAMAGE(foes[1]); HIT_COUNT.hits == 3; foes[2] untouched
func test_the_spill_wraps_around_the_slots() -> void
	# _versus(3): foes[2].hp = 1, triple at foes[2]: the next DAMAGE targets foes[0]
func test_the_spill_skips_a_fainted_slot_and_a_benched_foe() -> void
	# _versus(2, 1 bench): foes[0].hp = 1, foes[1].hp = 1, triple at foes[0]: DAMAGE foes[0], FAINT, DAMAGE foes[1], FAINT, then the move ends; the benched creature is untouched and no SEND_OUT during the move; HIT_COUNT.hits == 2
func test_a_lone_foe_ends_the_move_early() -> void
	# _versus(1): foe hp 1, flurry forced to 5 via a 5-5 variant move "quint": 1 DAMAGE, HIT_COUNT.hits == 1
func test_the_hit_that_ends_the_battle_stops_the_move() -> void
	# _versus(1, 0): foe hp 1, triple: HIT_COUNT precedes BATTLE_END in the event list; no further DAMAGE
func test_the_attacker_fainting_mid_move_stops_it() -> void
	# attacker hp 1, foe passive "thorns" (200-power retaliation): triple lands 1 hit; the attacker FAINTs; HIT_COUNT.hits == 1
func test_next_foe_after_returns_null_without_a_standing_foe() -> void
	# _versus(1): foe hp 0 and check_faints(); e.next_foe_after(me, foe) is null
```

- [ ] **Step 2: Run to verify failure** — `RUN tests/battle/test_multi_hit_moves.gd`. Expected: FAIL (the moves validate after Task 1 but nothing repeats; `HIT_COUNT`, `next_foe_after` missing).

- [ ] **Step 3: Implement.**
  - `BattleEvents`: `const HIT_COUNT := "hit_count"` under "Actions" and add it to `ALL`. `EffectContext`: `var hit_index := 0` ("0-based number of the hit being run; 0 for a single-hit move").
  - `BattleText.describe`: `"hit_count":` returns `"Hit %d times!" % int(ev.hits)` when `int(ev.hits) >= 2`, else `""`.
  - `BattleEngine`: `var _hit_awards_once := false` and `var _hit_awarded := {}`; `begin_multi_hit()` sets the flag and clears the dict, `end_multi_hit()` clears the flag; private `_award_hit(b: Battler, happening: String)` returns early when the flag is set and `"%s:%d" % [happening, b.bid]` is already in `_hit_awarded`, else records it and calls `rewards.award(b, happening)`. In `deal_damage`, replace the two `rewards.award(attacker, "hit_dealt")` and `rewards.award(target, "hit_survived")` calls with `_award_hit`. `next_foe_after(user, fallen)`: `var opp := sides[1 - user.side]`, `var n := opp.slots.size()`, `var start := opp.slot_of(fallen)`; for `i in range(1, n + 1)` take `opp.slots[(start + i) % n]` and return it if it is non-null, `alive()` and `active`; return null otherwise (a `start` of -1 simply scans from slot 0).
  - `ActionRunner._move`: after the targets loop that builds `ctx.targets` (and its empty-list return), replace the last two lines with:

```gdscript
	if not m.is_multi_hit():
		e.run_effects(ctx, m.effects)
		e.field_rules.finish_consume(ctx)
		return
	_run_hits(b, m, ctx)
```

  - `ActionRunner._run_hits` (the loop is an algorithm the signature does not fix):

```gdscript
func _run_hits(b: Battler, m: MoveDef, ctx: EffectContext) -> void:
	var e := engine
	var count := e.rng.randi_range(m.hits_min, m.hits_max)
	var landed := 0
	e.begin_multi_hit()
	for i in count:
		ctx.hit_index = i
		var current: Battler = ctx.targets[0]
		e.run_effects(ctx, m.effects)
		landed += 1
		e.check_faints()
		if not b.alive() or e.sides.any(func(s: BattleSide) -> bool: return s.defeated()):
			break
		if not current.alive():
			var next := e.next_foe_after(b, current)
			if next == null:
				break
			ctx.targets.clear()
			ctx.targets.append(next)
	e.end_multi_hit()
	e.emit({"type": BattleEvents.HIT_COUNT, "bid": b.bid, "hits": landed})
	e.field_rules.finish_consume(ctx)
```

- [ ] **Step 4: Run to verify pass** — `RUN tests/battle/test_multi_hit_moves.gd`, then `RUN tests/battle` (whole folder). Expected: PASS, including `test_battle_events.gd`, `test_simulation_invariants.gd` and `test_targeting_matrix.gd` unchanged.

---

### Task 3: AI — score at the mean hit count

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`estimate_damage`, `score`)
- Test: `tests/battle/test_ai_multi_hit.gd`

**Interfaces:**
- Consumes: `MoveDef.mean_hits()` (Task 1).
- Produces: `BattleAI.estimate_damage(...)` now returns the per-hit total times `m.mean_hits()` (unchanged signature).

- [ ] **Step 1: Write the failing tests** in `tests/battle/test_ai_multi_hit.gd` (same `before()` shape as Task 2; moves `triple` (20 power, 3-3), `flurry` (20 power, 2-5), `plain20` (20 power, no `hits`), `plain60` (60 power, no `hits`)):

```gdscript
func test_estimate_is_per_hit_damage_times_the_mean_hit_count() -> void
	# vs a "tank": estimate(flurry) == estimate(plain20) * 3.5 and estimate(triple) == estimate(plain20) * 3.0 (assert_float is_equal_approx within 0.001)
func test_a_single_hit_move_estimates_as_before() -> void
	# estimate(plain20) equals BattleMath.damage(e, ctx, {"op": "damage"}, target, false).amount for the same move
func test_the_ai_prefers_a_multi_hit_move_to_an_equal_single_hit_one() -> void
	# score(e, user, triple, foe.bid, "aggressive") > score(plain20, ...), and choose() on a creature knowing [plain20, triple] picks "triple" (test_ai.gd shows the call shape)
func test_equal_expected_damage_scores_equally() -> void
	# plain60 (60 per use) and triple (3 x 20 = 60) estimate the same damage: |score(plain60) - score(triple)| < 0.001 vs a tank
func test_retaliation_counts_per_expected_hit() -> void
	# tactician, foe passive "thorns" (a hit trigger that damages the attacker): let drop(m) = score(m, no-passive foe) - score(m, thorns foe);
	# assert drop(triple) is greater than drop(plain20) * 2.5 (three expected hits against one)
```

- [ ] **Step 2: Run to verify failure** — `RUN tests/battle/test_ai_multi_hit.gd`. Expected: FAIL (estimate ignores hits).

- [ ] **Step 3: Implement.** In `estimate_damage`, `return total * m.mean_hits()`. In `score`, multiply the `_retaliation(...)` term by `m.mean_hits()`. Nothing else changes.

- [ ] **Step 4: Run to verify pass** — `RUN tests/battle/test_ai_multi_hit.gd`, then `RUN tests/battle`. Expected: PASS; the existing AI suites (`test_ai.gd`, `test_ai_passives.gd`) unchanged because `mean_hits()` is 1.0 for single-hit moves.

---

### Task 4: Text — the hits label and the compendium

**Files:**
- Modify: `core/data/effect_text.gd`, `tools/compendium_builder.gd` (Moves tables near line 368)
- Test: add to `tests/data/test_multi_hit_data.gd`; `tests/data/test_compendium.gd` regenerates over real data (Task 5 content).

**Interfaces:**
- Consumes: `MoveDef.hits_min/hits_max/is_multi_hit()`.
- Produces: `EffectText.hits_label(m: MoveDef) -> String` — `""` for a single-hit move, `"Hits 3 times"` when `min == max`, `"Hits 2-5 times"` otherwise.

- [ ] **Step 1: Write the failing tests** (append to `tests/data/test_multi_hit_data.gd`):

```gdscript
func test_hits_label_wording() -> void
	# single-hit "" ; {"min":3,"max":3} "Hits 3 times"; {"min":2,"max":2} "Hits 2 times"; {"min":2,"max":5} "Hits 2-5 times"
func test_compendium_moves_table_shows_the_hits_label() -> void
	# a db whose raw has a 2-5 move: CompendiumBuilder.build(db) contains "Hits 2-5 times" on that move's table row
```

- [ ] **Step 2: Run to verify failure** — `RUN tests/data/test_multi_hit_data.gd`. Expected: FAIL (`hits_label` missing).

- [ ] **Step 3: Implement** `EffectText.hits_label`. In `compendium_builder.gd` Moves tables, after `var effects := EffectText.effects(db, m.effects)`, when `EffectText.hits_label(m) != ""` set `effects = "%s; %s" % [EffectText.hits_label(m), effects]` (before the description `<br>` line is appended).

- [ ] **Step 4: Run to verify pass** — `RUN tests/data/test_multi_hit_data.gd`, then `RUN tests/data/test_compendium.gd`. Expected: PASS.

---

### Task 5: Content — three example moves

**Files:**
- Modify: `data/moves/water.json` (Twin Splash), `data/moves/ice.json` (Needle Flurry), `data/moves/electric.json` (Spark Volley), `data/creatures/starter_line.json` (Tidepup learnset), `data/creatures/route_01.json` (Frostling and Voltmoth learnsets)
- Test: `tests/data/test_multi_hit_moves_data.gd`

**Interfaces:**
- Consumes: `hits` schema (Task 1), `EffectText.hits_label` (Task 4).

Numbers (the single-target anchors are Splash Jab 40 power / cost 2, Riptide and Tide Beam 55 / cost 6, Arc Pair 44 / cost 5; each move's expected total is a little above a single move of its cost):

| id | name | type / category | power | cost | accuracy | hits | effects | learned by |
|---|---|---|---|---|---|---|---|---|
| `twin_splash` | Twin Splash | water / special | 28 | 5 | 100 | 2-2 | `[{"op":"damage"}]` | Tidepup, Lv 15 |
| `needle_flurry` | Needle Flurry | ice / physical | 20 | 5 | 95 | 3-3 | `[{"op":"damage"}]` | Frostling, Lv 10 |
| `spark_volley` | Spark Volley | electric / special | 16 | 6 | 100 | 2-5 | `[{"op":"damage"},{"op":"apply_status","status":"shock","chance":10}]` | Voltmoth, Lv 15 |

Each has `"target": "one_enemy"` and a one-line `description` (for example "Two quick jets of water." / "Three needles of ice." / "A rapid burst of sparks that may shock.").

- [ ] **Step 1: Write the failing test** `tests/data/test_multi_hit_moves_data.gd`:

```gdscript
func test_shipped_multi_hit_moves() -> void
	# DataLoader.load_database("res://data", "res://dialogue"): no errors, no warnings; for the three ids above:
	# target one_enemy, hits_min/hits_max as in the table, a teacher with the stated level (scan db.creature(cid).learnset),
	# category and type as in the table; and the set of shipped moves with is_multi_hit() is exactly these three
func test_each_move_beats_a_single_target_move_of_its_cost_on_average() -> void
	# for each: power * mean_hits() is between 55 and 62 (a little above 55, the single-target move at cost 5-6)
```

- [ ] **Step 2: Run to verify failure** — `RUN tests/data/test_multi_hit_moves_data.gd`. Expected: FAIL (moves missing).

- [ ] **Step 3: Implement** the three move entries (matching each file's existing formatting) and the learnset lines (`{"level": 15, "move": "twin_splash"}` after Tide Beam in Tidepup's list, `{"level": 10, "move": "needle_flurry"}` before Glacier Crash in Frostling's, `{"level": 15, "move": "spark_volley"}` after Thunder Cascade in Voltmoth's). The moves are additive; no existing entry changes.

- [ ] **Step 4: Run to verify pass** — `RUN tests/data/test_multi_hit_moves_data.gd`, then `bash scripts/check.sh` (full run, includes the simulation invariants and regenerates `documentation/compendium.md`). Expected: "All checks passed."

---

### Task 6: Docs, handoff and a tour

**Files:**
- Modify: `documentation/battle-engine.md`, main spec §2.4 pointer, `documentation/developer-guide.md` (roadmap line), `.superpowers/HANDOFF.md`, `.claude/skills/run-godot-monster-catching-game/driver.gd` (mode list and header), `.claude/skills/run-godot-monster-catching-game/SKILL.md`
- Create: `.claude/skills/run-godot-monster-catching-game/tours/multihit.gd`

- [ ] **Step 1: Write the tour.** Read `tours/held.gd` and `driver.gd` first and follow their structure. `multihit.gd` starts a battle with a Voltmoth knowing Spark Volley against a 3-foe tamer or custom team, sets the first foe to 1 HP, uses the move, waits for the text line "Hit N times!", screenshots it, and asserts through `expect(...)`: a foe fainted, a second foe took damage, `HIT_COUNT` arrived. Register `multihit` in `driver.gd`'s mode list (line ~56) and header comment, and add one line to `SKILL.md`.

- [ ] **Step 2: Run the tour** with the driver, mode `multihit` (see `SKILL.md` for the exact command). Expected: ALL CHECKS PASSED, and the screenshots show the log line.

- [ ] **Step 3: Write the docs.** `documentation/battle-engine.md`: under "Targeting" add a "Multi-hit moves" section (the `hits` field, the per-hit effect rule, accuracy once, the faint-and-spill rule with a worked 3-foe example including wraparound, the attacker-faints stop, Affinity once per move, `HIT_COUNT` with its fields in the event list, and `balance.max_hits`); under "Passives and the AI" add that the AI scores a ranged move at its mean hit count and does not model the spill. The main spec's §2.4 gets a one-line pointer to the multi-hit spec. The developer guide's roadmap line and `.superpowers/HANDOFF.md` (header, an "M6c Multi-hit moves" entry with the suggested commit title "Add multi-hit moves (M6)", "What's next" now lists AI trigger modelling and the pinned rulings as the open M6 items) are updated.

- [ ] **Step 4: Final run** — `bash scripts/check.sh`. Expected: "All checks passed." Run the `battle` tour too (the existing one) to confirm no battle regression. Expected: ALL CHECKS PASSED.
