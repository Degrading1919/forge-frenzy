# Forging, luck and weapon generation

## Controlled RNG contract — LOCKED

The player **chooses weapon class and material** before forging. RNG determines:
- **Craftsmanship / quality** (how well made).
- **Rarity** (prestige / exceptionalness).
- **Design variant** (from approved assets).
- **Special trait(s)** (visual/value identity, possibly none).

The rolled result is persisted as a concrete owned weapon record, not recomputed from a new random seed whenever viewed. Server is authoritative for material consumption, all RNG, reward values, inventory writes and economics.

## Material controls price potential — LOCKED

Each material defines a **minimum and maximum potential selling price**. Luck and roll outcomes change where results fall inside that range. Weapon type defines identity/silhouette; it must not silently erase the material-defined economic ceiling. Price can be generated from weighted quality/rarity/trait rolls and normalized/clamped into the material's range. The exact math is **OPEN**; do not simply multiply a weapon's final price by the luck multiplier or allow a cheap material to trivially invalidate higher tiers.

An exceptional early Iron weapon can be impressive within Iron's limits; advanced material tiers open significantly higher value bands. Keep older materials useful for faster, lower-cost attempts and completing collections.

## Forge minigame — LOCKED direction, thresholds OPEN

A **short click/tap-to-hammer minigame** is the primary forging action. Click speed/performance earns **1x–5x luck** for *that roll*, not a direct 1x–5x selling-price multiplier.

Explicit player targets:
- Most ordinary manual players: approximately **2.5x** luck.
- Exceptional manual performance: up to **5x**.
- **Free basic autoclicker: 1.5x** automatic luck.
- **Paid premium autoclicker: 4x** automatic luck.

Automatic modes perform forging without requiring rapid input; 4x is intended to be especially attractive to paid players, but free manual play can reach the 5x ceiling. Potential external macros are a reality; server-side rate limits, bounded action windows and validation are required. Do not claim perfect autoclicker detection.

Practical implementation **PROPOSED**: short heat-up, timed strike window with animation/sound/sparks, then quench/reveal. Forge equipment may shorten preparation or provide ergonomics/forgiveness. Calibrate mobile, keyboard, mouse, controller and accessibility support through real playtesting. Avoid a mandatory physically punishing click challenge; the free auto option is important.

**Economics:** luck increases outcome quality/rarity/trait probabilities as appropriate, with transparent, testable distributions. A 5x luck boost is *not* necessarily 5x the probability of every rare item; define and disclose its actual mathematical behavior.

## Craftsmanship — PROPOSED taxonomy

Crude, Standard, Fine, Masterwork, Perfect. Earlier illustrative value multipliers were 0.6x, 1x, 1.5x, 2.5x and 5x respectively; **these are NOT locked production values** and must be normalized against material value bounds.

## Rarity — PROPOSED taxonomy and sample odds

Common, Uncommon, Rare, Epic, Legendary, Mythic. A previously illustrated *baseline-only* distribution:

| Rarity | Sample baseline chance |
|---|---:|
| Common | 65% |
| Uncommon | 23% |
| Rare | 9% |
| Epic | 2.5% |
| Legendary | 0.45% |
| Mythic | 0.05% |

**Important:** these were illustrations, not approved real odds. Actual odds with luck/machines/gear/paid modifiers must be designed, audited for economy and disclosed as required by Roblox policy.

**Visual asset rule — LOCKED:** Common through Epic reuse standard weapon models with per-material colors/textures/material properties and appropriate effects. **Legendary and Mythic get dedicated exceptional assets**; may reuse those dedicated meshes across metals with skins. Do not create a unique mesh for every weapon × material × rarity combination.

## Weapon families and variations — PROPOSED content counts

Five initial classes: Sword, Greatsword, Axe, Dagger, Hammer. Example standard content target: 3 designs per class = **15 common-to-Epic base meshes**. Approximately ten dedicated Legendary/Mythic models is a preliminary asset budget, **not confirmed**. The selected class/metal must be visually understandable.

Sample traits: Infernal, Frozen, Stormforged, Radiant, plus no trait. Traits should be visually distinctive and affect sell value/collection identity, not pretend to grant combat stats in a game without combat.

## Weapon lifecycle — PLANNED

Forging creates persistent item ID, owner, material ID, class, quality, rarity, design ID, traits, rolled sell value and created timestamp. Player selects **sell** or **retain/display**. A record-best and collection journal can refer to the stored result. Selling must be transactional/idempotent to prevent dupes. Item model representation can be regenerated from saved IDs/properties.

## Forge reveal — PLANNED

Heat/glowing blank → strikes and sparks → quench/steam → rarity-tier-specific card and actual 3D weapon showcase. Big Legendary/Mythic moments should be visually unique and occasional, not perpetual loud notifications. Aim for short satisfying attempts, faster with progression. Earlier 8–12 sec attempt estimate was illustrative, not final.
