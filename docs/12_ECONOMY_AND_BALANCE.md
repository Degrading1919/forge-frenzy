# Economy and progression balancing plan

**All numbers below are targets or calculations to test, not final game balance.** Avoid tuning only for monetization; fun and free progression come first.

## Economy flow

Earn materials per elapsed time; spend selected usable ore to complete forging. Roll a weapon with sale price inside selected material's price band; sell to get coins; spend on extraction, refining, furnace/anvil, storage, gear, companion hatches and upgrades. Collect rather than sell the exceptional items. Evolution grants permanent advantages, usually resetting selected temporary progress.

### Key dimensions to tune

| Variable | Question |
|---|---|
| Ore produced per second | Does material generation keep up with active forging? |
| Refining throughput | Does smelting create a meaningful and understandable bottleneck? |
| Material cost per weapon | How many attempts are possible after collecting for one minute? |
| Weapon min/max sale value | Is each new ore era exciting without making all older ores irrelevant? |
| Forge cycle duration | Is manual interaction short and fun? |
| Manual performance distribution | Is ~2.5x achievable for typical desktop and phone players? |
| Premium/auto output | Does 1.5x free auto help accessibility? Does paid 4x feel powerful but safe? |
| Unlock/upgrade cost | Can players afford the next improvement on a predictable but satisfying timescale? |
| Evolution bonus | Does a free reset visibly accelerate recovery? |
| Buff stacking | Can premium machines/pets accidentally compound into unstoppable inflation? |

## Calculation principles

- **Material bands:** weapon sale payout stays within a metal's advertised potential range after integrating quality, rarity, visual design and traits.
- **Luck:** modifies the *probability distribution* of exceptional outcomes, not final price directly. At 1.5/2.5/4/5 luck, probability table can differ; normalize to 100% and ensure no invalid negatives.
- **Effective forge throughput:** attempts/minute = min(material supply / material cost, personal forging speed × parallel slot effects). Avoid treating more extractors as value if the forge is the true bottleneck.
- **Expected coins per minute:** attempts/minute × expected sale payout (adjust for % of kept items and other economic uses).
- **Expected rarity acquisition time:** if per-attempt rare chance p and attempts per minute a, expected attempts ≈ 1/p, expected minutes ≈ 1/(a·p) for independent identical rolls. Use tail-percentile simulations, not only averages.
- **Offline production:** cap by storage and rate; no uncapped inflation or free bypass of crafting.

## Progression feel targets — PROPOSED

- **First 30 seconds:** player learns choose ore/weapon, performs first forge and sees a value.
- **First 5 minutes:** multiple attempts, first meaningful extractor/forge upgrade and clear rare reveal anticipation.
- **First 30 minutes:** several tiers of upgrading, a new ore type, first companion/egg interaction, a showcase-worthy item.
- **First hour:** obvious character/workshop transformation, a longer-term material/evolution target and active forging still rewarding.
- **Returning session:** visible stockpile and enough available material to forge again; no paid wall.

Actual tier timings should be based on creator playtests and analytics, not locked as hard targets.

## Fairness experiments

Play through with:
1. **Entirely free, active manual:** target typical ~2.5x luck.
2. **Entirely free, auto:** 1.5x convenience and slower progression.
3. **Skilled manual:** near 5x, but watch for physically unhealthy click targets and cross-device disparity.
4. **Paid auto:** 4x luck but no access to forbidden materials/rarities.
5. **Premium stack:** pet + furnace + extractor + multi-forge + evolution protection to expose runaway multiplier combinations.

Use deterministic seeds and thousands of simulated forge attempts to evaluate return distributions; do not promise exact player outcomes or imply purchasable RNG guarantees. Revisit paid-random odds display each time formula changes.

## Long-term economy health

Prestige/rebirth is intended to reset temporary state and grant compounding permanent bonuses without infinite immediate rebirth. Lifetime wealth is based on earned sales rather than pay-to-win balance transfers. Keep item resale values bounded and all transactions idempotent. Periodic material rebalancing should avoid arbitrarily devaluing players' existing memorable items.
