# Core forging and economy: implementation notes

**Status: IMPLEMENTED as plain Luau, verified under Lune; not yet verified in Studio.** Balance numbers remain **PROPOSED** (docs/13, design/balance-v0.json). Built against [docs/16](16_CODE_LAYOUT_AND_CONTRACTS.md); this file records the API as shipped, where it goes beyond that contract, and how to test it.

## Files

| Path | Role |
|---|---|
| `src/shared/Config/Materials.luau` | 32 tiers: economics from balance-v0.json plus skin appearance (`color`, `material`, `accent`, `glow`) |
| `src/shared/Config/Balance.luau` | Forge/luck/odds/payout/production tables, weapon classes and designs, upgrade + gear tracks (`upgradeCost`, `upgradeEffect`, `gearLook`), premium bonus sizes, inventory limits |
| `src/shared/ForgeMath.luau` | Pure luck, strike validation, odds, weapon roll, valuation, disclosure tables, names, coin formatting |
| `src/shared/Economy.luau` | Pure profile rules: template + reconcile, rates, production settle, unlocks, upgrades, forge completion, sell/keep, showcase |
| `src/server/Services/{Data,Production,Forge,Upgrade}Service.luau` | Thin server services over Economy: sessions, timers, events, bonus hooks |
| `src/server/Packages/ProfileStore.luau` | Vendored ProfileStore 1.0.3 (Apache-2.0), see `THIRD_PARTY.md` |
| `src/server/Tests/{ForgeMath,Economy,CoreServices}.spec.luau` | Specs (Studio and Lune) |
| `tools/lune/*` | Lune runner, Roblox shims, balance sync check, pacing simulation |

## Rules as implemented

- **Luck** (server only): manual `clamp(1 + 0.3 × validStrikes / 6, 1, 5)`. A strike counts only inside the strike window (+0.35 s latency grace) and at most 20 per one-second bucket, so floods cap at exactly 5x. Free auto 1.5x, premium auto 4x (needs `MonetizationService.owns(player, "PremiumAutoForge")`). No gear or bonus touches luck.
- **Odds**: Rare/Epic/Legendary/Mythic × luck, Uncommon fixed, Common = remainder; craftsmanship ignores luck; trait chance by rarity. `ForgeMath.oddsTable(luck)` and `outcomeChance(...)` give exact unrounded numbers for disclosure.
- **Value**: `priceMin + clamp(band + qualityOffset + trait 0.025 + jitter ±0.01, 0.01, 0.99) × (priceMax − priceMin)`, rounded and clamped to the band. Stored once on the weapon (`v`), never recomputed.
- **Designs**: Common–Epic pick uniformly from 3 standard designs per class (one mesh family, material skin); Legendary and Mythic pick from that class's dedicated designs (1 each now = 10 dedicated models).
- **Production**: one selected ore at a time; ore every 6 s, ingot every 6.5 s; older materials up to 4x faster on a higher extractor (1.15 per tier behind); ore and ingot buffers share one cap (30 + upgrades); a full buffer stalls its stage and banks no progress. Offline time settles on join, capped at 4 h. The smelter takes the selected material's ore first, then the highest tier.
- **Forge cycle**: heat 2 s → window 6 s → roll → reveal 1.5 s. Furnace, Anvil and Hammer shorten heat/reveal (capped at −75%); companion/evolution/premium `prep` divides heat. Material is checked at start and spent at the roll, so abandoned sessions cost nothing and nothing needs refunding. Gloves give a chance to keep the ingot (never extra ingots).
- **Bonuses**: `ProductionService.bonuses(player)` sums `CompanionService.bonuses`, `EvolutionService.bonuses` (`production` → extract and smelt) and `Balance.premiumBonuses[key]` for owned keys. Each family (extract, smelt, prep, storage) is capped at 3x in total. Missing services count as zero.
- **Pending results**: each completed forge sets `profile.pending`; a still-pending older result is auto-kept first. Starting a forge requires room for both, so auto-keep never overflows the 250-weapon cap.

## Service API (beyond docs/16)

All functions return `(ok, resultOrErrorCode)` unless noted. Error codes: `NotLoaded, InvalidMode, NotOwned, Busy, InvalidMaterial, InvalidClass, NoMaterial, InventoryFull, MaterialLocked, MaxTier, NotEnoughCoins, InvalidTrack, MaxLevel, NothingPending, InvalidAction, InvalidRequest, NothingSold, UnknownWeapon, ShowcaseFull, NoSession`.

- **ForgeService**: `start(player, classIndex, materialIndex, mode)` per contract; called with no player (Main's lifecycle `start()`) it is a no-op, and `ForgeService.begin` is the same function without the name clash. `strike(player, sessionId) -> (counted, validCount)`; `resolve(player, "sell"|"keep")`; `stopAuto(player)`; plus `sellWeapons(player, {ids})` (skips showcased/unknown/duplicate ids), `toggleShowcase(player, id)`, `odds(mode) -> OddsTable`, `session(player)`. Events: `completed (player, weapon, luck)`, `stopped (player, reason)` when an auto loop ends (`Stopped`, `NoMaterial`, `InventoryFull`, `NotOwned`, ...).
- **ProductionService**: `selectMaterial`, `unlockNextMaterial`, `rates` per contract, plus `bonuses(player)`, `settleOffline(player)`, `tickPlayer(player, dt)`, event `materialUnlocked (player, index)`.
- **UpgradeService**: `buy(player, track)`, `list(player) -> { {track, name, kind, level, maxLevel, cost?, look?} }`, event `upgraded (player, track, level)`.
- **DataService**: `get`, `waitFor`, `markDirty`, `profileChanged` per contract, plus `update(player, fn)`, `profileLoaded`, and `registerDefaults({ field = default })` so other services add their profile fields without editing the template. Falls back to in-memory profiles if ProfileStore cannot load; ProfileStore itself uses its mock store in Studio without API access.

## Profile fields owned here

`schemaVersion, coins, lifetimeCoins, weaponsForged, weaponsSold, highestWeaponValue, selectedMaterial, unlockedTier, ore[32], ingots[32], progress {ore, smelt}, levels {track}, gear {track}, weapons {[id]=Weapon}, pending, showcase {id ≤ 6}, journal[32] (rarity bitmask per material), nextWeaponId, lastSeen`.

Per-material arrays are always dense length-32 arrays (DataStores reject sparse arrays); `Economy.reconcile` repairs them on every load. Weapon ids are `"w" .. nextWeaponId`, unique per player.

**For the evolution thread:** count `forgedSinceEvolve` from `ForgeService.completed` and track `highestTierSinceEvolve` from `ProductionService.materialUnlocked`. A normal evolve resets `coins, ore, ingots, progress, unlockedTier (→1), selectedMaterial (→1), levels`; keep `gear, weapons, showcase, journal` and lifetime counters unless the decision log says otherwise.

## Verification

Run from the repo root with [Lune](https://lune-org.github.io) 0.10:

```
lune run tools/lune/run-tests.luau            # 40 specs + balance-v0.json sync check
lune run tools/lune/simulate-economy.luau 60  # pacing for 1.5x / 2.5x / 4x / 5x players
```

The Studio thread should also run `src/server/Tests/*.spec.luau` in Studio (they use the real `Random`, `Players` and `BindableEvent`), then playtest save/rejoin with API access on.

## Balance findings from the simulation (PROPOSED numbers, no evolution, no bonuses)

| Profile | Tier at 60 min | First Tin | Steel | All 32 tiers |
|---|---|---|---|---|
| Free auto 1.5x | 10 Titanium | 3.5 min | 16.6 min | not within 4 h (27 Astralite) |
| Manual 2.5x | 11 Tungsten | 3.1 min | 13.4 min | ~3.9 h |
| Paid auto 4x | 13 Moonsteel | 2.8 min | 11.6 min | ~3.2 h |
| Skilled 5x | 14 Mithril | 2.2 min | 11.9 min | ~2.8 h |

- First-hour targets in docs/13 are met for free players (first unlock in ~3 min, several materials by 20 min).
- With the v0 unlock curve a typical free player reaches Primordium in about four hours of play before any evolution; the evolution reset and its fresh-tier gates are what stretch this, so tune them together.
- With base rates the 9.5 s forge cycle, not material supply, is the bottleneck for the whole first hour (no starved cycles). Extractor/smelter upgrades only start to matter once heat/reveal upgrades, multi-forge or auto modes shorten the cycle. Consider slower base extraction or cheaper furnace/anvil levels if machine upgrades feel inert in playtests.
