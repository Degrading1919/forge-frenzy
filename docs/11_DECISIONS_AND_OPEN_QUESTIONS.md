# Design decision log and unresolved questions

**As of October 7, 2026.** This is a record of design conversation, not an implementation changelog. Make references to statuses explicit.

## Locked or expressly affirmed

1. **Project isolation:** Forge Frenzy is a new Roblox game, not Adventurer's Rise.
2. **Game direction:** blacksmithing-first incremental game; factory **supplies materials for personal forging**, not an independent tycoon as main attraction.
3. **Controlled RNG:** player selects weapon class and metal; RNG rolls craftsmanship, rarity, visual design and traits.
4. **Economic definition:** material controls output's **potential selling-price band**, not a universally fixed rarity.
5. **Click-luck minigame:** clicking performance drives luck up to **5x**; ordinary manual result roughly **2.5x**; free autoclicker **1.5x**; premium autoclicker **4x**. Manual can exceed premium.
6. **Material quantity:** target many materials, working **32 across eight eras**.
7. **Asset efficiency:** standard weapons use same meshes retextured/recolored across metals; Legendary/Mythic merit dedicated distinctive assets.
8. **Material unlocking:** advance extractor levels, then select any previously unlocked material to output; **no separate mine per metal**.
9. **Upgrade structure:** meaningful forge/machine upgrades and some type of personal gear/pet.
10. **Monetization direction:** Robux purchases should be attractive and powerful but never necessary to make the free game playable.
11. **Long-term systems:** add evolution/rebirth and visible leaderboards.
12. **Development approach:** Claude Desktop project/thread orchestrator, use Roblox Studio tooling, Tripo3D, trustworthy third-party plugins and open-source reuse to accelerate a concentrated build session.

## Planned design selections (approved direction, mechanics to be finalized)

- Mine/extractor, smelter, storage, furnace, anvil and possibly separate quench upgrades.
- Gear: hammer, gloves, blacksmith apron.
- Forge Companions with production bonuses; small egg system; free hatching and paid multi-egg convenience; some premium companions guaranteed directly.
- Sell versus keep/physically display weapons; rare discoveries are a social status signal.
- Seven premium categories: Auto Forge; Multi-Forge; Companions/hatching; Collection magnet; Evolution protection; VIP machines/workshop; Limited editions, plus optional starter pack.
- Four board metrics: lifetime wealth, weapons forged, evolutions, highest-valued weapon.
- Normal rebirth resets certain temporary state; paid protected path preserves some of it, with anti-infinite-rebirth requirements.

## Open or expressly illustrative

- Economy: rates, output quantities, unit costs, price bands for all 32 metals, upgrade costs and balance curve.
- Forge math: exact click window, clicks-per-second→luck mapping, diminishing returns, accessibility and input security.
- RNG math: baseline probabilities, exactly how luck modifies odds, trait eligibility, legendary/mythic asset selection, final value formula, disclosure presentation.
- Whether player class choice influences material required/time/sale values beyond identity.
- Counts of owned/equipped pets, pet catalogs, number of egg tiers, hatch odds and multi-hatch pricing.
- Whether multi-forging outputs each receive 4x premium auto luck; how that interacts with throughput/economy.
- Machine model counts, upgrade tiers, final benefits and whether quench station is standalone.
- Exact manual-vs-auto progression pacing and how/when full automation is allowed.
- Evolution title, reset inventory, eligibility milestones, bonuses, price of protection and progression cap.
- VIP physical area layout, bonus stacking/caps, premium bundle contents and specific product prices.
- Specific art direction, workshop plot size, world layout, UI mockups, Tripo asset budget, audio direction.
- Production readiness, Roblox place file location, Studio MCP installation, library selection, hosting/publishing and engagement analytics.
- Anti-paywall and paid-random compliance decisions under current policies, especially premium luck and paid eggs.

## Known earlier examples not to treat as facts

- Baseline rarity split **65/23/9/2.5/0.45/0.05%** (Common→Mythic).
- Crude/Standard/Fine/Masterwork/Perfect value multipliers **0.6/1/1.5/2.5/5**.
- Illustrative Iron→Celestial values; Celestial used as an example category, not an ore in the 32-name list.
- **5 weapon classes × 3 common meshes** = 15 standard models; ~10 special unique models.
- Starting with 2 equipped pets, earning a 3rd.
- Example first evolution **500 forges and $1M lifetime sales; +50% production and +10% forge speed**.
- Example product prices **79–499 Robux** and example extractor/dragon bonuses.
- Full forging animation initial duration **8–12 seconds**.

## Important design tension to resolve before economy implementation

**Free manual luck versus paid Auto Forge:** 4x paid automatic luck will beat most manual players. This is deliberate monetization direction, but must remain fair for free users and comply with paid randomized outcome rules. Evaluate time and attempt throughput, not just the multiplier.

**Multi-Forge versus principal interaction:** letting players roll multiple weapons at once can weaken the blacksmithing fantasy. Treat as bonus output/production alongside a satisfying primary forging animation, not turning the whole game into a passive UI.

**Evolution protection versus economic inflation:** retained cash and machines can trivially allow recursive evolution. Use fresh milestone gates and make rewards worthwhile for regular free resets.

**Huge content count versus one-session development:** prefer registries/material skins/effects to bespoke implementation. Finish one beautiful, tested forge loop before filling every menu with placeholder content.
