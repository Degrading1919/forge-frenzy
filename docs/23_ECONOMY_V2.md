# Economy v2: curve and pacing evidence

Recorded October 8, 2026. This is **simulation evidence, not a human playtest.** It replaces the several-hour curve in docs/20 (see docs/21 §6).

## Reproduce

```powershell
.local/bin/lune-0.10.5/lune.exe run tools/lune/print-curve.luau
.local/bin/lune-0.10.5/lune.exe run tools/lune/simulate-v2.luau free 900 1
.local/bin/lune-0.10.5/lune.exe run tools/lune/simulate-v2.luau premium 900 1
.local/bin/lune-0.10.5/lune.exe run tools/lune/simulate-v2.luau manual 900 1
```

`simulate-v2.luau` runs the real `Economy`, `ForgeMath`, `CompanionService.Logic` and `EvolutionService.Logic`. It simulates an attentive player who:

- buys the next metal as soon as it is affordable;
- builds production pads costing at most half the next metal;
- buys upgrades costing at most 8% of the next metal;
- hatches the newest egg with up to 15% of lifetime cash, then merges and equips its best pets;
- re-picks forge recipes to match ingot supply;
- displays its best weapons, sells the rest at the booth and collects display cash;
- evolves as soon as it is eligible.

Walking, menus and reveals are not modelled, so a real player will be somewhat slower than these numbers.

## How the curve is built

All values are generated in `Config/Materials.luau` from a few parameters instead of being typed by hand:

- **Per-ingot price band.** Copper's minimum is $20. The value ratio between tiers rises from 2.1x (Tin) to 3.0x (Primordium). The band maximum is 18 × the minimum.
- **Unlock prices.** `previous priceMin × 12 × (tier − 1)^3.66`, with a ramp that discounts the first unlocks to 55% at Bronze, rising to full price by Platinum. Early unlocks take seconds to minutes; late ones take tens of hours.
- **Weapon values.** A weapon is worth `band position × class multiplier × evolution cash multiplier` (rank r gives 1 + 0.5r).
- **Ingot recipes** go up with weapon size: Dagger 1 ingot, Sword 2, Axe 3, Hammer 4, Greatsword 5.
- **Upgrades:**
  - Ore drill and smelter: +15% per level, cost growth 1.42.
  - Storage: +10 per level.
  - Heat and cooling: −0.1 s per level.
  - Gear: permanent, cost growth 9.
- **Pads and eggs** are priced as fractions of the relevant material's unlock price, so they stay meaningful at every stage.
- **Evolution:**
  - Requires 120 + 60r forges and unlocking metal min(32, 6 + 2r) since the last evolution.
  - Grants +50% cash and +10% production per rank.
  - Rank 13's requirement is the final metal itself.

Sample values without the evolution multiplier:

| Metal | Unlock | Avg Dagger (free auto) | Avg Greatsword (free auto) | Best possible |
|---|---|---|---|---|
| Copper | free | $67 | $282 | $1.80K |
| Tin | $132 | $142 | $594 | $3.78K |
| Iron | $38.3K | $656 | $2.73K | $17.4K |
| Gold | $7.23M | $7.16K | $29.8K | $190K |
| Adamantite | $534B | $18.8M | $78.6M | $500M |
| Primordium | $77.4Qi | $228T | $951T | $6.05Qa |

These are multiplied by up to x7 at evolution rank 13, so a perfect Primordium Greatsword can pass $40Qa. Exact figures come from `print-curve.luau`.

## Results (900 h cap)

| Scenario | Seed | Final metal reached | Evolutions | Tin | Bronze | Iron | Steel | Silver | Gold |
|---|---|---|---|---|---|---|---|---|---|
| Free auto | 1 | **493.9 h** | 13 | 0.2 m | 2.2 m | 9.9 m | 25.1 m | 52.2 m | 1.8 h |
| Free auto | 2 | **496.4 h** | 13 | 0.2 m | 1.8 m | 8.8 m | 24.2 m | 50.1 m | 1.7 h |
| Free auto | 3 | **496.0 h** | 13 | 0.2 m | 2.1 m | 9.6 m | 24.6 m | 51.4 m | 1.7 h |
| Manual forge 1 + free auto | 1 | 530.9 h | 13 | 0.2 m | 2.1 m | 10.9 m | 26.8 m | 54.9 m | 1.8 h |
| Premium (4x auto, Multi-Forge, Titan, VIP, Dragon Furnace) | 1 | 161.6 h | 13 | 0.1 m | 1.1 m | 5.4 m | 11.1 m | 19.8 m | 37.6 m |

Free seed 1 milestones:

- **First evolution:** 52 m.
- **Later evolutions:** 2.9 h, 5.9 h, 11 h, 19 h, 32 h, 51 h, 76 h, 111 h, 161 h, 222 h, 301 h and 381 h.
- **Pads:**

| Pad | Built at |
|---|---|
| Podiums | 0.2 m |
| Forge #2 | 2.6 m |
| Ore Line #2 | 19 m |
| More podiums | 39 m |
| Forge #3 | 2.4 h |
| Ore Line #3 | 5.3 h |
| Last podiums | 10.1 h |

**Readout:**

- The opening is fast: four metals and a second forge in the first 10 minutes, the first evolution inside an hour.
- The middle stretches to hours per metal.
- The last metals take 70–110 h each, giving roughly 500 h of free automated play to Primordium.
- Premium is about 3x faster but not required.
- Display income (6% of value per minute, capped to the current tier) is part of the simulated economy; raising it from 1.2% moved the free result by about 4%, after which the unlock exponent was retuned.

**Human checks still needed:** the real time spent walking, reading and in menus; whether 10–25 minute waits in the second hour feel good; and how much players hold weapons on display versus selling them.
