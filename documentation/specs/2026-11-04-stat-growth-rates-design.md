# Species Stat Growth Rates — Design

Date: 2026-11-04
Status: Implemented (plan: [documentation/plans/2026-11-04-stat-growth-rates.md](../plans/2026-11-04-stat-growth-rates.md))
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md) §2.7 (stats), §2.10 (training points).
Builds on the [M4 progression design](2026-11-04-m4-progression-design.md). Follows the level-cap-99 and
growth/training split on the Summary (`CreatureInstance.grown`).

## 1. Goal

Today a species' base stat is the only thing that shapes its stats: `stat = 2·base·Lv/100 + 5`, so two
species with the same base stat always grow at the same rate. Give each species a **growth rate per
stat**, separate from its base stats, so a fast-growing attacker starts close to a slow one and pulls
ahead by Lv 99. Training stays the player-allocated part on top.

**Success:** a species can mark any stat as `slow` or `fast`; the stats a creature has at every level
follow from that; the Summary shows the difference between growth and training and which stats grow
fast or slow; the validator and compendium make imbalance visible; a species with no marks behaves
exactly as it does today.

### Decisions

| Topic | Decision |
|---|---|
| Model | A growth rate per stat, separate from the base stat (not explicit per-level gain tables, and not a replacement for base stats) |
| Rate form | Named tiers: `slow`, `steady`, `fast`. Missing means `steady`. |
| Where the rate enters | It multiplies the level slope only (`2·base·Lv/100`); the flat parts stay as they are |
| Balance rule | The validator warns, without failing, when a species' tiers sum above a budget |
| Evolution | The new species' rates apply to the whole level, as base stats do today |
| Saves | No change: rates are species data |
| First pass content | The 8 shipped species stay all-`steady`; marking them is a separate pass |

## 2. Data

### 2.1 Species

`data/creatures/*.json` entries get an optional field:

```json
"growth_rates": { "patk": "fast", "spd": "slow" }
```

Keys are any of the nine stats (`hp`, `patk`, `pdef`, `satk`, `sdef`, `spd`, `luck`, `resolve`,
`stamina`); values are tier ids. Unlisted stats are `steady`. (The existing `growth` field is evolution
branches, so the new field has its own name.) `CreatureDef.growth_rates` holds the dictionary;
`CreatureDef.growth_tier(stat) -> String` returns the tier id, defaulting to `"steady"`.

### 2.2 Balance

`data/balance.json` gets:

```json
"growth_tiers": { "slow": 0.8, "steady": 1.0, "fast": 1.2 },
"growth_budget": 2
```

- `growth_tiers` must contain `steady` with value `1.0` (it is the identity every missing entry uses).
  Other tiers are numbers in `0.1..3.0`.
- `growth_budget` is the warning threshold (§4).
- `BalanceDef` exposes `growth_percent(tier) -> int`, `roundi(multiplier · 100)`, so the formulas use
  integer maths and `steady` reproduces today's numbers exactly.

## 3. Formula

`Stats` takes a percent rate (default `100`):

| Function | Formula |
|---|---|
| `stat_at(base, level, pct)` | `(2·base·pct·level) / 10000 + 5` |
| `hp_at(base, level, pct)` | `(2·base·pct·level) / 10000 + level + 10` |
| `energy_at(base_stamina, level, flat, pct)` | `(2·base_stamina·pct·level) / 10000 + flat` |

(Integer division, as now.) `CreatureInstance.grown(db, stat)` looks up the species tier for the stat
and passes its percent. Training is unchanged and additive, so `grown()` still means growth only and
`max_hp`, `max_energy` and `stat` stay `grown + training`.

The Resolve resistance formula's average creature (`Stats.stat_at(50, level)`) stays `steady`.

At Lv 99:

| Base | Slow (0.8) | Steady | Fast (1.2) | Training cap |
|---|---|---|---|---|
| 50 | 84 | 104 | 123 | +30 |
| 100 | 163 | 203 | 242 | +30 |

Evolving switches to the new species' base stats and rates for the whole level; stats can jump a little
at evolution, as they do now.

## 4. Validation

- `growth_rates` keys must be known stats and values must be keys of `growth_tiers`
  (`DataSchemas` plus a reference check in `DataValidator`). These fail validation.
- **Warning, not failure:** `DataValidator.warnings(raw)` returns messages for species whose tier sum
  exceeds `growth_budget`. Each `fast` counts +1 and each `slow` −1 (`steady` 0; a tier counts by its
  position relative to `steady`: above 1.0 is +1, below is −1). `tools/validate_data.gd` prints them
  and `scripts/check.sh` shows them without failing. Errors and warnings stay separate lists.

## 5. Display

### 5.1 Summary

The Stats tab keeps `total (growth+trained)` (`Physical Attack 104 (92+12)`; an untrained stat shows
only its total). A stat whose tier is not `steady` also gets a marker after the value: `▲` for `fast`,
`▼` for `slow` (plain `+` / `-` if the font lacks the glyphs). No per-level number is shown, because
rounding makes it misleading. The cells must still fit three to a row with every stat trained and marked
(the existing `ScreenFit` test covers it).

### 5.2 Compendium

Each species lists its non-`steady` tiers, and its Lv 99 stats and total (with no training), so
imbalance is visible. Generated by `tools/generate_compendium.gd`.

## 6. Saves and migration

None. A creature stores no rate; `grown()` reads the species. Creatures whose species gain non-`steady`
tiers change stats the next time they are read, and HP and energy are clamped to the new maximums on
load, as with the level cap.

## 7. Out of scope

Per-creature random growth, explicit per-level gain tables, shared growth profiles, Luck becoming
functional, and applying tiers to the shipped species (a follow-up content pass once this is in).

## 8. Testing

- **Formula:** `steady` equals today's `stat_at`, `hp_at` and `energy_at` for a range of bases and
  levels; slow and fast match the table in §3, including HP and Stamina.
- **`grown()`:** with non-`steady` tiers, `grown + training` equals `max_hp`, `max_energy` and `stat`.
- **Regression:** every shipped creature's stats at several levels are unchanged.
- **Validator:** an unknown stat key or tier fails; an over-budget species yields a warning and does not
  fail; `growth_tiers` without `steady` (or with `steady ≠ 1.0`) fails.
- **Summary:** the split and markers appear for non-`steady` stats; the page fits the screen with all
  stats trained and marked.
- **Compendium:** it lists tiers and Lv 99 stats; `check.sh` passes.
- Docs: update §2.7 of the main spec and `battle-engine.md` where they describe the formulas.
