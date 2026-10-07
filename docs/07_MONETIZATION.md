# Monetization — powerful but not required

## Commercial principle — LOCKED

Encourage Robux purchases for visibly powerful, satisfying upgrades **without making the game unplayable for nonpayers**. Premium upgrades accelerate/convenience and can look spectacular; all ore eras, weapon rarity tiers (including Mythic), manual 5x luck and meaningful pet progression remain reachable free.

Inspiration from Fly to Space: multi-open eggs, special egg, magnet/auto-collect, no-reset rebirth, VIP area, limited-time pets and launch/auto device. Adapt these concepts to blacksmithing; do not copy other games' names, graphics, assets or prices.

## Planned monetization categories (seven)

| Category | Paid value | Free path / restriction |
|---|---|---|
| 1. Premium Auto Forge | Automates attempts at **4x luck** | Free auto mode gives **1.5x**; manual up to **5x** |
| 2. Multi-Forge / throughput | Allows multiple finished weapons per production cycle | One forge at start; possible earned extra slot (under balance review) |
| 3. Companions and hatching | Guaranteed premium companion; optional special eggs; 3x/5x egg opening convenience | Free eggs, useful earned companions and standard opening |
| 4. Collection magnet / sorting | Auto-pickup output, optional configurable auto-sell filters | Manual pickup/sale fully supported |
| 5. Evolution protection | Evolve while preserving defined resettable progress | Normal evolutions unlock same permanent ranks and bonuses |
| 6. VIP workshop and premium machines | Visually outstanding workshops/machines, meaningful output/prep boosts | Every material and rarity tier achievable without VIP |
| 7. Limited editions | Distinctive time-limited companions, cosmetics, hammers and machinery skins | Regular strong items plus obtainable seasonal options |

**Optional starter bundle (additional SKU, not an eighth core system):** affordable starter coins/gear cosmetic/useful companion.

## Earlier working product concepts — not price-locked

- Premium Auto Forge: **399 Robux** (illustrative).
- Titan Excavator: **299 Robux** (illustrative; e.g. roughly double ore output).
- Dragon Furnace: **499 Robux** (illustrative; faster prep and distinctive appearance).
- Golden Forge Dragon: **249 Robux** (illustrative production companion).
- Blacksmith Starter Pack: **79 Robux** (illustrative).
- Exclusive VIP plot / cosmetic machinery and limited-time pets: no final SKU or price.
- Premium multi-hatch / multi-forge, magnet, protected evolve: exact price/limits **OPEN**.

These were idea-stage suggestions, **not user-approved production prices**. Reprice after actual competitor research, economy modeling and playtesting.

## Paid acceleration boundaries

- No Robux-only ore, rarity tier or permanent game-completion gate.
- Paid auto-forge 4x should be potent; skilled manual can exceed it up to 5x.
- No invisible multiplicative stacking that creates accidental 1000x economies; define additive/multiplicative groups, caps and display final rates.
- VIP and limited items must be presented clearly; do not fake scarcity.
- Free players should still earn upgrades at satisfying intervals and have reasons to play actively.
- Items advertised as permanent should remain permanent, including through normal evolution.

## Roblox paid-random-item compliance — MUST CHECK before shipping

Paid luck modifiers, special paid eggs and purchases connected to randomized prizes may trigger Roblox paid-random-item requirements **even if the base forging attempt uses earned materials**. Verify current Creator Hub rules and policy APIs at implementation/release time; determine eligibility per player/region, show accurate numerical outcome probabilities (including modifiers), and provide compliant alternatives where required. Do not assume cash-earned rolls are exempt if paid modifiers affect their odds.

Use approved Roblox purchase APIs and validate receipts/idempotency server-side; never trust client 'purchase succeeded'. Separate permanent passes, repeatable products, consumables, and limited-time entitlements according to Roblox's current platform support.

Monetization balancing and final rollout **require owner approval**. No test implementation should execute real Robux purchases or publish live commercial content without permission.
