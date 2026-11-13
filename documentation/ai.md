# Battle AI

How an AI-controlled side chooses its actions: the styles (data in `data/ai_styles.json`), how moves, Rest and swaps are
scored, what the tactician values from passives, held items and triggers, and how multi-hit and two-target moves are
handled. The engine the AI plays on (round order, effects, events, tests) is in [battle-engine.md](battle-engine.md);
the code is `core/battle/ai/battle_ai.gd`. Compare styles with `tools/simulate.gd --ai=A,B` (see
[Balance simulator](battle-engine.md#balance-simulator)); the AI suites are listed in the Testing table of the engine
reference.

## Styles

Styles are data: each is an entry in `data/ai_styles.json` (category `ai_styles`, `AiStyleDef`, `Database.ai_style(id)`), a profile of weights that `BattleAI` reads. A tamer's `ai` names one; a tamer with no `ai` uses `basic`. Wild creatures are `basic`, and a side the caller controls has `ai == ""` and never reaches the AI. An unknown id asserts. Weights are 0 to 3, and 1.0 means "as the tactician does".

| Field | Meaning |
| --- | --- |
| `random` | Pick a random option, no scoring (`basic`). |
| `damage` | Weight on damage landed on foes (and the cost of hitting an ally). |
| `ko` | Weight on the knockout bonus (`ko_bonus(ref)` = `KO_FACTOR` 1.4 x the creature's best hit, so a finishing blow keeps its weight at every level) and on the knockout/faint trigger value of a finishing move. |
| `retaliation` | Weight on the hit-trigger retaliation cost of a non-lethal hit. |
| `setup` | Weight on statuses, debuffs and field-state setup (`_setup_value`). |
| `buff` | Weight on the user's own stat buffs (`_buff_value`: a positive `stat_stage` on the user or an ally is valued like the same drop on a foe). |
| `heal` | Weight on a heal effect's value. |
| `rest` | Weight on Rest's score. |
| `trigger_setup` | Multiplier on setup effects (statuses, stages, energy, cures, field states) inside trigger values; HP effects always count fully. |
| `seeks_status` | Whether a foe's `status` triggers can raise the score of inflicting a status (false: capped at 0, so it avoids a punishing status but never seeks one). |
| `attack` | `best` scores attacks by damage; `weakest` scores them by weakness (`WEAK_ATTACK_BAND` 0.5 x (1 - 0.5 x min(1, damage / `ref`)), so every attack scores 0.25 to 0.5, the weakest highest). |
| `swap`, `swap_margin`, `swap_avoid` | Whether it swaps, the margin a swap must beat the best option by (x `ref`), and the weight on the swap score's damage-avoided term. |

| Style | Behavior |
| --- | --- |
| `basic` | Random move and target. The default. |
| `aggressive` | Highest expected damage, with a bonus for knockouts. Heals when below half HP. Reads knockout, faint, status and round-end triggers, counting setup effects at half weight. |
| `tactician` | Aggressive scoring plus value for setting up reactions on the enemy side, new states its team can follow up on, statuses and debuffs. Setup values are multiples of its best available damage, so they scale with level. It avoids triggering reactions on its own side. It swaps (see below). |
| `passive` | An easier opponent. It prefers heals, buffs, Rest (weighted double), statuses and field setup, and attacks only when nothing is worth more than the weakest-hit band: then it takes its weakest damaging move, never chasing a knockout (`ko` 0). It never swaps. |
| `defensive` | Plays for survival: damage 0.7, setup 0.5, heals 1.5, Rest 1.5, retaliation 1.5. It swaps with a margin of 0.1 (the tactician's is 0.25) and counts the damage avoided 1.5 times. |
| `trickster` | Statuses, debuffs and field setup weigh 1.5 times and damage 0.6 times; a knockout still counts fully. It never swaps. |

To add or tune a style, edit `data/ai_styles.json` (all fields are required and validated); `tools/simulate.gd --ai=A,B` runs any two against each other. The heal term has a cliff at 50% HP (full value below, 0.2 above), so a style's `heal` weight shifts where a heal beats an attack only below that line.

**AI swapping (styles with `swap`).** `choose` adds one swap option per unclaimed bench creature, scored by `BattleAI.swap_score(engine, b, c, style, ref)` in the same units as a move. The score is the sum of: damage avoided (`min(threat(b), hp_b) - min(threat(c), hp_c)`, plus `ko_bonus(ref)` when `b` would be knocked out and `c` would not, times the style's `swap_avoid`; `threat(x)` is the expected damage `x` takes: each foe's best usable move, weighted by the chance it is aimed at `x`, so a single-target move counts 1/n for a side of n active creatures, `two_enemies` min(2, n)/n and spread moves in full; the "doomed" knockout bonus switches on where this average reaches `hp_b`, which is not the same as a 50% chance of being knocked out, so it can flip near that line), the bench creature's damage edge (`OFFENCE_ROUNDS` 1), `enter_value` for its enter triggers, and an escape term (negative stages are a cost removed, positive stages a loss, and a turn-skipping status counts its skip share; statuses themselves are not cleared). A swap is chosen only when it beats the best move or Rest by the style's `swap_margin` x `ref`. A creature that has not acted since it was placed by a swap or a faint replacement (`Battler.acted` is false) never swaps out, which stops ping-pong; creatures placed at battle start count as having acted. `choose_all` tracks claimed bench creatures so two actives never take the same one, and stops asking a swapper for further actions (Underdog bonus actions). A benched creature is also charged for its own turn-skipping status (a status does not tick on the bench). The bench creature is scored as it would be after the swap: `threat(c)`, `best_damage(c)` and `enter_value(c)` are computed with `c` temporarily standing in `b`'s slot (`BattleAI._with_swapped_in`, which restores everything and draws no RNG), so its own passive and held item (an absorb, say), its `field_boost`, and the auras of the allies that stay on the field all count. Not modelled: choosing a faint replacement (the engine fills the slot).

For a `two_enemies` move the AI builds one option per unordered pair of standing foes and scores the pair as a whole: the damage estimate uses the real spread count (2), the pair's knockouts and setup values add up, and the best pair wins. `basic` picks a random pair.

A multi-hit move is scored at its mean hit count: the per-hit damage estimate is multiplied by `(hits_min + hits_max) / 2`, and the tactician's retaliation cost is charged once per expected hit. The spill to another foe after a faint is not modelled.

Every AI picks only moves it can afford, falls back on Scrap, and considers Rest below 20% energy.


## What the AI values

Damage estimates already include stat, type-power, resistance, Scrap and reaction passives. On top of that:

- **Absorb (aggressive and tactician):** damage a target's `absorb_type` passive would absorb counts as 0, and the heal it gives (capped at the target's missing HP) is subtracted for a foe or added for an ally. The AI stops hitting absorbers and may hit its own.
- **Blocks (tactician):** `status_immune`, `guard_stages` and `field_shelter` zero the value of the statuses, stat drops and reaction damage they block, in moves and in reactions.
- **Overwriting a state (tactician):** at the cap, a state that doesn't react pushes out the oldest one. Knocking out a state that helps the holder is worth `REPLACE` x the best damage if the holder is the enemy and costs it if the holder is the AI's own side; knocking out a state that hurts the holder is the reverse.
- **Own passives (tactician):** `field_boost` stacks count toward a setup's reaction value, and `rest_bonus` scales Rest's value.
- **Retaliation (styles with a `retaliation` weight):** a hit that doesn't knock the target out is charged the expected cost of the target's `hit` triggers, priced by the same `BattleAI.trigger_value` as every other trigger (status, stat drop, damage on the attacker, and anything that helps the foe such as a self-heal on hit; weighted by chance and `when`; `contact` triggers need a physical move; a spent `per_battle` item costs nothing), less whatever the attacker's own passive blocks. The engine fires hit triggers after the damage, so they are priced at the HP the target is left with (an Oran Berry only costs when the hit leaves it under half), and a consumed or `per_battle` item is charged once however many hits the move has, while a passive's triggers are charged per hit.

- **Cures:** a move with a `cure_status` effect (on the move's targets, or the effect's own `target`) is worth the status value of each matching afflicted creature on the user's own side, counting only the rounds the status has left. Curing a foe's status costs the same amount; nothing to cure scores zero.
- **Other triggers (tactician and aggressive):** a trigger's effects are priced from the AI's side by `BattleAI.trigger_value` (positive helps the AI's side), weighted by `chance` and zero when its `when` fails or a `per_battle` item is spent. HP effects (`damage`, `heal`) count fully for both styles; setup effects (statuses, stat stages, energy, cures, field states) count in `ref` units, at x`AGGRESSIVE_SETUP_MULT` (0.5) for aggressive. A hostile field state landing on the AI's own side costs `NEW_STATE` x `ref` (only a trigger does that); restacking a state counts for or against by whose side it helps.
  - **`knockout`:** a move that finishes a foe gains the value of the user's own `knockout` triggers (Finisher's energy, Cold Snap's +1 Speed).
  - **`faint`:** the same move pays the target's `faint` triggers, which land on the killer (Ember Trail scorching the AI's side). A fainting holder receives nothing from its own trigger. Finishing the AI's own ally pays the faint term only.
  - **`status`:** a move that would status a foe pays that foe's `status` triggers, weighted by the status chance. For aggressive the term is capped at 0 (it avoids a punishing status but never seeks one).
  - **`round_end`:** the AI's own end-of-round healing lowers how urgent a heal move is, and a foe's lowers the credit for a hit that doesn't finish it (`BattleAI.round_end_hp`).
  - **`enter`:** not part of move scoring. `BattleAI.enter_value(engine, b, incoming, style)` prices an entry and is the entry term of `swap_score` (see "AI swapping" under Styles) (evaluated with the bench creature in place, so its held item and its `field_boost` count).

Not modelled: `status` triggers on the AI's own creatures (no move gives an ally a status), and `enter` in move scoring.

## Held items and the AI

The tactician's hit-retaliation estimate includes the target's held-item `hit` triggers (including `when` and
chance), and absorb, block and own-effect estimates read the held item through the same effect list as passives.

