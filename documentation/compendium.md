# Content Compendium

> Generated from `data/` by `tools/generate_compendium.gd`. Do not edit by hand;
> change the JSON and regenerate.

| Section | Count |
|---|---|
| [Rules and Balance](#rules-and-balance) | — |
| [Types](#types) | 14 |
| [Affinities](#affinities) | 4 |
| [Statuses](#statuses) | 4 |
| [Field States](#field-states) | 12 |
| [Reactions](#reactions) | 8 |
| [Passives](#passives) | 19 |
| [Held items](#held-items) | 5 |
| [Moves](#moves) | 50 |
| [Items](#items) | 7 |
| [Creatures](#creatures) | 12 |
| [Tamers](#tamers) | 4 |
| [Encounters](#encounters) | 2 |
| [Achievements](#achievements) | 11 |

## Rules and Balance

Global rules and tuning values from `data/balance.json`. The sections after this one refer to them.

| Setting | Value |
|---|---|
| Level cap | 99 |
| Party size | 6 |
| Battle format | Up to 3 active a side; in tamer battles the tamer's *Max active* sets it and the player may field fewer; in wild battles the pack size sets the foe side |
| Max moves per creature | 4 |
| Turn order | Fleeing (wild battles only), then swaps, then items, then moves by *Pri* (higher first, default 0); ties go to the faster creature, then at random |
| Same-type attack bonus | x1.25 |
| Round limit (draw) | 200 |
| XP formula | yield x level / 5, x1.5 vs tamers |
| Catch status bonus | x1.5 |
| Max field states per side | 1 |
| Growth Affinity threshold | 30 |
| Growth tiers | Slow x0.8, Steady x1, Fast x1.2 on a stat's per-level growth |
| Growth tier budget | 2 (each faster stat counts +1, each slower one -1) |
| Catch HP weight | 0.8 |
| Resolve resist cap | 30% (average creature: half that) |
| Resolve endure cap | 10%, once per battle |
| Energy pool | 2 x base Stamina x Lv / 100 + 20 |
| Rest restores | 25% of max energy |
| Training points | 1 per level, max 30 per stat, +2 HP per point |

### Multi-target damage

A move that hits more than one creature deals less to each. *Two foes* moves hit two foes the user picks (one foe left standing takes full damage); *All enemies*, *All allies* and *Everyone* count every creature they hit. An outnumbered side takes less of it (see [Underdog](#underdog)).

| Creatures hit | Damage to each |
|---|---|
| 1 | x1 |
| 2 | x0.85 |
| 3 or more | x0.75 |

### Underdog

A side is *outnumbered* when the foes have more creatures active. Its *step* is foes active / own active - 1 (1 vs 2 is 1, 1 vs 3 is 2). Per step it gets 0.5 extra actions per creature each round (rounded down), P.Atk, P.Def, S.Atk, S.Def +15% (max 15%), 20% less spread damage taken (max 50%) and, on the player's side, 50% more XP. Passive `when` conditions that say *outnumbered* test the same rule.

| Format | Step | Extra actions | Stat bonus | Spread damage taken | XP bonus |
|---|---|---|---|---|---|
| 1 vs 2 | 1 | 0 | +15% | -20% | +50% |
| 1 vs 3 | 2 | 1 | +15% | -40% | +100% |
| 2 vs 3 | 0.5 | 0 | +7.5% | -10% | +25% |

### Bond

Range -100 to 100; starters begin at 20.

| Effect | At most |
|---|---|
| Disobey chance (negative Bond) | 40% at -100 |
| Accuracy and damage penalty | 20% at -100 |
| Lash out chance | 5% at -50 or below |
| XP bonus (positive Bond) | 10% at 100 |

| Happening | Bond |
|---|---|
| Battle Won | +2 |
| Knockout | +1 |
| Healed Item | +1 |
| Rested | +2 |
| Fainted | -4 |
| Overworked | -2 |

### Affinity awards

| Happening | Affinity | Points |
|---|---|---|
| Hit Dealt | Striker | 1 |
| Knockout | Striker | 3 |
| Hit Survived | Warden | 1 |
| Heal | Warden | 2 |
| Field Applied | Catalyst | 2 |
| Reaction Triggered | Catalyst | 4 |
| Field Cashed In | Catalyst | 1 |
| Status Inflicted | Trickster | 2 |
| Stat Lowered | Trickster | 1 |

## Types

14 types. Creatures can have up to 2, giving 105 possible single and dual types; 11 are in use so far.

### Type guide

*Pros* and *cons* are written in `data/types.json`. The matchup lines are computed from the chart below.

#### Neutral

*A blank slate. Ordinary creatures relying on plain strength and instinct, neither strong nor weak against anything.*

- **Pros:** Never resisted: hits every type for normal damage; No weaknesses at all; Pairs with any second type without adding weaknesses or changing matchups
- **Cons:** Never hits anything for bonus damage; Resists nothing
- **Hits hard:** —
- **Hits weakly:** —
- **Weak to:** —
- **Resists:** —
- **Creatures:** —

#### Fire

*Heat, flame and fury. Burns living things and melts metal.*

- **Pros:** Strong against Grass, Ice and Iron; Resists Fire, Grass, Ice and Iron; Natural fit for Scorched-field setups
- **Cons:** Weak to Water and Earth; Fizzles against Water, Earth and other Fire
- **Hits hard:** Grass, Ice, Iron
- **Hits weakly:** Fire, Water, Earth
- **Weak to:** Water, Earth
- **Resists:** Fire, Grass, Ice, Iron
- **Creatures:** Emberkit, Blazefox, Cinderwisp

#### Water

*Tides, rain and pressure. Quenches flame, erodes stone and shorts out machines.*

- **Pros:** Strong against Fire, Earth and Virtual; Resists Fire, Water and Iron; Sets up Soaked for Conduction and Icebound
- **Cons:** Weak to Grass and Electric; Absorbed by Grass and other Water
- **Hits hard:** Fire, Earth, Virtual
- **Hits weakly:** Water, Grass
- **Weak to:** Grass, Electric
- **Resists:** Fire, Water, Iron
- **Creatures:** Tidepup, Torrentusk, Mistcoil

#### Grass

*Roots, vines and growth. Drinks water and splits stone, but burns easily.*

- **Pros:** Strong against Water and Earth; Resists Water, Grass, Electric and Earth; Overgrown fields slow the enemy and fuel Wildfire
- **Cons:** Weak to Fire and Ice; Can't cut through Fire, Grass or Iron
- **Hits hard:** Water, Earth
- **Hits weakly:** Fire, Grass, Iron
- **Weak to:** Fire, Ice
- **Resists:** Water, Grass, Electric, Earth
- **Creatures:** Sprigling, Thornwall, Mossweaver

#### Electric

*Lightning and current. Races through water and metal, and overloads machines.*

- **Pros:** Strong against Water, Iron and Virtual; Resists Electric, Iron and Virtual; Triggers Conduction on Soaked fields
- **Cons:** Weak to Earth; Has no effect at all on Earth; Dissipates into Grass and other Electric
- **Hits hard:** Water, Iron, Virtual
- **Hits weakly:** Grass, Electric
- **No effect on:** Earth
- **Weak to:** Earth
- **Resists:** Electric, Iron, Virtual
- **Creatures:** Voltmoth

#### Ice

*Frost and cold. Freezes plants and cracks the ground, but melts under heat.*

- **Pros:** Strong against Grass and Earth; Resists Ice; Frosted fields set up Icebound and Steam
- **Cons:** Weak to Fire and Iron; Struggles against Fire, Ice and Iron
- **Hits hard:** Grass, Earth
- **Hits weakly:** Fire, Ice, Iron
- **Weak to:** Fire, Iron
- **Resists:** Ice
- **Creatures:** Frostling, Mistcoil

#### Earth

*Stone, sand and soil. Grounds lightning, smothers fire and crushes metal.*

- **Pros:** Strong against Fire, Electric and Iron; Immune to Electric; Resists Fire
- **Cons:** Weak to Water, Grass and Ice; Can't touch what isn't solid: weak against Ghost and Grass
- **Hits hard:** Fire, Electric, Iron
- **Hits weakly:** Grass, Ghost
- **Weak to:** Water, Grass, Ice
- **Resists:** Fire
- **Immune to:** Electric
- **Creatures:** Pebblet, Thornwall, Torrentusk

#### Magic

*Arcane power, runes and enchantment. Banishes spirits and wards off darkness.*

- **Pros:** Strong against Ghost and Dark; Resists Magic, Dark and Virtual
- **Cons:** Weak to Mental and Iron (focus breaks spells; cold iron grounds them); Can't overcome Iron, Virtual or other Magic
- **Hits hard:** Ghost, Dark
- **Hits weakly:** Magic, Iron, Virtual
- **Weak to:** Mental, Iron
- **Resists:** Magic, Virtual, Dark
- **Creatures:** —

#### Mental

*Psychic force, willpower and illusion. Overwhelms simple minds and disrupts spellcasting.*

- **Pros:** Strong against Magic and Ghost; Resists Mental
- **Cons:** Weak to Ghost, Dark and Virtual: fragile defensively; Mental and Ghost are each strong against the other; Little effect on Iron, Dark, Virtual or other Mental
- **Hits hard:** Magic, Ghost
- **Hits weakly:** Mental, Iron, Virtual, Dark
- **Weak to:** Virtual, Ghost, Dark
- **Resists:** Mental
- **Creatures:** —

#### Iron

*Metal, armour and machinery. A defensive wall that shatters ice and grounds magic.*

- **Pros:** Resists Grass, Ice, Magic, Mental, Dark, Light and Iron; Strong against Ice and Magic
- **Cons:** Weak to Fire, Electric, Earth and Virtual; Few offensive targets; struggles against Fire, Water, Electric and Iron
- **Hits hard:** Ice, Magic
- **Hits weakly:** Fire, Water, Electric, Iron
- **Weak to:** Fire, Electric, Earth, Virtual
- **Resists:** Grass, Ice, Magic, Mental, Iron, Dark, Light
- **Creatures:** —

#### Virtual

*Digital constructs and living code. Hacks machines and floods minds with data.*

- **Pros:** Strong against Iron and Mental; Resists Magic, Mental and Virtual
- **Cons:** Weak to Water, Electric and Ghost (shorts, surges, and things in the machine); Can't parse Magic; weak against Electric, Ghost and other Virtual
- **Hits hard:** Mental, Iron
- **Hits weakly:** Electric, Magic, Virtual, Ghost
- **Weak to:** Water, Electric, Ghost
- **Resists:** Magic, Mental, Virtual
- **Creatures:** —

#### Ghost

*Spirits and echoes of the departed. Haunts minds and possesses machines; hard to pin down.*

- **Pros:** Strong against Mental and Virtual; Resists Earth and Virtual
- **Cons:** Weak to Magic, Light and Mental: Mental and Ghost are each strong against the other; Fades against Dark and Light
- **Hits hard:** Mental, Virtual
- **Hits weakly:** Dark, Light
- **Weak to:** Magic, Mental, Light
- **Resists:** Earth, Virtual
- **Creatures:** Cinderwisp, Mossweaver

#### Dark

*Shadow, stealth and fear. Clouds the mind and swallows light.*

- **Pros:** Strong against Mental and Light; Resists Mental, Ghost and Dark
- **Cons:** Weak to Magic and Light; Held back by Magic wards, Iron and other Dark
- **Hits hard:** Mental, Light
- **Hits weakly:** Magic, Iron, Dark
- **Weak to:** Magic, Light
- **Resists:** Mental, Ghost, Dark
- **Creatures:** —

#### Light

*Radiance and purity. Dispels shadows and spirits, but glances off polished metal.*

- **Pros:** Strong against Dark and Ghost; Resists Ghost and Light; Only one weakness
- **Cons:** Weak to Dark: Light and Dark are each strong against the other; Only two offensive targets; Iron and other Light resist it
- **Hits hard:** Ghost, Dark
- **Hits weakly:** Iron, Light
- **Weak to:** Dark
- **Resists:** Ghost, Light
- **Creatures:** —

### Type chart

Damage multiplier when the **row** type attacks the **column** type. Blank means x1.

| Attacker \ Defender | Neutral | Fire | Water | Grass | Electric | Ice | Earth | Magic | Mental | Iron | Virtual | Ghost | Dark | Light |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Neutral** |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| **Fire** |  | x0.5 | x0.5 | x2 |  | x2 | x0.5 |  |  | x2 |  |  |  |  |
| **Water** |  | x2 | x0.5 | x0.5 |  |  | x2 |  |  |  | x2 |  |  |  |
| **Grass** |  | x0.5 | x2 | x0.5 |  |  | x2 |  |  | x0.5 |  |  |  |  |
| **Electric** |  |  | x2 | x0.5 | x0.5 |  | x0 |  |  | x2 | x2 |  |  |  |
| **Ice** |  | x0.5 |  | x2 |  | x0.5 | x2 |  |  | x0.5 |  |  |  |  |
| **Earth** |  | x2 |  | x0.5 | x2 |  |  |  |  | x2 |  | x0.5 |  |  |
| **Magic** |  |  |  |  |  |  |  | x0.5 |  | x0.5 | x0.5 | x2 | x2 |  |
| **Mental** |  |  |  |  |  |  |  | x2 | x0.5 | x0.5 | x0.5 | x2 | x0.5 |  |
| **Iron** |  | x0.5 | x0.5 |  | x0.5 | x2 |  | x2 |  | x0.5 |  |  |  |  |
| **Virtual** |  |  |  |  | x0.5 |  |  | x0.5 | x2 | x2 | x0.5 | x0.5 |  |  |
| **Ghost** |  |  |  |  |  |  |  |  | x2 |  | x2 |  | x0.5 | x0.5 |
| **Dark** |  |  |  |  |  |  |  | x0.5 | x2 | x0.5 |  |  | x0.5 | x2 |
| **Light** |  |  |  |  |  |  |  |  |  | x0.5 |  | x2 | x2 | x0.5 |

## Affinities

Growth tracks filled by how a creature is used in battle (points per happening are in [Rules and Balance](#rules-and-balance)). Growth branches need at least 30 points in the matching track, and the first track to reach 30 unlocks the species' Affinity passive for that track (see [Passives](#passives)).

| Affinity | Id | Grows from |
|---|---|---|
| **Catalyst** | `catalyst` | Grows from shaping the field and triggering reactions. |
| **Striker** | `striker` | Grows from dealing damage and landing finishing blows. |
| **Trickster** | `trickster` | Grows from statuses, debuffs, and making foes miss. |
| **Warden** | `warden` | Grows from absorbing hits, healing, and protecting allies. |

## Statuses

Conditions on a single creature. Each lasts a set number of rounds.

| Status | Id | Rounds | Effect | Description |
|---|---|---|---|---|
| **Burn** | `burn` | 4 | Loses 6.25% max HP each round | Loses a little HP each round. |
| **Chill** | `chill` | 3 | Spd x0.75 | Speed is reduced. |
| **Daze** | `daze` | 3 | Acc x0.8 | Accuracy is reduced. |
| **Shock** | `shock` | 3 | 25% chance to lose its action | May lose its action to muscle spasms. |

## Field States

Held per side (max 1 at once). Passive effects apply to every creature on that side.

| State | Id | Max stacks | Default rounds | Passive | Reacts with |
|---|---|---|---|---|---|
| **Charged** | `charged` | 3 | 3 | Electric damage taken x1.15 | Soaked → Conduction, Glitched → Overload, Magnetized → Railstorm |
| **Enchanted** | `enchanted` | 3 | 4 | S.Def x1.15 | — |
| **Frosted** | `frosted` | 3 | 4 | Acc x0.95 | Soaked → Icebound, Scorched → Steam |
| **Glitched** | `glitched` | 3 | 3 | Virtual damage taken x1.2; Resolve x0.9 | Charged → Overload |
| **Haunted** | `haunted` | 3 | 4 | Resolve x0.8; Ghost damage taken x1.15 | Hazed → Nightmare |
| **Hazed** | `hazed` | 3 | 3 | S.Def x0.9; Mental damage taken x1.2 | Haunted → Nightmare |
| **Magnetized** | `magnetized` | 3 | 4 | Spd x0.9; Electric damage taken x1.15 | Charged → Railstorm |
| **Overgrown** | `overgrown` | 3 | 5 | Spd x0.9 | Scorched → Wildfire |
| **Radiant** | `radiant` | 3 | 4 | Dark damage taken x0.75; Ghost damage taken x0.75; Acc x1.1 | Shrouded → Eclipse |
| **Scorched** | `scorched` | 3 | 3 | Grass damage taken x1.2; Ice damage taken x1.2 | Frosted → Steam, Overgrown → Wildfire |
| **Shrouded** | `shrouded` | 3 | 3 | Acc x0.85 | Radiant → Eclipse |
| **Soaked** | `soaked` | 3 | 4 | Electric damage taken x1.25; Fire damage taken x0.75 | Charged → Conduction, Frosted → Icebound |

- **Charged:** Static crackles in the air.
- **Enchanted:** Glowing runes ward this side against spells and beams. Cast it on your own side.
- **Frosted:** Rime coats the ground. Footing is poor.
- **Glitched:** Corrupted data flickers across this side. Code finds its way in.
- **Haunted:** Restless spirits whisper here, wearing down the will to resist.
- **Hazed:** A psychic fog dulls every mind on this side.
- **Magnetized:** Iron filings cling to everything, weighing creatures down and drawing in current.
- **Overgrown:** Tangled growth slows everyone on this side.
- **Radiant:** Warm light bathes this side, sharpening aim and burning away shadow. Cast it on your own side.
- **Scorched:** Embers smoulder underfoot. Grass and ice suffer.
- **Shrouded:** Thick shadow makes it hard to see what you're aiming at.
- **Soaked:** Ground is flooded. Electric hits harder here, fire fizzles.

## Reactions

Fire immediately when an incoming state meets one already on that side. "All allies" means every creature on the side where the reaction fired.

| Reaction | Inputs | Consumes | Scope | Effects |
|---|---|---|---|---|
| **Conduction** | Charged + Soaked | Charged | That side | Damage (power 60 Electric), scales with stacks consumed → all allies; Inflicts Shock (30%) → all allies |
| **Eclipse** | Shrouded + Radiant | Shrouded, Radiant | Both sides | Inflicts Daze (50%) → everyone |
| **Icebound** | Soaked + Frosted | Soaked | That side | Spd -2 → all allies; Inflicts Chill → all allies |
| **Nightmare** | Haunted + Hazed | Hazed | That side | Damage (power 45 Mental), scales with stacks consumed → all allies; Resolve -2 → all allies |
| **Overload** | Glitched + Charged | Glitched, Charged | That side | Damage (power 45 Virtual), scales with stacks consumed → all allies; Inflicts Shock (40%) → all allies |
| **Railstorm** | Magnetized + Charged | Magnetized | That side | Damage (power 55 Electric), scales with stacks consumed → all allies |
| **Steam** | Scorched + Frosted | Scorched, Frosted | Both sides | Acc -1 → everyone |
| **Wildfire** | Scorched + Overgrown | Overgrown | That side | Damage (power 45 Fire), scales with stacks consumed → all allies; Inflicts Burn → all allies |

- **Conduction:** Current races through the water, shocking everyone standing in it.
- **Eclipse:** Light and shadow collide, and the whole field goes dark and dazzling at once.
- **Icebound:** Standing water freezes solid around their feet.
- **Nightmare:** The spirits slip into fogged minds and the haze turns into terror.
- **Overload:** A surge hits corrupted data and everything shorts out at once.
- **Railstorm:** Current arcs through the magnetized filings, flinging them like shrapnel.
- **Steam:** A scalding cloud blankets the whole battlefield.
- **Wildfire:** The undergrowth catches. Everything on this side burns.

## Passives

Every creature has two passive slots. Its *rolled* passive is picked at random from its species' list (*Species* shows the name alone); its *Affinity* passive unlocks when its first Affinity track reaches 30 points (*Species* shows the track in brackets). Only the active slot works; the player picks it on the Summary screen. *Self* passives' effects apply only to their holder; *Aura* passives apply their effects to every active creature on the holder's side (the same aura does not stack). A trigger reads *On event (physical) (chance) [when]*: (physical) means only physical moves set it off, the percentage is its chance to fire, and it is skipped when it would only heal or restore a creature that is already full. *Overworld* effects apply while the creature leads the party (first in the party, fainted or not). A `when` condition is shown in brackets.

| Passive | Id | Scope | Effects | Triggers | Overworld | Species |
|---|---|---|---|---|---|---|
| **Bulwark Hide** | `bulwark_hide` | Self | Earth damage taken x0.7; Foes can't lower its P.Def | — | — | Torrentusk |
| **Chill Skin** | `chill_skin` | Self | — | On being hit (physical) (30%): Inflicts Chill | — | Mistcoil, Mossweaver |
| **Cold Snap** | `cold_snap` | Self | — | On a knockout: Spd +1 | XP earned x1.1 | Blazefox, Frostling |
| **Ember Trail** | `ember_trail` | Self | — | On fainting: Applies Scorched to the enemy side | — | Cinderwisp, Emberkit |
| **Finisher** | `finisher` | Self | Scrap x1.5 | On a knockout: Restores 15% max energy | — | Blazefox (Striker), Cinderwisp (Striker), Emberkit (Striker), Frostling (Striker), Mistcoil (Striker), Mossweaver (Striker), Pebblet (Striker), Sprigling (Striker), Thornwall (Striker), Tidepup (Striker), Torrentusk (Striker), Voltmoth (Striker) |
| **Fog Weaver** | `fog_weaver` | Self | Its field states get +1 round(s) | — | — | Cinderwisp, Mistcoil |
| **Frost Guard** | `frost_guard` | Self | Can't be given Chill; Ice damage taken x0.5 | — | — | Frostling |
| **Guardian Aura** | `guardian_aura` | Aura | All damage taken x0.9 | — | — | Blazefox (Warden), Cinderwisp (Warden), Emberkit (Warden), Frostling (Warden), Mistcoil (Warden), Mossweaver (Warden), Pebblet (Warden), Sprigling (Warden), Thornwall (Warden), Tidepup (Warden), Torrentusk (Warden), Voltmoth (Warden) |
| **Kindling** | `kindling` | Self | Fire moves x1.5 [HP below 34%] | — | — | Blazefox, Emberkit |
| **Lightning Rod** | `lightning_rod` | Self | Electric damage heals 25% max HP instead | — | — | Voltmoth |
| **Photosynth** | `photosynth` | Self | — | On round end: Heals 6.25% max HP | Bond gains x1.25 | Sprigling, Thornwall |
| **Reaction Spark** | `reaction_spark` | Self | Reactions it triggers x1.3; Its field states get +1 stack(s) | — | — | Blazefox (Catalyst), Cinderwisp (Catalyst), Emberkit (Catalyst), Frostling (Catalyst), Mistcoil (Catalyst), Mossweaver (Catalyst), Pebblet (Catalyst), Sprigling (Catalyst), Thornwall (Catalyst), Tidepup (Catalyst), Torrentusk (Catalyst), Voltmoth (Catalyst) |
| **Rootbed** | `rootbed` | Self | Can't be given Daze | On entering: Applies Overgrown to own side | — | Mossweaver, Sprigling |
| **Rubble Pile** | `rubble_pile` | Self | P.Def x1.3 [outnumbered] | — | — | Pebblet |
| **Slippery** | `slippery` | Self | Can't be given a status; Rest restores +15% max energy | — | — | Blazefox (Trickster), Cinderwisp (Trickster), Emberkit (Trickster), Frostling (Trickster), Mistcoil (Trickster), Mossweaver (Trickster), Pebblet (Trickster), Sprigling (Trickster), Thornwall (Trickster), Tidepup (Trickster), Torrentusk (Trickster), Voltmoth (Trickster) |
| **Static Wings** | `static_wings` | Self | Electric moves cost 2 less | — | — | Voltmoth |
| **Sturdy** | `sturdy` | Self | Foes can't lower its stats | — | — | Pebblet, Thornwall |
| **Tidal Heart** | `tidal_heart` | Self | Water moves x1.2 | — | — | Tidepup, Torrentusk |
| **Undertow** | `undertow` | Self | — | On entering: Applies Soaked to the enemy side | Wild encounter rate x0.8 | Tidepup |

- **Bulwark Hide:** Takes 30% less Earth damage. Foes can't lower its Physical Defense.
- **Chill Skin:** When hit by a physical move, 30% chance to Chill the attacker.
- **Cold Snap:** On a knockout, +1 Speed. Earns 10% more XP while it leads.
- **Ember Trail:** When it faints, scorches the enemy side.
- **Finisher:** On a knockout, restores 15% energy. Scrap hits 50% harder.
- **Fog Weaver:** Field states it applies last 1 round longer.
- **Frost Guard:** Can't be Chilled. Takes half damage from Ice.
- **Guardian Aura:** Allies on the field take 10% less damage from moves.
- **Kindling:** Below a third of its HP, Fire moves hit 50% harder.
- **Lightning Rod:** Electric damage heals it for 25% of its HP instead.
- **Photosynth:** Heals 1/16 of its HP at the end of each round. Bond gains are 25% larger while it leads.
- **Reaction Spark:** Reactions it triggers deal 30% more. Its field states gain +1 stack.
- **Rootbed:** On entering battle, grows Overgrown on its own side. Can't be Dazed.
- **Rubble Pile:** While outnumbered, Physical Defense x1.3.
- **Slippery:** Can't be given a status. Rest restores an extra 15% energy.
- **Static Wings:** Electric moves cost 2 less energy.
- **Sturdy:** Foes can't lower its stats.
- **Tidal Heart:** Water moves hit 20% harder.
- **Undertow:** On entering battle, soaks the enemy side. Wild encounters are 20% rarer while it leads.

## Held items

One item per creature, given and taken back on the Summary screen. *Use*: *Permanent* items stay held; *Consumed* items are used up the first time they fire; *Per battle* items fire once each battle. *Scope*: *Self* items' effects apply only to their holder; *Aura* items apply their effects to every active creature on the holder's side (the same item does not stack). Triggers read as for [Passives](#passives), and run after the holder's passive. *Overworld* effects apply while the holder leads the party (first in the party, fainted or not). A `when` condition is shown in brackets.

| Item | Id | Price | Use | Scope | Effects | Triggers | Overworld |
|---|---|---|---|---|---|---|---|
| **Guard Banner** | `guard_banner` | 800 | Permanent | Aura | All damage taken x0.9 | — | — |
| **Oran Berry** | `oran_berry` | 200 | Consumed | Self | — | On being hit [HP below 50%]: Heals 25% max HP → self | — |
| **Rough Bark** | `rough_bark` | 500 | Per battle | Self | — | On being hit (physical): P.Atk -1 → attacker | — |
| **Scout Lens** | `scout_lens` | 350 | Permanent | Self | — | — | Wild encounter rate x0.9 |
| **Tide Charm** | `tide_charm` | 400 | Permanent | Self | Water moves x1.1 | — | — |

- **Guard Banner:** Allies on the field take 10% less damage.
- **Oran Berry:** Eaten when hurt below half HP: heals a quarter. One use.
- **Rough Bark:** First physical hit each battle lowers the attacker's Phys. Attack.
- **Scout Lens:** Wild encounters are 10% rarer while it leads.
- **Tide Charm:** Water moves hit 10% harder.

## Moves

Grouped by type. Physical moves use P.Atk vs P.Def; special moves use S.Atk vs S.Def. *Cost* is energy spent (some passives lower it). *Pri* is turn-order priority: higher acts first, then the faster creature. Moves that hit more than one creature deal less to each; turn order, energy and the multi-target table are in [Rules and Balance](#rules-and-balance). Effects run top to bottom; `bonus_if_field` modifiers apply to the damage or heal after them. **Scrap** is always available, even without energy.

### Dark moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Dusk Pulse** | `dusk_pulse` | Special | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A ripple of cold shadow.* | Blazefox |
| **Shadow Claw** | `shadow_claw` | Physical | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A slash from the darkness.* | — |
| **Shroud** | `shroud` | Status | — | 4 | — | 0 | Enemy side | Applies Shrouded to the enemy side<br>*Smothers the enemy side in shadow.* | — |

### Earth moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Dust Sweep** | `dust_sweep` | Status | — | 3 | — | 0 | Own side | Clears all states from own side<br>*Clears every state from your own side.* | Pebblet |
| **Pebble Toss** | `pebble_toss` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage | Pebblet |
| **Quake Stomp** | `quake_stomp` | Physical | 70 | 9 | 100% | 0 | Everyone | Damage<br>*Shakes the whole field, allies included.* | Pebblet, Thornwall, Torrentusk |

### Electric moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Arc Pair** | `arc_pair` | Special | 44 | 5 | 100% | 0 | Two foes | Damage; Inflicts Shock (10%)<br>*Lightning arcs between two foes of your choice.* | Voltmoth |
| **Spark Bite** | `spark_bite` | Physical | 45 | 3 | 100% | 0 | One enemy | Damage; Inflicts Shock (15%) | Voltmoth |
| **Spark Volley** | `spark_volley` | Special | 16 | 6 | 100% | 0 | One enemy | Hits 2-5 times; Damage; Inflicts Shock (10%)<br>*A rapid burst of sparks that may shock.* | Voltmoth |
| **Static Field** | `static_field` | Status | — | 4 | — | 0 | Enemy side | Applies Charged to the enemy side<br>*Charges the air over the enemy side.* | Voltmoth |
| **Thunder Cascade** | `thunder_cascade` | Special | 50 | 7 | 90% | 0 | All enemies | x1.4 if the target's side is Charged; Damage | Voltmoth |

### Fire moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Crossfire** | `crossfire` | Special | 44 | 4 | 100% | 0 | Two foes | Damage<br>*Flames lash two foes of your choice.* | Blazefox, Emberkit |
| **Ember Flick** | `ember_flick` | Special | 40 | 2 | 100% | 0 | One enemy | Damage; Inflicts Burn (10%) | Blazefox, Cinderwisp, Emberkit |
| **Flare Burst** | `flare_burst` | Special | 45 | 7 | 90% | 0 | All enemies | x1.6 if the target's side is Scorched (consumes it); Damage<br>*Hits every foe; far stronger on a Scorched side.* | Blazefox, Emberkit |
| **Scorch Field** | `scorch_field` | Status | — | 4 | — | 0 | Enemy side | Applies Scorched to the enemy side<br>*Sets the enemy side smouldering.* | Cinderwisp, Emberkit |

### Ghost moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Haunt** | `haunt` | Status | — | 4 | — | 0 | Enemy side | Applies Haunted to the enemy side<br>*Calls restless spirits onto the enemy side.* | Cinderwisp, Mossweaver |
| **Spirit Touch** | `spirit_touch` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A chilling touch from beyond.* | — |
| **Wail** | `wail` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A mournful cry that rattles the soul.* | Cinderwisp, Mossweaver |

### Grass moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Regrowth** | `regrowth` | Status | — | 6 | — | 0 | Self | x1.5 if own side is Overgrown; Heals 20% max HP<br>*Heals; heals more on your own Overgrown side.* | Sprigling, Thornwall |
| **Seed Carpet** | `seed_carpet` | Status | — | 4 | — | 0 | Enemy side | Applies Overgrown to the enemy side<br>*Grows a thicket on the enemy side.* | Mossweaver, Sprigling |
| **Twin Lash** | `twin_lash` | Physical | 42 | 4 | 100% | 0 | Two foes | Damage<br>*Two vines strike two foes of your choice.* | Sprigling |
| **Vine Lash** | `vine_lash` | Physical | 45 | 3 | 100% | 0 | One enemy | Damage | Mossweaver, Sprigling, Thornwall |

### Ice moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Frost Nip** | `frost_nip` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage; Inflicts Chill (20%) | Frostling |
| **Glacier Crash** | `glacier_crash` | Physical | 80 | 9 | 85% | 0 | One enemy | Damage | Frostling, Mistcoil |
| **Needle Flurry** | `needle_flurry` | Physical | 20 | 5 | 95% | 0 | One enemy | Hits 3 times; Damage<br>*Three needles of ice.* | Frostling |
| **Rime Veil** | `rime_veil` | Status | — | 4 | — | 0 | Enemy side | Applies Frosted to the enemy side<br>*Coats the enemy side in frost.* | Frostling, Mistcoil |

### Iron moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Iron Bash** | `iron_bash` | Physical | 50 | 4 | 95% | 0 | One enemy | Damage<br>*A heavy, armoured slam.* | — |
| **Magnet Pulse** | `magnet_pulse` | Special | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A wave of magnetic force.* | — |
| **Magnetize** | `magnetize` | Status | — | 4 | — | 0 | Enemy side | Applies Magnetized to the enemy side<br>*Scatters iron filings across the enemy side.* | — |

### Light moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Flash Strike** | `flash_strike` | Physical | 40 | 2 | 100% | +1 | One enemy | Damage<br>*A strike quick as a flash of light.* | — |
| **Light Beam** | `light_beam` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A focused beam of radiance.* | — |
| **Radiance** | `radiance` | Status | — | 4 | — | 0 | Own side | Applies Radiant to own side<br>*Bathes your own side in warm light.* | — |

### Magic moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Enchant** | `enchant` | Status | — | 4 | — | 0 | Own side | Applies Enchanted to own side<br>*Draws protective runes around your own side.* | — |
| **Hex Bolt** | `hex_bolt` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A crackling bolt of raw arcana.* | — |
| **Rune Strike** | `rune_strike` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A blow carried by a glowing rune.* | — |

### Mental moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Focus Palm** | `focus_palm` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A strike guided by total concentration.* | — |
| **Mind Spike** | `mind_spike` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*A piercing psychic jolt.* | — |
| **Psychic Haze** | `psychic_haze` | Status | — | 4 | — | 0 | Enemy side | Applies Hazed to the enemy side<br>*Fills the enemy side with a dulling psychic fog.* | — |

### Neutral moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Brace** | `brace` | Status | — | 3 | — | 0 | Self | P.Def +1; S.Def +1<br>*Raises Physical and Special Defense.* | Pebblet, Thornwall |
| **Scrap** | `scrap` | Physical | 25 | 0 | 100% | 0 | One enemy | Damage<br>*A desperate, free flail. Always available, even with no energy.* | Everyone (fallback) |
| **Tackle** | `tackle` | Physical | 40 | 1 | 100% | 0 | One enemy | Damage | Emberkit, Tidepup |
| **Taunting Howl** | `taunting_howl` | Status | — | 3 | 100% | 0 | All enemies | P.Atk -1<br>*Lowers every foe's Physical Attack.* | Tidepup |

### Virtual moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Byte** | `byte` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage<br>*A quick, glitching snap.* | — |
| **Data Burst** | `data_burst` | Special | 50 | 4 | 100% | 0 | One enemy | Damage<br>*Floods the target with a blast of raw data.* | — |
| **Digitize** | `digitize` | Status | — | 4 | — | 0 | Enemy side | Applies Glitched to the enemy side<br>*Converts the enemy's field to a digital entity.* | — |

### Water moves

| Move | Id | Cat. | Power | Cost | Acc | Pri | Target | Effects | Learned by |
|---|---|---|---|---|---|---|---|---|---|
| **Drench** | `drench` | Status | — | 4 | — | 0 | Enemy side | Applies Soaked to the enemy side<br>*Floods the enemy side.* | Mistcoil, Tidepup |
| **Riptide** | `riptide` | Physical | 55 | 6 | 95% | 0 | One enemy | x1.5 if the target's side is Soaked (consumes it); Damage<br>*Stronger on a Soaked side, draining the water.* | Tidepup, Torrentusk |
| **Splash Jab** | `splash_jab` | Physical | 40 | 2 | 100% | 0 | One enemy | Damage | Tidepup, Torrentusk |
| **Tide Beam** | `tide_beam` | Special | 55 | 6 | 100% | 0 | One enemy | Damage<br>*A focused jet of water.* | Mistcoil, Tidepup |
| **Twin Splash** | `twin_splash` | Special | 28 | 5 | 100% | 0 | One enemy | Hits 2 times; Damage<br>*Two quick jets of water.* | Tidepup |

## Items

Bag items, used from the bag in battle or on the field. Held items are listed under [Held items](#held-items).

| Item | Id | Category | Price | Target | Effects | Description |
|---|---|---|---|---|---|---|
| **Clear Tonic** | `clear_tonic` | Heal | 200 | One ally | Cures any status | Cures a creature's status condition. |
| **Lure Cage** | `lure_cage` | Capture | 100 | One enemy | Capture x1 | A plain woven cage. Works anywhere. |
| **Reset Seed** | `reset_seed` | Training | 600 | One ally | Returns all spent training points (field use only) | Returns all of a creature's training points so they can be spent again. |
| **Salve** | `salve` | Heal | 150 | One ally | Heals 33% max HP | Restores a third of a creature's HP. |
| **Snare Vine** | `snare_vine` | Capture | 250 | One enemy | Capture x0.8, x2.5 on Overgrown | Far more effective on an Overgrown side. |
| **Tide Net** | `tide_net` | Capture | 250 | One enemy | Capture x0.8, x2.5 on Soaked | Far more effective on a Soaked side. |
| **Tonic** | `tonic` | Heal | 150 | One ally | Restores 50% max energy | Restores half of a creature's energy. |

## Creatures

Base stats. *Total* sums the six battle stats (HP to Spd); Luck, Resolve and Stamina are listed separately. A **Growth** line lists any stat that grows faster or slower than steady (tier multipliers in [Rules and Balance](#rules-and-balance)); 10 of 12 species have one. *Lv 99 stats* are untrained, with each stat's growth tier applied.

| Creature | Types | HP | P.Atk | P.Def | S.Atk | S.Def | Spd | Luck | Resolve | Stamina | Total | Catch | XP |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [Blazefox](#blazefox) | Fire | 55 | 50 | 45 | 90 | 55 | 95 | 60 | 45 | 55 | 390 | 10% | 160 |
| [Cinderwisp](#cinderwisp) | Fire / Ghost | 60 | 40 | 50 | 75 | 80 | 70 | 65 | 60 | 65 | 375 | 10% | 160 |
| [Emberkit](#emberkit) | Fire | 45 | 45 | 40 | 60 | 45 | 60 | 55 | 40 | 50 | 295 | 45% | 55 |
| [Frostling](#frostling) | Ice | 50 | 50 | 50 | 45 | 55 | 45 | 50 | 55 | 50 | 295 | 40% | 55 |
| [Mistcoil](#mistcoil) | Water / Ice | 70 | 45 | 55 | 80 | 70 | 80 | 55 | 55 | 60 | 400 | 10% | 160 |
| [Mossweaver](#mossweaver) | Grass / Ghost | 65 | 45 | 55 | 75 | 80 | 60 | 65 | 70 | 55 | 380 | 10% | 160 |
| [Pebblet](#pebblet) | Earth | 60 | 55 | 75 | 30 | 45 | 25 | 40 | 70 | 60 | 290 | 50% | 50 |
| [Sprigling](#sprigling) | Grass | 55 | 45 | 55 | 40 | 60 | 35 | 45 | 60 | 55 | 290 | 50% | 50 |
| [Thornwall](#thornwall) | Grass / Earth | 80 | 65 | 80 | 40 | 85 | 30 | 45 | 75 | 70 | 380 | 10% | 160 |
| [Tidepup](#tidepup) | Water | 50 | 45 | 45 | 50 | 45 | 50 | 50 | 45 | 55 | 285 | 40% | 60 |
| [Torrentusk](#torrentusk) | Water / Earth | 75 | 85 | 70 | 45 | 55 | 55 | 45 | 65 | 70 | 385 | 10% | 160 |
| [Voltmoth](#voltmoth) | Electric | 40 | 40 | 35 | 60 | 40 | 75 | 60 | 40 | 45 | 290 | 40% | 55 |

### Blazefox

`blazefox` · Fire

*Its tail trails sparks faster than the eye can follow.*

- **Base stats:** HP 55 · P.Atk 50 · P.Def 45 · S.Atk 90 · S.Def 55 · Spd 95 · Luck 60 · Resolve 45 · Stamina 55
- **Catch rate:** 10% base · **XP yield:** 160
- **Growth:** P.Def slow, S.Atk fast, Spd fast, Resolve slow
- **Lv 99 stats:** HP 217 · P.Atk 104 · P.Def 76 · S.Atk 218 · S.Def 113 · Spd 230 · Luck 123 · Resolve 76 · Stamina 128 · Total 958
- **Found:** Not found in the wild
- **Grows from:** Emberkit (Lv 16, Striker Affinity), Emberkit (Lv 16, default)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Ember Flick | Fire | Special | 40 | 2 | 100% |
| 1 | Crossfire | Fire | Special | 44 | 4 | 100% |
| 1 | Flare Burst | Fire | Special | 45 | 7 | 90% |
| 16 | Dusk Pulse | Dark | Special | 40 | 2 | 100% |

### Cinderwisp

`cinderwisp` · Fire / Ghost

*A restless flame that haunts the tall grass after dusk.*

- **Base stats:** HP 60 · P.Atk 40 · P.Def 50 · S.Atk 75 · S.Def 80 · Spd 70 · Luck 65 · Resolve 60 · Stamina 65
- **Catch rate:** 10% base · **XP yield:** 160
- **Growth:** P.Atk slow, P.Def slow, S.Atk fast, S.Def fast
- **Lv 99 stats:** HP 227 · P.Atk 68 · P.Def 84 · S.Atk 183 · S.Def 195 · Spd 143 · Luck 133 · Resolve 123 · Stamina 148 · Total 900
- **Found:** Not found in the wild
- **Grows from:** Emberkit (Lv 16, Catalyst Affinity)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Ember Flick | Fire | Special | 40 | 2 | 100% |
| 1 | Scorch Field | Fire | Status | — | 4 | — |
| 1 | Haunt | Ghost | Status | — | 4 | — |
| 16 | Wail | Ghost | Special | 50 | 4 | 100% |

### Emberkit

`emberkit` · Fire

*Leaves smouldering pawprints wherever it runs.*

- **Base stats:** HP 45 · P.Atk 45 · P.Def 40 · S.Atk 60 · S.Def 45 · Spd 60 · Luck 55 · Resolve 40 · Stamina 50
- **Catch rate:** 45% base · **XP yield:** 55
- **Growth:** P.Def slow, S.Atk fast, Spd fast, Resolve slow
- **Lv 99 stats:** HP 198 · P.Atk 94 · P.Def 68 · S.Atk 147 · S.Def 94 · Spd 147 · Luck 113 · Resolve 68 · Stamina 119 · Total 748
- **Found:** Not found in the wild
- **Grows into:** Lv 16 → **Blazefox** (Striker Affinity); Lv 16 → **Cinderwisp** (Catalyst Affinity); Lv 16 → **Blazefox** (default)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Tackle | Neutral | Physical | 40 | 1 | 100% |
| 1 | Ember Flick | Fire | Special | 40 | 2 | 100% |
| 6 | Scorch Field | Fire | Status | — | 4 | — |
| 9 | Crossfire | Fire | Special | 44 | 4 | 100% |
| 11 | Flare Burst | Fire | Special | 45 | 7 | 90% |

### Frostling

`frostling` · Ice

*A shy spirit that frosts the ground when startled.*

- **Base stats:** HP 50 · P.Atk 50 · P.Def 50 · S.Atk 45 · S.Def 55 · Spd 45 · Luck 50 · Resolve 55 · Stamina 50
- **Catch rate:** 40% base · **XP yield:** 55
- **Lv 99 stats:** HP 208 · P.Atk 104 · P.Def 104 · S.Atk 94 · S.Def 113 · Spd 94 · Luck 104 · Resolve 113 · Stamina 119 · Total 717
- **Found:** Route 1 – Route 1 tall grass, Lv 5–7; Route 1 – Route 1 deep grass, Lv 5–8

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Frost Nip | Ice | Physical | 40 | 2 | 100% |
| 6 | Rime Veil | Ice | Status | — | 4 | — |
| 10 | Needle Flurry | Ice | Physical | 20 | 5 | 95% |
| 14 | Glacier Crash | Ice | Physical | 80 | 9 | 85% |

### Mistcoil

`mistcoil` · Water / Ice

*A serpent of fog that turns battlefields into marshes.*

- **Base stats:** HP 70 · P.Atk 45 · P.Def 55 · S.Atk 80 · S.Def 70 · Spd 80 · Luck 55 · Resolve 55 · Stamina 60
- **Catch rate:** 10% base · **XP yield:** 160
- **Growth:** P.Atk slow, P.Def slow, S.Atk fast, Spd fast
- **Lv 99 stats:** HP 247 · P.Atk 76 · P.Def 92 · S.Atk 195 · S.Def 143 · Spd 195 · Luck 113 · Resolve 113 · Stamina 138 · Total 948
- **Found:** Not found in the wild
- **Grows from:** Tidepup (Lv 16, Catalyst Affinity)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Tide Beam | Water | Special | 55 | 6 | 100% |
| 1 | Drench | Water | Status | — | 4 | — |
| 1 | Rime Veil | Ice | Status | — | 4 | — |
| 16 | Glacier Crash | Ice | Physical | 80 | 9 | 85% |

### Mossweaver

`mossweaver` · Grass / Ghost

*Weaves moss into traps and waits for foes to trip.*

- **Base stats:** HP 65 · P.Atk 45 · P.Def 55 · S.Atk 75 · S.Def 80 · Spd 60 · Luck 65 · Resolve 70 · Stamina 55
- **Catch rate:** 10% base · **XP yield:** 160
- **Growth:** P.Atk slow, P.Def slow, S.Atk fast, S.Def fast
- **Lv 99 stats:** HP 237 · P.Atk 76 · P.Def 92 · S.Atk 183 · S.Def 195 · Spd 123 · Luck 133 · Resolve 143 · Stamina 128 · Total 906
- **Found:** Not found in the wild
- **Grows from:** Sprigling (Lv 16, Trickster Affinity)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Vine Lash | Grass | Physical | 45 | 3 | 100% |
| 1 | Seed Carpet | Grass | Status | — | 4 | — |
| 1 | Haunt | Ghost | Status | — | 4 | — |
| 16 | Wail | Ghost | Special | 50 | 4 | 100% |

### Pebblet

`pebblet` · Earth

*Mistaken for a rock until it headbutts your shin.*

- **Base stats:** HP 60 · P.Atk 55 · P.Def 75 · S.Atk 30 · S.Def 45 · Spd 25 · Luck 40 · Resolve 70 · Stamina 60
- **Catch rate:** 50% base · **XP yield:** 50
- **Growth:** P.Def fast, S.Atk slow, Spd slow, Resolve fast
- **Lv 99 stats:** HP 227 · P.Atk 113 · P.Def 183 · S.Atk 52 · S.Def 94 · Spd 44 · Luck 84 · Resolve 171 · Stamina 138 · Total 713
- **Found:** Route 1 – Route 1 tall grass, Lv 3–6; Route 1 – Route 1 deep grass, Lv 5–8

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Pebble Toss | Earth | Physical | 40 | 2 | 100% |
| 1 | Brace | Neutral | Status | — | 3 | — |
| 7 | Dust Sweep | Earth | Status | — | 3 | — |
| 13 | Quake Stomp | Earth | Physical | 70 | 9 | 100% |

### Sprigling

`sprigling` · Grass

*A sprout that plants seeds in every footprint.*

- **Base stats:** HP 55 · P.Atk 45 · P.Def 55 · S.Atk 40 · S.Def 60 · Spd 35 · Luck 45 · Resolve 60 · Stamina 55
- **Catch rate:** 50% base · **XP yield:** 50
- **Growth:** S.Atk slow, S.Def fast, Spd slow, Resolve fast
- **Lv 99 stats:** HP 217 · P.Atk 94 · P.Def 113 · S.Atk 68 · S.Def 147 · Spd 60 · Luck 94 · Resolve 147 · Stamina 128 · Total 699
- **Found:** Not found in the wild
- **Grows into:** Lv 16 → **Thornwall** (Warden Affinity); Lv 16 → **Mossweaver** (Trickster Affinity); Lv 16 → **Thornwall** (default)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Vine Lash | Grass | Physical | 45 | 3 | 100% |
| 4 | Seed Carpet | Grass | Status | — | 4 | — |
| 8 | Regrowth | Grass | Status | — | 6 | — |
| 10 | Twin Lash | Grass | Physical | 42 | 4 | 100% |

### Thornwall

`thornwall` · Grass / Earth

*Grows a hedge of thorns around anything it decides to guard.*

- **Base stats:** HP 80 · P.Atk 65 · P.Def 80 · S.Atk 40 · S.Def 85 · Spd 30 · Luck 45 · Resolve 75 · Stamina 70
- **Catch rate:** 10% base · **XP yield:** 160
- **Growth:** HP fast, S.Atk slow, S.Def fast, Spd slow
- **Lv 99 stats:** HP 299 · P.Atk 133 · P.Def 163 · S.Atk 68 · S.Def 206 · Spd 52 · Luck 94 · Resolve 153 · Stamina 158 · Total 921
- **Found:** Not found in the wild
- **Grows from:** Sprigling (Lv 16, Warden Affinity), Sprigling (Lv 16, default)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Vine Lash | Grass | Physical | 45 | 3 | 100% |
| 1 | Regrowth | Grass | Status | — | 6 | — |
| 1 | Brace | Neutral | Status | — | 3 | — |
| 16 | Quake Stomp | Earth | Physical | 70 | 9 | 100% |

### Tidepup

`tidepup` · Water

*A pup that splashes puddles into its foes' paths.*

- **Base stats:** HP 50 · P.Atk 45 · P.Def 45 · S.Atk 50 · S.Def 45 · Spd 50 · Luck 50 · Resolve 45 · Stamina 55
- **Catch rate:** 40% base · **XP yield:** 60
- **Lv 99 stats:** HP 208 · P.Atk 94 · P.Def 94 · S.Atk 104 · S.Def 94 · Spd 104 · Luck 104 · Resolve 94 · Stamina 128 · Total 698
- **Found:** Not found in the wild
- **Grows into:** Lv 16 → **Torrentusk** (Striker Affinity); Lv 16 → **Mistcoil** (Catalyst Affinity); Lv 16 → **Torrentusk** (default)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Tackle | Neutral | Physical | 40 | 1 | 100% |
| 1 | Splash Jab | Water | Physical | 40 | 2 | 100% |
| 5 | Drench | Water | Status | — | 4 | — |
| 9 | Riptide | Water | Physical | 55 | 6 | 95% |
| 12 | Taunting Howl | Neutral | Status | — | 3 | 100% |
| 14 | Tide Beam | Water | Special | 55 | 6 | 100% |
| 15 | Twin Splash | Water | Special | 28 | 5 | 100% |

### Torrentusk

`torrentusk` · Water / Earth

*Grew up charging through floods, tusks first.*

- **Base stats:** HP 75 · P.Atk 85 · P.Def 70 · S.Atk 45 · S.Def 55 · Spd 55 · Luck 45 · Resolve 65 · Stamina 70
- **Catch rate:** 10% base · **XP yield:** 160
- **Growth:** HP fast, P.Atk fast, S.Atk slow, Luck slow
- **Lv 99 stats:** HP 287 · P.Atk 206 · P.Def 143 · S.Atk 76 · S.Def 113 · Spd 113 · Luck 76 · Resolve 133 · Stamina 158 · Total 938
- **Found:** Not found in the wild
- **Grows from:** Tidepup (Lv 16, Striker Affinity), Tidepup (Lv 16, default)

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Splash Jab | Water | Physical | 40 | 2 | 100% |
| 1 | Riptide | Water | Physical | 55 | 6 | 95% |
| 16 | Quake Stomp | Earth | Physical | 70 | 9 | 100% |

### Voltmoth

`voltmoth` · Electric

*Its wingbeats leave the air prickling with static.*

- **Base stats:** HP 40 · P.Atk 40 · P.Def 35 · S.Atk 60 · S.Def 40 · Spd 75 · Luck 60 · Resolve 40 · Stamina 45
- **Catch rate:** 40% base · **XP yield:** 55
- **Growth:** P.Atk slow, P.Def slow, S.Atk fast, Spd fast
- **Lv 99 stats:** HP 188 · P.Atk 68 · P.Def 60 · S.Atk 147 · S.Def 84 · Spd 183 · Luck 123 · Resolve 84 · Stamina 109 · Total 730
- **Found:** Route 1 – Route 1 tall grass, Lv 3–6; Route 1 – Route 1 deep grass, Lv 5–8

| Lv | Move | Type | Cat. | Power | Cost | Acc |
|---|---|---|---|---|---|---|
| 1 | Spark Bite | Electric | Physical | 45 | 3 | 100% |
| 5 | Static Field | Electric | Status | — | 4 | — |
| 9 | Arc Pair | Electric | Special | 44 | 5 | 100% |
| 12 | Thunder Cascade | Electric | Special | 50 | 7 | 90% |
| 15 | Spark Volley | Electric | Special | 16 | 6 | 100% |

## Tamers

NPC opponents. *Max active* is how many creatures they field at once.

### Hiker Tom

`hiker_tom` · Max active **1** · AI `basic` · Reward 250

| Creature | Lv | Moves |
|---|---|---|
| Pebblet | 6 | Pebble Toss, Brace *(latest learnset)* |
| Sprigling | 6 | Vine Lash, Seed Carpet *(latest learnset)* |

### Rival

`rival_01` · Max active **2** · AI `tactician` · Reward 500

| Creature | Lv | Moves |
|---|---|---|
| Voltmoth | 7 | Spark Bite, Static Field |
| Frostling | 7 | Frost Nip, Rime Veil *(latest learnset)* |

**Items:** Salve x1

### Rival

`rival_lab` · Max active **1** · AI `basic` · Reward 100

| Creature | Lv | Moves |
|---|---|---|
| Sprigling | 5 | Vine Lash, Seed Carpet *(latest learnset)* |

### Scout Ana

`scout_ana` · Max active **1** · AI `basic` · Reward 200

| Creature | Lv | Moves |
|---|---|---|
| Sprigling | 5 | Vine Lash, Seed Carpet *(latest learnset)* |
| Emberkit | 6 | Tackle, Ember Flick, Scorch Field *(latest learnset)* |

## Encounters

Wild encounter tables. Chance is per creature in the pack.

### Route 1 deep grass

`route_01_deep_grass` · Pack size 1–2

| Creature | Chance | Levels |
|---|---|---|
| Frostling | 40% | 5–8 |
| Voltmoth | 30% | 5–8 |
| Pebblet | 30% | 5–8 |

### Route 1 tall grass

`route_01_grass` · Pack size 1–2

| Creature | Chance | Levels |
|---|---|---|
| Voltmoth | 50% | 3–6 |
| Pebblet | 37.5% | 3–6 |
| Frostling | 12.5% | 5–7 |

## Achievements

Unlocked by play and shown in the Achievements screen. A hidden one reads "???" there until it is earned.

| Achievement | Id | Needs |
|---|---|---|
| **First Steps** | `first_steps` | 500 steps |
| **First Victory** | `first_victory` | 1 battles won |
| **Tamer Trouncer** | `tamer_trouncer` | 1 tamers defeated |
| **First Catch** | `first_catch` | 1 creatures caught |
| **Field Notes** | `field_notes` | 4 species seen |
| **Collector** | `collector` | every species caught |
| **First Evolution** | `first_evolution` | 1 creature(s) evolved |
| **Rising Star** | `rising_star` | a creature at level 20 |
| **Close Friends** | `close_friends` | a creature at Bond 80 |
| **Big Spender** | `big_spender` | 1000 money earned |
| **Quick on the Draw** (hidden) | `quick_on_the_draw` | story flag `quick_draw_won` |
