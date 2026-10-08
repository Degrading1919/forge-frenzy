# Playtest balance v0 — numerical starting assumptions

**Status: PROPOSED FOR PROTOTYPE.** This file and [design/balance-v0.json](../design/balance-v0.json) are implementation-ready *starting values*, **not owner-approved final balancing**. We are converting design intent into a reversible first playtest. Do not label these new numbers LOCKED.

## Experience targets

| Time | Desired experience |
|---|---|
| 0–30 seconds | First weapon created, result revealed, sale obvious |
| 2–5 minutes | First meaningful machine upgrade and new material in sight |
| 10–20 minutes | Multiple materials, a visible upgraded machine and first companion |
| 25–45 minutes | First evolution should become plausible through active play |
| 1 hour | Workshop visibly different, some rare gallery pieces, new progression goals |
| Subsequent sessions | Multiple material eras, true rare hunting, social competition and evolutions |

These are playtest targets, not guarantees. Track median **free** time-to-unlock separately from paid user performance. A completed first-hour path is more important than balance perfection on day one.

## Material value bands: 32 candidate tiers

A simple monotonically increasing candidate economy: `minPrice(t) = round(12 × 1.78^(t−1))`, `maxPrice(t) = 18 × minPrice(t)`. Material sets the absolute output price band. All classes use the same range initially so visual class preference doesn't create a strictly optimal money-farming choice. Five weapon classes and all named metals are in the configuration.

Unlocking material `t>1` via extractor tier costs approximately `[10+2(t−2)] × expected selling value of material (t−1) at 2.5x manual luck`. These costs are concrete in the JSON, with a rarity-only expected-value approximation; recalibrate using full roll Monte Carlo and actual throughput. Machine output speed/capacity requires separate upgrades so unlocking alone does not resolve every bottleneck.

| Tier | Material | Min sale | Max sale | Extractor unlock price |
|---:|---|---:|---:|---:|
| 1 | Copper | 12 | 216 | 0 |
| 2 | Tin | 21 | 378 | 414 |
| 3 | Bronze | 38 | 684 | 870 |
| 4 | Iron | 68 | 1,224 | 1,836 |
| 5 | Steel | 120 | 2,160 | 3,754 |
| 6 | Silver | 214 | 3,852 | 7,451 |
| 7 | Gold | 382 | 6,876 | 14,764 |
| 8 | Platinum | 679 | 12,222 | 28,990 |
| 9 | Cobalt | 1,209 | 21,762 | 56,213 |
| 10 | Titanium | 2,153 | 38,754 | 108,432 |
| 11 | Tungsten | 3,832 | 68,976 | 207,949 |
| 12 | Osmium | 6,820 | 122,760 | 396,554 |
| 13 | Moonsteel | 12,140 | 218,520 | 752,817 |
| 14 | Mithril | 21,609 | 388,962 | 1,423,811 |
| 15 | Runite | 38,465 | 692,370 | 2,683,440 |
| 16 | Adamantite | 68,467 | 1,232,406 | 5,042,013 |
| 17 | Emberite | 121,871 | 2,193,678 | 9,447,043 |
| 18 | Frostsilver | 216,931 | 3,904,758 | 17,656,485 |
| 19 | Stormium | 386,137 | 6,950,466 | 32,925,235 |
| 20 | Obsidian | 687,324 | 12,371,832 | 61,270,839 |
| 21 | Bloodiron | 1,223,436 | 22,021,848 | 113,803,947 |
| 22 | Soulsteel | 2,177,716 | 39,198,888 | 211,011,360 |
| 23 | Starsteel | 3,876,335 | 69,774,030 | 390,624,215 |
| 24 | Voidmetal | 6,899,876 | 124,197,768 | 722,053,933 |
| 25 | Sunmetal | 12,281,780 | 221,072,040 | 1,332,858,017 |
| 26 | Lunarite | 21,861,568 | 393,508,224 | 2,457,219,103 |
| 27 | Astralite | 38,913,591 | 700,444,638 | 4,524,672,333 |
| 28 | Etherium | 69,266,191 | 1,246,791,438 | 8,322,380,636 |
| 29 | Chronosteel | 123,293,821 | 2,219,288,778 | 15,291,703,042 |
| 30 | Nebulium | 219,463,001 | 3,950,334,018 | 28,069,832,629 |
| 31 | Aetherglass | 390,644,141 | 7,031,594,538 | 51,478,371,750 |
| 32 | Primordium | 695,346,571 | 12,516,238,278 | 94,326,545,693 |

The longest-term tier values are large; test Roblox numeric precision, OrderedDataStore ordering and currency abbreviations. Do not switch to an arbitrary BigNum library unless needed; protect integer/safe arithmetic and plan leaderboard scaling if amounts ever approach 2^53.

## Forging: one minigame, directly testable multiplier

- Manual hammering: **6-second timed strike window**, proposed `luck = clamp(1 + 0.30 × validatedClicksPerSecond, 1, 5)`.
- 5 valid clicks/sec = **2.5x**, 10 clicks/sec = **4.0x**, ~13.34 clicks/sec = **5.0x**.
- Free auto: **1.5x**; premium auto: **4.0x**, regardless of synthetic/autoclick scripts used elsewhere.
- Starting heat prep: **2 seconds**; quench/reveal: **1.5 seconds**. One early forge roughly **9.5 seconds** in manual mode, plus UI/loading. Time and click targets are for accessibility testing; avoid pushing players into painful rapid input over long sessions.
- Authoritative server validates time window, event replay, rate cap and forge eligibility. Do not blindly trust a client-reported CPS or luck multiplier. Exploit prevention can't distinguish all human tapping from external macros; enforce a firm 5x ceiling instead.
- Alternative input/accommodation for mobile/controller and free auto mode are essential. The default UX should not shame players for using free auto.

## Proposed exact base odds; luck affects *rarity only* at first

To simplify transparency and preserve controlled RNG, v0 luck multiplies the probabilities of **Rare, Epic, Legendary and Mythic**, leaves Uncommon unchanged, and takes the remaining probability from Common. All probabilities are percentages. Formula stays valid and nonnegative through 5x luck.

| Rarity | 1x | 1.5x free auto | 2.5x typical | 4x premium auto | 5x maximum |
|---|---:|---:|---:|---:|---:|
| Common | 65.045% | 59.067% | 47.112% | 29.180% | 17.225% |
| Uncommon | 23.000% | 23.000% | 23.000% | 23.000% | 23.000% |
| Rare | 9.000% | 13.500% | 22.500% | 36.000% | 45.000% |
| Epic | 2.500% | 3.750% | 6.250% | 10.000% | 12.500% |
| Legendary | 0.450% | 0.675% | 1.125% | 1.800% | 2.250% |
| Mythic | 0.0050% | 0.0075% | 0.0125% | 0.0200% | 0.0250% |

For arbitrary luck between these values, calculate the formula, rather than rounding/normalizing already rounded display values. Show rounded percentages to users only with a disclosure interface that handles rounding responsibly and shows the exact numerically calculated total.

Craftsmanship v0 base odds (separate from luck): Crude **24%**, Standard **42%**, Fine **24%**, Masterwork **9%**, Perfect **1%**. Trait odds conditioned on rarity: Common **2%**, Uncommon **4%**, Rare **8%**, Epic **15%**, Legendary **30%**, Mythic **50%**. The selected visual design is a uniform random choice among eligible variants for the class and rarity, unless collectible balancing later changes it. Traits do not affect combat because combat isn't part of the game.

**Paid-random requirement:** paid 4x luck is an odds modifier even if material comes from play. Build server-derived, user-specific *actual final outcome odds*, policy gates and dynamic disclosures before offering a paid modifier. Actual per-item odds can require joint design/quality/trait calculations and must not be implied solely by this rarity table. See [Roblox paid random item policy](https://create.roblox.com/docs/production/monetization/paid-random-items).

## Price calculation (candidate, not just a blanket rarity multiplier)

`position = clamp(rarityBandPosition + craftsmanshipOffset + (trait ? 0.025 : 0) + random(-0.01,0.01), 0.01, 0.99)`.

`value = round(minPrice + position × (maxPrice − minPrice))`.

Rarity band positions: Common 0.05, Uncommon 0.12, Rare 0.25, Epic 0.45, Legendary 0.75, Mythic 0.95. Quality offsets: Crude −0.02, Standard −0.01, Fine 0, Masterwork +0.025, Perfect +0.05. Clamp final sale value within that material's explicit min/max band **after all adjustments**. This means a Legendary of any metal is a strongly valuable result **within that metal**, and a Perfect Common can still differ meaningfully from a Crude Common. All outputs store the actual rolled value once, never reroll on viewing.

The result attributes, material band, reroll probability and final sale value must remain consistent. Make reveals satisfying across ordinary results too, not solely Legendary/Mythic.

## Production baseline and machine upgrade priorities

Starting candidate rates: selected highest-tier ore **one raw ore every 6 seconds**, one ingot refined **every 6.5 seconds**, base recipe **one ingot per forge**. A 9.5-second forging cycle is initially the player bottleneck; after shortening heat/reveal or adding multi-forge, output can become the bottleneck. Older metals produce faster on an advanced extractor, by up to **4x**. Cap ingot storage initially at **30**, expandable.

Machine paths in priority order:
1. Extractor tier unlocks ore/material selections (32 data entries grouped into 8 visually evolving chassis families).
2. Extraction rate modules improve ore/sec for selected ore.
3. Refinery speed improves ingots/sec.
4. Storage raises buffer cap and potential offline production window.
5. Furnace level shortens heat preparation.
6. Anvil level reduces non-click downtime or improves forge comfort but does **not** raise the 5x luck cap.
7. Quench stays a **visual phase**, not an independent economy/machine upgrade at launch unless playtests identify a good reason.

**Balance is bound by throughput:** `actualForgesPerMin ≈ min(60 / forgeCycleSeconds × forgeSlots, orePerMin / orePerForge, ingotsPerMin / ingotsPerForge)`. Every forge output pays its own material cost and gets an independent roll; paid multi-forge cannot create free weapons.

Upgrade costs for non-extractor branches are not yet final; initialize each on a separate, visible coin-cost curve tied to current material earnings, then tune based on first-hour simulation. Avoid introducing five independent currencies.

## Pets and gear starter numbers

- **2 equipped companion slots** initially; third earned through normal progression. Hatch **1 free egg per action**; premium multi-hatch supports 3 and 5 where policy allows.
- Typical bonuses include extraction, refining and forge preparation; group same-stat bonuses additively then apply a **3x per-family cap** to avoid runaway stacking. Strong premium companions can be significant within the same cap.
- Gear should be visible: Hammer reduces non-click cycle downtime, Gloves improve material efficiency (but never create negative cost/duplication), Apron improves material storage/utility. All equip/upgrade logic is server-backed.
- Paid VIP/machine output bonuses and pet stat caps must be measured together; premium should win meaningfully on convenience/speed but not become a prerequisite for the next metal.

## Evolution/rebirth prototype

Working name **Blacksmith Evolution**. First eligibility: **150 weapons forged since last evolution** and **material tier 4 achieved**. At current rank `r`, next rank requires `150+50r` freshly forged weapons and `min(32, 4+2r)` highest temporary extractor tier reached since the last evolve (do not allow stored pre-evolve highest-tier history alone to qualify). Expected 25–45 minutes to first evolution is a hypothesis, not proof.

- **Normal evolution resets:** current coins, raw ores, ingots, current extractor capability and other temporary machine levels; starts with usable equipment and a starting ore recipe. It keeps permanent collection/journal, pets, paid entitlements, permanent cosmetics/unlocks, lifetime stats and evolution bonuses.
- **Protected evolution (paid):** retains the normally reset state. Both forms reset since-last-evolution counters and increment rank only once per validated eligibility.
- Proposed permanent evolution rewards: **+15% production per rank** and **+3% preparation speed per rank**; cap/scale later.
- Permanently discovered materials remain in the catalog, but producing higher metals after *normal* reset requires rebuilding temporary extractor capability. Make this distinction clear in UI.
- The ranked gate above must use **fresh extractor progress since last evolution**, even for protected resets; if keeping a high-tier extractor, require a separate tier-equivalent challenge or resettable evolution milestone token so premium users cannot instantly qualify by retained machines. Implement and test a single explicit predicate for both paths.

## Anti-frustration and tuning gates

- Track material-starvation, idle time, forgings/session, first-upgrade time, median free progression and earned-value-per-minute across paid/free paths.
- If a free player lacks material for several consecutive attempts while actively forging, ease supply or costs rather than pushing a store modal.
- If buying a premium auto-forge causes a player to skip the core reveal or stop interacting, preserve a meaningful optional reveal/share/showcase loop.
- Test the full stack with and without premium, failing purchases, reconnection, multi-client concurrency and evolution at high ranks.
