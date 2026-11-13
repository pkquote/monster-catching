# M6g AI styles: design

Status: Draft, 2026-11-12 (revised: styles are data). Part of M6 (engine backlog) in the
[roadmap](2026-11-05-roadmap-m5-m8.md). Builds on [M6e](2026-11-12-m6e-ai-trigger-modelling-design.md) (the
trigger valuators) and [M6f](2026-11-12-m6f-ai-swapping-design.md) (`swap_score`, tactician-only swapping). Engine
facts are in the [battle engine reference](../battle-engine.md).

## 1. Goal and context

The AI has three styles: `basic` (random), `aggressive` (damage and knockouts) and `tactician` (aggressive plus setup,
retaliation and, since M6f, swapping). The scoring code branches on the style **name** in many places. This piece makes a
style **data**: a new content category, `ai_styles` (`data/ai_styles.json`), whose entries are weight profiles that the
existing scoring reads. All styles, the existing three included, become entries (approach A, chosen by the user; data
files chosen by the user on 2026-11-12). Three new styles are then added as entries:

| Style | Idea |
|---|---|
| `passive` | An easier opponent. It avoids attacking: it prefers heals, buffs and Rest, and when it has nothing worth doing it takes its **weakest** damaging move (decided with the user, 2026-11-12) |
| `defensive` | Survival: heals and Rest earlier, weighs the damage it would take, and swaps out of danger more readily |
| `trickster` | Statuses, debuffs and field setup first; damage is secondary |

`basic` is the default style: a tamer with no `ai` field uses it.

## 2. Decisions

| Topic | Decision |
|---|---|
| Home | New category `ai_styles`, stored as one file `data/ai_styles.json` (`"file"` category, like `statuses`), schema-validated, loaded into `Database` as `AiStyleDef`, listed in the compendium. Styles are tuned and added without code |
| Existing styles | `basic`, `aggressive` and `tactician` become entries whose weights reproduce today's behavior exactly. They choose exactly as before. Proof: every existing AI test passes unchanged, and `tools/simulate.gd` output is identical before and after the refactor (2v2, 200 battles, seed 1, four runs listed in the plan) |
| Default | The tamer `ai` field becomes optional and a reference to `ai_styles` (replacing the fixed enum). A tamer without it uses `basic` (`TamerDef.ai` defaults to `"basic"`). A side the caller controls still has `ai == ""` and never reaches the AI. Existing tamer data is not edited |
| Unknown id | A style id missing from the database asserts (data validation makes it impossible for tamers; `tools/simulate.gd` rejects an unknown `--ai=` name) |
| Own buffs | New term `_buff_value`: a positive `stat_stage` on the user or its allies, valued like a debuff (`DEBUFF_VALUE[stat] x ref x stages`). Its weight is 0 for `aggressive` and `tactician`, so they are unchanged |
| `passive` attacks | Damaging options are not scored by damage. Each is scored by how **weak** it is (a lower estimated damage is better, in a small band of 0.25 to 0.5), and any non-attack option worth more than the band beats every attack. So it attacks only when nothing else is worth doing, and then with its weakest damaging move (the fallback Scrap counts) |
| Swapping | An entry field enables it. `tactician` and `defensive` swap; `defensive` with a lower margin and a heavier damage-avoided term |
| Wild creatures | Stay `basic` (the launcher still passes it). The launcher's "Sparring Partner" stays `tactician` |
| Randomness | None. Scoring never draws from `engine.rng` (as M6e and M6f) |

## 3. The profile (an `ai_styles` entry)

An entry is `{id, name, description, ...fields}`. All fields are required. `1.0` means "as the tactician does today".

| Field | Type, range | Meaning |
|---|---|---|
| `random` | bool | Choose a random option, no scoring (`basic`) |
| `damage` | number 0 to 3 | Weight on damage landed on foes (and the cost of hitting an ally) |
| `ko` | number 0 to 3 | Weight on `KO_BONUS` and on the knockout/faint trigger value of a finishing move |
| `retaliation` | number 0 to 3 | Weight on the hit-trigger retaliation cost of a non-lethal hit |
| `setup` | number 0 to 3 | Weight on `_setup_value` (statuses, debuffs, field states) |
| `buff` | number 0 to 3 | Weight on `_buff_value` (own stat buffs, new) |
| `heal` | number 0 to 3 | Weight on a heal effect's value |
| `rest` | number 0 to 3 | Weight on `rest_score` |
| `trigger_setup` | number 0 to 3 | The multiplier M6e's `trigger_value` applies to setup effects (statuses, stages, energy, cures, field states) |
| `seeks_status` | bool | Whether a foe's `status` triggers can raise the score of inflicting a status (false: capped at 0, M6e's aggressive rule) |
| `attack` | enum `best`, `weakest` | Score attacks by damage, or by weakness: `WEAK_ATTACK_BAND` x (1 - 0.5 x min(1, estimated damage / `ref`)), a range of 0.25 to 0.5 |
| `swap` | bool | Swapping enabled |
| `swap_margin` | number 0 to 3 | `SWAP_MARGIN` for this style, x `ref` |
| `swap_avoid` | number 0 to 3 | Weight on `swap_score`'s damage-avoided term (including its knockout bonus) |

The refactor replaces the string comparisons (`style == "tactician"`, `style != "basic"`, M6e's `AGGRESSIVE_SETUP_MULT`
check, M6f's tactician gate) with reads of these fields.

### The six entries (first values; all are tuned with the simulator)

| Field | basic | aggressive | tactician | passive | defensive | trickster |
|---|---|---|---|---|---|---|
| `random` | true | false | false | false | false | false |
| `damage` | 1.0 | 1.0 | 1.0 | 1.0 | 0.7 | 0.6 |
| `ko` | 1.0 | 1.0 | 1.0 | 0.0 | 1.0 | 1.0 |
| `retaliation` | 1.0 | 0.0 | 1.0 | 1.0 | 1.5 | 1.0 |
| `setup` | 1.0 | 0.0 | 1.0 | 1.0 | 0.5 | 1.5 |
| `buff` | 0.0 | 0.0 | 0.0 | 1.0 | 0.5 | 0.5 |
| `heal` | 1.0 | 1.0 | 1.0 | 1.5 | 1.5 | 1.0 |
| `rest` | 1.0 | 1.0 | 1.0 | 2.0 | 1.5 | 1.0 |
| `trigger_setup` | 1.0 | 0.5 | 1.0 | 1.0 | 1.0 | 1.0 |
| `seeks_status` | true | false | true | true | true | true |
| `attack` | best | best | best | weakest | best | best |
| `swap` | false | false | true | false | true | false |
| `swap_margin` | 0.25 | 0.25 | 0.25 | 0.25 | 0.1 | 0.25 |
| `swap_avoid` | 1.0 | 1.0 | 1.0 | 1.0 | 1.5 | 1.0 |

(`basic`'s row is neutral: it is never scored, so its other fields are never read.)

- **passive.** Heals, buffs, Rest, statuses, debuffs and field setup score as the tactician does, with the weights
  above. An attack scores `WEAK_ATTACK_BAND x (1 - 0.5 x min(1, estimated damage / ref))` (a range of 0.25 to 0.5 HP-equivalent, so the
  weakest scores highest and a pointless move worth 0 loses to every attack), a non-lethal hit pays retaliation as
  usual, and any option whose weighted value is above the band wins before an attack is considered. With nothing
  worth doing it takes the weakest damaging move. It never swaps.
- **defensive.** Scores like the tactician with damage and setup down-weighted and heals, Rest and retaliation
  up-weighted. It swaps with the same `swap_score` but counts the damage avoided 1.5 times and needs only a 0.1 margin,
  so it leaves a losing matchup sooner.
- **trickster.** Statuses, debuffs and field setup weigh 1.5 times, damage 0.6 times, and the knockout bonus stays 1.0,
  so a status that costs a foe several turns beats a mediocre hit but a finishing blow still wins.

## 4. Where the profile is read

`BattleAI` resolves a style with `engine.db.ai_style(id)` (an `AiStyleDef`) and reads it in `choose` and `score` (heal
branch, effects loop, damage branch, setup, retaliation, knockout term), `rest_score`, `_best_swap` and `swap_score`
(margin and avoided-damage weight), and `trigger_value` (`trigger_setup`). `choose` builds its options as today.

## 5. Data, tools and tests

- **Data layer:** `ai_styles` joins `DataSchemas.CATEGORIES` (`"file"`) with a schema for the fields above;
  `AiStyleDef` (`core/data/defs/ai_style_def.gd`); `Database` builder and `ai_style(id)` accessor;
  `data/ai_styles.json` with the six entries; a compendium section; `FixtureDB.raw()` adds the six entries read from
  the shipped file, so tests run on the real weights.
- **Tamers:** the schema's `ai` becomes `{"t": "ref", "cat": "ai_styles", "opt": true}`; `TamerDef.ai` defaults to
  `"basic"`.
- `tools/simulate.gd`: its comment and help list the ids from the database; it rejects an unknown name.
- `data_testpack/tamers/tp_tamers.json`: one tamer per new style, one tamer with no `ai` (to cover the default); the pack
  simulation's style rotation includes the new styles (it rotates through basic, tactician and aggressive today). No
  shipped (`data/`) tamer changes.
- Docs: "AI styles" in `documentation/battle-engine.md` gets the profile table and the three styles; the data
  reference (and the developer guide, wherever categories are listed) gains `ai_styles`; the test table gains the new
  files; the HANDOFF records the piece.

### Tests

New `tests/battle/test_ai_styles.gd` and `tests/data/test_ai_styles_data.gd`:

1. Data: the shipped file validates; it has the six ids; every entry has every field with in-range values; the six
   rows equal the table above, field by field; `Database.ai_style` returns an `AiStyleDef`; the validator rejects an
   entry missing a field, a weight out of range, and a bad `attack`; a tamer's `ai` naming an unknown style is rejected;
   a tamer without `ai` loads with `ai == "basic"`.
2. Behavior pins: for a fixed set of fixtures (damage, heal, status, debuff, field setup, trigger and swap cases from the
   existing AI suites), `choose` for `aggressive`, `tactician` and `basic` equals its pre-refactor result.
3. `buff`: a self-buff move scores above 0 for `passive` and 0 for the tactician; weighted by the profile.
4. `passive`: with a heal below half HP it heals; with a buff and a hit it buffs; with only attacks it picks the weakest
   (not the strongest, not a knockout); at low energy it prefers Rest; it never swaps; scoring draws no RNG.
5. `defensive`: heals and Rests at a higher HP than the tactician; a swap the tactician declines (gap inside 0.25 x `ref`
   but over 0.1) it takes; retaliation costs more.
6. `trickster`: prefers a status or debuff over a same-damage hit; still takes a knockout over a status.

The existing AI suites, the pack suites and `check.sh` pass unchanged. A simulator run records, for 2v2 at levels 10
and 40, every pair of new style against `tactician` and `basic` (200 battles, seed 1): win shares and average rounds.
**Targets** (reported, tuned if missed): `passive` wins at most 40% against `tactician`; `defensive` and `trickster`
each between 35% and 65% against `tactician`; no style draws more than 2% of its battles. A missed target is tuned by
number and reported, not silently relaxed.

## 6. Not changed

The engine; the shipped tamers and the launcher (wild `basic`, Sparring Partner `tactician`); M6e's trigger valuators
and M6f's swap scoring except for reading weights from the profile. No per-tamer overrides of a profile (a tamer
picks one style id).

## 7. Risks

- **Refactor drift.** Touching every style branch can change `aggressive` or `tactician` silently. The identical simulator
  output and the unchanged suites are the guard; the refactor is built and verified before any new style is added.
- **New content category.** A category touches the loader, schemas, validator, database, compendium and fixtures. The
  plan builds it first with the existing three styles only, behind passing suites, and runs `check.sh` before the
  refactor starts.
- **Passive that looks broken.** A style that avoids attacking can stall a battle (both sides buffing). The round limit
  already ends battles; the draw rate is a target, and `passive` always has Scrap, so it keeps attacking when nothing
  else is worth doing.
- **Tuning numbers.** All first values are guesses; they are now data, so tuning is an edit to the JSON.
- **Currency.** The new `buff` term reuses `DEBUFF_VALUE` (stages are worth the same up or down), which a simulator pass
  may show to be too generous.
